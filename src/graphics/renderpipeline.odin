package graphics

import "../app"
import "../ecs/params"
import "vendor:wgpu"

Clear_Color :: struct {
	r, g, b, a: f64,
}

main_render_system :: proc(
	ctx_res: params.Res(Render_Context),
	fctx_res: params.Res(Frame_Context),
	clear_color: params.Res(Clear_Color),
	batch2d: params.Res(Batch2D),
	batch3d: params.Res(Batch3D),
) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	if ctx == nil || ctx.device == nil do return
	
	if fctx.encoder == nil || fctx.texture_view == nil do return

	color: wgpu.Color
	if clear_color.ptr != nil {
		color = {clear_color.ptr.r, clear_color.ptr.g, clear_color.ptr.b, clear_color.ptr.a}
	} else {
		color = {0.1, 0.2, 0.3, 1.0} // Default dark blue
	}

	color_attachment := wgpu.RenderPassColorAttachment{
		view       = fctx.texture_view,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = color,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	}

	pass_desc := wgpu.RenderPassDescriptor{
		colorAttachmentCount = 1,
		colorAttachments = &color_attachment,
	}

	render_pass := wgpu.CommandEncoderBeginRenderPass(fctx.encoder, &pass_desc)

	if batch3d.ptr != nil {
		batch3d_flush(batch3d.ptr, ctx, render_pass)
	}

	if batch2d.ptr != nil {
		batch2d_flush(batch2d.ptr, ctx, render_pass)
	}

	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)
}
