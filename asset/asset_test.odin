package asset

import errors "../errors"
import "base:runtime"
import "core:fmt"
import "core:io"
import linalg "core:math/linalg"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
TextAsset :: struct {
	content: string,
}

@(private)
text_loader_proc :: proc(
	ctx: ^Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	buf: [1024]u8
	n, err := io.read(ctx.reader, buf[:])
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
	loader := AssetLoader {
		load = text_loader_proc,
	}
	asset_manager_init(&mgr, loader)
	asset_server_register(&server, &mgr)

	asset_schemas_register(&server.registry, "mods", "test_base")

	resolved, id, ok := asset_schemas_resolve(&server.registry, "mods://hello.txt")
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
	hello_data, hello_id, hello_err := asset_server_load(&server, "mods://hello.txt", TextAsset)
	testing.expect(t, hello_err.payload == nil)
	testing.expect(t, hello_data != nil)
	testing.expect_value(t, hello_data.content, "Hello Geri!")

	// Test untyped
	asset_server_register_extension(&server, ".txt", typeid_of(TextAsset))
	untyped_res, _, untyped_err := asset_server_load_untyped(&server, "mods://hello.txt")
	testing.expect(t, untyped_err.payload == nil)
	testing.expect(t, untyped_res != nil)
	testing.expect_value(t, (^TextAsset)(untyped_res).content, "Hello Geri!")
}

@(test)
test_gltf_loader :: proc(t: ^testing.T) {
	server: AssetServer
	asset_server_init(&server)
	defer asset_server_destroy(&server)

	mgr: AssetManager(Gltf_Data)
	asset_manager_init(&mgr, GLTF_LOADER)
	defer asset_manager_destroy(&mgr)
	asset_server_register(&server, &mgr)

	gltf_data, id, err := asset_server_load(
		&server,
		"../geri-test/AnimatedTriangle.gltf",
		Gltf_Data,
	)
	testing.expect(t, err.payload == nil)
	testing.expect(t, gltf_data != nil)
	testing.expect(t, gltf_data.raw_data != nil)
	testing.expect(t, len(gltf_data.raw_data.meshes) > 0)
}

@(test)
test_obj_loader :: proc(t: ^testing.T) {
	obj_content :=
		"# Simple OBJ file\n" +
		"v 0.0 0.0 0.0\n" +
		"v 1.0 0.0 0.0\n" +
		"v 0.0 1.0 0.0\n" +
		"vn 0.0 0.0 1.0\n" +
		"vt 0.0 0.0\n" +
		"vt 1.0 0.0\n" +
		"vt 0.0 1.0\n" +
		"f 1/1/1 2/2/1 3/3/1\n"

	sr: strings.Reader
	strings.reader_init(&sr, obj_content)
	reader := io.to_reader(strings.reader_to_stream(&sr))
	load_ctx := Load_Context {
		reader = reader,
		path   = "test.obj",
	}
	res := obj_loader_proc(&load_ctx, nil, context.allocator)
	testing.expect(t, errors.is_ok(res))
	mesh_ptr := (^Obj_Mesh)(errors.unwrap(res))
	defer obj_mesh_destroy(mesh_ptr)

	testing.expect(t, mesh_ptr != nil)
	testing.expect_value(t, len(mesh_ptr.vertices), 3)
	testing.expect_value(t, len(mesh_ptr.indices), 3)
	testing.expect_value(t, mesh_ptr.vertices[0], linalg.Vector3f32{0.0, 0.0, 0.0})
	testing.expect_value(t, mesh_ptr.indices[0], 0)

	// Test loading the real Wolf_One_obj.obj file if it exists
	data, err := os.read_entire_file("../geri-test/Wolf_One_obj.obj", context.allocator)
	if err == nil {
		defer delete(data)
		sr: strings.Reader
		strings.reader_init(&sr, string(data))
		reader := io.to_reader(strings.reader_to_stream(&sr))
		load_ctx := Load_Context {
			reader = reader,
			path   = "../geri-test/Wolf_One_obj.obj",
		}
		real_res := obj_loader_proc(&load_ctx, nil, context.allocator)
		testing.expect(t, errors.is_ok(real_res))
		real_mesh := (^Obj_Mesh)(errors.unwrap(real_res))
		if real_mesh != nil {
			defer obj_mesh_destroy(real_mesh)
			testing.expect(t, len(real_mesh.vertices) > 0)
			testing.expect(t, len(real_mesh.indices) > 0)
		}
	}
}

@(test)
test_material_loader :: proc(t: ^testing.T) {
	mtl_content :=
		"# Material Library\n" +
		"newmtl Gold\n" +
		"Ka 0.24725 0.1995 0.0745\n" +
		"Kd 0.75164 0.60648 0.22648\n" +
		"Ks 0.628281 0.555802 0.366065\n" +
		"Ns 51.2\n" +
		"map_Kd gold_diffuse.png\n"

	sr: strings.Reader
	strings.reader_init(&sr, mtl_content)
	reader := io.to_reader(strings.reader_to_stream(&sr))
	load_ctx := Load_Context {
		reader = reader,
		path   = "test.mtl",
	}
	res := material_loader_proc(&load_ctx, nil, context.allocator)
	testing.expect(t, errors.is_ok(res))
	lib_ptr := (^Materials)(errors.unwrap(res))
	defer materials_destroy(lib_ptr, context.allocator)

	testing.expect(t, lib_ptr != nil)
	gold, found := lib_ptr.materials["Gold"]
	testing.expect(t, found)
	testing.expect_value(t, gold.name, "Gold")
	testing.expect_value(t, gold.shininess, f32(51.2))
	testing.expect_value(t, gold.map_kd, "gold_diffuse.png")
}

