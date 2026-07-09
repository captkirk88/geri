package graphics

import "base:runtime"
import "core:fmt"
import "core:io"
import "vendor:wgpu"

// Compiles a WGSL shader code into a render pipeline matching the vertex layout (2D or 3D).
// If uniform_size > 0, it creates a unified uniform buffer and binds it at @group(0) @binding(0).
create_render_shader_pass :: proc(
	device: wgpu.Device,
	wgsl_source: io.Reader,
	vertex_entry: string = "vs_main",
	fragment_entry: string = "fs_main",
	is_3d: bool = false,
	format: wgpu.TextureFormat = .BGRA8Unorm,
	uniform_size: u64 = 0,
) -> (
	pass: Shader_Pass,
	ok: bool,
) {
	pass.type = .Render
	pass.uniform_size = uniform_size

	// Read WGSL source from Reader
	wgsl_code, read_ok := read_all(wgsl_source, context.temp_allocator)
	if !read_ok do return pass, false

	// Compile Shader Module
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = wgsl_code,
	}
	shader_desc := wgpu.ShaderModuleDescriptor {
		nextInChain = &shader_source.chain,
	}
	pass.shader_module = wgpu.DeviceCreateShaderModule(device, &shader_desc)
	if pass.shader_module == nil do return pass, false

	// Setup Bind Group and layout if uniforms are requested
	pipeline_layout: wgpu.PipelineLayout
	if uniform_size > 0 {
		aligned_size := (uniform_size + 255) & ~u64(255)
		buf_desc := wgpu.BufferDescriptor {
			usage = {.Uniform, .CopyDst},
			size  = aligned_size,
		}
		pass.uniform_buf = wgpu.DeviceCreateBuffer(device, &buf_desc)
		if pass.uniform_buf == nil {
			wgpu.ShaderModuleRelease(pass.shader_module)
			return pass, false
		}

		// Create Bind Group Layout
		layout_entry := wgpu.BindGroupLayoutEntry {
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, hasDynamicOffset = false, minBindingSize = 0},
		}
		layout_desc := wgpu.BindGroupLayoutDescriptor {
			entryCount = 1,
			entries    = &layout_entry,
		}
		pass.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(device, &layout_desc)
		if pass.bind_group_layout == nil {
			wgpu.BufferRelease(pass.uniform_buf)
			wgpu.ShaderModuleRelease(pass.shader_module)
			return pass, false
		}

		// Create Bind Group
		bg_entry := wgpu.BindGroupEntry {
			binding = 0,
			buffer  = pass.uniform_buf,
			offset  = 0,
			size    = aligned_size,
		}
		bg_desc := wgpu.BindGroupDescriptor {
			layout     = pass.bind_group_layout,
			entryCount = 1,
			entries    = &bg_entry,
		}
		pass.bind_group = wgpu.DeviceCreateBindGroup(device, &bg_desc)
		if pass.bind_group == nil {
			wgpu.BindGroupLayoutRelease(pass.bind_group_layout)
			wgpu.BufferRelease(pass.uniform_buf)
			wgpu.ShaderModuleRelease(pass.shader_module)
			return pass, false
		}

		pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
			bindGroupLayoutCount = 1,
			bindGroupLayouts     = &pass.bind_group_layout,
		}
		pipeline_layout = wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	} else {
		pipeline_layout_desc := wgpu.PipelineLayoutDescriptor{}
		pipeline_layout = wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	}
	if pipeline_layout == nil {
		destroy_shader_pass(&pass)
		return pass, false
	}
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// Vertex Layout configuration
	vertex_buffer_layout: wgpu.VertexBufferLayout
	vertex_attributes_2d: [2]wgpu.VertexAttribute
	vertex_attributes_3d: [2]wgpu.VertexAttribute

	if !is_3d {
		vertex_attributes_2d = {
			{format = .Float32x2, offset = 0, shaderLocation = 0},
			{format = .Float32x4, offset = 8, shaderLocation = 1},
		}
		vertex_buffer_layout = {
			arrayStride    = size_of(Vertex2D),
			stepMode       = .Vertex,
			attributeCount = 2,
			attributes     = &vertex_attributes_2d[0],
		}
	} else {
		vertex_attributes_3d = {
			{format = .Float32x3, offset = 0, shaderLocation = 0},
			{format = .Float32x4, offset = 12, shaderLocation = 1},
		}
		vertex_buffer_layout = {
			arrayStride    = size_of(Vertex3D),
			stepMode       = .Vertex,
			attributeCount = 2,
			attributes     = &vertex_attributes_3d[0],
		}
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
		module      = pass.shader_module,
		entryPoint  = fragment_entry,
		targetCount = 1,
		targets     = &color_target,
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		layout = pipeline_layout,
		vertex = {
			module = pass.shader_module,
			entryPoint = vertex_entry,
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = is_3d ? .Back : .None},
		multisample = {count = 1, mask = 0xFFFFFFFF, alphaToCoverageEnabled = false},
		fragment = &fragment_state,
	}

	pass.render_pipeline = wgpu.DeviceCreateRenderPipeline(device, &pipeline_desc)
	if pass.render_pipeline == nil {
		destroy_shader_pass(&pass)
		return pass, false
	}

	return pass, true
}

