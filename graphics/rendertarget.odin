package graphics

import "vendor:wgpu"

// render_target_init allocates a WGPU texture and view of the given dimensions.
// If format is .Undefined, it defaults to the context swapchain format.
render_target_init :: proc(
	ctx: ^Render_Context,
	width, height: u32,
	format: wgpu.TextureFormat = .Undefined,
) -> (
	target: Render_Target,
	ok: bool,
) {
	if ctx == nil || ctx.device == nil do return target, false

	target.width = width
	target.height = height

	// Fallback to active swapchain format if undefined
	target.format = (format == .Undefined) ? ctx.config.format : format

	desc := wgpu.TextureDescriptor {
		label         = "Render Target Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = target.format,
		usage         = {.RenderAttachment, .TextureBinding, .CopySrc},
	}
	target.texture = wgpu.DeviceCreateTexture(ctx.device, &desc)
	if target.texture == nil do return target, false

	view_desc := wgpu.TextureViewDescriptor {
		format          = target.format,
		dimension       = ._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	target.texture_view = wgpu.TextureCreateView(target.texture, &view_desc)
	if target.texture_view == nil {
		wgpu.TextureRelease(target.texture)
		target.texture = nil
		return target, false
	}

	return target, true
}

// render_target_destroy safely releases the underlying WGPU texture and view.
render_target_destroy :: proc(target: ^Render_Target) {
	if target.texture_view != nil {
		wgpu.TextureViewRelease(target.texture_view)
		target.texture_view = nil
	}
	if target.texture != nil {
		wgpu.TextureRelease(target.texture)
		target.texture = nil
	}
}
