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
import components "../../graphics/components"
import threeD "../../graphics/3d"
import "../../input"
import log "../../logging"
import "../../transform"
import "../../windowing"

GltfModel :: struct {
	asset: asset.AssetId(asset.Gltf_Data),
	color: [4]f32,
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
	triangle_gltf, triangle_id, triangle_err := asset.asset_server_load(
		server,
		"game://gltf/AnimatedTriangle.gltf",
		asset.Gltf_Data,
	)

	wolf, wolf_id, wolf_err := asset.asset_server_load(
		server,
		"game://gltf/wolf/Wolf-Blender-2.82a.gltf",
		asset.Gltf_Data,
	)

	// Load WGSL shader assets
	pbr_shader, pbr_shader_id, pbr_err := asset.asset_server_load(
		server,
		"game://shaders/pbr.wgsl",
		graphics.Shader_Asset,
	)

	pbr_skinned_shader, pbr_skinned_shader_id, pbr_skinned_err := asset.asset_server_load(
		server,
		"game://shaders/pbr_skinned.wgsl",
		graphics.Shader_Asset,
	)

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
		GltfModel{asset = triangle_id, color = {1.0, 1.0, 1.0, 1.0}},
	)

	// 3. Spawn Point Light entities (ECS Light components)
	light1 := ecs.world_spawn(world)
	light1_t: transform.Transform
	transform.init(&light1_t)
	transform.set_translation(&light1_t, {5.0, 5.0, 5.0})
	ecs.world_add_component(world, light1, light1_t)
	ecs.world_add_component(
		world,
		light1,
		components.Point_Light{intensity = 1.0, color = {1.0, 1.0, 1.0}, radius = 20.0},
	)

	light2 := ecs.world_spawn(world)
	light2_t: transform.Transform
	transform.init(&light2_t)
	transform.set_translation(&light2_t, {-5.0, 5.0, -5.0})
	ecs.world_add_component(world, light2, light2_t)
	ecs.world_add_component(
		world,
		light2,
		components.Point_Light{intensity = 0.5, color = {0.8, 0.9, 1.0}, radius = 20.0},
	)

	// 4. Spawn Wolf GLTF Entity
	wolf_ent := ecs.world_spawn(world)
	wolf_t: transform.Transform
	transform.init(&wolf_t)
	transform.set_translation(&wolf_t, {2.0, -1.0, 0.0})
	transform.set_scale(&wolf_t, {2.5, 2.5, 2.5})
	// Face the camera slightly
	rot := linalg.quaternion_angle_axis_f32(180.0 * math.RAD_PER_DEG, {0.0, 1.0, 0.0})
	transform.set_rotation(&wolf_t, rot)
	ecs.world_add_component(world, wolf_ent, wolf_t)
	ecs.world_add_component(
		world,
		wolf_ent,
		GltfModel{asset = wolf_id, color = {1.0, 1.0, 1.0, 1.0}},
	)
	ecs.world_add_component(
		world,
		wolf_ent,
		components.Light_Target{
			light_entities = {light1, light2, {}, {}},
			num_targets    = 2,
		},
	)
	ecs.world_add_resource(world, Wolf_Render_State{}, destroy_wolf_render_state)
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

draw_gltf_node :: proc(
	batch: ^graphics.Batch3D,
	model: ^asset.Gltf_Data,
	n: ^cgltf.node,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
	textures: []asset.Asset_Entry(wgpu.Texture),
) {
	if n == nil || model == nil || model.raw_data == nil do return
	if n.name != nil && string(n.name) == "Circle" do return
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
			for &attr in prim.attributes {
				if attr.type == .position {
					pos_attr = &attr
				} else if attr.type == .texcoord && attr.index == 0 {
					uv_attr = &attr
				}
			}
			if pos_attr == nil do continue

			// Resolve texture and base color factor if available
			tex_handle: wgpu.Texture = nil
			vertex_color := color
			if prim.material != nil && prim.material.has_pbr_metallic_roughness {
				pbr_mat := &prim.material.pbr_metallic_roughness
				factor := pbr_mat.base_color_factor
				vertex_color = {factor[0] * color[0], factor[1] * color[1], factor[2] * color[2], factor[3] * color[3]}
				base_tex := pbr_mat.base_color_texture
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

				uv_coord: [2]f32 = {0.0, 0.0}
				if uv_buffer != nil {
					uv_coord = {uv_buffer[i * 2 + 0], uv_buffer[i * 2 + 1]}
				}

				append(
					&batch.vertices,
					graphics.Vertex3D{position = final_pos, color = vertex_color, uv = uv_coord},
				)
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

			cmd := graphics.Draw_Command {
				index_start = start_idx,
				index_count = u32(len(batch.indices) - int(start_idx)),
				texture     = tex_handle,
			}
			append(&batch.commands, cmd)
		}
	}

	for child in n.children {
		draw_gltf_node(batch, model, child, color, vp, model_m4, use_pbr, textures)
	}
}

