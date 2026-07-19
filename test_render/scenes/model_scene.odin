package scenes

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:image"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:time"
import "vendor:cgltf"
import "vendor:sdl3"
import "vendor:wgpu"

import "../../asset"
import "../../camera"
import "../../ecs"
import "../../ecs/params"
import "../../errors"
import "../../graphics"
import threeD "../../graphics/3d"
import "../../input"
import log "../../logging"
import "../../transform"
import "../../windowing"

GltfModel :: struct {
	asset: asset.AssetId(asset.Gltf_Data),
	color: [4]f32,
}

ObjModel :: struct {
	mesh:      asset.AssetId(asset.Obj_Mesh),
	materials: asset.AssetId(asset.Materials),
	color:     [4]f32,
}

model_setup :: proc(world: ^ecs.World) {
	server := ecs.world_get_resource(world, asset.AssetServer)
	if server == nil do panic("AssetServer resource not found")

	window_res := ecs.world_get_resource(world, windowing.Window_Context)
	if window_res == nil || window_res.window == nil do return

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.window, &win_w, &win_h)
	w := f32(win_w)
	h := f32(win_h)

	// Register path schema "game"
	asset.asset_schemas_register(&server.registry, "game", "test_assets/")

	// Load assets
	gltf_res := asset.asset_server_load(server, "game://AnimatedTriangle.gltf", asset.Gltf_Data)
	_ = errors.unwrap(gltf_res)

	obj_res := asset.asset_server_load(server, "game://Wolf_One.obj", asset.Obj_Mesh)
	_ = errors.unwrap(obj_res)

	mtl_res := asset.asset_server_load(server, "game://Wolf_One.mtl", asset.Materials)
	mtl_data := errors.unwrap(mtl_res)

	// Load WGSL shader assets
	pbr_shader_res := asset.asset_server_load(
		server,
		"game://shaders/pbr.wgsl",
		graphics.Shader_Asset,
	)
	_ = errors.unwrap(pbr_shader_res)

	// Resolve AssetIds
	_, gltf_id_untyped, _ := asset.asset_schemas_resolve(
		&server.registry,
		"game://AnimatedTriangle.gltf",
	)
	gltf_id := asset.AssetId(asset.Gltf_Data) {
		id = gltf_id_untyped,
	}

	_, obj_id_untyped, _ := asset.asset_schemas_resolve(&server.registry, "game://Wolf_One.obj")
	obj_id := asset.AssetId(asset.Obj_Mesh) {
		id = obj_id_untyped,
	}

	_, mtl_id_untyped, _ := asset.asset_schemas_resolve(&server.registry, "game://Wolf_One.mtl")
	mtl_id := asset.AssetId(asset.Materials) {
		id = mtl_id_untyped,
	}

	wolf_color := [4]f32{0.5, 0.5, 0.5, 1.0}
	if mtl_data != nil {
		if mat, ok := mtl_data.materials["Wolf_Body"]; ok {
			wolf_color = {mat.diffuse.x, mat.diffuse.y, mat.diffuse.z, 1.0}
		}
		// Load textures referenced by any material
		for _, mat in mtl_data.materials {
			if len(mat.map_kd) > 0 {
				// Normalize backslashes to forward slashes
				clean_tex, _ := strings.replace_all(mat.map_kd, "\\", "/", context.temp_allocator)

				// Strip any leading Blender-specific option switches (e.g., "-s 0.8 0.8 1.0")
				fields := strings.fields(clean_tex, context.temp_allocator)
				if len(fields) > 0 {
					clean_tex = fields[len(fields) - 1]
				}

				// Find "textures/" substring and slice starting from that, or default to the file basename
				tex_idx := strings.index(clean_tex, "textures/")
				if tex_idx != -1 {
					clean_tex = clean_tex[tex_idx:]
				} else {
					// Fallback: if "textures/" is not in path, try to find last slash to get basename
					last_slash := strings.last_index(clean_tex, "/")
					if last_slash != -1 {
						clean_tex = fmt.tprintf("textures/%s", clean_tex[last_slash + 1:])
					} else {
						clean_tex = fmt.tprintf("textures/%s", clean_tex)
					}
				}

				// Clean up any double slashes (e.g. "//") in the path
				clean_tex, _ = strings.replace_all(clean_tex, "//", "/", context.temp_allocator)

				tex_uri := fmt.tprintf("game://%s", clean_tex)
				log.info("Loading material texture: %s", tex_uri)
				_ = asset.asset_server_load(server, tex_uri, image.Image)
			}
		}
	}

	// 1. Spawn Perspective Camera
	cam_ent := ecs.world_spawn(world)
	cam: camera.Camera
	camera.init(&cam)
	aspect := w / h
	camera.set_perspective(&cam, 45.0 * math.RAD_PER_DEG, aspect, 0.1, 100.0)

	cam_t: transform.Transform
	transform.init(&cam_t)
	transform.set_translation(&cam_t, {0.0, 1.0, 8.0})

	ecs.world_add_component(world, cam_ent, cam)
	ecs.world_add_component(world, cam_ent, cam_t)

	// 2. Spawn GLTF Entity
	gltf_ent := ecs.world_spawn(world)
	gltf_t: transform.Transform
	transform.init(&gltf_t)
	transform.set_translation(&gltf_t, {-2.0, 0.0, 0.0})
	transform.set_scale(&gltf_t, {2.0, 2.0, 2.0})
	ecs.world_add_component(world, gltf_ent, gltf_t)
	ecs.world_add_component(
		world,
		gltf_ent,
		GltfModel{asset = gltf_id, color = {1.0, 1.0, 1.0, 1.0}},
	)

	// 3. Spawn OBJ Entity
	obj_ent := ecs.world_spawn(world)
	obj_t: transform.Transform
	transform.init(&obj_t)
	transform.set_translation(&obj_t, {2.0, -1.0, 0.0})
	transform.set_scale(&obj_t, {2.5, 2.5, 2.5})
	// Face the camera slightly
	rot := linalg.quaternion_angle_axis_f32(180.0 * math.RAD_PER_DEG, {0.0, 1.0, 0.0})
	transform.set_rotation(&obj_t, rot)
	ecs.world_add_component(world, obj_ent, obj_t)
	ecs.world_add_component(
		world,
		obj_ent,
		ObjModel{mesh = obj_id, materials = mtl_id, color = wolf_color},
	)
}

