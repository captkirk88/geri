package input

import "../ecs/params"
import "core:math"
import "core:time"
import "vendor:sdl3"

sdl_to_keycode :: proc(key: sdl3.Keycode) -> KeyCode {
	switch key {
	case sdl3.K_A:
		return .A
	case sdl3.K_B:
		return .B
	case sdl3.K_C:
		return .C
	case sdl3.K_D:
		return .D
	case sdl3.K_E:
		return .E
	case sdl3.K_F:
		return .F
	case sdl3.K_G:
		return .G
	case sdl3.K_H:
		return .H
	case sdl3.K_I:
		return .I
	case sdl3.K_J:
		return .J
	case sdl3.K_K:
		return .K
	case sdl3.K_L:
		return .L
	case sdl3.K_M:
		return .M
	case sdl3.K_N:
		return .N
	case sdl3.K_O:
		return .O
	case sdl3.K_P:
		return .P
	case sdl3.K_Q:
		return .Q
	case sdl3.K_R:
		return .R
	case sdl3.K_S:
		return .S
	case sdl3.K_T:
		return .T
	case sdl3.K_U:
		return .U
	case sdl3.K_V:
		return .V
	case sdl3.K_W:
		return .W
	case sdl3.K_X:
		return .X
	case sdl3.K_Y:
		return .Y
	case sdl3.K_Z:
		return .Z
	case sdl3.K_0:
		return .Num0
	case sdl3.K_1:
		return .Num1
	case sdl3.K_2:
		return .Num2
	case sdl3.K_3:
		return .Num3
	case sdl3.K_4:
		return .Num4
	case sdl3.K_5:
		return .Num5
	case sdl3.K_6:
		return .Num6
	case sdl3.K_7:
		return .Num7
	case sdl3.K_8:
		return .Num8
	case sdl3.K_9:
		return .Num9
	case sdl3.K_F1:
		return .F1
	case sdl3.K_F2:
		return .F2
	case sdl3.K_F3:
		return .F3
	case sdl3.K_F4:
		return .F4
	case sdl3.K_F5:
		return .F5
	case sdl3.K_F6:
		return .F6
	case sdl3.K_F7:
		return .F7
	case sdl3.K_F8:
		return .F8
	case sdl3.K_F9:
		return .F9
	case sdl3.K_F10:
		return .F10
	case sdl3.K_F11:
		return .F11
	case sdl3.K_F12:
		return .F12
	case sdl3.K_LSHIFT:
		return .LeftShift
	case sdl3.K_RSHIFT:
		return .RightShift
	case sdl3.K_LCTRL:
		return .LeftCtrl
	case sdl3.K_RCTRL:
		return .RightCtrl
	case sdl3.K_LALT:
		return .LeftAlt
	case sdl3.K_RALT:
		return .RightAlt
	case sdl3.K_LGUI:
		return .LeftSuper
	case sdl3.K_RGUI:
		return .RightSuper
	case sdl3.K_CAPSLOCK:
		return .CapsLock
	case sdl3.K_NUMLOCKCLEAR:
		return .NumLock
	case sdl3.K_SCROLLLOCK:
		return .ScrollLock
	case sdl3.K_PRINTSCREEN:
		return .PrintScreen
	case sdl3.K_PAUSE:
		return .Pause
	case sdl3.K_INSERT:
		return .Insert
	case sdl3.K_HOME:
		return .Home
	case sdl3.K_END:
		return .End
	case sdl3.K_PAGEUP:
		return .PageUp
	case sdl3.K_PAGEDOWN:
		return .PageDown
	case sdl3.K_SPACE:
		return .Space
	case sdl3.K_RETURN:
		return .Enter
	case sdl3.K_ESCAPE:
		return .Escape
	case sdl3.K_BACKSPACE:
		return .Backspace
	case sdl3.K_TAB:
		return .Tab
	case sdl3.K_LEFT:
		return .Left
	case sdl3.K_RIGHT:
		return .Right
	case sdl3.K_UP:
		return .Up
	case sdl3.K_DOWN:
		return .Down
	}
	return .None
}

sdl_to_buttoncode :: proc(btn: u8) -> MouseButtonCode {
	switch btn {
	case 1:
		return .Left
	case 2:
		return .Middle
	case 3:
		return .Right
	}
	return .None
}

sdl_to_gamepad_button :: proc(btn: sdl3.GamepadButton) -> GamepadButton {
	#partial switch btn {
	case .SOUTH:
		return .South
	case .EAST:
		return .East
	case .WEST:
		return .West
	case .NORTH:
		return .North
	case .BACK:
		return .Back
	case .GUIDE:
		return .Guide
	case .START:
		return .Start
	case .LEFT_STICK:
		return .LeftStick
	case .RIGHT_STICK:
		return .RightStick
	case .LEFT_SHOULDER:
		return .LeftShoulder
	case .RIGHT_SHOULDER:
		return .RightShoulder
	case .DPAD_UP:
		return .DpadUp
	case .DPAD_DOWN:
		return .DpadDown
	case .DPAD_LEFT:
		return .DpadLeft
	case .DPAD_RIGHT:
		return .DpadRight
	}
	return .None
}

sdl_to_gamepad_axis :: proc(axis: sdl3.GamepadAxis) -> GamepadAxis {
	#partial switch axis {
	case .LEFTX:
		return .LeftX
	case .LEFTY:
		return .LeftY
	case .RIGHTX:
		return .RightX
	case .RIGHTY:
		return .RightY
	case .LEFT_TRIGGER:
		return .TriggerLeft
	case .RIGHT_TRIGGER:
		return .TriggerRight
	}
	return .None
}

