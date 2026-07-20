package graphics

import "../ecs/params"
import "core:mem"
import "vendor:wgpu"

DEFAULT_SHADER_2D :: `
struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = vec4<f32>(model.position, 0.0, 1.0);
    out.color = model.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
`

// init_batch2d initializes a 2D batching context, creating CPU dynamic arrays
// and the default WGPU Render Pipeline. An optional shader source can be provided
// to override the built-in default WGSL shader.
init_batch2d :: proc(
	device: wgpu.Device,
	format: wgpu.TextureFormat,
	source: Shader_Source = nil,
	multisample_count: u32 = 1,
) -> Batch2D {
	batch := Batch2D{}
	batch.vertices = make([dynamic]Vertex2D)
	batch.indices = make([dynamic]u32)

	// Shader module
	effective_source: Shader_Source
	if source != nil {
		effective_source = source
	} else {
		effective_source = Shader_Source_WGSL {
			code = DEFAULT_SHADER_2D,
		}
	}
	shader := shader_module_from_source(device, effective_source)
	defer wgpu.ShaderModuleRelease(shader)

	// Pipeline Layout
	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor{}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// Vertex Layout
	vertex_attributes := [2]wgpu.VertexAttribute {
		{format = .Float32x2, offset = 0, shaderLocation = 0},
		{format = .Float32x4, offset = 8, shaderLocation = 1},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Vertex2D),
		stepMode       = .Vertex,
		attributeCount = 2,
		attributes     = &vertex_attributes[0],
	}

	// Blend state
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
		module      = shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}

	depth_stencil_state := wgpu.DepthStencilState {
		format = .Depth24Plus,
		depthWriteEnabled = .False,
		depthCompare = .Always,
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		layout = pipeline_layout,
		vertex = {
			module = shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
		multisample = {
			count = multisample_count,
			mask = 0xFFFFFFFF,
			alphaToCoverageEnabled = false,
		},
		depthStencil = &depth_stencil_state,
		fragment = &fragment_state,
	}

	batch.pipeline = wgpu.DeviceCreateRenderPipeline(device, &pipeline_desc)
	batch.vert_buf_cap = 0
	batch.ind_buf_cap = 0
	batch.shader_passes = make([dynamic]Shader_Pass)
	batch.active_pass_idx = -1
	return batch
}

// destroy_batch2d releases all CPU-side and WGPU-side resources owned by the 2D batch,
// including all custom shader passes registered inside it.
destroy_batch2d :: proc(batch: ^Batch2D) {
	if batch.pipeline != nil {
		wgpu.RenderPipelineRelease(batch.pipeline)
		batch.pipeline = nil
	}
	if batch.vertex_buf != nil {
		wgpu.BufferRelease(batch.vertex_buf)
		batch.vertex_buf = nil
	}
	if batch.index_buf != nil {
		wgpu.BufferRelease(batch.index_buf)
		batch.index_buf = nil
	}
	for &pass in batch.shader_passes {
		destroy_shader_pass(&pass)
	}
	delete(batch.shader_passes)
	batch.shader_passes = nil
	delete(batch.vertices)
	batch.vertices = nil
	delete(batch.indices)
	batch.indices = nil
}

// batch2d_prepare_buffers ensures GPU buffers are correctly allocated and copies
// current vertex and index data from CPU memory to the GPU buffer.
batch2d_prepare_buffers :: proc(batch: ^Batch2D, ctx: ^Render_Context) {
	if len(batch.vertices) == 0 || len(batch.indices) == 0 do return

	vert_size := len(batch.vertices) * size_of(Vertex2D)
	ind_size := len(batch.indices) * size_of(u32)

	// Reallocate vertex buffer if needed
	// Buffer includes Storage usage to support compute/mesh shader emulation stages
	if vert_size > batch.vert_buf_cap {
		if batch.vertex_buf != nil do wgpu.BufferRelease(batch.vertex_buf)
		batch.vert_buf_cap = max(vert_size, batch.vert_buf_cap * 2, 1024)
		desc := wgpu.BufferDescriptor {
			usage = {.Vertex, .CopyDst, .Storage},
			size  = u64(batch.vert_buf_cap),
		}
		batch.vertex_buf = wgpu.DeviceCreateBuffer(ctx.device, &desc)
	}

	// Reallocate index buffer if needed
	if ind_size > batch.ind_buf_cap {
		if batch.index_buf != nil do wgpu.BufferRelease(batch.index_buf)
		batch.ind_buf_cap = max(ind_size, batch.ind_buf_cap * 2, 1024)
		batch.ind_buf_cap = (batch.ind_buf_cap + 3) & ~int(3)
		desc := wgpu.BufferDescriptor {
			usage = {.Index, .CopyDst, .Storage},
			size  = u64(batch.ind_buf_cap),
		}
		batch.index_buf = wgpu.DeviceCreateBuffer(ctx.device, &desc)
	}

	// Upload data
	padded_ind_size := (ind_size + 3) & ~int(3)
	needed_cap := padded_ind_size / size_of(u32)
	if cap(batch.indices) < needed_cap {
		reserve(&batch.indices, needed_cap)
	}

	wgpu.QueueWriteBuffer(
		ctx.queue,
		batch.vertex_buf,
		0,
		raw_data(batch.vertices),
		uint(vert_size),
	)
	wgpu.QueueWriteBuffer(
		ctx.queue,
		batch.index_buf,
		0,
		raw_data(batch.indices),
		uint(padded_ind_size),
	)
}

