package game

import "core:math"

player_fsm_dashing_init :: proc(player: ^Player) {
	player.fsm.handlers[.Dashing] = {
		enter  = player_fsm_dashing_enter,
		update = player_fsm_dashing_update,
	}
}

player_fsm_dashing_enter :: proc(ctx: ^Player) {
	ctx.abilities.dash_active_timer = PLAYER_DASH_DURATION
	ctx.abilities.dash_cooldown_timer = PLAYER_DASH_COOLDOWN
}

// Dashing — direction-locked horizontal burst. Zero gravity. Transitions on timer expiry.
// - Grounded: timer expired && on_ground
// - Wall_Run_Vertical: timer expired && on_side_wall && WALL_RUN held && cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: timer expired && on_side_wall && SLIDE held
// - Airborne: timer expired (default)
player_fsm_dashing_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	// Timer expired — apply normal movement on expiry frame, then transition
	if ctx.abilities.dash_active_timer <= 0 {
		player_apply_movement(ctx, dt)
		if ctx.sensor.on_ground do return .Grounded
		if ctx.sensor.on_side_wall {
			if math.abs(ctx.transform.vel.x) > PLAYER_IMPACT_THRESHOLD do player_trigger_impact(ctx, math.abs(ctx.transform.vel.x), {1, 0})
			if game.input.is_down[.WALL_RUN] && ctx.abilities.wall_run_cooldown_timer <= 0 && !ctx.abilities.wall_run_used && ctx.transform.vel.y > 0 do return .Wall_Run_Vertical
			if game.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	speed := PLAYER_DASH_SPEED
	if ctx.sensor.on_slope && ctx.abilities.dash_dir == ctx.sensor.on_slope_dir {
		speed *= PLAYER_SLOPE_UPHILL_FACTOR
	}
	ctx.transform.vel.x = ctx.abilities.dash_dir * speed
	ctx.transform.vel.y = 0
	return nil
}
