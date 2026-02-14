package game

// Update all emitters: accumulate fractional particles and spawn when ready
sand_emitter_update :: proc(sand: ^Sand_World) {
	// Fixed dt based on sim interval: each call is one fixed step
	dt := 1.0 / (f32(FPS) * f32(FIXED_STEPS))

	for &emitter in sand.emitters {
		rate := WATER_EMITTER_RATE if emitter.material == .Water else SAND_EMITTER_RATE
		emitter.accumulator += rate * dt

		for emitter.accumulator >= 1.0 {
			emitter.accumulator -= 1.0

			// Spawn fills all cells in tile below emitter (emitter coords are in tile space)
			base_sand_x := emitter.tx * int(SAND_CELLS_PER_TILE)
			base_sand_y := (emitter.ty - 1) * int(SAND_CELLS_PER_TILE)

			for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
				for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
					sand_x := base_sand_x + cell_dx
					sand_y := base_sand_y + cell_dy
					if !sand_in_bounds(sand, sand_x, sand_y) do continue

					idx := sand_y * sand.width + sand_x
					if sand.cells[idx].material == .Empty {
						// Create particle
						hash := u32(sand_x * 7 + sand_y * 13 + int(sand.step_counter))
						sand.cells[idx] = Sand_Cell {
							material      = emitter.material,
							sleep_counter = 0,
							color_variant = u8(hash & 3),
							flags         = 0,
						}

						// Update chunk active count
						chunk := sand_chunk_at(sand, sand_x, sand_y)
						if chunk != nil do chunk.active_count += 1
					}

					// Always keep emitter area active so pile drains when space opens
					sand_wake_neighbors(sand, sand_x, sand_y)
					sand_chunk_mark_dirty(sand, sand_x, sand_y)
				}
			}
		}
	}
}
