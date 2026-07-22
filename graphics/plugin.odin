package graphics

import "../app"
import asset "../asset"
import camera "../camera"
import "../ecs"
import "../ecs/params"
import errors "../errors"
import log "../logging"
import "../windowing"
import "./components"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:image"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import stbi "vendor:stb/image"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

global_render_context: ^Render_Context

recreate_msaa_texture :: proc(ctx: ^Render_Context, sample_count: u32, hdr: bool = false) {
	if ctx.msaa_view != nil {
		wgpu.TextureViewRelease(ctx.msaa_view)
		ctx.msaa_view = nil
	}
	if ctx.msaa_texture != nil {
		wgpu.TextureRelease(ctx.msaa_texture)
		ctx.msaa_texture = nil
	}
	if ctx.depth_view != nil {
		wgpu.TextureViewRelease(ctx.depth_view)
		ctx.depth_view = nil
	}
	if ctx.depth_texture != nil {
		wgpu.TextureRelease(ctx.depth_texture)
		ctx.depth_texture = nil
	}
	if ctx.normal_view != nil {
		wgpu.TextureViewRelease(ctx.normal_view)
		ctx.normal_view = nil
	}
	if ctx.normal_texture != nil {
		wgpu.TextureRelease(ctx.normal_texture)
		ctx.normal_texture = nil
	}
	if ctx.ssao_view != nil {
		wgpu.TextureViewRelease(ctx.ssao_view)
		ctx.ssao_view = nil
	}
	if ctx.ssao_texture != nil {
		wgpu.TextureRelease(ctx.ssao_texture)
		ctx.ssao_texture = nil
	}
	if ctx.ssao_blur_view != nil {
		wgpu.TextureViewRelease(ctx.ssao_blur_view)
		ctx.ssao_blur_view = nil
	}
	if ctx.ssao_blur_tex != nil {
		wgpu.TextureRelease(ctx.ssao_blur_tex)
		ctx.ssao_blur_tex = nil
	}
	if ctx.hdr_view != nil {
		wgpu.TextureViewRelease(ctx.hdr_view)
		ctx.hdr_view = nil
	}
	if ctx.hdr_texture != nil {
		wgpu.TextureRelease(ctx.hdr_texture)
		ctx.hdr_texture = nil
	}

	if sample_count > 1 {
		desc := wgpu.TextureDescriptor {
			usage         = {.RenderAttachment},
			dimension     = ._2D,
			size          = {ctx.config.width, ctx.config.height, 1},
			format        = ctx.config.format,
			mipLevelCount = 1,
			sampleCount   = sample_count,
		}
		ctx.msaa_texture = wgpu.DeviceCreateTexture(ctx.device, &desc)
		if ctx.msaa_texture != nil {
			ctx.msaa_view = wgpu.TextureCreateView(ctx.msaa_texture, nil)
		}
	}

	depth_desc := wgpu.TextureDescriptor {
		usage         = {.RenderAttachment, .TextureBinding},
		dimension     = ._2D,
		size          = {ctx.config.width, ctx.config.height, 1},
		format        = .Depth24Plus,
		mipLevelCount = 1,
		sampleCount   = sample_count > 1 ? sample_count : 1,
	}
	ctx.depth_texture = wgpu.DeviceCreateTexture(ctx.device, &depth_desc)
	if ctx.depth_texture != nil {
		ctx.depth_view = wgpu.TextureCreateView(ctx.depth_texture, nil)
	}

	// Normal Texture (View-space normals for SSAO pass)
	normal_desc := wgpu.TextureDescriptor {
		usage         = {.RenderAttachment, .TextureBinding},
		dimension     = ._2D,
		size          = {ctx.config.width, ctx.config.height, 1},
		format        = .RGBA16Float,
		mipLevelCount = 1,
		sampleCount   = 1,
	}
	ctx.normal_texture = wgpu.DeviceCreateTexture(ctx.device, &normal_desc)
	if ctx.normal_texture != nil {
		ctx.normal_view = wgpu.TextureCreateView(ctx.normal_texture, nil)
	}

	// SSAO Raw Target
	ssao_desc := wgpu.TextureDescriptor {
		usage         = {.RenderAttachment, .TextureBinding},
		dimension     = ._2D,
		size          = {ctx.config.width, ctx.config.height, 1},
		format        = .R8Unorm,
		mipLevelCount = 1,
		sampleCount   = 1,
	}
	ctx.ssao_texture = wgpu.DeviceCreateTexture(ctx.device, &ssao_desc)
	if ctx.ssao_texture != nil {
		ctx.ssao_view = wgpu.TextureCreateView(ctx.ssao_texture, nil)
	}

	// SSAO Blur Target
	ctx.ssao_blur_tex = wgpu.DeviceCreateTexture(ctx.device, &ssao_desc)
	if ctx.ssao_blur_tex != nil {
		ctx.ssao_blur_view = wgpu.TextureCreateView(ctx.ssao_blur_tex, nil)
	}

	// HDR Target
	if hdr {
		hdr_desc := wgpu.TextureDescriptor {
			usage         = {.RenderAttachment, .TextureBinding},
			dimension     = ._2D,
			size          = {ctx.config.width, ctx.config.height, 1},
			format        = .RGBA16Float,
			mipLevelCount = 1,
			sampleCount   = 1,
		}
		ctx.hdr_texture = wgpu.DeviceCreateTexture(ctx.device, &hdr_desc)
		if ctx.hdr_texture != nil {
			ctx.hdr_view = wgpu.TextureCreateView(ctx.hdr_texture, nil)
		}
	}
}

