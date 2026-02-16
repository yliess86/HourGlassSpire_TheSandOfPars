package game

import engine "../engine"
import "core:fmt"
import sdl "vendor:sdl3"

// Convenience wrappers for camera coordinate conversion
game_world_to_screen :: proc(world_pos, world_size: [2]f32) -> sdl.FRect {
	return engine.camera_world_to_screen(&game.camera, world_pos, world_size)
}

game_world_to_screen_point :: proc(world_pos: [2]f32) -> [2]f32 {
	return engine.camera_world_to_screen_point(&game.camera, world_pos)
}

Game_State :: struct {
	win:            engine.Window,
	running:        bool,
	debug:          Debug_State,
	world_w:        f32,

	// Engine
	input:          engine.Input(Input_Action),
	clock:          engine.Clock,

	// Camera & Level
	camera:         engine.Camera,
	level:          Level,

	// Player
	player:         Player,
	dust:           engine.Particle_Pool,
	steps:          engine.Particle_Pool,

	// Sand
	sand_world:     engine.Sand_World,
	sand_particles: engine.Particle_Pool,

	// Atmosphere
	atmosphere:     Atmosphere,
}

game: Game_State

game_config_post_apply :: proc() {
	input_binding_apply(&game.input)
	game.camera.follow_speed_min = CAMERA_FOLLOW_SPEED_MIN
	game.camera.follow_speed_max = CAMERA_FOLLOW_SPEED_MAX
	game.camera.dead_zone = CAMERA_DEAD_ZONE
	game.camera.boundary_zone = CAMERA_BOUNDARY_ZONE
	sand_graphics_init_lut()
	engine.sand_config_reload()
	game_sand_inject_fields()
}

game_sand_inject_fields :: proc() {
	game.sand_world.gravity = GRAVITY
	game.sand_world.run_speed = PLAYER_RUN_SPEED
	game.sand_world.wall_detect_eps = PLAYER_CHECK_SIDE_WALL_EPS
	game.sand_world.fixed_dt = 1.0 / (f32(FPS) * f32(FIXED_STEPS))
}

game_clean :: proc() {
	engine.particle_pool_destroy(&game.dust)
	engine.particle_pool_destroy(&game.steps)
	engine.particle_pool_destroy(&game.sand_particles)
	atmosphere_destroy(&game.atmosphere)
	engine.sand_destroy(&game.sand_world)
	engine.config_destroy(&config_game)
	level_destroy(&game.level)
	engine.window_clean(&game.win)
}

game_init :: proc() {
	game.running = true
	game.debug = .CONTROLS

	// Load config first (before window_init so WINDOW_TITLE/LOGICAL_H/WINDOW_SCALE are available)
	config_load_and_apply()
	engine.sand_config_load_and_apply()

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
	level, level_ok := level_load(fmt.ctprintf("assets/%s.bmp", LEVEL_NAME))
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
	game.player.body.pos = game.level.player_spawn
	game.player.abilities.dash_dir = 1
	player_init(&game.player)

	// Sand
	level_data := level_to_sand_data(&game.level)
	engine.sand_init(&game.sand_world, &level_data)
	delete(level_data.tiles)
	delete(level_data.original_tiles)
	delete(game.level.sand_piles)
	delete(game.level.sand_emitters)
	delete(game.level.water_piles)
	delete(game.level.water_emitters)
	delete(game.level.fire_emitters)
	delete(game.level.original_tiles)
	game_sand_inject_fields()

	// Apply post-config (input bindings + camera params) and snap camera to player spawn
	game_config_post_apply()
	game.camera.pos = engine.physics_body_center(&game.player.body)
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
	player_graphics_spawn_sand_particles(&game.sand_particles, &game.player)
	player_sand_footprint_update(&game.sand_world, &game.player)
	player_graphics_sand_dust_tick(&game.player)
	engine.sand_projectile_update(&game.sand_world, dt)
	engine.sand_sub_step_tick(&game.sand_world)
	engine.sand_emitter_update(&game.sand_world)
	engine.sand_particles_update(&game.sand_particles, dt)
	player_graphics_dust_update(&game.dust, dt)
	player_graphics_step_update(&game.steps, dt)
	atmosphere_update(&game.atmosphere, &game.level, dt)
	engine.camera_follow(
		&game.camera,
		engine.physics_body_center(&game.player.body),
		{0, 0},
		{game.level.world_w, game.level.world_h},
		dt,
	)
	engine.camera_clamp(&game.camera, {0, 0}, {game.level.world_w, game.level.world_h})
}

game_render :: proc() {
	level_render(&game.level)
	atmosphere_render(&game.atmosphere)
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)
	player_graphics_particle_render(&game.steps)
	player_graphics_particle_render(&game.dust)
	player_graphics_render(&game.player)
	player_graphics_sand_particle_render(&game.sand_particles)
	sand_graphics_render(&game.sand_world)
	sand_projectile_render(&game.sand_world)
}

game_render_debug :: proc() {
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)

	center_x := f32(game.win.logical_w) / 2
	next := Debug_State((int(game.debug) + 1) % len(Debug_State))
	debug_text_center(
		center_x,
		DEBUG_TEXT_MARGIN_Y,
		fmt.ctprintf("%v", game.debug),
		DEBUG_COLOR_STATE,
	)
	family := engine.input_family(game.input.type, game.input.gamepad)
	hint: cstring
	if family == .Keyboard {
		hint = sdl.GetScancodeName(game.input.bindings[.DEBUG].keyboard)
	} else {
		names := engine.INPUT_BUTTON_NAMES
		hint = names[family].back
	}
	debug_text_center(
		center_x,
		DEBUG_TEXT_MARGIN_Y + DEBUG_TEXT_LINE_H,
		fmt.ctprintf("%s > %v", hint, next),
		DEBUG_COLOR_STATE_MUTED,
	)

	if game.debug == .CONTROLS {
		debug_render_controls()
		return
	}

	level_debug(&game.level)
	sand_graphics_debug(&game.sand_world)

	sensor_pos: [2]f32 = {DEBUG_TEXT_MARGIN_X, DEBUG_TEXT_MARGIN_Y + 2 * DEBUG_TEXT_LINE_H}
	player_graphics_sensor_debug(&game.player, sensor_pos)
	player_graphics_physics_debug(&game.player)
	player_graphics_debug(&game.player)
	debug_camera()

	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		DEBUG_TEXT_MARGIN_Y,
		"FPS:",
		fmt.ctprintf("%.0f", 1.0 / game.clock.dt),
	)

	// Version info — bottom-left
	version_y := f32(game.win.logical_h) - 2 * DEBUG_TEXT_LINE_H - DEBUG_TEXT_MARGIN_Y
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		version_y,
		"Version:",
		fmt.ctprintf("%s", VERSION_HASH),
	)
	debug_text(
		DEBUG_TEXT_MARGIN_X,
		version_y + DEBUG_TEXT_LINE_H,
		fmt.ctprintf("%s - %s - %s", VERSION_NAME, VERSION_DATE, VERSION_TIME),
		DEBUG_COLOR_STATE_MUTED,
	)
}

// Reload both game and sand configs
config_reload_all :: proc() {
	game_reloaded := config_reload()
	sand_reloaded := engine.sand_config_reload()
	if game_reloaded || sand_reloaded {
		game_config_post_apply()
		fmt.eprintf("[config] Reloaded\n")
	}
}
