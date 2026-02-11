package engine

import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"

Input_Type :: enum u8 {
	KEYBOARD,
	GAMEPAD,
}

Input_Action :: enum u8 {
	MOVE_UP,
	MOVE_DOWN,
	MOVE_LEFT,
	MOVE_RIGHT,
	JUMP,
	DASH,
	WALL_RUN,
	SLIDE,
	DEBUG,
	QUIT,
}

Input :: struct {
	type:       Input_Type,
	gamepad:    ^sdl.Gamepad,
	was_down:   [Input_Action]bool,
	is_down:    [Input_Action]bool,
	is_pressed: [Input_Action]bool,
	axis:       [2]f32,
}

INPUT_BINDING_KEYBOARD :: [Input_Action]sdl.Scancode {
	.MOVE_UP    = .W,
	.MOVE_DOWN  = .S,
	.MOVE_LEFT  = .A,
	.MOVE_RIGHT = .D,
	.JUMP       = .SPACE,
	.DASH       = .L,
	.WALL_RUN   = .LSHIFT,
	.SLIDE      = .LCTRL,
	.DEBUG      = .F3,
	.QUIT       = .ESCAPE,
}

INPUT_BINDING_GAMEPAD_BUTTON :: [Input_Action]sdl.GamepadButton {
	.MOVE_UP    = .DPAD_UP,
	.MOVE_DOWN  = .DPAD_DOWN,
	.MOVE_LEFT  = .DPAD_LEFT,
	.MOVE_RIGHT = .DPAD_RIGHT,
	.JUMP       = .SOUTH,
	.DASH       = .NORTH,
	.WALL_RUN   = .RIGHT_SHOULDER,
	.SLIDE      = .LEFT_SHOULDER,
	.DEBUG      = .BACK,
	.QUIT       = .START,
}

INPUT_BINDING_GAMEPAD_AXIS :: #partial [Input_Action]sdl.GamepadAxis {
	.MOVE_UP    = .LEFTY,
	.MOVE_DOWN  = .LEFTY,
	.MOVE_LEFT  = .LEFTX,
	.MOVE_RIGHT = .LEFTX,
}

INPUT_BINDING_GAMEPAD_AXIS_DEADZONE: f32 : 0.1

input_init :: proc(type: Input_Type = .KEYBOARD) -> (input: Input) {
	return Input{type = type}
}

input_pre_update :: proc(input: ^Input) {
	input.was_down = input.is_down
}

input_post_update :: proc(input: ^Input) {
	for action in Input_Action do input.is_pressed[action] = input.is_down[action] && !input.was_down[action]
}

input_update :: proc(input: ^Input, event: ^sdl.Event) {
	input_update_keyboard(input, event)
	input_update_gamepad(input, event)
}

input_update_keyboard :: proc(input: ^Input, event: ^sdl.Event) {
	#partial switch event.type {
	case .KEY_DOWN:
		input.type = .KEYBOARD
		for scancode, action in INPUT_BINDING_KEYBOARD {
			if event.key.scancode == scancode do input.is_down[action] = true
		}
	case .KEY_UP:
		for scancode, action in INPUT_BINDING_KEYBOARD {
			if event.key.scancode == scancode do input.is_down[action] = false
		}
	}

	if input.type == .KEYBOARD {
		x := int(input.is_down[.MOVE_RIGHT]) - int(input.is_down[.MOVE_LEFT])
		y := int(input.is_down[.MOVE_UP]) - int(input.is_down[.MOVE_DOWN])
		input.axis = {f32(x), f32(y)}
		input.axis = linalg.normalize0(input.axis)
	}
}

input_update_gamepad :: proc(input: ^Input, event: ^sdl.Event) {
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
		for button, action in INPUT_BINDING_GAMEPAD_BUTTON {
			if event.gbutton.button == u8(button) do input.is_down[action] = true
		}
	case .GAMEPAD_BUTTON_UP:
		for button, action in INPUT_BINDING_GAMEPAD_BUTTON {
			if event.gbutton.button == u8(button) {
				input.is_down[action] = false
				if action == .MOVE_LEFT do input.axis.x = 0
				if action == .MOVE_RIGHT do input.axis.x = 0
				if action == .MOVE_UP do input.axis.y = 0
				if action == .MOVE_DOWN do input.axis.y = 0
			}
		}
	case .GAMEPAD_AXIS_MOTION:
		input.type = .GAMEPAD

		value := f32(event.gaxis.value) / 3_2767
		value_abs := math.abs(value)
		axis: f32 = value if value_abs > INPUT_BINDING_GAMEPAD_AXIS_DEADZONE else 0
		axis = axis if value_abs < 1 - INPUT_BINDING_GAMEPAD_AXIS_DEADZONE else math.sign(value)

		#partial switch sdl.GamepadAxis(event.gaxis.axis) {
		case .LEFTX:
			input.axis.x = axis
		case .LEFTY:
			input.axis.y = -axis
		}
	}

	if input.type == .GAMEPAD {
		dpad_x := f32(int(input.is_down[.MOVE_RIGHT]) - int(input.is_down[.MOVE_LEFT]))
		dpad_y := f32(int(input.is_down[.MOVE_UP]) - int(input.is_down[.MOVE_DOWN]))
		input.axis.x = input.axis.x * (1.0 - math.abs(dpad_x)) + dpad_x
		input.axis.y = input.axis.y * (1.0 - math.abs(dpad_y)) + dpad_y
		input.axis = linalg.normalize0(input.axis) if dpad_x != 0 || dpad_y != 0 else input.axis
	}
}
