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

// Find topmost sand cell surface Y in a column near the player's feet
sand_column_surface_y :: proc(sand: ^Sand_World, tx, base_ty, scan_height: int) -> (f32, bool) {
	for ty := base_ty + scan_height; ty >= max(base_ty - 1, 0); ty -= 1 {
		if !sand_in_bounds(sand, tx, ty) do continue
		if sand_get(sand, tx, ty).material == .Sand do return f32(ty + 1) * TILE_SIZE, true
	}
	return 0, false
}

// Interpolated sand surface height under the player's center
sand_surface_query :: proc(sand: ^Sand_World, player: ^Player) -> (f32, bool) {
	center_x := player.transform.pos.x
	center_tx := int(center_x / TILE_SIZE)
	base_ty := int(player.transform.pos.y / TILE_SIZE)
	scan := int(SAND_SURFACE_SCAN_HEIGHT)

	left_y, left_ok := sand_column_surface_y(sand, center_tx, base_ty, scan)
	if !left_ok do return 0, false

	frac_x := center_x / TILE_SIZE - f32(center_tx)
	adj_tx := center_tx + 1 if frac_x >= 0.5 else center_tx - 1

	right_y, right_ok := sand_column_surface_y(sand, adj_tx, base_ty, scan)
	if !right_ok do return left_y, true

	if adj_tx > center_tx do return math.lerp(left_y, right_y, frac_x), true
	return math.lerp(right_y, left_y, frac_x), true
}

