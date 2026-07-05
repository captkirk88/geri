package main

import "base:runtime"
import "core:c"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:testing"
import "core:time"
import "vendor:sdl3"

import "../app"
import "../ecs"
import "../ecs/params"
import fps "../fps"
import graphics "../graphics"
import twoD "../graphics/2d"
import input "../input"
import log "../logging"
import gtime "../time"
import transform "../transform"
import ui "../ui"
import "../windowing"

// Grid cell tag so we can query them to change highlight color or check if they still exist
Grid_Cell :: struct {
	index: int,
}

// Anchor target to scale based on scroll pinch
Pinchable_Box :: struct {
	base_width:  f32,
	base_height: f32,
	scale:       f32,
}

Grid_Panel_Res :: struct {
	entity: ecs.Entity,
}

Showcase_State :: struct {
	start_time:     time.Tick,
	grid_despawned: bool,
	verified:       bool,
	box_canvas:     ecs.Entity,
	box_color:      [4]f32,
}

setup_system :: proc(commands: params.Commands) {
	// Root Container
	root := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		root,
		ui.UI_Node {
			width    = {100.0, .Percent},
			height   = {100.0, .Percent},
			bg_color = {0.1, 0.1, 0.12, 0.0}, // transparent to reveal rotating box
		},
		ui.Layout_Flex {
			direction = .Row,
			justify_content = .Space_Between,
			align_items = .Stretch,
			gap = 20.0,
		},
	)

	// 1. FLEX PANEL (Left)
	flex_panel := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		flex_panel,
		ui.UI_Node {
			width        = {30.0, .Percent},
			height       = {100.0, .Percent},
			margin       = {20.0, 0.0, 20.0, 20.0},
			padding      = {20.0, 20.0, 20.0, 20.0},
			bg_color     = {0.18, 0.18, 0.22, 0.8}, // semi-transparent
			border_color = {0.3, 0.3, 0.4, 1.0},
			border_width = 2.0,
		},
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Start,
			align_items = .Stretch,
			gap = 15.0,
		},
	)
	ecs.commands_add_relation(commands.ptr, flex_panel.entity, ecs.ChildOf, root.entity)

	// Flex children buttons
	for i in 0 ..< 3 {
		btn := ecs.commands_spawn(commands.ptr)
		grow_val: f32 = (i == 1) ? 1.0 : 0.0 // Second button grows to fill space

		node := ui.UI_Node {
			width        = {100.0, .Percent},
			height       = {60.0, .Pixels},
			bg_color     = {0.25, 0.25, 0.35, 1.0},
			border_color = {0.4, 0.4, 0.6, 1.0},
			border_width = 1.0,
		}

		if i == 0 {
			node.padding = {18.0, 20.0, 15.0, 20.0} // Vertical centering padding
			ecs.entity_commands_add_components(
				btn,
				ui.Label{text = "[c=yellow][b]Click Me![/b][/c]", color = {1.0, 1.0, 1.0, 1.0}},
			)
		}

		ecs.entity_commands_add_components(
			btn,
			node,
			ui.Flex_Item{grow = grow_val},
			ui.Button{},
			ui.UI_Style {
				normal = {
					bg_color = {0.25, 0.25, 0.35, 1.0},
					border_color = {0.4, 0.4, 0.6, 1.0},
					border_width = 1.0,
				},
				hover = {
					bg_color = {0.35, 0.35, 0.5, 1.0},
					border_color = {0.4, 0.4, 0.6, 1.0},
					border_width = 1.0,
				},
				active = {
					bg_color = {0.5, 0.4, 0.6, 1.0},
					border_color = {0.4, 0.4, 0.6, 1.0},
					border_width = 1.0,
				},
			},
		)
		ecs.commands_add_relation(commands.ptr, btn.entity, ecs.ChildOf, flex_panel.entity)
	}

	// 2. GRID PANEL (Middle)
	grid_panel := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		grid_panel,
		ui.UI_Node {
			width        = {30.0, .Percent},
			height       = {100.0, .Percent},
			margin       = {20.0, 0.0, 20.0, 0.0},
			padding      = {20.0, 20.0, 20.0, 20.0},
			bg_color     = {0.15, 0.2, 0.18, 0.8}, // semi-transparent
			border_color = {0.25, 0.4, 0.3, 1.0},
			border_width = 2.0,
		},
		ui.Layout_Grid{columns = 3, rows = 3, column_gap = 10.0, row_gap = 10.0},
	)
	ecs.commands_add_relation(commands.ptr, grid_panel.entity, ecs.ChildOf, root.entity)

	// Store grid panel entity so timer system can despawn it
	ecs.commands_add_resource_no_destroy(commands.ptr, Grid_Panel_Res{entity = grid_panel.entity})

	// Spawn 3x3 Grid Cells
	for row in 0 ..< 3 {
		for col in 0 ..< 3 {
			idx := row * 3 + col + 1 // 1-based cell index
			cell := ecs.commands_spawn(commands.ptr)
			ecs.entity_commands_add_components(
				cell,
				ui.UI_Node {
					width = {100.0, .Percent},
					height = {100.0, .Percent},
					bg_color = {0.2, 0.3, 0.25, 1.0},
					border_color = {0.3, 0.5, 0.4, 1.0},
					border_width = 1.0,
				},
				Grid_Cell{index = idx},
			)
			ecs.commands_add_relation(commands.ptr, cell.entity, ecs.ChildOf, grid_panel.entity)
		}
	}

	// 3. ANCHOR PANEL (Right)
	anchor_panel := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		anchor_panel,
		ui.UI_Node {
			width        = {30.0, .Percent},
			height       = {100.0, .Percent},
			margin       = {20.0, 20.0, 20.0, 0.0},
			padding      = {20.0, 20.0, 20.0, 20.0},
			bg_color     = {0.22, 0.18, 0.18, 0.8}, // semi-transparent
			border_color = {0.4, 0.3, 0.3, 1.0},
			border_width = 2.0,
		},
	)
	ecs.commands_add_relation(commands.ptr, anchor_panel.entity, ecs.ChildOf, root.entity)

	// Spawning an anchored child in the center that can be scaled
	pinch_box := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		pinch_box,
		ui.UI_Node {
			width = {150.0, .Pixels},
			height = {150.0, .Pixels},
			bg_color = {0.5, 0.25, 0.25, 1.0},
			border_color = {0.7, 0.4, 0.4, 1.0},
			border_width = 2.0,
		},
		ui.Layout_Anchor {
			anchor_min = {0.5, 0.5},
			anchor_max = {0.5, 0.5},
			offset_min = {0.0, 0.0},
			offset_max = {0.0, 0.0},
		},
		Pinchable_Box{base_width = 150.0, base_height = 150.0, scale = 1.0},
	)
	ecs.commands_add_relation(commands.ptr, pinch_box.entity, ecs.ChildOf, anchor_panel.entity)

	// Spawn Rotating Box UI Canvas
	box_canvas := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		box_canvas,
		ui.UI_Node {
			width        = {250.0, .Pixels},
			height       = {250.0, .Pixels},
			bg_color     = {0.5, 0.15, 0.7, 0.5}, // Initially semi-transparent purple
			border_color = {0.7, 0.3, 0.9, 1.0},
			border_width = 2.0,
		},
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Center,
			align_items = .Center,
			gap = 10.0,
		},
		ui.UI_Canvas{render_mode = .World_Space, reference_size = {250, 250}},
		transform.Transform{world_matrix = linalg.MATRIX4F32_IDENTITY},
	)

	// Label for slider
	lbl := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		lbl,
		ui.UI_Node {
			width   = {100.0, .Percent},
			height  = {30.0, .Pixels},
			padding = {0, 0, 0, 35}, // Indent to align nicely
		},
		ui.Label{text = "[c=white][b]Box Color[/b][/c]", color = {1.0, 1.0, 1.0, 1.0}},
	)
	ecs.commands_add_relation(commands.ptr, lbl.entity, ecs.ChildOf, box_canvas.entity)

	// Color slider
	sld := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		sld,
		ui.UI_Node {
			width = {180.0, .Pixels},
			height = {20.0, .Pixels},
			bg_color = {0.2, 0.2, 0.2, 1.0},
			border_color = {0.4, 0.4, 0.4, 1.0},
			border_width = 1.0,
		},
		ui.Slider {
			value = 0.5,
			active_color = {0.8, 0.2, 0.6, 1.0},
			knob_color = {1.0, 1.0, 1.0, 1.0},
		},
	)
	ecs.commands_add_relation(commands.ptr, sld.entity, ecs.ChildOf, box_canvas.entity)

	// Add showcase state resource
	ecs.commands_add_resource(
		commands.ptr,
		Showcase_State {
			start_time = time.tick_now(),
			grid_despawned = false,
			verified = false,
			box_canvas = box_canvas.entity,
			box_color = {0.5, 0.15, 0.7, 0.5},
		},
	)
}

