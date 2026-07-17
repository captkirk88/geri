package scenes

import "base:runtime"
import "core:math/rand"
import "core:math"
import "core:math/linalg"
import "core:c"
import "vendor:sdl3"

import "../../ecs"
import "../../ecs/params"
import "../../camera"
import "../../transform"
import "../../graphics"
import "../../windowing"

Circle :: struct {
	radius: f32,
	color:  [4]f32,
}

Velocity2D :: struct {
	x, y: f32,
}

append_circle :: proc(
	batch: ^graphics.Batch2D,
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
	append(&batch.vertices, graphics.Vertex2D{position = project_point(vp, center), color = color})

	// Add perimeter vertices
	for i in 0 ..< segments {
		angle := f32(i) * 2.0 * math.PI / f32(segments)
		pos := [2]f32{center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)}
		append(&batch.vertices, graphics.Vertex2D{position = project_point(vp, pos), color = color})
	}

	// Add indices for triangles
	for i in 1 ..< segments {
		append(&batch.indices, base_idx, base_idx + u32(i), base_idx + u32(i + 1))
	}
	// Last triangle connecting back to the start
	append(&batch.indices, base_idx, base_idx + u32(segments), base_idx + 1)
}

circles_setup :: proc(world: ^ecs.World) {
	window_res := ecs.world_get_resource(world, windowing.Window_Context)
	if window_res == nil || window_res.window == nil do return

	circle_count := 2000 // Reduced from 10k to keep tests snappy

	win_w: c.int
	win_h: c.int
	sdl3.GetWindowSize(window_res.window, &win_w, &win_h)
	w := f32(win_w)
	h := f32(win_h)

	// Spawn Camera
	cam_ent := ecs.world_spawn(world)
	cam: camera.Camera
	camera.init(&cam)
	camera.set_orthographic(&cam, -w / 2, w / 2, -h / 2, h / 2, -1.0, 1.0)

	t: transform.Transform
	transform.init(&t)
	transform.set_translation(&t, {0, 0, 1})

	ecs.world_add_component(world, cam_ent, cam)
	ecs.world_add_component(world, cam_ent, t)

	for i in 0 ..< circle_count {
		fx := rand.float32_range(-w / 2 + 15, w / 2 - 15)
		fy := rand.float32_range(-h / 2 + 15, h / 2 - 15)

		hue := rand.float32_range(0, math.PI * 2)
		r := math.cos(hue) * 0.5 + 0.5
		g := math.cos(hue + math.PI * 2.0 / 3.0) * 0.5 + 0.5
		b := math.cos(hue + math.PI * 4.0 / 3.0) * 0.5 + 0.5

		vx := rand.float32_range(-150, 150)
		vy := rand.float32_range(-150, 150)

		t_circ: transform.Transform
		transform.init(&t_circ)
		transform.set_translation(&t_circ, {fx, fy, 0})

		ec := ecs.world_spawn(world)
		ecs.world_add_component(world, ec, t_circ)
		ecs.world_add_component(world, ec, Velocity2D{x = vx, y = vy})
		ecs.world_add_component(world, ec, Circle{radius = 15.0, color = {r, g, b, 1.0}})
	}
}

ActiveScene :: struct {
	index: int,
}

circles_draw_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(graphics.Batch2D),
	render_ctx: params.Res(graphics.Render_Context),
	window_res: params.Res(windowing.Window_Context),
) {
	active_scene := ecs.world_get_resource(world, ActiveScene)
	if active_scene == nil || active_scene.index != 0 do return
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return
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

	for arch in ecs.query(world, transform.Transform, Circle) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		circles := ecs.arch_get_field(arch, Circle)

		for i in 0 ..< len(transforms) {
			pos := transform.get_translation(transforms[i])
			circle := circles[i]
			append_circle(batch, pos.xy, circle.radius, circle.color, vp)
		}
	}

	font := ecs.world_get_resource(world, graphics.Font)
	if font != nil {
		graphics.draw_text(
			batch,
			"Scene 1: [color=red]Circles[/color] & [color=green]Text[/color]. Press ESC to switch scene.",
			-350 * ui_scale,
			220 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Hello [color=red]Red[/color], [color=green]Green[/color], and [color=blue]Blue[/color]!",
			-350 * ui_scale,
			150 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Beautiful [color=orange]Odin[/color] TTF [opacity=0.4]Opacity 0.4[/opacity] and [opacity=0.8]0.8[/opacity]!",
			-350 * ui_scale,
			100 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[bg=blue]Solid Blue Background[/bg] - [bg=green][bg_opacity=0.4]Transparent Green BG[/bg_opacity][/bg]",
			-350 * ui_scale,
			50 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"[c=#ff0022]Custom Hex Colors and [b]Bold[/b] [i]Italic[/i] [u]Underline[/u] [s]Strikethrough[/s][/c]!",
			-350 * ui_scale,
			0 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Arial size 16: [font_size=16]Small Arial text[/font_size]",
			-350 * ui_scale,
			-50 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
		graphics.draw_text(
			batch,
			"Consolas: [font=C:\\Windows\\Fonts\\consola.ttf][font_size=20]Consolas size 20[/font_size] and normal[/font]",
			-350 * ui_scale,
			-100 * ui_scale,
			font,
			1.0 * ui_scale,
			{1, 1, 1, 1},
			vp,
		)
	}
}