// Bidirectional player-sand/water coupling: displacement, drag, pressure, burial, buoyancy
sand_player_interact :: proc(sand: ^Sand_World, player: ^Player, dt: f32) {
	if sand.width == 0 || sand.height == 0 do return

	// Dash tunnel: carve through sand, reduced drag, skip normal displacement
	if player.fsm.current == .Dashing {
		sand_dash_carve(sand, player, dt)
		return
	}

	// Compute player tile footprint
	x0, y0, x1, y1 := sand_player_footprint(sand, player)

	// Impact crater: compute factor from landing speed
	impact_factor: f32 = 0
	if player.transform.impact_pending > 0 {
		speed := player.transform.impact_pending
		player.transform.impact_pending = 0
		range := SAND_IMPACT_MAX_SPEED - SAND_IMPACT_MIN_SPEED
		if range > 0 do impact_factor = math.clamp((speed - SAND_IMPACT_MIN_SPEED) / range, 0, 1)
	}

	// Expand footprint for crater
	extra := int(impact_factor * f32(SAND_IMPACT_RADIUS))
	cx0 := max(x0 - extra, 0)
	cy0 := max(y0 - extra, 0)
	cx1 := min(x1 + extra, sand.width - 1)

	sand_displaced := 0
	water_displaced := 0
	player_cx := int(player.transform.pos.x / TILE_SIZE)

	// Displacement: push sand and water out of footprint (+ crater ring)
	for ty in cy0 ..= y1 {
		for tx in cx0 ..= cx1 {
			if !sand_in_bounds(sand, tx, ty) do continue
			mat := sand.cells[ty * sand.width + tx].material
			if mat != .Sand && mat != .Water do continue

			push_dx: int = tx >= player_cx ? 1 : -1
			in_ring := tx < x0 || tx > x1 || ty < y0

			displaced := false
			if in_ring && impact_factor > 0 {
				displaced = sand_eject_cell_up(sand, tx, ty, y1, push_dx)
			} else {
				displaced = sand_displace_cell(sand, tx, ty, push_dx)
			}

			if displaced {
				if mat == .Water do water_displaced += 1
				else do sand_displaced += 1
			}
		}
	}

	// Displacement particles (scaled by impact)
	if sand_displaced > 0 {
		emit_pos := [2]f32{player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE}
		count :=
			impact_factor > 0 ? int(math.lerp(f32(4), f32(16), impact_factor)) : min(sand_displaced, 4)
		speed_mult := math.lerp(f32(1), SAND_IMPACT_PARTICLE_SPEED_MULT, impact_factor)
		sand_particles_emit_scaled(
			&game.sand_particles,
			emit_pos,
			player.transform.vel,
			SAND_COLOR,
			count,
			speed_mult,
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

	// Sand_Swim: light displacement drag only, skip heavy forces
	if player.fsm.current == .Sand_Swim {
		if sand_displaced > 0 {
			drag := SAND_SWIM_DRAG_FACTOR * SAND_PLAYER_DRAG_MAX
			player.transform.vel.x *= (1.0 - drag)
			player.transform.vel.y *= (1.0 - drag * SAND_PLAYER_DRAG_Y_FACTOR)
		}
		if water_displaced > 0 {
			drag := min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX)
			player.transform.vel.x *= (1.0 - drag)
			player.transform.vel.y *= (1.0 - drag * WATER_PLAYER_DRAG_Y_FACTOR)
		}
		// Skip to water buoyancy + current (below)
	} else {
		// Sand drag — quadratic scaling by immersion, skip Y drag when jumping
		if sand_displaced > 0 {
			immersion := player.sensor.sand_immersion
			effective_drag := immersion * immersion * SAND_PLAYER_DRAG_MAX
			player.transform.vel.x *= (1.0 - effective_drag)
			if player.transform.vel.y <= 0 do player.transform.vel.y *= (1.0 - effective_drag * SAND_PLAYER_DRAG_Y_FACTOR)
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
			capped := math.sqrt(f32(above_count))
			player.transform.vel.y -= capped * SAND_PRESSURE_FORCE * dt
		}

		// Quicksand: activity-scaled sinking (horizontal movement makes you sink faster)
		if player.sensor.sand_immersion > SAND_BURIAL_THRESHOLD && player.transform.vel.y <= 0 {
			activity := math.clamp(math.abs(player.transform.vel.x) / PLAYER_RUN_SPEED, 0, 2)
			base_sink := SAND_QUICKSAND_BASE_SINK * GRAVITY * dt
			move_sink := SAND_QUICKSAND_MOVE_MULT * activity * GRAVITY * dt
			player.transform.vel.y -= base_sink + move_sink
		}
	}

	// Buoyancy: upward force scaled by water immersion ratio
	water_immersion := sand_compute_water_immersion(sand, player)
	if water_immersion > WATER_BUOYANCY_THRESHOLD {
		buoyancy := water_immersion * WATER_BUOYANCY_FORCE
		player.transform.vel.y += buoyancy * dt
	}

	// Water current: flowing water pushes the player horizontally
	flow_sum: f32 = 0
	flow_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !sand_in_bounds(sand, tx, ty) do continue
			cell := sand.cells[ty * sand.width + tx]
			if cell.material != .Water do continue
			flow_dir := cell.flags & SAND_FLAG_FLOW_MASK
			if flow_dir ==
			   SAND_FLAG_FLOW_LEFT {flow_sum -= 1; flow_count += 1} else if flow_dir == SAND_FLAG_FLOW_RIGHT {flow_sum += 1; flow_count += 1}
		}
	}
	if flow_count > 0 {
		current_avg := flow_sum / f32(flow_count)
		player.transform.vel.x += current_avg * WATER_CURRENT_FORCE * dt
	}
}

