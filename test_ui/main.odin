package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import "vendor:sdl3"

import "../app"
import "../ecs"
import "../ecs/params"
import systems "../ecs/systems"
import errors "../errors"
import fps "../fps"
import graphics "../graphics"
import twoD "../graphics/2d"
import input "../input"
import log "../logging"
import gmem "../mem"
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

// Tag component to associate UI element containers with a page index
Page_Tag :: struct {
	page_index: int,
}

Showcase_State :: struct {
	start_time:     time.Tick,
	grid_despawned: bool,
	verified:       bool,
	box_canvas:     ecs.Entity,
	box_color:      [4]f32,
	active_page:    int,
	page_count:     int,
}

Scroll_Content_Tag :: struct {}

global_tracker: gmem.Tracker

@(tag = "system")
setup_system :: proc(world: ^ecs.World, commands: params.Commands) {
	// Root Container (100% viewport)
	root := ecs.commands_spawn(commands.ptr)
	ecs.entity_commands_add_components(
		root,
		ui.UI_Node {
			width    = {100.0, .Percent},
			height   = {100.0, .Percent},
			bg_color = {0.1, 0.1, 0.12, 0.0}, // transparent to reveal background
		},
		ui.Layout_Flex{direction = .Column, justify_content = .Center, align_items = .Center},
	)

	// Add showcase state resource directly to world so immediate system runs can access it
	ecs.world_add_resource(
		world,
		Showcase_State {
			start_time = time.tick_now(),
			grid_despawned = false,
			verified = false,
			box_canvas = root.entity,
			box_color = {0.5, 0.15, 0.7, 0.5},
			active_page = 0,
			page_count = 5,
		},
	)

	// Spawn initial slide 1 via system runner
	sys := systems.new_system(slide_flex_system)
	systems.run_system(world, sys)
	systems.destroy_system(world, sys)
}


// Keyboard input system that highlights grid cells on pressing '1' to '9'
@(tag = "system")
keyboard_grid_system :: proc(world: ^ecs.World, key_inp: input.Input(input.KeyCode)) {
	for arch in ecs.query(world, ui.UI_Node, Grid_Cell) {
		nodes, cells, count := ecs.arch_zip(arch, ui.UI_Node, Grid_Cell)

		for i in 0 ..< count {
			node := &nodes[i]
			cell := &cells[i]

			kc: input.KeyCode
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
@(tag = "system")
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
	gamepad_sensitivity := f32(0.001)
	gamepad_delta := 1.0 + (rt - lt) * gamepad_sensitivity

	frame_scale := pinch_delta * gamepad_delta

	for arch in ecs.query(world, ui.UI_Node, Pinchable_Box) {
		nodes, boxes, count := ecs.arch_zip(arch, ui.UI_Node, Pinchable_Box)

		for i in 0 ..< count {
			node := &nodes[i]
			box := &boxes[i]

			// Accumulate frame-relative scaling changes on the component
			box.scale = clamp(box.scale * frame_scale, 0.1, 10.0)

			node.width = {box.base_width * box.scale, .Pixels}
			node.height = {box.base_height * box.scale, .Pixels}
		}
	}
}


// --- Separate Slide Showcase Systems ---

@(tag = "system")
slide_flex_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	flex_panel := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		flex_panel,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			padding = {15.0, 15.0, 15.0, 15.0},
			bg_color = {0.18, 0.18, 0.22, 0.8},
			border_color = {0.3, 0.3, 0.4, 1.0},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		flex_panel,
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Start,
			align_items = .Stretch,
			gap = 15.0,
		},
	)
	ecs.world_add_component(world, flex_panel, Page_Tag{page_index = 0})
	ecs.world_add_relation(world, flex_panel, ui.UI_ChildOf, state.box_canvas)

	for i in 0 ..< 3 {
		btn := ecs.world_spawn(world)
		grow_val: f32 = (i == 1) ? 1.0 : 0.0
		node := ui.UI_Node {
			width        = {100.0, .Percent},
			height       = {60.0, .Pixels},
			bg_color     = {0.25, 0.25, 0.35, 1.0},
			border_color = {0.4, 0.4, 0.6, 1.0},
			border_width = 1.0,
		}
		if i == 0 {
			node.padding = {18.0, 20.0, 15.0, 20.0}
			ecs.world_add_component(
				world,
				btn,
				ui.Label{text = "[c=yellow][b]Click Me![/b][/c]", color = {1.0, 1.0, 1.0, 1.0}},
			)
		}
		ecs.world_add_component(world, btn, node)
		ecs.world_add_component(world, btn, ui.Flex_Item{grow = grow_val})
		ecs.world_add_component(world, btn, ui.Button{})
		ecs.world_add_component(
			world,
			btn,
			ui.UI_Style {
				normal = {
					bg_color = {0.25, 0.25, 0.35, 1.0},
					border_color = {0.4, 0.4, 0.6, 1.0},
					border_width = 1.0,
				},
				hover = {
					bg_color = {0.35, 0.35, 0.5, 1.0},
					border_color = {0.5, 0.5, 0.8, 1.0},
					border_width = 1.5,
				},
				active = {
					bg_color = {0.5, 0.4, 0.6, 1.0},
					border_color = {0.7, 0.5, 0.9, 1.0},
					border_width = 2.0,
				},
			},
		)
		ecs.world_add_relation(world, btn, ui.UI_ChildOf, flex_panel)
	}
}

