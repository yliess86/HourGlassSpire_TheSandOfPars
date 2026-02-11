package game

import "core:math"

player_fsm_wall_run_vertical_init :: proc() {
	player_fsm.handlers[.Wall_Run_Vertical] = {
		enter  = player_fsm_wall_run_vertical_enter,
		update = player_fsm_wall_run_vertical_update,
		exit   = player_fsm_wall_run_vertical_exit,
	}
}

player_fsm_wall_run_vertical_enter :: proc(ctx: ^Game_State) {
	ctx.player_wall_run_used = true
	ctx.player_wall_run_timer = 0
}

player_fsm_wall_run_vertical_exit :: proc(ctx: ^Game_State) {
	ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
}

// Wall_Run_Vertical — running up a wall (side or back) with exponential speed decay. No gravity.
// Side wall: snaps X, uses WALL_RUN_VERTICAL_SPEED, wall jump away on buffer, coyote on exit.
// Back wall: zeroes X vel, uses WALL_RUN_HORIZONTAL_SPEED, straight-up jump on buffer.
// - Airborne: jump buffered (wall jump if side, straight jump if back)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Slide: speed decayed or released && SLIDE held
// - Airborne: speed decayed or released or detached
// - Grounded: on_ground (landed) AND falling
player_fsm_wall_run_vertical_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_wall_run_timer += dt

	speed := PLAYER_WALL_RUN_VERTICAL_SPEED
	decay := PLAYER_WALL_RUN_VERTICAL_DECAY
	ctx.player_vel.y = speed * math.exp(-decay * ctx.player_wall_run_timer)
	ctx.player_vel.x = 0

	if player_sensor.on_side_wall {
		ctx.player_vel.x = math.lerp(
			ctx.player_vel.x,
			ctx.input.axis.x * PLAYER_RUN_SPEED,
			15.0 * dt,
		)
		ctx.player_pos.x = player_sensor.on_side_wall_snap_x
	}

	if ctx.player_jump_buffer_timer > 0 {
		if player_sensor.on_side_wall {
			ctx.player_pos.x -= player_sensor.on_side_wall_dir * EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = -player_sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
		} else do ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 do return .Dashing

	if ctx.player_vel.y <= PLAYER_WALL_SLIDE_SPEED {
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !ctx.input.is_down[.WALL_RUN] {
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !player_sensor.on_side_wall && !player_sensor.on_back_wall do return .Airborne
	if player_sensor.on_ground && ctx.player_vel.y <= 0 do return .Grounded

	return nil
}
