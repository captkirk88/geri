package plugins

import "../app"
import "../graphics"
import "../windowing"
import errors "../errors"

Default_Plugins :: proc() -> app.Plugin {
	return app.Plugin{build = proc(plugin: app.Plugin, a: ^app.App) -> (errors.Error, bool) {
			if err, ok := app.app_add_plugin(a, windowing.Window_Plugin()); !ok do return err, false
			if err, ok := app.app_add_plugin(a, graphics.Render_Plugin()); !ok do return err, false
			if err, ok := app.app_add_plugin(a, Assets_Plugin()); !ok do return err, false
			return {}, true
		}, destroy = proc(plugin: app.Plugin, a: ^app.App) {
			graphics.Render_Plugin().destroy(plugin, a)
		}}
}
