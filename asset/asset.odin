package asset

import errors "../errors"
import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:hash"
import "core:io"
import "core:log"
import virtual "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

AssetPath :: string

UntypedAssetId :: struct {
	value: u64,
}

AssetId :: struct($T: typeid) {
	using id: UntypedAssetId,
}

Asset_Entry :: struct($T: typeid) {
	id:    AssetId(T),
	asset: T,
}

Asset_Loaded :: struct {
	path: string,
	id:   UntypedAssetId,
}

Asset_Event :: union {
	Asset_Loaded,
}


AssetError :: enum {
	None = 0,
	Invalid_Data,
	Loader_Error,
	Allocator_Error,
	Manager_Not_Found,
	Path_Not_Resolved,
	Type_Mismatch,
	File_Open_Error,
}

Asset_Dependency :: struct {
	path: string,
	type: typeid,
}

Load_Context :: struct {
	reader: io.Reader,
	path:   string,
}

AssetLoader :: struct {
	load:         proc(
		ctx: ^Load_Context,
		settings: rawptr,
		allocator: runtime.Allocator,
	) -> errors.Result(rawptr, errors.Error),
	destroy:      proc(asset: rawptr, allocator: runtime.Allocator),
	dependencies: proc(
		asset: rawptr,
		ctx: ^Load_Context,
		settings: rawptr,
		allocator: runtime.Allocator,
	) -> []Asset_Dependency,
}

IAssetManager :: struct {
	manager_ptr:           rawptr,
	load_asset:            proc(
		manager_ptr: rawptr,
		id: UntypedAssetId,
		ctx: ^Load_Context,
		settings: rawptr,
	) -> errors.Result(rawptr, errors.Error),
	destroy:               proc(manager_ptr: rawptr),
	populate_assets_slice: proc(
		manager_ptr: rawptr,
		target_slice_ptr: rawptr,
		allocator: runtime.Allocator,
	),
	get_dependencies:      proc(
		manager_ptr: rawptr,
		id: UntypedAssetId,
		ctx: ^Load_Context,
		settings: rawptr,
		allocator: runtime.Allocator,
	) -> []Asset_Dependency,
}

AssetManager :: struct($T: typeid) {
	mutex:     sync.Mutex,
	loader:    AssetLoader,
	assets:    map[UntypedAssetId]T,
	allocator: runtime.Allocator,
	arena:     virtual.Arena,
}

asset_manager_init :: proc(
	mgr: ^AssetManager($T),
	loader: AssetLoader,
	allocator := context.allocator,
) {
	mgr.loader = loader
	mgr.allocator = allocator
	mgr.assets = make(map[UntypedAssetId]T, allocator)
	_ = virtual.arena_init_growing(&mgr.arena)
}

asset_manager_destroy :: proc(mgr: ^AssetManager($T)) {
	if mgr.assets == nil do return
	if mgr.loader.destroy != nil {
		allocator := virtual.arena_allocator(&mgr.arena)
		for id in mgr.assets {
			val_ptr := &mgr.assets[id]
			ti := type_info_of(T)
			_, is_ptr := ti.variant.(runtime.Type_Info_Pointer)
			if is_ptr {
				ptr := (^rawptr)(val_ptr)^
				mgr.loader.destroy(ptr, allocator)
			} else {
				mgr.loader.destroy(val_ptr, allocator)
			}
		}
	}
	delete(mgr.assets)
	mgr.assets = nil
	virtual.arena_destroy(&mgr.arena)
}

