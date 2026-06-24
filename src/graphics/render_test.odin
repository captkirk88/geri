#+feature using-stmt
package graphics

import "../app"
import "../ecs"
import "../windowing"
import "core:testing"
import "core:time"
import "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"
import "core:fmt"

// Note: WGPU and SDL3 test is skipped by default in `odin test` because
// the Odin test runner spawns worker threads, which causes SEH exceptions in DX12.
// To test this, you can invoke it from a standalone executable on the main thread.
// @(test)
test_render_pipeline_initialization :: proc(t: ^testing.T) {

	application := app.app_init([]app.Plugin{windowing.Window_Plugin(), Render_Plugin()})
	defer {
		window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
		if window_ctx != nil && window_ctx.window != nil {
			sdl3.DestroyWindow(window_ctx.window)
		}
		sdl3.Quit()

		app.app_destroy(&application)
	}

	window_ctx := ecs.world_get_resource(&application.world, windowing.Window_Context)
	testing.expect(t, window_ctx != nil, "Window_Context should be initialized")
	if window_ctx != nil {
		testing.expect(t, window_ctx.window != nil, "SDL Window should be created")
	}

	render_ctx := ecs.world_get_resource(&application.world, Render_Context)
	testing.expect(t, render_ctx != nil, "Render_Context should be initialized")
	if render_ctx != nil {
		testing.expect(t, render_ctx.device != nil, "WGPU Device should be created")
	}

	app.app_run_schedule(&application, app.Startup)

	for !application.should_exit {
		batch2d := ecs.world_get_resource(&application.world, Batch2D)
		if batch2d != nil {
			append(
				&batch2d.vertices,
				Vertex2D{position = {0.0, 0.5}, color = {1.0, 0.0, 0.0, 1.0}},
			)
			append(
				&batch2d.vertices,
				Vertex2D{position = {-0.5, -0.5}, color = {0.0, 1.0, 0.0, 1.0}},
			)
			append(
				&batch2d.vertices,
				Vertex2D{position = {0.5, -0.5}, color = {0.0, 0.0, 1.0, 1.0}},
			)
			append(&batch2d.indices, 0, 1, 2)
		}
		app.app_update(&application)
	}

	ecs.emit(&application.world, app.App_Exit_Event{})
	app.app_update(&application) // Trigger cleanup systems
}
