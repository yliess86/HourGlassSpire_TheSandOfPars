package engine

import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"

Input_Type :: enum u8 {
	KEYBOARD,
	GAMEPAD,
}

Input_Binding :: struct {
	keyboard:       sdl.Scancode,
	gamepad_button: sdl.GamepadButton,
}

Input_Axis_Map :: struct($Action: typeid) {
	pos_x, neg_x: Action,
	pos_y, neg_y: Action,
	gamepad_x:    sdl.GamepadAxis,
	gamepad_y:    sdl.GamepadAxis,
}

Input :: struct($Action: typeid) {
	type:       Input_Type,
	gamepad:    ^sdl.Gamepad,
	was_down:   [Action]bool,
	is_down:    [Action]bool,
	is_pressed: [Action]bool,
	axis:       [2]f32,
	bindings:   [Action]Input_Binding,
	axis_map:   Input_Axis_Map(Action),
	deadzone:   f32,
}

input_init :: proc(input: ^Input($Action), deadzone: f32 = 0.1) {
	input^ = {}
	input.deadzone = deadzone
}

input_pre_update :: proc(input: ^Input($Action)) {
	input.was_down = input.is_down
}

input_post_update :: proc(input: ^Input($Action)) {
	for action in Action do input.is_pressed[action] = input.is_down[action] && !input.was_down[action]
}

input_update :: proc(input: ^Input($Action), event: ^sdl.Event) {
	input_update_keyboard(input, event)
	input_update_gamepad(input, event)
}

input_update_keyboard :: proc(input: ^Input($Action), event: ^sdl.Event) {
	#partial switch event.type {
	case .KEY_DOWN:
		input.type = .KEYBOARD
		for binding, action in input.bindings {
			if event.key.scancode == binding.keyboard do input.is_down[action] = true
		}
	case .KEY_UP:
		for binding, action in input.bindings {
			if event.key.scancode == binding.keyboard do input.is_down[action] = false
		}
	}

	if input.type == .KEYBOARD {
		x := int(input.is_down[input.axis_map.pos_x]) - int(input.is_down[input.axis_map.neg_x])
		y := int(input.is_down[input.axis_map.pos_y]) - int(input.is_down[input.axis_map.neg_y])
		input.axis = {f32(x), f32(y)}
		input.axis = linalg.normalize0(input.axis)
	}
}

input_update_gamepad :: proc(input: ^Input($Action), event: ^sdl.Event) {
	#partial switch event.type {
	case .GAMEPAD_ADDED:
		if input.gamepad == nil {
			input.gamepad = sdl.OpenGamepad(event.gdevice.which)
		}
	case .GAMEPAD_REMOVED:
		if input.gamepad != nil && event.gdevice.which == sdl.GetGamepadID(input.gamepad) {
			sdl.CloseGamepad(input.gamepad)
			input.gamepad = nil
		}
	case .GAMEPAD_BUTTON_DOWN:
		input.type = .GAMEPAD
		for binding, action in input.bindings {
			if event.gbutton.button == u8(binding.gamepad_button) do input.is_down[action] = true
		}
	case .GAMEPAD_BUTTON_UP:
		for binding, action in input.bindings {
			if event.gbutton.button == u8(binding.gamepad_button) {
				input.is_down[action] = false
				if action == input.axis_map.neg_x do input.axis.x = 0
				if action == input.axis_map.pos_x do input.axis.x = 0
				if action == input.axis_map.pos_y do input.axis.y = 0
				if action == input.axis_map.neg_y do input.axis.y = 0
			}
		}
	case .GAMEPAD_AXIS_MOTION:
		input.type = .GAMEPAD

		value := f32(event.gaxis.value) / 3_2767
		value_abs := math.abs(value)
		axis: f32 = value if value_abs > input.deadzone else 0
		axis = axis if value_abs < 1 - input.deadzone else math.sign(value)

		gaxis := sdl.GamepadAxis(event.gaxis.axis)
		if gaxis == input.axis_map.gamepad_x {
			input.axis.x = axis
		} else if gaxis == input.axis_map.gamepad_y {
			input.axis.y = -axis
		}
	}

	if input.type == .GAMEPAD {
		dpad_x := f32(int(input.is_down[input.axis_map.pos_x]) - int(input.is_down[input.axis_map.neg_x]))
		dpad_y := f32(int(input.is_down[input.axis_map.pos_y]) - int(input.is_down[input.axis_map.neg_y]))
		input.axis.x = input.axis.x * (1.0 - math.abs(dpad_x)) + dpad_x
		input.axis.y = input.axis.y * (1.0 - math.abs(dpad_y)) + dpad_y
		input.axis = linalg.normalize0(input.axis) if dpad_x != 0 || dpad_y != 0 else input.axis
	}
}
