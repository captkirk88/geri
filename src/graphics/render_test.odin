#+feature using-stmt
package graphics

import "../app"
import "../ecs"
import "../windowing"
import "core:testing"
import "vendor:sdl3"
import "vendor:wgpu"

@(test)
test_render_pipeline_initialization :: proc(t: ^testing.T) {
	application := app.app_init([]app.Plugin{windowing.Window_Plugin(), Render_Plugin()})
	defer {

		render_ctx := ecs.world_get_resource(&application.world, Render_Context)
		if render_ctx != nil {
			wgpu.QueueRelease(render_ctx.queue)
			wgpu.DeviceRelease(render_ctx.device)
			wgpu.AdapterRelease(render_ctx.adapter)
			wgpu.SurfaceRelease(render_ctx.surface)
			wgpu.InstanceRelease(render_ctx.instance)
		}

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
}