preprocess_wgsl_includes :: proc(
	raw_code: string,
	server: ^asset.AssetServer,
	current_dir: string,
	allocator: runtime.Allocator,
) -> (
	string,
	bool,
) {
	lines := strings.split_lines(raw_code, context.temp_allocator)
	var_builder: strings.Builder
	strings.builder_init(&var_builder, allocator)

	for line in lines {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "//!include ") {
			rem := trimmed[len("//!include "):]
			rem = strings.trim_space(rem)
			if len(rem) >= 2 && rem[0] == '"' && rem[len(rem) - 1] == '"' {
				inc_path := rem[1:len(rem) - 1]

				resolved_path: string
				resolved_id: asset.UntypedAssetId
				ok: bool

				if strings.contains(inc_path, "://") {
					resolved_path, resolved_id, ok = asset.asset_schemas_resolve(
						&server.registry,
						asset.AssetPath(inc_path),
					)
				} else {
					relative_full := strings.concatenate(
						{current_dir, "/", inc_path},
						context.temp_allocator,
					)
					resolved_path, resolved_id, ok = asset.asset_schemas_resolve(
						&server.registry,
						asset.AssetPath(relative_full),
					)
				}

				if !ok {
					log.error("Shader preprocessor: Failed to resolve include path: %s", inc_path)
					strings.builder_destroy(&var_builder)
					return "", false
				}

				dep_bytes: []byte
				read_ok := false

				sync.mutex_lock(&server.mutex)
				embed_data, found_embed := server.embedded_assets[inc_path]
				if !found_embed {
					embed_data, found_embed = server.embedded_assets[resolved_path]
				}
				if found_embed {
					dep_bytes = embed_data
					read_ok = true
				}
				sync.mutex_unlock(&server.mutex)

				if !read_ok {
					err: os.Error
					dep_bytes, err = os.read_entire_file(resolved_path, context.temp_allocator)
					if err == nil {
						read_ok = true
					}
				}

				if !read_ok {
					log.error(
						"Shader preprocessor: Failed to read include file: %s (resolved: %s)",
						inc_path,
						resolved_path,
					)
					strings.builder_destroy(&var_builder)
					return "", false
				}

				next_dir := filepath.dir(resolved_path)
				dep_code, dep_ok := preprocess_wgsl_includes(
					string(dep_bytes),
					server,
					next_dir,
					allocator,
				)
				if !dep_ok {
					strings.builder_destroy(&var_builder)
					return "", false
				}
				defer delete(dep_code, allocator)

				strings.write_string(&var_builder, dep_code)
				strings.write_rune(&var_builder, '\n')
			}
		} else {
			strings.write_string(&var_builder, line)
			strings.write_rune(&var_builder, '\n')
		}
	}

	return strings.to_string(var_builder), true
}

