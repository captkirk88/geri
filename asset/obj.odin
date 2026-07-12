package asset

import errors "../errors"
import "base:runtime"
import "core:bufio"
import "core:io"
import linalg "core:math/linalg"
import "core:strconv"
import "core:strings"

Obj_Mesh :: struct {
	vertices:  [dynamic]linalg.Vector3f32,
	normals:   [dynamic]linalg.Vector3f32,
	texcoords: [dynamic]linalg.Vector2f32,
	indices:   [dynamic]u32,
}

OBJ_LOADER :: AssetLoader {
	load    = obj_loader_proc,
	destroy = obj_destroy_proc,
}

obj_destroy_proc :: proc(asset: rawptr, allocator: runtime.Allocator) {
	mesh := (^Obj_Mesh)(asset)
	if mesh != nil {
		delete(mesh.vertices)
		delete(mesh.normals)
		delete(mesh.texcoords)
		delete(mesh.indices)
	}
}

obj_mesh_destroy :: proc(mesh: ^Obj_Mesh) {
	if mesh != nil {
		delete(mesh.vertices)
		delete(mesh.normals)
		delete(mesh.texcoords)
		delete(mesh.indices)
		free(mesh)
	}
}

// Map key representing a unique vertex combination in Obj
Vertex_Key :: struct {
	v:  int,
	vt: int,
	vn: int,
}

obj_loader_proc :: proc(
	reader: io.Reader,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	// Temp storage for raw OBJ data
	temp_positions := make([dynamic]linalg.Vector3f32, context.temp_allocator)
	temp_normals := make([dynamic]linalg.Vector3f32, context.temp_allocator)
	temp_texcoords := make([dynamic]linalg.Vector2f32, context.temp_allocator)

	mesh := new(Obj_Mesh, allocator)
	mesh.vertices = make([dynamic]linalg.Vector3f32, allocator)
	mesh.normals = make([dynamic]linalg.Vector3f32, allocator)
	mesh.texcoords = make([dynamic]linalg.Vector2f32, allocator)
	mesh.indices = make([dynamic]u32, allocator)

	// Map to de-duplicate unique vertex coordinate combinations
	unique_vertices := make(map[Vertex_Key]u32, 1024, context.temp_allocator)

	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, reader, context.temp_allocator)
	defer bufio.scanner_destroy(&scanner)

	for bufio.scanner_scan(&scanner) {
		line := bufio.scanner_text(&scanner)
		line = strings.trim_space(line)
		if len(line) == 0 || line[0] == '#' do continue

		parts := strings.fields(line, context.temp_allocator)
		if len(parts) < 2 do continue

		type := parts[0]
		switch type {
		case "v":
			if len(parts) >= 4 {
				x, _ := strconv.parse_f32(parts[1])
				y, _ := strconv.parse_f32(parts[2])
				z, _ := strconv.parse_f32(parts[3])
				append(&temp_positions, linalg.Vector3f32{x, y, z})
			}
		case "vn":
			if len(parts) >= 4 {
				x, _ := strconv.parse_f32(parts[1])
				y, _ := strconv.parse_f32(parts[2])
				z, _ := strconv.parse_f32(parts[3])
				append(&temp_normals, linalg.Vector3f32{x, y, z})
			}
		case "vt":
			if len(parts) >= 3 {
				u, _ := strconv.parse_f32(parts[1])
				v, _ := strconv.parse_f32(parts[2])
				append(&temp_texcoords, linalg.Vector2f32{u, v})
			}
		case "f":
			face_vertices := make([dynamic]u32, context.temp_allocator)
			for i := 1; i < len(parts); i += 1 {
				// Parse v/vt/vn
				vertex_str := parts[i]
				indices := strings.split(vertex_str, "/", context.temp_allocator)

				v_idx, vt_idx, vn_idx := 0, 0, 0

				if len(indices) > 0 && len(indices[0]) > 0 {
					v_idx, _ = strconv.parse_int(indices[0])
					if v_idx < 0 do v_idx = len(temp_positions) + v_idx + 1
				}
				if len(indices) > 1 && len(indices[1]) > 0 {
					vt_idx, _ = strconv.parse_int(indices[1])
					if vt_idx < 0 do vt_idx = len(temp_texcoords) + vt_idx + 1
				}
				if len(indices) > 2 && len(indices[2]) > 0 {
					vn_idx, _ = strconv.parse_int(indices[2])
					if vn_idx < 0 do vn_idx = len(temp_normals) + vn_idx + 1
				}

				key := Vertex_Key{v_idx, vt_idx, vn_idx}
				out_idx, found := unique_vertices[key]
				if !found {
					out_idx = u32(len(mesh.vertices))
					unique_vertices[key] = out_idx

					// Add vertex position
					pos := linalg.Vector3f32{0, 0, 0}
					if v_idx > 0 && v_idx <= len(temp_positions) {
						pos = temp_positions[v_idx - 1]
					}
					append(&mesh.vertices, pos)

					// Add normal
					norm := linalg.Vector3f32{0, 0, 0}
					if vn_idx > 0 && vn_idx <= len(temp_normals) {
						norm = temp_normals[vn_idx - 1]
					}
					append(&mesh.normals, norm)

					// Add texcoord
					tex := linalg.Vector2f32{0, 0}
					if vt_idx > 0 && vt_idx <= len(temp_texcoords) {
						tex = temp_texcoords[vt_idx - 1]
					}
					append(&mesh.texcoords, tex)
				}
				append(&face_vertices, out_idx)
			}

			// Triangulate face using triangle fan
			if len(face_vertices) >= 3 {
				for i := 1; i < len(face_vertices) - 1; i += 1 {
					append(&mesh.indices, face_vertices[0])
					append(&mesh.indices, face_vertices[i])
					append(&mesh.indices, face_vertices[i + 1])
				}
			}
		}
	}

	return errors.Ok(rawptr){value = mesh}
}