update_gltf_animation :: proc(data: ^cgltf.data, time_elapsed: f32) {
	if data == nil || len(data.animations) == 0 do return

	for anim in data.animations {
		for channel in anim.channels {
			node := channel.target_node
			sampler := channel.sampler
			if node == nil || sampler == nil do return

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

draw_gltf_node :: proc(
	batch: ^graphics.Batch3D,
	data: ^cgltf.data,
	n: ^cgltf.node,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
) {
	if n == nil do return

	mat: [16]f32
	cgltf.node_transform_world(n, ([^]f32)(&mat[0]))
	node_m4 := transmute(linalg.Matrix4f32)mat

	combined_model := model_m4 * node_m4
	mvp := vp * combined_model

	if n.mesh != nil {
		for &prim in n.mesh.primitives {
			pos_attr: ^cgltf.attribute = nil
			for &attr in prim.attributes {
				if attr.type == .position {
					pos_attr = &attr
					break
				}
			}
			if pos_attr == nil do continue

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

			for i in 0 ..< count {
				raw_pos := [3]f32 {
					pos_buffer[i * 3 + 0],
					pos_buffer[i * 3 + 1],
					pos_buffer[i * 3 + 2],
				}

				final_pos: [3]f32
				if use_pbr {
					// PBR shader projects on GPU, so CPU only transforms to world-space
					world_pos4 := combined_model * [4]f32{raw_pos[0], raw_pos[1], raw_pos[2], 1.0}
					final_pos = world_pos4.xyz
				} else {
					// Default shader expects clip space
					final_pos = threeD.project_point(mvp, raw_pos)
				}

				append(&batch.vertices, graphics.Vertex3D{position = final_pos, color = color})
			}

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
		}
	}

	for child in n.children {
		draw_gltf_node(batch, data, child, color, vp, model_m4, use_pbr)
	}
}

draw_gltf_model_hierarchical :: proc(
	batch: ^graphics.Batch3D,
	model: ^asset.Gltf_Data,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
) {
	if model == nil || model.raw_data == nil do return
	data := model.raw_data

	if data.scene != nil {
		for n in data.scene.nodes {
			draw_gltf_node(batch, data, n, color, vp, model_m4, use_pbr)
		}
	} else {
		for i in 0 ..< len(data.nodes) {
			n := &data.nodes[i]
			if n.parent == nil {
				draw_gltf_node(batch, data, n, color, vp, model_m4, use_pbr)
			}
		}
	}
}

model_update_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_axes: input.Input(input.GamepadAxis),
	gp_buttons: input.Input(input.GamepadButton),
	prev_tick_local: params.Local(time.Tick),
	initialized_local: params.Local(bool),
	anim_timer: params.Local(f32),
	gltfs: params.Assets(asset.Gltf_Data),
	gltf_query: params.Query(struct {
			t: transform.Transform,
			m: GltfModel,
		}),
	obj_query: params.Query(struct {
			t: transform.Transform,
			m: ObjModel,
		}),
) {
	active_scene := ecs.world_get_resource(world, ActiveScene)
	if active_scene == nil || active_scene.index != 2 do return

	if initialized_local.value^ == false {
		prev_tick_local.value^ = time.tick_now()
		initialized_local.value^ = true
		anim_timer.value^ = 0.0
	}

	now := time.tick_now()
	dt := f32(time.duration_seconds(time.tick_diff(prev_tick_local.value^, now)))
	prev_tick_local.value^ = now

	if dt <= 0.0 || dt > 0.1 {
		dt = 1.0 / 60.0
	}

	anim_timer.value^ += dt
	t_elapsed := anim_timer.value^

	// 1. Calculate rotation change from mouse drag / Touch drag (unified)
	rot_x: f32 = 0.0
	rot_y: f32 = 0.0
	if input.is_down(mouse_inp, input.MouseButtonCode.Left) {
		m_delta := input.mouse_delta(mouse_inp)
		rot_y = m_delta.x * 0.01
		rot_x = m_delta.y * 0.01
	}

	// 2. Calculate rotation change from Gamepad Sticks
	rx := input.gamepad_axis(gp_axes, .RightX)
	ry := input.gamepad_axis(gp_axes, .RightY)
	if rx == 0.0 && ry == 0.0 {
		rx = input.gamepad_axis(gp_axes, .LeftX)
		ry = input.gamepad_axis(gp_axes, .LeftY)
	}
	if math.abs(rx) > 0.1 {
		rot_y += rx * dt * 2.0
	}
	if math.abs(ry) > 0.1 {
		rot_x += ry * dt * 2.0
	}

	if rot_x != 0.0 || rot_y != 0.0 {
		q_y := linalg.quaternion_angle_axis_f32(rot_y, {0, 1, 0})
		q_x := linalg.quaternion_angle_axis_f32(rot_x, {1, 0, 0})
		q_rot := q_y * q_x

		for arch in params.query(gltf_query) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				transform.rotate_local(t, q_rot)
			}
		}

		for arch in params.query(obj_query) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				transform.rotate_local(t, q_rot)
			}
		}
	}

	// 3. Animate GLTF Models
	for arch in params.query(gltf_query) {
		models := ecs.arch_get_field(arch, GltfModel)
		for i in 0 ..< len(models) {
			m := models[i]
			for &entry in gltfs.assets {
				if entry.id.id.value == m.asset.id.value {
					update_gltf_animation(entry.asset.raw_data, t_elapsed)
					break
				}
			}
		}
	}
}

