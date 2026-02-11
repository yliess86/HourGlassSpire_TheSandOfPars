package game

import engine "../engine"
import sdl "vendor:sdl3"

Debug_State :: enum u8 {
	NONE,
	PLAYER,
	BACKGROUND,
	ALL,
}

DEBUG_COLOR_COLLIDER: [3]u8 : {0, 255, 0}
DEBUG_COLOR_COLLIDER_BACK_WALL: [3]u8 : {0, 100, 100} // dark cyan — back wall colliders
DEBUG_COLOR_COLLIDER_CEILING: [3]u8 : {200, 50, 50} // dark red — ceiling colliders
DEBUG_COLOR_COLLIDER_SIDE_WALL: [3]u8 : {255, 180, 0} // orange — side wall colliders
DEBUG_COLOR_COLLIDER_PLATFORM: [3]u8 : {0, 100, 255}
DEBUG_COLOR_FACING_DIR: [3]u8 : {0, 255, 255} // cyan — facing direction
DEBUG_COLOR_PLAYER: [3]u8 : {255, 0, 255} // magenta — player position
DEBUG_COLOR_STATE: [3]u8 : {255, 255, 255} // white — state text
DEBUG_COLOR_STATE_MUTED: [3]u8 : {130, 130, 130} // muted gray — previous state text
DEBUG_COLOR_RAY_HIT: [3]u8 : {255, 255, 0} // bright yellow — ray hit
DEBUG_COLOR_RAY_MISS: [3]u8 : {80, 80, 80} // dim gray — ray miss
DEBUG_COLOR_VELOCITY: [3]u8 : {180, 255, 0} // yellow-green — velocity vector
DEBUG_CROSS_HALF: f32 : 2 // pixels, half-size of anchor crosses
DEBUG_FACING_LENGTH: f32 : 0.5 // pixels, length of facing direction line
DEBUG_TEXT_CHAR_W: f32 : 8 // SDL debug font character width
DEBUG_TEXT_LINE_H: f32 : 12 // pixels, line height for debug text rows
DEBUG_TEXT_MARGIN_X: f32 : 16 // pixels, horizontal margin from screen edges for debug text
DEBUG_TEXT_MARGIN_Y: f32 : 10 // pixels, vertical margin from screen edges for debug text
DEBUG_TEXT_STATE_GAP: f32 : 24 // pixels, gap above player to state text
DEBUG_VEL_SCALE: f32 : 0.01 // velocity vector display scale

debug_set_color :: proc(color: [3]u8) {
	sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, 255)
}

debug_text_width :: proc(text: cstring) -> f32 {
	return f32(len(text)) * DEBUG_TEXT_CHAR_W
}

debug_text :: proc(x, y: f32, text: cstring, color: [3]u8 = DEBUG_COLOR_STATE) {
	debug_set_color(color)
	sdl.RenderDebugText(game.win.renderer, x, y, text)
}

debug_text_center :: proc(x, y: f32, text: cstring, color: [3]u8 = DEBUG_COLOR_STATE) {
	text_w := debug_text_width(text)
	debug_set_color(color)
	sdl.RenderDebugText(game.win.renderer, x - text_w / 2, y, text)
}

debug_value_with_label :: proc(
	x, y: f32,
	label, value: cstring,
	color_label: [3]u8 = DEBUG_COLOR_STATE,
	color_value: [3]u8 = DEBUG_COLOR_STATE_MUTED,
) {
	label_w := debug_text_width(label)
	space_w := debug_text_width(" ")
	debug_text(x, y, label, color_label)
	debug_text(x + label_w + space_w, y, value, color_value)
}

debug_point :: proc(pos: [2]f32, color: [3]u8 = DEBUG_COLOR_STATE) {
	sp := world_to_screen_point(pos)
	debug_set_color(color)
	sdl.RenderLine(game.win.renderer, sp.x - DEBUG_CROSS_HALF, sp.y, sp.x + DEBUG_CROSS_HALF, sp.y)
	sdl.RenderLine(game.win.renderer, sp.x, sp.y - DEBUG_CROSS_HALF, sp.x, sp.y + DEBUG_CROSS_HALF)
}

debug_point_player :: proc(pos: [2]f32) {
	debug_point(pos, DEBUG_COLOR_PLAYER)
}

debug_vector :: proc(pos: [2]f32, dir: [2]f32, color: [3]u8) {
	sp := world_to_screen_point(pos)
	sd := world_to_screen_point(pos + dir)
	debug_set_color(color)
	sdl.RenderLine(game.win.renderer, sp.x, sp.y, sd.x, sd.y)
}

debug_collider_rect :: proc(
	collider_rect: engine.Collider_Rect,
	color: [3]u8 = DEBUG_COLOR_COLLIDER,
) {
	bottom_left := collider_rect.pos - collider_rect.size / 2
	rect := world_to_screen(bottom_left, collider_rect.size)
	debug_set_color(color)
	sdl.RenderRect(game.win.renderer, &rect)
}

debug_ray :: proc(origin, endpoint: [2]f32, hit: bool) {
	sp := world_to_screen_point(origin)
	ep := world_to_screen_point(endpoint)
	debug_set_color(DEBUG_COLOR_RAY_HIT if hit else DEBUG_COLOR_RAY_MISS)
	sdl.RenderLine(game.win.renderer, sp.x, sp.y, ep.x, ep.y)
}

debug_collider_plateform :: proc(collider_rect: engine.Collider_Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_PLATFORM)
}

debug_collider_back_wall :: proc(collider_rect: engine.Collider_Rect) {
	debug_collider_rect(collider_rect, DEBUG_COLOR_COLLIDER_BACK_WALL)
}

debug_collider_slope :: proc(collider_slope: engine.Collider_Slope) {
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
	sp0 := world_to_screen_point(p0)
	sp1 := world_to_screen_point(p1)
	sp2 := world_to_screen_point(p2)
	debug_set_color(DEBUG_COLOR_COLLIDER)
	sdl.RenderLine(game.win.renderer, sp0.x, sp0.y, sp1.x, sp1.y)
	sdl.RenderLine(game.win.renderer, sp1.x, sp1.y, sp2.x, sp2.y)
	sdl.RenderLine(game.win.renderer, sp2.x, sp2.y, sp0.x, sp0.y)
}
