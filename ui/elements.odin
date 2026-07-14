package ui

import "../app"
import "../ecs"
import "../ecs/params"
import graphics "../graphics"
import twoD "../graphics/2d"
import input "../input"
import "../windowing"
import "core:math/linalg"
import regex "core:text/regex"
import "vendor:sdl3"
import stbtt "vendor:stb/truetype"

// Hoverable/Clickable button state tracker.
Button :: struct {
	is_hovered: bool,
	is_pressed: bool,
	is_clicked: bool,
}

// Text rendering element that automatically displays font textures.
Label :: struct {
	text:      string,
	color:     [4]f32,
	font_size: f32, // 0 = derive from font's default size
}

// Checkbox selection control component.
Checkbox :: struct {
	checked:      bool,
	active_color: [4]f32,
	is_hovered:   bool,
	is_pressed:   bool,
}

// Horizontal slider control component.
Slider :: struct {
	value:        f32, // normalized range [0.0, 1.0]
	active_color: [4]f32,
	knob_color:   [4]f32,
	is_hovered:   bool,
	is_pressed:   bool,
}

// Toggle selection control component.
Toggle :: struct {
	checked:      bool,
	active_color: [4]f32,
	knob_color:   [4]f32,
	is_hovered:   bool,
	is_pressed:   bool,
}

// Progress bar display component.
ProgressBar :: struct {
	value:        f32, // normalized range [0.0, 1.0]
	active_color: [4]f32,
}

// Radio button selection control component.
RadioButton :: struct {
	checked:      bool,
	active_color: [4]f32,
	is_hovered:   bool,
	is_pressed:   bool,
}

// Text input control component.
TextInput :: struct {
	text:                   [dynamic]u8,
	is_focused:             bool,
	is_hovered:             bool,
	is_pressed:             bool,
	max_length:             int,
	allowed_chars:          string,
	unwanted_chars:         string,
	restrict_regex_pattern: string,

	// Backspace/B Repeat State
	backspace_held:         bool,
	backspace_repeat_timer: f32,
}

ui_get_interaction_state :: proc(w: ^ecs.World, entity: ecs.Entity) -> (hovered, pressed: bool) {
	if btn := ecs.world_get_component(w, entity, Button); btn != nil {
		return btn.is_hovered, btn.is_pressed
	}
	if cb := ecs.world_get_component(w, entity, Checkbox); cb != nil {
		return cb.is_hovered, cb.is_pressed
	}
	if sld := ecs.world_get_component(w, entity, Slider); sld != nil {
		return sld.is_hovered, sld.is_pressed
	}
	if tg := ecs.world_get_component(w, entity, Toggle); tg != nil {
		return tg.is_hovered, tg.is_pressed
	}
	if rb := ecs.world_get_component(w, entity, RadioButton); rb != nil {
		return rb.is_hovered, rb.is_pressed
	}
	if ti := ecs.world_get_component(w, entity, TextInput); ti != nil {
		return ti.is_hovered, ti.is_pressed
	}
	return false, false
}

// Renderers for each control type
ui_render_label :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	label: ^Label,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	font := ecs.world_get_resource(w, graphics.Font)
	if font != nil {
		font_size := label.font_size > 0.0 ? label.font_size : font.pixel_height
		x := node.rect.x + node.padding[3]
		y := node.rect.y + node.padding[0]

		size_scale := font.pixel_height > 0.0 ? (font_size / font.pixel_height) : 1.0
		baseline_offset := f32(font.ascent) * font.scale * size_scale
		det2 := vp[0][0] * vp[1][1] - vp[0][1] * vp[1][0]
		if det2 < 0.0 {
			y += baseline_offset
		} else {
			y -= baseline_offset
		}

		color := label.color
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		graphics.draw_text(batch, label.text, x, y, font, 1.0, color, vp)
	}
}

