package main

import "core:c"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:time"
import "vendor:sdl3"
import "vendor:wgpu"

import "../app"
import "../ecs"
import "../ecs/params"
import errors "../errors"
import fps "../fps"
import graphics "../graphics"
import input "../input"
import log "../logging"
import gtime "../time"
import ui "../ui"
import "../windowing"

UI_TARGET_WIDTH :: u32(1024)
UI_TARGET_HEIGHT :: u32(1024)
SPHERE_UI_PITCH :: f32(0.0)

Sphere_UI_Uniforms :: struct {
	viewport: [2]f32,
	center:   [2]f32,
	radius:   f32,
	yaw:      f32,
	_pad:     [2]f32,
}

Sphere_UI_Vertex :: struct {
	position: [2]f32,
}

Sphere_UI_Renderer :: struct {
	pipeline:          wgpu.RenderPipeline,
	shader_module:     wgpu.ShaderModule,
	bind_group_layout: wgpu.BindGroupLayout,
	pipeline_layout:   wgpu.PipelineLayout,
	uniform_buf:       wgpu.Buffer,
	vertex_buf:        wgpu.Buffer,
	index_buf:         wgpu.Buffer,
	index_count:       u32,
}

Sphere_UI_State :: struct {
	start_time:    time.Tick,
	canvas_entity: ecs.Entity,
	center_ndc:    [2]f32,
	radius_ndc:    f32,
	yaw_speed:     f32,
}

SPHERE_UI_SHADER :: `
struct SphereUniforms {
    viewport: vec2<f32>,
    center: vec2<f32>,
    radius: f32,
    yaw: f32,
    _pad: vec2<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: SphereUniforms;
@group(0) @binding(1) var sphere_tex: texture_2d<f32>;

struct VSIn {
    @location(0) position: vec2<f32>,
};

struct VSOut {
    @builtin(position) clip_position: vec4<f32>,
};

@vertex
fn vs_main(in: VSIn) -> VSOut {
    var out: VSOut;
    out.clip_position = vec4<f32>(in.position, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let ndc_x = (frag_pos.x / uniforms.viewport.x) * 2.0 - 1.0;
    let ndc_y = 1.0 - (frag_pos.y / uniforms.viewport.y) * 2.0;

    let local = (vec2<f32>(ndc_x, ndc_y) - uniforms.center) / uniforms.radius;
    let r2 = dot(local, local);
    if (r2 > 1.0) {
        discard;
    }

    let z = sqrt(max(0.0, 1.0 - r2));
    let n = normalize(vec3<f32>(local.x, local.y, z));

	let cy = cos(uniforms.yaw);
	let sy = sin(uniforms.yaw);
	let nx = n.x * cy - n.z * sy;
	let nz = n.x * sy + n.z * cy;
	let n_rot = normalize(vec3<f32>(nx, n.y, nz));

    let pi = 3.14159265359;
	let u = 1.0 - (atan2(n_rot.z, n_rot.x) / (2.0 * pi) + 0.5);
	let v = acos(clamp(n_rot.y, -1.0, 1.0)) / pi;

	let dims = textureDimensions(sphere_tex, 0);
	let tx = i32(clamp(u * f32(dims.x), 0.0, f32(dims.x - 1u)));
	let ty = i32(clamp(v * f32(dims.y), 0.0, f32(dims.y - 1u)));
	let tex = textureLoad(sphere_tex, vec2<i32>(tx, ty), 0);

    let light_dir = normalize(vec3<f32>(0.35, 0.7, 0.6));
    let diff = clamp(dot(n, light_dir) * 0.75 + 0.25, 0.0, 1.0);
    return vec4<f32>(tex.rgb * diff, tex.a);
}
`

sphere_ui_renderer_destroy :: proc(r: ^Sphere_UI_Renderer) {
	if r == nil do return
	if r.index_buf != nil {
		wgpu.BufferRelease(r.index_buf)
		r.index_buf = nil
	}
	if r.vertex_buf != nil {
		wgpu.BufferRelease(r.vertex_buf)
		r.vertex_buf = nil
	}
	if r.uniform_buf != nil {
		wgpu.BufferRelease(r.uniform_buf)
		r.uniform_buf = nil
	}
	if r.bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(r.bind_group_layout)
		r.bind_group_layout = nil
	}
	if r.pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(r.pipeline_layout)
		r.pipeline_layout = nil
	}
	if r.pipeline != nil {
		wgpu.RenderPipelineRelease(r.pipeline)
		r.pipeline = nil
	}
	if r.shader_module != nil {
		wgpu.ShaderModuleRelease(r.shader_module)
		r.shader_module = nil
	}
}

