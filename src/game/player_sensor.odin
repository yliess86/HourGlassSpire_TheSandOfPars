package game

import engine "../engine"
import "core:fmt"

Player_Sensor :: struct {
	in_platform:          bool, // overlapping any platform (for Dropping exit)
	on_back_wall:         bool, // overlapping a back wall collider
	on_ground:            bool, // any upward surface (ground + platform + slope)
	on_ground_snap_y:     f32, // surface Y of detected ground (for snapping on land)
	on_platform:          bool, // surface is a platform (for drop-through)
	on_sand:              bool, // standing on sand surface (sand is the ground)
	sand_immersion:       f32, // 0.0 (free) to 1.0 (buried)
	on_water:             bool, // overlapping water cells (informational, does not count as ground)
	water_immersion:      f32, // 0.0 (free) to 1.0 (submerged)
	on_side_wall:         bool,
	on_side_wall_dir:     f32, // +1 right, -1 left, 0 no side wall
	on_side_wall_snap_x:  f32, // inner edge X of detected left wall + PLAYER_SIZE/2 or right wall - PLAYER_SIZE/2
	on_slope:             bool,
	on_slope_dir:         f32, // +1 uphill, -1 downhill, 0 flat

	// Debug: cached raycast hits for visualization
	debug_ground_hit:     engine.Collider_Raycast_Hit,
	debug_slope_hit:      engine.Collider_Raycast_Hit,
	debug_platform_hit:   engine.Collider_Raycast_Hit,
	debug_wall_left_hit:  engine.Collider_Raycast_Hit,
	debug_wall_right_hit: engine.Collider_Raycast_Hit,
}

player_sensor_update :: proc(player: ^Player) {
	in_platform: bool
	on_back_wall: bool
	on_ground: bool
	on_ground_snap_y: f32 = -1e18
	on_platform: bool
	on_sand: bool
	on_side_wall: bool
	on_side_wall_dir: f32
	on_side_wall_snap_x: f32
	on_slope: bool
	on_slope_dir: f32

	debug_ground_hit: engine.Collider_Raycast_Hit
	debug_slope_hit: engine.Collider_Raycast_Hit
	debug_platform_hit: engine.Collider_Raycast_Hit
	debug_wall_left_hit: engine.Collider_Raycast_Hit
	debug_wall_right_hit: engine.Collider_Raycast_Hit

	for c in game.level.ground_colliders {
		if on_ground do break
		origin := player.transform.pos + {0, EPS}
		max_dist := PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.collider_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			debug_ground_hit = hit
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
		}
	}

	for c in game.level.side_wall_colliders {
		if on_side_wall do break

		hit_l := engine.Collider_Raycast_Hit{}
		{
			origin :=
				player.transform.pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_l = engine.collider_raycast_rect(origin, 0, -1, max_dist, c, cross_half_size)
		}
		if hit_l.hit {
			on_side_wall = true
			on_side_wall_dir = -1
			on_side_wall_snap_x = hit_l.point.x + PLAYER_SIZE / 2
			debug_wall_left_hit = hit_l
		}

		hit_r := engine.Collider_Raycast_Hit{}
		{
			origin :=
				player.transform.pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_r = engine.collider_raycast_rect(origin, 0, 1, max_dist, c, cross_half_size)
		}
		if hit_r.hit {
			on_side_wall = true
			on_side_wall_dir = 1
			on_side_wall_snap_x = hit_r.point.x - PLAYER_SIZE / 2
			debug_wall_right_hit = hit_r
		}
	}

	for c in game.level.slope_colliders {
		origin := player.transform.pos + {0, PLAYER_STEP_HEIGHT}
		max_dist := PLAYER_STEP_HEIGHT + PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.collider_raycast_slope(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			on_slope = true
			on_slope_dir = 1 if c.kind == .Right || c.kind == .Ceil_Left else -1
			debug_slope_hit = hit
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			break
		}
	}

	for c in game.level.platform_colliders {
		if in_platform && on_platform do break
		if !in_platform && engine.collider_check_rect_vs_rect(c, player.collider) {
			in_platform = true
		}
		if !on_platform && player.transform.vel.y <= 0 {
			origin := player.transform.pos + {0, EPS}
			max_dist := PLAYER_CHECK_GROUND_EPS + EPS
			cross_half_size := PLAYER_SIZE / 2
			hit := engine.collider_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
			if hit.hit {
				on_ground = true
				on_platform = true
				debug_platform_hit = hit
				if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			}
		}
	}

	for c in game.level.back_wall_colliders {
		overlap := engine.collider_check_rect_vs_rect(c, player.collider)
		if overlap {
			on_back_wall = true
			break
		}
	}

	// Sand ground detection (only if no solid/slope/platform ground)
	if !on_ground {
		foot_tx0 := int((player.transform.pos.x - PLAYER_SIZE / 2) / TILE_SIZE)
		foot_tx1 := int((player.transform.pos.x + PLAYER_SIZE / 2) / TILE_SIZE)
		foot_ty := int(player.transform.pos.y / TILE_SIZE)

		for check_ty in ([2]int{foot_ty, foot_ty - 1}) {
			if on_sand do break
			for tx in foot_tx0 ..= foot_tx1 {
				if !sand_in_bounds(&game.sand, tx, check_ty) do continue
				if sand_get(&game.sand, tx, check_ty).material != .Sand do continue
				surface_y := f32(check_ty + 1) * TILE_SIZE
				dist := player.transform.pos.y - surface_y
				if dist >= -PLAYER_STEP_HEIGHT && dist <= PLAYER_CHECK_GROUND_EPS {
					on_ground = true
					on_sand = true
					if surface_y > on_ground_snap_y do on_ground_snap_y = surface_y
				}
			}
		}
	}

	player.sensor.in_platform = in_platform
	player.sensor.on_back_wall = on_back_wall
	player.sensor.on_ground = on_ground
	player.sensor.on_ground_snap_y = on_ground_snap_y
	player.sensor.on_platform = on_platform
	player.sensor.on_sand = on_sand
	player.sensor.sand_immersion = sand_compute_immersion(&game.sand, player)
	water_immersion := sand_compute_water_immersion(&game.sand, player)
	player.sensor.on_water = water_immersion > 0
	player.sensor.water_immersion = water_immersion
	player.sensor.on_side_wall = on_side_wall
	player.sensor.on_side_wall_dir = on_side_wall_dir
	player.sensor.on_side_wall_snap_x = on_side_wall_snap_x
	player.sensor.on_slope = on_slope
	player.sensor.on_slope_dir = on_slope_dir
	player.sensor.debug_ground_hit = debug_ground_hit
	player.sensor.debug_slope_hit = debug_slope_hit
	player.sensor.debug_platform_hit = debug_platform_hit
	player.sensor.debug_wall_left_hit = debug_wall_left_hit
	player.sensor.debug_wall_right_hit = debug_wall_right_hit
}

