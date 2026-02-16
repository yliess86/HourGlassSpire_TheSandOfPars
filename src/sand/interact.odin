package sand

import "core:math"

// Compute immersion ratio (0.0-1.0) for a set of materials in an AABB footprint
compute_immersion :: proc(
	world: ^World,
	pos: [2]f32,
	size: f32,
	materials: bit_set[Material],
) -> f32 {
	if world.width == 0 || world.height == 0 do return 0
	x0, y0, x1, y1 := footprint_cells(world, pos, size)
	total := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if in_bounds(world, tx, ty) && get(world, tx, ty).material in materials do count += 1
		}
	}
	return f32(count) / f32(total)
}

// Find topmost sand cell surface Y in a column near the player's feet
column_surface_y :: proc(world: ^World, gx, base_gy, scan_height: int) -> (f32, bool) {
	for gy := base_gy + scan_height; gy >= max(base_gy - 1, 0); gy -= 1 {
		if !in_bounds(world, gx, gy) do continue
		col_mat := get(world, gx, gy).material
		if col_mat == .Sand || col_mat == .Wet_Sand do return f32(gy + 1) * SAND_CELL_SIZE, true
	}
	return 0, false
}

// Interpolated sand surface height at a given X position and base Y
surface_query :: proc(world: ^World, center_x, base_y: f32) -> (f32, bool) {
	center_gx := int(center_x / SAND_CELL_SIZE)
	base_gy := int(base_y / SAND_CELL_SIZE)
	scan := int(SAND_SURFACE_SCAN_HEIGHT)

	left_y, left_ok := column_surface_y(world, center_gx, base_gy, scan)
	if !left_ok do return 0, false

	frac_x := center_x / SAND_CELL_SIZE - f32(center_gx)
	adj_gx := center_gx + 1 if frac_x >= 0.5 else center_gx - 1

	right_y, right_ok := column_surface_y(world, adj_gx, base_gy, scan)
	if !right_ok do return left_y, true

	if adj_gx > center_gx do return math.lerp(left_y, right_y, frac_x), true
	return math.lerp(right_y, left_y, frac_x), true
}

// Count contiguous sand/wet sand cells in a column from ty_start to ty_end (inclusive)
count_wall_column :: proc(world: ^World, tx, ty_start, ty_end: int) -> int {
	count := 0
	for ty in ty_start ..= ty_end {
		if !in_bounds(world, tx, ty) do break
		mat := get(world, tx, ty).material
		if mat != .Sand && mat != .Wet_Sand do break
		count += 1
	}
	return count
}

// Detect a sand wall adjacent to an AABB (left or right column)
detect_wall :: proc(world: ^World, pos: [2]f32, size: f32) -> (bool, f32, f32) {
	if world.width == 0 || world.height == 0 do return false, 0, 0

	gy_start := int(pos.y / SAND_CELL_SIZE)
	gy_end := int((pos.y + size) / SAND_CELL_SIZE)

	left_x := pos.x - size / 2 - world.wall_detect_eps
	left_gx := int(left_x / SAND_CELL_SIZE)
	if in_bounds(world, left_gx, gy_start) {
		count := count_wall_column(world, left_gx, gy_start, gy_end)
		if count >= int(SAND_WALL_MIN_HEIGHT) {
			snap_x := f32(left_gx + 1) * SAND_CELL_SIZE + size / 2
			return true, -1, snap_x
		}
	}

	right_x := pos.x + size / 2 + world.wall_detect_eps
	right_gx := int(right_x / SAND_CELL_SIZE)
	if in_bounds(world, right_gx, gy_start) {
		count := count_wall_column(world, right_gx, gy_start, gy_end)
		if count >= int(SAND_WALL_MIN_HEIGHT) {
			snap_x := f32(right_gx) * SAND_CELL_SIZE - size / 2
			return true, 1, snap_x
		}
	}

	return false, 0, 0
}

// Erode sand wall: remove cells from the wall column near a position
wall_erode :: proc(world: ^World, pos: [2]f32, size, dir: f32) {
	if world.width == 0 || world.height == 0 do return

	wall_x := pos.x + dir * (size / 2 + world.wall_detect_eps)
	wall_gx := int(wall_x / SAND_CELL_SIZE)
	center_gy := int((pos.y + size / 2) / SAND_CELL_SIZE)
	push_dx: int = dir > 0 ? 1 : -1

	for _ in 0 ..< int(SAND_WALL_ERODE_RATE) {
		for try_gy in ([3]int{center_gy, center_gy + 1, center_gy - 1}) {
			if !in_bounds(world, wall_gx, try_gy) do continue
			mat := get(world, wall_gx, try_gy).material
			if mat != .Sand && mat != .Wet_Sand do continue
			displace_cell(world, wall_gx, try_gy, push_dx)
			break
		}
	}
}

