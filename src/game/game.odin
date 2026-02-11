package game

import engine "../engine"
import "core:fmt"
import sdl "vendor:sdl3"

// Convenience wrappers for camera coordinate conversion
world_to_screen :: proc(world_pos, world_size: [2]f32) -> sdl.FRect {
	return engine.camera_world_to_screen(&game.camera, world_pos, world_size)
}

world_to_screen_point :: proc(world_pos: [2]f32) -> [2]f32 {
	return engine.camera_world_to_screen_point(&game.camera, world_pos)
}

Game_State :: struct {
	win:     engine.Window,
	running: bool,
	debug:   Debug_State,
	world_w: f32,

	// Engine
	input:   engine.Input(Input_Action),
	clock:   engine.Clock,

	// Camera & Level
	camera:  engine.Camera,
	level:   Level,

	// Player
	player:  Player,
	dust:    engine.Particle_Pool,
	steps:   engine.Particle_Pool,
}

game: Game_State

config_post_apply :: proc() {
	input_binding_apply(&game.input)
	game.camera.follow_speed_min = CAMERA_FOLLOW_SPEED_MIN
	game.camera.follow_speed_max = CAMERA_FOLLOW_SPEED_MAX
	game.camera.dead_zone = CAMERA_DEAD_ZONE
	game.camera.boundary_zone = CAMERA_BOUNDARY_ZONE
}

game_clean :: proc() {
	engine.config_destroy(&game_config)
	level_destroy(&game.level)
	engine.window_clean(&game.win)
}

game_init :: proc() {
	game.running = true

	// Load config first (before window_init so WINDOW_TITLE/LOGICAL_H/WINDOW_SCALE are available)
	config_load_and_apply()

	win, ok := engine.window_init(
		fmt.ctprintf("%s", WINDOW_TITLE),
		i32(LOGICAL_H),
		i32(WINDOW_SCALE),
	)
	if !ok {game.running = false; return}
	game.win = win

	engine.input_init(&game.input)

	game.clock = engine.clock_init(u64(FPS), u64(FIXED_STEPS))

	// Load level
	level, level_ok := level_load("assets/level_01.bmp")
	if !level_ok {game.running = false; return}
	game.level = level
	game.world_w = game.level.world_w

	// Camera
	game.camera = engine.camera_init(
		f32(game.win.logical_w) / PPM,
		f32(LOGICAL_H) / PPM,
		PPM,
		f32(LOGICAL_H),
	)

	// Player
	game.player.transform.pos = game.level.player_spawn
	game.player.abilities.dash_dir = 1
	player_init(&game.player)

	// Apply post-config (input bindings + camera params) and snap camera to player spawn
	config_post_apply()
	game.camera.pos = game.player.collider.pos
}

game_update :: proc(dt: f32) {
	event: sdl.Event
	engine.input_pre_update(&game.input)
	for sdl.PollEvent(&event) {
		engine.input_update(&game.input, &event)
		if game.input.is_down[.QUIT] do game.running = false
		if event.type == .QUIT do game.running = false
	}
	engine.input_post_update(&game.input)
	if game.input.is_pressed[.DEBUG] do game.debug = Debug_State((int(game.debug) + 1) % len(Debug_State))
	if game.input.is_pressed[.RELOAD] do config_reload_all()
}

game_fixed_update :: proc(dt: f32) {
	player_fixed_update(&game.player, dt)
	player_dust_update(&game.dust, dt)
	player_step_update(&game.steps, dt)
	engine.camera_follow(
		&game.camera,
		game.player.collider.pos,
		{0, 0},
		{game.level.world_w, game.level.world_h},
		dt,
	)
	engine.camera_clamp(&game.camera, {0, 0}, {game.level.world_w, game.level.world_h})
}

game_render :: proc() {
	level_render(&game.level)
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)
	player_step_render(&game.steps)
	player_dust_render(&game.dust)
	player_render(&game.player)
}

game_render_debug :: proc() {
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)

	level_debug(&game.level)

	sensor_pos: [2]f32 = {DEBUG_TEXT_MARGIN_X, DEBUG_TEXT_MARGIN_Y + 2 * DEBUG_TEXT_LINE_H}
	player_sensor_debug(&game.player, sensor_pos)
	player_physics_debug(&game.player)
	player_debug(&game.player)
	camera_debug()

	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		DEBUG_TEXT_MARGIN_Y,
		"FPS:",
		fmt.ctprintf("%.0f", 1.0 / game.clock.dt),
	)
}
