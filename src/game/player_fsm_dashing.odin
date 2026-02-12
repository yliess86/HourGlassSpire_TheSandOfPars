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
	player_particles_dust_emit(
		&game.dust,
		ctx.transform.pos + {0, PLAYER_SIZE / 2},
		{-ctx.abilities.dash_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
		5,
	)
}

// Dashing — direction-locked burst. Zero gravity. On slopes: uphill follows 45° angle
// (ramps off slope top preserving upward momentum), downhill lifts off surface and
// dashes horizontally. Transitions on timer expiry.
// - Grounded: timer expired && on_ground
// - Wall_Run_Vertical: timer expired && on_side_wall && WALL_RUN held && cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: timer expired && on_side_wall && SLIDE held
// - Airborne: timer expired (default)
player_fsm_dashing_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	if ctx.abilities.dash_active_timer <= 0 {
		player_physics_apply_movement(ctx, dt)
		if ctx.sensor.on_ground do return .Grounded
		if ctx.sensor.on_side_wall {
			if math.abs(ctx.transform.vel.x) > PLAYER_IMPACT_THRESHOLD do player_graphics_trigger_impact(ctx, math.abs(ctx.transform.vel.x), {1, 0})
			if game.input.is_down[.WALL_RUN] && ctx.abilities.wall_run_cooldown_timer <= 0 && !ctx.abilities.wall_run_used && ctx.transform.vel.y > 0 do return .Wall_Run_Vertical
			if game.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	speed := PLAYER_DASH_SPEED
	sand_factor := max(1.0 - ctx.sensor.sand_immersion * SAND_MOVE_PENALTY, 0)
	speed *= sand_factor
	if ctx.sensor.on_slope {
		uphill := ctx.abilities.dash_dir == ctx.sensor.on_slope_dir
		if uphill {
			speed *= PLAYER_SLOPE_UPHILL_FACTOR
			SLOPE_45 :: 0.70710678
			ctx.transform.vel.x = ctx.abilities.dash_dir * speed * SLOPE_45
			ctx.transform.vel.y = speed * SLOPE_45
		} else {
			ctx.transform.vel.x = ctx.abilities.dash_dir * speed
			ctx.transform.vel.y = EPS // positive prevents slope snap
		}
	} else {
		ctx.transform.vel.x = ctx.abilities.dash_dir * speed
		if ctx.transform.vel.y <= 0 do ctx.transform.vel.y = 0
	}
	return nil
}