asset_manager_load :: proc(
	mgr: ^AssetManager($T),
	id: UntypedAssetId,
	ctx: ^Load_Context,
	settings: rawptr,
) -> errors.Result(rawptr, errors.Error) {
	sync.mutex_lock(&mgr.mutex)
	defer sync.mutex_unlock(&mgr.mutex)

	if val, ok := &mgr.assets[id]; ok {
		return errors.Ok(rawptr){value = val}
	}

	arena_allocator := virtual.arena_allocator(&mgr.arena)
	res := mgr.loader.load(ctx, settings, arena_allocator)
	switch r in res {
	case errors.Err(errors.Error):
		return r
	case errors.Ok(rawptr):
		raw_asset := r.value
		typed_asset := (^T)(raw_asset)^
		mgr.assets[id] = typed_asset

		ti := type_info_of(T)
		_, is_ptr := ti.variant.(runtime.Type_Info_Pointer)
		if !is_ptr {
			free(raw_asset, arena_allocator)
		}

		return errors.Ok(rawptr){value = &mgr.assets[id]}
	}
	return errors.Err(errors.Error){error = errors.new("unreachable")}
}

AssetSchemaRegistry :: struct {
	mutex:     sync.Mutex,
	paths:     map[string]string, // scheme name -> base path
	allocator: runtime.Allocator,
}

asset_schema_registry_init :: proc(
	registry: ^AssetSchemaRegistry,
	allocator := context.allocator,
) {
	registry.allocator = allocator
	registry.paths = make(map[string]string, allocator)
}

asset_schema_registry_destroy :: proc(registry: ^AssetSchemaRegistry) {
	for k, v in registry.paths {
		delete(k, registry.allocator)
		delete(v, registry.allocator)
	}
	delete(registry.paths)
}

asset_schemas_register :: proc(registry: ^AssetSchemaRegistry, scheme: string, base_path: string) {
	sync.mutex_lock(&registry.mutex)
	defer sync.mutex_unlock(&registry.mutex)

	if old_base, ok := registry.paths[scheme]; ok {
		delete(old_base, registry.allocator)
		registry.paths[scheme] = strings.clone(base_path, registry.allocator)
	} else {
		s := strings.clone(scheme, registry.allocator)
		b := strings.clone(base_path, registry.allocator)
		registry.paths[s] = b
	}
}

asset_schemas_resolve :: proc(
	registry: ^AssetSchemaRegistry,
	path: AssetPath,
) -> (
	resolved_path: string,
	id: UntypedAssetId,
	ok: bool,
) {
	scheme_delim :: "://"
	path_str := string(path)
	idx := strings.index(path_str, scheme_delim)

	resolved: string
	if idx != -1 {
		scheme := path_str[:idx]
		relative := path_str[idx + len(scheme_delim):]

		sync.mutex_lock(&registry.mutex)
		base_path, found := registry.paths[scheme]
		sync.mutex_unlock(&registry.mutex)

		if found {
			has_slash :=
				len(base_path) > 0 &&
				(base_path[len(base_path) - 1] == '/' || base_path[len(base_path) - 1] == '\\')
			if has_slash {
				resolved = strings.concatenate({base_path, relative}, context.temp_allocator)
			} else {
				resolved = strings.concatenate({base_path, "/", relative}, context.temp_allocator)
			}
		} else {
			resolved = path_str
		}
	} else {
		resolved = path_str
	}

	hash_val := hash.fnv64a(transmute([]u8)resolved)
	return resolved, UntypedAssetId{value = hash_val}, true
}

AssetServer :: struct {
	mutex:           sync.Mutex,
	registry:        AssetSchemaRegistry,
	managers:        map[typeid]IAssetManager,
	extension_types: map[string]typeid,
	allocator:       runtime.Allocator,
	embedded_assets: map[string][]byte,
	loaded_queue:    [dynamic]Asset_Loaded,
	asset_paths:     map[UntypedAssetId]string,
}

asset_server_init :: proc(server: ^AssetServer, allocator := context.allocator) {
	server.allocator = allocator
	asset_schema_registry_init(&server.registry, allocator)
	server.managers = make(map[typeid]IAssetManager, allocator)
	server.extension_types = make(map[string]typeid, allocator)
	server.embedded_assets = make(map[string][]byte, allocator)
	server.loaded_queue = make([dynamic]Asset_Loaded, allocator)
	server.asset_paths = make(map[UntypedAssetId]string, allocator)
}

