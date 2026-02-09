package game

import "core:fmt"
import "core:math"
import engine "../engine"
import sdl "vendor:sdl3"

// Resolution & Scaling
LOGICAL_H :: 480
WINDOW_SCALE :: 2
PPM: f32 : 16 // power of 2 — all pixel/PPM values exact in f32

// Engine
FPS :: 60
FIXED_STEPS :: 4

// Physics (meters, m/s, m/s²)
GRAVITY: f32 : 2_000.0 / PPM
EPS: f32 : 0.001 / PPM

// Colors
COLOR_BG: [3]u8 : {20, 20, 30}
COLOR_DEBUG_COLLIDER: [3]u8 : {0, 255, 0}
COLOR_DEBUG_PLATFORM: [3]u8 : {0, 100, 255}
COLOR_DEBUG_SENSOR: [3]u8 : {255, 255, 0}
COLOR_DEBUG_ANCHOR: [3]u8 : {255, 255, 255} // white — element anchors
COLOR_DEBUG_PLAYER: [3]u8 : {255, 0, 255} // magenta — player position
COLOR_DEBUG_FACING: [3]u8 : {0, 255, 255} // cyan — facing direction
COLOR_DEBUG_VELOCITY: [3]u8 : {180, 255, 0} // yellow-green — velocity vector
COLOR_DEBUG_BACK_WALL: [3]u8 : {0, 100, 100} // dark cyan — back wall colliders
COLOR_DEBUG_STATE: [3]u8 : {255, 255, 255} // white — state text
COLOR_DEBUG_STATE_MUTED: [3]u8 : {130, 130, 130} // muted gray — previous state text
COLOR_DEBUG_VALUE: [3]u8 : {180, 180, 180} // muted white — values
COLOR_DEBUG_ACTION: [3]u8 : {0, 220, 220} // cyan — action label
COLOR_DEBUG_ACTION_DIM: [3]u8 : {80, 80, 80} // dark gray — unavailable action

DEBUG_CROSS_HALF: f32 : 3 // pixels, half-size of anchor crosses
DEBUG_PLAYER_CROSS_HALF: f32 : 4 // pixels, half-size of player position cross
DEBUG_FACING_LENGTH: f32 : 18 // pixels, length of facing direction line
DEBUG_VEL_SCALE: f32 : 0.15 // velocity vector display scale
DEBUG_STATE_TEXT_GAP: f32 : 24 // pixels, gap above player to state text
DEBUG_FONT_CHAR_W: f32 : 8 // SDL debug font character width
DEBUG_TEXT_MARGIN_X: f32 : 16 // pixels, horizontal margin from screen edges for debug text
DEBUG_TEXT_MARGIN_Y: f32 : 10 // pixels, vertical margin from screen edges for debug text
DEBUG_TEXT_LINE_H: f32 : 12 // pixels, line height for debug text rows
DEBUG_SENSOR_BOX_W: f32 : 16 * DEBUG_FONT_CHAR_W // fixed width for sensor readout box

// World-to-screen conversion (camera-based)
// world_pos = bottom-left corner in world meters, world_size = dimensions in meters
world_to_screen :: proc(world_pos, world_size: [2]f32) -> sdl.FRect {
	cam_bl := game.camera.pos - game.camera.size / 2
	rel := (world_pos - cam_bl) * PPM
	sz := world_size * PPM
	return {rel.x, f32(LOGICAL_H) - rel.y - sz.y, sz.x, sz.y}
}

// World position → screen pixel (Y-flipped)
world_to_screen_point :: proc(world_pos: [2]f32) -> [2]f32 {
	cam_bl := game.camera.pos - game.camera.size / 2
	rel := (world_pos - cam_bl) * PPM
	return {rel.x, f32(LOGICAL_H) - rel.y}
}

Game_State :: struct {
	win:                            engine.Window,
	running:                        bool,
	debug:                          bool,
	world_w:                        f32,

	// Engine
	input:                          engine.Input,
	clock:                          engine.Clock,

	// Camera & Level
	camera:                         engine.Camera,
	level:                          Level,

	// Player
	player_vel:                     [2]f32,
	player_pos:                     [2]f32,
	player_collider:                engine.Collider_Rect,
	player_wall_sensor:             engine.Collider_Rect,

	// Player Abilities
	player_dash_dir:                f32,
	player_dash_active_timer:       f32,
	player_dash_cooldown_timer:     f32,
	player_coyote_timer:            f32,
	player_jump_buffer_timer:       f32,
	player_wall_run_timer:          f32,
	player_wall_run_cooldown_timer: f32,
	player_wall_run_used:           bool,
	player_back_run_timer:          f32,
	player_back_run_dir:            f32,
	player_back_run_used:           bool,
	player_back_climb_timer:        f32,
	player_back_climb_cooldown:     f32,
	// Player Slope
	player_on_slope:                bool,
	player_slope_dir:               f32, // +1 rises right, -1 rises left

	// Player Visual
	player_visual_look:             [2]f32,
	player_run_anim_timer:          f32,
	player_impact_timer:            f32,
	player_impact_strength:         f32,
	player_impact_axis:             [2]f32,
}

