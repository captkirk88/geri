package graphics

import "../app"
import "../ecs"
import "../ecs/params"
import log "../logging"
import "../windowing"
import "base:runtime"
import "core:bytes"
import "core:image"
import bmp "core:image/bmp"
import qoi "core:image/qoi"
import tga "core:image/tga"
import "core:os"
import "core:strings"
import stbi "vendor:stb/image"
import "vendor:wgpu"

handle_resize_system :: proc() {
}

capture_screenshot :: proc(w: ^ecs.World, path: string, format: Screenshot_Format = .TGA) {
	ecs.world_add_resource(w, Screenshot_Request{path = path, format = format})
}

screenshot_recording_begin :: proc(w: ^ecs.World, path: string) {
	rec := Screenshot_Recording {
		path   = path,
		frames = make([dynamic][]byte),
		active = true,
	}
	ecs.world_add_resource(w, rec, proc(r: ^Screenshot_Recording, alloc: runtime.Allocator) {
		for frame in r.frames {
			delete(frame)
		}
		delete(r.frames)
	})
}

screenshot_recording_end :: proc(w: ^ecs.World) {
	rec := ecs.world_get_resource(w, Screenshot_Recording)
	if rec != nil {
		rec.active = false
		log.debug(
			"screenshot_recording_end: path=%s, width=%d, height=%d, frame_count=%d",
			rec.path,
			rec.width,
			rec.height,
			len(rec.frames),
		)
		if len(rec.frames) > 0 {
			write_gif(rec.path, rec.width, rec.height, rec.frames[:])
		}
		ecs.world_remove_resource(w, Screenshot_Recording)
	}
}

frame_start_system :: proc(
	ctx_res: params.Res(Render_Context),
	fctx_res: params.Res(Frame_Context),
) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	if ctx == nil || ctx.device == nil do return

	surface_tex := wgpu.SurfaceGetCurrentTexture(ctx.surface)

	#partial switch surface_tex.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// Good
	case .Timeout, .Outdated, .Lost:
		// Needs reconfigure
		wgpu.SurfaceConfigure(ctx.surface, &ctx.config)
		surface_tex = wgpu.SurfaceGetCurrentTexture(ctx.surface)
	case .Error, .Occluded:
		return
	}

	if surface_tex.texture == nil do return

	view_desc := wgpu.TextureViewDescriptor {
		format          = wgpu.TextureGetFormat(surface_tex.texture),
		dimension       = ._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	fctx.texture_view = wgpu.TextureCreateView(surface_tex.texture, &view_desc)
	fctx.texture = surface_tex.texture

	encoder_desc := wgpu.CommandEncoderDescriptor {
		label = "Frame Encoder",
	}

	fctx.encoder = wgpu.DeviceCreateCommandEncoder(ctx.device, &encoder_desc)
}

