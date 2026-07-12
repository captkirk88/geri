package threeD

import g ".."
import "core:math"
import "core:math/linalg"
import "core:testing"
import "vendor:cgltf"
import asset "../../asset"

// project_point applies the view-projection matrix to a 3D point.
project_point :: proc(vp: linalg.Matrix4f32, p: [3]f32) -> [3]f32 {
	p4 := [4]f32{p.x, p.y, p.z, 1.0}
	res4 := vp * p4
	if res4.w != 0.0 do return res4.xyz / res4.w
	return res4.xyz
}

// draw_quad_3d appends a filled 3D quad to the 3D batch.
draw_quad_3d :: proc(
	batch: ^g.Batch3D,
	p0, p1, p2, p3: [3]f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	base_idx := u32(len(batch.vertices))
	append(
		&batch.vertices,
		g.Vertex3D{position = project_point(vp, p0), color = color},
		g.Vertex3D{position = project_point(vp, p1), color = color},
		g.Vertex3D{position = project_point(vp, p2), color = color},
		g.Vertex3D{position = project_point(vp, p3), color = color},
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

// draw_box appends a filled 3D box (cuboid) to the 3D batch.
draw_box :: proc(
	batch: ^g.Batch3D,
	center, size: [3]f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	half := size * 0.5

	p := [8][3]f32 {
		center + {-half.x, -half.y, -half.z}, // 0: bottom-left-back
		center + {half.x, -half.y, -half.z}, // 1: bottom-right-back
		center + {half.x, half.y, -half.z}, // 2: top-right-back
		center + {-half.x, half.y, -half.z}, // 3: top-left-back
		center + {-half.x, -half.y, half.z}, // 4: bottom-left-front
		center + {half.x, -half.y, half.z}, // 5: bottom-right-front
		center + {half.x, half.y, half.z}, // 6: top-right-front
		center + {-half.x, half.y, half.z}, // 7: top-left-front
	}

	base_idx := u32(len(batch.vertices))
	for pt in p {
		append(&batch.vertices, g.Vertex3D{position = project_point(vp, pt), color = color})
	}

	// 6 faces, 2 triangles each. Wind order is CCW from outside.
	append(
		&batch.indices,
		// Back face (Normal = -Z)
		base_idx + 0,
		base_idx + 3,
		base_idx + 2,
		base_idx + 0,
		base_idx + 2,
		base_idx + 1,
		// Front face (Normal = +Z)
		base_idx + 4,
		base_idx + 5,
		base_idx + 6,
		base_idx + 4,
		base_idx + 6,
		base_idx + 7,
		// Left face (Normal = -X)
		base_idx + 0,
		base_idx + 4,
		base_idx + 7,
		base_idx + 0,
		base_idx + 7,
		base_idx + 3,
		// Right face (Normal = +X)
		base_idx + 1,
		base_idx + 2,
		base_idx + 6,
		base_idx + 1,
		base_idx + 6,
		base_idx + 5,
		// Bottom face (Normal = -Y)
		base_idx + 0,
		base_idx + 1,
		base_idx + 5,
		base_idx + 0,
		base_idx + 5,
		base_idx + 4,
		// Top face (Normal = +Y)
		base_idx + 3,
		base_idx + 7,
		base_idx + 6,
		base_idx + 3,
		base_idx + 6,
		base_idx + 2,
	)
}

// draw_line_3d appends a thick line segment in 3D to the 3D batch by drawing a box oriented along the segment.
draw_line_3d :: proc(
	batch: ^g.Batch3D,
	p0, p1: [3]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	dir := p1 - p0
	len_dir := linalg.length(dir)
	if len_dir == 0 do return

	dir_norm := linalg.normalize(dir)
	temp := [3]f32{0, 1, 0}
	if math.abs(linalg.dot(dir_norm, temp)) > 0.99 {
		temp = {1, 0, 0}
	}
	u := linalg.normalize(linalg.cross(dir_norm, temp))
	v := linalg.cross(u, dir_norm)

	offset_u := u * (thickness * 0.5)
	offset_v := v * (thickness * 0.5)

	p := [8][3]f32 {
		p0 - offset_u - offset_v, // 0
		p0 + offset_u - offset_v, // 1
		p0 + offset_u + offset_v, // 2
		p0 - offset_u + offset_v, // 3
		p1 - offset_u - offset_v, // 4
		p1 + offset_u - offset_v, // 5
		p1 + offset_u + offset_v, // 6
		p1 - offset_u + offset_v, // 7
	}

	base_idx := u32(len(batch.vertices))
	for pt in p {
		append(&batch.vertices, g.Vertex3D{position = project_point(vp, pt), color = color})
	}

	append(
		&batch.indices,
		// Back face
		base_idx + 0,
		base_idx + 3,
		base_idx + 2,
		base_idx + 0,
		base_idx + 2,
		base_idx + 1,
		// Front face
		base_idx + 4,
		base_idx + 5,
		base_idx + 6,
		base_idx + 4,
		base_idx + 6,
		base_idx + 7,
		// Left face
		base_idx + 0,
		base_idx + 4,
		base_idx + 7,
		base_idx + 0,
		base_idx + 7,
		base_idx + 3,
		// Right face
		base_idx + 1,
		base_idx + 2,
		base_idx + 6,
		base_idx + 1,
		base_idx + 6,
		base_idx + 5,
		// Bottom face
		base_idx + 0,
		base_idx + 1,
		base_idx + 5,
		base_idx + 0,
		base_idx + 5,
		base_idx + 4,
		// Top face
		base_idx + 3,
		base_idx + 7,
		base_idx + 6,
		base_idx + 3,
		base_idx + 6,
		base_idx + 2,
	)
}

// draw_box_outline appends a box outline to the 3D batch using 12 line segments.
draw_box_outline :: proc(
	batch: ^g.Batch3D,
	center, size: [3]f32,
	thickness: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	half := size * 0.5

	p := [8][3]f32 {
		center + {-half.x, -half.y, -half.z},
		center + {half.x, -half.y, -half.z},
		center + {half.x, half.y, -half.z},
		center + {-half.x, half.y, -half.z},
		center + {-half.x, -half.y, half.z},
		center + {half.x, -half.y, half.z},
		center + {half.x, half.y, half.z},
		center + {-half.x, half.y, half.z},
	}

	draw_line_3d(batch, p[0], p[1], thickness, color, vp)
	draw_line_3d(batch, p[1], p[2], thickness, color, vp)
	draw_line_3d(batch, p[2], p[3], thickness, color, vp)
	draw_line_3d(batch, p[3], p[0], thickness, color, vp)

	draw_line_3d(batch, p[4], p[5], thickness, color, vp)
	draw_line_3d(batch, p[5], p[6], thickness, color, vp)
	draw_line_3d(batch, p[6], p[7], thickness, color, vp)
	draw_line_3d(batch, p[7], p[4], thickness, color, vp)

	draw_line_3d(batch, p[0], p[4], thickness, color, vp)
	draw_line_3d(batch, p[1], p[5], thickness, color, vp)
	draw_line_3d(batch, p[2], p[6], thickness, color, vp)
	draw_line_3d(batch, p[3], p[7], thickness, color, vp)
}

// draw_sphere appends a filled sphere (UV sphere) to the 3D batch.
draw_sphere :: proc(
	batch: ^g.Batch3D,
	center: [3]f32,
	radius: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
	rings := 16,
	sectors := 16,
) {
	if rings < 2 || sectors < 3 do return

	base_idx := u32(len(batch.vertices))

	// Generate vertices
	for r in 0 ..= rings {
		theta := f32(r) * math.PI / f32(rings)
		sin_theta := math.sin(theta)
		cos_theta := math.cos(theta)

		for s in 0 ..= sectors {
			phi := f32(s) * 2.0 * math.PI / f32(sectors)
			sin_phi := math.sin(phi)
			cos_phi := math.cos(phi)

			x := sin_theta * cos_phi
			y := cos_theta
			z := sin_theta * sin_phi

			pos := center + [3]f32{x, y, z} * radius
			append(&batch.vertices, g.Vertex3D{position = project_point(vp, pos), color = color})
		}
	}

	// Generate indices
	for r in 0 ..< rings {
		for s in 0 ..< sectors {
			first := u32(r * (sectors + 1) + s)
			second := first + u32(sectors + 1)

			append(
				&batch.indices,
				base_idx + first,
				base_idx + second,
				base_idx + first + 1,
				base_idx + first + 1,
				base_idx + second,
				base_idx + second + 1,
			)
		}
	}
}

// draw_cylinder appends a filled Y-aligned cylinder to the 3D batch.
draw_cylinder :: proc(
	batch: ^g.Batch3D,
	base_center: [3]f32,
	radius, height: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
	slices := 32,
) {
	if slices < 3 do return

	base_idx := u32(len(batch.vertices))

	bottom_center := base_center
	top_center := base_center + {0, height, 0}

	// Bottom center vertex
	append(&batch.vertices, g.Vertex3D{position = project_point(vp, bottom_center), color = color})

	// Bottom perimeter vertices
	for i in 0 ..< slices {
		angle := f32(i) * 2.0 * math.PI / f32(slices)
		pos := bottom_center + {radius * math.cos(angle), 0, radius * math.sin(angle)}
		append(&batch.vertices, g.Vertex3D{position = project_point(vp, pos), color = color})
	}

	// Top center vertex
	append(&batch.vertices, g.Vertex3D{position = project_point(vp, top_center), color = color})

	// Top perimeter vertices
	for i in 0 ..< slices {
		angle := f32(i) * 2.0 * math.PI / f32(slices)
		pos := top_center + {radius * math.cos(angle), 0, radius * math.sin(angle)}
		append(&batch.vertices, g.Vertex3D{position = project_point(vp, pos), color = color})
	}

	// Bottom cap
	for i in 0 ..< slices {
		curr := u32(1 + i)
		next := u32(1 + (i + 1) % slices)
		append(&batch.indices, base_idx + 0, base_idx + next, base_idx + curr)
	}

	// Top cap
	top_center_idx := u32(slices + 1)
	for i in 0 ..< slices {
		curr := u32(slices + 2 + i)
		next := u32(slices + 2 + (i + 1) % slices)
		append(&batch.indices, base_idx + top_center_idx, base_idx + curr, base_idx + next)
	}

	// Side walls
	for i in 0 ..< slices {
		b_curr := u32(1 + i)
		b_next := u32(1 + (i + 1) % slices)
		t_curr := u32(slices + 2 + i)
		t_next := u32(slices + 2 + (i + 1) % slices)

		append(&batch.indices, base_idx + b_curr, base_idx + t_curr, base_idx + b_next)
		append(&batch.indices, base_idx + b_next, base_idx + t_curr, base_idx + t_next)
	}
}

// draw_cone appends a filled Y-aligned cone to the 3D batch.
draw_cone :: proc(
	batch: ^g.Batch3D,
	base_center: [3]f32,
	radius, height: f32,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
	slices := 32,
) {
	if slices < 3 do return

	base_idx := u32(len(batch.vertices))

	bottom_center := base_center
	apex := base_center + {0, height, 0}

	// Bottom center vertex
	append(&batch.vertices, g.Vertex3D{position = project_point(vp, bottom_center), color = color})

	// Bottom perimeter vertices
	for i in 0 ..< slices {
		angle := f32(i) * 2.0 * math.PI / f32(slices)
		pos := bottom_center + {radius * math.cos(angle), 0, radius * math.sin(angle)}
		append(&batch.vertices, g.Vertex3D{position = project_point(vp, pos), color = color})
	}

	// Apex vertex
	append(&batch.vertices, g.Vertex3D{position = project_point(vp, apex), color = color})

	// Bottom cap
	for i in 0 ..< slices {
		curr := u32(1 + i)
		next := u32(1 + (i + 1) % slices)
		append(&batch.indices, base_idx + 0, base_idx + next, base_idx + curr)
	}

	// Side walls
	apex_idx := u32(slices + 1)
	for i in 0 ..< slices {
		b_curr := u32(1 + i)
		b_next := u32(1 + (i + 1) % slices)
		append(&batch.indices, base_idx + b_curr, base_idx + apex_idx, base_idx + b_next)
	}
}

// --- Tests ---

@(test)
test_draw_quad_3d :: proc(t: ^testing.T) {
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_quad_3d(&batch, {0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 4)
	testing.expect_value(t, len(batch.indices), 6)
}

@(test)
test_draw_box :: proc(t: ^testing.T) {
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_box(&batch, {0, 0, 0}, {2, 2, 2}, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 8)
	testing.expect_value(t, len(batch.indices), 36)
}

@(test)
test_draw_line_3d :: proc(t: ^testing.T) {
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_line_3d(&batch, {0, 0, 0}, {0, 5, 0}, 0.2, {1, 1, 1, 1})
	testing.expect_value(t, len(batch.vertices), 8)
	testing.expect_value(t, len(batch.indices), 36)
}

@(test)
test_draw_sphere :: proc(t: ^testing.T) {
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_sphere(&batch, {0, 0, 0}, 2.0, {1, 1, 1, 1}, rings = 8, sectors = 8)
	// (8+1)*(8+1) = 81 vertices
	testing.expect_value(t, len(batch.vertices), 81)
	// 8 * 8 * 6 = 384 indices
	testing.expect_value(t, len(batch.indices), 384)
}

@(test)
test_draw_cylinder :: proc(t: ^testing.T) {
	batch := g.Batch3D{}
	batch.vertices = make([dynamic]g.Vertex3D)
	batch.indices = make([dynamic]u32)
	defer {
		delete(batch.vertices)
		delete(batch.indices)
	}

	draw_cylinder(&batch, {0, 0, 0}, 1.0, 3.0, {1, 1, 1, 1}, slices = 8)
	// 1 + 8 + 1 + 8 = 18 vertices
	testing.expect_value(t, len(batch.vertices), 18)
	// Bottom cap: 8 * 3 = 24
	// Top cap: 8 * 3 = 24
	// Total: 96 indices
	testing.expect_value(t, len(batch.indices), 96)
}

draw_model :: proc{
	draw_gltf_model,
	draw_obj_model,
}

draw_gltf_model :: proc(
	batch: ^g.Batch3D,
	model: ^asset.Gltf_Data,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	if model == nil || model.raw_data == nil do return
	data := model.raw_data

	for &mesh in data.meshes {
		for &prim in mesh.primitives {
			// Find position attribute
			pos_attr: ^cgltf.attribute = nil
			for &attr in prim.attributes {
				if attr.type == .position {
					pos_attr = &attr
					break
				}
			}
			if pos_attr == nil do continue

			base_idx := u32(len(batch.vertices))
			accessor := pos_attr.data
			count := accessor.count

			// Unpack positions using cgltf
			pos_buffer := make([]f32, count * 3, context.temp_allocator)
			cgltf.accessor_unpack_floats(accessor, raw_data(pos_buffer), uint(len(pos_buffer)))

			for i in 0..<count {
				raw_pos := [3]f32{
					pos_buffer[i * 3 + 0],
					pos_buffer[i * 3 + 1],
					pos_buffer[i * 3 + 2],
				}
				append(&batch.vertices, g.Vertex3D{
					position = project_point(vp, raw_pos),
					color = color,
				})
			}

			if prim.indices != nil {
				idx_accessor := prim.indices
				idx_count := idx_accessor.count
				for i in 0..<idx_count {
					idx := u32(cgltf.accessor_read_index(idx_accessor, uint(i)))
					append(&batch.indices, base_idx + idx)
				}
			} else {
				for i in 0..<count {
					append(&batch.indices, base_idx + u32(i))
				}
			}
		}
	}
}

draw_obj_model :: proc(
	batch: ^g.Batch3D,
	model: ^asset.Obj_Mesh,
	color: [4]f32,
	vp := linalg.MATRIX4F32_IDENTITY,
) {
	if model == nil do return
	base_idx := u32(len(batch.vertices))

	for v in model.vertices {
		append(&batch.vertices, g.Vertex3D{
			position = project_point(vp, [3]f32{v[0], v[1], v[2]}),
			color = color,
		})
	}

	for idx in model.indices {
		append(&batch.indices, base_idx + idx)
	}
}

