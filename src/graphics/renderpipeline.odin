package graphics

import "../app"
import "../ecs/params"
import "vendor:wgpu"

Clear_Color :: struct {
	r, g, b, a: f64,
}

clear_screen_system :: proc(ctx_res: params.Res(Render_Context), fctx_res: params.Res(Frame_Context), clear_color: params.Res(Clear_Color)) {
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	
	if fctx.encoder == nil || fctx.texture_view == nil do return

	color: wgpu.Color
	if clear_color.ptr != nil {
		color = {clear_color.ptr.r, clear_color.ptr.g, clear_color.ptr.b, clear_color.ptr.a}
	} else {
		color = {0.1, 0.2, 0.3, 1.0} // Default dark blue
	}

	color_attachment := wgpu.RenderPassColorAttachment{
		view = fctx.texture_view,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = color,
	}

	pass_desc := wgpu.RenderPassDescriptor{
		colorAttachmentCount = 1,
		colorAttachments = &color_attachment,
	}

	render_pass := wgpu.CommandEncoderBeginRenderPass(fctx.encoder, &pass_desc)
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)
}