// Compiles a WGSL compute shader and sets up a default bind group layout:
// - Binding 0: Vertex Buffer (storage)
// - Binding 1: Index Buffer (storage)
// - Binding 2: Uniform Buffer (uniform, optional - active if uniform_size > 0)
create_compute_shader_pass :: proc(
	device: wgpu.Device,
	wgsl_source: io.Reader,
	entry_point: string = "cs_main",
	uniform_size: u64 = 0,
) -> (
	pass: Shader_Pass,
	ok: bool,
) {
	pass.type = .Compute
	pass.uniform_size = uniform_size

	// Read WGSL source from Reader
	wgsl_code, read_ok := read_all(wgsl_source, context.temp_allocator)
	if !read_ok do return pass, false

	// Compile Shader Module
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = wgsl_code,
	}
	shader_desc := wgpu.ShaderModuleDescriptor {
		nextInChain = &shader_source.chain,
	}
	pass.shader_module = wgpu.DeviceCreateShaderModule(device, &shader_desc)
	if pass.shader_module == nil do return pass, false

	// Setup layout entries
	entries: [3]wgpu.BindGroupLayoutEntry
	entry_count: u32 = 2

	entries[0] = {
		binding = 0,
		visibility = {.Compute},
		buffer = {type = .Storage, hasDynamicOffset = false, minBindingSize = 0},
	}
	entries[1] = {
		binding = 1,
		visibility = {.Compute},
		buffer = {type = .Storage, hasDynamicOffset = false, minBindingSize = 0},
	}

	if uniform_size > 0 {
		entry_count = 3
		aligned_size := (uniform_size + 255) & ~u64(255)
		buf_desc := wgpu.BufferDescriptor {
			usage = {.Uniform, .CopyDst},
			size  = aligned_size,
		}
		pass.uniform_buf = wgpu.DeviceCreateBuffer(device, &buf_desc)
		if pass.uniform_buf == nil {
			wgpu.ShaderModuleRelease(pass.shader_module)
			return pass, false
		}

		entries[2] = {
			binding = 2,
			visibility = {.Compute},
			buffer = {type = .Uniform, hasDynamicOffset = false, minBindingSize = 0},
		}
	}

	layout_desc := wgpu.BindGroupLayoutDescriptor {
		entryCount = uint(entry_count),
		entries    = &entries[0],
	}
	pass.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(device, &layout_desc)
	if pass.bind_group_layout == nil {
		destroy_shader_pass(&pass)
		return pass, false
	}

	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &pass.bind_group_layout,
	}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	if pipeline_layout == nil {
		destroy_shader_pass(&pass)
		return pass, false
	}
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	pipeline_desc := wgpu.ComputePipelineDescriptor {
		layout = pipeline_layout,
		compute = {module = pass.shader_module, entryPoint = entry_point},
	}
	pass.compute_pipeline = wgpu.DeviceCreateComputePipeline(device, &pipeline_desc)
	if pass.compute_pipeline == nil {
		destroy_shader_pass(&pass)
		return pass, false
	}

	return pass, true
}

