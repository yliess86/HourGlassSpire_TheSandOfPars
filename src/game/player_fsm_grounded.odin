package game

import "core:math"

player_fsm_grounded_init :: proc() {
	player_fsm.handlers[.Grounded] = {
		enter  = player_fsm_grounded_enter,
		update = player_fsm_grounded_update,
	}
}

player_fsm_grounded_enter :: proc(ctx: ^Game_State) {
	ctx.player_wall_run_cooldown_timer = 0
	ctx.player_wall_run_used = false
	if player_sensor.on_ground {
		ctx.player_pos.y = player_sensor.on_ground_snap_y
		player_sync_collider()
	}
}

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
// - Dropping: on_platform && down held && jump buffered
// - Airborne: jump buffered (jump)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Run_Vertical: on_side_wall && WALL_RUN held
// - Wall_Run_Horizontal: on_back_wall && WALL_RUN && horizontal input
// - Wall_Run_Vertical: on_back_wall && WALL_RUN (default)
// - Airborne: !on_ground (fell off edge)
player_fsm_grounded_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	speed_factor: f32 = 1.0
	if player_sensor.on_slope {
		uphill := math.sign(ctx.input.axis.x) == player_sensor.on_slope_dir
		speed_factor = PLAYER_SLOPE_UPHILL_FACTOR if uphill else PLAYER_SLOPE_DOWNHILL_FACTOR
	}
	ctx.player_vel.x = math.lerp(
		ctx.player_vel.x,
		ctx.input.axis.x * PLAYER_RUN_SPEED * speed_factor,
		15.0 * dt,
	)
	ctx.player_vel.y = 0
	ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION

	if player_sensor.on_platform && ctx.input.axis.y < -0.5 && ctx.player_jump_buffer_timer > 0 {
		ctx.player_pos.y -= 2.0 / PPM
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		return .Dropping
	}

	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 do return .Dashing
	if player_sensor.on_side_wall && ctx.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if player_sensor.on_back_wall && ctx.input.is_down[.WALL_RUN] && math.abs(ctx.input.axis.x) > 0.5 do return .Wall_Run_Horizontal
	if player_sensor.on_back_wall && ctx.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if !player_sensor.on_ground do return .Airborne

	return nil
}