shader_loader_proc :: proc(
	ctx: ^asset.Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	data_bytes := make([dynamic]byte, context.temp_allocator)
	buf: [4096]byte
	for {
		n, err := io.read(ctx.reader, buf[:])
		if n > 0 {
			append(&data_bytes, ..buf[:n])
		}
		if err != nil {
			break
		}
	}

	server := global_asset_server
	if server == nil {
		return errors.Err(errors.Error) {
			error = errors.new("Shader loader: AssetServer not registered globally"),
		}
	}

	current_dir := "test_assets/shaders"
	if settings != nil {
		path_str := string((cstring)(settings))
		current_dir = filepath.dir(path_str)
	}

	preprocessed, preprocess_ok := preprocess_wgsl_includes(
		string(data_bytes[:]),
		server,
		current_dir,
		context.temp_allocator,
	)
	if !preprocess_ok {
		return errors.Err(errors.Error){error = errors.new("Failed to preprocess WGSL includes")}
	}

	ctx := global_render_context
	if ctx == nil || ctx.device == nil {
		return errors.Err(errors.Error) {
			error = errors.new("Shader loader: Render_Context not available"),
		}
	}

	shader_source := wgpu.ChainedStruct {
		sType = .ShaderSourceWGSL,
	}
	shader_source_wgsl := wgpu.ShaderSourceWGSL {
		chain = shader_source,
		code  = preprocessed,
	}
	shader_desc := wgpu.ShaderModuleDescriptor {
		nextInChain = &shader_source_wgsl.chain,
	}
	module := wgpu.DeviceCreateShaderModule(ctx.device, &shader_desc)
	if module == nil {
		return errors.Err(errors.Error) {
			error = errors.new("Failed to compile preprocessed WGSL shader"),
		}
	}

	shader_asset := new(Shader_Asset, allocator)
	shader_asset.module = module
	return errors.Ok(rawptr){value = shader_asset}
}

texture_loader_proc :: proc(
	ctx: ^asset.Load_Context,
	settings: rawptr,
	allocator: runtime.Allocator,
) -> errors.Result(rawptr, errors.Error) {
	data, ok := read_all(ctx.reader, context.temp_allocator)
	if !ok {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Loader_Error)}
	}

	w, h, comp: c.int
	stb_pixels := stbi.load_from_memory(raw_data(data), c.int(len(data)), &w, &h, &comp, 4)
	if stb_pixels == nil {
		return errors.Err(errors.Error){error = errors.from_payload(asset.AssetError.Invalid_Data)}
	}
	defer stbi.image_free(stb_pixels)

	ctx := global_render_context
	if ctx == nil || ctx.device == nil || ctx.queue == nil {
		return errors.Err(errors.Error) {
			error = errors.new("Render_Context not available for Texture_Loader"),
		}
	}

	desc := wgpu.TextureDescriptor {
		usage = {.TextureBinding, .CopyDst},
		dimension = ._2D,
		size = {width = u32(w), height = u32(h), depthOrArrayLayers = 1},
		format = .RGBA8UnormSrgb,
		mipLevelCount = 1,
		sampleCount = 1,
	}
	tex := wgpu.DeviceCreateTexture(ctx.device, &desc)
	if tex == nil {
		return errors.Err(errors.Error){error = errors.new("Failed to create WGPU texture")}
	}

	tex_layout := wgpu.TexelCopyBufferLayout {
		offset       = 0,
		bytesPerRow  = u32(w * 4),
		rowsPerImage = u32(h),
	}
	dst := wgpu.TexelCopyTextureInfo {
		texture  = tex,
		mipLevel = 0,
		origin   = {0, 0, 0},
		aspect   = .All,
	}
	wgpu.QueueWriteTexture(ctx.queue, &dst, stb_pixels, uint(w * h * 4), &tex_layout, &desc.size)

	ptex := new(wgpu.Texture, allocator)
	ptex^ = tex
	return errors.Ok(rawptr){value = ptex}
}

