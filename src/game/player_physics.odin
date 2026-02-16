package game

import physics "../physics"
import "core:math"

player_physics_apply_movement :: proc(player: ^Player, dt: f32) {
	player.transform.vel.x = math.lerp(
		player.transform.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * player_move_factor(player, SAND_MOVE_PENALTY, 0),
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	gravity_mult: f32 =
		PLAYER_FAST_FALL_MULT if player.transform.vel.y > 0 && !game.input.is_down[.JUMP] else 1.0
	player.transform.vel.y -= gravity_mult * GRAVITY * dt
}

player_physics_update :: proc(player: ^Player, dt: f32) {
	body := physics.Body {
		pos    = player.transform.pos,
		vel    = player.transform.vel,
		size   = {PLAYER_SIZE, PLAYER_SIZE},
		offset = {0, PLAYER_SIZE / 2},
	}
	if player.fsm.current == .Dropping do body.flags += {.Dropping}
	if player.fsm.current == .Grounded do body.flags += {.Grounded}

	geom := physics.Static_Geometry {
		ground    = game.level.ground_colliders[:],
		ceiling   = game.level.ceiling_colliders[:],
		walls     = game.level.side_wall_colliders[:],
		platforms = game.level.platform_colliders[:],
		slopes    = game.level.slope_colliders[:],
	}

	cfg := physics.Solve_Config {
		step_height = PLAYER_STEP_HEIGHT,
		sweep_skin  = PLAYER_SWEEP_SKIN,
		slope_snap  = PLAYER_SLOPE_SNAP,
		eps         = EPS,
	}

	physics.solve(&body, geom, cfg, dt)

	player.transform.pos = body.pos
	player.transform.vel = body.vel
	player_sync_collider(player)
}

player_physics_debug :: proc(player: ^Player) {
	if game.debug == .PLAYER || game.debug == .ALL {
		debug_collider_rect(player.collider)
		debug_point(player.transform.pos, DEBUG_COLOR_PLAYER)

		player_mid_y: [2]f32 = {player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE / 2}
		player_vel := player.transform.vel * PPM * DEBUG_VEL_SCALE
		player_dash_dir: [2]f32 = {player.abilities.dash_dir * DEBUG_FACING_LENGTH, 0}
		debug_vector(player_mid_y, player_vel, DEBUG_COLOR_VELOCITY)
		debug_vector(player_mid_y, player_dash_dir, DEBUG_COLOR_FACING_DIR)
	}
}
