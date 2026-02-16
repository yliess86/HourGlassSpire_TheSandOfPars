package sand

// Update all emitters: accumulate fractional particles and spawn when ready
emitter_update :: proc(world: ^World) {
	dt := world.fixed_dt

	for &emitter in world.emitters {
		rate := WATER_EMITTER_RATE if emitter.material == .Water else SAND_EMITTER_RATE
		cpt := f32(SAND_CELLS_PER_TILE)
		emitter.accumulator += rate * dt

		for emitter.accumulator >= 1.0 {
			emitter.accumulator -= 1.0

			base_sand_x := emitter.tx * int(SAND_CELLS_PER_TILE)
			base_sand_y := (emitter.ty - 1) * int(SAND_CELLS_PER_TILE)

			center := cpt / 2 - 0.5
			radius_sq := (cpt / 2) * (cpt / 2)

			for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
				for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
					dx := f32(cell_dx) - center
					dy := f32(cell_dy) - center
					if dx * dx + dy * dy > radius_sq do continue

					sand_x := base_sand_x + cell_dx
					sand_y := base_sand_y + cell_dy
					if !in_bounds(world, sand_x, sand_y) do continue

					idx := sand_y * world.width + sand_x
					if world.cells[idx].material == .Empty {
						hash := u32(sand_x * 7 + sand_y * 13 + int(world.step_counter))
						world.cells[idx] = Cell {
							material      = emitter.material,
							sleep_counter = 0,
							color_variant = u8(hash & 3),
							flags         = 0,
						}

						chunk := chunk_at(world, sand_x, sand_y)
						if chunk != nil do chunk.active_count += 1
					}

					wake_neighbors(world, sand_x, sand_y)
					chunk_mark_dirty(world, sand_x, sand_y)
				}
			}
		}
	}
}
