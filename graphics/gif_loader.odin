package graphics

import "../asset"
import "../errors"
import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:hash"
import "core:image"
import "core:io"
import stbi "vendor:stb/image"
import "core:c"
import "./components"

global_asset_server: ^asset.AssetServer

// Helper to read all bytes from a reader
read_all :: proc(reader: io.Reader, allocator := context.allocator) -> ([]byte, bool) {
	buf := make([dynamic]byte, allocator)
	chunk: [4096]byte
	for {
		n, err := io.read(reader, chunk[:])
		if n > 0 {
			append(&buf, ..chunk[:n])
		}
		if err != nil {
			if err == .EOF do break
			delete(buf)
			return nil, false
		}
	}
	return buf[:], true
}

// Stores an asset manually in the server's manager
asset_store :: proc(server: ^asset.AssetServer, id: asset.AssetId($T), val: T) {
	if server == nil do return
	
	// Lock server mutex to find the manager
	mgr_val, ok := server.managers[typeid_of(T)]
	if !ok do return

	mgr := (^asset.AssetManager(T))(mgr_val.manager_ptr)
	
	// Lock manager mutex and insert
	mgr.assets[id.id] = val
}

// cimage.Image Loader
image_loader_proc :: proc(
	reader: io.Reader,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	data, ok := read_all(reader, context.temp_allocator)
	if !ok {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Loader_Error)}
	}

	w, h, comp: c.int
	stb_pixels := stbi.load_from_memory(raw_data(data), c.int(len(data)), &w, &h, &comp, 4)
	if stb_pixels == nil {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Invalid_Data)}
	}
	defer stbi.image_free(stb_pixels)

	img := new(image.Image, allocator)
	img.width = int(w)
	img.height = int(h)
	img.channels = 4
	img.depth = 8
	
	img.pixels.buf = make([dynamic]u8, int(w * h * 4), allocator)
	copy(img.pixels.buf[:], stb_pixels[:w * h * 4])

	return errors.Ok(rawptr){value = img}
}

image_destroy_proc :: proc(asset_ptr: rawptr, allocator: runtime.Allocator) {
	img := (^image.Image)(asset_ptr)
	if img != nil {
		delete(img.pixels.buf)
	}
}

// SpriteAnimation Loader (reads GIF)
sprite_animation_loader_proc :: proc(
	reader: io.Reader,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	data, ok := read_all(reader, context.temp_allocator)
	if !ok {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Loader_Error)}
	}

	delays_ptr: [^]c.int
	w, h, frames_count, comp: c.int
	stb_pixels := stbi.load_gif_from_memory(raw_data(data), c.int(len(data)), &delays_ptr, &w, &h, &frames_count, &comp, 4)
	if stb_pixels == nil {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Invalid_Data)}
	}
	defer stbi.image_free(stb_pixels)
	defer stbi.image_free(delays_ptr)

	anim := new(components.SpriteAnimation, allocator)
	frames := make([]asset.AssetId(image.Image), int(frames_count), allocator)
	delays := make([]f32, int(frames_count), allocator)

	frame_size := int(w * h * 4)
	for i in 0 ..< int(frames_count) {
		frame_img: image.Image
		frame_img.width = int(w)
		frame_img.height = int(h)
		frame_img.channels = 4
		frame_img.depth = 8
		frame_img.pixels.buf = make([dynamic]u8, frame_size, allocator)
		
		offset := i * frame_size
		copy(frame_img.pixels.buf[:], stb_pixels[offset : offset + frame_size])

		// Generate a unique dummy asset path/ID for each frame
		frame_path := fmt.tprintf("generated://frame_%p_%d", anim, offset)
		hash_val := hash.fnv64a(transmute([]u8)frame_path)
		frame_id := asset.AssetId(image.Image){id = {value = hash_val}}

		// Store frame image in manager
		asset_store(global_asset_server, frame_id, frame_img)

		frames[i] = frame_id
		// stb_image returns delays in milliseconds
		delays[i] = f32(delays_ptr[i]) / 1000.0
	}

	anim.frames = frames
	anim.delays = delays

	return errors.Ok(rawptr){value = anim}
}

sprite_animation_destroy_proc :: proc(asset_ptr: rawptr, allocator: runtime.Allocator) {
	anim := (^components.SpriteAnimation)(asset_ptr)
	if anim != nil {
		// Note: the individual frame images are owned and cleaned up by the cimage.Image AssetManager.
		delete(anim.frames, allocator)
		delete(anim.delays, allocator)
	}
}