build_sphere_ui_renderer :: proc(
	ctx: ^graphics.Render_Context,
	target: graphics.Render_Target,
) -> (
	Sphere_UI_Renderer,
	bool,
) {
	r := Sphere_UI_Renderer{}
	if ctx == nil || ctx.device == nil || target.texture_view == nil do return r, false

	r.shader_module = graphics.shader_module_from_source(
		ctx.device,
		graphics.Shader_Source_WGSL{SPHERE_UI_SHADER},
	)
	if r.shader_module == nil do return r, false

	layout_entries := [2]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			bindingArraySize = 1,
			buffer = {type = .Uniform, hasDynamicOffset = false, minBindingSize = 0},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			bindingArraySize = 1,
			texture = {sampleType = .Float, viewDimension = ._2D, multisampled = false},
		},
	}
	layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Sphere Bind Group Layout",
		entryCount = len(layout_entries),
		entries    = &layout_entries[0],
	}
	r.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(ctx.device, &layout_desc)
	if r.bind_group_layout == nil {
		sphere_ui_renderer_destroy(&r)
		return r, false
	}

	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Sphere Render Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &r.bind_group_layout,
	}
	r.pipeline_layout = wgpu.DeviceCreatePipelineLayout(ctx.device, &pipeline_layout_desc)
	if r.pipeline_layout == nil {
		sphere_ui_renderer_destroy(&r)
		return r, false
	}

	u_desc := wgpu.BufferDescriptor {
		label = "Sphere Uniform Buffer",
		usage = {.Uniform, .CopyDst},
		size  = 256,
	}
	r.uniform_buf = wgpu.DeviceCreateBuffer(ctx.device, &u_desc)
	if r.uniform_buf == nil {
		sphere_ui_renderer_destroy(&r)
		return r, false
	}

	verts := [4]Sphere_UI_Vertex {
		{position = {-1.0, -1.0}},
		{position = {1.0, -1.0}},
		{position = {1.0, 1.0}},
		{position = {-1.0, 1.0}},
	}
	inds := [6]u32{0, 1, 2, 2, 3, 0}

	vb_desc := wgpu.BufferDescriptor {
		label = "Sphere Vertex Buffer",
		usage = {.Vertex},
		size  = u64(size_of(verts)),
	}
	r.vertex_buf = graphics.render_create_static_buffer(
		ctx,
		vb_desc.usage,
		raw_data(verts[:]),
		vb_desc.size,
	)
	if r.vertex_buf == nil {
		sphere_ui_renderer_destroy(&r)
		return r, false
	}

	ib_desc := wgpu.BufferDescriptor {
		label = "Sphere Index Buffer",
		usage = {.Index},
		size  = u64(size_of(inds)),
	}
	r.index_buf = graphics.render_create_static_buffer(
		ctx,
		ib_desc.usage,
		raw_data(inds[:]),
		ib_desc.size,
	)
	if r.index_buf == nil {
		sphere_ui_renderer_destroy(&r)
		return r, false
	}
	r.index_count = 6

	vertex_attrs := [1]wgpu.VertexAttribute{{format = .Float32x2, offset = 0, shaderLocation = 0}}
	vertex_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Sphere_UI_Vertex),
		stepMode       = .Vertex,
		attributeCount = 1,
		attributes     = &vertex_attrs[0],
	}

	// Use the new helper to create the render pipeline. Pass nil for blend_state to use the default.
	r.pipeline = graphics.render_create_pipeline(
		ctx,
		r.pipeline_layout,
		r.shader_module,
		vertex_layout,
		wgpu.ColorTargetState {
			format = ctx.config.format,
			writeMask = wgpu.ColorWriteMaskFlags_All,
		},
		nil,
	)
	if r.pipeline == nil {sphere_ui_renderer_destroy(&r); return r, false}

	return r, true
}

