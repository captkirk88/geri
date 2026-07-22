package graphics

import asset "../asset"
import log "../logging"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:cgltf"
import wgpu "vendor:wgpu"

SkinnedSubMesh :: struct {
	mesh:         Mesh,
	texture:      wgpu.Texture,
	tex_view:     wgpu.TextureView,
	fallback_tex: wgpu.Texture,
	uniform_buf:  wgpu.Buffer,
	bind_group:   wgpu.BindGroup,
}

Gltf_Render_Config :: struct {
	exclude_nodes: []string,
}

update_gltf_animation :: proc(data: ^cgltf.data, time_elapsed: f32) {
	if data == nil || len(data.animations) == 0 do return

	for anim in data.animations {
		for channel in anim.channels {
			node := channel.target_node
			sampler := channel.sampler
			if node == nil || sampler == nil do continue

			input := sampler.input
			output := sampler.output
			if input.count == 0 || output.count == 0 do return

			times := make([]f32, input.count, context.temp_allocator)
			if cgltf.accessor_unpack_floats(input, ([^]f32)(raw_data(times)), uint(len(times))) !=
			   uint(len(times)) {
				node_name := string(node.name) if node.name != nil else "unnamed"
				panic(fmt.tprintf("Failed to unpack GLTF animation times for node: %s", node_name))
			}

			total_duration := times[len(times) - 1]
			t := time_elapsed
			if total_duration > 0.0 {
				t = math.mod(time_elapsed, total_duration)
			}

			k0 := 0
			k1 := 0
			for i in 0 ..< len(times) - 1 {
				if t >= times[i] && t <= times[i + 1] {
					k0 = i
					k1 = i + 1
					break
				}
			}

			factor: f32 = 0.0
			if sampler.interpolation != .step {
				t0 := times[k0]
				t1 := times[k1]
				if t1 - t0 > 0.0 {
					factor = (t - t0) / (t1 - t0)
				}
			}

			if channel.target_path == .rotation {
				q0: [4]f32
				q1: [4]f32
				if !cgltf.accessor_read_float(output, uint(k0), ([^]f32)(&q0[0]), 4) ||
				   !cgltf.accessor_read_float(output, uint(k1), ([^]f32)(&q1[0]), 4) {
					node_name := string(node.name) if node.name != nil else "unnamed"
					panic(
						fmt.tprintf(
							"Failed to read GLTF animation rotation keyframe for node: %s",
							node_name,
						),
					)
				}

				quat0 := transmute(linalg.Quaternionf32)q0
				quat1 := transmute(linalg.Quaternionf32)q1

				quat_out := linalg.quaternion_slerp(quat0, quat1, factor)
				node.rotation = transmute([4]f32)quat_out
				node.has_rotation = true
			} else if channel.target_path == .translation {
				v0: [3]f32
				v1: [3]f32
				if !cgltf.accessor_read_float(output, uint(k0), ([^]f32)(&v0[0]), 3) ||
				   !cgltf.accessor_read_float(output, uint(k1), ([^]f32)(&v1[0]), 3) {
					node_name := string(node.name) if node.name != nil else "unnamed"
					panic(
						fmt.tprintf(
							"Failed to read GLTF animation translation keyframe for node: %s",
							node_name,
						),
					)
				}

				v_out := linalg.lerp(
					linalg.Vector3f32{v0[0], v0[1], v0[2]},
					linalg.Vector3f32{v1[0], v1[1], v1[2]},
					factor,
				)
				node.translation = {v_out.x, v_out.y, v_out.z}
				node.has_translation = true
			} else if channel.target_path == .scale {
				v0: [3]f32
				v1: [3]f32
				if !cgltf.accessor_read_float(output, uint(k0), ([^]f32)(&v0[0]), 3) ||
				   !cgltf.accessor_read_float(output, uint(k1), ([^]f32)(&v1[0]), 3) {
					node_name := string(node.name) if node.name != nil else "unnamed"
					panic(
						fmt.tprintf(
							"Failed to read GLTF animation scale keyframe for node: %s",
							node_name,
						),
					)
				}

				v_out := linalg.lerp(
					linalg.Vector3f32{v0[0], v0[1], v0[2]},
					linalg.Vector3f32{v1[0], v1[1], v1[2]},
					factor,
				)
				node.scale = {v_out.x, v_out.y, v_out.z}
				node.has_scale = true
			}
		}
	}
}