// Keyboard input system that highlights grid cells on pressing '1' to '9'
keyboard_grid_system :: proc(world: ^ecs.World, key_inp: input.Input(input.KeyCode)) {
	for arch in ecs.query(world, ui.UI_Node, Grid_Cell) {
		nodes := ecs.arch_get_field(arch, ui.UI_Node)
		cells := ecs.arch_get_field(arch, Grid_Cell)

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			cell := &cells[i]

			kc := input.KeyCode.None
			switch cell.index {
			case 1:
				kc = .Num1
			case 2:
				kc = .Num2
			case 3:
				kc = .Num3
			case 4:
				kc = .Num4
			case 5:
				kc = .Num5
			case 6:
				kc = .Num6
			case 7:
				kc = .Num7
			case 8:
				kc = .Num8
			case 9:
				kc = .Num9
			}

			if kc != .None && input.is_down(key_inp, kc) {
				node.bg_color = {0.4, 0.7, 0.5, 1.0} // bright green highlight
			} else {
				node.bg_color = {0.2, 0.3, 0.25, 1.0}
			}
		}
	}
}

// Gesture scaling system that updates UI size on pinch scale or gamepad triggers
gesture_scaling_system :: proc(
	world: ^ecs.World,
	gesture_inp: input.Input(input.Gesture),
	gamepad_inp: input.Input(input.GamepadAxis),
) {
	// Pinch scale is a frame-relative delta (defaults to 1.0 when no pinch is updating)
	pinch_delta := input.pinch_scale(gesture_inp)

	// Gamepad trigger input is also frame-relative delta
	rt := input.gamepad_axis(gamepad_inp, .TriggerRight)
	lt := input.gamepad_axis(gamepad_inp, .TriggerLeft)
	gamepad_delta := 1.0 + (rt - lt) * 0.1

	frame_scale := pinch_delta * gamepad_delta

	for arch in ecs.query(world, ui.UI_Node, Pinchable_Box) {
		nodes := ecs.arch_get_field(arch, ui.UI_Node)
		boxes := ecs.arch_get_field(arch, Pinchable_Box)

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			box := &boxes[i]

			// Accumulate frame-relative scaling changes on the component
			box.scale = clamp(box.scale * frame_scale, 0.1, 10.0)

			node.width = {box.base_width * box.scale, .Pixels}
			node.height = {box.base_height * box.scale, .Pixels}

			state := ecs.world_get_resource(world, ui.UI_State)
			if state != nil {
				state.dirty = true
			}
		}
	}
}

