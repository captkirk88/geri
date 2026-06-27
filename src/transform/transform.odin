package transform

import "core:math/linalg"

Transform :: struct {
	world_matrix: linalg.Matrix4f32,
}

init :: proc(t: ^Transform) {
	t.world_matrix = linalg.MATRIX4F32_IDENTITY
}

set_translation :: proc(t: ^Transform, translation: [3]f32) {
	t.world_matrix[3].xyz = translation
}

get_translation :: proc(t: Transform) -> [3]f32 {
	return t.world_matrix[3].xyz
}
