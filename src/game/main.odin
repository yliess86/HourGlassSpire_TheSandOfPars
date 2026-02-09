package game

import engine "../engine"
import "core:fmt"
import "core:math"
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
	player_wall_run_dir:            f32,
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
	player_color := player_color()
	sdl.SetRenderDrawColor(game.win.renderer, player_color.r, player_color.g, player_color.b, 255)
	sdl.RenderFillRect(game.win.renderer, &rect_p)
}

game_render_debug :: proc() {
	debug_collider_rect(game.player_collider)
	for c in game.level.ground_colliders do debug_collider_rect(c)
	for c in game.level.platform_colliders do debug_collider_plateform(c)
	for c in game.level.back_wall_colliders do debug_collider_back_wall(c)
	for s in game.level.slope_colliders do debug_collider_slope(s)
	debug_collider_sensor(game.player_wall_sensor)

	for c in game.level.ground_colliders do debug_point(c.pos)
	for c in game.level.platform_colliders do debug_point(c.pos)
	debug_point_player(game.player_pos)

	player_mid_y: [2]f32 = {game.player_pos.x, game.player_pos.y + PLAYER_SIZE / 2}
	player_dash_dir: [2]f32 = {game.player_dash_dir * DEBUG_FACING_LENGTH, 0}
	player_vel := game.player_vel * PPM * DEBUG_VEL_SCALE
	debug_vector(player_mid_y, player_dash_dir, DEBUG_COLOR_FACING_DIR)
	debug_vector(player_mid_y, player_vel, DEBUG_COLOR_VELOCITY)

	player_top := world_to_screen_point({game.player_pos.x, game.player_pos.y + PLAYER_SIZE})
	player_subti := player_top - {0, DEBUG_TEXT_STATE_GAP}
	player_title := player_subti - {0, DEBUG_TEXT_LINE_H}
	debug_text_center(player_title.x, player_title.y, fmt.ctprintf("%v", player_fsm.current))
	debug_text_center(
		player_subti.x,
		player_subti.y,
		fmt.ctprintf("%v", player_fsm.previous),
		DEBUG_COLOR_STATE_MUTED,
	)

	Label_Value :: struct {
		label, value: cstring,
	}
	fps_entry := Label_Value{"FPS:", fmt.ctprintf("%.0f", 1.0 / game.clock.dt)}
	sensor_entries := [?]Label_Value {
		{"coyote_timer:", fmt.ctprintf("%.2f", game.player_coyote_timer)},
		{"dash_active_timer:", fmt.ctprintf("%.2f", game.player_dash_active_timer)},
		{"dash_cooldown_timer:", fmt.ctprintf("%.2f", game.player_dash_cooldown_timer)},
		{"in_platform:", fmt.ctprintf("%v", player_sensor.in_platform)},
		{"jump_buffer_timer:", fmt.ctprintf("%.2f", game.player_jump_buffer_timer)},
		{"on_back_wall: ", fmt.ctprintf("%v", player_sensor.on_back_wall)},
		{"on_ground:", fmt.ctprintf("%v", player_sensor.on_ground)},
		{"on_platform:", fmt.ctprintf("%v", player_sensor.on_platform)},
		{"on_side_wall:", fmt.ctprintf("%v", player_sensor.on_side_wall)},
		{"on_side_wall_dir:", fmt.ctprintf("%.0f", player_sensor.on_side_wall_dir)},
		{"on_slope:", fmt.ctprintf("%v", player_sensor.on_slope)},
		{"on_slope_dir:", fmt.ctprintf("%.0f", player_sensor.on_slope_dir)},
		{"wall_run_cooldown_timer:", fmt.ctprintf("%.2f", game.player_wall_run_cooldown_timer)},
		{"wall_run_timer:", fmt.ctprintf("%.2f", game.player_wall_run_timer)},
	}
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		DEBUG_TEXT_MARGIN_Y,
		fps_entry.label,
		fps_entry.value,
	)
	for entry, i in sensor_entries {
		debug_value_with_label(
			DEBUG_TEXT_MARGIN_X,
			2 * DEBUG_TEXT_LINE_H + DEBUG_TEXT_MARGIN_Y + f32(i) * DEBUG_TEXT_LINE_H,
			entry.label,
			entry.value,
		)
	}
}