@(tag = "system")
setup_system :: proc(commands: params.Commands, render_ctx: params.Res(graphics.Render_Context)) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil do return

	target, ok := graphics.render_target_init(render_ctx.ptr, UI_TARGET_WIDTH, UI_TARGET_HEIGHT)
	if !ok {
		log.error("test_ui_3d: failed to create UI render target")
		return
	}

	canvas := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		canvas,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			bg_color = {0.08, 0.1, 0.14, 0.85},
			padding = {40.0, 40.0, 40.0, 40.0},
		},
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Center,
			align_items = .Stretch,
			gap = 20.0,
		},
		ui.UI_Canvas {
			render_mode = .World_Space,
			reference_size = {f32(UI_TARGET_WIDTH), f32(UI_TARGET_HEIGHT)},
		},
		ui.UI_Canvas_Target{target = target},
	)

	title := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		title,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {80.0, .Pixels},
			padding = {22.0, 10.0, 10.0, 10.0},
			bg_color = {0.18, 0.25, 0.35, 1.0},
			border_color = {0.55, 0.72, 0.9, 1.0},
			border_width = 2.0,
		},
		ui.Label {
			text = "[c=#d4f4ff][b]UI Canvas on Sphere[/b][/c]\nDrag slider + click button",
			color = {1.0, 1.0, 1.0, 1.0},
		},
	)
	ecs.commands_add_relation(commands.ptr, title.entity, ecs.ChildOf, canvas.entity)

	button := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		button,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {90.0, .Pixels},
			padding = {30.0, 0.0, 0.0, 22.0},
			bg_color = {0.23, 0.32, 0.46, 1.0},
			border_color = {0.67, 0.82, 0.95, 1.0},
			border_width = 2.0,
		},
		ui.Button{},
		ui.UI_Style {
			normal = {
				bg_color = {0.23, 0.32, 0.46, 1.0},
				border_color = {0.67, 0.82, 0.95, 1.0},
				border_width = 2.0,
				text_color = {0.95, 0.98, 1.0, 1.0},
			},
			hover = {
				bg_color = {0.31, 0.45, 0.64, 1.0},
				border_color = {0.74, 0.89, 1.0, 1.0},
				border_width = 2.0,
				text_color = {1.0, 1.0, 1.0, 1.0},
			},
			active = {
				bg_color = {0.4, 0.56, 0.78, 1.0},
				border_color = {0.84, 0.94, 1.0, 1.0},
				border_width = 2.0,
				text_color = {1.0, 1.0, 1.0, 1.0},
			},
		},
		ui.Label{text = "[b]Clickable Through Sphere[/b]", color = {1.0, 1.0, 1.0, 1.0}},
	)
	ecs.commands_add_relation(commands.ptr, button.entity, ecs.ChildOf, canvas.entity)

	slider := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		slider,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {44.0, .Pixels},
			bg_color = {0.15, 0.16, 0.18, 1.0},
			border_color = {0.45, 0.45, 0.45, 1.0},
			border_width = 1.0,
		},
		ui.Slider {
			value = 0.35,
			active_color = {0.8, 0.28, 0.2, 1.0},
			knob_color = {0.98, 0.95, 0.9, 1.0},
		},
	)
	ecs.commands_add_relation(commands.ptr, slider.entity, ecs.ChildOf, canvas.entity)

	spacer := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		spacer,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {8.0, .Pixels},
			bg_color = {0.0, 0.0, 0.0, 0.0},
		},
	)
	ecs.commands_add_relation(commands.ptr, spacer.entity, ecs.ChildOf, canvas.entity)

	hint := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		hint,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {64.0, .Pixels},
			padding = {18.0, 10.0, 10.0, 10.0},
			bg_color = {0.16, 0.2, 0.26, 1.0},
			border_color = {0.38, 0.5, 0.62, 1.0},
			border_width = 1.0,
		},
		ui.Label {
			text = "Mouse over the sphere maps into the offscreen UI canvas",
			color = {0.88, 0.92, 0.97, 1.0},
		},
	)
	ecs.commands_add_relation(commands.ptr, hint.entity, ecs.ChildOf, canvas.entity)

	renderer, renderer_ok := build_sphere_ui_renderer(render_ctx.ptr, target)
	if !renderer_ok {
		log.error("test_ui_3d: failed to build sphere renderer pipeline")
		return
	}

	ecs.commands_add_resource_no_destroy(commands.ptr, renderer)

	ecs.commands_add_resource_no_destroy(
		commands.ptr,
		Sphere_UI_State {
			start_time = time.tick_now(),
			canvas_entity = canvas.entity,
			center_ndc = {0.0, 0.0},
			radius_ndc = 0.55,
			yaw_speed = 0.45,
		},
	)
}

