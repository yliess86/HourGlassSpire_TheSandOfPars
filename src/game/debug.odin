package game

import engine "../engine"
import "core:fmt"
import sdl "vendor:sdl3"

Debug_State :: enum u8 {
	NONE,
	PLAYER,
	BACKGROUND,
	SAND,
	ALL,
	CONTROLS,
}

debug_set_color :: proc(color: [4]u8) {
	sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
}

debug_text_width :: proc(text: cstring) -> f32 {
	return f32(len(text)) * DEBUG_TEXT_CHAR_W
}

debug_text :: proc(x, y: f32, text: cstring, color: [4]u8 = DEBUG_COLOR_STATE) {
	debug_set_color(color)
	sdl.RenderDebugText(game.win.renderer, x, y, text)
}

debug_text_center :: proc(x, y: f32, text: cstring, color: [4]u8 = DEBUG_COLOR_STATE) {
	text_w := debug_text_width(text)
	debug_set_color(color)
	sdl.RenderDebugText(game.win.renderer, x - text_w / 2, y, text)
}

debug_value_with_label :: proc(
	x, y: f32,
	label, value: cstring,
	color_label: [4]u8 = DEBUG_COLOR_STATE,
	color_value: [4]u8 = DEBUG_COLOR_STATE_MUTED,
) {
	label_w := debug_text_width(label)
	space_w := debug_text_width(" ")
	debug_text(x, y, label, color_label)
	debug_text(x + label_w + space_w, y, value, color_value)
}

debug_point :: proc(pos: [2]f32, color: [4]u8 = DEBUG_COLOR_STATE) {
	sp := game_world_to_screen_point(pos)
	debug_set_color(color)
	sdl.RenderLine(game.win.renderer, sp.x - DEBUG_CROSS_HALF, sp.y, sp.x + DEBUG_CROSS_HALF, sp.y)
	sdl.RenderLine(game.win.renderer, sp.x, sp.y - DEBUG_CROSS_HALF, sp.x, sp.y + DEBUG_CROSS_HALF)
}

debug_vector :: proc(pos: [2]f32, dir: [2]f32, color: [4]u8) {
	sp := game_world_to_screen_point(pos)
	sd := game_world_to_screen_point(pos + dir)
	debug_set_color(color)
	sdl.RenderLine(game.win.renderer, sp.x, sp.y, sd.x, sd.y)
}

debug_collider_rect :: proc(
	collider_rect: engine.Physics_Rect,
	color: [4]u8 = DEBUG_COLOR_COLLIDER,
) {
	bottom_left := collider_rect.pos - collider_rect.size / 2
	rect := game_world_to_screen(bottom_left, collider_rect.size)
	debug_set_color(color)
	sdl.RenderRect(game.win.renderer, &rect)
}

debug_ray :: proc(
	origin, endpoint: [2]f32,
	hit: engine.Physics_Raycast_Hit,
	hit_color: [4]u8 = DEBUG_COLOR_RAY_GROUND,
) {
	sp := game_world_to_screen_point(origin)
	ep := game_world_to_screen_point(endpoint)
	if hit.hit {
		hp := game_world_to_screen_point(hit.point)
		debug_set_color(hit_color)
		sdl.RenderLine(game.win.renderer, sp.x, sp.y, hp.x, hp.y)
		debug_set_color(DEBUG_COLOR_RAY_MISS)
		sdl.RenderLine(game.win.renderer, hp.x, hp.y, ep.x, ep.y)
		debug_point(hit.point, DEBUG_COLOR_RAY_HIT_POINT)
	} else {
		debug_set_color(DEBUG_COLOR_RAY_MISS)
		sdl.RenderLine(game.win.renderer, sp.x, sp.y, ep.x, ep.y)
	}
}

debug_collider_platform :: proc(collider_rect: engine.Physics_Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_PLATFORM)
}

debug_collider_back_wall :: proc(collider_rect: engine.Physics_Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_BACK_WALL)
}

