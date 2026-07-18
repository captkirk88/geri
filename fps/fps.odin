package fps

import "../app"
import ecs "../ecs"
import "../ecs/params"
import errors "../errors"
import graphics "../graphics"
import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "vendor:wgpu"

// Number of samples to average over for a smooth FPS reading.
FPS_SAMPLE_COUNT :: 64

// Resource stored in the ECS world tracking frame timing.
Fps_Counter :: struct {
	samples:      [FPS_SAMPLE_COUNT]f64,
	sample_index: int,
	sample_count: int,
	// Customization
	color:        [4]f32,
	font_size:    f32,
}

// Dedicated batch for the HUD overlay — flushed in a separate LoadOp:.Load
// render pass so FPS text is always composited on top of the scene.
Fps_Batch :: struct {
	batch: graphics.Batch2D,
}

// Optional settings for FPS behavior.
// .Capped uses VSYNC-backed FIFO; .Uncapped requests immediate presentation.
Fps_Settings :: enum {
	Capped,
	Uncapped,
}

// Returns the current averaged FPS.
fps_average :: proc(c: ^Fps_Counter) -> f64 {
	if c.sample_count == 0 do return 0
	sum: f64
	for i in 0 ..< c.sample_count {
		sum += c.samples[i]
	}
	return sum / f64(c.sample_count)
}

// System: runs in First — samples the wall-clock delta and records it.
@(tag = "system")
fps_tick_system :: proc(fps_res: params.Res(Fps_Counter), dt: params.Res(app.DeltaTime)) {
	c := fps_res.ptr
	if c == nil do return

	dt_val := dt.ptr != nil ? dt.ptr.f32_seconds : f32(0.0)
	if dt_val <= 0.0 do return

	dt_sec := f64(dt_val)
	c.samples[c.sample_index] = 1.0 / dt_sec
	c.sample_index = (c.sample_index + 1) % FPS_SAMPLE_COUNT
	if c.sample_count < FPS_SAMPLE_COUNT {
		c.sample_count += 1
	}
}

// Applies FPS runtime settings that affect swapchain/present behavior.
@(tag = "system")
fps_settings_system :: proc(
	settings_res: params.Res(Fps_Settings),
	ctx_res: params.Res(graphics.Render_Context),
) {
	settings := settings_res.ptr
	ctx := ctx_res.ptr
	if settings == nil || ctx == nil || ctx.device == nil || ctx.surface == nil do return

	desired_mode := wgpu.PresentMode.Fifo
	if settings^ == .Uncapped {
		desired_mode = .Immediate
	}

	if ctx.config.presentMode == desired_mode do return

	config := ctx.config
	config.presentMode = desired_mode
	wgpu.SurfaceConfigure(ctx.surface, &config)
	ctx.config = config
}

// System: runs in PostRender (before frame_present_system) — draws the FPS
// counter into the dedicated HUD batch, then flushes it into a fresh
// LoadOp:.Load render pass so it composites on top of the full scene.
@(tag = "system")
fps_render_system :: proc(
	fps_res: params.Res(Fps_Counter),
	batch_res: params.Res(Fps_Batch),
	ctx_res: params.Res(graphics.Render_Context),
	fctx_res: params.Res(graphics.Frame_Context),
	font_res: params.Res(graphics.Font),
) {
	c := fps_res.ptr
	batch_wrapper := batch_res.ptr
	ctx := ctx_res.ptr
	fctx := fctx_res.ptr
	font := font_res.ptr

	if c == nil || batch_wrapper == nil || ctx == nil || ctx.device == nil do return
	if fctx == nil || fctx.encoder == nil || fctx.texture_view == nil do return
	if font == nil do return

	batch := &batch_wrapper.batch

	avg := fps_average(c)
	text := fmt.tprintf(
		"[bg_opacity=0.5][bg=black][color=#ffdd44]FPS:[/color] [color=#ffffff]%.1f[/color][/bg][/bg_opacity]",
		avg,
	)

	w := f32(ctx.config.width)
	h := f32(ctx.config.height)

	// Pixel-space orthographic VP — maps world pixels to NDC (y-up, origin center)
	vp := linalg.matrix_ortho3d_f32(-w / 2, w / 2, -h / 2, h / 2, 0.0, 1.0)

	padding: f32 = 8.0
	font_size := c.font_size
	if font_size <= 0 do font_size = font.pixel_height
	x := -w / 2 + padding
	y := h / 2 - font_size - padding

	graphics.draw_text(batch, text, x, y, font, 1.0, c.color, vp)

	graphics.render_batch2d(batch, ctx, fctx)
}

