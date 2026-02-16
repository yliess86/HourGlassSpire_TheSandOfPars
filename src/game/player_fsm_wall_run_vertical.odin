package game

import sand "../sand"
import "core:math"

player_fsm_wall_run_vertical_init :: proc(player: ^Player) {
	player.fsm.handlers[.Wall_Run_Vertical] = {
		enter  = player_fsm_wall_run_vertical_enter,
		update = player_fsm_wall_run_vertical_update,
		exit   = player_fsm_wall_run_vertical_exit,
	}
}

player_fsm_wall_run_vertical_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_used = true
	ctx.abilities.wall_run_timer = 0
}

player_fsm_wall_run_vertical_exit :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
}

// Wall_Run_Vertical — running up a wall (side or back) with exponential speed decay. No gravity.
// Side wall: snaps X, uses WALL_RUN_VERTICAL_SPEED, wall jump away on buffer, coyote on exit.
// Back wall: zeroes X vel, uses WALL_RUN_HORIZONTAL_SPEED, straight-up jump on buffer.
// - Airborne: jump buffered (wall jump if side, straight jump if back)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Slide: speed decayed or released && SLIDE held
// - Airborne: speed decayed or released or detached
// - Grounded: on_ground (landed) AND falling
player_fsm_wall_run_vertical_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	ctx.abilities.wall_run_timer += dt

	speed := PLAYER_WALL_RUN_VERTICAL_SPEED
	decay := PLAYER_WALL_RUN_VERTICAL_DECAY
	combined := player_move_factor(ctx, sand.SAND_WALL_RUN_PENALTY, sand.WATER_MOVE_PENALTY)
	ctx.body.vel.y = speed * combined * math.exp(-decay * ctx.abilities.wall_run_timer)
	ctx.body.vel.x = 0

	if ctx.sensor.on_side_wall {
		ctx.body.vel.x = math.lerp(
			ctx.body.vel.x,
			game.input.axis.x * PLAYER_RUN_SPEED,
			PLAYER_MOVE_LERP_SPEED * dt,
		)
		ctx.body.pos.x = ctx.sensor.on_side_wall_snap_x
	}

	if ctx.sensor.on_sand_wall do sand.wall_erode(&game.sand_world, ctx.body.pos, PLAYER_SIZE, ctx.sensor.on_side_wall_dir)

	if player_wall_jump(ctx) do return .Airborne
	if ctx.abilities.jump_buffer_timer > 0 {
		// Back wall: straight-up jump
		ctx.body.vel.y = PLAYER_JUMP_FORCE
		if ctx.sensor.on_sand_wall do ctx.body.vel.y *= sand.SAND_WALL_JUMP_MULT
		ctx.abilities.jump_buffer_timer = 0
		player_particles_dust_emit(
			&game.dust,
			ctx.body.pos,
			{0, -PLAYER_PARTICLE_DUST_SPEED_MAX},
			int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
		)
		player_particles_step_emit(&game.steps, ctx.body.pos)
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing

	if ctx.body.vel.y <= PLAYER_WALL_SLIDE_SPEED {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if ctx.sensor.on_side_wall do ctx.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !game.input.is_down[.WALL_RUN] {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if ctx.sensor.on_side_wall do ctx.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !ctx.sensor.on_side_wall && !ctx.sensor.on_back_wall do return .Airborne
	if ctx.sensor.on_ground && ctx.body.vel.y <= 0 do return .Grounded

	// Footstep-synced dust while running on wall
	prev := ctx.graphics.run_anim_timer
	ctx.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * dt
	if math.floor(prev / math.PI) != math.floor(ctx.graphics.run_anim_timer / math.PI) {
		if ctx.sensor.on_side_wall {
			wall_pos := [2]f32 {
				ctx.body.pos.x + ctx.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
				ctx.body.pos.y,
			}
			player_particles_dust_emit(
				&game.dust,
				wall_pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_particles_step_emit(&game.steps, wall_pos)
		} else {
			player_particles_dust_emit(
				&game.dust,
				ctx.body.pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_particles_step_emit(&game.steps, ctx.body.pos)
		}
	}

	return nil
}
