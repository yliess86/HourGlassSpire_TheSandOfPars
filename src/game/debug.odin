package game

import physics "../physics"
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

debug_collider_rect :: proc(collider_rect: physics.Rect, color: [4]u8 = DEBUG_COLOR_COLLIDER) {
	bottom_left := collider_rect.pos - collider_rect.size / 2
	rect := game_world_to_screen(bottom_left, collider_rect.size)
	debug_set_color(color)
	sdl.RenderRect(game.win.renderer, &rect)
}

debug_ray :: proc(
	origin, endpoint: [2]f32,
	hit: physics.Raycast_Hit,
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

debug_collider_platform :: proc(collider_rect: physics.Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_PLATFORM)
}

debug_collider_back_wall :: proc(collider_rect: physics.Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_BACK_WALL)
}

debug_collider_slope :: proc(collider_slope: physics.Slope) {
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
