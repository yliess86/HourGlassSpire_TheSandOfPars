package game

import engine "../engine"
import "core:math"

player_apply_movement :: proc(dt: f32) {
	game.player_vel.x = math.lerp(
		game.player_vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED,
		15.0 * dt,
	)
	gravity_mult: f32 = 3.0 if game.player_vel.y > 0 && !game.input.is_down[.JUMP] else 1.0
	game.player_vel.y -= gravity_mult * GRAVITY * dt
}

player_physics_update :: proc(dt: f32) {
	game.player_pos.x += game.player_vel.x * dt
	player_sync_collider()
	player_resolve_slopes()
	player_resolve_x()

	game.player_pos.y += game.player_vel.y * dt
	player_sync_collider()
	player_resolve_y()
	player_resolve_slopes()
}

player_resolve_x :: proc() {
	pc := &game.player_collider

	for c in game.level.side_wall_colliders {
		wall_top := c.pos.y + c.size.y / 2
		player_bottom := pc.pos.y - pc.size.y / 2
		if player_bottom >= wall_top - PLAYER_STEP_HEIGHT + EPS do continue

		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, game.player_vel.x, 0)
		if resolved {
			game.player_pos.x = game.player_collider.pos.x
			game.player_vel.x = 0
		}
	}
}

player_resolve_y :: proc() {
	pc := &game.player_collider

	for c in game.level.ceiling_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, game.player_vel.y, 1)
		if resolved {
			game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
			game.player_vel.y = 0
		}
	}

	if game.player_vel.y > 0 do return

	for c in game.level.ground_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, game.player_vel.y, 1)
		if resolved {
			game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
			game.player_vel.y = 0
		}
	}

	if player_fsm.current != .Dropping {
		for c in game.level.platform_colliders {
			if game.player_pos.y >= c.pos.y + c.size.y / 2 - EPS {
				resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, game.player_vel.y, 1)
				if resolved {
					game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
					game.player_vel.y = 0
				}
			}
		}
	}
}

player_resolve_slopes :: proc() {
	if game.player_vel.y > 0 do return

	found := false
	best_surface_y := f32(-1e18)
	for c in game.level.slope_colliders {
		if game.player_pos.x >= c.base_x && game.player_pos.x <= c.base_x + c.span {
			sy := engine.collider_slope_surface_y(c, game.player_pos.x)
			if sy > best_surface_y {
				best_surface_y = sy
				found = true
			}
		}
	}

	if found {
		dist := game.player_pos.y - best_surface_y
		if dist < 0 {
			game.player_pos.y = best_surface_y
			game.player_vel.y = 0
			player_sync_collider()
		} else {
			is_grounded := player_fsm.current == .Grounded
			snap_dist := 2 * PLAYER_STEP_HEIGHT if is_grounded else PLAYER_SLOPE_SNAP
			if dist <= snap_dist {
				game.player_pos.y = best_surface_y
				game.player_vel.y = 0
				player_sync_collider()
			}
		}
	}
}

player_physics_debug :: proc() {
	if game.debug == .PLAYER || game.debug == .ALL {
		debug_collider_rect(game.player_collider)
		debug_point_player(game.player_pos)

		player_mid_y: [2]f32 = {game.player_pos.x, game.player_pos.y + PLAYER_SIZE / 2}
		player_vel := game.player_vel * PPM * DEBUG_VEL_SCALE
		player_dash_dir: [2]f32 = {game.player_dash_dir * DEBUG_FACING_LENGTH, 0}
		debug_vector(player_mid_y, player_vel, DEBUG_COLOR_VELOCITY)
		debug_vector(player_mid_y, player_dash_dir, DEBUG_COLOR_FACING_DIR)
	}
}
