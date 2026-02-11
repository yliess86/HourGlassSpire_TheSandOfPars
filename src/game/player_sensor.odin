package game

import engine "../engine"
import "core:fmt"

Player_Sensor :: struct {
	in_platform:         bool, // overlapping any platform (for Dropping exit)
	on_back_wall:        bool, // overlapping a back wall collider
	on_ground:           bool, // any upward surface (ground + platform + slope)
	on_ground_snap_y:    f32, // surface Y of detected ground (for snapping on land)
	on_platform:         bool, // surface is a platform (for drop-through)
	on_side_wall:        bool,
	on_side_wall_dir:    f32, // +1 right‹, -1 left, 0 no side wall
	on_side_wall_snap_x: f32, // inner edge X of detected left wall + PLAYER_SIZE/2 or right wall - PLAYER_SIZE/2
	on_slope:            bool,
	on_slope_dir:        f32, // +1 uphill, -1 downhill, 0 flat
}

player_sensor_update :: proc() {
	in_platform: bool
	on_back_wall: bool
	on_ground: bool
	on_ground_snap_y: f32 = -1e18
	on_platform: bool
	on_side_wall: bool
	on_side_wall_dir: f32
	on_side_wall_snap_x: f32
	on_slope: bool
	on_slope_dir: f32

	for c in game.level.ground_colliders {
		if on_ground do break
		origin := game.player_pos + {0, EPS}
		max_dist := PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.collider_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
		}
	}

	for c in game.level.side_wall_colliders {
		if on_side_wall do break

		hit_l := engine.Collider_Raycast_Hit{}
		{
			origin := game.player_pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_l = engine.collider_raycast_rect(origin, 0, -1, max_dist, c, cross_half_size)
		}
		if hit_l.hit {
			on_side_wall = true
			on_side_wall_dir = -1
			on_side_wall_snap_x = hit_l.point.x + PLAYER_SIZE / 2
		}

		hit_r := engine.Collider_Raycast_Hit{}
		{
			origin := game.player_pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_r = engine.collider_raycast_rect(origin, 0, 1, max_dist, c, cross_half_size)
		}
		if hit_r.hit {
			on_side_wall = true
			on_side_wall_dir = 1
			on_side_wall_snap_x = hit_r.point.x - PLAYER_SIZE / 2
		}
	}

	for c in game.level.slope_colliders {
		origin := game.player_pos + {0, PLAYER_STEP_HEIGHT}
		max_dist := PLAYER_STEP_HEIGHT + PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.collider_raycast_slope(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			on_slope = true
			on_slope_dir = 1 if c.kind == .Right || c.kind == .Ceil_Left else -1
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			break
		}
	}

	for c in game.level.platform_colliders {
		if in_platform && on_platform do break
		if !in_platform && engine.collider_check_rect_vs_rect(c, game.player_collider) {
			in_platform = true
		}
		if !on_platform && game.player_vel.y <= 0 {
			origin := game.player_pos + {0, EPS}
			max_dist := PLAYER_CHECK_GROUND_EPS + EPS
			cross_half_size := PLAYER_SIZE / 2
			hit := engine.collider_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
			if hit.hit {
				on_ground = true
				on_platform = true
				if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			}
		}
	}

	for c in game.level.back_wall_colliders {
		overlap := engine.collider_check_rect_vs_rect(c, game.player_collider)
		if overlap {
			on_back_wall = true
			break
		}
	}

	player_sensor.in_platform = in_platform
	player_sensor.on_back_wall = on_back_wall
	player_sensor.on_ground = on_ground
	player_sensor.on_ground_snap_y = on_ground_snap_y
	player_sensor.on_platform = on_platform
	player_sensor.on_side_wall = on_side_wall
	player_sensor.on_side_wall_dir = on_side_wall_dir
	player_sensor.on_side_wall_snap_x = on_side_wall_snap_x
	player_sensor.on_slope = on_slope
	player_sensor.on_slope_dir = on_slope_dir
}

player_sensor_debug :: proc(screen_pos: [2]f32) {
	if game.debug == .PLAYER || game.debug == .ALL {
		{
			origin := game.player_pos + {0, EPS}
			end_point := origin - {0, PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(origin, end_point, player_sensor.on_ground)
		}
		{
			origin := game.player_pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin - {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			mask := player_sensor.on_side_wall_dir < 0
			debug_ray(origin, end_point, player_sensor.on_side_wall && mask)
		}
		{
			origin := game.player_pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin + {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			mask := player_sensor.on_side_wall_dir > 0
			debug_ray(origin, end_point, player_sensor.on_side_wall && mask)
		}
	}

	Label_Value :: struct {
		label, value: cstring,
	}

	entries := [?]Label_Value {
		{"in_platform:", fmt.ctprintf("%v", player_sensor.in_platform)},
		{"on_back_wall:", fmt.ctprintf("%v", player_sensor.on_back_wall)},
		{"on_ground:", fmt.ctprintf("%v", player_sensor.on_ground)},
		{"on_platform:", fmt.ctprintf("%v", player_sensor.on_platform)},
		{"on_side_wall:", fmt.ctprintf("%v", player_sensor.on_side_wall)},
		{"on_side_wall_dir:", fmt.ctprintf("%.0f", player_sensor.on_side_wall_dir)},
		{"on_side_wall_snap_x:", fmt.ctprintf("%.2f", player_sensor.on_side_wall_snap_x)},
		{"on_slope:", fmt.ctprintf("%v", player_sensor.on_slope)},
		{"on_slope_dir:", fmt.ctprintf("%.0f", player_sensor.on_slope_dir)},
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
