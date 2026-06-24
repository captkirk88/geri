package windowing

import "../app"
import "../ecs"
import "vendor:sdl3"

// Default descriptor if not set by the user
DEFAULT_WINDOW_DESCRIPTOR :: Window_Descriptor {
	title      = "Geri Engine",
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

	if !sdl3.Init({.VIDEO}) {
		return
	}

	flags: sdl3.WindowFlags
	if desc.resizable do flags += {.RESIZABLE}
	if desc.fullscreen do flags += {.FULLSCREEN}

	window := sdl3.CreateWindow(cstring(raw_data(desc.title)), desc.width, desc.height, flags)

	app.app_add_resource(a, Window_Context{window = window})

	// Add event pump system
	app.app_add_system(a, app.First, event_pump_system)
}

Window_Plugin :: proc(descriptor: ^Window_Descriptor = nil) -> app.Plugin {
	return app.Plugin{build = window_plugin_build, destroy = nil, data = descriptor}
}
