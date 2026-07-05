package main

import camera "../src/camera"
import transform "../src/transform"
import "base:runtime"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/app"
import "../src/ecs"
import "../src/ecs/params"
import fps "../src/fps"
import graphics "../src/graphics"
import threeD "../src/graphics/3d"
import log "../src/logging"
import gtime "../src/time"
import "../src/windowing"
import "core:c"
import "core:math"
import "vendor:sdl3"
import "vendor:wgpu"

// Component to store shader pass states and simulation time
Blob :: struct {
	compute_pass: graphics.Shader_Pass,
	render_pass:  graphics.Shader_Pass,
	batch:        graphics.Batch3D,
	time:         f32,
	vertex_count: int,
	index_count:  int,
}

MyUniforms :: struct {
	time:      f32,
	intensity: f32,
	aspect:    f32,
	padding:   f32,
}

// Compute shader to deform vertices along sphere normal to create a jelly blob effect
COMPUTE_SHADER :: `
struct Vertex {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    color_r: f32,
    color_g: f32,
    color_b: f32,
    color_a: f32,
}
struct MyUniforms {
	time: f32,
    intensity: f32,
	aspect: f32,
	padding: f32,
}
@group(0) @binding(0) var<storage, read_write> vertices: array<Vertex>;
@group(0) @binding(1) var<storage, read_write> indices: array<u32>;
@group(0) @binding(2) var<uniform> uniforms: MyUniforms;

@compute @workgroup_size(64)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    let count = arrayLength(&vertices);
    if (index >= count) {
        return;
    }
    
    let px = vertices[index].pos_x;
    let py = vertices[index].pos_y;
    let pz = vertices[index].pos_z;
    
    let pos = vec3<f32>(px, py, pz);
    
    // Normal for sphere at origin is just normalized pos
    let normal = normalize(pos);
    
    // Reconstruct the original constant position of the vertex on the sphere
    let base_radius: f32 = 0.55;
    let original_pos = normal * base_radius;
    
    // Create animated 3D wave for deforming the sphere using the stable original position
    let wave = sin(original_pos.x * 6.0 + uniforms.time * 2.5) * 
               cos(original_pos.y * 6.0 + uniforms.time * 2.0) * 
               sin(original_pos.z * 6.0 + uniforms.time * 3.0);
               
    let displacement = wave * 0.08 * uniforms.intensity;
    let new_pos = normal * (base_radius + displacement);
    
    vertices[index].pos_x = new_pos.x;
    vertices[index].pos_y = new_pos.y;
    vertices[index].pos_z = new_pos.z;
    
    // Animate color based on time and wave displacement using the stable original position
    vertices[index].color_r = 0.1 + 0.6 * (0.5 + 0.5 * cos(uniforms.time + original_pos.x * 3.0));
    vertices[index].color_g = 0.3 + 0.5 * (0.5 + 0.5 * sin(uniforms.time + original_pos.y * 3.0));
    vertices[index].color_b = 0.5 + 0.5 * (0.5 + 0.5 * sin(uniforms.time * 1.5 + wave));
    vertices[index].color_a = 1.0;
}
`

// Render shader that does vertex projection and directional lighting
RENDER_SHADER :: `
struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
}
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) light: f32,
}
struct MyUniforms {
	time: f32,
    intensity: f32,
	aspect: f32,
	padding: f32,
}
@group(0) @binding(0) var<uniform> uniforms: MyUniforms;

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    
    out.clip_position = vec4<f32>(model.position.x / uniforms.aspect, model.position.y, model.position.z * 0.5, 1.0);
    out.color = model.color;
    
    // Directional light from top-right-front
    let light_dir = normalize(vec3<f32>(0.5, 0.8, 1.0));
    let normal = normalize(model.position);
    out.light = clamp(dot(normal, light_dir) * 0.7 + 0.3, 0.0, 1.0);
    
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let pulse = 0.08 * sin(uniforms.time * 4.0) * uniforms.intensity;
    let base_color = vec4<f32>(
        clamp(in.color.r + pulse, 0.0, 1.0),
        clamp(in.color.g - pulse, 0.0, 1.0),
        clamp(in.color.b + pulse * 0.4, 0.0, 1.0),
        in.color.a
    );
    return vec4<f32>(base_color.rgb * in.light, base_color.a);
}
`

