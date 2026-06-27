package graphics

import "../app"
import "../ecs"
import "../ecs/params"
import log "../logging"
import "../windowing"
import "core:fmt"
import camera "../camera"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

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

render_plugin_build :: proc(plugin: app.Plugin, a: ^app.App) {
	window_ctx := ecs.world_get_resource(&a.world, windowing.Window_Context)
	if window_ctx == nil || window_ctx.window == nil {
		log.error(
			"Render_Plugin requires Window_Context to be initialized first. Did you forget to add Window_Plugin?",
		)
		return
	}

	instance_extras := wgpu.InstanceExtras {
		chain    = wgpu.ChainedStruct{sType = .InstanceExtras},
		backends = {.DX12}, // Use DX12 to avoid Vulkan SEH exceptions in odin test runner
	}
	instance_desc := wgpu.InstanceDescriptor {
		nextInChain = &instance_extras.chain,
	}
	instance := wgpu.CreateInstance(&instance_desc)
	if instance == nil {
		log.error("Failed to create WGPU Instance.")
		return
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
		log.error("Failed to get WGPU Adapter.")
		return
	}

	// Request Device
	device_future := wgpu.AdapterRequestDevice(
		req_data.adapter,
		nil,
		{callback = _on_device, userdata1 = &req_data},
	)

	if req_data.device == nil {
		log.error("Failed to get WGPU Device.")
		return
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
	caps, _ := wgpu.SurfaceGetCapabilities(surface, req_data.adapter)
	defer wgpu.SurfaceCapabilitiesFreeMembers(caps)

	if caps.formatCount > 0 {
		config.format = caps.formats[0]
	}

	wgpu.SurfaceConfigure(surface, &config)

	render_ctx := Render_Context {
		instance = instance,
		surface  = surface,
		adapter  = req_data.adapter,
		device   = req_data.device,
		queue    = queue,
		config   = config,
	}

	app.app_add_resource(a, render_ctx)
	app.app_add_resource(a, Frame_Context{})

	batch2d := init_batch2d(req_data.device, config.format)
	app.app_add_resource(a, batch2d)
	batch3d := init_batch3d(req_data.device, config.format)
	app.app_add_resource(a, batch3d)

	app.app_add_system(a, app.PreUpdate, camera.auto_transform_system)
	app.app_add_system(a, app.PreRender, frame_start_system)
	app.app_add_system(a, app.Render, main_render_system)
	app.app_add_system(a, app.PostRender, frame_present_system)
	app.app_add_system(a, app.Last, render_cleanup_system)
	app.app_add_system(a, app.First, handle_resize_system) // To resize surface
}

render_cleanup_system :: proc(
	exit_events: params.EventReader(app.App_Exit_Event),
	batch2d: params.Res(Batch2D),
	batch3d: params.Res(Batch3D),
	render_ctx: params.Res(Render_Context),
) {
	if len(exit_events.events) > 0 {
		if batch2d.ptr != nil do destroy_batch2d(batch2d.ptr)
		if batch3d.ptr != nil do destroy_batch3d(batch3d.ptr)

		if render_ctx.ptr != nil && render_ctx.ptr.device != nil {
			wgpu.QueueRelease(render_ctx.ptr.queue)
			wgpu.DeviceRelease(render_ctx.ptr.device)
			wgpu.AdapterRelease(render_ctx.ptr.adapter)
			wgpu.SurfaceRelease(render_ctx.ptr.surface)
			wgpu.InstanceRelease(render_ctx.ptr.instance)
			render_ctx.ptr.device = nil
			render_ctx.ptr.queue = nil
		}
	}
}

render_plugin_destroy :: proc(plugin: app.Plugin, a: ^app.App) {
	// Cleanup is now handled by render_cleanup_system on App_Exit_Event
}

Render_Plugin :: proc() -> app.Plugin {
	return app.Plugin{build = render_plugin_build, destroy = render_plugin_destroy}
}