// Gamepad showcase system that logs when controller buttons are pressed/held/released
gamepad_showcase_system :: proc(
	gp_buttons: input.Input(input.GamepadButton),
	gp_axes: input.Input(input.GamepadAxis),
) {
	if input.is_pressed(gp_buttons, input.GamepadButton.South) do log.info("Showcase: Gamepad South button pressed!")
	if input.is_pressed(gp_buttons, input.GamepadButton.East) do log.info("Showcase: Gamepad East button pressed!")
	if input.is_pressed(gp_buttons, input.GamepadButton.North) do log.info("Showcase: Gamepad North button pressed!")
	if input.is_pressed(gp_buttons, input.GamepadButton.West) do log.info("Showcase: Gamepad West button pressed!")

	left_x := input.gamepad_axis(gp_axes, .LeftX)
	left_y := input.gamepad_axis(gp_axes, .LeftY)
	if left_x != 0.0 || left_y != 0.0 {
		log.info("Showcase: Gamepad Left Stick: (%.2f, %.2f)", left_x, left_y)
	}
}

// Timer system that manages the despawn countdown and logs cascading deletion details
timer_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	elapsed := time.duration_seconds(time.tick_since(state.start_time))

	if !state.grid_despawned && elapsed >= 4.0 {
		grid_res := ecs.world_get_resource(world, Grid_Panel_Res)
		if grid_res != nil {
			log.info(
				"Test Showcase: Despawning the Grid Panel entity to trigger cascading cleanup...",
			)
			ecs.world_despawn(world, grid_res.entity)
			state.grid_despawned = true
		}
	}

	if state.grid_despawned && !state.verified && elapsed >= 5.0 {
		count := 0
		for arch in ecs.query(world, Grid_Cell) {
			count += len(ecs.arch_get_entities(arch))
		}
		log.info(
			"Test Showcase Verification: Found %d active Grid_Cell entities (Expected: 0)",
			count,
		)
		state.verified = true
	}
}