collect_gltf_lights :: proc(
	model: ^asset.Gltf_Data,
	n: ^cgltf.node,
	model_m4: linalg.Matrix4f32,
	lights: ^[dynamic]Pbr_Light,
) {
	if n == nil do return

	mat: [16]f32
	cgltf.node_transform_world(n, ([^]f32)(&mat[0]))
	node_m4 := transmute(linalg.Matrix4f32)mat
	combined_model := model_m4 * node_m4

	if n.light != nil {
		light_pos := combined_model * [4]f32{0, 0, 0, 1}
		pbr_light := Pbr_Light {
			position  = light_pos.xyz,
			intensity = n.light.intensity,
			color     = n.light.color,
			radius    = n.light.range,
		}
		append(lights, pbr_light)
	}

	for child in n.children {
		collect_gltf_lights(model, child, model_m4, lights)
	}
}

draw_gltf_node :: proc(
	batch: ^Batch3D,
	model: ^asset.Gltf_Data,
	n: ^cgltf.node,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
	textures: []asset.Asset_Entry(wgpu.Texture),
	config: Gltf_Render_Config = {},
) {
	if n == nil || model == nil || model.raw_data == nil do return
	if n.name != nil {
		name_str := string(n.name)
		for ex in config.exclude_nodes {
			if name_str == ex do return
		}
	}
	data := model.raw_data

	mat: [16]f32
	cgltf.node_transform_world(n, ([^]f32)(&mat[0]))
	node_m4 := transmute(linalg.Matrix4f32)mat

	combined_model := model_m4 * node_m4
	mvp := vp * combined_model

	if n.mesh != nil {
		for &prim in n.mesh.primitives {
			pos_attr: ^cgltf.attribute = nil
			uv_attr: ^cgltf.attribute = nil
			normal_attr: ^cgltf.attribute = nil
			for &attr in prim.attributes {
				if attr.type == .position {
					pos_attr = &attr
				} else if attr.type == .texcoord && attr.index == 0 {
					uv_attr = &attr
				} else if attr.type == .normal {
					normal_attr = &attr
				}
			}
			if pos_attr == nil do continue

			// Resolve texture if available
			tex_handle: wgpu.Texture = nil
			if prim.material != nil && prim.material.has_pbr_metallic_roughness {
				base_tex := prim.material.pbr_metallic_roughness.base_color_texture
				if base_tex.texture != nil && base_tex.texture.image_ != nil {
					uri := base_tex.texture.image_.uri
					if uri != nil {
						uri_str := string(uri)
						if asset_id, found := model.textures[uri_str]; found {
							for &tex_entry in textures {
								if tex_entry.id.id.value == asset_id.id.value {
									tex_handle = tex_entry.asset
									break
								}
							}
						}
					}
				}
			}

			base_idx := u32(len(batch.vertices))
			accessor := pos_attr.data
			count := accessor.count

			pos_buffer := make([]f32, count * 3, context.temp_allocator)
			if cgltf.accessor_unpack_floats(
				   accessor,
				   ([^]f32)(raw_data(pos_buffer)),
				   uint(len(pos_buffer)),
			   ) !=
			   uint(len(pos_buffer)) {
				node_name := string(n.name) if n.name != nil else "unnamed"
				acc_name := string(accessor.name) if accessor.name != nil else "unnamed"
				panic(
					fmt.tprintf(
						"Failed to unpack GLTF positions for accessor: %s in node: %s",
						acc_name,
						node_name,
					),
				)
			}

			uv_buffer: []f32 = nil
			if uv_attr != nil {
				uv_accessor := uv_attr.data
				uv_buffer = make([]f32, count * 2, context.temp_allocator)
				unpacked := cgltf.accessor_unpack_floats(
					uv_accessor,
					([^]f32)(raw_data(uv_buffer)),
					uint(len(uv_buffer)),
				)
				if unpacked != uint(len(uv_buffer)) {
					uv_buffer = nil
				}
			}

			normal_buffer: []f32 = nil
			if normal_attr != nil {
				normal_accessor := normal_attr.data
				normal_buffer = make([]f32, count * 3, context.temp_allocator)
				unpacked := cgltf.accessor_unpack_floats(
					normal_accessor,
					([^]f32)(raw_data(normal_buffer)),
					uint(len(normal_buffer)),
				)
				if unpacked != uint(len(normal_buffer)) {
					normal_buffer = nil
				}
			}

			for i in 0 ..< count {
				raw_pos := [3]f32{
					pos_buffer[i * 3 + 0],
					pos_buffer[i * 3 + 1],
					pos_buffer[i * 3 + 2],
				}
				world_pos := combined_model * [4]f32{raw_pos.x, raw_pos.y, raw_pos.z, 1.0}

				uv_coord: [2]f32 = {0.0, 0.0}
				if uv_buffer != nil {
					uv_coord = {uv_buffer[i * 2 + 0], uv_buffer[i * 2 + 1]}
				}

				normal_val: [3]f32 = {0.0, 1.0, 0.0}
				if normal_buffer != nil {
					normal_val = {
						normal_buffer[i * 3 + 0],
						normal_buffer[i * 3 + 1],
						normal_buffer[i * 3 + 2],
					}
				}

				v3d := Vertex3D {
					position = world_pos.xyz,
					color    = color,
					uv       = uv_coord,
					normal   = normal_val,
				}
				append(&batch.vertices, v3d)
			}

			start_idx := u32(len(batch.indices))
			if prim.indices != nil {
				idx_accessor := prim.indices
				idx_count := idx_accessor.count
				for i in 0 ..< idx_count {
					idx := u32(cgltf.accessor_read_index(idx_accessor, uint(i)))
					append(&batch.indices, base_idx + idx)
				}
			} else {
				for i in 0 ..< count {
					append(&batch.indices, base_idx + u32(i))
				}
			}

			cmd := Draw_Command {
				index_start = start_idx,
				index_count = u32(len(batch.indices) - int(start_idx)),
				texture     = tex_handle,
			}
			append(&batch.commands, cmd)
		}
	}

	for child in n.children {
		draw_gltf_node(batch, model, child, color, vp, model_m4, use_pbr, textures, config)
	}
}

