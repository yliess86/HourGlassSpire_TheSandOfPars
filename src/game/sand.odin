package game

Sand_Material :: enum u8 {
	Empty,
	Solid, // immovable, derived from level tiles
	Sand, // falling sand particle
	Water, // liquid particle: flows horizontally, buoyant
	Platform, // one-way: blocks sand from above, sand never moves up so pass-through is implicit
	Wet_Sand, // sand that contacted water: heavier, stickier, darker; dries without water
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
	flags:         u8, // bit 0: parity, bits 1-3: fall_count (0-7), bits 4-5: flow dir (Water) / dry counter (Wet_Sand)
}

// Flag bit layout
SAND_FLAG_PARITY :: u8(0x01) // bit 0
SAND_FLAG_FALL_MASK :: u8(0x0E) // bits 1-3
SAND_FLAG_FALL_SHIFT :: u8(1)
SAND_FLAG_FLOW_MASK :: u8(0x30) // bits 4-5 (water flow direction)
SAND_FLAG_FLOW_LEFT :: u8(0x10) // 01 = flowed left
SAND_FLAG_FLOW_RIGHT :: u8(0x20) // 10 = flowed right
SAND_FLAG_DRY_MASK :: u8(0x30) // bits 4-5 (Wet_Sand drying counter, same bits as flow — no conflict)
SAND_FLAG_DRY_SHIFT :: u8(4)

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
	width, height:      int, // grid dimensions (= level dimensions * SAND_CELLS_PER_TILE)
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

// Wang hash - produces pseudo-random spatial distribution for color variants
@(private = "file")
wang_hash :: proc(x, y: int) -> u8 {
	h := u32(x * 374761393 + y * 668265263)
	h = (h ~ (h >> 15)) * 2246822519
	h = (h ~ (h >> 13)) * 3266489917
	h = (h ~ (h >> 16))
	return u8(h & 3)
}

sand_init :: proc(sand: ^Sand_World, level: ^Level) {
	sand.width = level.width * int(SAND_CELLS_PER_TILE)
	sand.height = level.height * int(SAND_CELLS_PER_TILE)
	n := sand.width * sand.height
	sand.cells = make([]Sand_Cell, n)
	sand.slopes = make([]Sand_Slope_Kind, n)
	sand.step_counter = 1
	sand.sub_step_acc = 0

	// Initialize chunks
	sand_chunk_init(sand)

	// Populate grid from level tiles. Surface floor slopes (post-reclassification)
	// become slope cells with Empty material; everything else solid/slope → Solid.
	// Each level tile maps to SAND_CELLS_PER_TILE × SAND_CELLS_PER_TILE sand cells.
	for tile_y in 0 ..< level.height {
		for tile_x in 0 ..< level.width {
			tile_idx := tile_y * level.width + tile_x
			tile := level.tiles[tile_idx]
			orig := level.original_tiles[tile_idx]

			// Fill all sand cells within this tile's footprint
			for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
				for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
					sand_x := tile_x * int(SAND_CELLS_PER_TILE) + cell_dx
					sand_y := tile_y * int(SAND_CELLS_PER_TILE) + cell_dy
					sand_idx := sand_y * sand.width + sand_x

					if tile == .Slope_Right {
						// / diagonal: solid below, open above
						if cell_dx == cell_dy {
							sand.slopes[sand_idx] = .Right
						} else if cell_dx > cell_dy {
							sand.cells[sand_idx].material = .Solid
							sand.cells[sand_idx].color_variant = wang_hash(sand_x, sand_y)
						}
					} else if tile == .Slope_Left {
						// \ diagonal: solid below, open above
						sum := cell_dx + cell_dy
						if sum == int(SAND_CELLS_PER_TILE) - 1 {
							sand.slopes[sand_idx] = .Left
						} else if sum < int(SAND_CELLS_PER_TILE) - 1 {
							sand.cells[sand_idx].material = .Solid
							sand.cells[sand_idx].color_variant = wang_hash(sand_x, sand_y)
						}
					} else if orig == .Solid ||
					   orig == .Slope_Right ||
					   orig == .Slope_Left ||
					   orig == .Slope_Ceil_Right ||
					   orig == .Slope_Ceil_Left {
						sand.cells[sand_idx].material = .Solid
						sand.cells[sand_idx].color_variant = wang_hash(sand_x, sand_y)
					} else if orig == .Platform do sand.cells[sand_idx].material = .Platform
				}
			}
		}
	}

	// Load pre-placed sand piles from level (tile coords → fill all cells in tile)
	for pos in level.sand_piles {
		for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
			for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
				sand_x := pos.x * int(SAND_CELLS_PER_TILE) + cell_dx
				sand_y := pos.y * int(SAND_CELLS_PER_TILE) + cell_dy
				idx := sand_y * sand.width + sand_x
				sand.cells[idx].material = .Sand
				sand.cells[idx].color_variant = wang_hash(sand_x, sand_y)
				sand_chunk_mark_dirty(sand, sand_x, sand_y)
			}
		}
	}
	delete(level.sand_piles)

	// Load pre-placed water pools from level (tile coords → fill all cells in tile)
	for pos in level.water_piles {
		for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
			for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
				sand_x := pos.x * int(SAND_CELLS_PER_TILE) + cell_dx
				sand_y := pos.y * int(SAND_CELLS_PER_TILE) + cell_dy
				idx := sand_y * sand.width + sand_x
				sand.cells[idx].material = .Water
				sand.cells[idx].color_variant = wang_hash(sand_x, sand_y)
				sand_chunk_mark_dirty(sand, sand_x, sand_y)
			}
		}
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