ui_render_checkbox :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	checkbox: ^Checkbox,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	if checkbox.checked {
		pad: f32 = 4.0
		rect_x := node.rect.x + pad
		rect_y := node.rect.y + pad
		rect_w := max(f32(0.0), node.rect.w - pad * 2.0)
		rect_h := max(f32(0.0), node.rect.h - pad * 2.0)

		color := checkbox.active_color
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		twoD.draw_rect(batch, {rect_x, rect_y}, {rect_w, rect_h}, color, vp)
	}
}

ui_render_slider :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	slider: ^Slider,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	fill_w := node.rect.w * clamp(slider.value, 0.0, 1.0)
	if fill_w > 0.0 {
		color := slider.active_color
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		twoD.draw_rect(batch, {node.rect.x, node.rect.y}, {fill_w, node.rect.h}, color, vp)
	}
	knob_w := node.rect.h
	knob_x := node.rect.x + fill_w - knob_w / 2.0
	knob_x = clamp(knob_x, node.rect.x, node.rect.x + node.rect.w - knob_w)
	twoD.draw_rect(batch, {knob_x, node.rect.y}, {knob_w, node.rect.h}, slider.knob_color, vp)
}

ui_render_toggle :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	toggle: ^Toggle,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	if toggle.checked {
		color := toggle.active_color
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		twoD.draw_rect(batch, {node.rect.x, node.rect.y}, {node.rect.w, node.rect.h}, color, vp)
	}
	knob_w := node.rect.h
	knob_x := node.rect.x
	if toggle.checked {
		knob_x = node.rect.x + node.rect.w - knob_w
	}
	knob_x = clamp(knob_x, node.rect.x, node.rect.x + node.rect.w - knob_w)
	twoD.draw_rect(batch, {knob_x, node.rect.y}, {knob_w, node.rect.h}, toggle.knob_color, vp)
}

ui_render_progress_bar :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	progress_bar: ^ProgressBar,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	fill_w := node.rect.w * clamp(progress_bar.value, 0.0, 1.0)
	if fill_w > 0.0 {
		color := progress_bar.active_color
		if style != nil {
			state_style := style.normal
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		twoD.draw_rect(batch, {node.rect.x, node.rect.y}, {fill_w, node.rect.h}, color, vp)
	}
}

ui_render_radio_button :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	radio_button: ^RadioButton,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	if radio_button.checked {
		pad: f32 = node.rect.w * 0.25
		rect_x := node.rect.x + pad
		rect_y := node.rect.y + pad
		rect_w := max(f32(0.0), node.rect.w - pad * 2.0)
		rect_h := max(f32(0.0), node.rect.h - pad * 2.0)

		color := radio_button.active_color
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}
		twoD.draw_rect(batch, {rect_x, rect_y}, {rect_w, rect_h}, color, vp)
	}
}

ui_render_text_input :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	text_input: ^TextInput,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
	style: ^UI_Style,
) {
	font := ecs.world_get_resource(w, graphics.Font)
	if font != nil {
		font_size := font.pixel_height
		x := node.rect.x + node.padding[3]
		y := node.rect.y + node.padding[0]

		size_scale := font.pixel_height > 0.0 ? (font_size / font.pixel_height) : 1.0
		baseline_offset := f32(font.ascent) * font.scale * size_scale
		det2 := vp[0][0] * vp[1][1] - vp[0][1] * vp[1][0]
		if det2 < 0.0 {
			y += baseline_offset
		} else {
			y -= baseline_offset
		}

		color := [4]f32{1, 1, 1, 1}
		if style != nil {
			state_style := style.normal
			hovered, pressed := ui_get_interaction_state(w, entity)
			if pressed || text_input.is_focused {
				state_style = style.active
			} else if hovered {
				state_style = style.hover
			}
			if state_style.text_color.a > 0.0 {
				color = state_style.text_color
			}
		}

		text_str := string(text_input.text[:])
		graphics.draw_text(batch, text_str, x, y, font, 1.0, color, vp)

		if text_input.is_focused {
			// Calculate cursor position by counting character advances
			text_w: f32 = 0.0
			scale_val := stbtt.ScaleForPixelHeight(&font.info, font.pixel_height)
			for r in text_str {
				g := graphics.get_glyph(font, r, font.pixel_height)
				text_w += f32(g.advance) * scale_val
			}

			cursor_x := x + text_w
			cursor_w: f32 = 2.0
			max_h := max(f32(0.0), node.rect.h - node.padding[0] - node.padding[2])
			cursor_h := min(font_size, max_h)
			cursor_y := node.rect.y + node.padding[0]

			twoD.draw_rect(batch, {cursor_x, cursor_y}, {cursor_w, cursor_h}, color, vp)
		}
	}
}