draw_gltf_model_hierarchical :: proc(
	batch: ^Batch3D,
	model: ^asset.Gltf_Data,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
	textures: []asset.Asset_Entry(wgpu.Texture),
	config: Gltf_Render_Config = {},
) {
	if model == nil || model.raw_data == nil do return
	data := model.raw_data

	if data.scene != nil {
		for n in data.scene.nodes {
			draw_gltf_node(batch, model, n, color, vp, model_m4, use_pbr, textures, config)
		}
	} else {
		for i in 0 ..< len(data.nodes) {
			n := &data.nodes[i]
			if n.parent == nil {
				draw_gltf_node(batch, model, n, color, vp, model_m4, use_pbr, textures, config)
			}
		}
	}
}

build_skinned_submeshes :: proc(
	device: wgpu.Device,
	model: ^asset.Gltf_Data,
	textures: []asset.Asset_Entry(wgpu.Texture),
	bg_layout: wgpu.BindGroupLayout,
) -> []SkinnedSubMesh {
	if model == nil || model.raw_data == nil do return nil
	data := model.raw_data

	submeshes := make([dynamic]SkinnedSubMesh, context.temp_allocator)

	collect_primitives :: proc(
		n: ^cgltf.node,
		model: ^asset.Gltf_Data,
		textures: []asset.Asset_Entry(wgpu.Texture),
		submeshes: ^[dynamic]SkinnedSubMesh,
		device: wgpu.Device,
		bg_layout: wgpu.BindGroupLayout,
	) {
		if n == nil do return
		if n.name != nil && string(n.name) == "Circle" do return

		if n.mesh != nil {
			for &prim in n.mesh.primitives {
				pos_attr: ^cgltf.attribute = nil
				uv_attr: ^cgltf.attribute = nil
				joints_attr: ^cgltf.attribute = nil
				weights_attr: ^cgltf.attribute = nil
				normal_attr: ^cgltf.attribute = nil

				for &attr in prim.attributes {
					if attr.type == .position {
						pos_attr = &attr
					} else if attr.type == .texcoord && attr.index == 0 {
						uv_attr = &attr
					} else if attr.type == .joints && attr.index == 0 {
						joints_attr = &attr
					} else if attr.type == .weights && attr.index == 0 {
						weights_attr = &attr
					} else if attr.type == .normal {
						normal_attr = &attr
					}
				}

				if pos_attr == nil do continue

				accessor := pos_attr.data
				count := accessor.count

				vertices := make([]SkinnedVertex3D, count, context.temp_allocator)
				indices := make([dynamic]u32, context.temp_allocator)

				pos_buffer := make([]f32, count * 3, context.temp_allocator)
				_ = cgltf.accessor_unpack_floats(
					accessor,
					([^]f32)(raw_data(pos_buffer)),
					uint(len(pos_buffer)),
				)

				uv_buffer: []f32 = nil
				if uv_attr != nil {
					uv_accessor := uv_attr.data
					uv_buffer = make([]f32, count * 2, context.temp_allocator)
					_ = cgltf.accessor_unpack_floats(
						uv_accessor,
						([^]f32)(raw_data(uv_buffer)),
						uint(len(uv_buffer)),
					)
				}

				joints_buffer: []f32 = nil
				if joints_attr != nil {
					joints_accessor := joints_attr.data
					joints_buffer = make([]f32, count * 4, context.temp_allocator)
					_ = cgltf.accessor_unpack_floats(
						joints_accessor,
						([^]f32)(raw_data(joints_buffer)),
						uint(len(joints_buffer)),
					)
				}

				weights_buffer: []f32 = nil
				if weights_attr != nil {
					weights_accessor := weights_attr.data
					weights_buffer = make([]f32, count * 4, context.temp_allocator)
					_ = cgltf.accessor_unpack_floats(
						weights_accessor,
						([^]f32)(raw_data(weights_buffer)),
						uint(len(weights_buffer)),
					)
				}

				normal_buffer: []f32 = nil
				if normal_attr != nil {
					normal_accessor := normal_attr.data
					normal_buffer = make([]f32, count * 3, context.temp_allocator)
					unpacked := cgltf.accessor_unpack_floats(
						normal_accessor,
						([^]f32)(raw_data(normal_buffer)),
						uint(len(normal_buffer)),
					)
					if unpacked != uint(len(normal_buffer)) {
						normal_buffer = nil
					}
				}

				is_skinned := joints_attr != nil && weights_attr != nil
				node_m4 := linalg.MATRIX4F32_IDENTITY
				if !is_skinned {
					mat: [16]f32
					cgltf.node_transform_world(n, ([^]f32)(&mat[0]))
					node_m4 = transmute(linalg.Matrix4f32)mat
				}

				color_factor: [4]f32 = {1.0, 1.0, 1.0, 1.0}
				if prim.material != nil && prim.material.has_pbr_metallic_roughness {
					factor := prim.material.pbr_metallic_roughness.base_color_factor
					color_factor = {factor[0], factor[1], factor[2], factor[3]}
				}

				for i in 0 ..< count {
					raw_pos := [3]f32{
						pos_buffer[i * 3 + 0],
						pos_buffer[i * 3 + 1],
						pos_buffer[i * 3 + 2],
					}
					if !is_skinned {
						pos_model := node_m4 * [4]f32{raw_pos.x, raw_pos.y, raw_pos.z, 1.0}
						raw_pos = pos_model.xyz
					}

					uv_coord: [2]f32 = {0.0, 0.0}
					if uv_buffer != nil {
						uv_coord = {uv_buffer[i * 2 + 0], uv_buffer[i * 2 + 1]}
					}

					normal_val: [3]f32 = {0.0, 1.0, 0.0}
					if normal_buffer != nil {
						normal_val = {
							normal_buffer[i * 3 + 0],
							normal_buffer[i * 3 + 1],
							normal_buffer[i * 3 + 2],
						}
					}

					joints_val: [4]f32 = {0.0, 0.0, 0.0, 0.0}
					if joints_buffer != nil {
						joints_val = {
							joints_buffer[i * 4 + 0],
							joints_buffer[i * 4 + 1],
							joints_buffer[i * 4 + 2],
							joints_buffer[i * 4 + 3],
						}
					}

					weights_val: [4]f32 = {1.0, 0.0, 0.0, 0.0}
					if weights_buffer != nil {
						weights_val = {
							weights_buffer[i * 4 + 0],
							weights_buffer[i * 4 + 1],
							weights_buffer[i * 4 + 2],
							weights_buffer[i * 4 + 3],
						}
					}

					vertices[i] = SkinnedVertex3D {
						base = Vertex3D {
							position = raw_pos,
							color    = color_factor,
							uv       = uv_coord,
							normal   = normal_val,
						},
						joints   = joints_val,
						weights  = weights_val,
					}
				}

				if prim.indices != nil {
					idx_accessor := prim.indices
					idx_count := idx_accessor.count
					for i in 0 ..< idx_count {
						idx := u32(cgltf.accessor_read_index(idx_accessor, uint(i)))
						append(&indices, idx)
					}
				} else {
					for i in 0 ..< count {
						append(&indices, u32(i))
					}
				}

				// Resolve texture
				tex_handle: wgpu.Texture = nil
				if prim.material != nil && prim.material.has_pbr_metallic_roughness {
					base_tex := prim.material.pbr_metallic_roughness.base_color_texture
					if base_tex.texture != nil && base_tex.texture.image_ != nil {
						uri := base_tex.texture.image_.uri
						if uri != nil {
							uri_str := string(uri)
							if asset_id, found := model.textures[uri_str]; found {
								for &tex_entry in textures {
									if tex_entry.id.id.value == asset_id.id.value {
										tex_handle = tex_entry.asset
										break
									}
								}
							}
						}
					}
				}

				mesh, created := create_mesh(device, vertices[:], indices[:])
				if created {
					wgpu.QueueWriteBuffer(
						global_render_context.queue,
						mesh.vertex_buffer,
						0,
						raw_data(vertices),
						uint(len(vertices) * size_of(SkinnedVertex3D)),
					)
					wgpu.QueueWriteBuffer(
						global_render_context.queue,
						mesh.index_buffer,
						0,
						raw_data(indices),
						uint(len(indices) * size_of(u32)),
					)

					// Create Uniform Buffer for this submesh
					uniform_size := u64(size_of(Pbr_Uniforms))
					aligned_size := (uniform_size + 15) & ~u64(15)
					buf_desc := wgpu.BufferDescriptor {
						usage = {.Uniform, .CopyDst},
						size  = aligned_size,
					}
					uniform_buf := wgpu.DeviceCreateBuffer(device, &buf_desc)

					// Create Bind Group
					view_to_bind: wgpu.TextureView = nil
					fallback_tex: wgpu.Texture = nil
					if tex_handle != nil {
						view_to_bind = wgpu.TextureCreateView(tex_handle, nil)
					} else {
						fallback_tex, view_to_bind = create_fallback_texture(
							device,
							global_render_context.queue,
						)
					}

					bg_entries := [3]wgpu.BindGroupEntry {
						{binding = 0, buffer = uniform_buf, offset = 0, size = aligned_size},
						{binding = 1, textureView = view_to_bind},
						{binding = 2, sampler = global_render_context.default_sampler},
					}
					bg_desc := wgpu.BindGroupDescriptor {
						layout     = bg_layout,
						entryCount = 3,
						entries    = &bg_entries[0],
					}
					bind_group := wgpu.DeviceCreateBindGroup(device, &bg_desc)

					append(
						submeshes,
						SkinnedSubMesh {
							mesh = mesh,
							texture = tex_handle,
							tex_view = view_to_bind,
							fallback_tex = fallback_tex,
							uniform_buf = uniform_buf,
							bind_group = bind_group,
						},
					)
				}
			}
		}

		for child in n.children {
			collect_primitives(child, model, textures, submeshes, device, bg_layout)
		}
	}

	if data.scene != nil {
		for n in data.scene.nodes {
			collect_primitives(n, model, textures, &submeshes, device, bg_layout)
		}
	} else {
		for i in 0 ..< len(data.nodes) {
			n := &data.nodes[i]
			if n.parent == nil {
				collect_primitives(n, model, textures, &submeshes, device, bg_layout)
			}
		}
	}

	res := make([]SkinnedSubMesh, len(submeshes))
	copy(res, submeshes[:])
	return res
}

