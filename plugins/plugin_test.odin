package plugins

import "core:testing"
import "../app"
import ecs "../ecs"
import errors "../errors"

Config_A :: struct {
	value: int,
}

@(test)
test_plugin_lifecycle :: proc(t: ^testing.T) {
	Plugin_State :: struct {
		build_called: bool,
		destroy_called: bool,
	}

	state := Plugin_State{}

	build_proc :: proc(plugin: Plugin, a: ^app.App) -> (errors.Error, bool) {
		s := (^Plugin_State)(plugin.data)
		s.build_called = true
		app.app_add_resource(a, Config_A{value = 99})
		return {}, true
	}

	destroy_proc :: proc(plugin: Plugin, a: ^app.App) {
		s := (^Plugin_State)(plugin.data)
		s.destroy_called = true
	}

	plugin := make_plugin(&state, build_proc, destroy_proc)

	// Initialize the app passing the plugin.
	// The plugin should be built and destroyed during app_init.
	a := errors.wrap(app.app_init({plugin}))
	defer app.app_destroy(&a)

	testing.expect(t, state.build_called)
	testing.expect(t, state.destroy_called)

	// Resource added by the plugin should exist
	res := ecs.world_get_resource(&a.world, Config_A)
	testing.expect(t, res != nil)
	if res != nil {
		testing.expect_value(t, res.value, 99)
	}
}