@(tag = "system")
slide_grid_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	grid_panel := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		grid_panel,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			padding = {15.0, 15.0, 15.0, 15.0},
			bg_color = {0.15, 0.2, 0.18, 0.8},
			border_color = {0.25, 0.4, 0.3, 1.0},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		grid_panel,
		ui.Layout_Grid{columns = 3, rows = 3, column_gap = 10.0, row_gap = 10.0},
	)
	ecs.world_add_component(world, grid_panel, Page_Tag{page_index = 1})
	ecs.world_add_relation(world, grid_panel, ui.UI_ChildOf, state.box_canvas)

	for row in 0 ..< 3 {
		for col in 0 ..< 3 {
			idx := row * 3 + col + 1
			cell := ecs.world_spawn(world)
			ecs.world_add_component(
				world,
				cell,
				ui.UI_Node {
					width = {100.0, .Percent},
					height = {100.0, .Percent},
					bg_color = {0.2, 0.3, 0.25, 1.0},
					border_color = {0.3, 0.5, 0.4, 1.0},
					border_width = 1.0,
				},
			)
			ecs.world_add_component(world, cell, Grid_Cell{index = idx})
			ecs.world_add_relation(world, cell, ui.UI_ChildOf, grid_panel)
		}
	}
}

@(tag = "system")
slide_selection_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	container := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		container,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			padding = {15.0, 15.0, 15.0, 15.0},
			bg_color = {0.15, 0.18, 0.22, 0.6},
			border_color = {0.3, 0.35, 0.4, 0.8},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		container,
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Start,
			align_items = .Start,
			gap = 15.0,
		},
	)
	ecs.world_add_component(world, container, Page_Tag{page_index = 2})
	ecs.world_add_relation(world, container, ui.UI_ChildOf, state.box_canvas)

	lbl := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		lbl,
		ui.UI_Node{width = {100.0, .Percent}, height = {25.0, .Pixels}},
	)
	ecs.world_add_component(world, lbl, ui.Label{text = "[c=cyan][b]Selection Controls[/b][/c]"})
	ecs.world_add_relation(world, lbl, ui.UI_ChildOf, container)

	chk := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		chk,
		ui.UI_Node {
			width = {28.0, .Pixels},
			height = {28.0, .Pixels},
			bg_color = {0.2, 0.2, 0.2, 1.0},
			border_color = {0.4, 0.4, 0.4, 1.0},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		chk,
		ui.Checkbox{checked = true, active_color = {0.2, 0.7, 0.4, 1.0}},
	)
	ecs.world_add_relation(world, chk, ui.UI_ChildOf, container)

	rad := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		rad,
		ui.UI_Node {
			width = {28.0, .Pixels},
			height = {28.0, .Pixels},
			bg_color = {0.2, 0.2, 0.2, 1.0},
			border_color = {0.4, 0.4, 0.4, 1.0},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		rad,
		ui.RadioButton{checked = true, active_color = {0.8, 0.4, 0.2, 1.0}},
	)
	ecs.world_add_relation(world, rad, ui.UI_ChildOf, container)
}

