package game

import "core:math"

player_fsm_wall_run_horizontal_init :: proc(player: ^Player) {
	player.fsm.handlers[.Wall_Run_Horizontal] = {
		enter  = player_fsm_wall_run_horizontal_enter,
		update = player_fsm_wall_run_horizontal_update,
	}
}

player_fsm_wall_run_horizontal_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_used = true
	ctx.abilities.wall_run_timer = 0
	ctx.abilities.wall_run_dir = ctx.abilities.dash_dir
}

// Wall_Run_Horizontal — horizontal parabolic arc along a back wall. Direction-locked.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (ran off)
// - Grounded: on_ground (landed) AND falling
// - Airborne: vel.y < -WALL_SLIDE_SPEED (falling fast)
// - Airborne: on_side_wall (hit side wall)
player_fsm_wall_run_horizontal_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	ctx.abilities.wall_run_timer += dt
	combined := player_move_factor(ctx, SAND_WALL_RUN_PENALTY, WATER_MOVE_PENALTY)
	ctx.transform.vel.x = PLAYER_WALL_RUN_HORIZONTAL_SPEED * ctx.abilities.wall_run_dir * combined
	ctx.transform.vel.y =
		PLAYER_WALL_RUN_HORIZONTAL_LIFT * combined -
		GRAVITY * PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT * ctx.abilities.wall_run_timer

	if ctx.sensor.on_sand_wall do sand_wall_erode(&game.sand, ctx)

	if ctx.abilities.jump_buffer_timer > 0 {
		ctx.transform.vel.y = PLAYER_JUMP_FORCE
		if ctx.sensor.on_sand_wall do ctx.transform.vel.y *= SAND_WALL_JUMP_MULT
		ctx.abilities.jump_buffer_timer = 0
		player_particles_step_emit(&game.steps, ctx.transform.pos)
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if !ctx.sensor.on_back_wall do return .Airborne
	if ctx.sensor.on_ground && ctx.transform.vel.y <= 0 do return .Grounded
	if ctx.transform.vel.y < -PLAYER_WALL_SLIDE_SPEED do return .Airborne
	if ctx.sensor.on_side_wall do return .Airborne

	if !game.input.is_down[.WALL_RUN] {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if ctx.sensor.on_side_wall do ctx.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	// Footstep-synced dust trailing behind run direction
	prev := ctx.graphics.run_anim_timer
	fall_speed := max(f32(0), -ctx.transform.vel.y)
	bob_mult := 1.0 + fall_speed / PLAYER_WALL_RUN_HORIZONTAL_LIFT
	ctx.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * bob_mult * dt
	if math.floor(prev / math.PI) != math.floor(ctx.graphics.run_anim_timer / math.PI) {
		player_particles_dust_emit(
			&game.dust,
			ctx.transform.pos,
			{-ctx.abilities.wall_run_dir * PLAYER_PARTICLE_DUST_SPEED_MIN, 0},
			int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
		)
		player_particles_step_emit(&game.steps, ctx.transform.pos)
	}

	return nil
}