// Writes new uniform data from the CPU to the GPU uniform buffer.
shader_pass_update_uniforms :: proc(pass: ^Shader_Pass, ctx: ^Render_Context, uniforms: any) {
	if pass.uniform_buf == nil || pass.uniform_size == 0 do return

	uniforms_info := runtime.type_info_base(type_info_of(uniforms.id))
	uniforms_size := uniforms_info.size

	assert(
		u64(uniforms_size) <= pass.uniform_size,
		fmt.tprintf(
			"Uniform struct (size %d) exceeds uniform buffer capacity %d",
			uniforms_size,
			pass.uniform_size,
		),
	)

	wgpu.QueueWriteBuffer(ctx.queue, pass.uniform_buf, 0, uniforms.data, uint(uniforms_size))
}

// Compiles a wgpu.ShaderModule from a Shader_Source union value.
// Returns nil if the source variant is unrecognized or compilation fails.
shader_module_from_source :: proc(
	device: wgpu.Device,
	source: Shader_Source,
) -> wgpu.ShaderModule {
	switch s in source {
	case Shader_Source_WGSL:
		src := wgpu.ShaderSourceWGSL {
			chain = {sType = .ShaderSourceWGSL},
			code = s.code,
		}
		desc := wgpu.ShaderModuleDescriptor {
			nextInChain = &src.chain,
		}
		return wgpu.DeviceCreateShaderModule(device, &desc)
	case Shader_Source_SPIRV:
		src := wgpu.ShaderSourceSPIRV {
			chain = {sType = .ShaderSourceSPIRV},
			codeSize = u32(len(s.code)),
			code = raw_data(s.code),
		}
		desc := wgpu.ShaderModuleDescriptor {
			nextInChain = &src.chain,
		}
		return wgpu.DeviceCreateShaderModule(device, &desc)
	case Shader_Source_GLSL:
		src := wgpu.ShaderSourceGLSL {
			chain = {sType = .ShaderSourceGLSL},
			stage = s.stage,
			code = s.code,
		}
		desc := wgpu.ShaderModuleDescriptor {
			nextInChain = &src.chain,
		}
		return wgpu.DeviceCreateShaderModule(device, &desc)
	}
	return nil
}

// Releases all WGPU resources owned by the shader pass.
destroy_shader_pass :: proc(pass: ^Shader_Pass) {
	if pass.render_pipeline != nil {
		wgpu.RenderPipelineRelease(pass.render_pipeline)
		pass.render_pipeline = nil
	}
	if pass.compute_pipeline != nil {
		wgpu.ComputePipelineRelease(pass.compute_pipeline)
		pass.compute_pipeline = nil
	}
	if pass.bind_group != nil {
		wgpu.BindGroupRelease(pass.bind_group)
		pass.bind_group = nil
	}
	if pass.bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(pass.bind_group_layout)
		pass.bind_group_layout = nil
	}
	if pass.uniform_buf != nil {
		wgpu.BufferRelease(pass.uniform_buf)
		pass.uniform_buf = nil
	}
	if pass.shader_module != nil {
		wgpu.ShaderModuleRelease(pass.shader_module)
		pass.shader_module = nil
	}
}

@(private = "file")
read_all :: proc(r: io.Reader, allocator := context.allocator) -> (string, bool) {
	buf: [4096]byte
	b: [dynamic]byte
	b.allocator = allocator

	success := false
	defer if !success do delete(b)

	for {
		n, err := io.read(r, buf[:])
		if n > 0 {
			append(&b, ..buf[:n])
		}
		if err != nil {
			if err == .EOF {
				success = true
				break
			}
			return "", false
		}
	}
	return string(b[:]), true
}
