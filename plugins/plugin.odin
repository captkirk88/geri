package plugins

import "../app"
import ecs "../ecs"

Plugin :: app.Plugin

// Helper to create a Plugin from procedures and custom data.
make_plugin :: proc(
	data: rawptr = nil,
	build: proc(plugin: Plugin, app: ^app.App) = nil,
	destroy: proc(plugin: Plugin, app: ^app.App) = nil,
) -> Plugin {
	return Plugin{
		data = data,
		build = build,
		destroy = destroy,
	}
}
