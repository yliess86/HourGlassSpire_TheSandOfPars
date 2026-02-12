package game

import "core:math"

player_fsm_swimming_init :: proc(player: ^Player) {
	player.fsm.handlers[.Swimming] = {
		enter  = player_fsm_swimming_enter,
		update = player_fsm_swimming_update,
	}
}

player_fsm_swimming_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_cooldown_timer = 0
	ctx.abilities.wall_run_used = false
}

// Swimming — submerged in water. Reduced gravity, directional swimming, velocity damping.
// - Airborne: jump pressed near surface (water_immersion < WATER_SWIM_SURFACE_THRESHOLD)
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground && water_immersion < WATER_SWIM_EXIT_THRESHOLD
// - Airborne: water_immersion < WATER_SWIM_EXIT_THRESHOLD (surfaced)
player_fsm_swimming_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	// Horizontal movement (reduced by water penalty)
	water_factor := max(1.0 - ctx.sensor.water_immersion * WATER_MOVE_PENALTY, 0)
	ctx.transform.vel.x = math.lerp(
		ctx.transform.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * water_factor,
		PLAYER_MOVE_LERP_SPEED * dt,
	)

	// Vertical: up input, down input, or passive float
	if game.input.axis.y > PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			WATER_SWIM_UP_SPEED,
			PLAYER_MOVE_LERP_SPEED * dt,
		)
	} else if game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			-WATER_SWIM_DOWN_SPEED,
			PLAYER_MOVE_LERP_SPEED * dt,
		)
	} else {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			WATER_SWIM_FLOAT_SPEED,
			PLAYER_MOVE_LERP_SPEED * dt,
		)
	}

	// Reduced gravity
	ctx.transform.vel.y -= WATER_SWIM_GRAVITY_MULT * GRAVITY * dt

	// Velocity damping (water resistance)
	damping := math.exp(-WATER_SWIM_DAMPING * dt)
	ctx.transform.vel *= damping

	// Jump out at surface
	if ctx.abilities.jump_buffer_timer > 0 &&
	   ctx.sensor.water_immersion < WATER_SWIM_SURFACE_THRESHOLD {
		ctx.transform.vel.y = WATER_SWIM_JUMP_FORCE
		ctx.abilities.jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground && ctx.sensor.water_immersion < WATER_SWIM_EXIT_THRESHOLD do return .Grounded
	if ctx.sensor.water_immersion < WATER_SWIM_EXIT_THRESHOLD do return .Airborne

	return nil
}