setup_system :: proc(
	commands: params.Commands,
	render_ctx_res: params.Res(graphics.Render_Context),
) {
	ctx := render_ctx_res.ptr
	if ctx == nil || ctx.device == nil do return

	log.info("Compiling and initializing 3D blob shader passes...")


	// 1. Compile 3D Render Shader Pass
	render_r: strings.Reader
	render_pass, render_ok := graphics.create_render_shader_pass(
		ctx.device,
		strings.to_reader(&render_r, RENDER_SHADER),
		"vs_main",
		"fs_main",
		true, // is_3d = true
		ctx.config.format,
		16,
	)
	if !render_ok {
		log.error("Failed to compile 3D Render Shader Pass.")
		return
	}

	// 2. Compile Compute Shader Pass
	compute_r: strings.Reader
	compute_pass, compute_ok := graphics.create_compute_shader_pass(
		ctx.device,
		strings.to_reader(&compute_r, COMPUTE_SHADER),
		"cs_main",
		16,
	)
	if !compute_ok {
		log.error("Failed to compile Compute Shader Pass.")
		graphics.destroy_shader_pass(&render_pass)
		return
	}

	log.info("Shader passes compiled successfully!")

	// 3. Spawn Shader Entity with Transform and Gizmo3D
	blob_batch := graphics.init_batch3d(ctx.device, ctx.config.format)
	shader_comp := Blob {
		compute_pass = compute_pass,
		render_pass  = render_pass,
		batch        = blob_batch,
		time         = 0.0,
	}

	entity_t := transform.Transform{}
	transform.init(&entity_t)

	gizmo := threeD.Gizmo3D {
		size      = 1.5,
		thickness = 0.08,
	}

	entity := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(entity, shader_comp, entity_t)

	// Spawn camera entity so that Gizmo3D has a camera to project from
	cam := camera.Camera{}
	camera.init(&cam)
	camera.set_perspective(&cam, math.PI / 3.0, 800.0 / 600.0, 0.1, 100.0)

	cam_t := transform.Transform{}
	transform.init(&cam_t)
	transform.set_translation(&cam_t, {0.0, 0.0, -2.5})
	transform.set_rotation(&cam_t, linalg.quaternion_angle_axis_f32(0, {0, 1, 0}))

	cam_ent := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(cam_ent, cam, cam_t)

	// 4. Initialize and register default font for FPS/HUD rendering
	font: graphics.Font
	if graphics.font_init(&font, "C:\\Windows\\Fonts\\arial.ttf", 32.0) {
		ecs.commands_add_resource(
			commands.ptr,
			font,
			proc(f: ^graphics.Font, alloc: runtime.Allocator) {
				graphics.font_destroy(f)
			},
		)
	}

	// 5. Register Clear_Color resource to clear screen at beginning of frame
	clear_color := graphics.Clear_Color{0.05, 0.08, 0.12, 1.0}
	ecs.commands_add_resource(commands.ptr, clear_color)
}

draw_shader_system :: proc(
	render_ctx_res: params.Res(graphics.Render_Context),
	frame_ctx_res: params.Res(graphics.Frame_Context),
	window_ctx_res: params.Res(windowing.Window_Context),
	shader_param: params.Single(Blob),
) {
	render_ctx := render_ctx_res.ptr
	frame_ctx := frame_ctx_res.ptr
	shader_data := shader_param.value
	batch := &shader_data.batch
	window_ctx := window_ctx_res.ptr

	if render_ctx == nil || render_ctx.device == nil || frame_ctx.encoder == nil || frame_ctx.texture_view == nil do return
	if shader_data == nil do return
	if window_ctx == nil || window_ctx.window == nil do return


	win_w, win_h: c.int = 800, 600

	sdl3.GetWindowSize(window_ctx.window, &win_w, &win_h)
	aspect := f32(win_w) / f32(win_h)

	// 1. Update uniforms (time, intensity, aspect, padding)
	shader_data.time += 0.016
	uniforms := MyUniforms {
		time      = shader_data.time,
		intensity = 1.0,
		aspect    = aspect,
		padding   = 0.0,
	}

	graphics.shader_pass_update_uniforms(&shader_data.compute_pass, render_ctx, uniforms)
	graphics.shader_pass_update_uniforms(&shader_data.render_pass, render_ctx, uniforms)

	// 2. Generate 3D UV Sphere once at startup
	if shader_data.vertex_count == 0 {
		log.info("Generating 3D UV Sphere vertices for blob jelly simulation...")

		cols, rows := 80, 80
		radius := f32(0.55)

		for r in 0 ..= rows {
			phi := math.PI * f32(r) / f32(rows)
			for c in 0 ..= cols {
				theta := 2.0 * math.PI * f32(c) / f32(cols)

				x := radius * math.sin(phi) * math.cos(theta)
				y := radius * math.sin(phi) * math.sin(theta)
				z := radius * math.cos(phi)

				append(
					&batch.vertices,
					graphics.Vertex3D{position = {x, y, z}, color = {0.2, 0.4, 0.6, 1.0}},
				)
			}
		}

		// Create indices for triangles
		for r in 0 ..< rows {
			for c in 0 ..< cols {
				i0 := u32(r * (cols + 1) + c)
				i1 := u32(r * (cols + 1) + (c + 1))
				i2 := u32((r + 1) * (cols + 1) + c)
				i3 := u32((r + 1) * (cols + 1) + (c + 1))

				// Triangle 1 (CCW)
				append(&batch.indices, i0, i2, i1)
				// Triangle 2 (CCW)
				append(&batch.indices, i1, i2, i3)
			}
		}

		shader_data.vertex_count = len(batch.vertices)
		shader_data.index_count = len(batch.indices)

		graphics.batch3d_prepare_buffers(batch, render_ctx)

		// Immediately clear CPU arrays so main_render_system does not try to flush them
		clear(&batch.vertices)
		clear(&batch.indices)
	}

	// 3. Execute Compute Pass on vertex buffer
	workgroups := u32((shader_data.vertex_count + 63) / 64)
	if workgroups > 0 {
		@(static) compute_pass_idx := -1
		if compute_pass_idx == -1 {
			compute_pass_idx = graphics.batch3d_add_shader_pass(batch, shader_data.compute_pass)
		}
		graphics.batch3d_run_compute(
			batch,
			render_ctx,
			frame_ctx.encoder,
			compute_pass_idx,
			workgroups,
		)
	}

	// 4. Begin Render Pass and draw the GPU-deformed UV sphere
	@(static) render_pass_idx := -1
	if render_pass_idx == -1 {
		render_pass_idx = graphics.batch3d_add_shader_pass(batch, shader_data.render_pass)
	}
	graphics.batch3d_set_active_pass(batch, render_pass_idx)

	color := wgpu.Color{0.05, 0.08, 0.12, 1.0}
	render_pass := graphics.begin_render_pass(frame_ctx, .Load, color)
	defer graphics.end_render_pass(render_pass)


	graphics.batch3d_draw_buffers(batch, render_pass, u32(shader_data.index_count))
}

