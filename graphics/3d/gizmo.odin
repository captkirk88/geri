package threeD

import g ".."
import "../../app"
import "../../camera"
import ecs "../../ecs"
import params "../../ecs/params"
import "../../ecs/systems"
import "../../transform"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:testing"
import "vendor:wgpu"

// Gizmo3D is a component that visualizes the local orientation axes of an entity in 3D.
Gizmo3D :: struct {
	size:      f32,
	thickness: f32,
}

// Gizmo_Plugin_3D returns a plugin that registers the 3D gizmo rendering system.
Gizmo_Plugin_3D :: proc() -> app.Plugin {
	return app.Plugin{build = proc(plugin: app.Plugin, a: ^app.App) {
			app.app_add_system(
				a,
				app.Render,
				draw_gizmo_3d_system,
				before = []rawptr{rawptr(g.main_render_system)},
			)
		}}
}

// draw_arrow_3d draws a 3D arrow (cylinder shaft + cone tip) pointing in a given direction.
draw_arrow_3d :: proc(
	batch: ^g.Batch3D,
	origin, dir: [3]f32,
	size, thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	dir_norm := linalg.normalize(dir)

	shaft_len := size * 0.8
	cone_len := size * 0.2
	cone_radius := thickness * 2.0

	// Orthonormal basis for rotating Y-aligned cylinder/cone to point along dir_norm
	temp := [3]f32{0, 0, 1}
	if math.abs(linalg.dot(dir_norm, temp)) > 0.99 {
		temp = {1, 0, 0}
	}
	X := linalg.normalize(linalg.cross(temp, dir_norm))
	Z := linalg.cross(dir_norm, X)

	// Construct model matrix by setting its columns individually (column-major)
	M := linalg.MATRIX4F32_IDENTITY
	M[0].xyz = X
	M[1].xyz = dir_norm
	M[2].xyz = Z
	M[3].xyz = origin

	mvp := vp * M

	draw_cylinder(batch, {0, 0, 0}, thickness, shaft_len, color, mvp, slices = 16)
	draw_cone(batch, {0, shaft_len, 0}, cone_radius, cone_len, color, mvp, slices = 16)
}

// draw_gizmo_3d_system is an ECS system that draws 3D gizmos for all entities with Transform and Gizmo3D components.
draw_gizmo_3d_system :: proc(query: params.Query(struct {
			t: transform.Transform,
			g: Gizmo3D,
		}), batch3d: params.Res(
		g.Batch3D,
	), render_ctx: params.Res(g.Render_Context), cam_param: params.Single(camera.Camera)) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return
	if batch3d.ptr == nil do return

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
		gizmos := ecs.arch_get_field(arch, Gizmo3D)

		for i in 0 ..< len(transforms) {
			t := transforms[i]
			gizmo := gizmos[i]

			pos := transform.get_translation(t)

			dir_x := linalg.vector_normalize(t.world_matrix[0].xyz)
			dir_y := linalg.vector_normalize(t.world_matrix[1].xyz)
			dir_z := linalg.vector_normalize(t.world_matrix[2].xyz)

			size := gizmo.size if gizmo.size > 0 else 1.0
			thickness := gizmo.thickness if gizmo.thickness > 0 else 0.05

			draw_arrow_3d(batch3d.ptr, pos, dir_x, size, thickness, {1, 0, 0, 1}, vp)
			draw_arrow_3d(batch3d.ptr, pos, dir_y, size, thickness, {0, 1, 0, 1}, vp)
			draw_arrow_3d(batch3d.ptr, pos, dir_z, size, thickness, {0, 0, 1, 1}, vp)
		}
	}
}

// --- Tests ---

@(test)
test_gizmo_3d_rendering :: proc(t: ^testing.T) {
	world := ecs.new_world()
	defer ecs.world_destroy(&world)

	// Mock render context and batch resources
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)

	ecs.world_add_resource(&world, batch, proc(b: ^g.Batch3D, alloc: runtime.Allocator) {
		g.destroy_batch3d(b)
	})
	systems.world_init_default_params(&world)
	ecs.world_add_resource(&world, g.Render_Context{device = cast(wgpu.Device)rawptr(uintptr(1))})

	// Spawn camera
	cam := camera.Camera{}
	camera.init(&cam)
	cam_t := transform.Transform{}
	transform.init(&cam_t)
	cam_ent := ecs.world_spawn(&world)
	ecs.world_add_component(&world, cam_ent, cam)
	ecs.world_add_component(&world, cam_ent, cam_t)

	// Spawn entity with transform and Gizmo3D
	entity_t := transform.Transform{}
	transform.init(&entity_t)
	entity_t.world_matrix = linalg.matrix4_from_trs_f32(
		{10, 20, 30},
		linalg.quaternion_angle_axis_f32(math.PI * 0.25, {1, 0, 0}),
		{1, 1, 1},
	)
	gizmo := Gizmo3D {
		size      = 2.0,
		thickness = 0.1,
	}

	entity := ecs.world_spawn(&world)
	ecs.world_add_component(&world, entity, entity_t)
	ecs.world_add_component(&world, entity, gizmo)

	draw_gizmo_sys := systems.new_system(draw_gizmo_3d_system)
	defer systems.destroy_system(&world, draw_gizmo_sys)
	systems.run_system(&world, draw_gizmo_sys)

	batch_res := ecs.world_get_resource(&world, g.Batch3D)

	// Verify that the system appended vertices (arrows) for three axes (X, Y, Z)
	// Cylinder: 1 + 16 + 1 + 16 = 34 vertices
	// Cone: 1 + 16 + 1 = 18 vertices
	// Each 3D arrow: 34 + 18 = 52 vertices
	// 3 arrows * 52 vertices = 156 vertices
	testing.expect_value(t, len(batch_res.vertices), 156)
}
