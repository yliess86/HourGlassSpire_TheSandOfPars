package game

import "core:fmt"
import sdl "vendor:sdl3"

// Controller family for button label lookup
Debug_Controls_Family :: enum u8 {
	Keyboard,
	Xbox,
	PlayStation,
	Switch,
	Generic,
}

// Gamepad button display names per family
Debug_Controls_Button_Names :: struct {
	south, north, right_shoulder, left_shoulder, back: cstring,
}

DEBUG_CONTROLS_NAMES :: [Debug_Controls_Family]Debug_Controls_Button_Names {
	.Keyboard    = {},
	.Xbox        = {"A", "Y", "RB", "LB", "Back"},
	.PlayStation = {"Cross", "Triangle", "R1", "L1", "Share"},
	.Switch      = {"B", "X", "R", "L", "−"},
	.Generic     = {"A", "Y", "RB", "LB", "Back"},
}

DEBUG_CONTROLS_FAMILY_LABELS :: [Debug_Controls_Family]cstring {
	.Keyboard    = "Keyboard",
	.Xbox        = "Xbox",
	.PlayStation = "PlayStation",
	.Switch      = "Switch",
	.Generic     = "Gamepad",
}

debug_controls_family :: proc() -> Debug_Controls_Family {
	if game.input.type == .KEYBOARD || game.input.gamepad == nil do return .Keyboard
	#partial switch sdl.GetGamepadType(game.input.gamepad) {
	case .PS3, .PS4, .PS5:
		return .PlayStation
	case .XBOX360, .XBOXONE:
		return .Xbox
	case .NINTENDO_SWITCH_PRO,
	     .NINTENDO_SWITCH_JOYCON_LEFT,
	     .NINTENDO_SWITCH_JOYCON_RIGHT,
	     .NINTENDO_SWITCH_JOYCON_PAIR:
		return .Switch
	case:
		return .Generic
	}
}

@(private = "file")
debug_controls_text_right :: proc(x, y: f32, text: cstring, color: [4]u8 = DEBUG_COLOR_STATE) {
	text_w := debug_text_width(text)
	debug_text(x - text_w, y, text, color)
}

@(private = "file")
debug_controls_key_name :: proc(action: Input_Action) -> cstring {
	return sdl.GetScancodeName(game.input.bindings[action].keyboard)
}

@(private = "file")
debug_controls_move_label :: proc() -> cstring {
	u := debug_controls_key_name(.MOVE_UP)
	d := debug_controls_key_name(.MOVE_DOWN)
	l := debug_controls_key_name(.MOVE_LEFT)
	r := debug_controls_key_name(.MOVE_RIGHT)
	// If all single-char, compact as "WASD"
	if len(u) == 1 && len(d) == 1 && len(l) == 1 && len(r) == 1 {
		return fmt.ctprintf("%s%s%s%s", u, l, d, r)
	}
	return fmt.ctprintf("%s/%s/%s/%s", u, l, d, r)
}

debug_controls_render :: proc() {
	family := debug_controls_family()
	is_keyboard := family == .Keyboard

	right_x := f32(game.win.logical_w) - DEBUG_TEXT_MARGIN_X
	y := DEBUG_TEXT_MARGIN_Y

	// Title — controller family name
	family_labels := DEBUG_CONTROLS_FAMILY_LABELS
	debug_controls_text_right(right_x, y, family_labels[family], DEBUG_COLOR_STATE)
	y += DEBUG_TEXT_LINE_H * DEBUG_TEXT_TITLE_GAP

	// Action rows: label (muted) + key/button (bright), right-aligned
	Row :: struct {
		label: cstring,
		key:   cstring,
	}

	button_names := DEBUG_CONTROLS_NAMES
	names := button_names[family]
	rows: [5]Row
	if is_keyboard {
		rows = {
			{"Move", debug_controls_move_label()},
			{"Jump", debug_controls_key_name(.JUMP)},
			{"Dash", debug_controls_key_name(.DASH)},
			{"Wall Run", debug_controls_key_name(.WALL_RUN)},
			{"Slide", debug_controls_key_name(.SLIDE)},
		}
	} else {
		rows = {
			{"Move", "D-Pad / Stick"},
			{"Jump", names.south},
			{"Dash", names.north},
			{"Wall Run", names.right_shoulder},
			{"Slide", names.left_shoulder},
		}
	}

	max_label_w: f32
	max_key_w: f32
	for row in rows {
		max_label_w = max(max_label_w, debug_text_width(row.label))
		max_key_w = max(max_key_w, debug_text_width(row.key))
	}
	gap := debug_text_width("  ")
	label_x := right_x - max_label_w - gap - max_key_w
	key_x := right_x - max_key_w
	for row in rows {
		debug_text(label_x, y, row.label, DEBUG_COLOR_STATE_MUTED)
		debug_text(key_x, y, row.key, DEBUG_COLOR_STATE)
		y += DEBUG_TEXT_LINE_H
	}
}
