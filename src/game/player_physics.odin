package game

import engine "../engine"
import sand "../sand"
import "core:math"

player_physics_apply_movement :: proc(player: ^Player, dt: f32) {
	player.body.vel.x = math.lerp(
		player.body.vel.x,
		game.input.axis.x *
		PLAYER_RUN_SPEED *
		player_move_factor(player, sand.SAND_MOVE_PENALTY, 0),
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	gravity_mult: f32 =
		PLAYER_FAST_FALL_MULT if player.body.vel.y > 0 && !game.input.is_down[.JUMP] else 1.0
	player.body.vel.y -= gravity_mult * GRAVITY * dt
}

player_physics_update :: proc(player: ^Player, dt: f32) {
	player.body.flags = {}
	if player.fsm.current == .Dropping do player.body.flags += {.Dropping}
	if player.fsm.current == .Grounded do player.body.flags += {.Grounded}

	geom := engine.Physics_Static_Geometry {
		ground    = game.level.ground_colliders[:],
		ceiling   = game.level.ceiling_colliders[:],
		walls     = game.level.side_wall_colliders[:],
		platforms = game.level.platform_colliders[:],
		slopes    = game.level.slope_colliders[:],
	}

	cfg := engine.Physics_Solve_Config {
		step_height = PLAYER_STEP_HEIGHT,
		sweep_skin  = PLAYER_SWEEP_SKIN,
		slope_snap  = PLAYER_SLOPE_SNAP,
		eps         = EPS,
	}

	engine.physics_solve(&player.body, geom, cfg, dt)
}

player_physics_debug :: proc(player: ^Player) {
	if game.debug == .PLAYER || game.debug == .ALL {
		rect := engine.physics_body_rect(&player.body)
		debug_collider_rect(rect)
		debug_point(player.body.pos, DEBUG_COLOR_PLAYER)

		player_mid_y: [2]f32 = {player.body.pos.x, player.body.pos.y + PLAYER_SIZE / 2}
		player_vel := player.body.vel * PPM * DEBUG_VEL_SCALE
		player_dash_dir: [2]f32 = {player.abilities.dash_dir * DEBUG_FACING_LENGTH, 0}
		debug_vector(player_mid_y, player_vel, DEBUG_COLOR_VELOCITY)
		debug_vector(player_mid_y, player_dash_dir, DEBUG_COLOR_FACING_DIR)
	}
}
