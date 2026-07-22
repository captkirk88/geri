package ui

import "../app"
import "../ecs"
import errors "../errors"
import graphics "../graphics"
import input "../input"
import "base:runtime"
import "vendor:sdl3"

UI_Plugin :: proc() -> app.Plugin {
	return app.Plugin{build = ui_plugin_build, destroy = nil, data = nil}
}

ui_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) -> (err: errors.Error, ok: bool) {
	state: UI_State
	ui_state_init(&state)
	ecs.world_add_resource(&a.world, state, proc(s: ^UI_State, alloc: runtime.Allocator) {
		ui_state_destroy(s)
	})

	// Add default UI input configuration
	config := UI_Input_Config {
		mouse_click    = .Left,
		gamepad_submit = .South,
	}
	ecs.world_add_resource(&a.world, config)

	// Ensure a default graphics.Font resource is registered for UI text rendering
	if ecs.world_get_resource(&a.world, graphics.Font) == nil {
		font: graphics.Font
		if graphics.font_init(&font, "C:\\Windows\\Fonts\\arial.ttf", 32.0) {
			ecs.world_add_resource(&a.world, font, proc(f: ^graphics.Font, alloc: runtime.Allocator) {
				graphics.font_destroy(f)
			})
		}
	}

	// Initialize observers for dirty flag and cascading despawn
	ui_observer_init(&a.world)

	// Add layout and interaction systems to app.Update
	app.app_add_system(a, app.Update, ui_layout_system)
	app.app_add_system(a, app.Update, ui_button_interaction_system)
	app.app_add_system(a, app.Update, ui_slider_interaction_system)
	app.app_add_system(a, app.Update, ui_scrollbar_interaction_system)
	app.app_add_system(a, app.Update, ui_checkbox_interaction_system)
	app.app_add_system(a, app.Update, ui_toggle_interaction_system)
	app.app_add_system(a, app.Update, ui_radio_button_interaction_system)
	app.app_add_system(a, app.Update, ui_text_input_interaction_system)

	// Add render system to app.Render, scheduled before the main render system flushes Batch2D
	app.app_add_system(
		a,
		app.Render,
		ui_render_system,
		before = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)

	app.app_add_system(a, app.Last, ui_text_input_cleanup_system)

	return {}, true
}

ui_state_init :: proc(state: ^UI_State, allocator := context.allocator) {
	state.dirty = true
	state.deferred_despawns = make([dynamic]ecs.Entity, allocator)
}

ui_state_destroy :: proc(state: ^UI_State) {
	delete(state.deferred_despawns)
}
