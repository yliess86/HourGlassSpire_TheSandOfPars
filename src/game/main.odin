package game

import engine "../engine"
import "core:fmt"
import sdl "vendor:sdl3"

// Resolution & Scaling
LOGICAL_H :: 480
WINDOW_SCALE :: 1
PPM: f32 : 16 // power of 2 — all pixel/PPM values exact in f32

// Engine
FPS :: 60
FIXED_STEPS :: 4

// Physics (meters, m/s, m/s²)
GRAVITY: f32 : 2_000.0 / PPM
EPS: f32 : 1 / PPM

// Colors
COLOR_BG: [3]u8 : {20, 20, 30}

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
	input:   engine.Input,
	clock:   engine.Clock,

	// Camera & Level
	camera:  engine.Camera,
	level:   Level,

	// Player
	player:  Player,
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
		if game.debug != .NONE do game_render_debug()
		sdl.RenderPresent(game.win.renderer)
		free_all(context.temp_allocator)
	}
}

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
	game.camera = engine.camera_init(f32(game.win.logical_w) / PPM, f32(LOGICAL_H) / PPM, PPM, f32(LOGICAL_H))

	// Player
	game.player.transform.pos = game.level.player_spawn
	game.player.abilities.dash_dir = 1
	player_init(&game.player)
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
}

game_fixed_update :: proc(dt: f32) {
	player_fixed_update(&game.player, dt)
	engine.camera_follow(&game.camera, game.player.collider.pos)
	engine.camera_clamp(&game.camera, {0, 0}, {game.level.world_w, game.level.world_h})
}

game_render :: proc() {
	level_render(&game.level)
	player_render(&game.player)
}

game_render_debug :: proc() {
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)

	level_debug(&game.level)

	sensor_pos: [2]f32 = {DEBUG_TEXT_MARGIN_X, DEBUG_TEXT_MARGIN_Y + 2 * DEBUG_TEXT_LINE_H}
	player_sensor_debug(&game.player, sensor_pos)
	player_physics_debug(&game.player)
	player_debug(&game.player)

	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		DEBUG_TEXT_MARGIN_Y,
		"FPS:",
		fmt.ctprintf("%.0f", 1.0 / game.clock.dt),
	)
}
