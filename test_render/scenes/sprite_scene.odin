package scenes

import "base:runtime"
import "core:c"
import "core:image"
import "core:math/linalg"
import "vendor:sdl3"

import "../../asset"
import "../../camera"
import "../../ecs"
import "../../ecs/params"
import "../../errors"
import "../../graphics"
import "../../graphics/components"
import "../../transform"
import "../../windowing"

sprite_setup :: proc(world: ^ecs.World) {
	server := ecs.world_get_resource(world, asset.AssetServer)
	if server == nil do panic("AssetServer resource not found")

	window_res := ecs.world_get_resource(world, windowing.Window_Context)
	if window_res == nil || window_res.window == nil do return

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.window, &win_w, &win_h)
	w := f32(win_w)
	h := f32(win_h)

	// Register the local path scheme "game" to read workspace files
	asset.asset_schemas_register(&server.registry, "game", "test_assets/")

	// Load animations
	walk_res := asset.asset_server_load(server, "game://blob.walk.gif", components.SpriteAnimation)
	walk_anim := errors.unwrap(walk_res)

	attack_res := asset.asset_server_load(
		server,
		"game://blob.attack.gif",
		components.SpriteAnimation,
	)
	attack_anim := errors.unwrap(attack_res)

	// Resolve the asset IDs of the loaded animations
	_, walk_id_untyped, _ := asset.asset_schemas_resolve(&server.registry, "game://blob.walk.gif")
	walk_id := asset.AssetId(components.SpriteAnimation) {
		id = walk_id_untyped,
	}

	_, attack_id_untyped, _ := asset.asset_schemas_resolve(
		&server.registry,
		"game://blob.attack.gif",
	)
	attack_id := asset.AssetId(components.SpriteAnimation) {
		id = attack_id_untyped,
	}

	// 1. Spawn Global Camera
	global_cam_ent := ecs.world_spawn(world)
	global_cam: camera.Camera
	camera.init(&global_cam)
	camera.set_orthographic(&global_cam, -w / 2, w / 2, -h / 2, h / 2, -100.0, 100.0)

	global_cam_t: transform.Transform
	transform.init(&global_cam_t)
	transform.set_translation(&global_cam_t, {0, 0, 10})

	ecs.world_add_component(world, global_cam_ent, global_cam)
	ecs.world_add_component(world, global_cam_ent, global_cam_t)

	// 2. Spawn Local Camera (translated to offset rendering)
	local_cam_ent := ecs.world_spawn(world)
	local_cam: camera.Camera
	camera.init(&local_cam)
	camera.set_orthographic(&local_cam, -w / 2, w / 2, -h / 2, h / 2, -100.0, 100.0)

	local_cam_t: transform.Transform
	transform.init(&local_cam_t)
	// Offset local camera so its center is shifted
	transform.set_translation(&local_cam_t, {50, 50, 10})

	ecs.world_add_component(world, local_cam_ent, local_cam)
	ecs.world_add_component(world, local_cam_ent, local_cam_t)

	// 3. Spawn Entity 1: AnimatedSprite (walk), 2D Space, Global Camera
	t1: transform.Transform
	transform.init(&t1)
	transform.set_translation(&t1, {-150, 0, 0})

	ent1 := ecs.world_spawn(world)
	ecs.world_add_component(world, ent1, t1)
	ecs.world_add_component(
		world,
		ent1,
		components.new_animated_sprite(
			walk_id,
			{128, 128},
			{0.5, 0.5},
			true,
			true,
			{1, 1, 1, 1},
			._2D,
		),
	)

	// 4. Spawn Entity 2: AnimatedSprite (attack), 2D Space, Global Camera
	t2: transform.Transform
	transform.init(&t2)
	transform.set_translation(&t2, {150, 0, 0})

	ent2 := ecs.world_spawn(world)
	ecs.world_add_component(world, ent2, t2)
	ecs.world_add_component(
		world,
		ent2,
		components.new_animated_sprite(
			attack_id,
			{128, 128},
			{0.5, 0.5},
			true,
			true,
			{1.0, 0.6, 0.6, 1.0}, // Reddish tint
			._2D,
		),
	)

	// 5. Spawn Entity 3: AnimatedSprite (walk), 2D Space, Local Camera Override
	t3: transform.Transform
	transform.init(&t3)
	transform.set_translation(&t3, {0, -100, 0})

	ent3 := ecs.world_spawn(world)
	ecs.world_add_component(world, ent3, t3)
	ecs.world_add_component(
		world,
		ent3,
		components.new_animated_sprite(
			walk_id,
			{96, 96},
			{0.5, 0.5},
			true,
			true,
			{0.6, 0.8, 1.0, 0.8}, // Bluish translucent tint
			._2D,
			local_cam_ent,
		),
	)

	// 6. Spawn Entity 4: Static Sprite (frame 0 of walk), 3D Space, Global Camera
	t4: transform.Transform
	transform.init(&t4)
	transform.set_translation(&t4, {0, 100, 0})

	ent4 := ecs.world_spawn(world)
	ecs.world_add_component(world, ent4, t4)
	ecs.world_add_component(
		world,
		ent4,
		components.new_sprite(walk_anim.frames[0], {128, 128}, {0.5, 0.5}, {1, 1, 1, 1}, ._3D),
	)
}

sprite_draw_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(graphics.Batch2D),
	window_res: params.Res(windowing.Window_Context),
) {
	active_scene := ecs.world_get_resource(world, ActiveScene)
	if active_scene == nil || active_scene.index != 1 do return
	batch := batch2d.ptr
	if world == nil || batch == nil do return

	win_w, win_h: c.int
	if window_res.ptr != nil && window_res.ptr.window != nil {
		sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	} else {
		win_w = 800
		win_h = 600
	}
	ui_scale := f32(win_w) / 800.0

	vp := graphics.resolve_camera_vp(world, {})

	font := ecs.world_get_resource(world, graphics.Font)
	if font != nil {
		graphics.draw_text(
			batch,
			"Scene 2: [color=orange]Sprite[/color] & [color=cyan]Animation[/color] rendering.",
			-350 * ui_scale,
			220 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[color=green]Left[/color]: Walk (2D, Global Cam)",
			-350 * ui_scale,
			-180 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[color=red]Right[/color]: Attack Tinted (2D, Global Cam)",
			50 * ui_scale,
			-180 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[color=blue]Bottom[/color]: Walk Translucent (2D, Local Cam Offset)",
			-350 * ui_scale,
			-215 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[color=yellow]Top[/color]: Static Frame 0 (3D Space, Global Cam)",
			-350 * ui_scale,
			-250 * ui_scale,
			font,
			0.8 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
	}
}