@(test)
test_material_loader_blender :: proc(t: ^testing.T) {
	mtl_content :=
		"# Some comment\n" +
		"\n" +
		"newmtl Material.001\n" +
		"Ns 96.078431\n" +
		"Ka 0.000000 0.000000 0.000000\n" +
		"Kd 0.472432 0.472432 0.472432\n" +
		"Ks 0.000000 0.000000 0.000000\n" +
		"Ni 1.000000\n" +
		"d 1.000000\n" +
		"illum 1\n" +
		"map_Kd Z:\\\\anything.jpg\n" +
		"\n" +
		"newmtl another_mat\n" +
		"Ns 0.000000\n" +
		"Ka 0.000000 0.000000 0.000000\n" +
		"Kd 0.167357 0.159407 0.136949\n" +
		"Ks 0.000000 0.000000 0.000000\n" +
		"Ni 1.000000\n" +
		"d 1.000000\n" +
		"illum 1\n"

	sr: strings.Reader
	strings.reader_init(&sr, mtl_content)
	reader := io.to_reader(strings.reader_to_stream(&sr))
	load_ctx := Load_Context {
		reader = reader,
		path   = "test.mtl",
	}
	res := material_loader_proc(&load_ctx, nil, context.allocator)
	testing.expect(t, errors.is_ok(res))
	lib_ptr := (^Materials)(errors.unwrap(res))
	defer materials_destroy(lib_ptr, context.allocator)

	testing.expect(t, lib_ptr != nil)

	mat1, found1 := lib_ptr.materials["Material.001"]
	testing.expect(t, found1)
	testing.expect_value(t, mat1.name, "Material.001")
	testing.expect_value(t, mat1.shininess, f32(96.078431))
	testing.expect_value(t, mat1.illum, 1)
	testing.expect_value(t, mat1.map_kd, "Z:\\\\anything.jpg")

	claws, found2 := lib_ptr.materials["another_mat"]
	testing.expect(t, found2)
	testing.expect_value(t, claws.name, "another_mat")
	testing.expect_value(t, claws.shininess, f32(0.0))
	testing.expect_value(t, claws.illum, 1)
}

import wgpu "vendor:wgpu"

@(private)
mock_texture_loader_proc :: proc(
	ctx: ^Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	dummy := new(wgpu.Texture, allocator)
	return errors.Ok(rawptr){value = dummy}
}

@(private)
mock_texture_destroy_proc :: proc(asset: rawptr, allocator: runtime.Allocator) {
	free(asset, allocator)
}

@(test)
test_gltf_dependencies :: proc(t: ^testing.T) {
	server: AssetServer
	asset_server_init(&server)
	defer asset_server_destroy(&server)

	gltf_mgr: AssetManager(Gltf_Data)
	asset_manager_init(&gltf_mgr, GLTF_LOADER)
	defer asset_manager_destroy(&gltf_mgr)
	asset_server_register(&server, &gltf_mgr)

	tex_mgr: AssetManager(wgpu.Texture)
	asset_manager_init(
		&tex_mgr,
		AssetLoader{load = mock_texture_loader_proc, destroy = mock_texture_destroy_proc},
	)
	defer asset_manager_destroy(&tex_mgr)
	asset_server_register(&server, &tex_mgr)
	asset_server_register_extension(&server, ".png", typeid_of(wgpu.Texture))
	asset_server_register_extension(&server, ".jpg", typeid_of(wgpu.Texture))
	asset_server_register_extension(&server, ".jpeg", typeid_of(wgpu.Texture))

	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/eyes_diffuse.jpeg",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/Fur_Col_20.png",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/Fur_2.png",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/Fur_Alpha_3.png",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/fella3_Kopie_7.png",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/fur__fella3_jpg_001_diffuse.png",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/Material__wolf_col_tga_diffuse.jpeg",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/Material__wolf_col_tga_diffuse_jpeg.jpg",
		transmute([]u8)string("dummy"),
	)
	asset_server_register_embedded(
		&server,
		"test_assets/gltf/wolf/eyes_diffuse_jpeg.jpg",
		transmute([]u8)string("dummy"),
	)

	gltf_data, id, err := asset_server_load(
		&server,
		"test_assets/gltf/wolf/Wolf-Blender-2.82a.gltf",
		Gltf_Data,
	)
	testing.expect(t, err.payload == nil)
	testing.expect(t, gltf_data != nil)

	testing.expect(t, len(gltf_data.textures) > 0)
	for name, tex_id in gltf_data.textures {
		_, ok := tex_mgr.assets[tex_id.id]
		testing.expect(t, ok)
	}
}
