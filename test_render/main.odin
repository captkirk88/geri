package main

import camera "../camera"
import transform "../transform"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:time"

import "../app"
import "../ecs"
import "../ecs/params"
import errors "../errors"
import fps "../fps"
import graphics "../graphics"
import input "../input"
import log "../logging"
import plugins "../plugins"
import gtime "../time"
import "../windowing"
import "core:c"
import "vendor:sdl3"

import "scenes"

Scene :: struct {
	name: string,
	init: proc(world: ^ecs.World),
	exit: proc(world: ^ecs.World),
}

clear_all_entities :: proc(world: ^ecs.World) {
	for i in 0 ..< len(world.entities) {
		meta := world.entities[i]
		ent := ecs.Entity {
			id  = u64(i),
			gen = u64(meta.gen),
		}
		if ecs.world_is_alive(world, ent) {
			ecs.world_despawn(world, ent)
		}
	}
}

scenes_list := []Scene {
	{name = "Circles", init = scenes.circles_setup, exit = proc(world: ^ecs.World) {
			ecs.world_clear(world)
		}},
	{name = "Sprites", init = scenes.sprite_setup, exit = proc(world: ^ecs.World) {
			ecs.world_clear(world)
		}},
	{name = "Models", init = scenes.model_setup, exit = proc(world: ^ecs.World) {
			ecs.world_clear(world)
		}},
}

SceneManager :: struct {
	current_scene_idx: int,
}

scene_transition_system :: proc(
	world: ^ecs.World,
	sdl_events: params.EventReader(sdl3.Event),
	mgr_res: params.Res(SceneManager),
	dt_res: params.Res(app.DeltaTime),
	elapsed: params.Local(f32),
) {
	mgr := mgr_res.ptr
	if mgr == nil do return
	dt := dt_res.ptr

	dt_sec := dt.f32_seconds if dt != nil else 1.0 / 60.0
	elapsed.value^ += dt_sec

	should_transition := false
	if elapsed.value^ >= 1.0 {
		elapsed.value^ = 0.0
		should_transition = true
	}

	for event in sdl_events.events {
		if event.type == .KEY_DOWN && event.key.key == sdl3.K_ESCAPE {
			should_transition = true
			elapsed.value^ = 0.0
		}
	}

	if should_transition {
		// Exit current scene
		scenes_list[mgr.current_scene_idx].exit(world)

		// Move to next scene
		mgr.current_scene_idx = (mgr.current_scene_idx + 1) % len(scenes_list)
		log.info("Transitioning to scene: %s", scenes_list[mgr.current_scene_idx].name)

		active_scene := ecs.world_get_resource(world, scenes.ActiveScene)
		if active_scene != nil {
			active_scene.index = mgr.current_scene_idx
		}

		// Init next scene
		scenes_list[mgr.current_scene_idx].init(world)
	}
}

movement_system :: proc(
	world: ^ecs.World,
	window_res: params.Res(windowing.Window_Context),
	prev_tick_local: params.Local(time.Tick),
	initialized_local: params.Local(bool),
) {
	if world == nil || window_res.ptr == nil do return

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	half_w := f32(win_w) / 2
	half_h := f32(win_h) / 2

	if initialized_local.value^ == false {
		prev_tick_local.value^ = time.tick_now()
		initialized_local.value^ = true
	}

	now := time.tick_now()
	dt := f32(time.duration_seconds(time.tick_diff(prev_tick_local.value^, now)))
	prev_tick_local.value^ = now

	// Clamp dt to avoid huge steps
	if dt <= 0.0 || dt > 0.1 {
		dt = 1.0 / 60.0
	}

	// This system queries Circle movement.
	for arch in ecs.query(world, transform.Transform, scenes.Velocity2D) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		velocities := ecs.arch_get_field(arch, scenes.Velocity2D)
		circles := ecs.arch_get_field(arch, scenes.Circle)

		for i in 0 ..< len(transforms) {
			t := &transforms[i]
			vel := &velocities[i]
			circle := circles[i]

			pos := transform.get_translation(t^)
			pos.x += vel.x * dt
			pos.y += vel.y * dt

			radius := circle.radius

			if pos.x - radius < -half_w {
				pos.x = -half_w + radius
				vel.x = -vel.x
			} else if pos.x + radius > half_w {
				pos.x = half_w - radius
				vel.x = -vel.x
			}

			if pos.y - radius < -half_h {
				pos.y = -half_h + radius
				vel.y = -vel.y
			} else if pos.y + radius > half_h {
				pos.y = half_h - radius
				vel.y = -vel.y
			}

			transform.set_translation(t, pos)
		}
	}
}