texture_destroy_proc :: proc(asset_ptr: rawptr, allocator: runtime.Allocator) {
	ptex := (^wgpu.Texture)(asset_ptr)
	if ptex != nil {
		if ptex^ != nil {
			wgpu.TextureRelease(ptex^)
		}
		free(ptex, allocator)
	}
}

shader_destroy_proc :: proc(asset_ptr: rawptr, allocator: runtime.Allocator) {
	shader_ptr := (^Shader_Asset)(asset_ptr)
	if shader_ptr != nil {
		if shader_ptr.module != nil {
			wgpu.ShaderModuleRelease(shader_ptr.module)
			shader_ptr.module = nil
		}
	}
}

wgpu_error_callback :: proc "c" (
	device: ^wgpu.Device,
	type: wgpu.ErrorType,
	message: string,
	userdata1, userdata2: rawptr,
) {
	context = runtime.default_context()
	log.error("WGPU Validation Error: %s ---", message)
}

Request_Data :: struct {
	adapter: wgpu.Adapter,
	device:  wgpu.Device,
}

_on_adapter :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: wgpu.StringView,
	userdata, _2: rawptr,
) {
	if status == .Success {
		ctx := cast(^Request_Data)userdata
		ctx.adapter = adapter
	}
}

_on_device :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: wgpu.StringView,
	userdata, _2: rawptr,
) {
	if status == .Success {
		ctx := cast(^Request_Data)userdata
		ctx.device = device
	}
}

