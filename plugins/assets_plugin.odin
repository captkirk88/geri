package plugins

import "../app"
import asset "../asset"
import ecs "../ecs"
import systems "../ecs/systems"
import "base:runtime"
import "core:sync"

register_assets_param_builder :: proc(w: ^ecs.World) {
	systems.register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			PARAM_NAME :: "Assets("
			PARAM_LEN := len(PARAM_NAME)
			named, ok := info.variant.(runtime.Type_Info_Named)
			if !ok do return false
			return len(named.name) >= PARAM_LEN && named.name[:PARAM_LEN] == PARAM_NAME
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			base_info := runtime.type_info_base(info)
			s := base_info.variant.(runtime.Type_Info_Struct)
			slice_ti := s.types[0]
			slice_info := slice_ti.variant.(runtime.Type_Info_Slice)

			elem_base := runtime.type_info_base(slice_info.elem)
			elem_struct := elem_base.variant.(runtime.Type_Info_Struct)
			t := elem_struct.types[1].id

			server := ecs.world_get_resource(w, asset.AssetServer)
			if server == nil {
				panic("Assets(T) system parameter used but AssetServer resource is not registered in the World.")
			}

			sync.mutex_lock(&server.mutex)
			mgr_val, ok := server.managers[t]
			sync.mutex_unlock(&server.mutex)

			if ok {
				mgr_val.populate_assets_slice(mgr_val.manager_ptr, ptr, context.temp_allocator)
			} else {
				slice := runtime.Raw_Slice {
					data = nil,
					len  = 0,
				}
				((^runtime.Raw_Slice)(ptr))^ = slice
			}
		},
	})
}

import errors "../errors"

Assets_Plugin :: proc() -> app.Plugin {
	return app.Plugin{build = proc(plugin: app.Plugin, a: ^app.App) -> (errors.Error, bool) {
			server: asset.AssetServer
			asset.asset_server_init(&server)

			ecs.world_add_resource_with_destroy(
				&a.world,
				server,
				proc(s: ^asset.AssetServer, alloc: runtime.Allocator) {
					asset.asset_server_destroy(s)
				},
			)

			register_assets_param_builder(&a.world)
			return {}, true
		}, destroy = nil}
}