input_update_system :: proc(
	events: params.EventReader(sdl3.Event),
	state_res: params.Res(Input_State),
) {
	state := state_res.ptr
	if state == nil do return

	// Reset transient states
	state.keys_pressed = {}
	state.keys_released = {}
	clear(&state.mouse_buttons_pressed)
	clear(&state.mouse_buttons_released)
	clear(&state.gestures_active)
	clear(&state.gamepad_buttons_pressed)
	clear(&state.gamepad_buttons_released)
	clear(&state.targets)
	state.mouse_wheel = {0, 0}
	state.mouse_delta = {0, 0}
	state.pan_delta = {0, 0}
	state.pinch_scale = 1.0

	mx, my: f32
	_ = sdl3.GetMouseState(&mx, &my)
	state.mouse_position = {mx, my}

	now := time.tick_now()

	for ev in events.events {
		#partial switch ev.type {
		case .KEY_DOWN:
			kc := sdl_to_keycode(ev.key.key)
			if kc != .None {
				if !(kc in state.keys_down) {
					state.keys_pressed += {kc}
				}
				state.keys_down += {kc}
			}
		case .KEY_UP:
			kc := sdl_to_keycode(ev.key.key)
			if kc != .None {
				state.keys_down -= {kc}
				state.keys_released += {kc}
			}
		case .MOUSE_MOTION:
			state.mouse_position = {ev.motion.x, ev.motion.y}
			state.mouse_delta = {ev.motion.xrel, ev.motion.yrel}
			if state.mouse_buttons_down[.Left] {
				state.is_dragging = true
				state.gestures_active[.Pan] = true
				state.pan_delta = {ev.motion.xrel, ev.motion.yrel}
			}
		case .MOUSE_BUTTON_DOWN:
			btn := sdl_to_buttoncode(ev.button.button)
			if btn != .None {
				state.mouse_position = {ev.button.x, ev.button.y}
				state.mouse_buttons_pressed[btn] = true
				state.mouse_buttons_down[btn] = true
				if btn == .Left {
					state.gesture_start_pos = {ev.button.x, ev.button.y}
					state.gesture_start_time = now
					state.is_dragging = false
				}
			}
		case .MOUSE_BUTTON_UP:
			btn := sdl_to_buttoncode(ev.button.button)
			if btn != .None {
				state.mouse_position = {ev.button.x, ev.button.y}
				state.mouse_buttons_down[btn] = false
				state.mouse_buttons_released[btn] = true

				if btn == .Left {
					end_pos := [2]f32{ev.button.x, ev.button.y}
					delta := end_pos - state.gesture_start_pos
					dist := math.sqrt(delta.x * delta.x + delta.y * delta.y)
					dur := time.duration_seconds(time.tick_since(state.gesture_start_time))

					if dist < 10.0 && dur < 0.25 {
						state.gestures_active[.Tap] = true
						tap_dur := time.duration_seconds(time.tick_since(state.last_tap_time))
						if tap_dur < 0.3 {
							state.gestures_active[.DoubleTap] = true
						}
						state.last_tap_time = now
					} else if dist > 50.0 && dur < 0.3 {
						if math.abs(delta.x) > math.abs(delta.y) {
							if delta.x > 0 do state.gestures_active[.SwipeRight] = true
							else do state.gestures_active[.SwipeLeft] = true
						} else {
							if delta.y > 0 do state.gestures_active[.SwipeDown] = true
							else do state.gestures_active[.SwipeUp] = true
						}
					}
					state.is_dragging = false
				}
			}
		case .MOUSE_WHEEL:
			state.mouse_wheel = {ev.wheel.x, ev.wheel.y}
			state.gestures_active[.Pinch] = true
			state.pinch_scale = 1.0 + ev.wheel.y * 0.1

		case .PINCH_BEGIN:
			state.gestures_active[.Pinch] = true
		case .PINCH_UPDATE:
			state.gestures_active[.Pinch] = true
			state.pinch_scale = ev.pinch.scale
		case .PINCH_END:

		// Gamepad handling
		case .GAMEPAD_ADDED:
			gp := sdl3.OpenGamepad(ev.gdevice.which)
			if gp != nil {
				state.gamepads[ev.gdevice.which] = gp
			}
		case .GAMEPAD_REMOVED:
			if gp, ok := state.gamepads[ev.gdevice.which]; ok {
				sdl3.CloseGamepad(gp)
				delete_key(&state.gamepads, ev.gdevice.which)
			}
		case .GAMEPAD_BUTTON_DOWN:
			btn := sdl_to_gamepad_button(sdl3.GamepadButton(ev.gbutton.button))
			if btn != .None {
				state.gamepad_buttons_pressed[btn] = true
				state.gamepad_buttons_down[btn] = true
			}
		case .GAMEPAD_BUTTON_UP:
			btn := sdl_to_gamepad_button(sdl3.GamepadButton(ev.gbutton.button))
			if btn != .None {
				state.gamepad_buttons_down[btn] = false
				state.gamepad_buttons_released[btn] = true
			}
		case .GAMEPAD_AXIS_MOTION:
			axis := sdl_to_gamepad_axis(sdl3.GamepadAxis(ev.gaxis.axis))
			if axis != .None {
				val := f32(ev.gaxis.value) / 32767.0
				val = clamp(val, -1.0, 1.0)

				deadzone := state.gamepad_deadzone
				if axis == .TriggerLeft || axis == .TriggerRight {
					deadzone = state.trigger_deadzone
				}

				if math.abs(val) < deadzone {
					val = 0.0
				} else {
					sign: f32 = val >= 0.0 ? 1.0 : -1.0
					val = sign * (math.abs(val) - deadzone) / (1.0 - deadzone)
				}
				state.gamepad_axes[axis] = val
			}
		}
	}
}