@(tag = "system")
slide_anchor_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	container := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		container,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			padding = {15.0, 15.0, 15.0, 15.0},
			bg_color = {0.15, 0.18, 0.22, 0.6},
			border_color = {0.3, 0.35, 0.4, 0.8},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(world, container, Page_Tag{page_index = 3})
	ecs.world_add_relation(world, container, ui.UI_ChildOf, state.box_canvas)

	pinch_box := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		pinch_box,
		ui.UI_Node {
			width = {140.0, .Pixels},
			height = {140.0, .Pixels},
			bg_color = {0.5, 0.25, 0.25, 1.0},
			border_color = {0.7, 0.4, 0.4, 1.0},
			border_width = 2.0,
		},
	)
	ecs.world_add_component(
		world,
		pinch_box,
		ui.Layout_Anchor {
			anchor_min = {0.5, 0.5},
			anchor_max = {0.5, 0.5},
			offset_min = {0.0, 0.0},
			offset_max = {0.0, 0.0},
		},
	)
	ecs.world_add_component(
		world,
		pinch_box,
		Pinchable_Box{base_width = 140.0, base_height = 140.0, scale = 1.0},
	)
	ecs.world_add_relation(world, pinch_box, ui.UI_ChildOf, container)
}

@(tag = "system")
slide_text_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	container := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		container,
		ui.UI_Node {
			width = {100.0, .Percent},
			height = {100.0, .Percent},
			padding = {15.0, 15.0, 15.0, 15.0},
			bg_color = {0.15, 0.18, 0.22, 0.6},
			border_color = {0.3, 0.35, 0.4, 0.8},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		container,
		ui.Layout_Flex {
			direction = .Column,
			justify_content = .Start,
			align_items = .Start,
			gap = 15.0,
		},
	)
	ecs.world_add_component(world, container, Page_Tag{page_index = 4})
	ecs.world_add_relation(world, container, ui.UI_ChildOf, state.box_canvas)

	lbl := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		lbl,
		ui.UI_Node{width = {100.0, .Percent}, height = {25.0, .Pixels}},
	)
	ecs.world_add_component(
		world,
		lbl,
		ui.Label{text = "[c=orange][b]Text Input & Progress[/b][/c]"},
	)
	ecs.world_add_relation(world, lbl, ui.UI_ChildOf, container)

	txt := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		txt,
		ui.UI_Node {
			width = {200.0, .Pixels},
			height = {32.0, .Pixels},
			padding = {5.0, 5.0, 5.0, 5.0},
			bg_color = {0.1, 0.1, 0.1, 1.0},
			border_color = {0.4, 0.4, 0.4, 1.0},
			border_width = 1.0,
		},
	)
	ecs.world_add_component(
		world,
		txt,
		ui.TextInput{text = make([dynamic]u8, context.allocator), max_length = 16},
	)
	ecs.world_add_relation(world, txt, ui.UI_ChildOf, container)

	pbar := ecs.world_spawn(world)
	ecs.world_add_component(
		world,
		pbar,
		ui.UI_Node {
			width = {200.0, .Pixels},
			height = {20.0, .Pixels},
			bg_color = {0.2, 0.2, 0.2, 1.0},
		},
	)
	ecs.world_add_component(
		world,
		pbar,
		ui.ProgressBar{value = 0.75, active_color = {0.3, 0.7, 0.9, 1.0}},
	)
	ecs.world_add_relation(world, pbar, ui.UI_ChildOf, container)
}

// Array of showcase system procedures to run on Spacebar keypress
SHOWCASE_SYSTEMS := [?]rawptr {
	rawptr(slide_flex_system),
	rawptr(slide_grid_system),
	rawptr(slide_selection_system),
	rawptr(slide_anchor_system),
	rawptr(slide_text_system),
}

