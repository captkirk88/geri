package asset

import "core:testing"
import "core:io"
import "core:strings"
import "core:os"
import "base:runtime"
import errors "../errors"

TextAsset :: struct {
	content: string,
}

text_loader_proc :: proc(reader: io.Reader, settings: rawptr, allocator: runtime.Allocator) -> errors.Result(rawptr, errors.Error) {
	buf: [1024]u8
	n, err := io.read(reader, buf[:])
	if err != nil && err != .EOF do return errors.Err(errors.Error){error = errors.from_payload(AssetError.Loader_Error)}

	asset_val := new(TextAsset, allocator)
	asset_val.content = strings.clone(string(buf[:n]), allocator)
	return errors.Ok(rawptr){value = asset_val}
}

@(test)
test_asset_lifecycle :: proc(t: ^testing.T) {
	server: AssetServer
	asset_server_init(&server)
	defer asset_server_destroy(&server)

	mgr: AssetManager(TextAsset)
	loader := AssetLoader { load = text_loader_proc }
	asset_manager_init(&mgr, loader)
	defer {
		for _, val in mgr.assets {
			delete(val.content, mgr.allocator)
		}
	}
	asset_server_register(&server, &mgr)

	asset_schema_registry_register(&server.registry, "mods", "test_base")

	resolved, id, ok := asset_schema_registry_resolve(&server.registry, "mods://hello.txt")
	testing.expect(t, ok)
	testing.expect_value(t, resolved, "test_base/hello.txt")

	os.make_directory("test_base")
	defer os.remove("test_base")

	file_path := "test_base/hello.txt"
	fd, err := os.open(file_path, {.Write, .Create, .Trunc})
	testing.expect(t, err == 0)
	os.write(fd, transmute([]u8)string("Hello Geri!"))
	os.close(fd)
	defer os.remove(file_path)

	// Load typed
	res := asset_server_load(&server, "mods://hello.txt", TextAsset)
	testing.expect(t, errors.is_ok(res))
	asset_ptr := errors.wrap(res)
	testing.expect(t, asset_ptr != nil)
	testing.expect_value(t, asset_ptr.content, "Hello Geri!")

	// Test untyped
	asset_server_register_extension(&server, ".txt", typeid_of(TextAsset))
	untyped_res := asset_server_load_untyped(&server, "mods://hello.txt")
	testing.expect(t, errors.is_ok(untyped_res))
	untyped_ptr := errors.wrap(untyped_res)
	testing.expect(t, untyped_ptr != nil)
	testing.expect_value(t, (^TextAsset)(untyped_ptr).content, "Hello Geri!")
}
