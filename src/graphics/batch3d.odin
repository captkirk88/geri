package graphics

import "../ecs/params"
import "vendor:wgpu"
import "core:mem"

SHADER_3D :: `
struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    // Simple pass-through. In a real engine, we'd multiply by projection/view matrices.
    out.clip_position = vec4<f32>(model.position, 1.0);
    out.color = model.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
`

init_batch3d :: proc(device: wgpu.Device, format: wgpu.TextureFormat) -> Batch3D {
	batch := Batch3D{}
	batch.vertices = make([dynamic]Vertex3D)
	batch.indices = make([dynamic]u16)

	// Shader
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code  = SHADER_3D,
	}
	shader_desc := wgpu.ShaderModuleDescriptor {
		nextInChain = &shader_source.chain,
	}
	shader := wgpu.DeviceCreateShaderModule(device, &shader_desc)
	defer wgpu.ShaderModuleRelease(shader)

	// Pipeline Layout
	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor{}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &pipeline_layout_desc)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// Vertex Layout
	vertex_attributes := [2]wgpu.VertexAttribute{
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x4, offset = 12, shaderLocation = 1},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout{
		arrayStride    = size_of(Vertex3D),
		stepMode       = .Vertex,
		attributeCount = 2,
		attributes     = &vertex_attributes[0],
	}

	// Blend state
	blend_state := wgpu.BlendState{
		color = {
			srcFactor = .SrcAlpha,
			dstFactor = .OneMinusSrcAlpha,
			operation = .Add,
		},
		alpha = {
			srcFactor = .One,
			dstFactor = .OneMinusSrcAlpha,
			operation = .Add,
		},
	}

	color_target := wgpu.ColorTargetState{
		format    = format,
		blend     = &blend_state,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	fragment_state := wgpu.FragmentState{
		module      = shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}

	// Depth Stencil (optional, skipping for now to keep it simple, but we'd normally want it for 3D)
	// depth_stencil := wgpu.DepthStencilState{ ... }

	pipeline_desc := wgpu.RenderPipelineDescriptor{
		layout = pipeline_layout,
		vertex = {
			module      = shader,
			entryPoint  = "vs_main",
			bufferCount = 1,
			buffers     = &vertex_buffer_layout,
		},
		primitive = {
			topology  = .TriangleList,
			frontFace = .CCW,
			cullMode  = .Back, // Cull back faces for 3D
		},
		multisample = {
			count                  = 1,
			mask                   = 0xFFFFFFFF,
			alphaToCoverageEnabled = false,
		},
		fragment = &fragment_state,
	}

	batch.pipeline = wgpu.DeviceCreateRenderPipeline(device, &pipeline_desc)
	batch.vert_buf_cap = 0
	batch.ind_buf_cap = 0
	return batch
}

destroy_batch3d :: proc(batch: ^Batch3D) {
	if batch.pipeline != nil do wgpu.RenderPipelineRelease(batch.pipeline)
	if batch.vertex_buf != nil do wgpu.BufferRelease(batch.vertex_buf)
	if batch.index_buf != nil do wgpu.BufferRelease(batch.index_buf)
	delete(batch.vertices)
	delete(batch.indices)
}

batch3d_flush :: proc(batch: ^Batch3D, ctx: ^Render_Context, pass: wgpu.RenderPassEncoder) {
	if len(batch.indices) == 0 do return

	vert_size := len(batch.vertices) * size_of(Vertex3D)
	ind_size := len(batch.indices) * size_of(u16)

	// Reallocate vertex buffer if needed
	if vert_size > batch.vert_buf_cap {
		if batch.vertex_buf != nil do wgpu.BufferRelease(batch.vertex_buf)
		batch.vert_buf_cap = max(vert_size, batch.vert_buf_cap * 2, 1024)
		desc := wgpu.BufferDescriptor{
			usage = {.Vertex, .CopyDst},
			size  = u64(batch.vert_buf_cap),
		}
		batch.vertex_buf = wgpu.DeviceCreateBuffer(ctx.device, &desc)
	}

	// Reallocate index buffer if needed
	if ind_size > batch.ind_buf_cap {
		if batch.index_buf != nil do wgpu.BufferRelease(batch.index_buf)
		batch.ind_buf_cap = max(ind_size, batch.ind_buf_cap * 2, 1024)
		batch.ind_buf_cap = (batch.ind_buf_cap + 3) & ~int(3)
		desc := wgpu.BufferDescriptor{
			usage = {.Index, .CopyDst},
			size  = u64(batch.ind_buf_cap),
		}
		batch.index_buf = wgpu.DeviceCreateBuffer(ctx.device, &desc)
	}

	// Upload data
	padded_ind_size := (ind_size + 3) & ~int(3)
	needed_cap := padded_ind_size / size_of(u16)
	if cap(batch.indices) < needed_cap {
		reserve(&batch.indices, needed_cap)
	}

	wgpu.QueueWriteBuffer(ctx.queue, batch.vertex_buf, 0, raw_data(batch.vertices), uint(vert_size))
	wgpu.QueueWriteBuffer(ctx.queue, batch.index_buf, 0, raw_data(batch.indices), uint(padded_ind_size))

	// Draw
	wgpu.RenderPassEncoderSetPipeline(pass, batch.pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, batch.vertex_buf, 0, u64(vert_size))
	wgpu.RenderPassEncoderSetIndexBuffer(pass, batch.index_buf, .Uint16, 0, u64(ind_size))
	wgpu.RenderPassEncoderDrawIndexed(pass, u32(len(batch.indices)), 1, 0, 0, 0)

	// Clear
	clear(&batch.vertices)
	clear(&batch.indices)
}