// batch2d_draw_buffers issues draw commands for the batch's current GPU buffer contents,
// using either the default pipeline or the active custom render pass (and its uniforms).
batch2d_draw_buffers :: proc(batch: ^Batch2D, pass: wgpu.RenderPassEncoder, index_count: u32) {
	if batch.vertex_buf == nil || batch.index_buf == nil || index_count == 0 do return

	pipeline := batch.pipeline
	bind_group: wgpu.BindGroup = nil

	// Check if there is an active custom Render shader pass
	if batch.active_pass_idx >= 0 && batch.active_pass_idx < len(batch.shader_passes) {
		sp := batch.shader_passes[batch.active_pass_idx]
		if sp.type == .Render && sp.render_pipeline != nil {
			pipeline = sp.render_pipeline
			bind_group = sp.bind_group
		}
	}

	vert_size := u64(len(batch.vertices) * size_of(Vertex2D))
	if vert_size == 0 do vert_size = u64(batch.vert_buf_cap)
	call := Indexed_Draw_Call {
		pipeline    = pipeline,
		bind_group  = bind_group,
		vertex_buf  = batch.vertex_buf,
		vertex_size = vert_size,
		index_buf   = batch.index_buf,
		index_size  = u64(batch.ind_buf_cap),
		index_count = index_count,
	}
	render_draw_indexed_call(pass, call)
}

// batch2d_flush prepares WGPU buffers with the current CPU vertices, draws them,
// and clears the CPU-side data array.
batch2d_flush :: proc(batch: ^Batch2D, ctx: ^Render_Context, pass: wgpu.RenderPassEncoder) {
	if len(batch.indices) == 0 do return

	batch2d_prepare_buffers(batch, ctx)
	batch2d_draw_buffers(batch, pass, u32(len(batch.indices)))

	// Clear dynamic CPU buffers after draw
	clear(&batch.vertices)
	clear(&batch.indices)
}

