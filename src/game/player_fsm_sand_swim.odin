package game

import "core:math"

player_fsm_sand_swim_init :: proc(player: ^Player) {
	player.fsm.handlers[.Sand_Swim] = {
		enter  = player_fsm_sand_swim_enter,
		update = player_fsm_sand_swim_update,
	}
}

player_fsm_sand_swim_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_cooldown_timer = 0
	ctx.abilities.wall_run_used = false
}

// Sand_Swim — submerged in sand. Heavy drag, slow directional movement, can climb out.
// - Airborne: jump pressed near surface (sand_immersion < SAND_SWIM_SURFACE_THRESHOLD)
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground && sand_immersion < SAND_SWIM_EXIT_THRESHOLD
// - Airborne: sand_immersion < SAND_SWIM_EXIT_THRESHOLD (surfaced)
player_fsm_sand_swim_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	// Horizontal movement (reduced by sand penalty)
	sand_factor := max(1.0 - ctx.sensor.sand_immersion * SAND_SWIM_MOVE_PENALTY, 0)
	ctx.transform.vel.x = math.lerp(
		ctx.transform.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * sand_factor,
		SAND_SWIM_LERP_SPEED * dt,
	)

	// Vertical: up input, down input, or passive sink
	if game.input.axis.y > PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			SAND_SWIM_UP_SPEED,
			SAND_SWIM_LERP_SPEED * dt,
		)
	} else if game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			-SAND_SWIM_DOWN_SPEED,
			SAND_SWIM_LERP_SPEED * dt,
		)
	} else {
		ctx.transform.vel.y = math.lerp(
			ctx.transform.vel.y,
			-SAND_SWIM_SINK_SPEED,
			SAND_SWIM_LERP_SPEED * dt,
		)
	}

	// Reduced gravity
	ctx.transform.vel.y -= SAND_SWIM_GRAVITY_MULT * GRAVITY * dt

	// Velocity damping (sand resistance)
	damping := math.exp(-SAND_SWIM_DAMPING * dt)
	ctx.transform.vel *= damping

	// Sand hop — spam jump when deep to boil upward
	if game.input.is_pressed[.JUMP] &&
	   ctx.sensor.sand_immersion >= SAND_SWIM_SURFACE_THRESHOLD &&
	   ctx.abilities.sand_hop_cooldown_timer <= 0 {
		ctx.transform.vel.y = SAND_SWIM_HOP_FORCE
		ctx.abilities.sand_hop_cooldown_timer = SAND_SWIM_HOP_COOLDOWN
		sand_particles_emit(
			&game.sand_particles,
			ctx.transform.pos + {0, PLAYER_SIZE},
			PLAYER_SIZE / 2,
			math.PI / 2,
			math.PI / 3,
			{0, 0},
			SAND_COLOR,
			int(SAND_SWIM_HOP_PARTICLE_COUNT),
		)
	}

	// Jump out near surface
	if ctx.abilities.jump_buffer_timer > 0 &&
	   ctx.sensor.sand_immersion < SAND_SWIM_SURFACE_THRESHOLD {
		ctx.transform.vel.y = SAND_SWIM_JUMP_FORCE
		ctx.abilities.jump_buffer_timer = 0
		sand_particles_emit(
			&game.sand_particles,
			ctx.transform.pos + {0, PLAYER_SIZE},
			PLAYER_SIZE / 2,
			math.PI / 2,
			math.PI / 3,
			{0, abs(ctx.transform.vel.y) * 0.15},
			SAND_COLOR,
			int(SAND_SWIM_JUMP_PARTICLE_COUNT),
		)
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground && ctx.sensor.sand_immersion < SAND_SWIM_EXIT_THRESHOLD do return .Grounded
	if ctx.sensor.sand_immersion < SAND_SWIM_EXIT_THRESHOLD do return .Airborne

	return nil
}
