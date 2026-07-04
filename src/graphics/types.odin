package graphics

import "vendor:wgpu"

// Render_Context manages the global WebGPU handles required to interface with the GPU adapter,
// device, command queue, and configure render surfaces.
Render_Context :: struct {
	instance: wgpu.Instance,             // Handle to the global WGPU instance.
	surface:  wgpu.Surface,              // OS-specific window surface for rendering.
	adapter:  wgpu.Adapter,              // Hardware device adapter (physical GPU info).
	device:   wgpu.Device,               // Logical GPU connection for resource creation.
	queue:    wgpu.Queue,                // Command queue to submit work to the GPU.
	config:   wgpu.SurfaceConfiguration, // Display/format configuration for the render surface.
}

// Frame_Context stores transient, per-frame resources used to record and encode
// rendering/compute commands for a single frame.
Frame_Context :: struct {
	texture_view: wgpu.TextureView,     // Active target view of the swapchain texture.
	encoder:      wgpu.CommandEncoder,    // Encoder to record draw and compute commands.
	texture:      wgpu.Texture,           // Underlying swapchain texture being presented.
}

// Screenshot_Format defines the image file types supported when capturing screenshots.
Screenshot_Format :: enum {
	TGA, // Targa image format.
	BMP, // Windows Bitmap format.
	QOI, // Quite OK Image Format.
	PNG, // Portable Network Graphics format.
}

// Screenshot_Request represents a command to capture the active frame buffer
// and write it to the local file system.
Screenshot_Request :: struct {
	path:   string,            // Target file system path for the output file.
	format: Screenshot_Format, // Desired image file format.
}

// Screenshot_Recording manages the state of continuous frame capturing to output an animated GIF.
Screenshot_Recording :: struct {
	path:   string,          // Target file system path for the output GIF.
	frames: [dynamic][]byte, // Slices containing raw RGBA frame buffers.
	width:  int,             // Target width of the frames.
	height: int,             // Target height of the frames.
	active: bool,            // Whether recording is actively capturing frames.
}

// Vertex2D represents a standard vertex layout for 2D batch drawing.
Vertex2D :: struct {
	position: [2]f32, // 2D position coordinates (X, Y).
	color:    [4]f32, // Normalized RGBA color coordinates [0.0 - 1.0].
}

// Vertex3D represents a standard vertex layout for 3D batch drawing.
Vertex3D :: struct {
	position: [3]f32, // 3D position coordinates (X, Y, Z).
	color:    [4]f32, // Normalized RGBA color coordinates [0.0 - 1.0].
}

// Shader_Stage represents the logical pipeline stage of a graphics/compute shader.
// Geometry and Tessellation stages are physically emulated using Compute Shaders on modern WebGPU APIs.
Shader_Stage :: enum {
	Vertex,                 // Process input vertex attributes.
	Fragment,               // Compute pixel/fragment output colors.
	Mesh,                   // Amplification & mesh shading (emulated via Compute).
	Compute,                // General-purpose GPU compute.
	Geometry,               // Primitive amplification (emulated via Compute).
	TessellationControl,    // Determines patch tessellation factors (emulated via Compute).
	TessellationEvaluation, // Evaluates patch positions (emulated via Compute).
}

// Shader_Pass_Type classifies a shader pass into either a Render (vertex/fragment)
// or Compute pipeline pass.
Shader_Pass_Type :: enum {
	Render,  // Pipeline with Vertex/Fragment stages.
	Compute, // Pipeline with a Compute stage.
}

// Shader_Pass represents a compiled shader module and its corresponding pipeline,
// with a unified uniform buffer and automatic bind group caching.
Shader_Pass :: struct {
	type:              Shader_Pass_Type,         // Whether this is a Render or Compute pass.
	label:             string,                   // Human-readable identifier for debugging.
	shader_module:     wgpu.ShaderModule,        // Compiled WGSL shader module.
	render_pipeline:   wgpu.RenderPipeline,      // Compiled render pipeline (valid if type is Render).
	compute_pipeline:  wgpu.ComputePipeline,     // Compiled compute pipeline (valid if type is Compute).
	uniform_buf:       wgpu.Buffer,              // Unified GPU uniform buffer for uniform variables.
	uniform_size:      u64,                      // Allocation size of the GPU uniform buffer in bytes.
	bind_group_layout: wgpu.BindGroupLayout,     // Bind group layout defining pipeline bindings.
	bind_group:        wgpu.BindGroup,           // Cached bind group binding storage buffers and uniforms.
	last_vertex_buf:   wgpu.Buffer,              // Cached vertex buffer handle used to detect buffer changes.
	last_index_buf:    wgpu.Buffer,              // Cached index buffer handle used to detect buffer changes.
}

// Batch2D manages dynamic batches of 2D lines/triangles, uploading them to GPU buffers.
// It supports custom shader passes (Compute and Render stages).
Batch2D :: struct {
	vertices:        [dynamic]Vertex2D,    // Dynamic CPU buffer for 2D vertices.
	indices:         [dynamic]u32,         // Dynamic CPU buffer for indices.
	vertex_buf:      wgpu.Buffer,          // GPU buffer containing vertex data.
	index_buf:       wgpu.Buffer,          // GPU buffer containing index data.
	pipeline:        wgpu.RenderPipeline,  // Default render pipeline.
	vert_buf_cap:    int,                  // Current capacity in bytes of vertex_buf.
	ind_buf_cap:     int,                  // Current capacity in bytes of index_buf.
	shader_passes:   [dynamic]Shader_Pass, // Registered custom shader passes.
	active_pass_idx: int,                  // Index of the active custom pass. -1 uses default.
}

// Batch3D manages dynamic batches of 3D lines/triangles, uploading them to GPU buffers.
// It supports custom shader passes (Compute and Render stages).
Batch3D :: struct {
	vertices:        [dynamic]Vertex3D,    // Dynamic CPU buffer for 3D vertices.
	indices:         [dynamic]u32,         // Dynamic CPU buffer for indices.
	vertex_buf:      wgpu.Buffer,          // GPU buffer containing vertex data.
	index_buf:       wgpu.Buffer,          // GPU buffer containing index data.
	pipeline:        wgpu.RenderPipeline,  // Default render pipeline.
	vert_buf_cap:    int,                  // Current capacity in bytes of vertex_buf.
	ind_buf_cap:     int,                  // Current capacity in bytes of index_buf.
	shader_passes:   [dynamic]Shader_Pass, // Registered custom shader passes.
	active_pass_idx: int,                  // Index of the active custom pass. -1 uses default.
}
