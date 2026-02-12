package game

import "core:math"

player_fsm_grounded_init :: proc(player: ^Player) {
	player.fsm.handlers[.Grounded] = {
		enter  = player_fsm_grounded_enter,
		update = player_fsm_grounded_update,
	}
}

player_fsm_grounded_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_cooldown_timer = 0
	ctx.abilities.wall_run_used = false
	if ctx.sensor.on_ground {
		ctx.transform.pos.y = ctx.sensor.on_ground_snap_y
		player_sync_collider(ctx)
	}
	player_particles_dust_emit(&game.dust, ctx.transform.pos, {0, 0}, 6)
}

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
// - Dropping: on_platform && down held && jump buffered
// - Airborne: jump buffered (jump)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Run_Vertical: on_side_wall && WALL_RUN held
// - Wall_Run_Horizontal: on_back_wall && WALL_RUN && horizontal input
// - Wall_Run_Vertical: on_back_wall && WALL_RUN (default)
// - Airborne: !on_ground (fell off edge)
player_fsm_grounded_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	prev := ctx.graphics.run_anim_timer
	if math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD {
		ctx.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * dt
		if math.floor(prev / math.PI) != math.floor(ctx.graphics.run_anim_timer / math.PI) {
			player_particles_dust_emit(&game.dust, ctx.transform.pos, {0, 0}, 2)
		}
	} else do ctx.graphics.run_anim_timer = 0

	speed_factor: f32 = 1.0
	if ctx.sensor.on_slope {
		uphill := math.sign(game.input.axis.x) == ctx.sensor.on_slope_dir
		speed_factor = PLAYER_SLOPE_UPHILL_FACTOR if uphill else PLAYER_SLOPE_DOWNHILL_FACTOR
	}
	sand_move_factor: f32 = 1.0 - ctx.sensor.sand_immersion * SAND_MOVE_PENALTY
	water_move_factor: f32 = 1.0 - ctx.sensor.water_immersion * WATER_MOVE_PENALTY
	combined_move := max(sand_move_factor * water_move_factor, 0)
	ctx.transform.vel.x = math.lerp(
		ctx.transform.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * speed_factor * combined_move,
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	ctx.transform.vel.y = -SAND_SINK_SPEED if ctx.sensor.on_sand else 0
	ctx.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION

	if ctx.sensor.water_immersion > WATER_SWIM_ENTER_THRESHOLD do return .Swimming

	if ctx.sensor.on_platform &&
	   game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD &&
	   ctx.abilities.jump_buffer_timer > 0 {
		ctx.transform.pos.y -= PLAYER_DROP_NUDGE
		ctx.abilities.jump_buffer_timer = 0
		ctx.abilities.coyote_timer = 0
		return .Dropping
	}

	if ctx.abilities.jump_buffer_timer > 0 {
		sand_jump := 1.0 - ctx.sensor.sand_immersion * SAND_JUMP_PENALTY
		water_jump := 1.0 - ctx.sensor.water_immersion * WATER_JUMP_PENALTY
		jump_factor := max(sand_jump * water_jump, 0)
		if jump_factor > 0 {
			ctx.transform.vel.y = PLAYER_JUMP_FORCE * jump_factor
			ctx.abilities.jump_buffer_timer = 0
			ctx.abilities.coyote_timer = 0
			player_particles_dust_emit(
				&game.dust,
				ctx.transform.pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MAX},
				4,
			)
			return .Airborne
		}
		ctx.abilities.jump_buffer_timer = 0
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_side_wall && game.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if ctx.sensor.on_back_wall && game.input.is_down[.WALL_RUN] && math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD do return .Wall_Run_Horizontal
	if ctx.sensor.on_back_wall && game.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if !ctx.sensor.on_ground do return .Airborne

	return nil
}
