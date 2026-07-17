package scenes

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"
import "vendor:cgltf"
import "vendor:sdl3"

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
) {
	if n == nil do return

	mat: [16]f32
	cgltf.node_transform_world(n, ([^]f32)(&mat[0]))
	node_m4 := transmute(linalg.Matrix4f32)mat

	mvp := vp * node_m4

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
				append(
					&batch.vertices,
					graphics.Vertex3D {
						position = threeD.project_point(mvp, raw_pos),
						color = color,
					},
				)
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
		draw_gltf_node(batch, data, child, color, vp)
	}
}

draw_gltf_model_hierarchical :: proc(
	batch: ^graphics.Batch3D,
	model: ^asset.Gltf_Data,
	color: [4]f32,
	vp: linalg.Matrix4f32,
) {
	if model == nil || model.raw_data == nil do return
	data := model.raw_data

	if data.scene != nil {
		for n in data.scene.nodes {
			draw_gltf_node(batch, data, n, color, vp)
		}
	} else {
		for i in 0 ..< len(data.nodes) {
			n := &data.nodes[i]
			if n.parent == nil {
				draw_gltf_node(batch, data, n, color, vp)
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

		for arch in ecs.query(world, transform.Transform, GltfModel) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				transform.rotate_local(t, q_rot)
			}
		}

		for arch in ecs.query(world, transform.Transform, ObjModel) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				transform.rotate_local(t, q_rot)
			}
		}

		for arch in ecs.query(world, transform.Transform, ObjModel) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			for i in 0 ..< len(transforms) {
				t := &transforms[i]
				transform.rotate_local(t, q_rot)
			}
		}
	}

	// 3. Animate GLTF Models
	gltf_mgr := ecs.world_get_resource(world, asset.AssetManager(asset.Gltf_Data))
	if gltf_mgr != nil {
		for arch in ecs.query(world, GltfModel) {
			models := ecs.arch_get_field(arch, GltfModel)
			for i in 0 ..< len(models) {
				m := models[i]
				if gltf_ptr, ok := &gltf_mgr.assets[m.asset.id]; ok {
					update_gltf_animation(gltf_ptr.raw_data, t_elapsed)
				}
			}
		}
	}
}

model_draw_system :: proc(
	world: ^ecs.World,
	batch3d: params.Res(graphics.Batch3D),
	batch2d: params.Res(graphics.Batch2D),
	window_res: params.Res(windowing.Window_Context),
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

	// Draw GLTF models
	gltf_mgr := ecs.world_get_resource(world, asset.AssetManager(asset.Gltf_Data))
	if gltf_mgr != nil {
		for arch in ecs.query(world, transform.Transform, GltfModel) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			models := ecs.arch_get_field(arch, GltfModel)
			for i in 0 ..< len(transforms) {
				t := transforms[i]
				m := models[i]
				if gltf_ptr, ok := &gltf_mgr.assets[m.asset.id]; ok {
					model_vp := vp * t.world_matrix
					draw_gltf_model_hierarchical(batch, gltf_ptr, m.color, model_vp)
				}
			}
		}
	}

	// Draw OBJ models
	obj_mgr := ecs.world_get_resource(world, asset.AssetManager(asset.Obj_Mesh))
	if obj_mgr != nil {
		for arch in ecs.query(world, transform.Transform, ObjModel) {
			transforms := ecs.arch_get_field(arch, transform.Transform)
			models := ecs.arch_get_field(arch, ObjModel)
			for i in 0 ..< len(transforms) {
				t := transforms[i]
				m := models[i]
				if obj_ptr, ok := &obj_mgr.assets[m.mesh.id]; ok {
					model_vp := vp * t.world_matrix
					threeD.draw_model(batch, obj_ptr, m.color, model_vp)
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

		graphics.draw_text(
			batch2d.ptr,
			"Scene 3: [color=orange]3D Models[/color] (GLTF & OBJ). Press ESC to switch scene.",
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
