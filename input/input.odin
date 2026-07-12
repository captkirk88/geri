package input

import ecs "../ecs"
import "core:time"
import "vendor:sdl3"

KeyCode :: enum {
	None,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Num0,
	Num1,
	Num2,
	Num3,
	Num4,
	Num5,
	Num6,
	Num7,
	Num8,
	Num9,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	LeftShift,
	RightShift,
	LeftCtrl,
	RightCtrl,
	LeftAlt,
	RightAlt,
	LeftSuper,
	RightSuper,
	CapsLock,
	NumLock,
	ScrollLock,
	PrintScreen,
	Pause,
	Insert,
	Home,
	End,
	PageUp,
	PageDown,
	Space,
	Enter,
	Escape,
	Backspace,
	Tab,
	Left,
	Right,
	Up,
	Down,
	NumPad0,
	NumPad1,
	NumPad2,
	NumPad3,
	NumPad4,
	NumPad5,
	NumPad6,
	NumPad7,
	NumPad8,
	NumPad9,
	NumPadAdd,
	NumPadSubtract,
	NumPadMultiply,
	NumPadDivide,
	NumPadEnter,
	NumPadDecimal,
}

KeyCodes :: bit_set[KeyCode;u128]

Shift :: KeyCodes{.LeftShift, .RightShift}
Ctrl :: KeyCodes{.LeftCtrl, .RightCtrl}
Alt :: KeyCodes{.LeftAlt, .RightAlt}
Super :: KeyCodes{.LeftSuper, .RightSuper}


MouseButtonCode :: enum {
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
	// Xbox A, PlayStation Cross, Switch B
	South,
	// Xbox B, PlayStation Circle, Switch A
	East,
	// Xbox X, PlayStation Square, Switch Y
	West,
	// Xbox Y, PlayStation Triangle, Switch X
	North,
	Back,
	// Xbox Guide, PlayStation PS Button, Switch Minus
	Guide,
	// Xbox Start, PlayStation Start, Switch Plus
	Start,
	// Xbox Left Stick, PlayStation Left Stick, Switch Left Stick Click
	LeftStick,
	// Xbox Right Stick, PlayStation Right Stick, Switch Right Stick Click
	RightStick,
	// Xbox Left Shoulder, PlayStation L1, Switch L
	LeftShoulder,
	// Xbox Right Shoulder, PlayStation R1, Switch R
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
	keys_down:                KeyCodes,
	keys_pressed:             KeyCodes,
	keys_released:            KeyCodes,
	mouse_buttons_down:       map[MouseButtonCode]bool,
	mouse_buttons_pressed:    map[MouseButtonCode]bool,
	mouse_buttons_released:   map[MouseButtonCode]bool,
	gestures_active:          map[Gesture]bool,
	mouse_position:           [2]f32,
	mouse_delta:              [2]f32,
	mouse_wheel:              [2]f32,
	pinch_scale:              f32,
	pan_delta:                [2]f32,

	// Gamepad State
	gamepads:                 map[sdl3.JoystickID]^sdl3.Gamepad,
	gamepad_buttons_down:     map[GamepadButton]bool,
	gamepad_buttons_pressed:  map[GamepadButton]bool,
	gamepad_buttons_released: map[GamepadButton]bool,
	gamepad_axes:             map[GamepadAxis]f32,

	// Gamepad Settings
	gamepad_deadzone:         f32,
	trigger_deadzone:         f32,

	// Helper fields for gesture detection
	gesture_start_pos:        [2]f32,
	gesture_start_time:       time.Tick,
	last_tap_time:            time.Tick,
	is_dragging:              bool,
	targets:                  map[ecs.Entity]Target_Input_State,
}

Target_Input_State :: struct {
	mouse_position: [2]f32,
}

Input :: struct($T: typeid) {
	state: ^Input_State,
}

is_down :: proc {
	is_down_generic,
	is_down_keys,
}

is_down_generic :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return code in inp.state.keys_down
	} else when T == MouseButtonCode {
		return inp.state.mouse_buttons_down[code]
	} else when T == Gesture {
		return inp.state.gestures_active[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_down[code]
	}
	return false
}

is_down_keys :: proc(inp: Input(KeyCode), codes: KeyCodes) -> bool {
	if inp.state == nil do return false
	return (inp.state.keys_down & codes) != {}
}

is_pressed :: proc {
	is_pressed_generic,
	is_pressed_keys,
}

