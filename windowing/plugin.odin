package windowing

import "../app"
import "../ecs"
import params "../ecs/params"
import "core:log"
import "core:strconv"
import "core:strings"
import "vendor:sdl3"

// Default descriptor if not set by the user
DEFAULT_WINDOW_DESCRIPTOR :: Window_Descriptor {
	title      = "Geri ECS",
	width      = 800,
	height     = 600,
	resizable  = true,
	fullscreen = false,
}

window_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) {
	desc := ecs.world_get_resource(&a.world, Window_Descriptor)
	if desc == nil {
		d := DEFAULT_WINDOW_DESCRIPTOR
		if plugin.data != nil {
			d = (cast(^Window_Descriptor)plugin.data)^
		}
		app.app_add_resource(a, d)
		desc = ecs.world_get_resource(&a.world, Window_Descriptor)
	}

	if !sdl3.Init({.VIDEO, .GAMEPAD, .AUDIO, .JOYSTICK, .HAPTIC, .SENSOR, .EVENTS}) {
		err_cstr := sdl3.GetError()
		defer delete_cstring(err_cstr)
		err_str, err := strings.clone_from_cstring(err_cstr)
		if err != nil {
			err_str = "Unknown SDL initialization error"
		}
		log.error("Failed to initialize SDL: %s", err_str)
		return
	}

	flags: sdl3.WindowFlags
	if desc.resizable do flags += {.RESIZABLE}
	if desc.fullscreen do flags += {.FULLSCREEN}

	window := sdl3.CreateWindow(cstring(raw_data(desc.title)), desc.width, desc.height, flags)

	app.app_add_resource(a, Window_Context{window = window})

	// Add event pump system
	app.app_add_system(a, app.First, event_pump_system)
	app.app_add_system(a, app.Last, window_cleanup_system)
}

@(tag = "system")
window_cleanup_system :: proc(
	exit_events: params.EventReader(app.App_Exit_Event),
	window_ctx: params.Res(Window_Context),
) {
	if len(exit_events.events) > 0 {
		if window_ctx.ptr != nil && window_ctx.ptr.window != nil {
			sdl3.DestroyWindow(window_ctx.ptr.window)
			window_ctx.ptr.window = nil
		}
		sdl3.Quit()
	}
}

Window_Plugin :: proc(descriptor: ^Window_Descriptor = nil) -> app.Plugin {
	return app.Plugin{build = window_plugin_build, destroy = nil, data = descriptor}
}
