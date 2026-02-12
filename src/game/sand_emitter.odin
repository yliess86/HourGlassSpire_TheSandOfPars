package game

// Update all emitters: accumulate fractional particles and spawn when ready
sand_emitter_update :: proc(sand: ^Sand_World) {
	// Fixed dt based on sim interval: each call is one fixed step
	dt := 1.0 / (f32(FPS) * f32(FIXED_STEPS))

	for &emitter in sand.emitters {
		emitter.accumulator += SAND_EMITTER_RATE * dt

		for emitter.accumulator >= 1.0 {
			emitter.accumulator -= 1.0

			// Spawn one tile below the emitter (sand falls from emitter)
			spawn_y := emitter.ty - 1
			if !sand_in_bounds(sand, emitter.tx, spawn_y) do continue

			idx := spawn_y * sand.width + emitter.tx
			if sand.cells[idx].material != .Empty do continue

			// Create sand particle
			hash := u32(emitter.tx * 7 + spawn_y * 13 + int(sand.step_counter))
			sand.cells[idx] = Sand_Cell {
				material      = .Sand,
				sleep_counter = 0,
				color_variant = u8(hash & 3),
				flags         = 0,
			}

			// Wake neighbors and mark chunk dirty
			sand_wake_neighbors(sand, emitter.tx, spawn_y)
			sand_chunk_mark_dirty(sand, emitter.tx, spawn_y)

			// Update chunk active count
			chunk := sand_chunk_at(sand, emitter.tx, spawn_y)
			if chunk != nil do chunk.active_count += 1
		}
	}
}
