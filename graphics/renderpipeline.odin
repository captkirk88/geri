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

	render_pass := begin_render_pass(fctx, wgpu.LoadOp.Clear, color)
	defer end_render_pass(render_pass)

	if batch3d.ptr != nil {
		batch3d_flush(batch3d.ptr, ctx, render_pass)
	}

	if batch2d.ptr != nil {
		batch2d_flush(batch2d.ptr, ctx, render_pass)
	}
}

begin_render_pass :: proc {
	begin_frame_render_pass,
	begin_target_render_pass,
}

begin_frame_render_pass :: proc(
	fctx: ^Frame_Context,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) -> wgpu.RenderPassEncoder {
	color_attachment := wgpu.RenderPassColorAttachment {
		view          = fctx.texture_view,
		loadOp        = load_op,
		storeOp       = store_op,
		clearValue    = clear_color,
		depthSlice    = wgpu.DEPTH_SLICE_UNDEFINED,
		resolveTarget = resolve_target,
	}
	pass_desc := wgpu.RenderPassDescriptor {
		colorAttachmentCount   = 1,
		colorAttachments       = &color_attachment,
		depthStencilAttachment = depth_stencil,
	}
	return wgpu.CommandEncoderBeginRenderPass(fctx.encoder, &pass_desc)
}

begin_target_render_pass :: proc(
	encoder: wgpu.CommandEncoder,
	target: Render_Target,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) -> wgpu.RenderPassEncoder {
	color_attachment := wgpu.RenderPassColorAttachment {
		view          = target.texture_view,
		loadOp        = load_op,
		storeOp       = store_op,
		clearValue    = clear_color,
		depthSlice    = wgpu.DEPTH_SLICE_UNDEFINED,
		resolveTarget = resolve_target,
	}
	pass_desc := wgpu.RenderPassDescriptor {
		colorAttachmentCount   = 1,
		colorAttachments       = &color_attachment,
		depthStencilAttachment = depth_stencil,
	}
	return wgpu.CommandEncoderBeginRenderPass(encoder, &pass_desc)
}

end_render_pass :: proc(pass: wgpu.RenderPassEncoder) {
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)
}

render_batch2d :: proc {
	render_batch2d_frame,
	render_batch2d_target,
}

render_batch2d_frame :: proc(
	batch: ^Batch2D,
	ctx: ^Render_Context,
	fctx: ^Frame_Context,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) {
	pass := begin_frame_render_pass(
		fctx,
		load_op,
		clear_color,
		store_op,
		depth_stencil,
		resolve_target,
	)
	defer end_render_pass(pass)
	batch2d_flush(batch, ctx, pass)
}

render_batch2d_target :: proc(
	batch: ^Batch2D,
	ctx: ^Render_Context,
	encoder: wgpu.CommandEncoder,
	target: Render_Target,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) {
	pass := begin_target_render_pass(
		encoder,
		target,
		load_op,
		clear_color,
		store_op,
		depth_stencil,
		resolve_target,
	)
	defer end_render_pass(pass)

	batch2d_flush(batch, ctx, pass)
}

render_batch3d :: proc {
	render_batch3d_frame,
	render_batch3d_target,
}

render_batch3d_frame :: proc(
	batch: ^Batch3D,
	ctx: ^Render_Context,
	fctx: ^Frame_Context,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) {
	pass := begin_frame_render_pass(
		fctx,
		load_op,
		clear_color,
		store_op,
		depth_stencil,
		resolve_target,
	)
	defer end_render_pass(pass)
	batch3d_flush(batch, ctx, pass)
}

render_batch3d_target :: proc(
	batch: ^Batch3D,
	ctx: ^Render_Context,
	encoder: wgpu.CommandEncoder,
	target: Render_Target,
	load_op: wgpu.LoadOp = .Load,
	clear_color: wgpu.Color = {},
	store_op: wgpu.StoreOp = .Store,
	depth_stencil: ^wgpu.RenderPassDepthStencilAttachment = nil,
	resolve_target: wgpu.TextureView = nil,
) {
	pass := begin_target_render_pass(
		encoder,
		target,
		load_op,
		clear_color,
		store_op,
		depth_stencil,
		resolve_target,
	)
	defer end_render_pass(pass)

	batch3d_flush(batch, ctx, pass)
}