game: Game_State

main :: proc() {
	defer game_clean()
	game_init()

	for game.running {
		engine.clock_update(&game.clock)
		game_update(game.clock.dt)
		for engine.clock_tick(&game.clock) do game_fixed_update(game.clock.fixed_dt)
		sdl.SetRenderDrawColor(game.win.renderer, COLOR_BG.r, COLOR_BG.g, COLOR_BG.b, 255)
		sdl.RenderClear(game.win.renderer)
		game_render()
		if game.debug do game_render_debug()
		sdl.RenderPresent(game.win.renderer)
		free_all(context.temp_allocator)
	}
}

// Game life cycle procs

game_clean :: proc() {
	level_destroy(&game.level)
	engine.window_clean(&game.win)
}

game_init :: proc() {
	game.running = true

	win, ok := engine.window_init("Hour Glass Spire - the Sands of Pars", LOGICAL_H, WINDOW_SCALE)
	if !ok {game.running = false; return}
	game.win = win

	game.input = engine.input_init()
	game.clock = engine.clock_init(FPS, FIXED_STEPS)

	// Load level
	level, level_ok := level_load("assets/level_01.bmp")
	if !level_ok {game.running = false; return}
	game.level = level
	game.world_w = game.level.world_w

	// Camera
	game.camera = engine.camera_init(f32(game.win.logical_w) / PPM, f32(LOGICAL_H) / PPM)

	// Player
	game.player_pos = game.level.player_spawn
	game.player_dash_dir = 1
	game.player_collider = {
		size = {PLAYER_SIZE, PLAYER_SIZE},
	}
	player_sync_collider()

	player_init()
}

game_update :: proc(dt: f32) {
	engine.input_pre_update(&game.input)

	event: sdl.Event
	for sdl.PollEvent(&event) {
		engine.input_update(&game.input, &event)
		if game.input.is_down[.QUIT] do game.running = false
		if event.type == .QUIT do game.running = false
	}

	engine.input_post_update(&game.input)

	if game.input.is_pressed[.DEBUG] do game.debug = !game.debug
}

game_fixed_update :: proc(dt: f32) {
	player_fixed_update(dt)
	engine.camera_follow(&game.camera, {game.player_pos.x, game.player_pos.y + PLAYER_SIZE / 2})
	engine.camera_clamp(&game.camera, {0, 0}, {game.level.world_w, game.level.world_h})
}

game_render :: proc() {
	vel_px := game.player_vel * PPM
	size_px: f32 = PLAYER_SIZE * PPM

	// -- Level tiles (camera-aware)
	level_render(&game.level)

	// -- Visual Deformation (layered) --
	h_scale: f32 = 1.0
	w_scale: f32 = 1.0

	// Layer 1: Velocity squash/stretch
	h_scale += math.abs(vel_px.y) * 0.001 - math.abs(vel_px.x) * 0.00025
	w_scale += -math.abs(vel_px.y) * 0.0005 + math.abs(vel_px.x) * 0.0005

	// Layer 2: Input look
	look := game.player_visual_look
	h_scale += look.y * PLAYER_LOOK_DEFORM
	w_scale -= look.y * PLAYER_LOOK_DEFORM * 0.5
	w_scale += math.abs(look.x) * PLAYER_LOOK_DEFORM * 0.3

	// Layer 3: Run bob
	run_osc := math.sin(game.player_run_anim_timer) * PLAYER_RUN_BOB_AMPLITUDE
	h_scale += run_osc
	w_scale -= run_osc * 0.5

	// Layer 4: Impact bounce
	if game.player_impact_strength > 0 {
		t := game.player_impact_timer
		envelope := game.player_impact_strength * math.exp(-PLAYER_IMPACT_DECAY * t)
		osc := envelope * math.cos(PLAYER_IMPACT_FREQ * t) * PLAYER_IMPACT_SCALE
		if envelope * PLAYER_IMPACT_SCALE < 0.005 {
			game.player_impact_strength = 0
		}
		h_scale -= osc * game.player_impact_axis.y
		w_scale += osc * game.player_impact_axis.y * 0.5
		w_scale -= osc * game.player_impact_axis.x
		h_scale += osc * game.player_impact_axis.x * 0.5
	}

	h_scale = math.clamp(h_scale, 0.5, 1.5)
	w_scale = math.clamp(w_scale, 0.5, 1.5)

	h := size_px * h_scale
	w := size_px * w_scale

	// -- Player (deformed size, bottom-center anchored)
	// Convert deformed pixel size back to world units for world_to_screen
	w_world := w / PPM
	h_world := h / PPM
	player_bl := [2]f32{game.player_pos.x - w_world / 2, game.player_pos.y}
	rect_p := world_to_screen(player_bl, {w_world, h_world})
	player_color := player_get_color()
	sdl.SetRenderDrawColor(game.win.renderer, player_color.r, player_color.g, player_color.b, 255)
	sdl.RenderFillRect(game.win.renderer, &rect_p)
}

