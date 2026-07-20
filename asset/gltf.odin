package asset

import errors "../errors"
import "base:runtime"
import "core:io"
import "core:strings"
import "vendor:cgltf"
import wgpu "vendor:wgpu"
import "core:path/filepath"
import "core:hash"

Gltf_Data :: struct {
	raw_data: ^cgltf.data,
	textures: map[string]AssetId(wgpu.Texture),
}

GLTF_LOADER :: AssetLoader {
	load         = gltf_loader_proc,
	destroy      = gltf_destroy_proc,
	dependencies = gltf_dependencies_proc,
}

gltf_destroy_proc :: proc(asset: rawptr, allocator: runtime.Allocator) {
	asset_ptr := (^Gltf_Data)(asset)
	if asset_ptr != nil {
		destroy_gltf_asset(asset_ptr)
		delete(asset_ptr.textures)
		free(asset_ptr, allocator)
	}
}

normalize_slash :: proc(path: string, allocator := context.temp_allocator) -> string {
	res, _ := strings.replace_all(path, "\\", "/", allocator)
	return res
}

gltf_loader_proc :: proc(
	ctx: ^Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	// Read all data from reader
	data_bytes := make([dynamic]byte, allocator)
	buf: [4096]byte
	for {
		n, err := io.read(ctx.reader, buf[:])
		if n > 0 {
			append(&data_bytes, ..buf[:n])
		}
		if err != nil {
			break
		}
	}
	defer delete(data_bytes)

	opts := cgltf.options{}

	data_ptr: rawptr = nil
	if len(data_bytes) > 0 {
		data_ptr = &data_bytes[0]
	}
	out_data, parse_res := cgltf.parse(opts, data_ptr, size = len(data_bytes))
	if parse_res != .success {
		return errors.Err(errors.Error){error = errors.from_payload(AssetError.Loader_Error)}
	}

	// Load buffers (e.g. for base64 or external files)
	gltf_path_cstr := strings.clone_to_cstring(ctx.path, context.temp_allocator)
	buf_res := cgltf.load_buffers(opts, out_data, gltf_path_cstr)
	if buf_res != .success {
		cgltf.free(out_data)
		return errors.Err(errors.Error){error = errors.from_payload(AssetError.Loader_Error)}
	}

	// Wrap in Gltf_Data
	gltf_asset := new(Gltf_Data, allocator)
	if gltf_asset == nil {
		cgltf.free(out_data)
		return errors.Err(errors.Error){error = errors.from_payload(AssetError.Allocator_Error)}
	}
	gltf_asset.raw_data = out_data
	gltf_asset.textures = make(map[string]AssetId(wgpu.Texture), allocator)

	// Populate texture mappings
	if ctx.path != "" && out_data != nil {
		dir := filepath.dir(ctx.path)

		for i in 0 ..< len(out_data.images) {
			img := &out_data.images[i]
			if img.uri != nil {
				uri_str := string(img.uri)
				if !strings.has_prefix(uri_str, "data:") {
					joined, _ := filepath.join({dir, uri_str}, context.temp_allocator)
					normalized := normalize_slash(joined, context.temp_allocator)
					hash_val := hash.fnv64a(transmute([]u8)normalized)
					
					gltf_asset.textures[uri_str] = AssetId(wgpu.Texture) {
						id = UntypedAssetId{value = hash_val},
					}
				}
			}
		}
	}

	return errors.Ok(rawptr){value = gltf_asset}
}

gltf_dependencies_proc :: proc(
	asset: rawptr,
	ctx: ^Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> []Asset_Dependency {
	gltf_asset := (^Gltf_Data)(asset)
	if gltf_asset == nil || gltf_asset.raw_data == nil || ctx == nil do return nil

	dir := filepath.dir(ctx.path)

	deps := make([dynamic]Asset_Dependency, allocator)

	for i in 0 ..< len(gltf_asset.raw_data.images) {
		img := &gltf_asset.raw_data.images[i]
		if img.uri != nil {
			uri_str := string(img.uri)
			if !strings.has_prefix(uri_str, "data:") {
				joined, _ := filepath.join({dir, uri_str}, context.temp_allocator)
				normalized := normalize_slash(joined, allocator)
				append(&deps, Asset_Dependency{
					path = normalized,
					type = typeid_of(wgpu.Texture),
				})
			}
		}
	}

	return deps[:]
}

destroy_gltf_asset :: proc(asset_ptr: ^Gltf_Data) {
	if asset_ptr != nil {
		if asset_ptr.raw_data != nil {
			cgltf.free(asset_ptr.raw_data)
			asset_ptr.raw_data = nil
		}
	}
}
