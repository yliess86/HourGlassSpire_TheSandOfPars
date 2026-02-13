package game

import engine "../engine"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl3"

// Compute sand immersion ratio (0.0–1.0) from player's tile footprint
sand_compute_immersion :: proc(sand: ^Sand_World, player: ^Player) -> f32 {
	if sand.width == 0 || sand.height == 0 do return 0
	x0, y0, x1, y1 := sand_player_footprint(sand, player)
	total := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	sand_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if sand_in_bounds(sand, tx, ty) && sand_get(sand, tx, ty).material == .Sand do sand_count += 1
		}
	}
	return f32(sand_count) / f32(total)
}

// Compute water immersion ratio (0.0–1.0) from player's tile footprint
sand_compute_water_immersion :: proc(sand: ^Sand_World, player: ^Player) -> f32 {
	if sand.width == 0 || sand.height == 0 do return 0
	x0, y0, x1, y1 := sand_player_footprint(sand, player)
	total := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	water_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if sand_in_bounds(sand, tx, ty) && sand_get(sand, tx, ty).material == .Water do water_count += 1
		}
	}
	return f32(water_count) / f32(total)
}

// Bidirectional player-sand/water coupling: displacement, drag, pressure, burial, buoyancy
sand_player_interact :: proc(sand: ^Sand_World, player: ^Player, dt: f32) {
	if sand.width == 0 || sand.height == 0 do return

	// Compute player tile footprint
	x0, y0, x1, y1 := sand_player_footprint(sand, player)

	sand_displaced := 0
	water_displaced := 0

	// Displacement: push sand and water out of the player footprint
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !sand_in_bounds(sand, tx, ty) do continue
			mat := sand.cells[ty * sand.width + tx].material
			if mat != .Sand && mat != .Water do continue

			// Push direction: away from player center horizontally
			player_cx := int(player.transform.pos.x / TILE_SIZE)
			push_dx: int = tx >= player_cx ? 1 : -1

			if sand_displace_cell(sand, tx, ty, push_dx) {
				if mat == .Water do water_displaced += 1
				else do sand_displaced += 1
			}
		}
	}

	// Displacement particles: visual feedback when pushing sand/water
	if sand_displaced > 0 {
		emit_pos := [2]f32{player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE}
		sand_particles_emit(
			&game.sand_particles,
			emit_pos,
			player.transform.vel,
			SAND_COLOR,
			min(sand_displaced, 4),
		)
	}
	if water_displaced > 0 {
		emit_pos := [2]f32{player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE}
		sand_particles_emit(
			&game.sand_particles,
			emit_pos,
			player.transform.vel,
			WATER_COLOR,
			min(water_displaced, 4),
		)
	}

	// Sand drag — full horizontal, reduced vertical
	if sand_displaced > 0 {
		drag := min(f32(sand_displaced) * SAND_PLAYER_DRAG_PER_CELL, SAND_PLAYER_DRAG_MAX)
		player.transform.vel.x *= (1.0 - drag)
		player.transform.vel.y *= (1.0 - drag * SAND_PLAYER_DRAG_Y_FACTOR)
	}

	// Water drag — full horizontal, reduced vertical
	if water_displaced > 0 {
		drag := min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX)
		player.transform.vel.x *= (1.0 - drag)
		player.transform.vel.y *= (1.0 - drag * WATER_PLAYER_DRAG_Y_FACTOR)
	}

	// Pressure: count sand cells directly above player (water does not create pressure)
	// Gap tolerance: scan past small empty gaps in the column
	above_count := 0
	for tx in x0 ..= x1 {
		gap := 0
		for ty := y1 + 1; ty < sand.height; ty += 1 {
			cell := sand_get(sand, tx, ty)
			if cell.material == .Sand {
				above_count += 1
				gap = 0
			} else if cell.material == .Solid {break} else {
				gap += 1
				if gap > int(SAND_PRESSURE_GAP_TOLERANCE) do break
			}
		}
	}

	if above_count > 0 {
		pressure_force := f32(above_count) * SAND_PRESSURE_FORCE
		player.transform.vel.y -= pressure_force * dt
	}

	// Burial detection: use sensor immersion (actual overlap, not displaced count)
	if player.sensor.sand_immersion > SAND_BURIAL_THRESHOLD {
		player.transform.vel.y -= SAND_BURIAL_GRAVITY_MULT * GRAVITY * dt
	}

	// Buoyancy: upward force scaled by water immersion ratio
	water_immersion := sand_compute_water_immersion(sand, player)
	if water_immersion > WATER_BUOYANCY_THRESHOLD {
		buoyancy := water_immersion * WATER_BUOYANCY_FORCE
		player.transform.vel.y += buoyancy * dt
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

// Try to displace a sand/water cell at (tx,ty) in push_dx direction.
// Returns true if successfully displaced, false if no space found even with chaining.
// Priority order: sideways and down only (never displaces upward)
@(private = "file")
sand_displace_cell :: proc(sand: ^Sand_World, tx, ty, push_dx: int) -> bool {
	if sand_try_displace_to(sand, tx, ty, tx + push_dx, ty) do return true
	if sand_try_displace_to(sand, tx, ty, tx, ty - 1) do return true
	if sand_try_displace_to(sand, tx, ty, tx + push_dx, ty - 1) do return true
	if sand_try_displace_to(sand, tx, ty, tx - push_dx, ty) do return true
	if sand_try_displace_to(sand, tx, ty, tx - push_dx, ty - 1) do return true
	return false
}

// Try to move a cell from (sx,sy) to (dx,dy) for displacement.
// Chain displacement: if destination is sand or water, recursively push it further in the same direction.
@(private = "file")
sand_try_displace_to :: proc(sand: ^Sand_World, sx, sy, dx, dy: int, depth: int = 0) -> bool {
	if !sand_in_bounds(sand, dx, dy) do return false
	dst_idx := dy * sand.width + dx
	dst_mat := sand.cells[dst_idx].material

	// Chain: if destination is sand or water, try to push it further in the same direction
	if (dst_mat == .Sand || dst_mat == .Water) && depth < int(SAND_DISPLACE_CHAIN) {
		chain_dx := dx + (dx - sx)
		chain_dy := dy + (dy - sy)
		if !sand_try_displace_to(sand, dx, dy, chain_dx, chain_dy, depth + 1) do return false
		// Destination cell was moved, fall through to move source into the now-empty space
	} else if dst_mat != .Empty do return false

	src_idx := sy * sand.width + sx
	sand.cells[dst_idx] = sand.cells[src_idx]
	sand.cells[dst_idx].sleep_counter = 0
	sand_cell_reset_fall(&sand.cells[dst_idx]) // Displacement is not natural fall
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

// Emit displacement particles with outward velocity away from player
sand_particles_emit :: proc(
	pool: ^engine.Particle_Pool,
	pos, player_vel: [2]f32,
	color: [4]u8,
	count: int,
) {
	for _ in 0 ..< count {
		angle := rand.float32() * 2 * math.PI
		speed := SAND_PARTICLE_SPEED * (0.5 + 0.5 * rand.float32())
		vel := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed + abs(player_vel.y) * 0.2}
		engine.particle_pool_emit(
			pool,
			engine.Particle {
				pos = pos,
				vel = vel,
				lifetime = SAND_PARTICLE_LIFETIME * (0.7 + 0.3 * rand.float32()),
				age = 0,
				size = SAND_PARTICLE_SIZE,
				color = color,
			},
		)
	}
}

sand_particles_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
	for i in 0 ..< pool.count {
		pool.items[i].vel.y -= SAND_PARTICLE_GRAVITY * dt
		pool.items[i].vel *= 1.0 - 3.0 * dt
		pool.items[i].pos += pool.items[i].vel * dt
	}
}

sand_particles_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(f32(p.color.a) * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := game_world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}
