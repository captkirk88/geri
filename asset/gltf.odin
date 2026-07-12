package asset

import errors "../errors"
import "base:runtime"
import "core:io"
import "core:strings"
import "vendor:cgltf"

Gltf_Data :: struct {
	raw_data: ^cgltf.data,
}

GLTF_LOADER :: AssetLoader {
	load    = gltf_loader_proc,
	destroy = gltf_destroy_proc,
}

gltf_destroy_proc :: proc(asset: rawptr, allocator: runtime.Allocator) {
	asset_ptr := (^Gltf_Data)(asset)
	if asset_ptr != nil {
		destroy_gltf_asset(asset_ptr)
	}
}

gltf_loader_proc :: proc(
	reader: io.Reader,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	// Read all data from reader
	data_bytes := make([dynamic]byte, allocator)
	buf: [4096]byte
	for {
		n, err := io.read(reader, buf[:])
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
	// If settings points to a cstring containing the directory/gltf path, we can pass it
	gltf_path: cstring = nil
	if settings != nil {
		gltf_path = (cstring)(settings)
	}

	buf_res := cgltf.load_buffers(opts, out_data, gltf_path)
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

	return errors.Ok(rawptr){value = gltf_asset}
}

destroy_gltf_asset :: proc(asset_ptr: ^Gltf_Data) {
	if asset_ptr != nil {
		if asset_ptr.raw_data != nil {
			cgltf.free(asset_ptr.raw_data)
			asset_ptr.raw_data = nil
		}
	}
}