player_sensor_debug :: proc(player: ^Player, screen_pos: [2]f32) {
	if game.debug == .PLAYER || game.debug == .ALL {
		// Ground ray (green)
		{
			origin := player.transform.pos + {0, EPS}
			end_point := origin - {0, PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(origin, end_point, player.sensor.debug_ground_hit, DEBUG_COLOR_RAY_GROUND)
		}
		// Slope ray (light green, starts higher, longer range)
		{
			origin := player.transform.pos + {0, PLAYER_STEP_HEIGHT}
			end_point := origin - {0, PLAYER_STEP_HEIGHT + PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(origin, end_point, player.sensor.debug_slope_hit, DEBUG_COLOR_RAY_SLOPE)
		}
		// Platform ray (blue)
		{
			origin := player.transform.pos + {0, EPS}
			end_point := origin - {0, PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(
				origin,
				end_point,
				player.sensor.debug_platform_hit,
				DEBUG_COLOR_RAY_PLATFORM,
			)
		}
		// Wall left ray (orange)
		{
			origin :=
				player.transform.pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin - {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			debug_ray(origin, end_point, player.sensor.debug_wall_left_hit, DEBUG_COLOR_RAY_WALL)
		}
		// Wall right ray (orange)
		{
			origin :=
				player.transform.pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin + {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			debug_ray(origin, end_point, player.sensor.debug_wall_right_hit, DEBUG_COLOR_RAY_WALL)
		}
		// Back wall indicator (dark cyan outline when overlapping)
		if player.sensor.on_back_wall {
			debug_collider_rect(player.collider, DEBUG_COLOR_COLLIDER_BACK_WALL)
		}
	}

	Label_Value :: struct {
		label, value: cstring,
	}

	entries := [?]Label_Value {
		{"in_platform:", fmt.ctprintf("%v", player.sensor.in_platform)},
		{"on_back_wall:", fmt.ctprintf("%v", player.sensor.on_back_wall)},
		{"on_ground:", fmt.ctprintf("%v", player.sensor.on_ground)},
		{"on_platform:", fmt.ctprintf("%v", player.sensor.on_platform)},
		{"on_sand:", fmt.ctprintf("%v", player.sensor.on_sand)},
		{"sand_immersion:", fmt.ctprintf("%.2f", player.sensor.sand_immersion)},
		{"on_water:", fmt.ctprintf("%v", player.sensor.on_water)},
		{"water_immersion:", fmt.ctprintf("%.2f", player.sensor.water_immersion)},
		{"on_side_wall:", fmt.ctprintf("%v", player.sensor.on_side_wall)},
		{"on_side_wall_dir:", fmt.ctprintf("%.0f", player.sensor.on_side_wall_dir)},
		{"on_side_wall_snap_x:", fmt.ctprintf("%.2f", player.sensor.on_side_wall_snap_x)},
		{"on_slope:", fmt.ctprintf("%v", player.sensor.on_slope)},
		{"on_slope_dir:", fmt.ctprintf("%.0f", player.sensor.on_slope_dir)},
	}
	for entry, i in entries {
		debug_value_with_label(
			DEBUG_TEXT_MARGIN_X,
			2 * DEBUG_TEXT_LINE_H + DEBUG_TEXT_MARGIN_Y + f32(i) * DEBUG_TEXT_LINE_H,
			entry.label,
			entry.value,
		)
	}
}
