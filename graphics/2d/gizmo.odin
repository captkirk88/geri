package twoD

import g ".."
import "../../app"
import "../../camera"
import "../../ecs"
import params "../../ecs/params"
import systems "../../ecs/systems"
import "../../transform"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:testing"
import "vendor:wgpu"

// Gizmo2D is a component that visualizes the local orientation axes of an entity in 2D.
Gizmo2D :: struct {
	size:      f32,
	thickness: f32,
}

// Gizmo_Plugin_2D returns a plugin that registers the 2D gizmo rendering system.
Gizmo_Plugin_2D :: proc() -> app.Plugin {
	return app.Plugin{build = proc(plugin: app.Plugin, a: ^app.App) {
			app.app_add_system(
				a,
				app.Render,
				draw_gizmo_2d_system,
				before = []rawptr{rawptr(g.main_render_system)},
			)
		}}
}

// draw_arrow_2d draws a 2D line segment with an arrowhead.
draw_arrow_2d :: proc(
	batch: ^g.Batch2D,
	p0, p1: [2]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	dir := p1 - p0
	len_dir := linalg.length(dir)
	if len_dir == 0 do return

	dir_norm := dir / len_dir
	arrow_head_size := len_dir * 0.25
	if arrow_head_size > 15.0 do arrow_head_size = 15.0
	if arrow_head_size < 5.0 do arrow_head_size = 5.0

	shaft_end := p1 - dir_norm * arrow_head_size

	draw_line(batch, p0, shaft_end, thickness, color, vp)

	normal := [2]f32{-dir_norm.y, dir_norm.x}
	width := arrow_head_size * 0.6

	tip := p1
	left := shaft_end + normal * width
	right := shaft_end - normal * width

	draw_triangle(batch, tip, left, right, color, vp)
}

// draw_gizmo_2d_system is an ECS system that draws 2D gizmos for all entities with Transform and Gizmo2D components.
draw_gizmo_2d_system :: proc(query: params.Query(struct {
			t: transform.Transform,
			g: Gizmo2D,
		}), batch2d: params.Res(
		g.Batch2D,
	), render_ctx: params.Res(g.Render_Context), cam_param: params.Single(camera.Camera)) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return
	if batch2d.ptr == nil do return

	t_cam := cam_param.value
	if t_cam == nil do return

	world := query._world
	vp: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY
	t_cam_transform := ecs.world_get_component(world, cam_param.entity, transform.Transform)
	if t_cam_transform != nil {
		vp = camera.get_view_projection(t_cam^, t_cam_transform^)
	}

	for arch in params.query(query) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		gizmos := ecs.arch_get_field(arch, Gizmo2D)

		for i in 0 ..< len(transforms) {
			t := transforms[i]
			gizmo := gizmos[i]

			pos := transform.get_translation(t).xy

			dir_x := linalg.vector_normalize(t.world_matrix[0].xy)
			dir_y := linalg.vector_normalize(t.world_matrix[1].xy)

			size := gizmo.size if gizmo.size > 0 else 50.0
			thickness := gizmo.thickness if gizmo.thickness > 0 else 3.0

			draw_arrow_2d(batch2d.ptr, pos, pos + dir_x * size, thickness, {1, 0, 0, 1}, vp)
			draw_arrow_2d(batch2d.ptr, pos, pos + dir_y * size, thickness, {0, 1, 0, 1}, vp)
		}
	}
}

// --- Tests ---

@(test)
test_gizmo_2d_rendering :: proc(t: ^testing.T) {
	world := ecs.new_world()
	defer ecs.world_destroy(&world)

	// Mock render context and batch resources
	batch := g.Batch2D{}
	batch.vertices = make([dynamic]g.Vertex2D)
	batch.indices = make([dynamic]u32)

	systems.world_init_default_params(&world)

	ecs.world_add_resource(&world, batch, proc(b: ^g.Batch2D, alloc: runtime.Allocator) {
		g.destroy_batch2d(b)
	})
	ecs.world_add_resource(&world, g.Render_Context{device = cast(wgpu.Device)rawptr(uintptr(1))})

	// Spawn camera
	cam := camera.Camera{}
	camera.init(&cam)
	cam_t := transform.Transform{}
	transform.init(&cam_t)
	cam_ent := ecs.world_spawn(&world)
	ecs.world_add_component(&world, cam_ent, cam)
	ecs.world_add_component(&world, cam_ent, cam_t)

	// Spawn entity with transform and Gizmo2D
	entity_t := transform.Transform{}
	transform.init(&entity_t)
	entity_t.world_matrix = linalg.matrix4_from_trs_f32(
		{10, 20, 0},
		linalg.quaternion_angle_axis_f32(math.PI * 0.25, {0, 0, 1}),
		{1, 1, 1},
	)
	gizmo := Gizmo2D {
		size      = 100.0,
		thickness = 4.0,
	}

	entity := ecs.world_spawn(&world)
	ecs.world_add_component(&world, entity, entity_t)
	ecs.world_add_component(&world, entity, gizmo)

	// Call system via runner
	draw_gizmo_sys := systems.new_system(draw_gizmo_2d_system)
	defer systems.destroy_system(&world, draw_gizmo_sys)
	systems.run_system(&world, draw_gizmo_sys)

	batch_res := ecs.world_get_resource(&world, g.Batch2D)

	// Verify that the system appended vertices (arrows) for two axes (X, Y)
	// 2 arrows * 7 vertices = 14 vertices
	testing.expect_value(t, len(batch_res.vertices), 14)
}