// System handling Spacebar keypress: clears current showcase entities and runs the next showcase system in SHOWCASE_SYSTEMS array
@(tag = "system")
spacebar_showcase_system :: proc(
	world: ^ecs.World,
	showcase_state: params.Res(Showcase_State),
	key_inp: input.Input(input.KeyCode),
) {
	state := showcase_state.ptr
	if state == nil do return

	if input.is_pressed(key_inp, input.KeyCode.Space) {
		// Advance index in showcase system array
		state.active_page = (state.active_page + 1) % len(SHOWCASE_SYSTEMS)
		log.info(
			"Showcase: Spacebar pressed! Running showcase system %d/%d",
			state.active_page + 1,
			len(SHOWCASE_SYSTEMS),
		)

		// Clear all previous showcase container entities
		for arch in ecs.query(world, Page_Tag) {
			entities := ecs.arch_get_entities(arch)
			for ent in entities {
				ecs.world_despawn(world, ent)
			}
		}

		// Instantiate and execute next system procedure from SHOWCASE_SYSTEMS array via systems.run_system
		sys: ^systems.System
		switch state.active_page {
		case 0:
			sys = systems.new_system(slide_flex_system)
		case 1:
			sys = systems.new_system(slide_grid_system)
		case 2:
			sys = systems.new_system(slide_selection_system)
		case 3:
			sys = systems.new_system(slide_anchor_system)
		case 4:
			sys = systems.new_system(slide_text_system)
		}

		if sys != nil {
			systems.run_system(world, sys)
			systems.destroy_system(world, sys)
		}
	}
}

