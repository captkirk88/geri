package input

import "core:time"
import "vendor:sdl3"

KeyCode :: enum {
	None,
	A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,
	Space, Enter, Escape, Backspace, Tab,
	Left, Right, Up, Down,
}

ButtonCode :: enum {
	None,
	Left,
	Right,
	Middle,
}

Gesture :: enum {
	None,
	Tap,
	DoubleTap,
	Pan,
	SwipeLeft,
	SwipeRight,
	SwipeUp,
	SwipeDown,
	Pinch,
}

GamepadButton :: enum {
	None,
	South, // Xbox A, PlayStation Cross
	East,  // Xbox B, PlayStation Circle
	West,  // Xbox X, PlayStation Square
	North, // Xbox Y, PlayStation Triangle
	Back,
	Guide,
	Start,
	LeftStick,
	RightStick,
	LeftShoulder,
	RightShoulder,
	DpadUp,
	DpadDown,
	DpadLeft,
	DpadRight,
}

GamepadAxis :: enum {
	None,
	LeftX,
	LeftY,
	RightX,
	RightY,
	TriggerLeft,
	TriggerRight,
}

Input_State :: struct {
	keys_down:              map[KeyCode]bool,
	keys_pressed:           map[KeyCode]bool,
	keys_released:          map[KeyCode]bool,

	buttons_down:           map[ButtonCode]bool,
	buttons_pressed:        map[ButtonCode]bool,
	buttons_released:       map[ButtonCode]bool,

	gestures_active:        map[Gesture]bool,

	mouse_position:         [2]f32,
	mouse_wheel:            [2]f32,
	pinch_scale:            f32,

	// Gamepad State
	gamepads:                  map[sdl3.JoystickID]^sdl3.Gamepad,
	gamepad_buttons_down:      map[GamepadButton]bool,
	gamepad_buttons_pressed:   map[GamepadButton]bool,
	gamepad_buttons_released:  map[GamepadButton]bool,
	gamepad_axes:              map[GamepadAxis]f32,

	// Gamepad Settings
	gamepad_deadzone:          f32,
	trigger_deadzone:          f32,

	// Helper fields for gesture detection
	gesture_start_pos:  [2]f32,
	gesture_start_time: time.Tick,
	last_tap_time:      time.Tick,
	is_dragging:        bool,
}

Input :: struct($T: typeid) {
	state: ^Input_State,
}

is_down :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return inp.state.keys_down[code]
	} else when T == ButtonCode {
		return inp.state.buttons_down[code]
	} else when T == Gesture {
		return inp.state.gestures_active[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_down[code]
	}
	return false
}

is_pressed :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return inp.state.keys_pressed[code]
	} else when T == ButtonCode {
		return inp.state.buttons_pressed[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_pressed[code]
	}
	return false
}

is_released :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return inp.state.keys_released[code]
	} else when T == ButtonCode {
		return inp.state.buttons_released[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_released[code]
	}
	return false
}

mouse_position :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.mouse_position
}

mouse_wheel :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.mouse_wheel
}

pinch_scale :: proc(inp: Input($T)) -> f32 {
	if inp.state == nil do return 1.0
	return inp.state.pinch_scale
}

gamepad_axis :: proc(inp: Input(GamepadAxis), axis: GamepadAxis) -> f32 {
	if inp.state == nil do return 0.0
	return inp.state.gamepad_axes[axis]
}

input_state_init :: proc(state: ^Input_State, allocator := context.allocator) {
	state.keys_down = make(map[KeyCode]bool, 16, allocator)
	state.keys_pressed = make(map[KeyCode]bool, 16, allocator)
	state.keys_released = make(map[KeyCode]bool, 16, allocator)

	state.buttons_down = make(map[ButtonCode]bool, 8, allocator)
	state.buttons_pressed = make(map[ButtonCode]bool, 8, allocator)
	state.buttons_released = make(map[ButtonCode]bool, 8, allocator)

	state.gestures_active = make(map[Gesture]bool, 8, allocator)
	state.pinch_scale = 1.0

	// Gamepad maps
	state.gamepads = make(map[sdl3.JoystickID]^sdl3.Gamepad, 4, allocator)
	state.gamepad_buttons_down = make(map[GamepadButton]bool, 16, allocator)
	state.gamepad_buttons_pressed = make(map[GamepadButton]bool, 16, allocator)
	state.gamepad_buttons_released = make(map[GamepadButton]bool, 16, allocator)
	state.gamepad_axes = make(map[GamepadAxis]f32, 8, allocator)

	state.gamepad_deadzone = 0.15
	state.trigger_deadzone = 0.05
}

input_state_destroy :: proc(state: ^Input_State) {
	delete(state.keys_down)
	delete(state.keys_pressed)
	delete(state.keys_released)

	delete(state.buttons_down)
	delete(state.buttons_pressed)
	delete(state.buttons_released)

	delete(state.gestures_active)

	// Close open gamepad handles
	for _, gp in state.gamepads {
		if gp != nil {
			sdl3.CloseGamepad(gp)
		}
	}
	delete(state.gamepads)
	delete(state.gamepad_buttons_down)
	delete(state.gamepad_buttons_pressed)
	delete(state.gamepad_buttons_released)
	delete(state.gamepad_axes)
}
