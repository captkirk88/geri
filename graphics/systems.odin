package graphics

import "../app"
import "../ecs"
import "../ecs/params"
import "../image/gif"
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
import "core:thread"
import stbi "vendor:stb/image"
import "vendor:wgpu"

Gif_Frame_Task_Data :: struct {
	writer:    ^gif.Gif_Writer,
	pixels:    []byte,
	allocator: runtime.Allocator,
}

gif_frame_worker_proc :: proc(task: thread.Task) {
	data := cast(^Gif_Frame_Task_Data)task.data
	if data == nil {
		return
	}
	allocator := data.allocator
	defer free(data, allocator)
	if data.writer == nil {
		delete(data.pixels, allocator)
		return
	}

	gif.write_frame(data.writer, data.pixels)
	delete(data.pixels, allocator)
}

handle_resize_system :: proc(
	resize_events: params.EventReader(windowing.Window_Resized_Event),
	render_ctx: params.Res(Render_Context),
	gfx_config: params.Res(Graphics_Config),
) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return
	for event in resize_events.events {
		if event.width > 0 && event.height > 0 {
			render_ctx.ptr.config.width = u32(event.width)
			render_ctx.ptr.config.height = u32(event.height)
			wgpu.SurfaceConfigure(render_ctx.ptr.surface, &render_ctx.ptr.config)
			
			sample_count: u32 = 1
			hdr := false
			if gfx_config.ptr != nil {
				sample_count = antialiasing_sample_count(gfx_config.ptr.antialiasing)
				hdr = gfx_config.ptr.hdr
			}
			recreate_msaa_texture(render_ctx.ptr, sample_count, hdr)
		}
	}
}


capture_screenshot :: proc(w: ^ecs.World, path: string, format: Screenshot_Format = .TGA) {
	ecs.world_add_resource(w, Screenshot_Request{path = path, format = format})
}

screenshot_recording_begin :: proc(w: ^ecs.World, path: string) {
	// Width and height are not known until the first frame is captured;
	// the file is opened lazily in frame_present_system on the first recorded frame.
	rec := Screenshot_Recording {
		writer = gif.Gif_Writer{file = nil},
		active = true,
	}
	rec.worker_pool = new(thread.Pool, context.allocator)
	if rec.worker_pool != nil {
		thread.pool_init(rec.worker_pool, context.allocator, 1)
		thread.pool_start(rec.worker_pool)
	}
	// Store the path in a resource so frame_present_system can open the writer.
	ecs.world_add_resource(w, Screenshot_Recording_Path{path = path})
	ecs.world_add_resource(w, rec)
}

screenshot_recording_end :: proc(w: ^ecs.World) {
	rec := ecs.world_get_resource(w, Screenshot_Recording)
	if rec != nil {
		rec.active = false
		if rec.worker_pool != nil {
			thread.pool_finish(rec.worker_pool)
			thread.pool_destroy(rec.worker_pool)
			free(rec.worker_pool, context.allocator)
			rec.worker_pool = nil
		}
		gif.close(&rec.writer)
		ecs.world_remove_resource(w, Screenshot_Recording)
		ecs.world_remove_resource(w, Screenshot_Recording_Path)
	}
}

@(tag = "system")
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

@(tag = "system")
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
					// Open the GIF writer on the first captured frame (dimensions now known)
					if rec.writer.file == nil {
						rec_path := ecs.world_get_resource(world, Screenshot_Recording_Path)
						if rec_path != nil {
							writer, ok := gif.open(rec_path.path, int(width), int(height))
							if ok {
								rec.writer = writer
							}
						}
					}
					if rec.writer.file != nil {
						if rec.worker_pool != nil {
							job_pixels := make([]byte, len(pixels), context.allocator)
							copy(job_pixels, pixels)
							job := new(Gif_Frame_Task_Data, context.allocator)
							job.writer = &rec.writer
							job.pixels = job_pixels
							job.allocator = context.allocator
							thread.pool_add_task(
								rec.worker_pool,
								context.allocator,
								gif_frame_worker_proc,
								job,
							)
						} else {
							gif.write_frame(&rec.writer, pixels)
						}
					}
					delete(pixels)
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
