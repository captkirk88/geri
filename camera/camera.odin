package camera

import "../ecs"
import params "../ecs/params"
import transform "../transform"
import "core:math/linalg"

Camera :: struct {
	target:     [3]f32,
	up:         [3]f32,
	projection: linalg.Matrix4f32,
}

init :: proc(c: ^Camera) {
	c.target = {0, 0, 0}
	c.up = {0, 1, 0}
	c.projection = linalg.MATRIX4F32_IDENTITY
}

set_perspective :: proc(c: ^Camera, fovy_rad, aspect, near, far: f32) {
	c.projection = linalg.matrix4_perspective_f32(fovy_rad, aspect, near, far)
}

set_orthographic :: proc(c: ^Camera, left, right, bottom, top, near, far: f32) {
	c.projection = linalg.matrix_ortho3d_f32(left, right, bottom, top, near, far)
}

get_view_projection :: proc(c: Camera, t: transform.Transform) -> linalg.Matrix4f32 {
	position := transform.get_translation(t)
	view := linalg.matrix4_look_at_f32(position, c.target, c.up)
	return c.projection * view
}

project_point :: proc(c: Camera, t: transform.Transform, point: [3]f32) -> [3]f32 {
	vp := get_view_projection(c, t)
	p4 := [4]f32{point.x, point.y, point.z, 1.0}
	res4 := vp * p4
	if res4.w != 0.0 {
		return res4.xyz / res4.w
	}
	return res4.xyz
}

auto_transform_system :: proc(commands: params.Commands, added_cameras: params.OnAdded(Camera)) {
	for entity in added_cameras.entities {
		t: transform.Transform
		transform.init(&t)
		ecs.commands_add_component(commands.ptr, entity, t)
	}
}
