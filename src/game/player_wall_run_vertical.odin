package game

import "core:math"

player_wall_run_vertical_init :: proc() {
	player_fsm.handlers[.Wall_Run_Vertical] = {update = player_wall_run_vertical_update}
}

// Wall_Run_Vertical — running up a wall (side or back) with exponential speed decay. No gravity.
// Side wall: snaps X, uses WALL_RUN_VERTICAL_SPEED, wall jump away on buffer, coyote on exit.
// Back wall: zeroes X vel, uses WALL_RUN_HORIZONTAL_SPEED, straight-up jump on buffer.
// - Airborne: jump buffered (wall jump if side, straight jump if back)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Slide: speed decayed or released && SLIDE held
// - Airborne: speed decayed or released or detached
// - Grounded: on_ground (landed)
player_wall_run_vertical_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_wall_run_used = true
	ctx.player_wall_run_timer += dt

	base_speed := PLAYER_WALL_RUN_VERTICAL_SPEED if player_sensor.on_side_wall else PLAYER_WALL_RUN_HORIZONTAL_SPEED
	ctx.player_vel.y = base_speed * math.exp(-PLAYER_WALL_RUN_DECAY * ctx.player_wall_run_timer)

	if player_sensor.on_side_wall {
		ctx.player_vel.x = math.lerp(ctx.player_vel.x, ctx.input.axis.x * PLAYER_RUN_SPEED, 15.0 * dt)
		ctx.player_pos.x = player_sensor.on_side_wall_snap_x
		ctx.player_vel.x = 0
	} else {
		ctx.player_vel.x = 0
	}

	if ctx.player_jump_buffer_timer > 0 {
		if player_sensor.on_side_wall {
			ctx.player_pos.x -= player_sensor.on_side_wall_dir * EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = -player_sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
		} else {
			ctx.player_vel.y = PLAYER_JUMP_FORCE
		}
		ctx.player_jump_buffer_timer = 0
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		return .Airborne
	}

	if player_check_dash() {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		return .Dashing
	}

	if ctx.player_vel.y <= PLAYER_WALL_SLIDE_SPEED {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !ctx.input.is_down[.WALL_RUN] {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !player_sensor.on_side_wall && !player_sensor.on_back_wall {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if player_sensor.on_ground {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		return .Grounded
	}

	return nil
}