// Rotating box system that updates the box's rotation, maps mouse position to local space, and updates color based on slider value
rotating_box_system :: proc(
	world: ^ecs.World,
	showcase_state: params.Res(Showcase_State),
	mouse_inp: input.Input(input.MouseButtonCode),
	window_res: params.Res(windowing.Window_Context),
) {
	state := showcase_state.ptr
	if state == nil || window_res.ptr == nil do return

	elapsed := f32(time.duration_seconds(time.tick_since(state.start_time)))

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)

	cx := f32(win_w) * 0.5
	cy := f32(win_h) * 0.5

	box_w: f32 = 250.0
	box_h: f32 = 250.0
	angle := elapsed * 1.0

	// 1. Update Box Canvas Transform (Rotation & Screen Centering)
	canvas_trans := ecs.world_get_component(world, state.box_canvas, transform.Transform)
	if canvas_trans != nil {
		c_val := linalg.cos(angle)
		s_val := linalg.sin(angle)
		canvas_trans.world_matrix = linalg.Matrix4f32 {
			c_val,
			-s_val,
			0.0,
			cx,
			s_val,
			c_val,
			0.0,
			cy,
			0.0,
			0.0,
			1.0,
			0.0,
			0.0,
			0.0,
			0.0,
			1.0,
		}
	}

	// 2. Map Screen Mouse Coordinates to Box Local Coordinate Space using the Inverse of VP
	mpos := input.mouse_position(mouse_inp)
	camera_vp := ui.ui_projection_matrix(f32(win_w), f32(win_h))
	local_to_center := linalg.matrix4_translate_f32({-box_w * 0.5, -box_h * 0.5, 0.0})
	vp := camera_vp * canvas_trans.world_matrix * local_to_center
	inv_vp := linalg.matrix4_inverse(vp)

	mpos_ndc := twoD.project_point(camera_vp, mpos)
	mpos_ndc_4 := [4]f32{mpos_ndc.x, mpos_ndc.y, 0.0, 1.0}
	local_pos_4 := inv_vp * mpos_ndc_4
	local_x := local_pos_4.x / local_pos_4.w
	local_y := local_pos_4.y / local_pos_4.w

	input.set_target_mouse_position(mouse_inp, state.box_canvas, {local_x, local_y})

	// 3. Update Box Color from the Slider's value
	for arch in ecs.query(world, ui.Slider) {
		sliders := ecs.arch_get_field(arch, ui.Slider)
		for i in 0 ..< len(sliders) {
			slider := &sliders[i]
			// Map slider value to box color (rotating RGB based on value)
			state.box_color = {
				slider.value,
				1.0 - slider.value,
				0.5 + slider.value * 0.5,
				0.8, // alpha
			}
		}
	}

	box_node := ecs.world_get_component(world, state.box_canvas, ui.UI_Node)
	if box_node != nil {
		box_node.bg_color = state.box_color
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

	application := app.app_init(
		[]app.Plugin {
			windowing.Window_Plugin(),
			graphics.Render_Plugin(),
			fps.Fps_Plugin(),
			input.Input_Plugin(),
			ui.UI_Plugin(),
		},
	)
	defer {
		app.app_destroy(&application)
	}

	// Register systems
	app.app_add_system(&application, app.Startup, setup_system)
	app.app_add_system(&application, app.Update, keyboard_grid_system)
	app.app_add_system(&application, app.Update, gesture_scaling_system)
	app.app_add_system(&application, app.Update, gamepad_showcase_system)
	app.app_add_system(&application, app.Update, timer_system)
	app.app_add_system(
		&application,
		app.Update,
		rotating_box_system,
		before = []rawptr {
			rawptr(ui.ui_button_interaction_system),
			rawptr(ui.ui_slider_interaction_system),
		},
	)

	app.app_run_schedule(&application, app.Startup)

	start_time := time.tick_now()
	screenshot_taken := false
	screenshot_time := duration / 2

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		if !screenshot_taken && elapsed >= screenshot_time {
			graphics.capture_screenshot(&application.world, "test_ui_screenshot.png", .PNG)
			screenshot_taken = true
		}

		if elapsed >= duration {
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)
	}
}
