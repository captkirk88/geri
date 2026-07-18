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

Antialiasing_Mode :: enum {
	None    = 1,
	MSAA_4x = 4,
}

Pbr_Config :: struct {
	lights:       [4]Pbr_Light,
	num_lights:   i32,
	roughness:    f32,
	metallic:     f32,
	ao:           f32,
	antialiasing: Antialiasing_Mode,
}

Pbr_Uniforms :: struct {
	vp:          linalg.Matrix4f32,
	model:       linalg.Matrix4f32,
	cam_pos:     [3]f32,
	num_lights:  i32,
	lights:      [4]Pbr_Light,
	roughness:   f32,
	metallic:    f32,
	ao:          f32,
	padding:     f32,
}

create_pbr_shader_pass :: proc(
	device: wgpu.Device,
	pbr_shader: ^Shader_Asset,
	format: wgpu.TextureFormat = .BGRA8Unorm,
	multisample_count: u32 = 1,
) -> (Shader_Pass, bool) {
	if pbr_shader == nil || pbr_shader.module == nil do return {}, false
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
