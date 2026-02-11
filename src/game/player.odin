package game

import engine "../engine"
import "core:fmt"
import "core:math"

// Player constants (meters, m/s, m/s²)
PLAYER_CHECK_GROUND_EPS: f32 : 2.0 / PPM
PLAYER_CHECK_SIDE_WALL_EPS: f32 : 2.0 / PPM
PLAYER_COYOTE_TIME_DURATION: f32 : 0.1
PLAYER_DASH_COOLDOWN: f32 : 0.75
PLAYER_DASH_DURATION: f32 : 0.15
PLAYER_DASH_SPEED: f32 : 4 * PLAYER_RUN_SPEED
PLAYER_IMPACT_DECAY: f32 : 8.0
PLAYER_IMPACT_FREQ: f32 : 18.0
PLAYER_IMPACT_SCALE: f32 : 0.20
PLAYER_IMPACT_THRESHOLD: f32 : 50.0 / PPM
PLAYER_JUMP_BUFFER_DURATION: f32 : 0.1
PLAYER_JUMP_FORCE: f32 : 700.0 / PPM
PLAYER_LOOK_DEFORM: f32 : 0.15
PLAYER_LOOK_SMOOTH: f32 : 12.0
PLAYER_RUN_BOB_AMPLITUDE: f32 : 0.06
PLAYER_RUN_BOB_SPEED: f32 : 12.0
PLAYER_RUN_SPEED: f32 : 300.0 / PPM
PLAYER_RUN_SPEED_THRESHOLD: f32 : 0.1 * PLAYER_RUN_SPEED
PLAYER_SIZE: f32 : 24.0 / PPM
PLAYER_SLOPE_DOWNHILL_FACTOR: f32 : 1.25
PLAYER_SLOPE_SNAP: f32 : 6.0 / PPM
PLAYER_SLOPE_UPHILL_FACTOR: f32 : 0.75
PLAYER_STEP_HEIGHT: f32 : 6.0 / PPM // Tolerance to step over small obstacles/slope tops
PLAYER_WALL_JUMP_EPS: f32 : 2.0 / PPM
PLAYER_WALL_JUMP_FORCE: f32 : 1.5 * PLAYER_JUMP_FORCE
PLAYER_WALL_RUN_COOLDOWN: f32 : 0.4
PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT: f32 : 0.5
PLAYER_WALL_RUN_HORIZONTAL_LIFT: f32 : 400.0 / PPM
PLAYER_WALL_RUN_HORIZONTAL_SPEED: f32 : 350.0 / PPM
PLAYER_WALL_RUN_VERTICAL_DECAY: f32 : 2.5
PLAYER_WALL_RUN_VERTICAL_SPEED: f32 : 500.0 / PPM
PLAYER_WALL_SLIDE_SPEED: f32 : 100.0 / PPM
PLAYER_COLOR := [Player_State][3]u8 {
	.Airborne            = {80, 200, 255},
	.Dashing             = {255, 50, 200},
	.Dropping            = {180, 100, 255},
	.Grounded            = {0, 150, 255},
	.Wall_Run_Horizontal = {255, 100, 60},
	.Wall_Run_Vertical   = {255, 100, 60},
	.Wall_Slide          = {255, 140, 60},
}

Player_State :: enum u8 {
	Airborne,
	Dashing,
	Dropping,
	Grounded,
	Wall_Run_Horizontal,
	Wall_Run_Vertical,
	Wall_Slide,
}

player_fsm: engine.FSM(Game_State, Player_State)
player_sensor: Player_Sensor

player_sync_collider :: proc() {
	game.player_collider.pos.x = game.player_pos.x
	game.player_collider.pos.y = game.player_pos.y + PLAYER_SIZE / 2
	game.player_collider.size = {PLAYER_SIZE, PLAYER_SIZE}
}

player_init :: proc() {
	player_fsm_airborne_init()
	player_fsm_dashing_init()
	player_fsm_dropping_init()
	player_fsm_grounded_init()
	player_fsm_wall_run_horizontal_init()
	player_fsm_wall_run_vertical_init()
	player_fsm_wall_slide_init()
	engine.fsm_init(&player_fsm, &game, Player_State.Grounded)

	player_sync_collider()
	player_sensor_update()
}

player_fixed_update :: proc(dt: f32) {
	game.player_dash_active_timer = math.max(0, game.player_dash_active_timer - dt)
	game.player_dash_cooldown_timer = math.max(0, game.player_dash_cooldown_timer - dt)
	game.player_coyote_timer = math.max(0, game.player_coyote_timer - dt)
	game.player_jump_buffer_timer = math.max(0, game.player_jump_buffer_timer - dt)
	game.player_wall_run_cooldown_timer = math.max(0, game.player_wall_run_cooldown_timer - dt)
	game.player_dash_dir =
		game.input.axis.x != 0 ? math.sign(game.input.axis.x) : game.player_dash_dir

	if game.input.is_pressed[.JUMP] do game.player_jump_buffer_timer = PLAYER_JUMP_BUFFER_DURATION

	engine.fsm_update(&player_fsm, dt)
	player_physics_update(dt)
	player_sensor_update()
}

player_debug :: proc() {
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
}
