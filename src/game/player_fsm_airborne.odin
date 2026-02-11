package game

import "core:math"

player_fsm_airborne_init :: proc() {
	player_fsm.handlers[.Airborne] = {
		update = player_fsm_airborne_update,
	}
}

// Airborne — in the air under gravity. Supports coyote jump (stays Airborne) and wall jump (stays Airborne).
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground (landed) AND falling/stationary
// - Wall_Run_Horizontal: on_back_wall && WALL_RUN && horizontal input && !wall_run_used && cooldown ready
// - Wall_Run_Vertical: on_back_wall && WALL_RUN && cooldown ready && !wall_run_used (default)
// - Wall_Slide: on_back_wall && SLIDE held
// - Wall_Run_Vertical: on_side_wall && WALL_RUN && cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: on_side_wall && SLIDE held
player_fsm_airborne_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	if ctx.player_jump_buffer_timer > 0 && ctx.player_coyote_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
	}

	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 do return .Dashing
	if player_sensor.on_ground && ctx.player_vel.y <= 0 {
		ctx.player_vel.y = 0
		return .Grounded
	}

	if player_sensor.on_back_wall {
		if ctx.input.is_down[.WALL_RUN] && math.abs(ctx.input.axis.x) > 0.5 && !ctx.player_wall_run_used && ctx.player_wall_run_cooldown_timer <= 0 do return .Wall_Run_Horizontal
		if ctx.input.is_down[.WALL_RUN] && ctx.player_wall_run_cooldown_timer <= 0 && !ctx.player_wall_run_used do return .Wall_Run_Vertical
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
	}

	if player_sensor.on_side_wall {
		if math.abs(ctx.player_vel.x) > PLAYER_IMPACT_THRESHOLD do player_trigger_impact(math.abs(ctx.player_vel.x), {1, 0})
		if ctx.player_jump_buffer_timer > 0 {
			if player_sensor.on_side_wall {
				offset_x := -EPS * player_sensor.on_side_wall_dir
				ctx.player_pos.x = player_sensor.on_side_wall_snap_x + offset_x
				ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
				ctx.player_vel.x = -player_sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
			}
			ctx.player_jump_buffer_timer = 0
			return nil // stay Airborne with wall-jump velocity
		}
		if ctx.input.is_down[.WALL_RUN] && ctx.player_wall_run_cooldown_timer <= 0 && !ctx.player_wall_run_used && ctx.player_vel.y > 0 do return .Wall_Run_Vertical
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
	}

	return nil
}
