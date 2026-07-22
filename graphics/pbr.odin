package graphics

import "core:math/linalg"
import wgpu "vendor:wgpu"
import "../errors"

Pbr_Light :: struct {
	position:  [3]f32,
	intensity: f32,
	color:     [3]f32,
	radius:    f32,
}


Pbr_Config :: struct {
	roughness:    f32,
	metallic:     f32,
	ao:           f32,
	antialiasing: Antialiasing_Mode,
}

Pbr_Uniforms :: struct {
	vp:             linalg.Matrix4f32,
	model:          linalg.Matrix4f32,
	cam_pos:        [3]f32,
	num_lights:     i32,
	lights:         [4]Pbr_Light,
	roughness:      f32,
	metallic:       f32,
	ao:             f32,
	num_joints:     i32,
	joint_matrices: [64]linalg.Matrix4f32,
}

// Creates a 1x1 white texture for use as a fallback when no diffuse texture is available.
create_fallback_texture :: proc(device: wgpu.Device, queue: wgpu.Queue) -> (wgpu.Texture, wgpu.TextureView) {
	desc := wgpu.TextureDescriptor {
		usage         = {.TextureBinding, .CopyDst},
		dimension     = ._2D,
		size          = {1, 1, 1},
		format        = .RGBA8UnormSrgb,
		mipLevelCount = 1,
		sampleCount   = 1,
	}
	tex := wgpu.DeviceCreateTexture(device, &desc)
	white_pixel := [4]u8{255, 255, 255, 255}
	wgpu.QueueWriteTexture(
		queue,
		&{texture = tex, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		&white_pixel,
		size_of(white_pixel),
		&{offset = 0, bytesPerRow = 4, rowsPerImage = 1},
		&{1, 1, 1},
	)
	view := wgpu.TextureCreateView(tex, nil)
	return tex, view
}

create_pbr_shader_pass :: proc(
	device: wgpu.Device,
	pbr_shader: ^Shader_Asset,
	format: wgpu.TextureFormat = .BGRA8Unorm,
	multisample_count: u32 = 1,
	default_texture_view: wgpu.TextureView = nil,
	default_sampler: wgpu.Sampler = nil,
) -> (Shader_Pass, bool) {
	if pbr_shader == nil || pbr_shader.module == nil do return {}, false

	// If we have a texture view and sampler, create with texture-aware layout
	if default_texture_view != nil && default_sampler != nil {
		res := create_pbr_shader_pass_with_texture(
			device,
			pbr_shader.module,
			format,
			multisample_count,
			default_texture_view,
			default_sampler,
		)
		#partial switch r in res {
		case errors.Err(errors.Error):
			return {}, false
		case errors.Ok(Shader_Pass):
			return r.value, true
		}
		return {}, false
	}

	// Fallback: no texture bindings
	res := create_shader_pass_from_module(
		device,
		pbr_shader.module,
		"vs_main",
		"fs_main",
		true,
		format,
		size_of(Pbr_Uniforms),
		multisample_count,
	)
	#partial switch r in res {
	case errors.Err(errors.Error):
		return {}, false
	case errors.Ok(Shader_Pass):
		return r.value, true
	}
	return {}, false
}

