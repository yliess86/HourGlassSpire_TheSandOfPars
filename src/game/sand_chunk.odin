package game

Sand_Chunk :: struct {
	active_count: u16, // non-Empty, non-Solid cells in chunk
	dirty:        bool, // a particle moved in/out this step
	needs_sim:    bool, // dirty OR neighbor dirty -> participate in next step
}

sand_chunk_init :: proc(sand: ^Sand_World) {
	sand.chunks_w = (sand.width + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	sand.chunks_h = (sand.height + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	sand.chunks = make([]Sand_Chunk, sand.chunks_w * sand.chunks_h)
}

sand_chunk_at :: proc(sand: ^Sand_World, tx, ty: int) -> ^Sand_Chunk {
	cx := tx / int(SAND_CHUNK_SIZE)
	cy := ty / int(SAND_CHUNK_SIZE)
	if cx < 0 || cx >= sand.chunks_w || cy < 0 || cy >= sand.chunks_h do return nil
	return &sand.chunks[cy * sand.chunks_w + cx]
}

sand_mark_chunk_dirty :: proc(sand: ^Sand_World, tx, ty: int) {
	chunk := sand_chunk_at(sand, tx, ty)
	if chunk != nil do chunk.dirty = true
}

// Propagate dirty flags: any chunk that is dirty, or has a dirty neighbor, needs simulation
sand_chunk_propagate_dirty :: proc(sand: ^Sand_World) {
	// First pass: consume dirty → needs_sim (only if chunk has simulatable content)
	for &chunk in sand.chunks {
		chunk.needs_sim = chunk.dirty && chunk.active_count > 0
	}
	// Second pass: propagate from originally-dirty chunks with active content to active neighbors
	for cy in 0 ..< sand.chunks_h {
		for cx in 0 ..< sand.chunks_w {
			idx := cy * sand.chunks_w + cx
			if !sand.chunks[idx].dirty || sand.chunks[idx].active_count == 0 do continue
			for dy in -1 ..= 1 {
				for dx in -1 ..= 1 {
					if dx == 0 && dy == 0 do continue
					nx, ny := cx + dx, cy + dy
					if nx < 0 || nx >= sand.chunks_w || ny < 0 || ny >= sand.chunks_h do continue
					if sand.chunks[ny * sand.chunks_w + nx].active_count == 0 do continue
					sand.chunks[ny * sand.chunks_w + nx].needs_sim = true
				}
			}
		}
	}
	// Third pass: clear dirty for next step
	for &chunk in sand.chunks {
		chunk.dirty = false
	}
}

// Post-step cleanup (dirty flags are cleared in sand_chunk_propagate_dirty)
sand_post_step :: proc(sand: ^Sand_World) {
}

// Recount active cells in all chunks (called once at init)
sand_recount_chunks :: proc(sand: ^Sand_World) {
	for &chunk in sand.chunks {
		chunk.active_count = 0
	}
	for y in 0 ..< sand.height {
		for x in 0 ..< sand.width {
			cell := sand.cells[y * sand.width + x]
			if cell.material != .Empty && cell.material != .Solid {
				chunk := sand_chunk_at(sand, x, y)
				if chunk != nil do chunk.active_count += 1
			}
		}
	}
	// Mark chunks with active particles as dirty so they get simulated on first step
	for &chunk in sand.chunks {
		if chunk.active_count > 0 do chunk.dirty = true
	}
}