render_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) -> (err: errors.Error, ok: bool) {
	window_ctx := ecs.world_get_resource(&a.world, windowing.Window_Context)
	if window_ctx == nil || window_ctx.window == nil {
		return errors.new(
				"Render_Plugin requires Window_Context to be initialized first. Did you forget to add Window_Plugin?",
			),
			false
	}

	instance_extras := wgpu.InstanceExtras {
		chain = wgpu.ChainedStruct{sType = .InstanceExtras},
		backends = {.DX12}, // Use DX12 to avoid Vulkan SEH exceptions in odin test runner
	}
	instance_desc := wgpu.InstanceDescriptor {
		nextInChain = &instance_extras.chain,
	}
	instance := wgpu.CreateInstance(&instance_desc)
	if instance == nil {
		return errors.new("Failed to create WGPU Instance."), false
	}

	surface := sdl3glue.GetSurface(instance, window_ctx.window)

	req_data: Request_Data

	// Request Adapter
	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = surface,
	}
	adapter_future := wgpu.InstanceRequestAdapter(
		instance,
		&adapter_options,
		{callback = _on_adapter, userdata1 = &req_data},
	)

	if req_data.adapter == nil {
		return errors.new("Failed to get WGPU Adapter."), false
	}

	device_desc := wgpu.DeviceDescriptor {
		uncapturedErrorCallbackInfo = {callback = wgpu_error_callback},
	}

	// Request Device
	device_future := wgpu.AdapterRequestDevice(
		req_data.adapter,
		&device_desc,
		{callback = _on_device, userdata1 = &req_data},
	)

	if req_data.device == nil {
		return errors.new("Failed to get WGPU Device."), false
	}

	queue := wgpu.DeviceGetQueue(req_data.device)

	win_desc := ecs.world_get_resource(&a.world, windowing.Window_Descriptor)

	config := wgpu.SurfaceConfiguration {
		device      = req_data.device,
		format      = .BGRA8Unorm, // Default fallback
		usage       = {.RenderAttachment, .CopySrc},
		width       = u32(win_desc.width),
		height      = u32(win_desc.height),
		presentMode = .Fifo,
		alphaMode   = .Auto,
	}

	// Try to get preferred format
	caps, status := wgpu.SurfaceGetCapabilities(surface, req_data.adapter)
	defer wgpu.SurfaceCapabilitiesFreeMembers(caps)

	#partial switch status {
	case .Error:
		log.warn("Failed to get WGPU Surface Capabilities.")

	}

	if caps.formatCount > 0 {
		config.format = caps.formats[0]
	}

	wgpu.SurfaceConfigure(surface, &config)

	sampler_desc := wgpu.SamplerDescriptor {
		addressModeU  = .Repeat,
		addressModeV  = .Repeat,
		addressModeW  = .Repeat,
		magFilter     = .Linear,
		minFilter     = .Linear,
		mipmapFilter  = .Linear,
		lodMinClamp   = 0.0,
		lodMaxClamp   = 32.0,
		maxAnisotropy = 1,
	}
	default_sampler := wgpu.DeviceCreateSampler(req_data.device, &sampler_desc)

	render_ctx := Render_Context {
		instance        = instance,
		surface         = surface,
		adapter         = req_data.adapter,
		device          = req_data.device,
		queue           = queue,
		config          = config,
		default_sampler = default_sampler,
	}

	gfx_config := default_graphics_config()
	gfx_config.pbr = Pbr_Config {
		roughness    = 0.8,
		metallic     = 0.0,
		ao           = 1.0,
		antialiasing = .MSAA_4x,
	}

	recreate_msaa_texture(&render_ctx, antialiasing_sample_count(gfx_config.antialiasing), gfx_config.hdr)

	app.app_add_resource(a, render_ctx)
	app.app_add_resource(a, gfx_config)
	app.app_add_resource(a, Frame_Context{})
	app.app_add_resource(a, Clear_Color{})

	render_ctx_ptr := ecs.world_get_resource(&a.world, Render_Context)
	global_render_context = render_ctx_ptr

	sample_count := antialiasing_sample_count(gfx_config.antialiasing)
	batch2d := init_batch2d(req_data.device, config.format, nil, sample_count)
	app.app_add_resource(a, batch2d)
	batch3d := init_batch3d(req_data.device, config.format, nil, sample_count)
	app.app_add_resource(a, batch3d)

	// Set up Asset Loaders if AssetServer exists
	server := ecs.world_get_resource(&a.world, asset.AssetServer)
	if server != nil {
		global_asset_server = server

		// 1. Image Loader
		img_mgr: asset.AssetManager(image.Image)
		asset.asset_manager_init(
			&img_mgr,
			asset.AssetLoader{load = image_loader_proc, destroy = image_destroy_proc},
			context.allocator,
		)

		ecs.world_add_resource(
			&a.world,
			img_mgr,
			proc(m: ^asset.AssetManager(image.Image), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)

		img_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(image.Image))
		asset.asset_server_register(server, img_mgr_ptr)
		asset.asset_server_register_extension(
			server,
			".gif",
			typeid_of(components.SpriteAnimation),
		)
		asset.asset_server_register_extension(server, ".png", typeid_of(image.Image))
		asset.asset_server_register_extension(server, ".jpg", typeid_of(image.Image))
		asset.asset_server_register_extension(server, ".jpeg", typeid_of(image.Image))

		// 2. SpriteAnimation Loader
		anim_mgr: asset.AssetManager(components.SpriteAnimation)
		asset.asset_manager_init(
			&anim_mgr,
			asset.AssetLoader {
				load = sprite_animation_loader_proc,
				destroy = sprite_animation_destroy_proc,
			},
			context.allocator,
		)

		ecs.world_add_resource_with_destroy(
			&a.world,
			anim_mgr,
			proc(m: ^asset.AssetManager(components.SpriteAnimation), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)

		anim_mgr_ptr := ecs.world_get_resource(
			&a.world,
			asset.AssetManager(components.SpriteAnimation),
		)
		asset.asset_server_register(server, anim_mgr_ptr)

		gltf_mgr: asset.AssetManager(asset.Gltf_Data)
		asset.asset_manager_init(&gltf_mgr, asset.GLTF_LOADER, a.world.allocator)
		ecs.world_add_resource(
			&a.world,
			gltf_mgr,
			proc(m: ^asset.AssetManager(asset.Gltf_Data), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)
		gltf_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(asset.Gltf_Data))
		asset.asset_server_register(server, gltf_mgr_ptr)
		asset.asset_server_register_extension(server, ".gltf", typeid_of(asset.Gltf_Data))

		// Register Obj manager on the fly
		obj_mgr: asset.AssetManager(asset.Obj_Mesh)
		asset.asset_manager_init(&obj_mgr, asset.OBJ_LOADER, a.world.allocator)
		ecs.world_add_resource(
			&a.world,
			obj_mgr,
			proc(m: ^asset.AssetManager(asset.Obj_Mesh), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)
		obj_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(asset.Obj_Mesh))
		asset.asset_server_register(server, obj_mgr_ptr)
		asset.asset_server_register_extension(server, ".obj", typeid_of(asset.Obj_Mesh))

		// Register Material manager on the fly
		mtl_mgr: asset.AssetManager(asset.Materials)
		asset.asset_manager_init(&mtl_mgr, asset.MATERIAL_LOADER, a.world.allocator)
		ecs.world_add_resource(
			&a.world,
			mtl_mgr,
			proc(m: ^asset.AssetManager(asset.Materials), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)
		mtl_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(asset.Materials))
		asset.asset_server_register(server, mtl_mgr_ptr)
		asset.asset_server_register_extension(server, ".mtl", typeid_of(asset.Materials))

		// Register Shader manager on the fly
		shader_mgr: asset.AssetManager(Shader_Asset)
		asset.asset_manager_init(
			&shader_mgr,
			asset.AssetLoader{load = shader_loader_proc, destroy = shader_destroy_proc},
			a.world.allocator,
		)
		ecs.world_add_resource(
			&a.world,
			shader_mgr,
			proc(m: ^asset.AssetManager(Shader_Asset), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)
		shader_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(Shader_Asset))
		asset.asset_server_register(server, shader_mgr_ptr)
		asset.asset_server_register_extension(server, ".wgsl", typeid_of(Shader_Asset))

		// Register Texture manager
		tex_mgr: asset.AssetManager(wgpu.Texture)
		asset.asset_manager_init(
			&tex_mgr,
			asset.AssetLoader{load = texture_loader_proc, destroy = texture_destroy_proc},
			a.world.allocator,
		)
		ecs.world_add_resource(
			&a.world,
			tex_mgr,
			proc(m: ^asset.AssetManager(wgpu.Texture), alloc: runtime.Allocator) {
				asset.asset_manager_destroy(m)
			},
		)
		tex_mgr_ptr := ecs.world_get_resource(&a.world, asset.AssetManager(wgpu.Texture))
		asset.asset_server_register(server, tex_mgr_ptr)
		asset.asset_server_register_extension(server, ".png", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".jpg", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".jpeg", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".tga", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".bmp", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".psd", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".gif", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".hdr", typeid_of(wgpu.Texture))
		asset.asset_server_register_extension(server, ".pic", typeid_of(wgpu.Texture))

		// Register embedded shaders
		asset.asset_server_register_embedded(
			server,
			"game://shaders/pbr_math.wgsl",
			#load("embed_assets/pbr_math.wgsl"),
		)
		asset.asset_server_register_embedded(
			server,
			"game://shaders/pbr.wgsl",
			#load("embed_assets/pbr.wgsl"),
		)
		asset.asset_server_register_embedded(
			server,
			"game://shaders/pbr_skinned.wgsl",
			#load("embed_assets/pbr_skinned.wgsl"),
		)
		asset.asset_server_register_embedded(
			server,
			"game://shaders/default_3d.wgsl",
			#load("embed_assets/default_3d.wgsl"),
		)
	}

	app.app_add_system(a, app.PreUpdate, camera.auto_transform_system)
	app.app_add_system(a, app.PreRender, frame_start_system)
	app.app_add_system(a, app.Render, main_render_system)
	app.app_add_system(a, app.PostRender, frame_present_system)
	render_cleanup_deps := []app.System_Dependency{rawptr(windowing.window_cleanup_system)}
	app.app_add_system(a, app.Last, render_cleanup_system, before = render_cleanup_deps)
	app.app_add_system(a, app.First, handle_resize_system) // To resize surface
	return {}, true
}

