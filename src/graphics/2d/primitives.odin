package twoD

import g ".."
import "core:math"
import "core:math/linalg"
import "core:testing"

// project_point applies the view-projection matrix to a 2D point, returning clip-space coordinates.
project_point :: proc(vp: linalg.Matrix4f32, p: [2]f32) -> [2]f32 {
	p4 := [4]f32{p.x, p.y, 0.0, 1.0}
	res4 := vp * p4
	if res4.w != 0.0 do return res4.xy / res4.w
	return res4.xy
}

// draw_triangle appends a filled triangle to the 2D batch.
draw_triangle :: proc(
	batch: ^g.Batch2D,
	p0, p1, p2: [2]f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	base_idx := u32(len(batch.vertices))
	append(
		&batch.vertices,
		g.Vertex2D{position = project_point(vp, p0), color = color},
		g.Vertex2D{position = project_point(vp, p1), color = color},
		g.Vertex2D{position = project_point(vp, p2), color = color},
	)
	append(&batch.indices, base_idx + 0, base_idx + 1, base_idx + 2)
}

// draw_rect appends a filled axis-aligned rectangle to the 2D batch.
draw_rect :: proc(
	batch: ^g.Batch2D,
	position: [2]f32,
	size: [2]f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	x0 := position.x
	y0 := position.y
	x1 := position.x + size.x
	y1 := position.y + size.y

	base_idx := u32(len(batch.vertices))
	append(
		&batch.vertices,
		g.Vertex2D{position = project_point(vp, {x0, y0}), color = color},
		g.Vertex2D{position = project_point(vp, {x1, y0}), color = color},
		g.Vertex2D{position = project_point(vp, {x1, y1}), color = color},
		g.Vertex2D{position = project_point(vp, {x0, y1}), color = color},
	)
	append(
		&batch.indices,
		base_idx + 0,
		base_idx + 1,
		base_idx + 2,
		base_idx + 0,
		base_idx + 2,
		base_idx + 3,
	)
}

// draw_line appends a thick line segment between two 2D points to the 2D batch.
draw_line :: proc(
	batch: ^g.Batch2D,
	p0, p1: [2]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	dir := p1 - p0
	len_dir := linalg.length(dir)
	if len_dir == 0 do return

	normal := [2]f32{-dir.y, dir.x} / len_dir
	offset := normal * (thickness * 0.5)

	v0 := p0 - offset
	v1 := p0 + offset
	v2 := p1 + offset
	v3 := p1 - offset

	base_idx := u32(len(batch.vertices))
	append(
		&batch.vertices,
		g.Vertex2D{position = project_point(vp, v0), color = color},
		g.Vertex2D{position = project_point(vp, v1), color = color},
		g.Vertex2D{position = project_point(vp, v2), color = color},
		g.Vertex2D{position = project_point(vp, v3), color = color},
	)
	append(
		&batch.indices,
		base_idx + 0,
		base_idx + 1,
		base_idx + 2,
		base_idx + 0,
		base_idx + 2,
		base_idx + 3,
	)
}

// draw_circle appends a filled circle to the 2D batch.
draw_circle :: proc(
	batch: ^g.Batch2D,
	center: [2]f32,
	radius: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
	segments := 32,
) {
	if segments < 3 do return
	base_idx := u32(len(batch.vertices))

	// Add center vertex
	append(&batch.vertices, g.Vertex2D{position = project_point(vp, center), color = color})

	// Add perimeter vertices
	for i in 0 ..< segments {
		angle := f32(i) * 2.0 * math.PI / f32(segments)
		pos := [2]f32{center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)}
		append(&batch.vertices, g.Vertex2D{position = project_point(vp, pos), color = color})
	}

	// Add indices for triangles
	for i in 1 ..< segments {
		append(&batch.indices, base_idx, base_idx + u32(i), base_idx + u32(i + 1))
	}
	// Last triangle connecting back to the start
	append(&batch.indices, base_idx, base_idx + u32(segments), base_idx + 1)
}

// draw_circle_outline appends a circle outline to the 2D batch using line segments.
draw_circle_outline :: proc(
	batch: ^g.Batch2D,
	center: [2]f32,
	radius: f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
	segments := 32,
) {
	if segments < 3 do return

	prev_pos := [2]f32{center.x + radius, center.y}
	for i in 1 ..= segments {
		angle := f32(i) * 2.0 * math.PI / f32(segments)
		pos := [2]f32{center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)}
		draw_line(batch, prev_pos, pos, thickness, color, vp)
		prev_pos = pos
	}
}

// draw_rect_outline appends a rectangle outline to the 2D batch.
draw_rect_outline :: proc(
	batch: ^g.Batch2D,
	position: [2]f32,
	size: [2]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	x0 := position.x
	y0 := position.y
	x1 := position.x + size.x
	y1 := position.y + size.y

	p0 := [2]f32{x0, y0}
	p1 := [2]f32{x1, y0}
	p2 := [2]f32{x1, y1}
	p3 := [2]f32{x0, y1}

	draw_line(batch, p0, p1, thickness, color, vp)
	draw_line(batch, p1, p2, thickness, color, vp)
	draw_line(batch, p2, p3, thickness, color, vp)
	draw_line(batch, p3, p0, thickness, color, vp)
}

// draw_triangle_outline appends a triangle outline to the 2D batch.
draw_triangle_outline :: proc(
	batch: ^g.Batch2D,
	p0, p1, p2: [2]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	draw_line(batch, p0, p1, thickness, color, vp)
	draw_line(batch, p1, p2, thickness, color, vp)
	draw_line(batch, p2, p0, thickness, color, vp)
}

// --- Tests ---

@(test)
test_draw_triangle :: proc(t: ^testing.T) {
	batch := g.Batch2D{}
	batch.vertices = make([dynamic]g.Vertex2D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_triangle(&batch, {0, 0}, {1, 0}, {0, 1}, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 3)
	testing.expect_value(t, len(batch.indices), 3)
}

@(test)
test_draw_rect :: proc(t: ^testing.T) {
	batch := g.Batch2D{}
	batch.vertices = make([dynamic]g.Vertex2D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_rect(&batch, {0, 0}, {10, 20}, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 4)
	testing.expect_value(t, len(batch.indices), 6)
}

@(test)
test_draw_line :: proc(t: ^testing.T) {
	batch := g.Batch2D{}
	batch.vertices = make([dynamic]g.Vertex2D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_line(&batch, {0, 0}, {10, 0}, 2.0, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 4)
	testing.expect_value(t, len(batch.indices), 6)
}

@(test)
test_draw_circle :: proc(t: ^testing.T) {
	batch := g.Batch2D{}
	batch.vertices = make([dynamic]g.Vertex2D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_circle(&batch, {0, 0}, 5.0, {1, 1, 1, 1}, segments = 16)
	testing.expect_value(t, len(batch.vertices), 1 + 16)
	testing.expect_value(t, len(batch.indices), 3 * 16)
}