// batch2d_run_compute executes a Compute Shader Pass on the batch's vertex and index buffers.
// Automatically creates and updates bind groups if buffers are reallocated.
batch2d_run_compute :: proc(
	batch: ^Batch2D,
	ctx: ^Render_Context,
	encoder: wgpu.CommandEncoder,
	pass_idx: int,
	workgroups_x: u32,
	workgroups_y := u32(1),
	workgroups_z := u32(1),
) {
	if pass_idx < 0 || pass_idx >= len(batch.shader_passes) do return
	pass := &batch.shader_passes[pass_idx]
	if pass.type != .Compute || pass.compute_pipeline == nil do return

	// Upload CPU data to buffers if CPU buffers contain any elements
	if len(batch.vertices) > 0 && len(batch.indices) > 0 {
		batch2d_prepare_buffers(batch, ctx)
	}

	if batch.vertex_buf == nil || batch.index_buf == nil do return

	// Check if bind group needs to be created or recreated due to buffer reallocation
	if pass.bind_group == nil ||
	   pass.last_vertex_buf != batch.vertex_buf ||
	   pass.last_index_buf != batch.index_buf {
		if pass.bind_group != nil {
			wgpu.BindGroupRelease(pass.bind_group)
		}

		// Binding 0: Vertices storage
		// Binding 1: Indices storage
		// Binding 2: Uniform Buffer (optional)
		entries: [3]wgpu.BindGroupEntry
		entry_count: u32 = 2

		entries[0] = {
			binding = 0,
			buffer  = batch.vertex_buf,
			offset  = 0,
			size    = u64(batch.vert_buf_cap),
		}
		entries[1] = {
			binding = 1,
			buffer  = batch.index_buf,
			offset  = 0,
			size    = u64(batch.ind_buf_cap),
		}

		if pass.uniform_buf != nil {
			entry_count = 3
			entries[2] = {
				binding = 2,
				buffer  = pass.uniform_buf,
				offset  = 0,
				size    = (pass.uniform_size + 255) & ~u64(255),
			}
		}

		bg_desc := wgpu.BindGroupDescriptor {
			layout     = pass.bind_group_layout,
			entryCount = uint(entry_count),
			entries    = &entries[0],
		}
		pass.bind_group = wgpu.DeviceCreateBindGroup(ctx.device, &bg_desc)
		pass.last_vertex_buf = batch.vertex_buf
		pass.last_index_buf = batch.index_buf
	}

	// Begin compute pass and dispatch
	compute_pass_desc := wgpu.ComputePassDescriptor{}
	compute_pass := wgpu.CommandEncoderBeginComputePass(encoder, &compute_pass_desc)
	defer {
		wgpu.ComputePassEncoderEnd(compute_pass)
		wgpu.ComputePassEncoderRelease(compute_pass)
	}

	wgpu.ComputePassEncoderSetPipeline(compute_pass, pass.compute_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(compute_pass, 0, pass.bind_group, nil)
	wgpu.ComputePassEncoderDispatchWorkgroups(
		compute_pass,
		workgroups_x,
		workgroups_y,
		workgroups_z,
	)
}

// batch2d_add_shader_pass registers a custom shader pass into the batch, returning its index.
batch2d_add_shader_pass :: proc(batch: ^Batch2D, pass: Shader_Pass) -> int {
	append(&batch.shader_passes, pass)
	return len(batch.shader_passes) - 1
}

// batch2d_set_active_pass sets the active shader pass index. Set to -1 to use default rendering.
batch2d_set_active_pass :: proc(batch: ^Batch2D, pass_idx: int) {
	batch.active_pass_idx = pass_idx
}

// batch2d_set_clip_rect sets the clipping boundaries of the 2D batch, intersecting with the previous clip rect if clipping was already enabled.
batch2d_set_clip_rect :: proc(batch: ^Batch2D, rect: [4]f32) {
	if batch.clip_enabled {
		cx0 := max(batch.clip_rect[0], rect[0])
		cy0 := max(batch.clip_rect[1], rect[1])
		cx1 := min(batch.clip_rect[0] + batch.clip_rect[2], rect[0] + rect[2])
		cy1 := min(batch.clip_rect[1] + batch.clip_rect[3], rect[1] + rect[3])
		cw := max(cx1 - cx0, 0.0)
		ch := max(cy1 - cy0, 0.0)
		batch.clip_rect = {cx0, cy0, cw, ch}
		batch.clip_enabled = cw > 0.0 && ch > 0.0
	} else {
		batch.clip_rect = rect
		batch.clip_enabled = rect[2] > 0.0 && rect[3] > 0.0
	}
}

// batch2d_disable_clip disables clipping on the 2D batch.
batch2d_disable_clip :: proc(batch: ^Batch2D) {
	batch.clip_enabled = false
}

// batch2d_clip_quad clips a quad's 2D coordinate bounds to the active clip rectangle on the CPU.
// Returns false if the quad is completely discarded/outside the clip area.
batch2d_clip_quad :: proc(batch: ^Batch2D, x0, y0, x1, y1: ^f32) -> bool {
	if !batch.clip_enabled do return true

	cx0 := batch.clip_rect[0]
	cy0 := batch.clip_rect[1]
	cx1 := batch.clip_rect[0] + batch.clip_rect[2]
	cy1 := batch.clip_rect[1] + batch.clip_rect[3]

	qmin_x := min(x0^, x1^)
	qmax_x := max(x0^, x1^)
	qmin_y := min(y0^, y1^)
	qmax_y := max(y0^, y1^)

	if qmax_x < cx0 || qmin_x > cx1 || qmax_y < cy0 || qmin_y > cy1 {
		return false
	}

	x0^ = clamp(x0^, cx0, cx1)
	x1^ = clamp(x1^, cx0, cx1)
	y0^ = clamp(y0^, cy0, cy1)
	y1^ = clamp(y1^, cy0, cy1)

	return abs(x1^ - x0^) > 0.0001 && abs(y1^ - y0^) > 0.0001
}

batch2d_draw :: proc {
	batch2d_draw_buffers,
}
