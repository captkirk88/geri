package input

import "base:runtime"
import "../app"
import "../ecs"
import errors "../errors"

Input_Plugin :: proc() -> app.Plugin {
	return app.Plugin{
		build = input_plugin_build,
		destroy = nil,
		data = nil,
	}
}

input_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) -> (err: errors.Error, ok: bool) {
	state: Input_State
	input_state_init(&state)
	ecs.world_add_resource(&a.world, state, proc(s: ^Input_State, alloc: runtime.Allocator) {
		input_state_destroy(s)
	})

	// Register custom system parameter builder for Input(T)
	ecs.world_register_param_builder(&a.world, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime_type_info_base(info)
			s, ok := base.variant.(runtime.Type_Info_Struct)
			if !ok do return false
			if s.field_count != 1 || s.names[0] != "state" do return false
			ptr_info := runtime_type_info_base(s.types[0])
			ptr_struct, is_ptr := ptr_info.variant.(runtime.Type_Info_Pointer)
			if !is_ptr do return false
			return ptr_struct.elem.id == typeid_of(Input_State)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			state_res := ecs.world_get_resource(w, Input_State)
			if state_res != nil {
				base := runtime_type_info_base(info)
				s := base.variant.(runtime.Type_Info_Struct)
				dest := (^rawptr)(uintptr(ptr) + s.offsets[0])
				dest^ = state_res
			}
		},
		after_run = nil,
		destroy = nil,
	})

	// Add input update system in app.PreUpdate
	app.app_add_system(a, app.PreUpdate, input_update_system)
	return {}, true
}

runtime_type_info_base :: proc(info: ^runtime.Type_Info) -> ^runtime.Type_Info {
	if info == nil do return nil
	current := info
	for {
		#partial switch variant in current.variant {
		case runtime.Type_Info_Named:
			current = variant.base
		case:
			return current
		}
	}
	return current
}
