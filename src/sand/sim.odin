package sand

import "core:math/rand"

// Tick the sub-step counter; fires step when interval is reached
sub_step_tick :: proc(world: ^World) {
	world.sub_step_acc += 1
	if world.sub_step_acc >= SAND_SIM_INTERVAL {
		world.sub_step_acc = 0
		step(world)
	}
}

// Core simulation step: cellular automaton rules with sleep/wake
step :: proc(world: ^World) {
	parity := world.step_counter & 1
	world.step_counter += 1
	chunk_propagate_dirty(world)
	for y in 0 ..< world.height {
		if parity == 0 do for x in 0 ..< world.width do dispatch_cell(world, x, y, parity)
		else do for x := world.width - 1; x >= 0; x -= 1 do dispatch_cell(world, x, y, parity)
	}
	restore_platforms(world)
}

// Unified sand + wet sand cell update (granular materials)
@(private = "file")
update_cell_granular :: proc(world: ^World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	is_wet := cell.material == .Wet_Sand

	chunk := chunk_at(world, x, y)
	if chunk != nil && !chunk.needs_sim do return

	cell_parity := u32(cell.flags & SAND_FLAG_PARITY)
	if cell_parity == (parity & 1) do return

	erode_adjacent_platforms(world, x, y)

	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	slope := world.slopes[idx]
	if slope == .Right {
		if try_move(world, x, y, x - 1, y - 1, parity) do cell_reset_fall(&world.cells[(y - 1) * world.width + (x - 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		if is_wet {try_wet_neighbors(world, x, y, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, x, y)}
		return
	} else if slope == .Left {
		if try_move(world, x, y, x + 1, y - 1, parity) do cell_reset_fall(&world.cells[(y - 1) * world.width + (x + 1)])
		else if cell.sleep_counter < 255 do cell.sleep_counter += 1
		if is_wet {try_wet_neighbors(world, x, y, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, x, y)}
		return
	}

	update_cell_granular_flat(world, x, y, parity, is_wet)
}

// Multi-step descent for flat (non-slope) granular cells (sand + wet sand)
@(private = "file")
update_cell_granular_flat :: proc(world: ^World, x, y: int, parity: u32, is_wet: bool) {
	cell := &world.cells[y * world.width + x]
	fall_count := cell_fall_count(cell)
	divisor := max(u8(1), SAND_FALL_ACCEL_DIVISOR)
	max_steps := int(min(1 + fall_count / divisor, SAND_FALL_MAX_STEPS))
	swap_chance: f32 = WET_SAND_WATER_SWAP_CHANCE if is_wet else SAND_WATER_SWAP_CHANCE

	cx, cy := x, y
	steps_taken := 0

	for step in 0 ..< max_steps {
		if !in_bounds(world, cx, cy - 1) do break
		if is_interactor_cell(world, cx, cy - 1) do break
		dst_idx := (cy - 1) * world.width + cx
		dst_mat := world.cells[dst_idx].material

		if dst_mat == .Empty {
			src_idx := cy * world.width + cx
			world.cells[dst_idx] = world.cells[src_idx]
			world.cells[dst_idx].sleep_counter = 0
			world.cells[src_idx] = Cell{}
			cy -= 1
			steps_taken += 1
		} else if dst_mat == .Water {
			if rand.float32() > swap_chance do break
			src_idx := cy * world.width + cx
			tmp := world.cells[dst_idx]
			world.cells[dst_idx] = world.cells[src_idx]
			world.cells[dst_idx].sleep_counter = 0
			world.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
			if !is_wet do world.cells[dst_idx].material = .Wet_Sand
			world.cells[src_idx] = tmp
			world.cells[src_idx].sleep_counter = 0
			world.cells[src_idx].flags =
				(world.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
			cell_reset_fall(&world.cells[dst_idx])
			cy -= 1
			steps_taken += 1
			break
		} else do break
	}

	if steps_taken > 0 {
		final := &world.cells[cy * world.width + cx]
		final.flags = (final.flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		new_fall := min(fall_count + u8(steps_taken), 7)
		cell_set_fall_count(final, new_fall)
		finalize_move(world, x, y, cx, cy)
		if is_wet {try_wet_neighbors(world, cx, cy, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, cx, cy)}
		return
	}

	// No downward movement: try diagonal (probability-gated for steeper piles)
	repose_chance: f32 = WET_SAND_REPOSE_CHANCE if is_wet else SAND_REPOSE_CHANCE
	cell = &world.cells[cy * world.width + cx]
	if rand.float32() < repose_chance {
		first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
		if try_move(world, cx, cy, cx + first_dx, cy - 1, parity) {
			cell_reset_fall(&world.cells[(cy - 1) * world.width + (cx + first_dx)])
			if is_wet {try_wet_neighbors(world, cx + first_dx, cy - 1, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, cx + first_dx, cy - 1)}
			return
		} else if try_move(world, cx, cy, cx - first_dx, cy - 1, parity) {
			cell_reset_fall(&world.cells[(cy - 1) * world.width + (cx - first_dx)])
			if is_wet {try_wet_neighbors(world, cx - first_dx, cy - 1, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, cx - first_dx, cy - 1)}
			return
		}
	}
	// Stuck
	cell_reset_fall(cell)
	if cell.sleep_counter < 255 do cell.sleep_counter += 1
	if is_wet {try_wet_neighbors(world, cx, cy, WET_SAND_SPREAD_CHANCE); wet_sand_dry_tick(world, cx, cy)}
}

// Probabilistically convert adjacent dry sand into wet sand
@(private = "file")
try_wet_neighbors :: proc(world: ^World, x, y: int, chance: f32) {
	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if !in_bounds(world, nx, ny) do continue
		n_idx := ny * world.width + nx
		if world.cells[n_idx].material != .Sand do continue
		if rand.float32() >= chance do continue
		world.cells[n_idx].material = .Wet_Sand
		world.cells[n_idx].flags &= ~SAND_FLAG_DRY_MASK
		world.cells[n_idx].sleep_counter = 0
		wake_neighbors(world, nx, ny)
		chunk_mark_dirty(world, nx, ny)
	}
}

// Drying logic: increment counter when no adjacent water; convert to Sand when threshold reached
@(private = "file")
wet_sand_dry_tick :: proc(world: ^World, x, y: int) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	if cell.material != .Wet_Sand do return

	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if in_bounds(world, nx, ny) && world.cells[ny * world.width + nx].material == .Water {
			cell.flags &= ~SAND_FLAG_DRY_MASK
			return
		}
	}

	count := (cell.flags & SAND_FLAG_DRY_MASK) >> SAND_FLAG_DRY_SHIFT
	count += 1
	if count >= WET_SAND_DRY_STEPS {
		cell.material = .Sand
		cell.flags &= ~SAND_FLAG_DRY_MASK
		wake_neighbors(world, x, y)
	} else {
		cell.flags = (cell.flags & ~SAND_FLAG_DRY_MASK) | (count << SAND_FLAG_DRY_SHIFT)
	}
}

// Try to move a sand/wet sand cell from (sx,sy) to (dx,dy). Returns true if moved.
@(private = "file")
try_move :: proc(world: ^World, sx, sy, dx, dy: int, parity: u32) -> bool {
	if !in_bounds(world, dx, dy) do return false

	dst_idx := dy * world.width + dx
	dst_mat := world.cells[dst_idx].material
	if dst_mat != .Empty && dst_mat != .Water do return false
	if is_interactor_cell(world, dx, dy) do return false

	src_idx := sy * world.width + sx

	if dst_mat == .Water {
		swap_chance := SAND_WATER_SWAP_CHANCE
		is_wet := world.cells[src_idx].material == .Wet_Sand
		if is_wet do swap_chance = WET_SAND_WATER_SWAP_CHANCE
		if rand.float32() > swap_chance do return false
		tmp := world.cells[dst_idx]
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].flags =
			(world.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		world.cells[dst_idx].sleep_counter = 0
		if !is_wet {
			world.cells[dst_idx].material = .Wet_Sand
			world.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
		}
		world.cells[src_idx] = tmp
		world.cells[src_idx].sleep_counter = 0
		world.cells[src_idx].flags =
			(world.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
	} else {
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].flags =
			(world.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		world.cells[dst_idx].sleep_counter = 0
		world.cells[src_idx] = Cell{}
	}

	if dst_mat == .Empty {
		finalize_move(world, sx, sy, dx, dy)
	} else {
		wake_neighbors(world, sx, sy)
		wake_neighbors(world, dx, dy)
		chunk_mark_dirty(world, sx, sy)
		chunk_mark_dirty(world, dx, dy)
	}

	return true
}

// Dispatch cell update based on material
@(private = "file")
dispatch_cell :: proc(world: ^World, x, y: int, parity: u32) {
	idx := y * world.width + x
	mat := world.cells[idx].material
	if mat == .Sand || mat == .Wet_Sand do update_cell_granular(world, x, y, parity)
	else if mat == .Water do update_cell_water(world, x, y, parity)
}

// Water cell update: down -> diagonal-down -> horizontal multi-cell flow
@(private = "file")
update_cell_water :: proc(world: ^World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]

	chunk := chunk_at(world, x, y)
	if chunk != nil && !chunk.needs_sim do return

	cell_parity := u32(cell.flags & SAND_FLAG_PARITY)
	if cell_parity == (parity & 1) do return

	erode_adjacent_platforms(world, x, y)
	try_wet_neighbors(world, x, y, WATER_CONTACT_WET_CHANCE)

	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	moved := false
	slope := world.slopes[idx]

	if slope == .Right {
		if try_move_water(world, x, y, x - 1, y - 1, parity) do moved = true
		else if try_flow_water(world, x, y, -1, parity) do moved = true
	} else if slope == .Left {
		if try_move_water(world, x, y, x + 1, y - 1, parity) do moved = true
		else if try_flow_water(world, x, y, 1, parity) do moved = true
	} else {
		if try_move_water(world, x, y, x, y - 1, parity) do moved = true
		else {
			first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
			if try_move_water(world, x, y, x + first_dx, y - 1, parity) do moved = true
			else if try_move_water(world, x, y, x - first_dx, y - 1, parity) do moved = true
			else {
				first_dx2: int = (rand.int31() & 1) == 0 ? -1 : 1
				if try_flow_water(world, x, y, first_dx2, parity) do moved = true
				else if try_flow_water(world, x, y, -first_dx2, parity) do moved = true
			}
		}
	}

	if !moved && slope == .None do moved = try_rise_water(world, x, y, parity)
	if !moved do if cell.sleep_counter < 255 do cell.sleep_counter += 1
}

@(private = "file")
try_move_water :: proc(world: ^World, sx, sy, dx, dy: int, parity: u32) -> bool {
	if !in_bounds(world, dx, dy) do return false

	dst_idx := dy * world.width + dx
	if world.cells[dst_idx].material != .Empty do return false
	if is_interactor_cell(world, dx, dy) do return false

	src_idx := sy * world.width + sx
	world.cells[dst_idx] = world.cells[src_idx]
	world.cells[dst_idx].flags = u8(parity & 1)
	world.cells[dst_idx].sleep_counter = 0
	world.cells[src_idx] = Cell{}
	finalize_move(world, sx, sy, dx, dy)

	return true
}

@(private = "file")
try_flow_water :: proc(world: ^World, x, y, dx: int, parity: u32) -> bool {
	is_surface :=
		!in_bounds(world, x, y + 1) || world.cells[(y + 1) * world.width + x].material != .Water
	if is_surface {
		depth_below := 0
		for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
			if world.cells[scan_y * world.width + x].material != .Water do break
			depth_below += 1
		}
		if depth_below < int(WATER_SURFACE_TENSION_DEPTH) {
			has_water_neighbor :=
				(in_bounds(world, x - 1, y) &&
					world.cells[y * world.width + (x - 1)].material == .Water) ||
				(in_bounds(world, x + 1, y) &&
						world.cells[y * world.width + (x + 1)].material == .Water)
			if !has_water_neighbor do return false
		}
	}

	depth := 0
	for scan_y := y + 1; scan_y < world.height; scan_y += 1 {
		if world.cells[scan_y * world.width + x].material != .Water do break
		depth += 1
		if depth >= int(WATER_FLOW_DISTANCE) do break
	}
	max_flow := min(1 + depth, int(WATER_FLOW_DISTANCE))

	target_x := -1
	for i in 1 ..= max_flow {
		nx := x + i * dx
		if !in_bounds(world, nx, y) do break
		if is_interactor_cell(world, nx, y) do break
		if world.cells[y * world.width + nx].material != .Empty do break

		below_empty :=
			in_bounds(world, nx, y - 1) &&
			world.cells[(y - 1) * world.width + nx].material == .Empty
		if below_empty {
			target_x = nx
			break
		}
		target_x = nx
	}

	if target_x < 0 do return false

	src_idx := y * world.width + x
	dst_idx := y * world.width + target_x
	world.cells[dst_idx] = world.cells[src_idx]
	flow_bits: u8 = SAND_FLAG_FLOW_RIGHT if dx > 0 else SAND_FLAG_FLOW_LEFT
	world.cells[dst_idx].flags = u8(parity & 1) | flow_bits
	world.cells[dst_idx].sleep_counter = 0
	world.cells[src_idx] = Cell{}
	finalize_move(world, x, y, target_x, y)

	return true
}

@(private = "file")
try_rise_water :: proc(world: ^World, x, y: int, parity: u32) -> bool {
	if !in_bounds(world, x, y + 1) do return false
	if is_interactor_cell(world, x, y + 1) do return false
	if world.cells[(y + 1) * world.width + x].material != .Empty do return false

	depth_below := 0
	for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
		if world.cells[scan_y * world.width + x].material != .Water do break
		depth_below += 1
	}
	if depth_below < int(WATER_PRESSURE_MIN_DEPTH) do return false

	my_height := depth_below + 1
	found_taller := false
	for dist in 1 ..= int(WATER_PRESSURE_SCAN_RANGE) {
		for sign in ([2]int{-1, 1}) {
			nx := x + dist * sign
			if !in_bounds(world, nx, y) do continue
			neighbor_height := 0
			for scan_y := y; scan_y >= 0; scan_y -= 1 {
				if world.cells[scan_y * world.width + nx].material != .Water do break
				neighbor_height += 1
			}
			for scan_y := y + 1; scan_y < world.height; scan_y += 1 {
				if world.cells[scan_y * world.width + nx].material != .Water do break
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

	return try_move_water(world, x, y, x, y + 1, parity)
}

@(private = "file")
erode_adjacent_platforms :: proc(world: ^World, x, y: int) {
	for dx in ([2]int{-1, 1}) {
		nx := x + dx
		if !in_bounds(world, nx, y) do continue
		n_idx := y * world.width + nx
		if world.cells[n_idx].material != .Platform do continue

		cpt := int(SAND_CELLS_PER_TILE)
		tile_base_x := (nx / cpt) * cpt
		tile_base_y := (y / cpt) * cpt

		for sub_dy in 0 ..< cpt {
			for sub_dx in 0 ..< cpt {
				sx := tile_base_x + sub_dx
				sy := tile_base_y + sub_dy
				if !in_bounds(world, sx, sy) do continue
				sub_idx := sy * world.width + sx
				if world.cells[sub_idx].material != .Platform do continue

				world.cells[sub_idx] = Cell{}
				wake_neighbors(world, sx, sy)
				chunk_mark_dirty(world, sx, sy)

				chunk := chunk_at(world, sx, sy)
				if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1

				append(&world.eroded_platforms, [2]int{sx, sy})
			}
		}

		world.cells[y * world.width + x].sleep_counter = 0
	}
}

@(private = "file")
restore_platforms :: proc(world: ^World) {
	i := 0
	for i < len(world.eroded_platforms) {
		pos := world.eroded_platforms[i]
		px, py := pos.x, pos.y
		idx := py * world.width + px

		if world.cells[idx].material != .Empty {
			i += 1
			continue
		}

		has_adjacent_sand := false
		for offset in ([3][2]int{{-1, 0}, {1, 0}, {0, 1}}) {
			nx := px + offset.x
			ny := py + offset.y
			if !in_bounds(world, nx, ny) do continue
			mat := world.cells[ny * world.width + nx].material
			if mat == .Sand || mat == .Wet_Sand || mat == .Water {
				has_adjacent_sand = true
				break
			}
		}

		if has_adjacent_sand {
			i += 1
			continue
		}

		world.cells[idx].material = .Platform
		wake_neighbors(world, px, py)
		chunk_mark_dirty(world, px, py)
		chunk := chunk_at(world, px, py)
		if chunk != nil do chunk.active_count += 1

		unordered_remove(&world.eroded_platforms, i)
	}
}