@(tag = "system")
sphere_ui_input_system :: proc(
	world: ^ecs.World,
	state_res: params.Res(Sphere_UI_State),
	mouse_inp: input.Input(input.MouseButtonCode),
	window_res: params.Res(windowing.Window_Context),
) {
	state := state_res.ptr
	if state == nil || window_res.ptr == nil do return

	if !ecs.world_is_alive(world, state.canvas_entity) {
		for arch in ecs.query(world, ui.UI_Canvas_Target) {
			entities := ecs.arch_get_entities(arch)
			if len(entities) > 0 {
				state.canvas_entity = entities[0]
				break
			}
		}
	}

	canvas_target := ecs.world_get_component(world, state.canvas_entity, ui.UI_Canvas_Target)
	if canvas_target == nil do return

	w, h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &w, &h)
	if w <= 0 || h <= 0 do return

	mpos := input.mouse_position(mouse_inp)
	ndc_x := (mpos.x / f32(w)) * 2.0 - 1.0
	ndc_y := 1.0 - (mpos.y / f32(h)) * 2.0

	local_x := (ndc_x - state.center_ndc.x) / state.radius_ndc
	local_y := (ndc_y - state.center_ndc.y) / state.radius_ndc
	r2 := local_x * local_x + local_y * local_y

	if r2 <= 1.0 {
		z := math.sqrt(max(f32(0.0), 1.0 - r2))
		n := linalg.vector_normalize([3]f32{local_x, local_y, z})

		yaw := f32(time.duration_seconds(time.tick_since(state.start_time))) * state.yaw_speed
		cy := math.cos(yaw)
		sy := math.sin(yaw)
		nx := n.x * cy - n.z * sy
		nz := n.x * sy + n.z * cy
		cp := math.cos(SPHERE_UI_PITCH)
		sp := math.sin(SPHERE_UI_PITCH)
		py := n.y * cp - nz * sp
		pz := n.y * sp + nz * cp
		n_rot := linalg.vector_normalize([3]f32{nx, py, pz})

		u := 1.0 - (math.atan2(n_rot.z, n_rot.x) / (2.0 * math.PI) + 0.5)
		v := math.acos(clamp(n_rot.y, -1.0, 1.0)) / math.PI

		ui_x := clamp(u, 0.0, 1.0) * f32(canvas_target.target.width)
		ui_y := clamp(v, 0.0, 1.0) * f32(canvas_target.target.height)
		input.set_target_mouse_position(mouse_inp, state.canvas_entity, {ui_x, ui_y})
	} else {
		input.set_target_mouse_position(mouse_inp, state.canvas_entity, {-10000.0, -10000.0})
	}
}

