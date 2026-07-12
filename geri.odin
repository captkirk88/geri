package geri
// This file is required for tests to be able to run becuse the way odin finds modules

import "app"
import "asset"
import "ecs"
import "ecs/params"
import "ecs/systems"
import "graphics"
import "logging"
import "plugins"
import "reflect"
import "specs"
import "time"
import "transform"
import "ui"
import "windowing"
import "errors"

import "base:runtime"
import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
TextAsset :: struct {
	content: string,
}

@(private)
text_loader_proc :: proc(
	reader: io.Reader,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	buf: [1024]u8
	n, err := io.read(reader, buf[:])
	if err != nil && err != .EOF do return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Loader_Error)}

	asset_val := new(TextAsset, allocator)
	asset_val.content = strings.clone(string(buf[:n]), allocator)
	return errors.Ok(rawptr){value = asset_val}
}

@(test)
test_assets_param :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	systems.world_init_default_params(&w)
	plugins.register_assets_param_builder(&w)

	server: asset.AssetServer
	asset.asset_server_init(&server)
	defer asset.asset_server_destroy(&server)

	mgr: asset.AssetManager(TextAsset)
	loader := asset.AssetLoader {
		load = text_loader_proc,
	}
	asset.asset_manager_init(&mgr, loader)
	defer {
		for _, val in mgr.assets {
			delete(val.content, mgr.allocator)
		}
	}
	asset.asset_server_register(&server, &mgr)

	asset.asset_schema_registry_register(&server.registry, "mods", "test_base_sys")

	os.make_directory("test_base_sys")
	defer os.remove("test_base_sys")

	file_path := "test_base_sys/hello.txt"
	fd, err := os.open(file_path, {.Write, .Create, .Trunc})
	testing.expect(t, err == 0)
	os.write(fd, transmute([]u8)string("Hello Geri Systems!"))
	os.close(fd)
	defer os.remove(file_path)

	// Load the asset
	res := asset.asset_server_load(&server, "mods://hello.txt", TextAsset)
	testing.expect(t, errors.is_ok(res))

	// Register AssetServer as a resource in the world
	ecs.world_add_resource(&w, server)

	// Keep track of what the system iterates over
	@(static) iterated_count := 0
	@(static) iterated_content: string

	sys_proc := proc(assets: params.Assets(TextAsset)) {
		iterated_count = len(assets.assets)
		if iterated_count > 0 {
			iterated_content = assets.assets[0].asset.content
		}
	}

	sys := systems.new_system(sys_proc)
	defer systems.destroy_system(&w, sys)

	systems.run_system(&w, sys)

	testing.expect_value(t, iterated_count, 1)
	testing.expect_value(t, iterated_content, "Hello Geri Systems!")
}
