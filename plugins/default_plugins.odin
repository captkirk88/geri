package plugins

import "../app"
import "../windowing"
import "../graphics"

Default_Plugins :: proc() -> app.Plugin {
	return app.Plugin{
		build = proc(plugin: app.Plugin, a: ^app.App) {
			windowing.Window_Plugin().build(plugin, a)
			graphics.Render_Plugin().build(plugin, a)
		},
		destroy = proc(plugin: app.Plugin, a: ^app.App) {
			graphics.Render_Plugin().destroy(plugin, a)
			windowing.Window_Plugin().destroy(plugin, a)
		},
	}
}