// Gamepad showcase system that logs when controller buttons are pressed/held/released
@(tag = "system")
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
@(tag = "system")
timer_system :: proc(world: ^ecs.World, showcase_state: params.Res(Showcase_State)) {
	state := showcase_state.ptr
	if state == nil do return

	elapsed := time.duration_seconds(time.tick_since(state.start_time))

	grid_res := ecs.world_get_resource(world, Grid_Panel_Res)
	if grid_res != nil && grid_res.entity.gen == 0 {
		// Resolve the placeholder to the real entity once spawned
		for arch in ecs.query(world, ui.Layout_Grid) {
			entities := ecs.arch_get_entities(arch)
			if len(entities) > 0 {
				grid_res.entity = entities[0]
				break
			}
		}
	}

	if !state.grid_despawned && elapsed >= 4.0 {
		if grid_res != nil && grid_res.entity != {} {
			log.info(
				"Test Showcase: Despawning the Grid Panel entity to trigger cascading cleanup...",
			)
			ecs.world_despawn(world, grid_res.entity)
			state.grid_despawned = true
			gmem.tracker_snapshot(&global_tracker)
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
@(tag = "system")
rotating_box_system :: proc(
	world: ^ecs.World,
	showcase_state: params.Res(Showcase_State),
	mouse_inp: input.Input(input.MouseButtonCode),
	win_desc: params.Res(windowing.Window_Descriptor),
) {
	state := showcase_state.ptr
	if state == nil do return

	elapsed := f32(time.duration_seconds(time.tick_since(state.start_time)))

	ref_w :=
		f32(win_desc.ptr.width) if win_desc.ptr != nil else f32(windowing.DEFAULT_WINDOW_DESCRIPTOR.width)
	ref_h :=
		f32(win_desc.ptr.height) if win_desc.ptr != nil else f32(windowing.DEFAULT_WINDOW_DESCRIPTOR.height)

	cx := ref_w * 0.5
	cy := ref_h * 0.5

	box_w: f32 = 270.0
	box_h: f32 = 250.0
	angle := elapsed * 1.0

	// Find the real box canvas entity in the world
	box_canvas_ent: ecs.Entity
	for arch in ecs.query(world, ui.UI_Canvas, transform.Transform) {
		canvases := ecs.arch_get_field(arch, ui.UI_Canvas)
		entities := ecs.arch_get_entities(arch)
		for i in 0 ..< len(canvases) {
			if canvases[i].render_mode == .World_Space {
				box_canvas_ent = entities[i]
				break
			}
		}
		if box_canvas_ent != {} do break
	}

	if box_canvas_ent == {} do return

	// 1. Update Box Canvas Transform (Rotation & Screen Centering)
	canvas_trans := ecs.world_get_component(world, box_canvas_ent, transform.Transform)
	if canvas_trans == nil do return

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

	// 2. Map Screen Mouse Coordinates to Box Local Coordinate Space using the Inverse of VP
	mpos := input.mouse_position(mouse_inp)
	camera_vp := ui.ui_projection_matrix(ref_w, ref_h)
	local_to_center := linalg.matrix4_translate_f32({-box_w * 0.5, -box_h * 0.5, 0.0})
	vp := camera_vp * canvas_trans.world_matrix * local_to_center
	inv_vp := linalg.matrix4_inverse(vp)

	mpos_ndc := twoD.project_point(camera_vp, mpos)
	mpos_ndc_4 := [4]f32{mpos_ndc.x, mpos_ndc.y, 0.0, 1.0}
	local_pos_4 := inv_vp * mpos_ndc_4
	local_x := local_pos_4.x / local_pos_4.w
	local_y := local_pos_4.y / local_pos_4.w

	input.set_target_mouse_position(mouse_inp, box_canvas_ent, {local_x, local_y})

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

	box_node := ecs.world_get_component(world, box_canvas_ent, ui.UI_Node)
	if box_node != nil {
		box_node.bg_color = state.box_color
	}

	// 4. Update scroll content y-offset based on scrollbar value (dynamically queried to avoid deferred entity generation mismatch)
	scroller_comp: ^ui.Scrollbar
	for arch in ecs.query(world, ui.Scrollbar) {
		scrollbars := ecs.arch_get_field(arch, ui.Scrollbar)
		if len(scrollbars) > 0 {
			scroller_comp = &scrollbars[0]
			break
		}
	}

	scroll_node: ^ui.UI_Node
	scroll_content_ent: ecs.Entity
	for arch in ecs.query(world, ui.UI_Node, Scroll_Content_Tag) {
		nodes := ecs.arch_get_field(arch, ui.UI_Node)
		entities := ecs.arch_get_entities(arch)
		if len(nodes) > 0 {
			scroll_node = &nodes[0]
			scroll_content_ent = entities[0]
			break
		}
	}

	if scroller_comp != nil && scroll_node != nil {
		max_scroll: f32 = 350.0 - 210.0 // scroll_content height is 350.0 now
		new_margin_top := -scroller_comp.value * max_scroll
		if scroll_node.margin[0] != new_margin_top {
			scroll_node.margin[0] = new_margin_top
			ui.ui_mark_dirty(world, scroll_content_ent)
		}
	}
}

main :: proc() {
	gmem.tracker_init(&global_tracker)
	context.allocator = gmem.tracker_allocator(&global_tracker)
	defer {
		gmem.tracker_report(&global_tracker, "test-ui")
		gmem.tracker_destroy(&global_tracker)
	}
	args := os.args
	duration := 10 * time.Second
	if len(args) > 1 {
		if parsed, ok := gtime.parse_duration(args[1]); ok {
			duration = parsed
		}
	}

	win_desc := windowing.Window_Descriptor {
		title      = "Press SPACEBAR!",
		fullscreen = windowing.DEFAULT_WINDOW_DESCRIPTOR.fullscreen,
		width      = windowing.DEFAULT_WINDOW_DESCRIPTOR.width,
		height     = windowing.DEFAULT_WINDOW_DESCRIPTOR.height,
		resizable  = windowing.DEFAULT_WINDOW_DESCRIPTOR.resizable,
	}
	application := errors.unwrap(
		app.app_init(
		[]app.Plugin {
			windowing.Window_Plugin(&win_desc),
			graphics.Render_Plugin(),
			//fps.Fps_Plugin(.Uncapped),
			input.Input_Plugin(),
			ui.UI_Plugin(),
		},
		),
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
	app.app_add_system(&application, app.Update, spacebar_showcase_system)

	start_time := time.tick_now()
	take_screenshot := false
	screenshot_taken := false
	screenshot_time := duration / 2

	for !application.should_exit {
		elapsed := time.tick_since(start_time)

		if take_screenshot && !screenshot_taken && elapsed >= screenshot_time {
			graphics.capture_screenshot(&application.world, "test_ui_screenshot.png", .PNG)
			screenshot_taken = true
		}

		if elapsed >= duration {
			ecs.emit(&application.world, app.App_Exit_Event{})
		}

		app.app_update(&application)
	}
}
