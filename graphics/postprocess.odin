package graphics

import "vendor:wgpu"

POSTPROCESS_WGSL :: #load("embed_assets/postprocess.wgsl", string)

init_postprocess_pass :: proc(ctx: ^Render_Context) -> (SSAO_Pass_Context, bool) {
	if ctx == nil || ctx.device == nil do return {}, false
	pass: SSAO_Pass_Context

	shader_source := wgpu.ChainedStruct {
		sType = .ShaderSourceWGSL,
	}
	shader_wgsl := wgpu.ShaderSourceWGSL {
		chain = shader_source,
		code  = POSTPROCESS_WGSL,
	}
	shader_desc := wgpu.ShaderModuleDescriptor {
		nextInChain = &shader_wgsl.chain,
	}
	module := wgpu.DeviceCreateShaderModule(ctx.device, &shader_desc)
	if module == nil do return {}, false

	noise_tex, noise_view := create_ssao_noise_texture(ctx)
	pass.noise_texture = noise_tex
	pass.noise_view = noise_view

	sampler_desc := wgpu.SamplerDescriptor {
		addressModeU = .Repeat,
		addressModeV = .Repeat,
		addressModeW = .Repeat,
		magFilter    = .Nearest,
		minFilter    = .Nearest,
	}
	pass.noise_sampler = wgpu.DeviceCreateSampler(ctx.device, &sampler_desc)

	return pass, true
}
