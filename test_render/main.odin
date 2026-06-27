package main

import camera "../src/camera"
import transform "../src/transform"
import "core:math/linalg"
import "core:testing"

import "../src/app"
import "../src/ecs"
import "../src/ecs/params"
import fps "../src/fps"
import graphics "../src/graphics"
import log "../src/logging"
import "../src/windowing"
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

	font: graphics.Font
	if graphics.font_init(&font, "C:\\Windows\\Fonts\\arial.ttf", 32.0) {
		ecs.world_add_resource(commands.ptr.world, font)
	}

	for i in 0 ..< circle_count {
		fx := rand.float32_range(-w / 2 + 15, w / 2 - 15)
		fy := rand.float32_range(-h / 2 + 15, h / 2 - 15)

		hue := rand.float32_range(0, math.PI * 2)
		r := math.cos(hue) * 0.5 + 0.5
		g := math.cos(hue + math.PI * 2.0 / 3.0) * 0.5 + 0.5
		b := math.cos(hue + math.PI * 4.0 / 3.0) * 0.5 + 0.5

		ec := ecs.commands_spawn(commands.ptr)
		ecs.entity_commands_add_components(
			ec,
			Position2D{x = fx, y = fy},
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
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"Hello [color=red]Red[/color], [color=green]Green[/color], and [color=blue]Blue[/color]!",
			-350,
			150,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"Beautiful [color=orange]Odin[/color] TTF [opacity=0.4]Opacity 0.4[/opacity] and [opacity=0.8]0.8[/opacity]!",
			-350,
			100,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"[bg=blue]Solid Blue Background[/bg] - [bg=green][bg_opacity=0.4]Transparent Green BG[/bg_opacity][/bg]",
			-350,
			50,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"[c=#ff0022]Custom Hex Colors and [b]Bold[/b] [i]Italic[/i] [u]Underline[/u] [s]Strikethrough[/s][/c]!",
			-350,
			0,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"Arial size 16: [font_size=16]Small Arial text[/font_size]",
			-350,
			-50,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"Consolas: [font=C:\\Windows\\Fonts\\consola.ttf][font_size=20]Consolas size 20[/font_size] and normal[/font]",
			-350,
			-100,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text_bbcode_ttf(
			batch,
			font,
			"Non-existent fallback: [font=non_existent.ttf]Should render as default font[/font]",
			-350,
			-150,
			{1, 1, 1, 1},
			vp,
		)
	}
}

main :: proc() {
	application := app.app_init(
		[]app.Plugin{windowing.Window_Plugin(), graphics.Render_Plugin(), fps.Fps_Plugin()},
	)
	defer {
		font := ecs.world_get_resource(&application.world, graphics.Font)
		if font != nil {
			graphics.font_destroy(font)
		}

		window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
		if window_ctx != nil && window_ctx.window != nil {
			sdl3.DestroyWindow(window_ctx.window)
		}
		sdl3.Quit()

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
	app.app_add_system(
		&application,
		app.Render,
		draw_circles_system,
		before = []rawptr{rawptr(main_render_system)},
	)

	app.app_run_schedule(&application, app.Startup)

	frame_count := 0
	max_frame_count := 100
	for !application.should_exit {
		if frame_count == max_frame_count / 2 {
			graphics.capture_screenshot(&application.world, "test_render_screenshot.png", .PNG)
		}
		if frame_count == max_frame_count {
			application.should_exit = true
		}
		app.app_update(&application)
		frame_count += 1
	}
}
