package sand

Chunk :: struct {
	active_count: u16, // non-Empty, non-Solid cells in chunk
	dirty:        bool, // a particle moved in/out this step
	needs_sim:    bool, // dirty OR neighbor dirty -> participate in next step
}

chunk_init :: proc(world: ^World) {
	world.chunks_w = (world.width + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	world.chunks_h = (world.height + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	world.chunks = make([]Chunk, world.chunks_w * world.chunks_h)
}

chunk_at :: proc(world: ^World, tx, ty: int) -> ^Chunk {
	cx := tx / int(SAND_CHUNK_SIZE)
	cy := ty / int(SAND_CHUNK_SIZE)
	if cx < 0 || cx >= world.chunks_w || cy < 0 || cy >= world.chunks_h do return nil
	return &world.chunks[cy * world.chunks_w + cx]
}

chunk_mark_dirty :: proc(world: ^World, tx, ty: int) {
	chunk := chunk_at(world, tx, ty)
	if chunk != nil do chunk.dirty = true
}

// Propagate dirty flags: any chunk that is dirty, or has a dirty neighbor, needs simulation
chunk_propagate_dirty :: proc(world: ^World) {
	// First pass: consume dirty -> needs_sim (only if chunk has simulatable content)
	for &chunk in world.chunks do chunk.needs_sim = chunk.dirty && chunk.active_count > 0
	// Second pass: propagate from originally-dirty chunks with active content to active neighbors
	for cy in 0 ..< world.chunks_h {
		for cx in 0 ..< world.chunks_w {
			idx := cy * world.chunks_w + cx
			if !world.chunks[idx].dirty || world.chunks[idx].active_count == 0 do continue
			for dy in -1 ..= 1 {
				for dx in -1 ..= 1 {
					if dx == 0 && dy == 0 do continue
					nx, ny := cx + dx, cy + dy
					if nx < 0 || nx >= world.chunks_w || ny < 0 || ny >= world.chunks_h do continue
					if world.chunks[ny * world.chunks_w + nx].active_count == 0 do continue
					world.chunks[ny * world.chunks_w + nx].needs_sim = true
				}
			}
		}
	}
	// Third pass: clear dirty for next step
	for &chunk in world.chunks do chunk.dirty = false
}

// Recount active cells in all chunks (called once at init)
chunk_recount :: proc(world: ^World) {
	for &chunk in world.chunks do chunk.active_count = 0
	for y in 0 ..< world.height {
		for x in 0 ..< world.width {
			cell := world.cells[y * world.width + x]
			if cell.material != .Empty && cell.material != .Solid {
				chunk := chunk_at(world, x, y)
				if chunk != nil do chunk.active_count += 1
			}
		}
	}
	// Mark chunks with active particles as dirty so they get simulated on first step
	for &chunk in world.chunks do if chunk.active_count > 0 do chunk.dirty = true
}
