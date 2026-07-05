package ui

import "../app"
import "../ecs"
import graphics "../graphics"
import "base:runtime"

UI_Plugin :: proc() -> app.Plugin {
	return app.Plugin{build = ui_plugin_build, destroy = nil, data = nil}
}

ui_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) {
	state: UI_State
	ui_state_init(&state)
	ecs.world_add_resource(&a.world, state, proc(s: ^UI_State, alloc: runtime.Allocator) {
		ui_state_destroy(s)
	})

	// Initialize observers for dirty flag and cascading despawn
	ui_observer_init(&a.world)

	// Add layout and interaction systems to app.Update
	app.app_add_system(a, app.Update, ui_layout_system)
	app.app_add_system(a, app.Update, ui_button_interaction_system)
	app.app_add_system(a, app.Update, ui_slider_interaction_system)

	// Add render system to app.Render, scheduled before the main render system flushes Batch2D
	app.app_add_system(
		a,
		app.Render,
		ui_render_system,
		before = []rawptr{rawptr(graphics.main_render_system)},
	)
}

ui_state_init :: proc(state: ^UI_State, allocator := context.allocator) {
	state.dirty = true
	state.deferred_despawns = make([dynamic]ecs.Entity, allocator)
}

ui_state_destroy :: proc(state: ^UI_State) {
	delete(state.deferred_despawns)
}
