package game

Sand_Material :: enum u8 {
	Empty,
	Solid, // immovable, derived from level tiles
	Sand, // falling sand particle
	Platform, // one-way: blocks sand from above, sand never moves up so pass-through is implicit
}

Sand_Cell :: struct {
	material:      Sand_Material, // 1 byte
	sleep_counter: u8, // frames without movement; sleeps at threshold
	color_variant: u8, // 0-3, random brightness offset for visual variety
	flags:         u8, // bit 0: updated-this-step parity (prevents double-move)
}

Sand_Emitter :: struct {
	tx, ty:      int, // tile coordinates of emitter
	accumulator: f32, // fractional particle accumulation
}

Sand_World :: struct {
	width, height:      int, // grid dimensions (= level.width, level.height)
	cells:              []Sand_Cell, // flat [y * width + x], y=0 = bottom

	// Chunks
	chunks_w, chunks_h: int,
	chunks:             []Sand_Chunk,

	// Emitters
	emitters:           [dynamic]Sand_Emitter,

	// Eroded platforms (tracked for restoration when sand moves away)
	eroded_platforms:   [dynamic][2]int,

	// Simulation state
	step_counter:       u32, // total sim steps (bit 0 = parity for updated flag)
	sub_step_acc:       u8, // counts fixed steps; fires sim when == SAND_SIM_INTERVAL
}

// Grid accessors
sand_get :: proc(sand: ^Sand_World, x, y: int) -> Sand_Cell {
	if x < 0 || x >= sand.width || y < 0 || y >= sand.height do return Sand_Cell{material = .Solid}
	return sand.cells[y * sand.width + x]
}

sand_set :: proc(sand: ^Sand_World, x, y: int, cell: Sand_Cell) {
	if x < 0 || x >= sand.width || y < 0 || y >= sand.height do return
	sand.cells[y * sand.width + x] = cell
}

sand_get_ptr :: proc(sand: ^Sand_World, x, y: int) -> ^Sand_Cell {
	if x < 0 || x >= sand.width || y < 0 || y >= sand.height do return nil
	return &sand.cells[y * sand.width + x]
}

sand_in_bounds :: proc(sand: ^Sand_World, x, y: int) -> bool {
	return x >= 0 && x < sand.width && y >= 0 && y < sand.height
}

sand_init :: proc(sand: ^Sand_World, level: ^Level) {
	sand.width = level.width
	sand.height = level.height
	sand.cells = make([]Sand_Cell, sand.width * sand.height)
	sand.step_counter = 0
	sand.sub_step_acc = 0

	// Initialize chunks
	sand_chunk_init(sand)

	// Populate grid from level tiles: solid tiles become Solid cells
	for y in 0 ..< sand.height {
		for x in 0 ..< sand.width {
			kind := level.original_tiles[y * sand.width + x]
			if kind == .Solid ||
			   kind == .Slope_Right ||
			   kind == .Slope_Left ||
			   kind == .Slope_Ceil_Right ||
			   kind == .Slope_Ceil_Left {
				sand.cells[y * sand.width + x].material = .Solid
			} else if kind == .Platform {
				sand.cells[y * sand.width + x].material = .Platform
			}
		}
	}

	// Load pre-placed sand piles from level
	for pos in level.sand_piles {
		idx := pos.y * sand.width + pos.x
		sand.cells[idx].material = .Sand
		sand.cells[idx].color_variant = u8((pos.x * 7 + pos.y * 13) & 3)
		sand_mark_chunk_dirty(sand, pos.x, pos.y)
	}
	delete(level.sand_piles)

	// Load emitters from level
	for pos in level.sand_emitters {
		append(&sand.emitters, Sand_Emitter{tx = pos.x, ty = pos.y})
	}
	delete(level.sand_emitters)
	delete(level.original_tiles)

	// Initial chunk active counts
	sand_recount_chunks(sand)
}

sand_destroy :: proc(sand: ^Sand_World) {
	delete(sand.cells)
	delete(sand.chunks)
	delete(sand.emitters)
	delete(sand.eroded_platforms)
}