// Interactor-sand/water coupling: displacement, drag, pressure, burial, buoyancy
interact :: proc(world: ^World, it: ^Interactor, dt: f32) {
	if world.width == 0 || world.height == 0 do return

	x0, y0, x1, y1 := footprint_cells(world, it.pos, it.size)
	world.interactor_x0 = x0
	world.interactor_y0 = y0
	world.interactor_x1 = x1
	world.interactor_y1 = y1
	world.interactor_blocking = true

	if it.is_dashing {
		dash_carve(world, it, dt)
		return
	}

	impact_factor: f32 = 0
	if it.impact_pending > 0 {
		speed := it.impact_pending
		it.impact_pending = 0
		range := SAND_IMPACT_MAX_SPEED - SAND_IMPACT_MIN_SPEED
		if range > 0 do impact_factor = math.clamp((speed - SAND_IMPACT_MIN_SPEED) / range, 0, 1)
	}
	it.out_impact_factor = impact_factor

	extra := int(impact_factor * f32(SAND_IMPACT_RADIUS))
	cx0 := max(x0 - extra, 0)
	cy0 := max(y0 - extra, 0)
	cx1 := min(x1 + extra, world.width - 1)

	sand_displaced := 0
	wet_sand_displaced := 0
	water_displaced := 0
	center_cx := int(it.pos.x / SAND_CELL_SIZE)

	for ty in cy0 ..= y1 {
		for tx in cx0 ..= cx1 {
			if !in_bounds(world, tx, ty) do continue
			mat := world.cells[ty * world.width + tx].material
			if mat != .Sand && mat != .Wet_Sand && mat != .Water do continue

			push_dx: int = tx >= center_cx ? 1 : -1
			in_ring := tx < x0 || tx > x1 || ty < y0

			displaced := false
			if in_ring && impact_factor > 0 {
				displaced = eject_cell_up(world, tx, ty, y1, push_dx)
			} else {
				displaced = displace_cell(world, tx, ty, push_dx)
			}

			if displaced {
				if mat == .Water do water_displaced += 1
				else if mat == .Wet_Sand do wet_sand_displaced += 1
				else do sand_displaced += 1
			}
		}
	}

	it.out_sand_displaced = sand_displaced
	it.out_wet_sand_displaced = wet_sand_displaced
	it.out_water_displaced = water_displaced

	surf_y, surf_ok := surface_query(world, it.pos.x, it.pos.y)
	it.out_surface_y = surf_y
	it.out_surface_found = surf_ok

	if it.is_submerged {
		if sand_displaced > 0 do apply_drag(&it.vel, SAND_SWIM_DRAG_FACTOR * SAND_PLAYER_DRAG_MAX, SAND_PLAYER_DRAG_Y_FACTOR, false)
		if wet_sand_displaced > 0 do apply_drag(&it.vel, SAND_SWIM_DRAG_FACTOR * WET_SAND_PLAYER_DRAG_MAX, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
		if water_displaced > 0 do apply_drag(&it.vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)
	} else {
		if sand_displaced > 0 {
			immersion := it.sand_immersion
			apply_drag(
				&it.vel,
				immersion * immersion * SAND_PLAYER_DRAG_MAX,
				SAND_PLAYER_DRAG_Y_FACTOR,
				true,
			)
		}
		if wet_sand_displaced > 0 {
			drag := min(
				f32(wet_sand_displaced) * WET_SAND_PLAYER_DRAG_PER_CELL,
				WET_SAND_PLAYER_DRAG_MAX,
			)
			apply_drag(&it.vel, drag, WET_SAND_PLAYER_DRAG_Y_FACTOR, true)
		}
		if water_displaced > 0 do apply_drag(&it.vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)

		above_count := 0
		for tx in x0 ..= x1 {
			gap := 0
			for ty := y1 + 1; ty < world.height; ty += 1 {
				cell := get(world, tx, ty)
				if cell.material == .Sand || cell.material == .Wet_Sand {
					above_count += 1
					gap = 0
				} else if cell.material == .Solid {break} else {
					gap += 1
					if gap > int(SAND_PRESSURE_GAP_TOLERANCE) do break
				}
			}
		}

		if above_count > 0 {
			capped := math.sqrt(f32(above_count))
			it.vel.y -= capped * SAND_PRESSURE_FORCE * dt
		}

		if it.sand_immersion > SAND_BURIAL_THRESHOLD && it.vel.y <= 0 {
			activity := math.clamp(
				math.abs(it.vel.x) / world.run_speed,
				0,
				SAND_QUICKSAND_MAX_ACTIVITY,
			)
			base_sink := SAND_QUICKSAND_BASE_SINK * world.gravity * dt
			move_sink := SAND_QUICKSAND_MOVE_MULT * activity * world.gravity * dt
			it.vel.y -= base_sink + move_sink
		}
	}

	water_immersion := compute_immersion(world, it.pos, it.size, {.Water})
	if water_immersion > WATER_BUOYANCY_THRESHOLD {
		buoyancy := water_immersion * WATER_BUOYANCY_FORCE
		it.vel.y += buoyancy * dt
	}

	flow_sum: f32 = 0
	flow_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !in_bounds(world, tx, ty) do continue
			cell := world.cells[ty * world.width + tx]
			if cell.material != .Water do continue
			flow_dir := cell.flags & SAND_FLAG_FLOW_MASK
			if flow_dir ==
			   SAND_FLAG_FLOW_LEFT {flow_sum -= 1; flow_count += 1} else if flow_dir == SAND_FLAG_FLOW_RIGHT {flow_sum += 1; flow_count += 1}
		}
	}
	if flow_count > 0 {
		current_avg := flow_sum / f32(flow_count)
		it.vel.x += current_avg * WATER_CURRENT_FORCE * dt
	}
}

