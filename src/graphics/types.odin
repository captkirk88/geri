package graphics

import "vendor:wgpu"

Render_Context :: struct {
	instance: wgpu.Instance,
	surface:  wgpu.Surface,
	adapter:  wgpu.Adapter,
	device:   wgpu.Device,
	queue:    wgpu.Queue,
	config:   wgpu.SurfaceConfiguration,
}

Frame_Context :: struct {
	texture_view: wgpu.TextureView,
	encoder:      wgpu.CommandEncoder,
	texture:      wgpu.Texture,
}

Screenshot_Format :: enum {
	TGA,
	BMP,
	QOI,
	PNG,
}

Screenshot_Request :: struct {
	path:   string,
	format: Screenshot_Format,
}

Vertex2D :: struct {
	position: [2]f32,
	color:    [4]f32,
}

Vertex3D :: struct {
	position: [3]f32,
	color:    [4]f32,
}

Batch2D :: struct {
	vertices:     [dynamic]Vertex2D,
	indices:      [dynamic]u32,
	vertex_buf:   wgpu.Buffer,
	index_buf:    wgpu.Buffer,
	pipeline:     wgpu.RenderPipeline,
	vert_buf_cap: int,
	ind_buf_cap:  int,
}

Batch3D :: struct {
	vertices:     [dynamic]Vertex3D,
	indices:      [dynamic]u32,
	vertex_buf:   wgpu.Buffer,
	index_buf:    wgpu.Buffer,
	pipeline:     wgpu.RenderPipeline,
	vert_buf_cap: int,
	ind_buf_cap:  int,
}
