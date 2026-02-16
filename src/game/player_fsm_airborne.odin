package game

import sand "../sand"
import "core:math"

player_fsm_airborne_init :: proc(player: ^Player) {
	player.fsm.handlers[.Airborne] = {
		update = player_fsm_airborne_update,
	}
}

// Airborne — in the air under gravity. Supports coyote jump (stays Airborne) and wall jump (stays Airborne).
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground (landed) AND falling/stationary
// - Sand_Swim: sand_immersion > SAND_SWIM_ENTER_THRESHOLD
// - Wall_Run_Horizontal: on_back_wall && WALL_RUN && horizontal input && !wall_run_used && cooldown ready
// - Wall_Run_Vertical: on_back_wall && WALL_RUN && cooldown ready && !wall_run_used (default)
// - Wall_Slide: on_back_wall && SLIDE held
// - Wall_Run_Vertical: on_side_wall && WALL_RUN && cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: on_side_wall && SLIDE held
player_fsm_airborne_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(ctx, dt)

	if ctx.abilities.jump_buffer_timer > 0 && ctx.abilities.coyote_timer > 0 {
		ctx.body.vel.y = PLAYER_JUMP_FORCE
		ctx.abilities.jump_buffer_timer = 0
		ctx.abilities.coyote_timer = 0
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground && ctx.body.vel.y <= 0 {
		ctx.body.vel.y = 0
		return .Grounded
	}
	if ctx.sensor.sand_immersion > sand.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
	if ctx.sensor.water_immersion > sand.WATER_SWIM_ENTER_THRESHOLD do return .Swimming

	if ctx.sensor.on_back_wall {
		if game.input.is_down[.WALL_RUN] && math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD && !(ctx.sensor.on_slope && math.sign(game.input.axis.x) == ctx.sensor.on_slope_dir) && !ctx.abilities.wall_run_used && ctx.abilities.wall_run_cooldown_timer <= 0 do return .Wall_Run_Horizontal
		if game.input.is_down[.WALL_RUN] && ctx.abilities.wall_run_cooldown_timer <= 0 && !ctx.abilities.wall_run_used do return .Wall_Run_Vertical
		if game.input.is_down[.SLIDE] do return .Wall_Slide
	}

	if ctx.sensor.on_side_wall {
		if math.abs(ctx.body.vel.x) > PLAYER_IMPACT_THRESHOLD do player_graphics_trigger_impact(ctx, math.abs(ctx.body.vel.x), {1, 0})
		if ctx.abilities.jump_buffer_timer > 0 {
			if ctx.sensor.on_side_wall {
				offset_x := -EPS * ctx.sensor.on_side_wall_dir
				ctx.body.pos.x = ctx.sensor.on_side_wall_snap_x + offset_x
				ctx.body.vel.y = PLAYER_WALL_JUMP_VERTICAL_MULT * PLAYER_JUMP_FORCE
				ctx.body.vel.x = -ctx.sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
				wall_pos := [2]f32 {
					ctx.body.pos.x + ctx.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
					ctx.body.pos.y + PLAYER_SIZE / 2,
				}
				player_particles_dust_emit(
					&game.dust,
					wall_pos,
					{-ctx.sensor.on_side_wall_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
					int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
				)
			}
			ctx.abilities.jump_buffer_timer = 0
			return nil
		}
		if game.input.is_down[.WALL_RUN] && ctx.abilities.wall_run_cooldown_timer <= 0 && !ctx.abilities.wall_run_used && ctx.body.vel.y > 0 do return .Wall_Run_Vertical
		if game.input.is_down[.SLIDE] do return .Wall_Slide
	}

	return nil
}
