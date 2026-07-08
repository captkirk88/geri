package graphics

import "../app"
import "../ecs/params"
import "vendor:wgpu"

Clear_Color :: struct {
	r, g, b, a: f64,
}

Indexed_Draw_Call :: struct {
	pipeline:    wgpu.RenderPipeline,
	bind_group:  wgpu.BindGroup,
	vertex_buf:  wgpu.Buffer,
	vertex_size: u64,
	index_buf:   wgpu.Buffer,
	index_size:  u64,
	index_count: u32,
}

// Create a static GPU buffer with the given usage flags and data, returning the created buffer.
//
// The buffer created and queued.
// The caller is responsible for releasing the buffer when it is no longer needed.
render_create_static_buffer :: proc(
	ctx: ^Render_Context,
	usage: wgpu.BufferUsageFlags,
	data: rawptr,
	size: u64,
) -> wgpu.Buffer {
	if ctx == nil || ctx.device == nil || ctx.queue == nil || data == nil || size == 0 do return nil
	desc := wgpu.BufferDescriptor {
		usage = usage | {.CopyDst},
		size  = size,
	}
	buf := wgpu.DeviceCreateBuffer(ctx.device, &desc)
	if buf == nil do return nil
	wgpu.QueueWriteBuffer(ctx.queue, buf, 0, data, uint(size))
	return buf
}

// Write data to a GPU buffer using the provided render context and queue
render_write_buffer :: proc(
	ctx: ^Render_Context,
	buffer: wgpu.Buffer,
	data: rawptr,
	size: u64,
	offset: u64 = 0,
) {
	if ctx == nil || ctx.queue == nil || buffer == nil || data == nil || size == 0 do return
	wgpu.QueueWriteBuffer(ctx.queue, buffer, offset, data, uint(size))
}

// Bind buffer resources to a bind group for use in shaders
render_bind_group_entry_buffer :: proc(
	binding: u32,
	buffer: wgpu.Buffer,
	size: u64,
	offset: u64 = 0,
) -> wgpu.BindGroupEntry {
	return wgpu.BindGroupEntry{binding = binding, buffer = buffer, offset = offset, size = size}
}

// Bind texture resources to a bind group for use in shaders
render_bind_group_entry_texture :: proc(
	binding: u32,
	texture_view: wgpu.TextureView,
) -> wgpu.BindGroupEntry {
	return wgpu.BindGroupEntry{binding = binding, textureView = texture_view}
}

// Bind sampler resources to a bind group for use in shaders
render_bind_group_entry_sampler :: proc(
	binding: u32,
	sampler: wgpu.Sampler,
) -> wgpu.BindGroupEntry {
	return wgpu.BindGroupEntry{binding = binding, sampler = sampler}
}

// Render a single indexed draw call using the provided render pass encoder
render_draw_indexed_call :: proc(pass: wgpu.RenderPassEncoder, call: Indexed_Draw_Call) {
	if pass == nil do return
	if call.pipeline == nil || call.vertex_buf == nil || call.index_buf == nil || call.index_count == 0 do return

	wgpu.RenderPassEncoderSetPipeline(pass, call.pipeline)
	if call.bind_group != nil {
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, call.bind_group, nil)
	}
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, call.vertex_buf, 0, call.vertex_size)
	wgpu.RenderPassEncoderSetIndexBuffer(pass, call.index_buf, .Uint32, 0, call.index_size)
	wgpu.RenderPassEncoderDrawIndexed(pass, call.index_count, 1, 0, 0, 0)
}

// Render a single indexed draw call using the provided render pass encoder and a bind group created from the provided layout and entries
render_draw_indexed_with_bind_group :: proc(
	pass: wgpu.RenderPassEncoder,
	device: wgpu.Device,
	call: Indexed_Draw_Call,
	layout: wgpu.BindGroupLayout,
	entries: []wgpu.BindGroupEntry,
) {
	if pass == nil || device == nil || layout == nil || len(entries) == 0 do return

	bg_desc := wgpu.BindGroupDescriptor {
		layout     = layout,
		entryCount = uint(len(entries)),
		entries    = &entries[0],
	}
	bind_group := wgpu.DeviceCreateBindGroup(device, &bg_desc)
	if bind_group == nil do return
	defer wgpu.BindGroupRelease(bind_group)

	call_with_bind_group := call
	call_with_bind_group.bind_group = bind_group
	render_draw_indexed_call(pass, call_with_bind_group)
}

@(tag = "system") // tagged so that users know this is a system and can be added to a schedule
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