@(tag = "system")
render_cleanup_system :: proc(
	exit_events: params.EventReader(app.App_Exit_Event),
	batch2d: params.Res(Batch2D),
	batch3d: params.Res(Batch3D),
	render_ctx: params.Res(Render_Context),
	fctx: params.Res(Frame_Context),
) {
	if len(exit_events.events) > 0 {

		custom_fonts_destroy()
		if batch2d.ptr != nil do destroy_batch2d(batch2d.ptr)
		if batch3d.ptr != nil do destroy_batch3d(batch3d.ptr)

		if fctx.ptr != nil {
			if fctx.ptr.encoder != nil {
				wgpu.CommandEncoderRelease(fctx.ptr.encoder)
				fctx.ptr.encoder = nil
			}
			if fctx.ptr.texture_view != nil {
				wgpu.TextureViewRelease(fctx.ptr.texture_view)
				fctx.ptr.texture_view = nil
			}
			fctx.ptr.texture = nil
		}

		if render_ctx.ptr != nil {
			if render_ctx.ptr.default_sampler != nil {
				wgpu.SamplerRelease(render_ctx.ptr.default_sampler)
				render_ctx.ptr.default_sampler = nil
			}

			if render_ctx.ptr.depth_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.depth_view)
				render_ctx.ptr.depth_view = nil
			}
			if render_ctx.ptr.depth_texture != nil {
				wgpu.TextureRelease(render_ctx.ptr.depth_texture)
				render_ctx.ptr.depth_texture = nil
			}
			if render_ctx.ptr.normal_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.normal_view)
				render_ctx.ptr.normal_view = nil
			}
			if render_ctx.ptr.normal_texture != nil {
				wgpu.TextureRelease(render_ctx.ptr.normal_texture)
				render_ctx.ptr.normal_texture = nil
			}
			if render_ctx.ptr.ssao_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.ssao_view)
				render_ctx.ptr.ssao_view = nil
			}
			if render_ctx.ptr.ssao_texture != nil {
				wgpu.TextureRelease(render_ctx.ptr.ssao_texture)
				render_ctx.ptr.ssao_texture = nil
			}
			if render_ctx.ptr.ssao_blur_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.ssao_blur_view)
				render_ctx.ptr.ssao_blur_view = nil
			}
			if render_ctx.ptr.ssao_blur_tex != nil {
				wgpu.TextureRelease(render_ctx.ptr.ssao_blur_tex)
				render_ctx.ptr.ssao_blur_tex = nil
			}
			if render_ctx.ptr.hdr_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.hdr_view)
				render_ctx.ptr.hdr_view = nil
			}
			if render_ctx.ptr.hdr_texture != nil {
				wgpu.TextureRelease(render_ctx.ptr.hdr_texture)
				render_ctx.ptr.hdr_texture = nil
			}

			if render_ctx.ptr.msaa_view != nil {
				wgpu.TextureViewRelease(render_ctx.ptr.msaa_view)
				render_ctx.ptr.msaa_view = nil
			}
			if render_ctx.ptr.msaa_texture != nil {
				wgpu.TextureRelease(render_ctx.ptr.msaa_texture)
				render_ctx.ptr.msaa_texture = nil
			}

			// Surface must be released BEFORE Queue, Device, Adapter, and Instance
			if render_ctx.ptr.surface != nil {
				wgpu.SurfaceRelease(render_ctx.ptr.surface)
				render_ctx.ptr.surface = nil
			}
			if render_ctx.ptr.queue != nil {
				wgpu.QueueRelease(render_ctx.ptr.queue)
				render_ctx.ptr.queue = nil
			}
			if render_ctx.ptr.device != nil {
				wgpu.DeviceRelease(render_ctx.ptr.device)
				render_ctx.ptr.device = nil
			}
			if render_ctx.ptr.adapter != nil {
				wgpu.AdapterRelease(render_ctx.ptr.adapter)
				render_ctx.ptr.adapter = nil
			}
			if render_ctx.ptr.instance != nil {
				wgpu.InstanceRelease(render_ctx.ptr.instance)
				render_ctx.ptr.instance = nil
			}
		}
	}
}

Render_Plugin :: proc() -> app.Plugin {
	return app.Plugin{build = render_plugin_build, destroy = nil}
}