// Creates a PBR shader pass with texture and sampler bindings at @group(0) @binding(1) and @binding(2).
create_pbr_shader_pass_with_texture :: proc(
	device: wgpu.Device,
	shader_module: wgpu.ShaderModule,
	format: wgpu.TextureFormat,
	multisample_count: u32,
	texture_view: wgpu.TextureView,
	sampler: wgpu.Sampler,
) -> errors.Result(Shader_Pass, errors.Error) {
	pass: Shader_Pass
	pass.type = .Render
	pass.shader_module = shader_module

	uniform_size := u64(size_of(Pbr_Uniforms))
	aligned_size := (uniform_size + 15) & ~u64(15)
	pass.uniform_size = aligned_size

	// Create Uniform Buffer
	buf_desc := wgpu.BufferDescriptor {
		usage = {.Uniform, .CopyDst},
		size  = aligned_size,
	}
	pass.uniform_buf = wgpu.DeviceCreateBuffer(device, &buf_desc)
	if pass.uniform_buf == nil {
		return errors.Err(errors.Error){error = errors.new("Failed to create Uniform Buffer")}
	}

	// Create Bind Group Layout with uniform + texture + sampler
	layout_entries := [3]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, hasDynamicOffset = false, minBindingSize = 0},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D, multisampled = false},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			sampler = {type = .Filtering},
		},
	}
	layout_desc := wgpu.BindGroupLayoutDescriptor {
		entryCount = 3,
		entries    = &layout_entries[0],
	}
	pass.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(device, &layout_desc)
	if pass.bind_group_layout == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create PBR Bind Group Layout")}
	}

	// Create Bind Group
	bg_entries := [3]wgpu.BindGroupEntry {
		{binding = 0, buffer = pass.uniform_buf, offset = 0, size = aligned_size},
		{binding = 1, textureView = texture_view},
		{binding = 2, sampler = sampler},
	}
	bg_desc := wgpu.BindGroupDescriptor {
		layout     = pass.bind_group_layout,
		entryCount = 3,
		entries    = &bg_entries[0],
	}
	pass.bind_group = wgpu.DeviceCreateBindGroup(device, &bg_desc)
	if pass.bind_group == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create PBR Bind Group")}
	}

	// Pipeline Layout
	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &pass.bind_group_layout,
	}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	if pipeline_layout == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create Pipeline Layout")}
	}
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// Vertex Layout (3D with UV)
	vertex_attributes := [4]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x4, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 28, shaderLocation = 2},
		{format = .Float32x3, offset = 36, shaderLocation = 3},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Vertex3D),
		stepMode       = .Vertex,
		attributeCount = 4,
		attributes     = &vertex_attributes[0],
	}

	blend_state := wgpu.BlendState {
		color = {srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
		alpha = {srcFactor = .One, dstFactor = .OneMinusSrcAlpha, operation = .Add},
	}
	color_target := wgpu.ColorTargetState {
		format    = format,
		blend     = &blend_state,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment_state := wgpu.FragmentState {
		module      = shader_module,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}

	depth_stencil_state := wgpu.DepthStencilState {
		format = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare = .Less,
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		layout = pipeline_layout,
		vertex = {
			module      = shader_module,
			entryPoint  = "vs_main",
			bufferCount = 1,
			buffers     = &vertex_buffer_layout,
		},
		fragment    = &fragment_state,
		primitive   = {topology = .TriangleList, frontFace = .CCW, cullMode = .Back},
		depthStencil = &depth_stencil_state,
		multisample = {count = multisample_count, mask = ~u32(0)},
	}
	pass.render_pipeline = wgpu.DeviceCreateRenderPipeline(device, &pipeline_desc)
	if pass.render_pipeline == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create PBR Render Pipeline")}
	}

	return errors.Ok(Shader_Pass){value = pass}
}

// Rebuilds a PBR bind group with a new texture view, keeping the same layout and uniform buffer.
pbr_rebuild_bind_group :: proc(
	device: wgpu.Device,
	pass: ^Shader_Pass,
	texture_view: wgpu.TextureView,
	sampler: wgpu.Sampler,
) {
	if pass.bind_group != nil {
		wgpu.BindGroupRelease(pass.bind_group)
	}
	aligned_size := pass.uniform_size
	bg_entries := [3]wgpu.BindGroupEntry {
		{binding = 0, buffer = pass.uniform_buf, offset = 0, size = aligned_size},
		{binding = 1, textureView = texture_view},
		{binding = 2, sampler = sampler},
	}
	bg_desc := wgpu.BindGroupDescriptor {
		layout     = pass.bind_group_layout,
		entryCount = 3,
		entries    = &bg_entries[0],
	}
	pass.bind_group = wgpu.DeviceCreateBindGroup(device, &bg_desc)
}

create_pbr_skinned_shader_pass :: proc(
	device: wgpu.Device,
	pbr_shader: ^Shader_Asset,
	format: wgpu.TextureFormat = .BGRA8Unorm,
	multisample_count: u32 = 1,
	default_texture_view: wgpu.TextureView = nil,
	default_sampler: wgpu.Sampler = nil,
) -> (Shader_Pass, bool) {
	if pbr_shader == nil || pbr_shader.module == nil do return {}, false

	if default_texture_view != nil && default_sampler != nil {
		res := create_pbr_skinned_shader_pass_with_texture(
			device,
			pbr_shader.module,
			format,
			multisample_count,
			default_texture_view,
			default_sampler,
		)
		#partial switch r in res {
		case errors.Err(errors.Error):
			return {}, false
		case errors.Ok(Shader_Pass):
			return r.value, true
		}
		return {}, false
	}

	return {}, false
}

