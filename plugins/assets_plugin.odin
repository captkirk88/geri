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

import log "../logging"
import "core:strings"

asset_event_dispatcher_system :: proc(
	server_res: params.Res(asset.AssetServer),
	event_writer: params.EventWriter(asset.Asset_Event),
) {
	server := server_res.ptr
	if server == nil do return

	sync.mutex_lock(&server.mutex)
	if len(server.loaded_queue) == 0 {
		sync.mutex_unlock(&server.mutex)
		return
	}

	for ev in server.loaded_queue {
		params.write(event_writer, ev)
	}
	clear(&server.loaded_queue)
	sync.mutex_unlock(&server.mutex)
}

clear_embedded_assets_system :: proc(
	events: params.EventReader(asset.Asset_Event),
	server_res: params.Res(asset.AssetServer),
) {
	server := server_res.ptr
	if server == nil do return

	for event in events.events {
		#partial switch ev in event {
		case asset.Asset_Loaded:
			if strings.has_suffix(ev.path, "pbr.wgsl") {
				asset.asset_server_clear_embedded(server)
				log.debug(
					"Asset System: Shaders loaded, automatically cleared embedded assets registry.",
				)
			}
		}
	}
}

import "../ecs/params"
import errors "../errors"
import "../graphics"
import wgpu "vendor:wgpu"

@(tag = "system")
assets_cleanup_system :: proc(
	world: ^ecs.World,
	exit_events: params.EventReader(app.App_Exit_Event),
) {
	if len(exit_events.events) > 0 {
		ecs.world_remove_resource(world, asset.AssetManager(graphics.Shader_Asset))
		ecs.world_remove_resource(world, asset.AssetManager(wgpu.Texture))
		ecs.world_remove_resource(world, asset.AssetManager(asset.Gltf_Data))

		server := ecs.world_get_resource(world, asset.AssetServer)
		if server != nil {
			clear(&server.managers)
		}

		ecs.world_remove_resource(world, asset.AssetServer)
	}
}

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

			app.app_add_system(a, app.PreUpdate, asset_event_dispatcher_system)
			app.app_add_system(a, app.PreUpdate, clear_embedded_assets_system)

			cleanup_deps := []app.System_Dependency{rawptr(graphics.render_cleanup_system)}
			app.app_add_system(a, app.Last, assets_cleanup_system, before = cleanup_deps)
			return {}, true
		}, destroy = nil}
}
