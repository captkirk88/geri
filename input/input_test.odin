package input

import "../ecs"
import params "../ecs/params"
import "base:runtime"
import "core:testing"
import "vendor:sdl3"

@(test)
test_input_state_injection :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)

	state: Input_State
	input_state_init(&state)
	ecs.world_add_resource(&w, state, proc(s: ^Input_State, alloc: runtime.Allocator) {
		input_state_destroy(s)
	})

	// Register custom system parameter builder for Input(T)
	ecs.world_register_param_builder(&w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime_type_info_base(info)
			s, ok := base.variant.(runtime.Type_Info_Struct)
			if !ok do return false
			if s.field_count != 1 || s.names[0] != "state" do return false
			ptr_info := runtime_type_info_base(s.types[0])
			ptr_struct, is_ptr := ptr_info.variant.(runtime.Type_Info_Pointer)
			if !is_ptr do return false
			return ptr_struct.elem.id == typeid_of(Input_State)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			state_res := ecs.world_get_resource(w, Input_State)
			if state_res != nil {
				base := runtime_type_info_base(info)
				s := base.variant.(runtime.Type_Info_Struct)
				dest := (^rawptr)(uintptr(ptr) + s.offsets[0])
				dest^ = state_res
			}
		},
		after_run = nil,
		destroy = nil,
	})

	// Test parameter matching
	info := type_info_of(Input(KeyCode))
	base := runtime_type_info_base(info)
	s, ok := base.variant.(runtime.Type_Info_Struct)
	testing.expect(t, ok)
	testing.expect_value(t, s.field_count, 1)
	testing.expect_value(t, s.names[0], "state")

	ptr_info := runtime_type_info_base(s.types[0])
	ptr_struct, is_ptr := ptr_info.variant.(runtime.Type_Info_Pointer)
	testing.expect(t, is_ptr)
	testing.expect(t, ptr_struct.elem.id == typeid_of(Input_State))

	// Test Gamepad Button Injection
	gp_btn_info := type_info_of(Input(GamepadButton))
	gp_btn_base := runtime_type_info_base(gp_btn_info)
	gp_btn_s, gp_btn_ok := gp_btn_base.variant.(runtime.Type_Info_Struct)
	testing.expect(t, gp_btn_ok)
	testing.expect_value(t, gp_btn_s.field_count, 1)
	testing.expect_value(t, gp_btn_s.names[0], "state")

	// Test Gamepad Axis Injection
	gp_ax_info := type_info_of(Input(GamepadAxis))
	gp_ax_base := runtime_type_info_base(gp_ax_info)
	gp_ax_s, gp_ax_ok := gp_ax_base.variant.(runtime.Type_Info_Struct)
	testing.expect(t, gp_ax_ok)
	testing.expect_value(t, gp_ax_s.field_count, 1)
	testing.expect_value(t, gp_ax_s.names[0], "state")
}

@(test)
test_gamepad_api_correctness :: proc(t: ^testing.T) {
	state: Input_State
	input_state_init(&state)
	defer input_state_destroy(&state)

	btn_inp := Input(GamepadButton) {
		state = &state,
	}
	axis_inp := Input(GamepadAxis) {
		state = &state,
	}

	// Test default values
	testing.expect_value(t, is_down(btn_inp, GamepadButton.South), false)
	testing.expect_value(t, is_pressed(btn_inp, GamepadButton.South), false)
	testing.expect_value(t, is_released(btn_inp, GamepadButton.South), false)
	testing.expect_value(t, gamepad_axis(axis_inp, GamepadAxis.LeftX), f32(0.0))

	// Set button down and pressed
	state.gamepad_buttons_down[GamepadButton.South] = true
	state.gamepad_buttons_pressed[GamepadButton.South] = true
	testing.expect_value(t, is_down(btn_inp, GamepadButton.South), true)
	testing.expect_value(t, is_pressed(btn_inp, GamepadButton.South), true)

	// Set button released
	state.gamepad_buttons_down[GamepadButton.South] = false
	state.gamepad_buttons_released[GamepadButton.South] = true
	testing.expect_value(t, is_down(btn_inp, GamepadButton.South), false)
	testing.expect_value(t, is_released(btn_inp, GamepadButton.South), true)

	// Set axis values
	state.gamepad_axes[GamepadAxis.LeftX] = -0.75
	state.gamepad_axes[GamepadAxis.TriggerRight] = 1.0
	testing.expect_value(t, gamepad_axis(axis_inp, GamepadAxis.LeftX), f32(-0.75))
	testing.expect_value(t, gamepad_axis(axis_inp, GamepadAxis.TriggerRight), f32(1.0))
}

@(test)
test_gamepad_deadzones :: proc(t: ^testing.T) {
	state: Input_State
	input_state_init(&state)
	defer input_state_destroy(&state)

	axis_inp := Input(GamepadAxis) {
		state = &state,
	}

	// Mock SDL3 events
	ev1: sdl3.Event
	ev1.type = .GAMEPAD_AXIS_MOTION
	ev1.gaxis.axis = u8(sdl3.GamepadAxis.LEFTX)
	ev1.gaxis.value = 3276 // ~0.1 (below stick deadzone of 0.15)

	ev2: sdl3.Event
	ev2.type = .GAMEPAD_AXIS_MOTION
	ev2.gaxis.axis = u8(sdl3.GamepadAxis.LEFTY)
	ev2.gaxis.value = 6553 // ~0.2 (above stick deadzone of 0.15)

	ev3: sdl3.Event
	ev3.type = .GAMEPAD_AXIS_MOTION
	ev3.gaxis.axis = u8(sdl3.GamepadAxis.LEFT_TRIGGER)
	ev3.gaxis.value = 1310 // ~0.04 (below trigger deadzone of 0.05)

	ev4: sdl3.Event
	ev4.type = .GAMEPAD_AXIS_MOTION
	ev4.gaxis.axis = u8(sdl3.GamepadAxis.RIGHT_TRIGGER)
	ev4.gaxis.value = 3276 // ~0.1 (above trigger deadzone of 0.05)

	reader := params.EventReader(sdl3.Event) {
		events = []sdl3.Event{ev1, ev2, ev3, ev4},
	}
	state_res := params.Res(Input_State) {
		ptr = &state,
	}

	input_update_system(reader, state_res)

	// Assertions
	testing.expect_value(t, gamepad_axis(axis_inp, .LeftX), f32(0.0))

	raw_y := f32(6553) / 32767.0
	expected_y := (raw_y - 0.15) / (1.0 - 0.15)
	testing.expect_value(t, gamepad_axis(axis_inp, .LeftY), expected_y)

	testing.expect_value(t, gamepad_axis(axis_inp, .TriggerLeft), f32(0.0))

	raw_tr := f32(3276) / 32767.0
	expected_tr := (raw_tr - 0.05) / (1.0 - 0.05)
	testing.expect_value(t, gamepad_axis(axis_inp, .TriggerRight), expected_tr)
}