debug_collider_slope :: proc(collider_slope: engine.Physics_Slope) {
	base_x, base_y, span := collider_slope.base_x, collider_slope.base_y, collider_slope.span
	p0, p1, p2: [2]f32
	switch collider_slope.kind {
	case .Right:
		p0 = {base_x, base_y}
		p1 = {base_x + span, base_y}
		p2 = {base_x + span, base_y + span}
	case .Left:
		p0 = {base_x, base_y}
		p1 = {base_x + span, base_y}
		p2 = {base_x, base_y + span}
	case .Ceil_Right:
		p0 = {base_x, base_y + span}
		p1 = {base_x + span, base_y + span}
		p2 = {base_x + span, base_y}
	case .Ceil_Left:
		p0 = {base_x, base_y + span}
		p1 = {base_x + span, base_y + span}
		p2 = {base_x, base_y}
	}
	sp0 := game_world_to_screen_point(p0)
	sp1 := game_world_to_screen_point(p1)
	sp2 := game_world_to_screen_point(p2)
	debug_set_color(DEBUG_COLOR_COLLIDER)
	sdl.RenderLine(game.win.renderer, sp0.x, sp0.y, sp1.x, sp1.y)
	sdl.RenderLine(game.win.renderer, sp1.x, sp1.y, sp2.x, sp2.y)
	sdl.RenderLine(game.win.renderer, sp2.x, sp2.y, sp0.x, sp0.y)
}

debug_camera :: proc() {
	dz := game.camera.dead_zone
	lw := f32(game.win.logical_w)
	lh := f32(game.win.logical_h)

	left := lw * (1 - dz) / 2
	right := lw * (1 + dz) / 2
	top := lh * (1 - dz) / 2
	bottom := lh * (1 + dz) / 2

	debug_set_color(DEBUG_COLOR_CAMERA_ZONE)
	r := game.win.renderer
	sdl.RenderLine(r, left, top, right, top) // top
	sdl.RenderLine(r, left, bottom, right, bottom) // bottom
	sdl.RenderLine(r, left, top, left, bottom) // left
	sdl.RenderLine(r, right, top, right, bottom) // right
}

@(private = "file")
debug_text_right :: proc(x, y: f32, text: cstring, color: [4]u8 = DEBUG_COLOR_STATE) {
	text_w := debug_text_width(text)
	debug_text(x - text_w, y, text, color)
}

@(private = "file")
debug_key_name :: proc(action: Input_Action) -> cstring {
	return sdl.GetScancodeName(game.input.bindings[action].keyboard)
}

@(private = "file")
debug_move_label :: proc() -> cstring {
	u := debug_key_name(.MOVE_UP)
	d := debug_key_name(.MOVE_DOWN)
	l := debug_key_name(.MOVE_LEFT)
	r := debug_key_name(.MOVE_RIGHT)
	if len(u) == 1 && len(d) == 1 && len(l) == 1 && len(r) == 1 {
		return fmt.ctprintf("%s%s%s%s", u, l, d, r)
	}
	return fmt.ctprintf("%s/%s/%s/%s", u, l, d, r)
}

debug_render_controls :: proc() {
	family := engine.input_family(game.input.type, game.input.gamepad)
	is_keyboard := family == .Keyboard

	right_x := f32(game.win.logical_w) - DEBUG_TEXT_MARGIN_X
	y := DEBUG_TEXT_MARGIN_Y

	family_labels := engine.INPUT_FAMILY_LABELS
	debug_text_right(right_x, y, family_labels[family], DEBUG_COLOR_STATE)
	y += DEBUG_TEXT_LINE_H * DEBUG_TEXT_TITLE_GAP

	Row :: struct {
		label: cstring,
		key:   cstring,
	}

	button_names := engine.INPUT_BUTTON_NAMES
	names := button_names[family]
	rows: [5]Row
	if is_keyboard {
		rows = {
			{"Move", debug_move_label()},
			{"Jump", debug_key_name(.JUMP)},
			{"Dash", debug_key_name(.DASH)},
			{"Wall Run", debug_key_name(.WALL_RUN)},
			{"Slide", debug_key_name(.SLIDE)},
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
