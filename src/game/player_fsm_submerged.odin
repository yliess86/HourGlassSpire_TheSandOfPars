package game

import sand "../sand"
import "core:math"

player_fsm_submerged_init :: proc(player: ^Player) {
	player.fsm.handlers[.Sand_Swim] = {
		enter  = player_fsm_submerged_enter,
		update = player_fsm_submerged_update,
	}
	player.fsm.handlers[.Swimming] = {
		enter  = player_fsm_submerged_enter,
		update = player_fsm_submerged_update,
	}
}

@(private = "file")
player_fsm_submerged_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_cooldown_timer = 0
	ctx.abilities.wall_run_used = false
}

// Submerged — shared handler for Sand_Swim and Swimming.
// Sand: heavy drag, slow directional movement, sand hop, sand particles.
// Water: reduced gravity, directional swimming, velocity damping.
// - Airborne: jump pressed near surface (immersion < surface threshold)
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground && immersion < exit threshold
// - Airborne: immersion < exit threshold (surfaced)
@(private = "file")
player_fsm_submerged_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	in_sand := ctx.fsm.current == .Sand_Swim

	move_penalty := sand.SAND_SWIM_MOVE_PENALTY if in_sand else sand.WATER_MOVE_PENALTY
	lerp_speed := sand.SAND_SWIM_LERP_SPEED if in_sand else PLAYER_MOVE_LERP_SPEED
	up_speed := sand.SAND_SWIM_UP_SPEED if in_sand else sand.WATER_SWIM_UP_SPEED
	down_speed := sand.SAND_SWIM_DOWN_SPEED if in_sand else sand.WATER_SWIM_DOWN_SPEED
	idle_speed := -sand.SAND_SWIM_SINK_SPEED if in_sand else sand.WATER_SWIM_FLOAT_SPEED
	grav_mult := sand.SAND_SWIM_GRAVITY_MULT if in_sand else sand.WATER_SWIM_GRAVITY_MULT
	damping_k := sand.SAND_SWIM_DAMPING if in_sand else sand.WATER_SWIM_DAMPING
	surface_threshold :=
		sand.SAND_SWIM_SURFACE_THRESHOLD if in_sand else sand.WATER_SWIM_SURFACE_THRESHOLD
	exit_threshold := sand.SAND_SWIM_EXIT_THRESHOLD if in_sand else sand.WATER_SWIM_EXIT_THRESHOLD
	jump_force := sand.SAND_SWIM_JUMP_FORCE if in_sand else sand.WATER_SWIM_JUMP_FORCE
	immersion := ctx.sensor.sand_immersion if in_sand else ctx.sensor.water_immersion

	// Horizontal movement
	move_factor := max(1.0 - immersion * move_penalty, 0)
	ctx.body.vel.x = math.lerp(
		ctx.body.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * move_factor,
		lerp_speed * dt,
	)

	// Vertical: up input, down input, or passive float/sink
	if game.input.axis.y > PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.body.vel.y = math.lerp(ctx.body.vel.y, up_speed, lerp_speed * dt)
	} else if game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.body.vel.y = math.lerp(ctx.body.vel.y, -down_speed, lerp_speed * dt)
	} else {
		ctx.body.vel.y = math.lerp(ctx.body.vel.y, idle_speed, lerp_speed * dt)
	}

	// Reduced gravity + velocity damping
	ctx.body.vel.y -= grav_mult * GRAVITY * dt
	ctx.body.vel *= math.exp(-damping_k * dt)

	// Sand hop — spam jump when deep to boil upward (sand only)
	if in_sand &&
	   game.input.is_pressed[.JUMP] &&
	   ctx.sensor.sand_immersion >= sand.SAND_SWIM_SURFACE_THRESHOLD &&
	   ctx.abilities.sand_hop_cooldown_timer <= 0 {
		ctx.body.vel.y = sand.SAND_SWIM_HOP_FORCE
		ctx.abilities.sand_hop_cooldown_timer = sand.SAND_SWIM_HOP_COOLDOWN
		sand.particles_emit(
			&game.sand_particles,
			ctx.body.pos + {0, PLAYER_SIZE},
			PLAYER_SIZE / 2,
			math.PI / 2,
			math.PI / 3,
			{0, 0},
			sand.SAND_COLOR,
			int(sand.SAND_SWIM_HOP_PARTICLE_COUNT),
		)
	}

	// Jump out near surface
	if ctx.abilities.jump_buffer_timer > 0 && immersion < surface_threshold {
		ctx.body.vel.y = jump_force
		ctx.abilities.jump_buffer_timer = 0
		if in_sand {
			sand.particles_emit(
				&game.sand_particles,
				ctx.body.pos + {0, PLAYER_SIZE},
				PLAYER_SIZE / 2,
				math.PI / 2,
				math.PI / 3,
				{0, abs(ctx.body.vel.y) * sand.SAND_IMPACT_PARTICLE_VEL_BIAS},
				sand.SAND_COLOR,
				int(sand.SAND_SWIM_JUMP_PARTICLE_COUNT),
			)
		}
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground && immersion < exit_threshold do return .Grounded
	if immersion < exit_threshold do return .Airborne

	return nil
}