frame_present_system :: proc(
	world: ^ecs.World,
	ctx_res: params.Res(Render_Context),
	fctx_res: params.Res(Frame_Context),
) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	if ctx == nil || ctx.device == nil do return
	if fctx.encoder == nil || fctx.texture_view == nil do return

	if world != nil {
		req := ecs.world_get_resource(world, Screenshot_Request)
		rec := ecs.world_get_resource(world, Screenshot_Recording)

		if req != nil || (rec != nil && rec.active) {
			width := ctx.config.width
			height := ctx.config.height
			// Round up to next 256 boundary for copy buffer padding
			bytes_per_row := (width * 4 + 255) & ~u32(255)
			buffer_size := u64(bytes_per_row * height)

			buffer_desc := wgpu.BufferDescriptor {
				usage = {.MapRead, .CopyDst},
				size  = buffer_size,
			}
			read_buf := wgpu.DeviceCreateBuffer(ctx.device, &buffer_desc)
			defer wgpu.BufferRelease(read_buf)

			src_copy := wgpu.TexelCopyTextureInfo {
				texture  = fctx.texture,
				mipLevel = 0,
				origin   = {0, 0, 0},
				aspect   = .All,
			}
			dst_copy := wgpu.TexelCopyBufferInfo {
				buffer = read_buf,
				layout = wgpu.TexelCopyBufferLayout {
					offset = 0,
					bytesPerRow = bytes_per_row,
					rowsPerImage = height,
				},
			}
			extent := wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			}
			wgpu.CommandEncoderCopyTextureToBuffer(fctx.encoder, &src_copy, &dst_copy, &extent)

			cmd_buffer := wgpu.CommandEncoderFinish(fctx.encoder, nil)
			wgpu.QueueSubmit(ctx.queue, {cmd_buffer})
			wgpu.CommandBufferRelease(cmd_buffer)

			cb_data := false
			map_cb :: proc "c" (
				status: wgpu.MapAsyncStatus,
				message: wgpu.StringView,
				userdata1: rawptr,
				userdata2: rawptr,
			) {
				done_ptr := (^bool)(userdata1)
				done_ptr^ = true
			}
			cb_info := wgpu.BufferMapCallbackInfo {
				mode      = .WaitAnyOnly,
				callback  = map_cb,
				userdata1 = &cb_data,
			}
			wgpu.BufferMapAsync(read_buf, {.Read}, 0, uint(buffer_size), cb_info)

			for !cb_data {
				wgpu.DevicePoll(ctx.device, true, nil)
			}

			mapped_data := wgpu.BufferGetConstMappedRange(read_buf, 0, uint(buffer_size))
			if len(mapped_data) > 0 {
				pixels := make([]byte, int(width * height * 4))

				for y in 0 ..< height {
					row_offset := int(y * bytes_per_row)
					row_data := mapped_data[row_offset:row_offset + int(width * 4)]

					dest_offset := int(y * width * 4)
					if ctx.config.format == .BGRA8Unorm || ctx.config.format == .BGRA8UnormSrgb {
						for x in 0 ..< width {
							idx := int(x * 4)
							pixels[dest_offset + idx + 0] = row_data[idx + 2] // R
							pixels[dest_offset + idx + 1] = row_data[idx + 1] // G
							pixels[dest_offset + idx + 2] = row_data[idx + 0] // B
							pixels[dest_offset + idx + 3] = row_data[idx + 3] // A
						}
					} else {
						copy(pixels[dest_offset:dest_offset + int(width * 4)], row_data)
					}
				}

				if req != nil {
					img := image.Image {
						width    = int(width),
						height   = int(height),
						channels = 4,
						depth    = 8,
					}
					img.pixels.buf = make(
						[dynamic]u8,
						int(width * height * 4),
						context.temp_allocator,
					)
					copy(img.pixels.buf[:], pixels)

					switch req.format {
					case .TGA:
						tga.save(req.path, &img)
					case .BMP:
						bmp.save(req.path, &img)
					case .QOI:
						qoi.save(req.path, &img)
					case .PNG:
						path_c := strings.clone_to_cstring(req.path, context.temp_allocator)
						stbi.write_png(
							path_c,
							i32(width),
							i32(height),
							4,
							raw_data(img.pixels.buf),
							i32(width * 4),
						)
					}
					ecs.world_remove_resource(world, Screenshot_Request)
				}

				if rec != nil && rec.active {
					rec.width = int(width)
					rec.height = int(height)
					append(&rec.frames, pixels)
				} else {
					delete(pixels)
				}

				wgpu.BufferUnmap(read_buf)
			}

			wgpu.SurfacePresent(ctx.surface)

			wgpu.CommandEncoderRelease(fctx.encoder)
			wgpu.TextureViewRelease(fctx.texture_view)
			fctx.encoder = nil
			fctx.texture_view = nil
			fctx.texture = nil
			return
		}
	}

	cmd_buffer := wgpu.CommandEncoderFinish(fctx.encoder, nil)
	cmds := []wgpu.CommandBuffer{cmd_buffer}
	wgpu.QueueSubmit(ctx.queue, cmds)

	wgpu.SurfacePresent(ctx.surface)

	wgpu.CommandBufferRelease(cmd_buffer)
	wgpu.CommandEncoderRelease(fctx.encoder)
	wgpu.TextureViewRelease(fctx.texture_view)

	fctx.encoder = nil
	fctx.texture_view = nil
	fctx.texture = nil
}