asset_server_destroy :: proc(server: ^AssetServer) {
	asset_schema_registry_destroy(&server.registry)
	for _, mgr in server.managers {
		mgr.destroy(mgr.manager_ptr)
	}
	delete(server.managers)
	delete(server.extension_types)
	delete(server.embedded_assets)
	delete(server.loaded_queue)
	for _, path in server.asset_paths {
		delete(path)
	}
	delete(server.asset_paths)
}

asset_server_register_embedded :: proc(server: ^AssetServer, path: string, data: []byte) {
	sync.mutex_lock(&server.mutex)
	defer sync.mutex_unlock(&server.mutex)
	server.embedded_assets[path] = data
}

asset_server_clear_embedded :: proc(server: ^AssetServer) {
	sync.mutex_lock(&server.mutex)
	defer sync.mutex_unlock(&server.mutex)
	clear(&server.embedded_assets)
}

asset_manager_populate_slice :: proc(
	$T: typeid,
) -> (
	proc(_: rawptr, _: rawptr, _: runtime.Allocator),
) {
	return proc(manager_ptr: rawptr, target_slice_ptr: rawptr, allocator: runtime.Allocator) {
			mgr := (^AssetManager(T))(manager_ptr)
			sync.mutex_lock(&mgr.mutex)
			defer sync.mutex_unlock(&mgr.mutex)

			slice := make([]Asset_Entry(T), len(mgr.assets), allocator)
			i := 0
			for id, asset in mgr.assets {
				slice[i] = Asset_Entry(T) {
					id = AssetId(T){id = id},
					asset = asset,
				}
				i += 1
			}

			raw_slice := transmute(runtime.Raw_Slice)slice
			((^runtime.Raw_Slice)(target_slice_ptr))^ = raw_slice
		}
}

asset_server_register :: proc(server: ^AssetServer, manager: ^AssetManager($T)) {
	sync.mutex_lock(&server.mutex)
	defer sync.mutex_unlock(&server.mutex)

	tid := typeid_of(T)
	server.managers[tid] = IAssetManager {
		manager_ptr = manager,
		load_asset = proc(
			manager_ptr: rawptr,
			id: UntypedAssetId,
			ctx: ^Load_Context,
			settings: rawptr,
		) -> errors.Result(rawptr, errors.Error) {
			mgr := (^AssetManager(T))(manager_ptr)
			return asset_manager_load(mgr, id, ctx, settings)
		},
		destroy = proc(manager_ptr: rawptr) {
			mgr := (^AssetManager(T))(manager_ptr)
			asset_manager_destroy(mgr)
		},
		populate_assets_slice = asset_manager_populate_slice(T),
		get_dependencies = proc(
			manager_ptr: rawptr,
			id: UntypedAssetId,
			ctx: ^Load_Context,
			settings: rawptr,
			allocator: runtime.Allocator,
		) -> []Asset_Dependency {
			mgr := (^AssetManager(T))(manager_ptr)
			if mgr.loader.dependencies == nil do return nil
			sync.mutex_lock(&mgr.mutex)
			defer sync.mutex_unlock(&mgr.mutex)
			if val, ok := &mgr.assets[id]; ok {
				ti := type_info_of(T)
				_, is_ptr := ti.variant.(runtime.Type_Info_Pointer)
				if is_ptr {
					ptr := (^rawptr)(val)^
					return mgr.loader.dependencies(ptr, ctx, settings, allocator)
				} else {
					return mgr.loader.dependencies(rawptr(val), ctx, settings, allocator)
				}
			}
			return nil
		},
	}
}

asset_server_register_extension :: proc(server: ^AssetServer, ext: string, tid: typeid) {
	sync.mutex_lock(&server.mutex)
	defer sync.mutex_unlock(&server.mutex)
	server.extension_types[ext] = tid
}

