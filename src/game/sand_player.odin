package game

import "core:math"

// Compute sand immersion ratio (0.0–1.0) from player's tile footprint
sand_compute_immersion :: proc(sand: ^Sand_World, player: ^Player) -> f32 {
	if sand.width == 0 || sand.height == 0 do return 0
	x0, y0, x1, y1 := sand_player_footprint(sand, player)
	total := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	sand_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if sand_in_bounds(sand, tx, ty) && sand_get(sand, tx, ty).material == .Sand {
				sand_count += 1
			}
		}
	}
	return f32(sand_count) / f32(total)
}

// Bidirectional player-sand coupling: displacement, drag, pressure, burial
sand_player_interact :: proc(sand: ^Sand_World, player: ^Player, dt: f32) {
	if sand.width == 0 || sand.height == 0 do return

	// Compute player tile footprint
	x0, y0, x1, y1 := sand_player_footprint(sand, player)

	total_cells := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	displaced_count := 0

	// Displacement: push sand out of the player footprint
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !sand_in_bounds(sand, tx, ty) do continue
			cell := &sand.cells[ty * sand.width + tx]
			if cell.material != .Sand do continue

			// Push direction: away from player center horizontally
			player_cx := int(player.transform.pos.x / TILE_SIZE)
			push_dx: int = tx >= player_cx ? 1 : -1

			if sand_displace_cell(sand, tx, ty, push_dx) {
				displaced_count += 1
			}
		}
	}

	// Drag: slow player based on displaced cells
	if displaced_count > 0 {
		drag_factor := f32(displaced_count) * SAND_PLAYER_DRAG_PER_CELL
		drag_factor = min(drag_factor, SAND_PLAYER_DRAG_MAX)
		player.transform.vel *= (1.0 - drag_factor)
	}

	// Pressure: count sand cells directly above player
	above_count := 0
	for tx in x0 ..= x1 {
		for ty := y1 + 1; ty < sand.height; ty += 1 {
			cell := sand_get(sand, tx, ty)
			if cell.material == .Sand {
				above_count += 1
			} else if cell.material == .Solid {
				break
			} else {
				break
			}
		}
	}

	if above_count > 0 {
		pressure_force := f32(above_count) * SAND_PRESSURE_FORCE
		player.transform.vel.y -= pressure_force * dt
	}

	// Burial detection
	burial_ratio := f32(displaced_count) / f32(total_cells)
	if burial_ratio > SAND_BURIAL_THRESHOLD {
		player.transform.vel.y -= SAND_BURIAL_GRAVITY_MULT * GRAVITY * dt
	}
}

// Compute the tile range overlapping the player collider
sand_player_footprint :: proc(sand: ^Sand_World, player: ^Player) -> (x0, y0, x1, y1: int) {
	x0 = int((player.transform.pos.x - PLAYER_SIZE / 2) / TILE_SIZE)
	y0 = int(player.transform.pos.y / TILE_SIZE)
	x1 = int((player.transform.pos.x + PLAYER_SIZE / 2) / TILE_SIZE)
	y1 = int((player.transform.pos.y + PLAYER_SIZE) / TILE_SIZE)

	x0 = math.clamp(x0, 0, sand.width - 1)
	y0 = math.clamp(y0, 0, sand.height - 1)
	x1 = math.clamp(x1, 0, sand.width - 1)
	y1 = math.clamp(y1, 0, sand.height - 1)
	return
}

// Try to displace a sand cell at (tx,ty) in push_dx direction.
// Returns true if successfully displaced, false if no space found even with chaining.
@(private = "file")
sand_displace_cell :: proc(sand: ^Sand_World, tx, ty, push_dx: int) -> bool {
	// Priority order: sideways and down only (sand never displaces upward)
	// 1. Primary push direction (horizontal)
	if sand_try_displace_to(sand, tx, ty, tx + push_dx, ty) do return true

	// 2. Down
	if sand_try_displace_to(sand, tx, ty, tx, ty - 1) do return true

	// 3. Diagonal down in push direction
	if sand_try_displace_to(sand, tx, ty, tx + push_dx, ty - 1) do return true

	// 4. Opposite direction (horizontal)
	if sand_try_displace_to(sand, tx, ty, tx - push_dx, ty) do return true

	// 5. Diagonal down in opposite direction
	if sand_try_displace_to(sand, tx, ty, tx - push_dx, ty - 1) do return true

	// No neighbor found even with chaining: leave cell in place
	return false
}

// Try to move a cell from (sx,sy) to (dx,dy) for displacement.
// Chain displacement: if destination is sand, recursively push it further in the same direction.
@(private = "file")
sand_try_displace_to :: proc(sand: ^Sand_World, sx, sy, dx, dy: int, depth: int = 0) -> bool {
	if !sand_in_bounds(sand, dx, dy) do return false
	dst_idx := dy * sand.width + dx
	dst_mat := sand.cells[dst_idx].material

	// Chain: if destination is sand, try to push it further in the same direction
	if dst_mat == .Sand && depth < int(SAND_DISPLACE_CHAIN) {
		if !sand_try_displace_to(sand, dx, dy, dx + (dx - sx), dy + (dy - sy), depth + 1) {
			return false
		}
		// Destination cell was moved, fall through to move source into the now-empty space
	} else if dst_mat != .Empty {
		return false
	}

	src_idx := sy * sand.width + sx
	sand.cells[dst_idx] = sand.cells[src_idx]
	sand.cells[dst_idx].sleep_counter = 0
	sand.cells[src_idx] = Sand_Cell{}

	sand_wake_neighbors(sand, sx, sy)
	sand_wake_neighbors(sand, dx, dy)
	sand_chunk_mark_dirty(sand, sx, sy)
	sand_chunk_mark_dirty(sand, dx, dy)

	// Update chunk active counts if crossing chunk boundary
	if sx / int(SAND_CHUNK_SIZE) != dx / int(SAND_CHUNK_SIZE) ||
	   sy / int(SAND_CHUNK_SIZE) != dy / int(SAND_CHUNK_SIZE) {
		src_chunk := sand_chunk_at(sand, sx, sy)
		dst_chunk := sand_chunk_at(sand, dx, dy)
		if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
		if dst_chunk != nil do dst_chunk.active_count += 1
	}

	return true
}
