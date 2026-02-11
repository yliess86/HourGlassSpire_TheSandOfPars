package game

import engine "../engine"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

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
	RELOAD,
	QUIT,
}

INPUT_DEFAULT_BINDINGS :: [Input_Action]engine.Input_Binding {
	.MOVE_UP = {keyboard = .W, gamepad_button = .DPAD_UP},
	.MOVE_DOWN = {keyboard = .S, gamepad_button = .DPAD_DOWN},
	.MOVE_LEFT = {keyboard = .A, gamepad_button = .DPAD_LEFT},
	.MOVE_RIGHT = {keyboard = .D, gamepad_button = .DPAD_RIGHT},
	.JUMP = {keyboard = .SPACE, gamepad_button = .SOUTH},
	.DASH = {keyboard = .L, gamepad_button = .NORTH},
	.WALL_RUN = {keyboard = .LSHIFT, gamepad_button = .RIGHT_SHOULDER},
	.SLIDE = {keyboard = .LCTRL, gamepad_button = .LEFT_SHOULDER},
	.DEBUG = {keyboard = .F3, gamepad_button = .BACK},
	.RELOAD = {keyboard = .F5, gamepad_button = .INVALID},
	.QUIT = {keyboard = .ESCAPE, gamepad_button = .START},
}

input_binding_apply :: proc(input: ^engine.Input(Input_Action)) {
	input.deadzone = INPUT_AXIS_DEADZONE
	input.axis_map = {
		pos_x     = .MOVE_RIGHT,
		neg_x     = .MOVE_LEFT,
		pos_y     = .MOVE_UP,
		neg_y     = .MOVE_DOWN,
		gamepad_x = .LEFTX,
		gamepad_y = .LEFTY,
	}
	input.bindings = INPUT_DEFAULT_BINDINGS

	action_names := [Input_Action]string {
		.MOVE_UP    = "MOVE_UP",
		.MOVE_DOWN  = "MOVE_DOWN",
		.MOVE_LEFT  = "MOVE_LEFT",
		.MOVE_RIGHT = "MOVE_RIGHT",
		.JUMP       = "JUMP",
		.DASH       = "DASH",
		.WALL_RUN   = "WALL_RUN",
		.SLIDE      = "SLIDE",
		.DEBUG      = "DEBUG",
		.RELOAD     = "RELOAD",
		.QUIT       = "QUIT",
	}

	for action in Input_Action {
		name := action_names[action]

		// Keyboard binding override from config
		kb_key := fmt.tprintf("INPUT_KB_%s", name)
		if kb_name, ok := engine.config_get_string(&game_config, kb_key); ok {
			scancode := sdl.GetScancodeFromName(
				strings.clone_to_cstring(kb_name, context.temp_allocator),
			)
			if scancode != sdl.Scancode(0) do input.bindings[action].keyboard = scancode
			else do fmt.eprintf("[input] Invalid keyboard binding for %s: \"%s\"\n", name, kb_name)
		}

		// Gamepad binding override from config
		gp_key := fmt.tprintf("INPUT_GP_%s", name)
		if gp_name, ok := engine.config_get_string(&game_config, gp_key); ok {
			button := sdl.GetGamepadButtonFromString(
				strings.clone_to_cstring(gp_name, context.temp_allocator),
			)
			if button != .INVALID do input.bindings[action].gamepad_button = button
			else do fmt.eprintf("[input] Invalid gamepad binding for %s: \"%s\"\n", name, gp_name)
		}
	}
}
