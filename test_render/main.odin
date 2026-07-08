// This is just a test program for the graphics module.
package main

import camera "../camera"
import transform "../transform"
import "base:runtime"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:testing"
import "core:time"

import "../app"
import "../ecs"
import "../ecs/params"
import fps "../fps"
import graphics "../graphics"
import log "../logging"
import gtime "../time"
import "../windowing"
import "core:c"
import "core:math"
import "core:math/rand"
import "vendor:sdl3"

Batch2D :: graphics.Batch2D

Vertex2D :: graphics.Vertex2D
Render_Context :: graphics.Render_Context

main_render_system :: graphics.main_render_system

Circle :: struct {
	radius: f32,
	color:  [4]f32,
}

Position2D :: struct {
	x, y: f32,
}

Velocity2D :: struct {
	x, y: f32,
}

append_circle :: proc(
	batch: ^Batch2D,
	center: [2]f32,
	radius: f32,
	color: [4]f32,
	vp: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY,
	segments := 32,
) {
	base_idx := u32(len(batch.vertices))

	project_point :: proc(vp: linalg.Matrix4f32, p: [2]f32) -> [2]f32 {
		p4 := [4]f32{p.x, p.y, 0.0, 1.0}
		res4 := vp * p4
		if res4.w != 0.0 {
			return res4.xy / res4.w
		}
		return res4.xy
	}

	// Add center vertex
	append(&batch.vertices, Vertex2D{position = project_point(vp, center), color = color})

	// Add perimeter vertices
	for i in 0 ..< segments {
		angle := f32(i) * 2.0 * math.PI / f32(segments)
		pos := [2]f32{center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)}
		append(&batch.vertices, Vertex2D{position = project_point(vp, pos), color = color})
	}

	// Add indices for triangles
	for i in 1 ..< segments {
		append(&batch.indices, base_idx, base_idx + u32(i), base_idx + u32(i + 1))
	}
	// Last triangle connecting back to the start
	append(&batch.indices, base_idx, base_idx + u32(segments), base_idx + 1)
}

setup_system :: proc(commands: params.Commands, window_res: params.Res(windowing.Window_Context)) {
	circle_count := 10_000

	margin: f32 = 0.08 // keep circles fully on screen (radius)
	win_w: c.int
	win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	w := f32(win_w)
	h := f32(win_h)

	// Spawn Camera
	cam_ec := ecs.commands_spawn(commands.ptr)
	cam: camera.Camera
	camera.init(&cam)
	camera.set_orthographic(&cam, -w / 2, w / 2, -h / 2, h / 2, -1.0, 1.0)

	// Create Transform and set its translation to (0, 0, 1)
	t: transform.Transform
	transform.init(&t)
	transform.set_translation(&t, {0, 0, 1})

	ecs.entity_commands_add_components(cam_ec, cam, t)

	for i in 0 ..< circle_count {
		fx := rand.float32_range(-w / 2 + 15, w / 2 - 15)
		fy := rand.float32_range(-h / 2 + 15, h / 2 - 15)

		hue := rand.float32_range(0, math.PI * 2)
		r := math.cos(hue) * 0.5 + 0.5
		g := math.cos(hue + math.PI * 2.0 / 3.0) * 0.5 + 0.5
		b := math.cos(hue + math.PI * 4.0 / 3.0) * 0.5 + 0.5

		vx := rand.float32_range(-150, 150)
		vy := rand.float32_range(-150, 150)

		ec := ecs.commands_spawn(commands.ptr)
		ecs.entity_commands_add_components(
			ec,
			Position2D{x = fx, y = fy},
			Velocity2D{x = vx, y = vy},
			Circle{radius = 15.0, color = {r, g, b, 1.0}},
		)
	}
}