draw_gltf_model_hierarchical :: proc(
	batch: ^graphics.Batch3D,
	model: ^asset.Gltf_Data,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	model_m4: linalg.Matrix4f32,
	use_pbr: bool,
	textures: []asset.Asset_Entry(wgpu.Texture),
) {
	if model == nil || model.raw_data == nil do return
	data := model.raw_data

	if data.scene != nil {
		for n in data.scene.nodes {
			draw_gltf_node(batch, model, n, color, vp, model_m4, use_pbr, textures)
		}
	} else {
		for i in 0 ..< len(data.nodes) {
			n := &data.nodes[i]
			if n.parent == nil {
				draw_gltf_node(batch, model, n, color, vp, model_m4, use_pbr, textures)
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
	cam_query: params.Query(struct {
			c: camera.Camera,
			t: transform.Transform,
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

	// 2. Calculate panning change from middle or right mouse drag
	pan_x: f32 = 0.0
	pan_y: f32 = 0.0
	if input.is_down(mouse_inp, input.MouseButtonCode.Middle) || input.is_down(mouse_inp, input.MouseButtonCode.Right) {
		m_delta := input.mouse_delta(mouse_inp)
		pan_x = m_delta.x * 0.015
		pan_y = m_delta.y * 0.015
	}

	if pan_x != 0.0 || pan_y != 0.0 {
		for arch in params.query(cam_query) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				pos := transform.get_translation(t^)
				pos.x -= pan_x
				pos.y += pan_y
				transform.set_translation(t, pos)
			}
		}
	}

	// 3. Calculate rotation change from Gamepad Sticks
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
	}

	// Calculate zoom amount
	zoom_amount: f32 = 0.0

	// 1. Mouse wheel zoom (scroll Y)
	m_wheel := input.mouse_wheel(mouse_inp)
	if m_wheel.y != 0.0 {
		zoom_amount -= m_wheel.y * 0.5
	}

	// 2. Right trigger / Left trigger zoom
	rt := input.gamepad_axis(gp_axes, .TriggerRight)
	lt := input.gamepad_axis(gp_axes, .TriggerLeft)
	if rt > 0.0 {
		zoom_amount -= rt * dt * 5.0
	}
	if lt > 0.0 {
		zoom_amount += lt * dt * 5.0
	}

	if zoom_amount != 0.0 {
		for arch in params.query(cam_query) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				pos := transform.get_translation(t^)
				pos.z += zoom_amount
				if pos.z < 1.0 do pos.z = 1.0
				if pos.z > 20.0 do pos.z = 20.0
				transform.set_translation(t, pos)
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
					graphics.update_gltf_animation(entry.asset.raw_data, t_elapsed)
					break
				}
			}
		}
	}
}

Wolf_Render_State :: struct {
	pbr_shader_pass:         graphics.Shader_Pass,
	pbr_skinned_shader_pass: graphics.Shader_Pass,
	pbr_initialized:         bool,
	skinned_initialized:     bool,
	wolf_submeshes:          []graphics.SkinnedSubMesh,
	wolf_mesh_created:       bool,
}

destroy_wolf_render_state :: proc(state: ^Wolf_Render_State, alloc: runtime.Allocator) {
	if state.wolf_mesh_created {
		for &submesh in state.wolf_submeshes {
			graphics.destroy_mesh(&submesh.mesh)
			if submesh.uniform_buf != nil {
				wgpu.BufferRelease(submesh.uniform_buf)
				submesh.uniform_buf = nil
			}
			if submesh.bind_group != nil {
				wgpu.BindGroupRelease(submesh.bind_group)
				submesh.bind_group = nil
			}
			if submesh.tex_view != nil {
				wgpu.TextureViewRelease(submesh.tex_view)
				submesh.tex_view = nil
			}
			if submesh.fallback_tex != nil {
				wgpu.TextureRelease(submesh.fallback_tex)
				submesh.fallback_tex = nil
			}
		}
		delete(state.wolf_submeshes)
		state.wolf_submeshes = nil
		state.wolf_mesh_created = false
	}
	if state.pbr_initialized {
		graphics.destroy_shader_pass(&state.pbr_shader_pass)
		state.pbr_initialized = false
	}
	if state.skinned_initialized {
		graphics.destroy_shader_pass(&state.pbr_skinned_shader_pass)
		state.skinned_initialized = false
	}
}