// Carve tunnel through sand during dash
@(private = "file")
dash_carve :: proc(world: ^World, it: ^Interactor, dt: f32) {
	prev_x := it.pos.x - it.vel.x * dt
	curr_x := it.pos.x

	gx_start := max(int(math.min(prev_x, curr_x) / SAND_CELL_SIZE) - 1, 0)
	gx_end := min(int(math.max(prev_x, curr_x) / SAND_CELL_SIZE) + 1, world.width - 1)
	gy_start := max(int(it.pos.y / SAND_CELL_SIZE), 0)
	gy_end := min(int((it.pos.y + it.size) / SAND_CELL_SIZE), world.height - 1)

	sand_carved := 0
	water_carved := 0
	push_dx: int = it.vel.x > 0 ? 1 : -1

	for gx in gx_start ..= gx_end {
		for gy in gy_start ..= gy_end {
			if !in_bounds(world, gx, gy) do continue
			idx := gy * world.width + gx
			mat := world.cells[idx].material
			if mat != .Sand && mat != .Wet_Sand && mat != .Water do continue

			if !eject_cell_up(world, gx, gy, gy_end, push_dx) do continue
			if mat == .Sand || mat == .Wet_Sand do sand_carved += 1
			else do water_carved += 1
		}
	}

	it.out_sand_displaced = sand_carved
	it.out_water_displaced = water_carved

	fx0, fy0, fx1, fy1 := footprint_cells(world, it.pos, it.size)
	sand_count := 0
	wet_sand_count := 0
	water_count := 0
	for ty in fy0 ..= fy1 {
		for tx in fx0 ..= fx1 {
			if !in_bounds(world, tx, ty) do continue
			mat := world.cells[ty * world.width + tx].material
			if mat == .Sand do sand_count += 1
			else if mat == .Wet_Sand do wet_sand_count += 1
			else if mat == .Water do water_count += 1
		}
	}
	if sand_count > 0 do apply_drag(&it.vel, min(f32(sand_count) * SAND_PLAYER_DRAG_PER_CELL, SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, SAND_PLAYER_DRAG_Y_FACTOR, false)
	if wet_sand_count > 0 do apply_drag(&it.vel, min(f32(wet_sand_count) * WET_SAND_PLAYER_DRAG_PER_CELL, WET_SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
	if water_count > 0 do apply_drag(&it.vel, min(f32(water_count) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WATER_PLAYER_DRAG_Y_FACTOR, false)
}

apply_drag :: proc(vel: ^[2]f32, drag, y_factor: f32, skip_positive_y: bool) {
	vel.x *= (1.0 - drag)
	if !skip_positive_y || vel.y <= 0 do vel.y *= (1.0 - drag * y_factor)
}

// Compute the cell range overlapping an AABB given bottom-center pos and square size
footprint_cells :: proc(world: ^World, pos: [2]f32, size: f32) -> (x0, y0, x1, y1: int) {
	x0 = int((pos.x - size / 2) / SAND_CELL_SIZE)
	y0 = int(pos.y / SAND_CELL_SIZE)
	x1 = int((pos.x + size / 2) / SAND_CELL_SIZE)
	y1 = int((pos.y + size) / SAND_CELL_SIZE)

	x0 = math.clamp(x0, 0, world.width - 1)
	y0 = math.clamp(y0, 0, world.height - 1)
	x1 = math.clamp(x1, 0, world.width - 1)
	y1 = math.clamp(y1, 0, world.height - 1)
	return
}

// Try to displace a sand/water cell at (tx,ty) in push_dx direction.
// Slope-aware: aligns push directions with slope surface geometry.
displace_cell :: proc(world: ^World, tx, ty, push_dx: int) -> bool {
	slope := get_slope(world, tx, ty)

	if slope == .Right {
		if push_dx < 0 {
			if try_displace_to(world, tx, ty, tx - 1, ty - 1) do return true
			if try_displace_to(world, tx, ty, tx - 1, ty) do return true
		} else {
			if try_displace_to(world, tx, ty, tx + 1, ty + 1) do return true
			if try_displace_to(world, tx, ty, tx + 1, ty) do return true
		}
		if try_displace_to(world, tx, ty, tx, ty + 1) do return true
	} else if slope == .Left {
		if push_dx > 0 {
			if try_displace_to(world, tx, ty, tx + 1, ty - 1) do return true
			if try_displace_to(world, tx, ty, tx + 1, ty) do return true
		} else {
			if try_displace_to(world, tx, ty, tx - 1, ty + 1) do return true
			if try_displace_to(world, tx, ty, tx - 1, ty) do return true
		}
		if try_displace_to(world, tx, ty, tx, ty + 1) do return true
	}

	if try_displace_to(world, tx, ty, tx + push_dx, ty) do return true
	if slope == .None {
		if try_displace_to(world, tx, ty, tx, ty - 1) do return true
	}
	if slope == .None || (slope == .Right && push_dx < 0) || (slope == .Left && push_dx > 0) {
		if try_displace_to(world, tx, ty, tx + push_dx, ty - 1) do return true
	}
	if try_displace_to(world, tx, ty, tx - push_dx, ty) do return true
	if slope == .None || (slope == .Right && push_dx > 0) || (slope == .Left && push_dx < 0) {
		if try_displace_to(world, tx, ty, tx - push_dx, ty - 1) do return true
	}
	return false
}

// Try to move a cell from (sx,sy) to (dx,dy) for displacement.
// Chain displacement: if destination is sand or water, recursively push it further.
try_displace_to :: proc(world: ^World, sx, sy, dx, dy: int, depth: int = 0) -> bool {
	if !in_bounds(world, dx, dy) do return false
	if is_interactor_cell(world, dx, dy) do return false
	dst_idx := dy * world.width + dx
	dst_mat := world.cells[dst_idx].material

	if (dst_mat == .Sand || dst_mat == .Wet_Sand || dst_mat == .Water) &&
	   depth < int(SAND_DISPLACE_CHAIN) {
		if get_slope(world, dx, dy) != .None do return false
		chain_dx := dx + (dx - sx)
		chain_dy := dy + (dy - sy)
		if !try_displace_to(world, dx, dy, chain_dx, chain_dy, depth + 1) do return false
	} else if dst_mat != .Empty do return false

	src_idx := sy * world.width + sx
	world.cells[dst_idx] = world.cells[src_idx]
	world.cells[dst_idx].sleep_counter = 0
	cell_reset_fall(&world.cells[dst_idx])
	world.cells[src_idx] = Cell{}
	finalize_move(world, sx, sy, dx, dy)

	return true
}

// Eject a sand/water cell upward (for crater rim splash), fallback to sideways
eject_cell_up :: proc(world: ^World, tx, ty, ceil_ty, push_dx: int) -> bool {
	for eject_y := ceil_ty + 1;
	    eject_y < min(ceil_ty + int(SAND_EJECT_MAX_HEIGHT), world.height);
	    eject_y += 1 {
		if !in_bounds(world, tx, eject_y) do continue
		if world.cells[eject_y * world.width + tx].material != .Empty do continue

		src_idx := ty * world.width + tx
		dst_idx := eject_y * world.width + tx
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].sleep_counter = 0
		cell_reset_fall(&world.cells[dst_idx])
		world.cells[src_idx] = Cell{}
		finalize_move(world, tx, ty, tx, eject_y)
		return true
	}
	return displace_cell(world, tx, ty, push_dx)
}