camera_resize_system :: proc(
	world: ^ecs.World,
	resize_events: params.EventReader(windowing.Window_Resized_Event),
	active_scene: params.Res(scenes.ActiveScene),
) {
	for event in resize_events.events {
		w := f32(event.width)
		h := f32(event.height)
		for arch in ecs.query(world, camera.Camera) {
			cameras := ecs.arch_get_field(arch, camera.Camera)
			for i in 0 ..< len(cameras) {
				if active_scene.ptr != nil && active_scene.ptr.index == 2 {
					camera.set_perspective(&cameras[i], 45.0 * math.RAD_PER_DEG, w / h, 0.1, 100.0)
				} else {
					camera.set_orthographic(
						&cameras[i],
						-w / 2,
						w / 2,
						-h / 2,
						h / 2,
						-100.0,
						100.0,
					)
				}
			}
		}
	}
}

main :: proc() {
	args := os.args
	duration := 10 * time.Second
	start_scene_idx := 0

	// Argument parsing:
	//   test_render.exe [scene_name] [duration]
	// scene_name is matched case-insensitively against scene names (e.g. "sprites", "circles")
	// duration accepts suffixes like 10s, 5m, etc.
	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		if parsed, ok := gtime.parse_duration(arg); ok {
			duration = parsed
		} else {
			// Try to match as a scene name prefix (in Odin for-range: first var is value, second is index)
			for scene, scene_idx in scenes_list {
				if len(arg) <= len(scene.name) {
					matched := true
					for k in 0 ..< len(arg) {
						ac := arg[k] | 0x20 // to lowercase
						sc := scene.name[k] | 0x20
						if ac != sc {
							matched = false
							break
						}
					}
					if matched {
						start_scene_idx = scene_idx
						break
					}
				}
			}
		}
	}

	application := errors.unwrap(
		app.app_init(
			[]app.Plugin {
				windowing.Window_Plugin(),
				input.Input_Plugin(),
				plugins.Assets_Plugin(),
				graphics.Render_Plugin(),
				fps.Fps_Plugin(.Uncapped),
			},
		),
	)
	defer {
		app.app_destroy(&application)
	}

	// Register SceneManager resource
	mgr := SceneManager {
		current_scene_idx = start_scene_idx,
	}
	app.app_add_resource(&application, mgr)

	// Register ActiveScene resource
	active_scene := scenes.ActiveScene {
		index = start_scene_idx,
	}
	app.app_add_resource(&application, active_scene)

	// Register systems
	app.app_add_system(&application, app.Update, scene_transition_system)
	app.app_add_system(&application, app.Update, movement_system)
	app.app_add_system(&application, app.Update, camera_resize_system)
	app.app_add_system(&application, app.Update, scenes.model_update_system)

	// Register Sprite animation system
	app.app_add_system(&application, app.Update, graphics.sprite_animation_system)

	// Register draw/rendering systems before main render flush
	app.app_add_system(
		&application,
		app.Render,
		scenes.circles_draw_system,
		before = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)
	app.app_add_system(
		&application,
		app.Render,
		scenes.sprite_draw_system,
		before = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)
	app.app_add_system(
		&application,
		app.Render,
		scenes.model_draw_system,
		before = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)
	app.app_add_system(
		&application,
		app.Render,
		graphics.sprite_render_system,
		before = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)

	// Initialize the starting scene
	log.info("Starting scene: %s (index %d)", scenes_list[start_scene_idx].name, start_scene_idx)
	scenes_list[start_scene_idx].init(&application.world)

	start_time := time.tick_now()
	screenshot_taken := false
	screenshot_time := duration / 2

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		// if !screenshot_taken && elapsed >= screenshot_time {
		// 	graphics.capture_screenshot(&application.world, "test_render_screenshot.png", .PNG)
		// 	screenshot_taken = true
		// }

		if elapsed >= duration {
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)
	}
}