asset_server_load_by_id :: proc(
	server: ^AssetServer,
	id: AssetId($T),
	ctx: ^Load_Context,
	settings: rawptr = nil,
) -> errors.Result(^T, errors.Error) {
	sync.mutex_lock(&server.mutex)
	mgr_val, ok := server.managers[typeid_of(T)]
	sync.mutex_unlock(&server.mutex)

	if !ok do return errors.Err(errors.Error){error = errors.from_payload(AssetError.Manager_Not_Found)}

	res := mgr_val.load_asset(mgr_val.manager_ptr, id.id, ctx, settings)
	#partial switch r in res {
	case errors.Err(errors.Error):
		return r
	case errors.Ok(rawptr):
		return errors.Ok(^T){value = (^T)(r.value)}
	}
	panic("unreachable")
}

asset_server_load_untyped_by_id :: proc(
	server: ^AssetServer,
	id: UntypedAssetId,
	tid: typeid,
	ctx: ^Load_Context,
	settings: rawptr = nil,
) -> errors.Result(rawptr, errors.Error) {
	sync.mutex_lock(&server.mutex)
	mgr_val, ok := server.managers[tid]
	sync.mutex_unlock(&server.mutex)

	if !ok do return errors.Err(errors.Error){error = errors.from_payload(AssetError.Manager_Not_Found)}

	return mgr_val.load_asset(mgr_val.manager_ptr, id, ctx, settings)
}

asset_server_load :: proc(
	server: ^AssetServer,
	path: AssetPath,
	$T: typeid,
	settings: rawptr = nil,
	caller_location := #caller_location,
) -> (
	^T,
	AssetId(T),
	errors.Error,
) {
	resolved, id, ok := asset_schemas_resolve(&server.registry, path)
	if !ok do return nil, AssetId(T){id = id}, errors.from_payload(AssetError.Path_Not_Resolved)

	// Try quick lookup
	sync.mutex_lock(&server.mutex)
	mgr_val, mgr_ok := server.managers[typeid_of(T)]
	sync.mutex_unlock(&server.mutex)

	if !mgr_ok do return nil, AssetId(T){id = id}, errors.from_payload(AssetError.Manager_Not_Found)

	mgr := (^AssetManager(T))(mgr_val.manager_ptr)
	sync.mutex_lock(&mgr.mutex)
	if val, found := &mgr.assets[id]; found {
		sync.mutex_unlock(&mgr.mutex)
		return val, AssetId(T){id = id}, errors.none()
	}
	sync.mutex_unlock(&mgr.mutex)

	f, f_err := os.open(resolved)
	reader: io.Reader
	opened := false
	if f_err == nil {
		opened = true
		reader = io.to_reader(os.to_stream(f))
	} else {
		sync.mutex_lock(&server.mutex)
		embed_data, found_embed := server.embedded_assets[string(path)]
		if !found_embed {
			embed_data, found_embed = server.embedded_assets[resolved]
		}
		sync.mutex_unlock(&server.mutex)

		if found_embed {
			r: bytes.Reader
			bytes.reader_init(&r, embed_data)
			reader = bytes.reader_to_stream(&r)
		} else {
			return nil, AssetId(T) {
				id = id,
			}, errors.from_payload(AssetError.File_Open_Error, location = caller_location)
		}
	}
	defer if opened do os.close(f)

	load_ctx := Load_Context {
		reader = reader,
		path   = resolved,
	}
	res := asset_server_load_by_id(server, AssetId(T){id = id}, &load_ctx, settings)
	loaded: ^T = nil

	#partial switch r in res {
	case errors.Ok(^T):
		sync.mutex_lock(&server.mutex)
		if id in server.asset_paths {
			delete(server.asset_paths[id])
		}
		server.asset_paths[id] = strings.clone(resolved, server.allocator)
		append(&server.loaded_queue, Asset_Loaded{path = string(path), id = id})
		mgr_val, mgr_ok := server.managers[typeid_of(T)]
		sync.mutex_unlock(&server.mutex)

		if mgr_ok && mgr_val.get_dependencies != nil {
			deps := mgr_val.get_dependencies(
				mgr_val.manager_ptr,
				id,
				&load_ctx,
				settings,
				context.temp_allocator,
			)
			for dep in deps {
				_, _, dep_err := asset_server_load_untyped(server, AssetPath(dep.path), settings)
				if dep_err.payload != nil {
					// We should probably log this error, but for now we'll just ignore it.
					log.errorf("Failed to load dependency %s: %v\n", dep.path, dep_err)
					return nil, {}, dep_err
				}
			}
		}

		loaded = errors.unwrap(res)
	}
	if loaded == nil {
		return nil, {}, errors.unwrap_err(res)
	}
	return loaded, AssetId(T){id = id}, errors.none()
}

