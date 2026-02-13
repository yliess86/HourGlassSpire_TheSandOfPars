package game

Sand_Material :: enum u8 {
	Empty,
	Solid, // immovable, derived from level tiles
	Sand, // falling sand particle
	Water, // liquid particle: flows horizontally, buoyant
	Platform, // one-way: blocks sand from above, sand never moves up so pass-through is implicit
}

Sand_Slope_Kind :: enum u8 {
	None,
	Right, // floor / — solid bottom-right, open top-left
	Left, // floor \ — solid bottom-left, open top-right
}

Sand_Cell :: struct {
	material:      Sand_Material, // 1 byte
	sleep_counter: u8, // frames without movement; sleeps at threshold
	color_variant: u8, // 0-3, random brightness offset for visual variety
	flags:         u8, // bit 0: parity, bits 1-3: fall_count (0-7)
}

// Flag bit layout
SAND_FLAG_PARITY :: u8(0x01) // bit 0
SAND_FLAG_FALL_MASK :: u8(0x0E) // bits 1-3
SAND_FLAG_FALL_SHIFT :: u8(1)
SAND_FLAG_FLOW_MASK :: u8(0x30) // bits 4-5 (water flow direction)
SAND_FLAG_FLOW_LEFT :: u8(0x10) // 01 = flowed left
SAND_FLAG_FLOW_RIGHT :: u8(0x20) // 10 = flowed right

sand_cell_fall_count :: proc(cell: ^Sand_Cell) -> u8 {
	return (cell.flags & SAND_FLAG_FALL_MASK) >> SAND_FLAG_FALL_SHIFT
}

sand_cell_set_fall_count :: proc(cell: ^Sand_Cell, count: u8) {
	cell.flags = (cell.flags & ~SAND_FLAG_FALL_MASK) | (min(count, 7) << SAND_FLAG_FALL_SHIFT)
}

sand_cell_increment_fall :: proc(cell: ^Sand_Cell) {
	count := sand_cell_fall_count(cell)
	if count < 7 do sand_cell_set_fall_count(cell, count + 1)
}

sand_cell_reset_fall :: proc(cell: ^Sand_Cell) {
	cell.flags &= ~SAND_FLAG_FALL_MASK
}

Sand_Emitter :: struct {
	tx, ty:      int, // tile coordinates of emitter
	accumulator: f32, // fractional particle accumulation
	material:    Sand_Material, // what this emitter spawns (.Sand or .Water)
}

Sand_World :: struct {
	width, height:      int, // grid dimensions (= level.width, level.height)
	cells:              []Sand_Cell, // flat [y * width + x], y=0 = bottom
	slopes:             []Sand_Slope_Kind, // parallel to cells; immutable structural data from level

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

sand_get_slope :: proc(sand: ^Sand_World, x, y: int) -> Sand_Slope_Kind {
	if x < 0 || x >= sand.width || y < 0 || y >= sand.height do return .None
	return sand.slopes[y * sand.width + x]
}

sand_init :: proc(sand: ^Sand_World, level: ^Level) {
	sand.width = level.width
	sand.height = level.height
	n := sand.width * sand.height
	sand.cells = make([]Sand_Cell, n)
	sand.slopes = make([]Sand_Slope_Kind, n)
	sand.step_counter = 1
	sand.sub_step_acc = 0

	// Initialize chunks
	sand_chunk_init(sand)

	// Populate grid from level tiles. Surface floor slopes (post-reclassification)
	// become slope cells with Empty material; everything else solid/slope → Solid.
	for y in 0 ..< sand.height {
		for x in 0 ..< sand.width {
			idx := y * sand.width + x
			tile := level.tiles[idx]
			orig := level.original_tiles[idx]

			if tile == .Slope_Right do sand.slopes[idx] = .Right
			else if tile == .Slope_Left do sand.slopes[idx] = .Left
			else if orig == .Solid || orig == .Slope_Right || orig == .Slope_Left || orig == .Slope_Ceil_Right || orig == .Slope_Ceil_Left {
				sand.cells[idx].material = .Solid
			} else if orig == .Platform do sand.cells[idx].material = .Platform
		}
	}

	// Load pre-placed sand piles from level
	for pos in level.sand_piles {
		idx := pos.y * sand.width + pos.x
		sand.cells[idx].material = .Sand
		sand.cells[idx].color_variant = u8((pos.x * 7 + pos.y * 13) & 3)
		sand_chunk_mark_dirty(sand, pos.x, pos.y)
	}
	delete(level.sand_piles)

	// Load pre-placed water pools from level
	for pos in level.water_piles {
		idx := pos.y * sand.width + pos.x
		sand.cells[idx].material = .Water
		sand.cells[idx].color_variant = u8((pos.x * 7 + pos.y * 13) & 3)
		sand_chunk_mark_dirty(sand, pos.x, pos.y)
	}
	delete(level.water_piles)

	// Load emitters from level
	for pos in level.sand_emitters do append(&sand.emitters, Sand_Emitter{tx = pos.x, ty = pos.y, material = .Sand})
	for pos in level.water_emitters do append(&sand.emitters, Sand_Emitter{tx = pos.x, ty = pos.y, material = .Water})
	delete(level.sand_emitters)
	delete(level.water_emitters)
	delete(level.original_tiles)

	// Initial chunk active counts
	sand_chunk_recount(sand)
}

sand_destroy :: proc(sand: ^Sand_World) {
	delete(sand.cells)
	delete(sand.slopes)
	delete(sand.chunks)
	delete(sand.emitters)
	delete(sand.eroded_platforms)
}
