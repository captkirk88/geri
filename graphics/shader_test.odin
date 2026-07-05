package graphics

import "core:testing"

@(test)
test_batch2d_shader_pass_lifecycle :: proc(t: ^testing.T) {
	// Setup a mock Batch2D (without device/WGPU stuff active for standard headless tests)
	batch := Batch2D{}
	batch.vertices = make([dynamic]Vertex2D)
	batch.indices = make([dynamic]u32)
	batch.shader_passes = make([dynamic]Shader_Pass)
	batch.active_pass_idx = -1

	// Test adding a dummy Shader_Pass
	pass := Shader_Pass {
		type  = .Render,
		label = "Dummy Render Pass",
	}

	idx := batch2d_add_shader_pass(&batch, pass)
	testing.expect_value(t, idx, 0)
	testing.expect_value(t, len(batch.shader_passes), 1)

	batch2d_set_active_pass(&batch, idx)
	testing.expect_value(t, batch.active_pass_idx, 0)

	// Add another compute pass
	pass2 := Shader_Pass {
		type  = .Compute,
		label = "Dummy Compute Pass",
	}
	idx2 := batch2d_add_shader_pass(&batch, pass2)
	testing.expect_value(t, idx2, 1)

	batch2d_set_active_pass(&batch, idx2)
	testing.expect_value(t, batch.active_pass_idx, 1)

	// Destroy batch
	destroy_batch2d(&batch)
	testing.expect(t, batch.shader_passes == nil)
	testing.expect(t, batch.vertices == nil)
	testing.expect(t, batch.indices == nil)
}

@(test)
test_batch3d_shader_pass_lifecycle :: proc(t: ^testing.T) {
	// Setup a mock Batch3D
	batch := Batch3D{}
	batch.vertices = make([dynamic]Vertex3D)
	batch.indices = make([dynamic]u32)
	batch.shader_passes = make([dynamic]Shader_Pass)
	batch.active_pass_idx = -1

	// Test adding a dummy Shader_Pass
	pass := Shader_Pass {
		type  = .Render,
		label = "Dummy Render Pass 3D",
	}

	idx := batch3d_add_shader_pass(&batch, pass)
	testing.expect_value(t, idx, 0)
	testing.expect_value(t, len(batch.shader_passes), 1)

	batch3d_set_active_pass(&batch, idx)
	testing.expect_value(t, batch.active_pass_idx, 0)

	// Destroy batch
	destroy_batch3d(&batch)
	testing.expect(t, batch.shader_passes == nil)
	testing.expect(t, batch.vertices == nil)
	testing.expect(t, batch.indices == nil)
}

@(test)
test_render_target_nil_safety :: proc(t: ^testing.T) {
	target, ok := render_target_init(nil, 800, 600)
	testing.expect(t, !ok)
	testing.expect(t, target.texture == nil)
	testing.expect(t, target.texture_view == nil)

	ctx := Render_Context{}
	target2, ok2 := render_target_init(&ctx, 800, 600)
	testing.expect(t, !ok2)
	testing.expect(t, target2.texture == nil)
	testing.expect(t, target2.texture_view == nil)

	// Safe to destroy even if nil/zeroed
	render_target_destroy(&target2)
}

