package graphics

Antialiasing_Mode :: enum {
	None    = 0,
	FXAA    = 1, // Fast Approximate Antialiasing
	TAA     = 2, // Temporal Antialiasing
	MSAA_2x = 2, // Hardware 2x MSAA
	MSAA_4x = 4, // Hardware 4x MSAA
	MSAA_8x = 8, // Hardware 8x MSAA
}

antialiasing_sample_count :: proc(mode: Antialiasing_Mode) -> u32 {
	#partial switch mode {
	case .MSAA_2x: return 2
	case .MSAA_4x: return 4
	case .MSAA_8x: return 8
	case:          return 1
	}
}

Graphics_Config :: struct {
	// Framebuffer & Format Pipeline Settings
	hdr:              bool,              // Enable RGBA16Float / HDR rendering target
	depth_stencil:    bool,              // Enable depth/stencil buffer pass & attachments
	antialiasing:     Antialiasing_Mode, // Antialiasing technique

	// Ambient Occlusion / SSAO Post-Processing
	ssao_enabled:     bool,              // Toggle SSAO post-pass
	ssao_radius:      f32,              // SSAO sampling radius in world space (e.g., 0.5)
	ssao_bias:        f32,              // SSAO depth bias to prevent self-shadowing acne (e.g., 0.025)
	ssao_kernel_size: i32,              // Number of sample hemisphere vectors (e.g., 32 or 64)
	ssao_power:       f32,              // SSAO intensity / contrast multiplier (e.g., 2.0)

	// Temporal AA Parameters
	taa_feedback:     f32,              // History frame blend ratio (e.g., 0.9)

	// PBR / Lighting Settings
	pbr:              Pbr_Config,
}

default_graphics_config :: proc() -> Graphics_Config {
	return Graphics_Config {
		hdr              = false,
		depth_stencil    = true,
		antialiasing     = .None,
		ssao_enabled     = true,
		ssao_radius      = 0.5,
		ssao_bias        = 0.025,
		ssao_kernel_size = 32,
		ssao_power       = 2.0,
		taa_feedback     = 0.9,
		pbr              = Pbr_Config{
			roughness = 0.5,
			metallic  = 0.0,
			ao        = 1.0,
		},
	}
}
