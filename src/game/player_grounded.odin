package game

import "core:math"

player_grounded_init :: proc() {
	player_fsm.handlers[.Grounded] = {
		enter  = player_grounded_enter,
		update = player_grounded_update,
	}
}

player_grounded_enter :: proc(ctx: ^Game_State) {
	ctx.player_wall_run_cooldown_timer = 0
	ctx.player_wall_run_used = false
}

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
// - Dropping: on_platform && down held && jump buffered
// - Airborne: jump buffered (jump)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Run_Vertical: on_side_wall && WALL_RUN held
// - Wall_Run_Horizontal: on_back_wall && WALL_RUN && horizontal input
// - Wall_Run_Vertical: on_back_wall && WALL_RUN (default)
// - Airborne: !on_ground (fell off edge)
player_grounded_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	ctx.player_vel.y = 0
	ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
	if player_sensor.on_slope {
		uphill := math.sign(ctx.player_vel.x) == player_sensor.on_slope_dir
		multipler := PLAYER_SLOPE_UPHILL_FACTOR if uphill else PLAYER_SLOPE_DOWNHILL_FACTOR
		ctx.player_vel.x *= multipler
	}

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
