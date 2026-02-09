package game

import "core:math"

player_dashing_init :: proc() {
	player_fsm.handlers[.Dashing] = {
		enter  = player_dashing_enter,
		update = player_dashing_update,
	}
}

player_dashing_enter :: proc(ctx: ^Game_State) {
	ctx.player_dash_active_timer = PLAYER_DASH_DURATION
	ctx.player_dash_cooldown_timer = PLAYER_DASH_COOLDOWN
}

// Dashing — direction-locked horizontal burst. Zero gravity. Transitions on timer expiry.
// - Grounded: timer expired && on_ground
// - Wall_Run_Vertical: timer expired && on_side_wall && WALL_RUN held && cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: timer expired && on_side_wall && SLIDE held
// - Airborne: timer expired (default)
player_dashing_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	// Timer expired — apply normal movement on expiry frame, then transition
	if ctx.player_dash_active_timer <= 0 {
		player_apply_movement(dt)
		if player_sensor.on_ground do return .Grounded
		if player_sensor.on_side_wall {
			if math.abs(ctx.player_vel.x) > PLAYER_IMPACT_THRESHOLD do player_trigger_impact(math.abs(ctx.player_vel.x), {1, 0})
			if ctx.input.is_down[.WALL_RUN] && ctx.player_wall_run_cooldown_timer <= 0 && !ctx.player_wall_run_used && ctx.player_vel.y > 0 do return .Wall_Run_Vertical
			if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	ctx.player_vel.x = ctx.player_dash_dir * PLAYER_DASH_SPEED
	ctx.player_vel.y = 0
	return nil
}
