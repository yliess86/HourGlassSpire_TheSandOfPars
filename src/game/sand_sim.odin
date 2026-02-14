package game

import "core:math/rand"

// Tick the sub-step counter; fires sand_step when interval is reached
sand_sub_step_tick :: proc(sand: ^Sand_World) {
	sand.sub_step_acc += 1
	if sand.sub_step_acc >= SAND_SIM_INTERVAL {
		sand.sub_step_acc = 0
		sand_step(sand)
	}
}

// Core simulation step: cellular automaton rules with sleep/wake
sand_step :: proc(sand: ^Sand_World) {
	parity := sand.step_counter & 1
	sand.step_counter += 1

	// Propagate dirty flags to determine which chunks need simulation
	sand_chunk_propagate_dirty(sand)

	// Iterate bottom-to-top so lower cells vacate first
	for y in 0 ..< sand.height {
		// Alternate horizontal scan direction each step to eliminate bias
		if parity == 0 do for x in 0 ..< sand.width do sand_dispatch_cell(sand, x, y, parity)
		else do for x := sand.width - 1; x >= 0; x -= 1 do sand_dispatch_cell(sand, x, y, parity)
	}

	sand_restore_platforms(sand)
}

@(private = "file")
sand_update_cell :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	idx := y * sand.width + x
	cell := &sand.cells[idx]

	if cell.material != .Sand do return

	// Skip if chunk doesn't need simulation
	chunk := sand_chunk_at(sand, x, y)
	if chunk != nil && !chunk.needs_sim do return

	// Skip if already updated this step (parity check)
	cell_parity := u32(cell.flags & SAND_FLAG_PARITY)
	if cell_parity == (parity & 1) do return

	// Erode adjacent platform cells
	sand_erode_adjacent_platforms(sand, x, y)

	// Skip if sleeping
	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	slope := sand.slopes[idx]

	// Slopes: single-step diagonal only, reset fall counter
	if slope == .Right {
		if sand_try_move(sand, x, y, x - 1, y - 1, parity) do sand_cell_reset_fall(&sand.cells[(y - 1) * sand.width + (x - 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		return
	} else if slope == .Left {
		if sand_try_move(sand, x, y, x + 1, y - 1, parity) do sand_cell_reset_fall(&sand.cells[(y - 1) * sand.width + (x + 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		return
	}

	// Flat cells: multi-step descent with momentum
	sand_update_cell_flat(sand, x, y, parity)
}

// Multi-step descent for flat (non-slope) sand cells
@(private = "file")
sand_update_cell_flat :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	cell := &sand.cells[y * sand.width + x]
	fall_count := sand_cell_fall_count(cell)
	divisor := max(u8(1), SAND_FALL_ACCEL_DIVISOR)
	max_steps := int(min(1 + fall_count / divisor, SAND_FALL_MAX_STEPS))

	cx, cy := x, y
	steps_taken := 0

	for step in 0 ..< max_steps {
		if !sand_in_bounds(sand, cx, cy - 1) do break
		if sand_is_player_cell(sand, cx, cy - 1) do break
		dst_idx := (cy - 1) * sand.width + cx
		dst_mat := sand.cells[dst_idx].material

		if dst_mat == .Empty {
			// Move down: lightweight copy (wake/dirty deferred)
			src_idx := cy * sand.width + cx
			sand.cells[dst_idx] = sand.cells[src_idx]
			sand.cells[dst_idx].sleep_counter = 0
			sand.cells[src_idx] = Sand_Cell{}
			cy -= 1
			steps_taken += 1
		} else if dst_mat == .Water {
			// Water swap: reset momentum, sand becomes wet
			if rand.float32() > SAND_WATER_SWAP_CHANCE do break
			src_idx := cy * sand.width + cx
			tmp := sand.cells[dst_idx]
			sand.cells[dst_idx] = sand.cells[src_idx]
			sand.cells[dst_idx].sleep_counter = 0
			sand.cells[dst_idx].material = .Wet_Sand
			sand.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
			sand.cells[src_idx] = tmp
			sand.cells[src_idx].sleep_counter = 0
			sand.cells[src_idx].flags =
				(sand.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
			sand_cell_reset_fall(&sand.cells[dst_idx])
			cy -= 1
			steps_taken += 1
			break // Water breaks momentum
		} else do break
	}

	if steps_taken > 0 {
		// Set parity and increment fall counter at final position
		final := &sand.cells[cy * sand.width + cx]
		final.flags = (final.flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		new_fall := min(fall_count + u8(steps_taken), 7)
		sand_cell_set_fall_count(final, new_fall)

		// Wake/dirty at start and end only
		sand_wake_neighbors(sand, x, y)
		sand_wake_neighbors(sand, cx, cy)
		sand_chunk_mark_dirty(sand, x, y)
		sand_chunk_mark_dirty(sand, cx, cy)

		// Chunk active counts
		if x / int(SAND_CHUNK_SIZE) != cx / int(SAND_CHUNK_SIZE) ||
		   y / int(SAND_CHUNK_SIZE) != cy / int(SAND_CHUNK_SIZE) {
			src_chunk := sand_chunk_at(sand, x, y)
			dst_chunk := sand_chunk_at(sand, cx, cy)
			if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
			if dst_chunk != nil do dst_chunk.active_count += 1
		}
		return
	}

	// No downward movement: try diagonal (probability-gated for steeper piles)
	cell = &sand.cells[cy * sand.width + cx]
	if rand.float32() < SAND_REPOSE_CHANCE {
		first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
		if sand_try_move(sand, cx, cy, cx + first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&sand.cells[(cy - 1) * sand.width + (cx + first_dx)])
			return
		} else if sand_try_move(sand, cx, cy, cx - first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&sand.cells[(cy - 1) * sand.width + (cx - first_dx)])
			return
		}
	}
	// Stuck
	sand_cell_reset_fall(cell)
	if cell.sleep_counter < 255 do cell.sleep_counter += 1
}

// Wet sand cell update: same as sand but stickier, sinks faster, dries without water
@(private = "file")
sand_update_cell_wet_sand :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	idx := y * sand.width + x
	cell := &sand.cells[idx]

	if cell.material != .Wet_Sand do return

	chunk := sand_chunk_at(sand, x, y)
	if chunk != nil && !chunk.needs_sim do return

	cell_parity := u32(cell.flags & SAND_FLAG_PARITY)
	if cell_parity == (parity & 1) do return

	sand_erode_adjacent_platforms(sand, x, y)

	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	slope := sand.slopes[idx]

	if slope == .Right {
		if sand_try_move(sand, x, y, x - 1, y - 1, parity) do sand_cell_reset_fall(&sand.cells[(y - 1) * sand.width + (x - 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		sand_wet_sand_dry_tick(sand, x, y)
		return
	} else if slope == .Left {
		if sand_try_move(sand, x, y, x + 1, y - 1, parity) do sand_cell_reset_fall(&sand.cells[(y - 1) * sand.width + (x + 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		sand_wet_sand_dry_tick(sand, x, y)
		return
	}

	sand_update_cell_wet_sand_flat(sand, x, y, parity)
}

// Multi-step descent for flat wet sand cells (stickier + faster water swap + drying)
@(private = "file")
sand_update_cell_wet_sand_flat :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	cell := &sand.cells[y * sand.width + x]
	fall_count := sand_cell_fall_count(cell)
	divisor := max(u8(1), SAND_FALL_ACCEL_DIVISOR)
	max_steps := int(min(1 + fall_count / divisor, SAND_FALL_MAX_STEPS))

	cx, cy := x, y
	steps_taken := 0

	for step in 0 ..< max_steps {
		if !sand_in_bounds(sand, cx, cy - 1) do break
		if sand_is_player_cell(sand, cx, cy - 1) do break
		dst_idx := (cy - 1) * sand.width + cx
		dst_mat := sand.cells[dst_idx].material

		if dst_mat == .Empty {
			src_idx := cy * sand.width + cx
			sand.cells[dst_idx] = sand.cells[src_idx]
			sand.cells[dst_idx].sleep_counter = 0
			sand.cells[src_idx] = Sand_Cell{}
			cy -= 1
			steps_taken += 1
		} else if dst_mat == .Water {
			// Wet sand sinks faster through water
			if rand.float32() > WET_SAND_WATER_SWAP_CHANCE do break
			src_idx := cy * sand.width + cx
			tmp := sand.cells[dst_idx]
			sand.cells[dst_idx] = sand.cells[src_idx]
			sand.cells[dst_idx].sleep_counter = 0
			sand.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK // Reset drying counter (touching water)
			sand.cells[src_idx] = tmp
			sand.cells[src_idx].sleep_counter = 0
			sand.cells[src_idx].flags =
				(sand.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
			sand_cell_reset_fall(&sand.cells[dst_idx])
			cy -= 1
			steps_taken += 1
			break
		} else do break
	}

	if steps_taken > 0 {
		final := &sand.cells[cy * sand.width + cx]
		final.flags = (final.flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		new_fall := min(fall_count + u8(steps_taken), 7)
		sand_cell_set_fall_count(final, new_fall)

		sand_wake_neighbors(sand, x, y)
		sand_wake_neighbors(sand, cx, cy)
		sand_chunk_mark_dirty(sand, x, y)
		sand_chunk_mark_dirty(sand, cx, cy)

		if x / int(SAND_CHUNK_SIZE) != cx / int(SAND_CHUNK_SIZE) ||
		   y / int(SAND_CHUNK_SIZE) != cy / int(SAND_CHUNK_SIZE) {
			src_chunk := sand_chunk_at(sand, x, y)
			dst_chunk := sand_chunk_at(sand, cx, cy)
			if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
			if dst_chunk != nil do dst_chunk.active_count += 1
		}

		sand_wet_sand_dry_tick(sand, cx, cy)
		return
	}

	// No downward movement: try diagonal (lower repose chance = steeper piles)
	cell = &sand.cells[cy * sand.width + cx]
	if rand.float32() < WET_SAND_REPOSE_CHANCE {
		first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
		if sand_try_move(sand, cx, cy, cx + first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&sand.cells[(cy - 1) * sand.width + (cx + first_dx)])
			sand_wet_sand_dry_tick(sand, cx + first_dx, cy - 1)
			return
		} else if sand_try_move(sand, cx, cy, cx - first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&sand.cells[(cy - 1) * sand.width + (cx - first_dx)])
			sand_wet_sand_dry_tick(sand, cx - first_dx, cy - 1)
			return
		}
	}
	// Stuck
	sand_cell_reset_fall(cell)
	if cell.sleep_counter < 255 do cell.sleep_counter += 1
	sand_wet_sand_dry_tick(sand, cx, cy)
}

// Drying logic: increment counter when no adjacent water; convert to Sand when threshold reached
@(private = "file")
sand_wet_sand_dry_tick :: proc(sand: ^Sand_World, x, y: int) {
	idx := y * sand.width + x
	cell := &sand.cells[idx]
	if cell.material != .Wet_Sand do return

	// Check 4-neighbors for water
	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if sand_in_bounds(sand, nx, ny) && sand.cells[ny * sand.width + nx].material == .Water {
			cell.flags &= ~SAND_FLAG_DRY_MASK // Reset counter
			return
		}
	}

	// No adjacent water — increment drying counter
	count := (cell.flags & SAND_FLAG_DRY_MASK) >> SAND_FLAG_DRY_SHIFT
	count += 1
	if count >= WET_SAND_DRY_STEPS {
		cell.material = .Sand
		cell.flags &= ~SAND_FLAG_DRY_MASK
		sand_wake_neighbors(sand, x, y)
	} else {
		cell.flags = (cell.flags & ~SAND_FLAG_DRY_MASK) | (count << SAND_FLAG_DRY_SHIFT)
	}
}

// Try to move a sand/wet sand cell from (sx,sy) to (dx,dy). Returns true if moved.
// Sand can swap with Water (density: sand sinks through water). Wet sand uses higher swap chance.
@(private = "file")
sand_try_move :: proc(sand: ^Sand_World, sx, sy, dx, dy: int, parity: u32) -> bool {
	if !sand_in_bounds(sand, dx, dy) do return false

	dst_idx := dy * sand.width + dx
	dst_mat := sand.cells[dst_idx].material
	if dst_mat != .Empty && dst_mat != .Water do return false
	if sand_is_player_cell(sand, dx, dy) do return false

	src_idx := sy * sand.width + sx

	if dst_mat == .Water {
		// Stochastic density swap: sand sinks through water with probability
		swap_chance := SAND_WATER_SWAP_CHANCE
		is_wet := sand.cells[src_idx].material == .Wet_Sand
		if is_wet do swap_chance = WET_SAND_WATER_SWAP_CHANCE
		if rand.float32() > swap_chance do return false
		tmp := sand.cells[dst_idx]
		sand.cells[dst_idx] = sand.cells[src_idx]
		sand.cells[dst_idx].flags =
			(sand.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		sand.cells[dst_idx].sleep_counter = 0
		if !is_wet {
			sand.cells[dst_idx].material = .Wet_Sand
			sand.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
		}
		sand.cells[src_idx] = tmp
		sand.cells[src_idx].sleep_counter = 0
		sand.cells[src_idx].flags =
			(sand.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
	} else {
		sand.cells[dst_idx] = sand.cells[src_idx]
		sand.cells[dst_idx].flags =
			(sand.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		sand.cells[dst_idx].sleep_counter = 0
		sand.cells[src_idx] = Sand_Cell{}
	}

	// Wake neighbors around both old and new positions
	sand_wake_neighbors(sand, sx, sy)
	sand_wake_neighbors(sand, dx, dy)

	// Mark chunks dirty
	sand_chunk_mark_dirty(sand, sx, sy)
	sand_chunk_mark_dirty(sand, dx, dy)

	// Update chunk active counts (only when moving into empty — swap keeps counts balanced)
	if dst_mat == .Empty {
		if sx / int(SAND_CHUNK_SIZE) != dx / int(SAND_CHUNK_SIZE) ||
		   sy / int(SAND_CHUNK_SIZE) != dy / int(SAND_CHUNK_SIZE) {
			src_chunk := sand_chunk_at(sand, sx, sy)
			dst_chunk := sand_chunk_at(sand, dx, dy)
			if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
			if dst_chunk != nil do dst_chunk.active_count += 1
		}
	}

	return true
}

// Water uses only the parity bit from flag layout

// Dispatch cell update based on material
@(private = "file")
sand_dispatch_cell :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	idx := y * sand.width + x
	mat := sand.cells[idx].material
	if mat == .Sand do sand_update_cell(sand, x, y, parity)
	else if mat == .Wet_Sand do sand_update_cell_wet_sand(sand, x, y, parity)
	else if mat == .Water do sand_update_cell_water(sand, x, y, parity)
}

// Water cell update: down → diagonal-down → horizontal multi-cell flow
@(private = "file")
sand_update_cell_water :: proc(sand: ^Sand_World, x, y: int, parity: u32) {
	idx := y * sand.width + x
	cell := &sand.cells[idx]

	// Skip if chunk doesn't need simulation
	chunk := sand_chunk_at(sand, x, y)
	if chunk != nil && !chunk.needs_sim do return

	// Skip if already updated this step (parity check)
	cell_parity := u32(cell.flags & SAND_FLAG_PARITY)
	if cell_parity == (parity & 1) do return

	// Erode adjacent platform cells
	sand_erode_adjacent_platforms(sand, x, y)

	// Skip if sleeping
	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	moved := false
	slope := sand.slopes[idx]

	// / slope: diagonal down-left, then flow left
	// \ slope: diagonal down-right, then flow right
	// Normal: down → diagonal → horizontal flow
	if slope == .Right {
		if sand_try_move_water(sand, x, y, x - 1, y - 1, parity) do moved = true
		else if sand_try_flow_water(sand, x, y, -1, parity) do moved = true
	} else if slope == .Left {
		if sand_try_move_water(sand, x, y, x + 1, y - 1, parity) do moved = true
		else if sand_try_flow_water(sand, x, y, 1, parity) do moved = true
	} else {
		if sand_try_move_water(sand, x, y, x, y - 1, parity) do moved = true
		else {
			first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
			if sand_try_move_water(sand, x, y, x + first_dx, y - 1, parity) do moved = true
			else if sand_try_move_water(sand, x, y, x - first_dx, y - 1, parity) do moved = true
			else {
				first_dx2: int = (rand.int31() & 1) == 0 ? -1 : 1
				if sand_try_flow_water(sand, x, y, first_dx2, parity) do moved = true
				else if sand_try_flow_water(sand, x, y, -first_dx2, parity) do moved = true
			}
		}
	}

	// Pressure equalization: try rising (non-slope only)
	if !moved && slope == .None do moved = sand_try_rise_water(sand, x, y, parity)

	// Stuck: increment sleep counter
	if !moved do if cell.sleep_counter < 255 do cell.sleep_counter += 1
}

// Try to move a water cell from (sx,sy) to (dx,dy). Water only moves into Empty cells.
// Used for downward and diagonal moves only.
@(private = "file")
sand_try_move_water :: proc(sand: ^Sand_World, sx, sy, dx, dy: int, parity: u32) -> bool {
	if !sand_in_bounds(sand, dx, dy) do return false

	dst_idx := dy * sand.width + dx
	if sand.cells[dst_idx].material != .Empty do return false
	if sand_is_player_cell(sand, dx, dy) do return false

	src_idx := sy * sand.width + sx
	sand.cells[dst_idx] = sand.cells[src_idx]
	sand.cells[dst_idx].flags = u8(parity & 1)
	sand.cells[dst_idx].sleep_counter = 0
	sand.cells[src_idx] = Sand_Cell{}

	sand_wake_neighbors(sand, sx, sy)
	sand_wake_neighbors(sand, dx, dy)
	sand_chunk_mark_dirty(sand, sx, sy)
	sand_chunk_mark_dirty(sand, dx, dy)

	if sx / int(SAND_CHUNK_SIZE) != dx / int(SAND_CHUNK_SIZE) ||
	   sy / int(SAND_CHUNK_SIZE) != dy / int(SAND_CHUNK_SIZE) {
		src_chunk := sand_chunk_at(sand, sx, sy)
		dst_chunk := sand_chunk_at(sand, dx, dy)
		if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
		if dst_chunk != nil do dst_chunk.active_count += 1
	}

	return true
}

// Depth-proportional horizontal flow: surface water moves 1 cell, deeper water flows faster.
// Scans up to min(1+depth, WATER_FLOW_DISTANCE) cells for an empty cell or drop-off edge.
// Surface tension: surface cells (empty above) only flow if local depth >= WATER_SURFACE_TENSION_DEPTH
// or if they have a horizontal water neighbor (puddle-edge spreading).
@(private = "file")
sand_try_flow_water :: proc(sand: ^Sand_World, x, y, dx: int, parity: u32) -> bool {
	// Surface tension: prevent thin films from spreading
	is_surface :=
		!sand_in_bounds(sand, x, y + 1) || sand.cells[(y + 1) * sand.width + x].material != .Water
	if is_surface {
		depth_below := 0
		for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
			if sand.cells[scan_y * sand.width + x].material != .Water do break
			depth_below += 1
		}
		if depth_below < int(WATER_SURFACE_TENSION_DEPTH) {
			has_water_neighbor :=
				(sand_in_bounds(sand, x - 1, y) &&
					sand.cells[y * sand.width + (x - 1)].material == .Water) ||
				(sand_in_bounds(sand, x + 1, y) &&
						sand.cells[y * sand.width + (x + 1)].material == .Water)
			if !has_water_neighbor do return false
		}
	}

	// Count contiguous water cells above to determine pressure/depth
	depth := 0
	for scan_y := y + 1; scan_y < sand.height; scan_y += 1 {
		if sand.cells[scan_y * sand.width + x].material != .Water do break
		depth += 1
		if depth >= int(WATER_FLOW_DISTANCE) do break
	}
	max_flow := min(1 + depth, int(WATER_FLOW_DISTANCE))

	target_x := -1
	for i in 1 ..= max_flow {
		nx := x + i * dx
		if !sand_in_bounds(sand, nx, y) do break
		if sand_is_player_cell(sand, nx, y) do break
		if sand.cells[y * sand.width + nx].material != .Empty do break

		// Drop-off: empty cell below — move here immediately (water falls next step)
		below_empty :=
			sand_in_bounds(sand, nx, y - 1) &&
			sand.cells[(y - 1) * sand.width + nx].material == .Empty
		if below_empty {
			target_x = nx
			break
		}
		target_x = nx
	}

	if target_x < 0 do return false

	src_idx := y * sand.width + x
	dst_idx := y * sand.width + target_x
	sand.cells[dst_idx] = sand.cells[src_idx]
	flow_bits: u8 = SAND_FLAG_FLOW_RIGHT if dx > 0 else SAND_FLAG_FLOW_LEFT
	sand.cells[dst_idx].flags = u8(parity & 1) | flow_bits
	sand.cells[dst_idx].sleep_counter = 0
	sand.cells[src_idx] = Sand_Cell{}

	sand_wake_neighbors(sand, x, y)
	sand_wake_neighbors(sand, target_x, y)
	sand_chunk_mark_dirty(sand, x, y)
	sand_chunk_mark_dirty(sand, target_x, y)

	if x / int(SAND_CHUNK_SIZE) != target_x / int(SAND_CHUNK_SIZE) {
		src_chunk := sand_chunk_at(sand, x, y)
		dst_chunk := sand_chunk_at(sand, target_x, y)
		if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
		if dst_chunk != nil do dst_chunk.active_count += 1
	}

	return true
}

// Pressure equalization: water in deep columns rises into empty cells above when a taller
// neighbor column exists. Lowest priority — only called when all other moves fail.
@(private = "file")
sand_try_rise_water :: proc(sand: ^Sand_World, x, y: int, parity: u32) -> bool {
	if !sand_in_bounds(sand, x, y + 1) do return false
	if sand_is_player_cell(sand, x, y + 1) do return false
	if sand.cells[(y + 1) * sand.width + x].material != .Empty do return false

	// Count contiguous water depth below (including self)
	depth_below := 0
	for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
		if sand.cells[scan_y * sand.width + x].material != .Water do break
		depth_below += 1
	}
	if depth_below < int(WATER_PRESSURE_MIN_DEPTH) do return false

	// Scan for a taller water column nearby
	my_height := depth_below + 1
	found_taller := false
	for dist in 1 ..= int(WATER_PRESSURE_SCAN_RANGE) {
		for sign in ([2]int{-1, 1}) {
			nx := x + dist * sign
			if !sand_in_bounds(sand, nx, y) do continue
			// Count water height at nx from same base level
			neighbor_height := 0
			for scan_y := y; scan_y >= 0; scan_y -= 1 {
				if sand.cells[scan_y * sand.width + nx].material != .Water do break
				neighbor_height += 1
			}
			for scan_y := y + 1; scan_y < sand.height; scan_y += 1 {
				if sand.cells[scan_y * sand.width + nx].material != .Water do break
				neighbor_height += 1
			}
			if neighbor_height > my_height {
				found_taller = true
				break
			}
		}
		if found_taller do break
	}
	if !found_taller do return false

	if rand.float32() >= WATER_PRESSURE_CHANCE do return false

	return sand_try_move_water(sand, x, y, x, y + 1, parity)
}

// Erode platform cells horizontally adjacent to a sand cell
@(private = "file")
sand_erode_adjacent_platforms :: proc(sand: ^Sand_World, x, y: int) {
	for dx in ([2]int{-1, 1}) {
		nx := x + dx
		if !sand_in_bounds(sand, nx, y) do continue
		n_idx := y * sand.width + nx
		if sand.cells[n_idx].material != .Platform do continue

		// Erode all sub-cells of the same tile to prevent trapping sand inside
		cpt := int(SAND_CELLS_PER_TILE)
		tile_base_x := (nx / cpt) * cpt
		tile_base_y := (y / cpt) * cpt

		for sub_dy in 0 ..< cpt {
			for sub_dx in 0 ..< cpt {
				sx := tile_base_x + sub_dx
				sy := tile_base_y + sub_dy
				if !sand_in_bounds(sand, sx, sy) do continue
				sub_idx := sy * sand.width + sx
				if sand.cells[sub_idx].material != .Platform do continue

				sand.cells[sub_idx] = Sand_Cell{}
				sand_wake_neighbors(sand, sx, sy)
				sand_chunk_mark_dirty(sand, sx, sy)

				chunk := sand_chunk_at(sand, sx, sy)
				if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1

				append(&sand.eroded_platforms, [2]int{sx, sy})
			}
		}

		// Wake this cell so it can move into the freed space
		sand.cells[y * sand.width + x].sleep_counter = 0
	}
}

// Restore eroded platforms when no sand is horizontally adjacent
@(private = "file")
sand_restore_platforms :: proc(sand: ^Sand_World) {
	i := 0
	for i < len(sand.eroded_platforms) {
		pos := sand.eroded_platforms[i]
		px, py := pos.x, pos.y
		idx := py * sand.width + px

		// Cell occupied — can't restore yet, keep tracking
		if sand.cells[idx].material != .Empty {
			i += 1
			continue
		}

		// Check if any horizontal or above neighbor is sand or water
		has_adjacent_sand := false
		for offset in ([3][2]int{{-1, 0}, {1, 0}, {0, 1}}) {
			nx := px + offset.x
			ny := py + offset.y
			if !sand_in_bounds(sand, nx, ny) do continue
			mat := sand.cells[ny * sand.width + nx].material
			if mat == .Sand || mat == .Wet_Sand || mat == .Water {
				has_adjacent_sand = true
				break
			}
		}

		if has_adjacent_sand {
			i += 1
			continue
		}

		// Restore platform
		sand.cells[idx].material = .Platform
		sand_wake_neighbors(sand, px, py)
		sand_chunk_mark_dirty(sand, px, py)
		chunk := sand_chunk_at(sand, px, py)
		if chunk != nil do chunk.active_count += 1

		unordered_remove(&sand.eroded_platforms, i)
	}
}

// Wake all 8 neighbors of a cell (reset their sleep counter)
sand_wake_neighbors :: proc(sand: ^Sand_World, x, y: int) {
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 do continue
			nx, ny := x + dx, y + dy
			if !sand_in_bounds(sand, nx, ny) do continue
			cell := &sand.cells[ny * sand.width + nx]
			if cell.material == .Sand || cell.material == .Wet_Sand || cell.material == .Water do cell.sleep_counter = 0
		}
	}
}
