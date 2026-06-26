package main

import "core:testing"

import "../src/app"
import "../src/ecs"
import "../src/ecs/params"
import graphics "../src/graphics"
import "../src/windowing"
import "core:c"
import "core:math"
import "core:math/rand"
import "vendor:sdl3"

main :: proc() {
	t := testing.T{}
	graphics.test_render_pipeline_initialization(&t)
}

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
	segments := 32,
) {
	base_idx := u16(len(batch.vertices))

	// Add center vertex
	append(&batch.vertices, Vertex2D{position = center, color = color})

	// Add perimeter vertices
	for i in 0 ..< segments {
		angle := f32(i) * 2.0 * math.PI / f32(segments)
		pos := [2]f32{center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)}
		append(&batch.vertices, Vertex2D{position = pos, color = color})
	}

	// Add indices for triangles
	for i in 1 ..< segments {
		append(&batch.indices, base_idx, base_idx + u16(i), base_idx + u16(i + 1))
	}
	// Last triangle connecting back to the start
	append(&batch.indices, base_idx, base_idx + u16(segments), base_idx + 1)
}

setup_system :: proc(commands: params.Commands, window_res: params.Res(windowing.Window_Context)) {
	circle_count := 10_000
	margin: f32 = 0.08 // keep circles fully on screen (radius)
	win_w: c.int
	win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	w := f32(win_w)
	h := f32(win_h)
	for i in 0 ..< circle_count {
		fx := rand.float32_range(-w / 2, w / 2)
		fy := rand.float32_range(-h / 2, h / 2)

		// Spread hue evenly then jitter for variety
		hue := (f32(i) / f32(circle_count) + rand.float32_range(0, 0.1)) * math.PI * 2
		r := math.cos(hue) * 0.5 + 0.5
		g := math.cos(hue + math.PI * 2 / 3) * 0.5 + 0.5
		b := math.cos(hue + math.PI * 4 / 3) * 0.5 + 0.5

		ec := ecs.commands_spawn(commands.ptr)
		ecs.entity_commands_add_components(
			ec,
			Position2D{x = fx, y = fy},
			Circle{radius = 0.06, color = {r, g, b, 1.0}},
		)
	}
}

draw_circles_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(Batch2D),
	render_ctx: params.Res(Render_Context),
) {
	// Guard: skip if device has been released by cleanup system (would write to freed memory)
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return

	batch := batch2d.ptr
	if world == nil || batch == nil do return

	for arch in ecs.query(world, Position2D, Circle) {
		positions := ecs.arch_get_field(arch, Position2D)
		circles := ecs.arch_get_field(arch, Circle)

		for i in 0 ..< len(positions) {
			pos := positions[i]
			circle := circles[i]
			append_circle(batch, {pos.x, pos.y}, circle.radius, circle.color)
		}
	}
}

test_render_pipeline_initialization :: proc(t: ^testing.T) {
	application := app.app_init([]app.Plugin{windowing.Window_Plugin(), graphics.Render_Plugin()})
	defer {
		window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
		if window_ctx != nil && window_ctx.window != nil {
			sdl3.DestroyWindow(window_ctx.window)
		}
		sdl3.Quit()

		app.app_destroy(&application)
	}

	window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
	testing.expect(t, window_ctx != nil, "Window_Context should be initialized")
	if window_ctx != nil {
		testing.expect(t, window_ctx.window != nil, "SDL Window should be created")
	}

	render_ctx := ecs.world_get_resource(&application.world, Render_Context)
	testing.expect(t, render_ctx != nil, "Render_Context should be initialized")
	if render_ctx != nil {
		testing.expect(t, render_ctx.device != nil, "WGPU Device should be created")
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

	for !application.should_exit {
		app.app_update(&application)
	}

}