is_pressed_generic :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return code in inp.state.keys_pressed
	} else when T == MouseButtonCode {
		return inp.state.mouse_buttons_pressed[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_pressed[code]
	}
	return false
}

is_pressed_keys :: proc(inp: Input(KeyCode), codes: KeyCodes) -> bool {
	if inp.state == nil do return false
	return (inp.state.keys_pressed & codes) != {}
}

is_released :: proc {
	is_released_generic,
	is_released_keys,
}

is_released_generic :: proc(inp: Input($T), code: T) -> bool {
	if inp.state == nil do return false
	when T == KeyCode {
		return code in inp.state.keys_released
	} else when T == MouseButtonCode {
		return inp.state.mouse_buttons_released[code]
	} else when T == GamepadButton {
		return inp.state.gamepad_buttons_released[code]
	}
	return false
}

is_released_keys :: proc(inp: Input(KeyCode), codes: KeyCodes) -> bool {
	if inp.state == nil do return false
	return (inp.state.keys_released & codes) != {}
}

mouse_position :: proc {
	mouse_position_global,
	mouse_position_target,
}

// Get the global mouse position
mouse_position_global :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.mouse_position
}

// Get the mouse position for a specific target entity
mouse_position_target :: proc(inp: Input($T), target: ecs.Entity) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	if target_state, ok := inp.state.targets[target]; ok {
		return target_state.mouse_position
	}
	return inp.state.mouse_position
}

// Set the mouse position for a specific target entity
set_target_mouse_position :: proc(inp: Input($T), target: ecs.Entity, pos: [2]f32) {
	if inp.state == nil do return
	inp.state.targets[target] = {
		mouse_position = pos,
	}
}

get_swipe_direction :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.pan_delta
}

mouse_wheel :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.mouse_wheel
}

pinch_scale :: proc(inp: Input($T)) -> f32 {
	if inp.state == nil do return 1.0
	return inp.state.pinch_scale
}

// Get the mouse delta (change in position) since the last frame
mouse_delta :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.mouse_delta
}

// Get the pan delta (change in position) since the last frame
pan_delta :: proc(inp: Input($T)) -> [2]f32 {
	if inp.state == nil do return {0, 0}
	return inp.state.pan_delta
}

is_tap :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.Tap]
}

is_double_tap :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.DoubleTap]
}

is_pan :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.Pan]
}

is_swipe_left :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.SwipeLeft]
}

is_swipe_right :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.SwipeRight]
}

is_swipe_up :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.SwipeUp]
}

is_swipe_down :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.SwipeDown]
}

is_pinch :: proc(inp: Input($T)) -> bool {
	if inp.state == nil do return false
	return inp.state.gestures_active[Gesture.Pinch]
}

gamepad_axis :: proc(inp: Input(GamepadAxis), axis: GamepadAxis) -> f32 {
	if inp.state == nil do return 0.0
	return inp.state.gamepad_axes[axis]
}

input_state_init :: proc(state: ^Input_State, allocator := context.allocator) {

	state.mouse_buttons_down = make(map[MouseButtonCode]bool, 8, allocator)
	state.mouse_buttons_pressed = make(map[MouseButtonCode]bool, 8, allocator)
	state.mouse_buttons_released = make(map[MouseButtonCode]bool, 8, allocator)

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

	state.targets = make(map[ecs.Entity]Target_Input_State, 8, allocator)
}

input_state_destroy :: proc(state: ^Input_State) {

	delete(state.mouse_buttons_down)
	delete(state.mouse_buttons_pressed)
	delete(state.mouse_buttons_released)

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

	delete(state.targets)
}

Coordinate_System :: enum {
	// standard OpenGL/WGPU NDC: X=[-1, 1] right, Y=[-1, 1] up
	NDC_Y_Up,
	// standard Vulkan: X=[-1, 1] right, Y=[-1, 1] down
	NDC_Y_Down,
}

// Convert screen coordinates to NDC (Normalized Device Coordinate) coordinates
screen_to_ndc :: proc "contextless" (
	screen_pos: [2]f32,
	window_size: [2]f32,
	system: Coordinate_System = .NDC_Y_Up,
) -> [2]f32 {
	x := (screen_pos.x / window_size.x) * 2.0 - 1.0
	y := (screen_pos.y / window_size.y) * 2.0 - 1.0
	if system == .NDC_Y_Up {
		y = -y
	}
	return {x, y}
}