ModelLocalState :: struct {
	pbr_shader_pass: graphics.Shader_Pass,
	pbr_initialized: bool,
}

model_draw_system :: proc(
	world: ^ecs.World,
	batch3d: params.Res(graphics.Batch3D),
	batch2d: params.Res(graphics.Batch2D),
	window_res: params.Res(windowing.Window_Context),
	pbr_config_res: params.Res(graphics.Pbr_Config),
	render_ctx: params.Res(graphics.Render_Context),
	gltfs: params.Assets(asset.Gltf_Data),
	objs: params.Assets(asset.Obj_Mesh),
	materials: params.Assets(asset.Materials),
	images: params.Assets(image.Image),
	shaders: params.Assets(graphics.Shader_Asset),
	gltf_query: params.Query(struct {
			t: transform.Transform,
			m: GltfModel,
		}),
	obj_query: params.Query(struct {
			t: transform.Transform,
			m: ObjModel,
		}),
	cam_query: params.Query(struct {
			c: camera.Camera,
			t: transform.Transform,
		}),
	local_state: params.Local(ModelLocalState),
) {
	active_scene := ecs.world_get_resource(world, ActiveScene)
	if active_scene == nil || active_scene.index != 2 do return

	batch := batch3d.ptr
	if batch == nil do return

	win_w, win_h: c.int
	if window_res.ptr != nil && window_res.ptr.window != nil {
		sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	} else {
		win_w = 800
		win_h = 600
	}
	ui_scale := f32(win_w) / 800.0

	vp := graphics.resolve_camera_vp(world, {})

	// Get camera position
	cam_pos := [3]f32{0.0, 1.0, 8.0}
	for arch in params.query(cam_query) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		if len(transforms) > 0 {
			cam_pos = transform.get_translation(transforms[0])
			break
		}
	}

	// 1. Initialize PBR shader pass from shader assets
	if local_state.value.pbr_initialized == false &&
	   render_ctx.ptr != nil &&
	   render_ctx.ptr.device != nil {
		// Resolve path to search for compiled module
		_, pbr_id, ok := asset.asset_schemas_resolve(
			&graphics.global_asset_server.registry,
			"game://shaders/pbr.wgsl",
		)
		if ok {
			for &entry in shaders.assets {
				if entry.id.id.value == pbr_id.value {
					sample_count: u32 = 1
					if pbr_config_res.ptr != nil {
						sample_count = u32(pbr_config_res.ptr.antialiasing)
					}
					pass, pbr_ok := graphics.create_pbr_shader_pass(
						render_ctx.ptr.device,
						&entry.asset,
						render_ctx.ptr.config.format,
						sample_count,
					)
					if pbr_ok {
						local_state.value.pbr_shader_pass = pass
						local_state.value.pbr_initialized = true
					}
					break
				}
			}
		}
	}

	use_pbr := local_state.value.pbr_initialized

	// 2. Setup PBR Uniforms if active
	if use_pbr {
		pass_idx := -1
		for p, idx in batch.shader_passes {
			if p.render_pipeline == local_state.value.pbr_shader_pass.render_pipeline {
				pass_idx = idx
				break
			}
		}
		if pass_idx == -1 {
			append(&batch.shader_passes, local_state.value.pbr_shader_pass)
			pass_idx = len(batch.shader_passes) - 1
		}
		batch.active_pass_idx = pass_idx

		// Update Uniforms
		uniforms: graphics.Pbr_Uniforms
		uniforms.vp = vp
		uniforms.model = linalg.MATRIX4F32_IDENTITY
		uniforms.cam_pos = cam_pos

		if pbr_config_res.ptr != nil {
			uniforms.lights = pbr_config_res.ptr.lights
			uniforms.num_lights = pbr_config_res.ptr.num_lights
			uniforms.roughness = pbr_config_res.ptr.roughness
			uniforms.metallic = pbr_config_res.ptr.metallic
			uniforms.ao = pbr_config_res.ptr.ao
		}

		graphics.shader_pass_update_uniforms(
			&batch.shader_passes[pass_idx],
			render_ctx.ptr,
			uniforms,
		)
	} else {
		batch.active_pass_idx = -1
	}

	// Draw GLTF models
	for arch in params.query(gltf_query) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		models := ecs.arch_get_field(arch, GltfModel)
		for i in 0 ..< len(transforms) {
			t := transforms[i]
			m := models[i]

			// Find GLTF data in Assets(Gltf_Data)
			for &entry in gltfs.assets {
				if entry.id.id.value == m.asset.id.value {
					draw_gltf_model_hierarchical(
						batch,
						&entry.asset,
						m.color,
						vp,
						t.world_matrix,
						use_pbr,
					)
					break
				}
			}
		}
	}

	// Draw OBJ models
	for arch in params.query(obj_query) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		models := ecs.arch_get_field(arch, ObjModel)
		for i in 0 ..< len(transforms) {
			t := transforms[i]
			m := models[i]

			// Find OBJ data in Assets(Obj_Mesh)
			for &entry in objs.assets {
				if entry.id.id.value == m.mesh.id.value {
					obj_ptr := &entry.asset
					base_idx := u32(len(batch.vertices))

					// Find map_kd texture if material exists
					tex_ptr: ^image.Image = nil
					for &mtl_entry in materials.assets {
						if mtl_entry.id.id.value == m.materials.id.value {
							mtl_data := &mtl_entry.asset
							if mat, ok3 := mtl_data.materials["Wolf_Body"];
							   ok3 && len(mat.map_kd) > 0 {
								clean_tex, _ := strings.replace_all(
									mat.map_kd,
									"\\",
									"/",
									context.temp_allocator,
								)
								fields := strings.fields(clean_tex, context.temp_allocator)
								if len(fields) > 0 do clean_tex = fields[len(fields) - 1]
								tex_idx := strings.index(clean_tex, "textures/")
								if tex_idx != -1 {
									clean_tex = clean_tex[tex_idx:]
								} else {
									last_slash := strings.last_index(clean_tex, "/")
									if last_slash != -1 {
										clean_tex = fmt.tprintf(
											"textures/%s",
											clean_tex[last_slash + 1:],
										)
									} else {
										clean_tex = fmt.tprintf("textures/%s", clean_tex)
									}
								}
								clean_tex, _ = strings.replace_all(
									clean_tex,
									"//",
									"/",
									context.temp_allocator,
								)

								// Resolve untyped asset ID for texture
								_, tex_id, _ := asset.asset_schemas_resolve(
									&graphics.global_asset_server.registry,
									fmt.tprintf("game://%s", clean_tex),
								)
								for &img_entry in images.assets {
									if img_entry.id.id.value == tex_id.value {
										tex_ptr = &img_entry.asset
										break
									}
								}
							}
							break
						}
					}

					for v, idx in obj_ptr.vertices {
						v_color := m.color
						if tex_ptr != nil && len(obj_ptr.texcoords) > idx {
							uv := obj_ptr.texcoords[idx]
							tx := int(uv.x * f32(tex_ptr.width)) % tex_ptr.width
							ty := int((1.0 - uv.y) * f32(tex_ptr.height)) % tex_ptr.height
							if tx < 0 do tx += tex_ptr.width
							if ty < 0 do ty += tex_ptr.height

							v_color = graphics.get_pixel(tex_ptr, tx, ty)
						} else {
							// Fallback to diffuse flat color
							for &mtl_entry in materials.assets {
								if mtl_entry.id.id.value == m.materials.id.value {
									mtl_data := &mtl_entry.asset
									if mat, ok3 := mtl_data.materials["Wolf_Body"]; ok3 {
										v_color = {
											mat.diffuse.x,
											mat.diffuse.y,
											mat.diffuse.z,
											1.0,
										}
									}
									break
								}
							}
						}

						final_pos: [3]f32
						raw_pos := [3]f32{v[0], v[1], v[2]}
						if use_pbr {
							world_pos4 :=
								t.world_matrix * [4]f32{raw_pos[0], raw_pos[1], raw_pos[2], 1.0}
							final_pos = world_pos4.xyz
						} else {
							final_pos = threeD.project_point(vp * t.world_matrix, raw_pos)
						}

						append(
							&batch.vertices,
							graphics.Vertex3D{position = final_pos, color = v_color},
						)
					}

					for idx in obj_ptr.indices {
						append(&batch.indices, base_idx + idx)
					}
					break
				}
			}
		}
	}

	// Draw UI overlay
	font := ecs.world_get_resource(world, graphics.Font)
	if font != nil && batch2d.ptr != nil {
		w := f32(win_w)
		h := f32(win_h)
		ui_vp := linalg.matrix_ortho3d_f32(-w / 2, w / 2, -h / 2, h / 2, -1.0, 1.0)

		pbr_str :=
			"[color=green]Active[/color]" if use_pbr else "[color=red]Disabled (No PBR Shader loaded)[/color]"
		graphics.draw_text(
			batch2d.ptr,
			fmt.tprintf(
				"Scene 3: [color=orange]3D PBR Models[/color] (%s). Press ESC to switch scene.",
				pbr_str,
			),
			-350 * ui_scale,
			220 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
		graphics.draw_text(
			batch2d.ptr,
			"Left: AnimatedTriangle.gltf (animated)",
			-350 * ui_scale,
			-200 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
		graphics.draw_text(
			batch2d.ptr,
			"Right: Wolf_One.obj (colored using Wolf_One.mtl)",
			-350 * ui_scale,
			-230 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
		graphics.draw_text(
			batch2d.ptr,
			"Drag Mouse/Touch or use Gamepad Sticks to Rotate",
			-350 * ui_scale,
			-260 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
	}
}
