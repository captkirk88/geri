package plugins

import "../app"
import "../graphics"
import "../windowing"

Default_Plugins :: proc() -> app.Plugin {
	return app.Plugin{build = proc(plugin: app.Plugin, a: ^app.App) {
			app.app_add_plugin(a, windowing.Window_Plugin())
			app.app_add_plugin(a, graphics.Render_Plugin())
			app.app_add_plugin(a, Assets_Plugin())
		}, destroy = proc(plugin: app.Plugin, a: ^app.App) {
			graphics.Render_Plugin().destroy(plugin, a)
		}}
}