debug_text_line :: proc(x, y: f32, label, value: cstring) {
	label_w := f32(len(label)) * DEBUG_FONT_CHAR_W
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_STATE.r,
		COLOR_DEBUG_STATE.g,
		COLOR_DEBUG_STATE.b,
		255,
	)
	sdl.RenderDebugText(game.win.renderer, x, y, label)
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_VALUE.r,
		COLOR_DEBUG_VALUE.g,
		COLOR_DEBUG_VALUE.b,
		255,
	)
	sdl.RenderDebugText(game.win.renderer, x + label_w, y, value)
}

game_render_debug :: proc() {
	// -- Ground + wall colliders (green) --
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_COLLIDER.r,
		COLOR_DEBUG_COLLIDER.g,
		COLOR_DEBUG_COLLIDER.b,
		255,
	)

	// Player collider
	{
		c := game.player_collider
		bl := c.pos - c.size / 2
		rect := world_to_screen(bl, c.size)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// Ground colliders
	for c in game.level.ground_colliders {
		bl := c.pos - c.size / 2
		rect := world_to_screen(bl, c.size)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// Wall colliders (deduplicated from ground — skip those already in ground_colliders)
	// Since solid tiles add to both, wall_colliders mirrors ground_colliders. Just draw them all.
	// The visual overlap is fine for debug.

	// Platform colliders
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_PLATFORM.r,
		COLOR_DEBUG_PLATFORM.g,
		COLOR_DEBUG_PLATFORM.b,
		255,
	)
	for c in game.level.platform_colliders {
		bl := c.pos - c.size / 2
		rect := world_to_screen(bl, c.size)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// Back wall colliders (dark cyan)
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_BACK_WALL.r,
		COLOR_DEBUG_BACK_WALL.g,
		COLOR_DEBUG_BACK_WALL.b,
		255,
	)
	for c in game.level.back_wall_colliders {
		bl := c.pos - c.size / 2
		rect := world_to_screen(bl, c.size)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// Slope colliders (green diagonal + bounding box)
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_COLLIDER.r,
		COLOR_DEBUG_COLLIDER.g,
		COLOR_DEBUG_COLLIDER.b,
		255,
	)
	for s in game.level.slope_colliders {
		// Bounding box
		bl := [2]f32{s.base_x, s.base_y}
		rect := world_to_screen(bl, {s.span, s.span})
		sdl.RenderRect(game.win.renderer, &rect)
		// Diagonal line (slope surface)
		p0, p1: [2]f32
		switch s.kind {
		case .Right, .Ceil_Left:
			p0 = {s.base_x, s.base_y}
			p1 = {s.base_x + s.span, s.base_y + s.span}
		case .Left, .Ceil_Right:
			p0 = {s.base_x, s.base_y + s.span}
			p1 = {s.base_x + s.span, s.base_y}
		}
		sp0 := world_to_screen_point(p0)
		sp1 := world_to_screen_point(p1)
		sdl.RenderLine(game.win.renderer, sp0.x, sp0.y, sp1.x, sp1.y)
	}

	// -- Wall sensor (yellow) --
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_SENSOR.r,
		COLOR_DEBUG_SENSOR.g,
		COLOR_DEBUG_SENSOR.b,
		255,
	)
	{
		c := game.player_wall_sensor
		bl := c.pos - c.size / 2
		rect := world_to_screen(bl, c.size)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// -- Element anchor crosses (white) --
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_ANCHOR.r,
		COLOR_DEBUG_ANCHOR.g,
		COLOR_DEBUG_ANCHOR.b,
		255,
	)
	for c in game.level.ground_colliders {
		sp := world_to_screen_point(c.pos)
		sdl.RenderLine(
			game.win.renderer,
			sp.x - DEBUG_CROSS_HALF,
			sp.y,
			sp.x + DEBUG_CROSS_HALF,
			sp.y,
		)
		sdl.RenderLine(
			game.win.renderer,
			sp.x,
			sp.y - DEBUG_CROSS_HALF,
			sp.x,
			sp.y + DEBUG_CROSS_HALF,
		)
	}
	for c in game.level.platform_colliders {
		sp := world_to_screen_point(c.pos)
		sdl.RenderLine(
			game.win.renderer,
			sp.x - DEBUG_CROSS_HALF,
			sp.y,
			sp.x + DEBUG_CROSS_HALF,
			sp.y,
		)
		sdl.RenderLine(
			game.win.renderer,
			sp.x,
			sp.y - DEBUG_CROSS_HALF,
			sp.x,
			sp.y + DEBUG_CROSS_HALF,
		)
	}

	// -- Player position cross (magenta) --
	player_sp := world_to_screen_point(game.player_pos)
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_PLAYER.r,
		COLOR_DEBUG_PLAYER.g,
		COLOR_DEBUG_PLAYER.b,
		255,
	)
	sdl.RenderLine(
		game.win.renderer,
		player_sp.x - DEBUG_PLAYER_CROSS_HALF,
		player_sp.y,
		player_sp.x + DEBUG_PLAYER_CROSS_HALF,
		player_sp.y,
	)
	sdl.RenderLine(
		game.win.renderer,
		player_sp.x,
		player_sp.y - DEBUG_PLAYER_CROSS_HALF,
		player_sp.x,
		player_sp.y + DEBUG_PLAYER_CROSS_HALF,
	)

	// -- Player facing direction (cyan) --
	center_sp := world_to_screen_point({game.player_pos.x, game.player_pos.y + PLAYER_SIZE / 2})
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_FACING.r,
		COLOR_DEBUG_FACING.g,
		COLOR_DEBUG_FACING.b,
		255,
	)
	sdl.RenderLine(
		game.win.renderer,
		center_sp.x,
		center_sp.y,
		center_sp.x + game.player_dash_dir * DEBUG_FACING_LENGTH,
		center_sp.y,
	)

	// -- Player velocity vector (yellow-green) --
	vel_px := game.player_vel * PPM * DEBUG_VEL_SCALE
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_VELOCITY.r,
		COLOR_DEBUG_VELOCITY.g,
		COLOR_DEBUG_VELOCITY.b,
		255,
	)
	sdl.RenderLine(
		game.win.renderer,
		center_sp.x,
		center_sp.y,
		center_sp.x + vel_px.x,
		center_sp.y - vel_px.y, // Y flipped for screen
	)

	// -- Player state text (white, follows player via camera) --
	state_name := fmt.ctprintf("%v", player_fsm.current)
	text_w := f32(len(state_name)) * DEBUG_FONT_CHAR_W
	top_sp := world_to_screen_point({game.player_pos.x, game.player_pos.y + PLAYER_SIZE})
	text_x := top_sp.x - text_w / 2
	text_y := top_sp.y - DEBUG_STATE_TEXT_GAP - 8
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_STATE.r,
		COLOR_DEBUG_STATE.g,
		COLOR_DEBUG_STATE.b,
		255,
	)
	sdl.RenderDebugText(game.win.renderer, text_x, text_y, state_name)

	// -- Previous player state text (muted) --
	prev_name := fmt.ctprintf("%v", player_fsm.previous)
	prev_w := f32(len(prev_name)) * DEBUG_FONT_CHAR_W
	prev_x := top_sp.x - prev_w / 2
	prev_y := text_y + DEBUG_TEXT_LINE_H
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_DEBUG_STATE_MUTED.r,
		COLOR_DEBUG_STATE_MUTED.g,
		COLOR_DEBUG_STATE_MUTED.b,
		255,
	)
	sdl.RenderDebugText(game.win.renderer, prev_x, prev_y, prev_name)

	// -- FPS counter (top left, screen space) --
	debug_text_line(
		DEBUG_TEXT_MARGIN_X,
		DEBUG_TEXT_MARGIN_Y,
		"FPS: ",
		fmt.ctprintf("%.0f", 1.0 / game.clock.dt),
	)

	// -- Player sensor + timers (top right, screen space) --
	sensor_x := f32(game.win.logical_w) - DEBUG_SENSOR_BOX_W - DEBUG_TEXT_MARGIN_X
	Sensor_Entry :: struct {
		label, value: cstring,
	}
	sensor_entries := [?]Sensor_Entry {
		{"ground:    ", fmt.ctprintf("%v", player_sensor.on_ground)},
		{"platform:  ", fmt.ctprintf("%v", player_sensor.on_platform)},
		{"in_plat:   ", fmt.ctprintf("%v", player_sensor.in_platform)},
		{"wall_l:    ", fmt.ctprintf("%v", player_sensor.on_left_wall)},
		{"wall_r:    ", fmt.ctprintf("%v", player_sensor.on_right_wall)},
		{"back_wall: ", fmt.ctprintf("%v", player_sensor.on_back_wall)},
		{"on_slope:  ", fmt.ctprintf("%v", player_sensor.on_slope)},
		{"slope_dir: ", fmt.ctprintf("%.0f", player_sensor.slope_dir)},
		{"wr_timer:  ", fmt.ctprintf("%.2f", game.player_wall_run_timer)},
		{"wr_cd:     ", fmt.ctprintf("%.2f", game.player_wall_run_cooldown_timer)},
		{"coyote:    ", fmt.ctprintf("%.2f", game.player_coyote_timer)},
		{"jump_buf:  ", fmt.ctprintf("%.2f", game.player_jump_buffer_timer)},
		{"dash_cd:   ", fmt.ctprintf("%.2f", game.player_dash_cooldown_timer)},
		{"dash_act:  ", fmt.ctprintf("%.2f", game.player_dash_active_timer)},
		{"back_cd:   ", fmt.ctprintf("%.2f", game.player_back_climb_cooldown)},
	}
	for entry, i in sensor_entries {
		debug_text_line(
			sensor_x,
			DEBUG_TEXT_MARGIN_Y + f32(i) * DEBUG_TEXT_LINE_H,
			entry.label,
			entry.value,
		)
	}

	// -- Key binding reminder (bottom left, screen space) --
	Binding_Entry :: struct {
		action:    engine.Input_Action,
		label:     cstring,
		available: bool,
	}
	current_state := player_fsm.current
	bindings := [?]Binding_Entry {
		{.JUMP, "Jump", current_state != .Dashing},
		{.DASH, "Dash", current_state != .Dashing && game.player_dash_cooldown_timer <= 0},
		{.WALL_RUN, "Wall Run", current_state != .Dashing},
		{.SLIDE, "Slide", current_state != .Dashing},
	}
	bind_y_start := f32(LOGICAL_H) - DEBUG_TEXT_MARGIN_Y - f32(len(bindings)) * DEBUG_TEXT_LINE_H
	kb_bindings := engine.INPUT_BINDING_KEYBOARD
	gp_bindings := engine.INPUT_BINDING_GAMEPAD_BUTTON
	for entry, i in bindings {
		y := bind_y_start + f32(i) * DEBUG_TEXT_LINE_H
		// Key name
		key_name: cstring
		if game.input.type == .KEYBOARD {
			key_name = sdl.GetScancodeName(kb_bindings[entry.action])
		} else {
			button := gp_bindings[entry.action]
			if game.input.gamepad != nil {
				label := sdl.GetGamepadButtonLabel(game.input.gamepad, button)
				key_name = fmt.ctprintf("%v", label)
			} else {
				key_name = sdl.GetGamepadStringForButton(button)
			}
		}
		key_str := fmt.ctprintf("[%s] ", key_name)
		key_w := f32(len(key_str)) * DEBUG_FONT_CHAR_W
		// Key in white
		sdl.SetRenderDrawColor(
			game.win.renderer,
			COLOR_DEBUG_STATE.r,
			COLOR_DEBUG_STATE.g,
			COLOR_DEBUG_STATE.b,
			255,
		)
		sdl.RenderDebugText(game.win.renderer, DEBUG_TEXT_MARGIN_X, y, key_str)
		// Action label in cyan or dim
		action_color := COLOR_DEBUG_ACTION if entry.available else COLOR_DEBUG_ACTION_DIM
		sdl.SetRenderDrawColor(
			game.win.renderer,
			action_color.r,
			action_color.g,
			action_color.b,
			255,
		)
		sdl.RenderDebugText(game.win.renderer, DEBUG_TEXT_MARGIN_X + key_w, y, entry.label)
	}
}