model_draw_system :: proc(
	world: ^ecs.World,
	batch3d: params.Res(graphics.Batch3D),
	batch2d: params.Res(graphics.Batch2D),
	window_res: params.Res(windowing.Window_Context),
	gfx_config_res: params.Res(graphics.Graphics_Config),
	render_ctx: params.Res(graphics.Render_Context),
	gltfs: params.Assets(asset.Gltf_Data),
	images: params.Assets(image.Image),
	shaders: params.Assets(graphics.Shader_Asset),
	textures: params.Assets(wgpu.Texture),
	gltf_query: params.Query(struct {
			t: transform.Transform,
			m: GltfModel,
		}),
	cam_query: params.Query(struct {
			c: camera.Camera,
			t: transform.Transform,
		}),
	light_query: params.Query(struct {
			t: transform.Transform,
			l: components.Point_Light,
		}),
) {
	state := ecs.world_get_resource(world, Wolf_Render_State)
	if state == nil do return

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
	if state.pbr_initialized == false && render_ctx.ptr != nil && render_ctx.ptr.device != nil {
		_, pbr_id, ok := asset.asset_schemas_resolve(
			&graphics.global_asset_server.registry,
			"game://shaders/pbr.wgsl",
		)
		if ok {
			for &entry in shaders.assets {
				if entry.id.id.value == pbr_id.value {
					sample_count: u32 = 1
					if gfx_config_res.ptr != nil {
						sample_count = graphics.antialiasing_sample_count(gfx_config_res.ptr.antialiasing)
					}
					fallback_tex, fallback_view := graphics.create_fallback_texture(
						render_ctx.ptr.device,
						render_ctx.ptr.queue,
					)
					pass, pbr_ok := graphics.create_pbr_shader_pass(
						render_ctx.ptr.device,
						&entry.asset,
						render_ctx.ptr.config.format,
						sample_count,
						fallback_view,
						render_ctx.ptr.default_sampler,
					)
					wgpu.TextureViewRelease(fallback_view)
					wgpu.TextureRelease(fallback_tex)

					if pbr_ok {
						state.pbr_shader_pass = pass
						state.pbr_initialized = true
					}
					break
				}
			}
		}
	}

	if state.skinned_initialized == false &&
	   render_ctx.ptr != nil &&
	   render_ctx.ptr.device != nil {
		_, pbr_id, ok := asset.asset_schemas_resolve(
			&graphics.global_asset_server.registry,
			"game://shaders/pbr_skinned.wgsl",
		)
		if ok {
			for &entry in shaders.assets {
				if entry.id.id.value == pbr_id.value {
					sample_count: u32 = 1
					if gfx_config_res.ptr != nil {
						sample_count = graphics.antialiasing_sample_count(gfx_config_res.ptr.antialiasing)
					}
					fallback_tex, fallback_view := graphics.create_fallback_texture(
						render_ctx.ptr.device,
						render_ctx.ptr.queue,
					)
					pass, pbr_ok := graphics.create_pbr_skinned_shader_pass(
						render_ctx.ptr.device,
						&entry.asset,
						render_ctx.ptr.config.format,
						sample_count,
						fallback_view,
						render_ctx.ptr.default_sampler,
					)
					wgpu.TextureViewRelease(fallback_view)
					wgpu.TextureRelease(fallback_tex)

					if pbr_ok {
						state.pbr_skinned_shader_pass = pass
						state.skinned_initialized = true
					}
					break
				}
			}
		}
	}

	// Initialize wolf submeshes if needed
	if state.wolf_mesh_created == false &&
	   render_ctx.ptr != nil &&
	   render_ctx.ptr.device != nil &&
	   state.skinned_initialized {
		for &entry in gltfs.assets {
			if entry.asset.raw_data != nil && len(entry.asset.raw_data.skins) > 0 {
				state.wolf_submeshes = graphics.build_skinned_submeshes(
					render_ctx.ptr.device,
					&entry.asset,
					textures.assets,
					state.pbr_skinned_shader_pass.bind_group_layout,
				)
				state.wolf_mesh_created = true
				break
			}
		}
	}

	use_pbr := state.pbr_initialized
	uniforms: graphics.Pbr_Uniforms

	// 2. Setup PBR Uniforms if active
	if use_pbr {
		pass_idx := -1
		for p, idx in batch.shader_passes {
			if p.render_pipeline == state.pbr_shader_pass.render_pipeline {
				pass_idx = idx
				break
			}
		}
		if pass_idx == -1 {
			append(&batch.shader_passes, state.pbr_shader_pass)
			pass_idx = len(batch.shader_passes) - 1
		}
		batch.active_pass_idx = pass_idx

		// Update Uniforms
		uniforms.vp = vp
		uniforms.model = linalg.MATRIX4F32_IDENTITY
		uniforms.cam_pos = cam_pos

		if gfx_config_res.ptr != nil {
			uniforms.roughness = gfx_config_res.ptr.pbr.roughness
			uniforms.metallic = gfx_config_res.ptr.pbr.metallic
			uniforms.ao = gfx_config_res.ptr.pbr.ao
		}

		// Dynamically gather lights from ECS Point_Light entities using arch_zip
		num_lights: i32 = 0
		for arch in params.query(light_query) {
			transforms, lights, count := ecs.arch_zip(arch, transform.Transform, components.Point_Light)
			for i in 0 ..< count {
				if num_lights >= 4 do break
				pos := transform.get_translation(transforms[i])
				uniforms.lights[num_lights] = graphics.Pbr_Light {
					position  = pos,
					intensity = lights[i].intensity,
					color     = lights[i].color,
					radius    = lights[i].radius,
				}
				num_lights += 1
			}
		}
		uniforms.num_lights = num_lights

		// Collect lights from gltf models
		gltf_lights := make([dynamic]graphics.Pbr_Light, context.temp_allocator)
		for arch in params.query(gltf_query) {
			transforms, models, count := ecs.arch_zip(arch, transform.Transform, GltfModel)
			for i in 0 ..< count {
				t := transforms[i]
				m := models[i]
				for &entry in gltfs.assets {
					if entry.id.id.value == m.asset.id.value {
						if entry.asset.raw_data != nil {
							data := entry.asset.raw_data
							if data.scene != nil {
								for n in data.scene.nodes {
									graphics.collect_gltf_lights(
										&entry.asset,
										n,
										t.world_matrix,
										&gltf_lights,
									)
								}
							} else {
								for j in 0 ..< len(data.nodes) {
									n := &data.nodes[j]
									if n.parent == nil {
										graphics.collect_gltf_lights(
											&entry.asset,
											n,
											t.world_matrix,
											&gltf_lights,
										)
									}
								}
							}
						}
						break
					}
				}
			}
		}

		for gl in gltf_lights {
			if uniforms.num_lights >= 4 do break
			uniforms.lights[uniforms.num_lights] = gl
			uniforms.num_lights += 1
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
					if entry.asset.raw_data != nil &&
					   len(entry.asset.raw_data.skins) > 0 &&
					   state.wolf_mesh_created {
						graphics.batch3d_draw(
							batch,
							render_ctx.ptr.device,
							render_ctx.ptr.queue,
							&entry.asset,
							state.wolf_submeshes,
							uniforms,
							t.world_matrix,
							state.pbr_skinned_shader_pass.render_pipeline,
						)
					} else {
						graphics.batch3d_draw(
							batch,
							&entry.asset,
							m.color,
							vp,
							t.world_matrix,
							use_pbr,
							textures.assets,
							graphics.Gltf_Render_Config{exclude_nodes = {"Circle"}},
						)
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

		pbr_str := "[c=green]Yes[/c]" if use_pbr else "[c=red]No[/c]"
		graphics.draw_text(
			batch2d.ptr,
			fmt.tprintf(
				"Scene 3: [c=orange]3D PBR Models[/c] (%s). Press ESC to switch scene.",
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
			"Right: Wolf-Blender-2.82a.gltf (PBR & animated)",
			-350 * ui_scale,
			-230 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
		graphics.draw_text(
			batch2d.ptr,
			"Drag Mouse/Touch or use Gamepad Sticks to Rotate Models",
			-350 * ui_scale,
			-260 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			ui_vp,
		)
	}
}