draw_skinned_submeshes :: proc(
	batch: ^Batch3D,
	device: wgpu.Device,
	queue: wgpu.Queue,
	model: ^asset.Gltf_Data,
	submeshes: []SkinnedSubMesh,
	base_uniforms: Pbr_Uniforms,
	model_m4: linalg.Matrix4f32,
	pipeline: wgpu.RenderPipeline,
) {
	if model == nil || model.raw_data == nil || len(model.raw_data.skins) == 0 do return

	// Calculate joint matrices
	joint_matrices: [64]linalg.Matrix4f32
	for j in 0 ..< 64 do joint_matrices[j] = linalg.MATRIX4F32_IDENTITY
	num_joints := i32(0)

	skin := &model.raw_data.skins[0]
	num_joints = i32(len(skin.joints))
	if num_joints > 64 do num_joints = 64

	for j in 0 ..< num_joints {
		joint_node := skin.joints[j]
		mat: [16]f32
		cgltf.node_transform_world(joint_node, &mat[0])
		joint_world := transmute(linalg.Matrix4f32)mat

		inv_bind: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY
		if skin.inverse_bind_matrices != nil {
			_ = cgltf.accessor_read_float(
				skin.inverse_bind_matrices,
				uint(j),
				&inv_bind[0][0],
				16,
			)
		}

		joint_matrices[j] = joint_world * inv_bind
	}

	// Render each submesh
	for &submesh in submeshes {
		sub_uniforms := base_uniforms
		sub_uniforms.model = model_m4
		sub_uniforms.num_joints = num_joints > 0 ? 64 : 0
		sub_uniforms.joint_matrices = joint_matrices

		// Upload uniforms to submesh uniform buffer
		wgpu.QueueWriteBuffer(
			queue,
			submesh.uniform_buf,
			0,
			&sub_uniforms,
			size_of(Pbr_Uniforms),
		)

		// Queue draw command
		cmd := Draw_Command {
			index_start = 0,
			index_count = submesh.mesh.index_count,
			texture     = submesh.texture,
			mesh        = &submesh.mesh,
			bind_group  = submesh.bind_group,
			pipeline    = pipeline,
		}
		append(&batch.commands, cmd)
	}
}
