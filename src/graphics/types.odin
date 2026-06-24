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
}
