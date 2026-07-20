package asset

import errors "../errors"
import "base:runtime"
import "core:bufio"
import "core:io"
import linalg "core:math/linalg"
import "core:strconv"
import "core:strings"

Material :: struct {
	name:      string, // Name of the material (from 'newmtl')
	ambient:   linalg.Vector3f32, // Ambient color coefficient (from 'Ka')
	diffuse:   linalg.Vector3f32, // Diffuse color coefficient (from 'Kd')
	specular:  linalg.Vector3f32, // Specular color coefficient (from 'Ks')
	shininess: f32, // Shininess / specular exponent (from 'Ns')
	illum:     int, // Illumination model (from 'illum', e.g. 1 = diffuse, 2 = specular)
	map_kd:    string, // Path to the diffuse texture map (from 'map_Kd')
}

Materials :: struct {
	materials: map[string]Material,
}

MATERIAL_LOADER :: AssetLoader {
	load    = material_loader_proc,
	destroy = materials_destroy_proc,
}

materials_destroy_proc :: proc(asset: rawptr, allocator: runtime.Allocator) {
	lib := (^Materials)(asset)
	if lib != nil {
		for _, mat in lib.materials {
			delete(mat.name, allocator)
			delete(mat.map_kd, allocator)
		}
		delete(lib.materials)
	}
}

materials_destroy :: proc(lib: ^Materials, allocator: runtime.Allocator) {
	if lib != nil {
		for _, mat in lib.materials {
			delete(mat.name, allocator)
			delete(mat.map_kd, allocator)
		}
		delete(lib.materials)
		free(lib, allocator)
	}
}

material_loader_proc :: proc(
	ctx: ^Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	lib := new(Materials, allocator)
	lib.materials = make(map[string]Material, allocator)

	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, ctx.reader, context.temp_allocator)
	defer bufio.scanner_destroy(&scanner)

	current_mat: ^Material = nil

	for bufio.scanner_scan(&scanner) {
		line := bufio.scanner_text(&scanner)
		line = strings.trim_space(line)
		if len(line) == 0 || line[0] == '#' do continue

		parts := strings.fields(line, context.temp_allocator)
		if len(parts) < 2 do continue

		cmd := parts[0]
		switch cmd {
		case "newmtl":
			name := strings.clone(parts[1], allocator)
			lib.materials[name] = Material {
				name      = name,
				ambient   = {0.2, 0.2, 0.2},
				diffuse   = {0.8, 0.8, 0.8},
				specular  = {0.0, 0.0, 0.0},
				shininess = 0.0,
				illum     = 2,
			}
			current_mat = &lib.materials[name]

		case "Ka":
			if current_mat != nil && len(parts) >= 4 {
				current_mat.ambient[0], _ = strconv.parse_f32(parts[1])
				current_mat.ambient[1], _ = strconv.parse_f32(parts[2])
				current_mat.ambient[2], _ = strconv.parse_f32(parts[3])
			}

		case "Kd":
			if current_mat != nil && len(parts) >= 4 {
				current_mat.diffuse[0], _ = strconv.parse_f32(parts[1])
				current_mat.diffuse[1], _ = strconv.parse_f32(parts[2])
				current_mat.diffuse[2], _ = strconv.parse_f32(parts[3])
			}

		case "Ks":
			if current_mat != nil && len(parts) >= 4 {
				current_mat.specular[0], _ = strconv.parse_f32(parts[1])
				current_mat.specular[1], _ = strconv.parse_f32(parts[2])
				current_mat.specular[2], _ = strconv.parse_f32(parts[3])
			}

		case "Ns":
			if current_mat != nil {
				current_mat.shininess, _ = strconv.parse_f32(parts[1])
			}

		case "map_Kd":
			if current_mat != nil {
				// Reconstruct the remaining string if texture filename contains spaces
				tex_path := strings.join(parts[1:], " ", context.temp_allocator)
				current_mat.map_kd = strings.clone(tex_path, allocator)
			}

		case "illum":
			if current_mat != nil {
				current_mat.illum, _ = strconv.parse_int(parts[1])
			}
		}
	}

	return errors.Ok(rawptr){value = lib}
}