create_pbr_skinned_shader_pass_with_texture :: proc(
	device: wgpu.Device,
	shader_module: wgpu.ShaderModule,
	format: wgpu.TextureFormat,
	multisample_count: u32,
	texture_view: wgpu.TextureView,
	sampler: wgpu.Sampler,
) -> errors.Result(Shader_Pass, errors.Error) {
	pass: Shader_Pass
	pass.type = .Render
	pass.shader_module = shader_module

	uniform_size := u64(size_of(Pbr_Uniforms))
	aligned_size := (uniform_size + 15) & ~u64(15)
	pass.uniform_size = aligned_size

	// Create Uniform Buffer
	buf_desc := wgpu.BufferDescriptor {
		usage = {.Uniform, .CopyDst},
		size  = aligned_size,
	}
	pass.uniform_buf = wgpu.DeviceCreateBuffer(device, &buf_desc)
	if pass.uniform_buf == nil {
		return errors.Err(errors.Error){error = errors.new("Failed to create Uniform Buffer")}
	}

	// Create Bind Group Layout with uniform + texture + sampler
	layout_entries := [3]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, hasDynamicOffset = false, minBindingSize = 0},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D, multisampled = false},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			sampler = {type = .Filtering},
		},
	}
	layout_desc := wgpu.BindGroupLayoutDescriptor {
		entryCount = 3,
		entries    = &layout_entries[0],
	}
	pass.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(device, &layout_desc)
	if pass.bind_group_layout == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create PBR Bind Group Layout")}
	}

	// Create Bind Group
	bg_entries := [3]wgpu.BindGroupEntry {
		{binding = 0, buffer = pass.uniform_buf, offset = 0, size = aligned_size},
		{binding = 1, textureView = texture_view},
		{binding = 2, sampler = sampler},
	}
	bg_desc := wgpu.BindGroupDescriptor {
		layout     = pass.bind_group_layout,
		entryCount = 3,
		entries    = &bg_entries[0],
	}
	pass.bind_group = wgpu.DeviceCreateBindGroup(device, &bg_desc)
	if pass.bind_group == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create PBR Bind Group")}
	}

	// Pipeline Layout
	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &pass.bind_group_layout,
	}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	if pipeline_layout == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create Pipeline Layout")}
	}
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// Skinned Vertex Layout
	vertex_attributes := [6]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x4, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 28, shaderLocation = 2},
		{format = .Float32x3, offset = 36, shaderLocation = 3},
		{format = .Float32x4, offset = 48, shaderLocation = 4},
		{format = .Float32x4, offset = 64, shaderLocation = 5},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(SkinnedVertex3D),
		stepMode       = .Vertex,
		attributeCount = 6,
		attributes     = &vertex_attributes[0],
	}

	blend_state := wgpu.BlendState {
		color = {srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
		alpha = {srcFactor = .One, dstFactor = .OneMinusSrcAlpha, operation = .Add},
	}
	color_target := wgpu.ColorTargetState {
		format    = format,
		blend     = &blend_state,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment_state := wgpu.FragmentState {
		module      = shader_module,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}

	depth_stencil_state := wgpu.DepthStencilState {
		format = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare = .Less,
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		layout = pipeline_layout,
		vertex = {
			module      = shader_module,
			entryPoint  = "vs_main",
			bufferCount = 1,
			buffers     = &vertex_buffer_layout,
		},
		fragment    = &fragment_state,
		primitive   = {topology = .TriangleList, frontFace = .CCW, cullMode = .Back},
		depthStencil = &depth_stencil_state,
		multisample = {count = multisample_count, mask = ~u32(0)},
	}
	pass.render_pipeline = wgpu.DeviceCreateRenderPipeline(device, &pipeline_desc)
	if pass.render_pipeline == nil {
		destroy_shader_pass(&pass)
		return errors.Err(errors.Error){error = errors.new("Failed to create Skinned PBR Render Pipeline")}
	}

	return errors.Ok(Shader_Pass){value = pass}
}