draw_circles_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(Batch2D),
	render_ctx: params.Res(Render_Context),
	cam_param: params.Single(camera.Camera),
) {
	// Guard: skip if device has been released by cleanup system (would write to freed memory)
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return

	batch := batch2d.ptr
	if world == nil || batch == nil do return

	vp: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY
	t := ecs.world_get_component(world, cam_param.entity, transform.Transform)
	if t != nil {
		vp = camera.get_view_projection(cam_param.value^, t^)
	}

	for arch in ecs.query(world, Position2D, Circle) {
		positions := ecs.arch_get_field(arch, Position2D)
		circles := ecs.arch_get_field(arch, Circle)

		for i in 0 ..< len(positions) {
			pos := positions[i]
			circle := circles[i]
			append_circle(batch, {pos.x, pos.y}, circle.radius, circle.color, vp)
		}
	}

	font := ecs.world_get_resource(world, graphics.Font)
	if font != nil {
		graphics.draw_text(
			batch,
			"Hello [color=red]Red[/color], [color=green]Green[/color], and [color=blue]Blue[/color]!",
			-350,
			150,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Beautiful [color=orange]Odin[/color] TTF [opacity=0.4]Opacity 0.4[/opacity] and [opacity=0.8]0.8[/opacity]!",
			-350,
			100,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[bg=blue]Solid Blue Background[/bg] - [bg=green][bg_opacity=0.4]Transparent Green BG[/bg_opacity][/bg]",
			-350,
			50,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[c=#ff0022]Custom Hex Colors and [b]Bold[/b] [i]Italic[/i] [u]Underline[/u] [s]Strikethrough[/s][/c]!",
			-350,
			0,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Arial size 16: [font_size=16]Small Arial text[/font_size]",
			-350,
			-50,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Consolas: [font=C:\\Windows\\Fonts\\consola.ttf][font_size=20]Consolas size 20[/font_size] and normal[/font]",
			-350,
			-100,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Non-existent fallback: [font=non_existent.ttf]Should render as default font[/font]",
			-350,
			-150,
			font,
			1.0,
			{1, 1, 1, 1},
			vp,
		)
	}
}

movement_system :: proc(world: ^ecs.World, window_res: params.Res(windowing.Window_Context)) {
	if world == nil || window_res.ptr == nil do return

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	half_w := f32(win_w) / 2
	half_h := f32(win_h) / 2

	@(static) prev_tick: time.Tick
	@(static) initialized: bool
	if !initialized {
		prev_tick = time.tick_now()
		initialized = true
	}

	now := time.tick_now()
	dt := f32(time.duration_seconds(time.tick_diff(prev_tick, now)))
	prev_tick = now

	// Clamp dt to avoid huge steps
	if dt <= 0.0 || dt > 0.1 {
		dt = 1.0 / 60.0
	}

	for arch in ecs.query(world, Position2D, Velocity2D) {
		positions := ecs.arch_get_field(arch, Position2D)
		velocities := ecs.arch_get_field(arch, Velocity2D)

		for i in 0 ..< len(positions) {
			pos := &positions[i]
			vel := &velocities[i]

			pos.x += vel.x * dt
			pos.y += vel.y * dt

			// Bounce off screen boundaries, accounting for radius (15.0)
			radius: f32 = 15.0

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
		}
	}
}


main :: proc() {
	args := os.args
	duration := 10 * time.Second
	if len(args) > 1 {
		if parsed, ok := gtime.parse_duration(args[1]); ok {
			duration = parsed
		}
	}

	application := app.app_init(
		[]app.Plugin {
			windowing.Window_Plugin(),
			graphics.Render_Plugin(),
			fps.Fps_Plugin(.Uncapped),
		},
	)
	defer {
		app.app_destroy(&application)
	}

	window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
	assert(window_ctx != nil, "Window_Context should be initialized")
	if window_ctx != nil {
		assert(window_ctx.window != nil, "SDL Window should be created")
	}

	render_ctx := ecs.world_get_resource(&application.world, Render_Context)
	assert(render_ctx != nil, "Render_Context should be initialized")
	if render_ctx != nil {
		assert(render_ctx.device != nil, "WGPU Device should be created")
	}

	// Register systems
	app.app_add_system(&application, app.Startup, setup_system)
	app.app_add_system(&application, app.Update, movement_system)
	app.app_add_system(
		&application,
		app.Render,
		draw_circles_system,
		before = []rawptr{rawptr(main_render_system)},
	)

	app.app_run_schedule(&application, app.Startup)

	start_time := time.tick_now()
	screenshot_taken := false
	screenshot_time := duration / 2

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		if !screenshot_taken && elapsed >= screenshot_time {
			graphics.capture_screenshot(&application.world, "test_render_screenshot.png", .PNG)
			screenshot_taken = true
		}

		if elapsed >= duration {
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)
	}
}