// Interaction Systems
UI_INTERACTION_SYSTEMS_GROUP := []app.System_Dependency {
	rawptr(ui_button_interaction_system),
	rawptr(ui_slider_interaction_system),
	rawptr(ui_checkbox_interaction_system),
	rawptr(ui_toggle_interaction_system),
	rawptr(ui_radio_button_interaction_system),
	rawptr(ui_text_input_interaction_system),
}

@(tag = "system")
ui_button_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_inp: input.Input(input.GamepadButton),
	config: params.Res(UI_Input_Config) = {},
) {
	for arch in ecs.query(world, UI_Node, Button) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		buttons := ecs.arch_get_field(arch, Button)
		entities := ecs.arch_get_entities(arch)

		click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
		submit_btn := config.ptr != nil ? config.ptr.gamepad_submit : input.GamepadButton.South

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			btn := &buttons[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			is_down :=
				input.is_down(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_down(gp_inp, submit_btn))
			is_pressed :=
				input.is_pressed(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_pressed(gp_inp, submit_btn))

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			btn.is_hovered = in_bounds
			btn.is_clicked = false

			if in_bounds {
				if is_pressed {
					btn.is_pressed = true
				}
				if btn.is_pressed {
					if !is_down {
						btn.is_pressed = false
						btn.is_clicked = true
					}
				}
			} else {
				btn.is_pressed = false
			}
		}
	}
}

@(tag = "system")
ui_slider_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_inp: input.Input(input.GamepadButton),
	config: params.Res(UI_Input_Config) = {},
) {
	for arch in ecs.query(world, UI_Node, Slider) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		sliders := ecs.arch_get_field(arch, Slider)
		entities := ecs.arch_get_entities(arch)

		click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
		submit_btn := config.ptr != nil ? config.ptr.gamepad_submit : input.GamepadButton.South

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			slider := &sliders[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			is_down :=
				input.is_down(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_down(gp_inp, submit_btn))
			is_pressed :=
				input.is_pressed(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_pressed(gp_inp, submit_btn))

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			slider.is_hovered = in_bounds
			if is_pressed && in_bounds {
				slider.is_pressed = true
			}
			if slider.is_pressed {
				if is_down {
					local_x := mpos.x - node.rect.x
					slider.value = clamp(local_x / node.rect.w, 0.0, 1.0)
					ui_mark_dirty(world, entity)
				} else {
					slider.is_pressed = false
				}
			}
		}
	}
}

@(tag = "system")
ui_checkbox_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_inp: input.Input(input.GamepadButton),
	config: params.Res(UI_Input_Config) = {},
) {
	for arch in ecs.query(world, UI_Node, Checkbox) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		checkboxes := ecs.arch_get_field(arch, Checkbox)
		entities := ecs.arch_get_entities(arch)

		click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
		submit_btn := config.ptr != nil ? config.ptr.gamepad_submit : input.GamepadButton.South

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			checkbox := &checkboxes[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			is_down :=
				input.is_down(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_down(gp_inp, submit_btn))
			is_pressed :=
				input.is_pressed(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_pressed(gp_inp, submit_btn))

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			checkbox.is_hovered = in_bounds
			if in_bounds {
				if is_pressed {
					checkbox.is_pressed = true
				}
				if checkbox.is_pressed {
					if !is_down {
						checkbox.is_pressed = false
						checkbox.checked = !checkbox.checked
						ui_mark_dirty(world, entity)
					}
				}
			} else {
				checkbox.is_pressed = false
			}
		}
	}
}

