package game

import engine "../engine"
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

player_physics_sweep_x :: proc(player: ^Player, dt: f32) -> f32 {
	delta_x := player.transform.vel.x * dt
	if delta_x == 0 do return 0

	dir_x: f32 = math.sign(delta_x)
	pc := player.collider
	origin: [2]f32 = {pc.pos.x + dir_x * pc.size.x / 2, pc.pos.y}
	travel := math.abs(delta_x)
	nearest: f32 = travel

	for c in game.level.side_wall_colliders {
		wall_top := c.pos.y + c.size.y / 2
		player_bottom := pc.pos.y - pc.size.y / 2
		if player_bottom >= wall_top - PLAYER_STEP_HEIGHT + EPS do continue

		hit := engine.collider_raycast_rect(origin, 0, dir_x, travel, c, pc.size.y / 2)
		if hit.hit && hit.distance < nearest {
			nearest = hit.distance
		}
	}

	safe := nearest - PLAYER_SWEEP_SKIN if nearest < travel else travel
	return dir_x * math.max(safe, 0)
}

player_physics_sweep_y :: proc(player: ^Player, dt: f32) -> f32 {
	delta_y := player.transform.vel.y * dt
	if delta_y == 0 do return 0

	dir_y: f32 = math.sign(delta_y)
	pc := player.collider
	origin: [2]f32 = {pc.pos.x, pc.pos.y + dir_y * pc.size.y / 2}
	travel := math.abs(delta_y)
	nearest: f32 = travel

	// Ceiling (moving up)
	if delta_y > 0 {
		for c in game.level.ceiling_colliders {
			hit := engine.collider_raycast_rect(origin, 1, dir_y, travel, c, pc.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	// Ground (moving down)
	if delta_y < 0 {
		for c in game.level.ground_colliders {
			hit := engine.collider_raycast_rect(origin, 1, dir_y, travel, c, pc.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	// Platforms (moving down, not Dropping, player above platform)
	if delta_y < 0 && player.fsm.current != .Dropping {
		for c in game.level.platform_colliders {
			if player.transform.pos.y >= c.pos.y + c.size.y / 2 - EPS {
				hit := engine.collider_raycast_rect(origin, 1, dir_y, travel, c, pc.size.x / 2)
				if hit.hit && hit.distance < nearest {
					nearest = hit.distance
				}
			}
		}
	}

	safe := nearest - PLAYER_SWEEP_SKIN if nearest < travel else travel
	return dir_y * math.max(safe, 0)
}

player_physics_update :: proc(player: ^Player, dt: f32) {
	player_sync_collider(player)

	player.transform.pos.x += player_physics_sweep_x(player, dt)
	player_sync_collider(player)
	player_physics_resolve_slopes(player)
	player_physics_resolve_x(player)

	player.transform.pos.y += player_physics_sweep_y(player, dt)
	player_sync_collider(player)
	player_physics_resolve_y(player)
	player_physics_resolve_slopes(player)
}

player_physics_resolve_x :: proc(player: ^Player) {
	pc := &player.collider

	for c in game.level.side_wall_colliders {
		wall_top := c.pos.y + c.size.y / 2
		player_bottom := pc.pos.y - pc.size.y / 2
		if player_bottom >= wall_top - PLAYER_STEP_HEIGHT + EPS do continue

		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, player.transform.vel.x, 0)
		if resolved {
			player.transform.pos.x = player.collider.pos.x
			player.transform.vel.x = 0
		}
	}
}

player_physics_resolve_y :: proc(player: ^Player) {
	pc := &player.collider

	for c in game.level.ceiling_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, player.transform.vel.y, 1)
		if resolved {
			player.transform.pos.y = player.collider.pos.y - PLAYER_SIZE / 2
			player.transform.vel.y = 0
		}
	}

	if player.transform.vel.y > 0 do return

	for c in game.level.ground_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(pc, c, player.transform.vel.y, 1)
		if resolved {
			player.transform.pos.y = player.collider.pos.y - PLAYER_SIZE / 2
			player.transform.vel.y = 0
		}
	}

	if player.fsm.current != .Dropping {
		for c in game.level.platform_colliders {
			if player.transform.pos.y >= c.pos.y + c.size.y / 2 - EPS {
				resolved, _ := engine.collider_resolve_dynamic_rect(
					pc,
					c,
					player.transform.vel.y,
					1,
				)
				if resolved {
					player.transform.pos.y = player.collider.pos.y - PLAYER_SIZE / 2
					player.transform.vel.y = 0
				}
			}
		}
	}
}

player_physics_resolve_slopes :: proc(player: ^Player) {
	found_floor := false
	best_floor_y := f32(-1e18)
	for c in game.level.slope_colliders {
		if !engine.collider_slope_is_floor(c) do continue
		if player.transform.pos.x >= c.base_x && player.transform.pos.x <= c.base_x + c.span {
			sy := engine.collider_slope_surface_y(c, player.transform.pos.x)
			if sy > best_floor_y {
				best_floor_y = sy
				found_floor = true
			}
		}
	}

	if found_floor {
		dist := player.transform.pos.y - best_floor_y
		if dist < 0 {
			player.transform.pos.y = best_floor_y
			player.transform.vel.y = math.max(player.transform.vel.y, 0)
			player_sync_collider(player)
		} else if player.transform.vel.y <= 0 {
			is_grounded := player.fsm.current == .Grounded
			snap_dist := 2 * PLAYER_STEP_HEIGHT if is_grounded else PLAYER_SLOPE_SNAP
			if dist <= snap_dist {
				player.transform.pos.y = best_floor_y
				player.transform.vel.y = 0
				player_sync_collider(player)
			}
		}
	}

	player_top := player.transform.pos.y + PLAYER_SIZE
	for c in game.level.slope_colliders {
		if engine.collider_slope_is_floor(c) do continue
		if player.transform.pos.x >= c.base_x && player.transform.pos.x <= c.base_x + c.span {
			sy := engine.collider_slope_surface_y(c, player.transform.pos.x)
			if player_top > sy {
				player.transform.pos.y = sy - PLAYER_SIZE
				if player.transform.vel.y > 0 {
					player.transform.vel.y = 0
				}
				player_sync_collider(player)
			}
		}
	}
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
