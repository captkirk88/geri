package transform

import "core:math/linalg"
import "core:testing"

Transform :: struct {
	world_matrix: linalg.Matrix4f32,
}

init :: proc "contextless" (t: ^Transform) {
	t.world_matrix = linalg.MATRIX4F32_IDENTITY
}

set_translation :: proc "contextless" (t: ^Transform, translation: [3]f32) {
	t.world_matrix[3].xyz = translation
}

get_translation :: proc "contextless" (t: Transform) -> [3]f32 {
	return t.world_matrix[3].xyz
}

set_scale :: proc "contextless" (t: ^Transform, scale: [3]f32) {
	t.world_matrix[0].xyz = linalg.vector_normalize(t.world_matrix[0].xyz) * scale.x
	t.world_matrix[1].xyz = linalg.vector_normalize(t.world_matrix[1].xyz) * scale.y
	t.world_matrix[2].xyz = linalg.vector_normalize(t.world_matrix[2].xyz) * scale.z
}

get_scale :: proc "contextless" (t: Transform) -> [3]f32 {
	return {
		linalg.vector_length(t.world_matrix[0].xyz),
		linalg.vector_length(t.world_matrix[1].xyz),
		linalg.vector_length(t.world_matrix[2].xyz),
	}
}

set_rotation :: proc "contextless" (t: ^Transform, q: linalg.Quaternionf32) {
	scale := get_scale(t^)
	rot_mat := linalg.matrix4_from_quaternion_f32(q)
	t.world_matrix[0].xyz = rot_mat[0].xyz * scale.x
	t.world_matrix[1].xyz = rot_mat[1].xyz * scale.y
	t.world_matrix[2].xyz = rot_mat[2].xyz * scale.z
}

get_rotation :: proc "contextless" (t: Transform) -> linalg.Quaternionf32 {
	scale := get_scale(t)
	m := linalg.MATRIX4F32_IDENTITY
	if scale.x != 0.0 do m[0].xyz = t.world_matrix[0].xyz / scale.x
	if scale.y != 0.0 do m[1].xyz = t.world_matrix[1].xyz / scale.y
	if scale.z != 0.0 do m[2].xyz = t.world_matrix[2].xyz / scale.z
	return linalg.quaternion_from_matrix4(m)
}

translate :: proc "contextless" (t: ^Transform, offset: [3]f32) {
	t.world_matrix[3].xyz += offset
}

rotate_local :: proc "contextless" (t: ^Transform, q: linalg.Quaternionf32) {
	rot_mat := linalg.matrix4_from_quaternion_f32(q)
	t.world_matrix = t.world_matrix * rot_mat
}

rotate_world :: proc "contextless" (t: ^Transform, q: linalg.Quaternionf32) {
	rot_mat := linalg.matrix4_from_quaternion_f32(q)
	pos := t.world_matrix[3].xyz
	t.world_matrix[3].xyz = 0
	t.world_matrix = rot_mat * t.world_matrix
	t.world_matrix[3].xyz = pos
}

@(test)
test_transform_helpers :: proc(t: ^testing.T) {
	tr: Transform
	init(&tr)

	testing.expect_value(t, get_translation(tr), [3]f32{0, 0, 0})
	testing.expect_value(t, get_scale(tr), [3]f32{1, 1, 1})

	set_translation(&tr, {1, 2, 3})
	testing.expect_value(t, get_translation(tr), [3]f32{1, 2, 3})

	set_scale(&tr, {2, 3, 4})
	testing.expect_value(t, get_scale(tr), [3]f32{2, 3, 4})

	q := linalg.quaternion_angle_axis_f32(0.5, {0, 1, 0})
	set_rotation(&tr, q)

	// verify scale is preserved after rotation
	testing.expect(t, linalg.abs(get_scale(tr).x - 2.0) < 0.001)
	testing.expect(t, linalg.abs(get_scale(tr).y - 3.0) < 0.001)
	testing.expect(t, linalg.abs(get_scale(tr).z - 4.0) < 0.001)

	// verify rotation round-trips
	qr := get_rotation(tr)
	testing.expect(t, linalg.abs(qr.w - q.w) < 0.001)
	testing.expect(t, linalg.abs(qr.y - q.y) < 0.001)

	translate(&tr, {10, 20, 30})
	testing.expect_value(t, get_translation(tr), [3]f32{11, 22, 33})
}