@(tag = "system")
ui_toggle_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_inp: input.Input(input.GamepadButton),
	config: params.Res(UI_Input_Config) = {},
) {
	for arch in ecs.query(world, UI_Node, Toggle) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		toggles := ecs.arch_get_field(arch, Toggle)
		entities := ecs.arch_get_entities(arch)

		click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
		submit_btn := config.ptr != nil ? config.ptr.gamepad_submit : input.GamepadButton.South

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			toggle := &toggles[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			is_down :=
				input.is_down(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_down(gp_inp, submit_btn))
			is_pressed :=
				input.is_pressed(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_pressed(gp_inp, submit_btn))

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			toggle.is_hovered = in_bounds
			if in_bounds {
				if is_pressed {
					toggle.is_pressed = true
				}
				if toggle.is_pressed {
					if !is_down {
						toggle.is_pressed = false
						toggle.checked = !toggle.checked
						ui_mark_dirty(world, entity)
					}
				}
			} else {
				toggle.is_pressed = false
			}
		}
	}
}

@(tag = "system")
ui_radio_button_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	gp_inp: input.Input(input.GamepadButton),
	config: params.Res(UI_Input_Config) = {},
) {
	for arch in ecs.query(world, UI_Node, RadioButton) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		radio_buttons := ecs.arch_get_field(arch, RadioButton)
		entities := ecs.arch_get_entities(arch)

		click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
		submit_btn := config.ptr != nil ? config.ptr.gamepad_submit : input.GamepadButton.South

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			radio_button := &radio_buttons[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			is_down :=
				input.is_down(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_down(gp_inp, submit_btn))
			is_pressed :=
				input.is_pressed(mouse_inp, click_btn) ||
				(gp_inp.state != nil && input.is_pressed(gp_inp, submit_btn))

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			radio_button.is_hovered = in_bounds
			if in_bounds {
				if is_pressed {
					radio_button.is_pressed = true
				}
				if radio_button.is_pressed {
					if !is_down {
						radio_button.is_pressed = false
						if !radio_button.checked {
							radio_button.checked = true
							ui_mark_dirty(world, entity)
						}
					}
				}
			} else {
				radio_button.is_pressed = false
			}
		}
	}
}