asset_server_load_untyped :: proc(
	server: ^AssetServer,
	path: AssetPath,
	settings: rawptr = nil,
	caller_location := #caller_location,
) -> (
	rawptr,
	UntypedAssetId,
	errors.Error,
) {
	resolved, id, ok := asset_schemas_resolve(&server.registry, path)
	if !ok do return nil, id, errors.from_payload(AssetError.Path_Not_Resolved)

	ext := filepath.ext(resolved)
	sync.mutex_lock(&server.mutex)
	tid, found_tid := server.extension_types[ext]
	sync.mutex_unlock(&server.mutex)

	if !found_tid do return nil, id, errors.from_payload(AssetError.Type_Mismatch)

	sync.mutex_lock(&server.mutex)
	mgr_val, mgr_ok := server.managers[tid]
	sync.mutex_unlock(&server.mutex)

	if !mgr_ok do return nil, id, errors.from_payload(AssetError.Manager_Not_Found)

	mgr_ptr := mgr_val.manager_ptr

	f, f_err := os.open(resolved)
	reader: io.Reader
	opened := false
	if f_err == nil {
		opened = true
		reader = io.to_reader(os.to_stream(f))
	} else {
		sync.mutex_lock(&server.mutex)
		embed_data, found_embed := server.embedded_assets[string(path)]
		if !found_embed {
			embed_data, found_embed = server.embedded_assets[resolved]
		}
		sync.mutex_unlock(&server.mutex)

		if found_embed {
			r: bytes.Reader
			bytes.reader_init(&r, embed_data)
			reader = bytes.reader_to_stream(&r)
		} else {
			return nil, id, errors.from_payload(
				AssetError.File_Open_Error,
				location = caller_location,
			)
		}
	}
	defer if opened do os.close(f)

	load_ctx := Load_Context {
		reader = reader,
		path   = resolved,
	}
	res := mgr_val.load_asset(mgr_ptr, id, &load_ctx, settings)
	maybe_loaded: rawptr = nil
	#partial switch r in res {
	case errors.Ok(rawptr):
		sync.mutex_lock(&server.mutex)
		if id in server.asset_paths {
			delete(server.asset_paths[id])
		}
		server.asset_paths[id] = strings.clone(resolved, server.allocator)
		append(&server.loaded_queue, Asset_Loaded{path = string(path), id = id})
		sync.mutex_unlock(&server.mutex)

		if mgr_val.get_dependencies != nil {
			deps := mgr_val.get_dependencies(
				mgr_ptr,
				id,
				&load_ctx,
				settings,
				context.temp_allocator,
			)
			for dep in deps {
				_, _, dep_err := asset_server_load_untyped(server, AssetPath(dep.path), nil)
				if dep_err.payload != nil {
					// We should probably log this error, but for now we'll just ignore it.
					log.errorf("Failed to load dependency %s: %v\n", dep.path, dep_err)
					return nil, {}, dep_err
				}
			}
		}

		maybe_loaded = errors.unwrap(res)
	}

	if maybe_loaded == nil {
		return nil, {}, errors.unwrap_err(res)
	}

	return maybe_loaded, id, errors.none()
}
