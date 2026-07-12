package windowing

import "../app"
import "../ecs"
import params "../ecs/params"
import errors "../errors"
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

window_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) -> (err: errors.Error, ok: bool) {
	desc := ecs.world_get_resource(&a.world, Window_Descriptor)
	if desc == nil {
		d := DEFAULT_WINDOW_DESCRIPTOR
		if plugin.data != nil {
			d = (cast(^Window_Descriptor)plugin.data)^
		}
		app.app_add_resource(a, d)
		desc = ecs.world_get_resource(&a.world, Window_Descriptor)
	}

	if !sdl3.Init(
	{
		.VIDEO,
		.GAMEPAD,
		.AUDIO,
		.JOYSTICK, // TODO: Not sure if this should be impl because not a lot of people use a joystick anymore
		.HAPTIC, // TODO: haptic feedback: this would provide vibration of the controller or mouse if it is supported
		.SENSOR, // TODO: gyros and accelerometers which I imagine would be useful for phones, VR, and devices that support it
		.EVENTS,
	},
	) {
		err_cstr := sdl3.GetError()
		defer delete_cstring(err_cstr)
		err_str, _ := strings.clone_from_cstring(err_cstr)
		return errors.new_fmt("Failed to initialize SDL: %s", err_str), false
	}

	flags: sdl3.WindowFlags
	if desc.resizable do flags += {.RESIZABLE}
	if desc.fullscreen do flags += {.FULLSCREEN}

	window := sdl3.CreateWindow(cstring(raw_data(desc.title)), desc.width, desc.height, flags)
	if window == nil {
		err_cstr := sdl3.GetError()
		defer delete_cstring(err_cstr)
		err_str, _ := strings.clone_from_cstring(err_cstr)
		return errors.new_fmt("Failed to create SDL window: %s", err_str), false
	}

	app.app_add_resource(a, Window_Context{window = window})

	// Add event pump system
	app.app_add_system(a, app.First, event_pump_system)
	app.app_add_system(a, app.Last, window_cleanup_system)
	return {}, true
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