@(tag = "system")
ui_text_input_interaction_system :: proc(
	world: ^ecs.World,
	mouse_inp: input.Input(input.MouseButtonCode),
	key_inp: input.Input(input.KeyCode),
	gp_inp: input.Input(input.GamepadButton),
	window_res: params.Res(windowing.Window_Context),
	dt: params.Res(app.DeltaTime),
	config: params.Res(UI_Input_Config) = {},
) {
	if window_res.ptr == nil || window_res.ptr.window == nil do return

	click_btn := config.ptr != nil ? config.ptr.mouse_click : input.MouseButtonCode.Left
	is_pressed := input.is_pressed(mouse_inp, click_btn)
	is_down := input.is_down(mouse_inp, click_btn)

	focused_entity: ecs.Entity = {}
	any_clicked_in_bounds := false

	// First pass: check which text input was clicked in-bounds
	for arch in ecs.query(world, UI_Node, TextInput) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		text_inputs := ecs.arch_get_field(arch, TextInput)
		entities := ecs.arch_get_entities(arch)

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			text_input := &text_inputs[i]
			entity := entities[i]

			root_canvas := ui_get_root_canvas(world, entity)
			mpos := input.mouse_position(mouse_inp, root_canvas)

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			text_input.is_hovered = in_bounds

			if in_bounds {
				if is_pressed {
					text_input.is_pressed = true
				}
				if text_input.is_pressed && !is_down {
					text_input.is_pressed = false
					focused_entity = entity
					any_clicked_in_bounds = true
				}
			} else {
				text_input.is_pressed = false
			}
		}
	}

	// Second pass: apply focus, process input, and manage dirty states
	any_focused := false
	for arch in ecs.query(world, UI_Node, TextInput) {
		text_inputs := ecs.arch_get_field(arch, TextInput)
		entities := ecs.arch_get_entities(arch)

		for i in 0 ..< len(text_inputs) {
			text_input := &text_inputs[i]
			entity := entities[i]

			was_focused := text_input.is_focused

			if any_clicked_in_bounds {
				text_input.is_focused = (entity == focused_entity)
			} else if is_pressed {
				// Clicked completely outside any text input bounds, unfocus
				text_input.is_focused = false
			}

			if text_input.is_focused {
				any_focused = true

				// 1. Process frame's typed text from input buffer
				if mouse_inp.state != nil && len(mouse_inp.state.text_input_buffer) > 0 {
					for char in mouse_inp.state.text_input_buffer {
						// Check allowed_chars filter
						if len(text_input.allowed_chars) > 0 {
							found := false
							for c in text_input.allowed_chars {
								if u8(c) == char {
									found = true
									break
								}
							}
							if !found do continue
						}

						// Check unwanted_chars filter
						if len(text_input.unwanted_chars) > 0 {
							found := false
							for c in text_input.unwanted_chars {
								if u8(c) == char {
									found = true
									break
								}
							}
							if found do continue
						}

						// Check max_length filter
						if text_input.max_length > 0 &&
						   len(text_input.text) >= text_input.max_length {
							continue
						}

						// Check regex_pattern filter
						if len(text_input.restrict_regex_pattern) > 0 {
							candidate := make([dynamic]u8, context.temp_allocator)
							append(&candidate, ..text_input.text[:])
							append(&candidate, char)
							candidate_str := string(candidate[:])

							re, err := regex.create(
								text_input.restrict_regex_pattern,
								{},
								context.temp_allocator,
								context.temp_allocator,
							)
							if err == nil {
								_, success := regex.match(
									re,
									candidate_str,
									context.temp_allocator,
									context.temp_allocator,
								)
								if !success do continue
							}
						}

						append(&text_input.text, char)
						text_input.is_pressed = false // clear pressed state on typing
						ui_mark_dirty(world, entity)
					}
				}

				// 2. Process Backspace or Gamepad B (East) with hold-repeat using DeltaTime
				is_backspace_down := input.is_down(key_inp, input.KeyCode.Backspace)
				is_gamepad_b_down := gp_inp.state != nil && input.is_down(gp_inp, input.GamepadButton.East)
				is_delete_down := is_backspace_down || is_gamepad_b_down

				if is_delete_down {
					dt_val := dt.ptr != nil ? dt.ptr.f32_seconds : f32(0.016)

					if !text_input.backspace_held {
						text_input.backspace_held = true
						text_input.backspace_repeat_timer = 0.0

						// Pop first character immediately
						if len(text_input.text) > 0 {
							pop(&text_input.text)
							ui_mark_dirty(world, entity)
						}
					} else {
						text_input.backspace_repeat_timer += dt_val

						// If we are in the repeating phase (>= 0.4s)
						if text_input.backspace_repeat_timer >= 0.4 {
							if len(text_input.text) > 0 {
								pop(&text_input.text)
								ui_mark_dirty(world, entity)
							}
							text_input.backspace_repeat_timer -= 0.05
						}
					}
				} else {
					text_input.backspace_held = false
					text_input.backspace_repeat_timer = 0.0
				}

				// 3. Process Enter/Escape to unfocus
				if input.is_pressed(key_inp, input.KeyCode.Enter) ||
				   input.is_pressed(key_inp, input.KeyCode.Escape) {
					text_input.is_focused = false
					ui_mark_dirty(world, entity)
				}
			}

			if was_focused != text_input.is_focused {
				ui_mark_dirty(world, entity)
			}
		}
	}

	// Update SDL3 text input active status based on overall focus state
	sdl_active := sdl3.TextInputActive(window_res.ptr.window)
	if any_focused && !sdl_active {
		_ = sdl3.StartTextInput(window_res.ptr.window)
	} else if !any_focused && sdl_active {
		_ = sdl3.StopTextInput(window_res.ptr.window)
	}
}
