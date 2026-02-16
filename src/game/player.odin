package game

import engine "../engine"
import "core:fmt"
import "core:math"

Player_State :: enum u8 {
	Airborne,
	Dashing,
	Dropping,
	Grounded,
	Sand_Swim,
	Swimming,
	Wall_Run_Horizontal,
	Wall_Run_Vertical,
	Wall_Slide,
}

Player_Abilities :: struct {
	dash_dir:                f32,
	dash_active_timer:       f32,
	dash_cooldown_timer:     f32,
	coyote_timer:            f32,
	jump_buffer_timer:       f32,
	wall_run_timer:          f32,
	wall_run_cooldown_timer: f32,
	wall_run_used:           bool,
	wall_run_dir:            f32,
	ground_sticky_timer:     f32,
	sand_hop_cooldown_timer: f32,
	footprint_last_x:        f32,
	footprint_side:          bool,
}

Player_Graphics :: struct {
	visual_look:     [2]f32,
	run_anim_timer:  f32,
	impact_timer:    f32,
	impact_strength: f32,
	impact_axis:     [2]f32,
}

Player :: struct {
	body:           engine.Physics_Body,
	impact_pending: f32, // landing speed, consumed by sand_player_interact
	abilities:      Player_Abilities,
	graphics:       Player_Graphics,
	fsm:            engine.FSM(Player, Player_State),
	sensor:         Player_Sensor,
}

// Perform a wall jump from a side wall. Returns true if jump executed.
player_wall_jump :: proc(ctx: ^Player) -> bool {
	if ctx.abilities.jump_buffer_timer <= 0 || !ctx.sensor.on_side_wall do return false
	ctx.body.pos.x -= ctx.sensor.on_side_wall_dir * EPS
	ctx.body.vel.y = PLAYER_WALL_JUMP_VERTICAL_MULT * PLAYER_JUMP_FORCE
	ctx.body.vel.x = -ctx.sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
	if ctx.sensor.on_sand_wall {
		ctx.body.vel.y *= SAND_WALL_JUMP_MULT
		ctx.body.vel.x *= SAND_WALL_JUMP_MULT
	}
	ctx.abilities.jump_buffer_timer = 0
	wall_pos := [2]f32 {
		ctx.body.pos.x + ctx.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
		ctx.body.pos.y + PLAYER_SIZE / 2,
	}
	player_particles_dust_emit(
		&game.dust,
		wall_pos,
		{-ctx.sensor.on_side_wall_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
		int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
	)
	player_particles_step_emit(&game.steps, wall_pos)
	return true
}

player_move_factor :: proc(ctx: ^Player, sand_penalty, water_penalty: f32) -> f32 {
	sand := max(1.0 - ctx.sensor.sand_immersion * sand_penalty, 0)
	water := max(1.0 - ctx.sensor.water_immersion * water_penalty, 0)
	return max(sand * water, 0)
}

player_init :: proc(player: ^Player) {
	player.body.size = {PLAYER_SIZE, PLAYER_SIZE}
	player.body.offset = {0, PLAYER_SIZE / 2}

	player_fsm_airborne_init(player)
	player_fsm_dashing_init(player)
	player_fsm_dropping_init(player)
	player_fsm_grounded_init(player)
	player_fsm_submerged_init(player)
	player_fsm_wall_run_horizontal_init(player)
	player_fsm_wall_run_vertical_init(player)
	player_fsm_wall_slide_init(player)
	engine.fsm_init(&player.fsm, player, Player_State.Grounded)

	player_sensor_update(player)
}

player_fixed_update :: proc(player: ^Player, dt: f32) {
	player.abilities.dash_active_timer = math.max(0, player.abilities.dash_active_timer - dt)
	player.abilities.dash_cooldown_timer = math.max(0, player.abilities.dash_cooldown_timer - dt)
	player.abilities.coyote_timer = math.max(0, player.abilities.coyote_timer - dt)
	player.abilities.jump_buffer_timer = math.max(0, player.abilities.jump_buffer_timer - dt)
	player.abilities.wall_run_cooldown_timer = math.max(
		0,
		player.abilities.wall_run_cooldown_timer - dt,
	)
	player.abilities.sand_hop_cooldown_timer = math.max(
		0,
		player.abilities.sand_hop_cooldown_timer - dt,
	)
	player.abilities.dash_dir =
		game.input.axis.x != 0 ? math.sign(game.input.axis.x) : player.abilities.dash_dir

	if game.input.is_pressed[.JUMP] do player.abilities.jump_buffer_timer = PLAYER_JUMP_BUFFER_DURATION

	engine.fsm_update(&player.fsm, dt)
	player_physics_update(player, dt)
	player_sensor_update(player)
}

player_debug :: proc(player: ^Player) {
	player_top := game_world_to_screen_point({player.body.pos.x, player.body.pos.y + PLAYER_SIZE})
	player_subti := player_top - {0, DEBUG_TEXT_STATE_GAP}
	player_title := player_subti - {0, DEBUG_TEXT_LINE_H}
	debug_text_center(player_title.x, player_title.y, fmt.ctprintf("%v", player.fsm.current))
	debug_text_center(
		player_subti.x,
		player_subti.y,
		fmt.ctprintf("%v", player.fsm.previous),
		DEBUG_COLOR_STATE_MUTED,
	)
}