// Carve tunnel through sand during dash
@(private = "file")
sand_dash_carve :: proc(sand: ^Sand_World, player: ^Player, dt: f32) {
	prev_x := player.transform.pos.x - player.transform.vel.x * dt
	curr_x := player.transform.pos.x

	tx_start := max(int(math.min(prev_x, curr_x) / TILE_SIZE) - 1, 0)
	tx_end := min(int(math.max(prev_x, curr_x) / TILE_SIZE) + 1, sand.width - 1)
	ty_start := max(int(player.transform.pos.y / TILE_SIZE), 0)
	ty_end := min(int((player.transform.pos.y + PLAYER_SIZE) / TILE_SIZE), sand.height - 1)

	sand_carved := 0
	water_carved := 0
	push_dx: int = player.transform.vel.x > 0 ? 1 : -1

	for tx in tx_start ..= tx_end {
		for ty in ty_start ..= ty_end {
			if !sand_in_bounds(sand, tx, ty) do continue
			idx := ty * sand.width + tx
			mat := sand.cells[idx].material
			if mat != .Sand && mat != .Water do continue

			// Eject upward or sideways, fallback destroy
			if sand_eject_cell_up(sand, tx, ty, ty_end, push_dx) {
				if mat == .Sand do sand_carved += 1
				else do water_carved += 1
			} else {
				// Destroy cell
				sand.cells[idx] = Sand_Cell{}
				sand_wake_neighbors(sand, tx, ty)
				sand_chunk_mark_dirty(sand, tx, ty)
				chunk := sand_chunk_at(sand, tx, ty)
				if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
				if mat == .Sand do sand_carved += 1
				else do water_carved += 1
			}
		}
	}

	// Particles
	total := sand_carved + water_carved
	if total > 0 {
		emit_pos := [2]f32{player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE / 2}
		if sand_carved > 0 {
			sand_particles_emit_scaled(
				&game.sand_particles,
				emit_pos,
				player.transform.vel,
				SAND_COLOR,
				min(sand_carved, int(SAND_DASH_PARTICLE_MAX)),
				SAND_DASH_PARTICLE_SPEED_MULT,
			)
		}
		if water_carved > 0 {
			sand_particles_emit_scaled(
				&game.sand_particles,
				emit_pos,
				player.transform.vel,
				WATER_COLOR,
				min(water_carved, int(SAND_DASH_PARTICLE_MAX)),
				SAND_DASH_PARTICLE_SPEED_MULT,
			)
		}
	}

	// Reduced drag
	x0, y0, x1, y1 := sand_player_footprint(sand, player)
	sand_count := 0
	water_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !sand_in_bounds(sand, tx, ty) do continue
			mat := sand.cells[ty * sand.width + tx].material
			if mat == .Sand do sand_count += 1
			else if mat == .Water do water_count += 1
		}
	}
	if sand_count > 0 {
		drag :=
			min(f32(sand_count) * SAND_PLAYER_DRAG_PER_CELL, SAND_PLAYER_DRAG_MAX) *
			SAND_DASH_DRAG_FACTOR
		player.transform.vel.x *= (1.0 - drag)
		player.transform.vel.y *= (1.0 - drag * SAND_PLAYER_DRAG_Y_FACTOR)
	}
	if water_count > 0 {
		drag :=
			min(f32(water_count) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX) *
			SAND_DASH_DRAG_FACTOR
		player.transform.vel.x *= (1.0 - drag)
		player.transform.vel.y *= (1.0 - drag * WATER_PLAYER_DRAG_Y_FACTOR)
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

// Eject a sand/water cell upward (for crater rim splash), fallback to sideways
@(private = "file")
sand_eject_cell_up :: proc(sand: ^Sand_World, tx, ty, ceil_ty, push_dx: int) -> bool {
	for eject_y := ceil_ty + 1; eject_y < min(ceil_ty + 4, sand.height); eject_y += 1 {
		if !sand_in_bounds(sand, tx, eject_y) do continue
		if sand.cells[eject_y * sand.width + tx].material != .Empty do continue

		src_idx := ty * sand.width + tx
		dst_idx := eject_y * sand.width + tx
		sand.cells[dst_idx] = sand.cells[src_idx]
		sand.cells[dst_idx].sleep_counter = 0
		sand_cell_reset_fall(&sand.cells[dst_idx])
		sand.cells[src_idx] = Sand_Cell{}

		sand_wake_neighbors(sand, tx, ty)
		sand_wake_neighbors(sand, tx, eject_y)
		sand_chunk_mark_dirty(sand, tx, ty)
		sand_chunk_mark_dirty(sand, tx, eject_y)

		if ty / int(SAND_CHUNK_SIZE) != eject_y / int(SAND_CHUNK_SIZE) {
			src_chunk := sand_chunk_at(sand, tx, ty)
			dst_chunk := sand_chunk_at(sand, tx, eject_y)
			if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
			if dst_chunk != nil do dst_chunk.active_count += 1
		}
		return true
	}
	return sand_displace_cell(sand, tx, ty, push_dx)
}

// Emit displacement particles with outward velocity away from player
sand_particles_emit :: proc(
	pool: ^engine.Particle_Pool,
	pos, player_vel: [2]f32,
	color: [4]u8,
	count: int,
) {
	sand_particles_emit_scaled(pool, pos, player_vel, color, count, 1.0)
}

@(private = "file")
sand_particles_emit_scaled :: proc(
	pool: ^engine.Particle_Pool,
	pos, player_vel: [2]f32,
	color: [4]u8,
	count: int,
	speed_mult: f32,
) {
	for _ in 0 ..< count {
		angle := rand.float32() * 2 * math.PI
		speed := SAND_PARTICLE_SPEED * (0.5 + 0.5 * rand.float32()) * speed_mult
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

// Sand dust: emits light sand-colored particles when running on sand
@(private = "file")
sand_dust_counter: u8

sand_dust_tick :: proc(player: ^Player) {
	sand_dust_counter += 1
	if sand_dust_counter < SAND_DUST_INTERVAL do return
	sand_dust_counter = 0

	if !player.sensor.on_sand do return
	if player.fsm.current != .Grounded do return
	if math.abs(player.transform.vel.x) < SAND_DUST_MIN_SPEED do return

	emit_x := player.transform.pos.x - math.sign(player.transform.vel.x) * PLAYER_SIZE / 4
	emit_pos := [2]f32{emit_x, player.transform.pos.y}
	vel := [2]f32 {
		-math.sign(player.transform.vel.x) * SAND_DUST_SPEED * (0.5 + 0.5 * rand.float32()),
		SAND_DUST_LIFT * rand.float32(),
	}
	dust_color := [4]u8 {
		min(SAND_COLOR.r + SAND_DUST_LIGHTEN, 255),
		min(SAND_COLOR.g + SAND_DUST_LIGHTEN, 255),
		min(SAND_COLOR.b + SAND_DUST_LIGHTEN, 255),
		SAND_COLOR.a,
	}
	engine.particle_pool_emit(
		&game.dust,
		engine.Particle {
			pos = emit_pos,
			vel = vel,
			lifetime = SAND_DUST_LIFETIME * (0.7 + 0.3 * rand.float32()),
			age = 0,
			size = SAND_DUST_SIZE,
			color = dust_color,
		},
	)
}

sand_footprint_update :: proc(sand: ^Sand_World, player: ^Player) {
	if player.fsm.current != .Grounded do return
	if !player.sensor.on_sand do return
	if math.abs(player.transform.vel.x) < SAND_FOOTPRINT_MIN_SPEED do return
	if math.abs(player.transform.pos.x - player.abilities.footprint_last_x) < SAND_FOOTPRINT_STRIDE do return

	player.abilities.footprint_last_x = player.transform.pos.x
	player.abilities.footprint_side = !player.abilities.footprint_side

	foot_ty := int(player.transform.pos.y / TILE_SIZE) - 1
	foot_tx := int(player.transform.pos.x / TILE_SIZE)

	if !sand_in_bounds(sand, foot_tx, foot_ty) do return
	idx := foot_ty * sand.width + foot_tx
	if sand.cells[idx].material != .Sand do return

	push_dx: int = player.transform.vel.x > 0 ? -1 : 1
	saved := sand.cells[idx]
	sand.cells[idx] = Sand_Cell{}

	chunk := sand_chunk_at(sand, foot_tx, foot_ty)
	if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
	sand_chunk_mark_dirty(sand, foot_tx, foot_ty)

	// Pile removed sand beside the footprint (no wake for persistence)
	for try_dx in ([2]int{push_dx, -push_dx}) {
		nx := foot_tx + try_dx
		if !sand_in_bounds(sand, nx, foot_ty) do continue
		if sand.cells[foot_ty * sand.width + nx].material != .Empty do continue
		sand.cells[foot_ty * sand.width + nx] = saved
		sand.cells[foot_ty * sand.width + nx].sleep_counter = SAND_SLEEP_THRESHOLD
		n_chunk := sand_chunk_at(sand, nx, foot_ty)
		if n_chunk != nil do n_chunk.active_count += 1
		sand_chunk_mark_dirty(sand, nx, foot_ty)
		break
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
