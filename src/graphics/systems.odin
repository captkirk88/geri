package graphics

import "../app"
import "../ecs/params"
import "../windowing"
import "vendor:wgpu"

handle_resize_system :: proc() {
}

frame_start_system :: proc(ctx_res: params.Res(Render_Context), fctx_res: params.Res(Frame_Context)) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr

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

	view_desc := wgpu.TextureViewDescriptor{
		format = wgpu.TextureGetFormat(surface_tex.texture),
		dimension = ._2D,
		baseMipLevel = 0,
		mipLevelCount = 1,
		baseArrayLayer = 0,
		arrayLayerCount = 1,
		aspect = .All,
	}
	fctx.texture_view = wgpu.TextureCreateView(surface_tex.texture, &view_desc)

	encoder_desc := wgpu.CommandEncoderDescriptor{label = "Frame Encoder"}
	fctx.encoder = wgpu.DeviceCreateCommandEncoder(ctx.device, &encoder_desc)
}

frame_present_system :: proc(ctx_res: params.Res(Render_Context), fctx_res: params.Res(Frame_Context)) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	if fctx.encoder == nil || fctx.texture_view == nil do return

	cmd_buffer := wgpu.CommandEncoderFinish(fctx.encoder, nil)
	cmds := []wgpu.CommandBuffer{cmd_buffer}
	wgpu.QueueSubmit(ctx.queue, cmds)

	wgpu.SurfacePresent(ctx.surface)

	wgpu.CommandBufferRelease(cmd_buffer)
	wgpu.CommandEncoderRelease(fctx.encoder)
	wgpu.TextureViewRelease(fctx.texture_view)

	fctx.encoder = nil
	fctx.texture_view = nil
}
