package graphics

import wgpu "vendor:wgpu"

Mesh :: struct {
	vertex_buffer: wgpu.Buffer,
	index_buffer:  wgpu.Buffer,
	vertex_count:  u32,
	index_count:   u32,
}

create_mesh :: proc(device: wgpu.Device, vertices: []$V, indices: []u32) -> (Mesh, bool) {
	if len(vertices) == 0 || len(indices) == 0 do return {}, false

	v_size := u64(len(vertices) * size_of(V))
	v_desc := wgpu.BufferDescriptor {
		usage            = {.Vertex, .CopyDst},
		size             = v_size,
		mappedAtCreation = false,
	}
	vertex_buffer := wgpu.DeviceCreateBuffer(device, &v_desc)
	if vertex_buffer == nil do return {}, false

	i_size := u64(len(indices) * size_of(u32))
	i_desc := wgpu.BufferDescriptor {
		usage            = {.Index, .CopyDst},
		size             = i_size,
		mappedAtCreation = false,
	}
	index_buffer := wgpu.DeviceCreateBuffer(device, &i_desc)
	if index_buffer == nil {
		wgpu.BufferRelease(vertex_buffer)
		return {}, false
	}

	return Mesh {
		vertex_buffer = vertex_buffer,
		index_buffer  = index_buffer,
		vertex_count  = u32(len(vertices)),
		index_count   = u32(len(indices)),
	}, true
}

destroy_mesh :: proc(mesh: ^Mesh) {
	if mesh.vertex_buffer != nil {
		wgpu.BufferRelease(mesh.vertex_buffer)
		mesh.vertex_buffer = nil
	}
	if mesh.index_buffer != nil {
		wgpu.BufferRelease(mesh.index_buffer)
		mesh.index_buffer = nil
	}
	mesh.vertex_count = 0
	mesh.index_count = 0
}
