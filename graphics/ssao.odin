package graphics

import "core:math"
import "core:math/rand"
import "vendor:wgpu"

// SSAO Hemisphere Kernel and Noise generation + Pass parameters
SSAO_Pass_Context :: struct {
	ssao_pipeline:      wgpu.RenderPipeline,
	ssao_bind_group:   wgpu.BindGroup,
	blur_pipeline:      wgpu.RenderPipeline,
	blur_bind_group:   wgpu.BindGroup,
	fxaa_pipeline:      wgpu.RenderPipeline,
	fxaa_bind_group:   wgpu.BindGroup,
	kernel_buffer:      wgpu.Buffer,
	noise_texture:      wgpu.Texture,
	noise_view:         wgpu.TextureView,
	noise_sampler:      wgpu.Sampler,
	bind_group_layout:  wgpu.BindGroupLayout,
}

SSAO_Uniforms :: struct {
	projection:       matrix[4, 4]f32,
	inv_projection:   matrix[4, 4]f32,
	view:             matrix[4, 4]f32,
	samples:          [64][4]f32,
	radius:           f32,
	bias:             f32,
	power:            f32,
	kernel_size:      i32,
	screen_size:      [2]f32,
	noise_scale:      [2]f32,
}

// Generates 64 hemisphere sample vectors oriented along +Z axis with falloff curve
generate_ssao_kernel :: proc(kernel: ^[64][4]f32, size: i32) {
	num := size > 64 ? 64 : (size < 1 ? 32 : size)
	for i in 0 ..< num {
		// Random direction in hemisphere (+Z)
		x := rand.float32_range(-1.0, 1.0)
		y := rand.float32_range(-1.0, 1.0)
		z := rand.float32_range(0.1, 1.0)
		
		len := math.sqrt(x*x + y*y + z*z)
		x /= len
		y /= len
		z /= len
		
		// Scale samples closer to center
		scale := f32(i) / f32(num)
		scale = math.lerp(f32(0.1), f32(1.0), scale * scale)
		
		kernel[i] = [4]f32{x * scale, y * scale, z * scale, 0.0}
	}
}

// Creates a 4x4 tiled noise texture containing random rotation vectors
create_ssao_noise_texture :: proc(ctx: ^Render_Context) -> (wgpu.Texture, wgpu.TextureView) {
	if ctx == nil || ctx.device == nil do return nil, nil
	
	noise_data: [16][4]f32
	for i in 0 ..< 16 {
		x := rand.float32_range(-1.0, 1.0)
		y := rand.float32_range(-1.0, 1.0)
		noise_data[i] = [4]f32{x, y, 0.0, 0.0}
	}

	desc := wgpu.TextureDescriptor {
		usage         = {.TextureBinding, .CopyDst},
		dimension     = ._2D,
		size          = {4, 4, 1},
		format        = .RGBA32Float,
		mipLevelCount = 1,
		sampleCount   = 1,
	}
	tex := wgpu.DeviceCreateTexture(ctx.device, &desc)
	if tex == nil do return nil, nil

	dst := wgpu.TexelCopyTextureInfo {
		texture  = tex,
		mipLevel = 0,
		origin   = {0, 0, 0},
		aspect   = .All,
	}
	layout := wgpu.TexelCopyBufferLayout {
		offset       = 0,
		bytesPerRow  = u32(4 * size_of([4]f32)),
		rowsPerImage = 4,
	}
	size := wgpu.Extent3D{width = 4, height = 4, depthOrArrayLayers = 1}

	wgpu.QueueWriteTexture(
		ctx.queue,
		&dst,
		&noise_data[0],
		size_of(noise_data),
		&layout,
		&size,
	)

	view := wgpu.TextureCreateView(tex, nil)
	return tex, view
}