cleanup_shader_system :: proc(
	exit_events: params.EventReader(app.App_Exit_Event),
	shader_param: params.Single(Blob),
) {
	if len(exit_events.events) > 0 {
		if shader_param.value != nil {
			log.info("Cleaning up shader pass WGPU bindings...")
			graphics.destroy_shader_pass(&shader_param.value.compute_pass)
			graphics.destroy_shader_pass(&shader_param.value.render_pass)
			graphics.destroy_batch3d(&shader_param.value.batch)
		}
	}
}

main :: proc() {
	args := os.args
	record_gif := true
	duration := 10 * time.Second
	if len(args) > 1 {
		for arg in args[1:] {
			if strings.starts_with(arg, "--") {
				arg := strings.trim_left(arg, "--")
				switch arg {
				case "no-record":
					record_gif = false
				case "help", "-":
					log.info("Usage: test_shader [DURATION] [--no-record|--help]")
					return
				case:
					log.warn("Unknown argument: %s", arg)
				}
			} else {
				if parsed, ok := gtime.parse_duration(arg); ok {
					duration = parsed
				}
			}
		}
	}

	log.info("Starting Shader Pass 3D Jelly Blob Demo...")

	application := app.app_init(
		[]app.Plugin {
			windowing.Window_Plugin(),
			graphics.Render_Plugin(),
			fps.Fps_Plugin(),
			threeD.Gizmo_Plugin_3D(),
		},
	)
	defer {
		app.app_destroy(&application)
	}

	// Register systems
	app.app_add_system(&application, app.Startup, setup_system)
	app.app_add_system(
		&application,
		app.Render,
		draw_shader_system,
		after = []rawptr{rawptr(graphics.main_render_system)},
	)
	app.app_add_system(
		&application,
		app.PostRender,
		cleanup_shader_system,
		after = []rawptr{rawptr(graphics.frame_present_system)},
		before = []rawptr{rawptr(graphics.render_cleanup_system)},
	)

	app.app_run_schedule(&application, app.Startup)


	start_time := time.tick_now()
	screenshot_taken := false
	screenshot_time := duration / 2
	frame_count := 0

	if record_gif {
		graphics.screenshot_recording_begin(&application.world, "test_shader_animation.gif")
	}

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		if !screenshot_taken && elapsed >= screenshot_time {
			graphics.capture_screenshot(&application.world, "test_shader_screenshot.png", .PNG)
			screenshot_taken = true
		}

		if elapsed >= duration {
			log.info("Duration reached, shutting down application.")
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)

		frame_count += 1
		if frame_count == 120 && record_gif {
			graphics.screenshot_recording_end(&application.world)
			log.info("Finished recording %d frames, shutting down.", frame_count)
			ecs.emit(&application.world, app.App_Exit_Event{})
		}
	}
}