@(tag = "system")
sphere_ui_render_system :: proc(
	world: ^ecs.World,
	render_ctx: params.Res(graphics.Render_Context),
	fctx_res: params.Res(graphics.Frame_Context),
	window_res: params.Res(windowing.Window_Context),
	state_res: params.Res(Sphere_UI_State),
	renderer_res: params.Res(Sphere_UI_Renderer),
) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil || fctx_res.ptr == nil || fctx_res.ptr.encoder == nil || fctx_res.ptr.texture_view == nil do return
	if window_res.ptr == nil || state_res.ptr == nil || renderer_res.ptr == nil do return

	state := state_res.ptr
	renderer := renderer_res.ptr
	canvas_target := ecs.world_get_component(world, state.canvas_entity, ui.UI_Canvas_Target)
	if canvas_target == nil || canvas_target.target.texture_view == nil do return

	w, h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &w, &h)
	if w <= 0 || h <= 0 do return

	elapsed := f32(time.duration_seconds(time.tick_since(state.start_time)))
	uniforms := Sphere_UI_Uniforms {
		viewport = {f32(w), f32(h)},
		center   = state.center_ndc,
		radius   = state.radius_ndc,
		yaw      = elapsed * state.yaw_speed,
	}
	uniform_arr := [1]Sphere_UI_Uniforms{uniforms}
	graphics.render_write_buffer(
		render_ctx.ptr,
		renderer.uniform_buf,
		raw_data(uniform_arr[:]),
		u64(size_of(Sphere_UI_Uniforms)),
	)

	pass := graphics.begin_frame_render_pass(fctx_res.ptr, .Load)
	defer graphics.end_render_pass(pass)

	bg_entries := [2]wgpu.BindGroupEntry {
		graphics.render_bind_group_entry_buffer(0, renderer.uniform_buf, 256),
		graphics.render_bind_group_entry_texture(1, canvas_target.target.texture_view),
	}

	call := graphics.Indexed_Draw_Call {
		pipeline    = renderer.pipeline,
		vertex_buf  = renderer.vertex_buf,
		vertex_size = u64(size_of([4]Sphere_UI_Vertex{})),
		index_buf   = renderer.index_buf,
		index_size  = u64(size_of([6]u32{})),
		index_count = renderer.index_count,
	}
	graphics.render_draw_indexed_with_bind_group(
		pass,
		render_ctx.ptr.device,
		call,
		renderer.bind_group_layout,
		bg_entries[:],
	)
}

@(tag = "system")
sphere_ui_feedback_system :: proc(world: ^ecs.World, state_res: params.Res(Sphere_UI_State)) {
	state := state_res.ptr
	if state == nil do return

	for arch in ecs.query(world, ui.Slider) {
		sliders := ecs.arch_get_field(arch, ui.Slider)
		if len(sliders) == 0 do continue
		v := sliders[0].value

		canvas_node := ecs.world_get_component(world, state.canvas_entity, ui.UI_Node)
		if canvas_node != nil {
			canvas_node.bg_color = {0.08 + v * 0.2, 0.1 + v * 0.15, 0.14 + v * 0.25, 0.85}
		}
		break
	}

	for arch in ecs.query(world, ui.Button) {
		buttons := ecs.arch_get_field(arch, ui.Button)
		for i in 0 ..< len(buttons) {
			if buttons[i].is_clicked {
				log.info("test_ui_3d: sphere-mapped button clicked")
				return
			}
		}
	}
}

main :: proc() {
	args := os.args
	duration := 10 * time.Second
	if len(args) > 1 {
		if parsed, ok := gtime.parse_duration(args[1]); ok {
			duration = parsed
		}
	}

	application := errors.unwrap(
		app.app_init(
			[]app.Plugin {
				windowing.Window_Plugin(),
				graphics.Render_Plugin(),
				fps.Fps_Plugin(.Uncapped),
				input.Input_Plugin(),
				ui.UI_Plugin(),
			},
		),
	)
	defer {
		app.app_destroy(&application)
	}

	app.app_add_resource(&application, graphics.Clear_Color{r = 0.35, g = 0.35, b = 0.35})

	app.app_add_system(&application, app.Startup, setup_system)
	app.app_add_system(
		&application,
		app.Update,
		sphere_ui_input_system,
		before = []app.System_Dependency {
			rawptr(ui.ui_button_interaction_system),
			rawptr(ui.ui_slider_interaction_system),
		},
	)
	app.app_add_system(&application, app.Update, sphere_ui_feedback_system)
	app.app_add_system(
		&application,
		app.Render,
		sphere_ui_render_system,
		after = []app.System_Dependency{rawptr(graphics.main_render_system)},
	)

	start_time := time.tick_now()
	screenshot_taken := false
	screenshot_time := duration / 4

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		if !screenshot_taken && elapsed >= screenshot_time {
			graphics.capture_screenshot(&application.world, "test_ui_3d_screenshot.png", .PNG)
			screenshot_taken = true
		}

		if elapsed >= duration {
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)
	}
}