// System: cleans up the Fps_Batch on app exit.
@(tag = "system")
fps_cleanup_system :: proc(
	exit_events: params.EventReader(app.App_Exit_Event),
	batch_res: params.Res(Fps_Batch),
) {
	if len(exit_events.events) > 0 {
		if batch_res.ptr != nil {
			graphics.destroy_batch2d(&batch_res.ptr.batch)
		}
	}
}

// Internal helper: creates the dedicated HUD batch and registers it as a resource.
@(private)
fps_plugin_build_impl :: proc(settings: Fps_Settings, plugin: app.Plugin, a: ^app.App) -> (err: errors.Error, ok: bool) {
	// Create the dedicated HUD batch. Render_Plugin must have already run.
	render_ctx := ecs.world_get_resource(&a.world, graphics.Render_Context)
	if render_ctx == nil || render_ctx.device == nil {
		return errors.new("Render_Plugin not initialized — Render_Context missing"), false
	}
	pbr_config := ecs.world_get_resource(&a.world, graphics.Pbr_Config)
	sample_count: u32 = 1
	if pbr_config != nil {
		sample_count = u32(pbr_config.antialiasing)
	}
	hud_batch := Fps_Batch {
		batch = graphics.init_batch2d(render_ctx.device, render_ctx.config.format, nil, sample_count),
	}
	app.app_add_resource(a, hud_batch)

	counter := Fps_Counter {
		color     = {1, 1, 1, 1},
		font_size = 0, // 0 = derive from loaded font's pixel_height
	}
	app.app_add_resource(a, counter)
	app.app_add_resource(a, settings)

	// Load font for Fps overlay
	font: graphics.Font
	// TODO:have a default CC0 licensed font
	if graphics.font_init(&font, "C:\\Windows\\Fonts\\arial.ttf", 32.0) {
		ecs.world_add_resource(&a.world, font, proc(f: ^graphics.Font, alloc: runtime.Allocator) {
			graphics.font_destroy(f)
		})
	}

	app.app_add_system(a, app.First, fps_settings_system)
	app.app_add_system(a, app.First, fps_tick_system)

	// PostRender: runs after main_render_system has submitted the scene batch,
	// but before frame_present_system calls wgpu.SurfacePresent.
	app.app_add_system(
		a,
		app.PostRender,
		fps_render_system,
		before = []app.System_Dependency{rawptr(graphics.frame_present_system)},
	)

	app.app_add_system(
		a,
		app.Last,
		fps_cleanup_system,
		//after = []app.System_Dependency{rawptr(graphics.frame_present_system)},
		before = []app.System_Dependency{rawptr(graphics.render_cleanup_system)},
	)
	return {}, true
}

fps_plugin_build :: proc(settings: Fps_Settings) -> proc(plugin: app.Plugin, a: ^app.App) -> (errors.Error, bool) {
	build_capped := proc(plugin: app.Plugin, a: ^app.App) -> (errors.Error, bool) {
		return fps_plugin_build_impl(.Capped, plugin, a)
	}

	build_uncapped := proc(plugin: app.Plugin, a: ^app.App) -> (errors.Error, bool) {
		return fps_plugin_build_impl(.Uncapped, plugin, a)
	}

	switch settings {
	case .Uncapped:
		return build_uncapped
	case .Capped:
		return build_capped
	}
	return build_capped // default
}

// Fps_Plugin adds an averaged FPS counter overlay to the top-left of the screen.
// Must be added AFTER Render_Plugin so the Render_Context resource is available.
// Requires a graphics.Font resource to be registered (e.g. via font_init in Startup).
Fps_Plugin :: proc(init_settings: Fps_Settings = .Capped) -> app.Plugin {
	return app.Plugin{build = fps_plugin_build(init_settings)}
}
