package sand

Material :: enum u8 {
	Empty,
	Solid, // immovable, derived from level tiles
	Sand, // falling sand particle
	Water, // liquid particle: flows horizontally, buoyant
	Platform, // one-way: blocks sand from above, sand never moves up so pass-through is implicit
	Wet_Sand, // sand that contacted water: heavier, stickier, darker; dries without water
}

Slope_Kind :: enum u8 {
	None,
	Right, // floor / — solid bottom-right, open top-left
	Left, // floor \ — solid bottom-left, open top-right
}

Cell :: struct {
	material:      Material, // 1 byte
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

cell_fall_count :: proc(cell: ^Cell) -> u8 {
	return (cell.flags & SAND_FLAG_FALL_MASK) >> SAND_FLAG_FALL_SHIFT
}

cell_set_fall_count :: proc(cell: ^Cell, count: u8) {
	cell.flags = (cell.flags & ~SAND_FLAG_FALL_MASK) | (min(count, 7) << SAND_FLAG_FALL_SHIFT)
}

cell_reset_fall :: proc(cell: ^Cell) {
	cell.flags &= ~SAND_FLAG_FALL_MASK
}

Interactor :: struct {
	// Inputs (game -> sand)
	pos:                    [2]f32, // reference point (bottom-center)
	vel:                    [2]f32, // current velocity (modified in place by drag/pressure/buoyancy)
	size:                   f32, // collider width/height (square)
	impact_pending:         f32, // landing speed for craters (consumed -> 0)
	sand_immersion:         f32, // previous frame immersion (for drag scaling)
	is_dashing:             bool, // triggers dash-carve path
	is_submerged:           bool, // Sand_Swim: lighter drag, skip heavy forces
	// Outputs (sand -> game)
	out_sand_immersion:     f32, // computed sand+wet_sand immersion (0..1)
	out_water_immersion:    f32, // computed water immersion (0..1)
	out_on_sand:            bool, // standing on sand surface
	out_on_ground:          bool, // sand provides ground
	out_ground_snap_y:      f32, // sand surface Y for ground snapping
	out_wall_found:         bool, // sand wall detected
	out_wall_dir:           f32, // wall direction (+1/-1)
	out_wall_snap_x:        f32, // wall snap X
	out_sand_displaced:     int, // count of sand cells displaced (for particles)
	out_wet_sand_displaced: int, // count of wet_sand cells displaced
	out_water_displaced:    int, // count of water cells displaced
	out_impact_factor:      f32, // 0..1 impact strength (for particle scaling)
	out_surface_y:          f32, // interpolated surface Y (for particle emit pos)
	out_surface_found:      bool, // whether surface was found
}

Emitter :: struct {
	tx, ty:      int, // tile coordinates of emitter
	accumulator: f32, // fractional particle accumulation
	material:    Material, // what this emitter spawns (.Sand or .Water)
}

World :: struct {
	width, height:                                              int, // grid dimensions (= level dimensions * SAND_CELLS_PER_TILE)
	cells:                                                      []Cell, // flat [y * width + x], y=0 = bottom
	slopes:                                                     []Slope_Kind, // parallel to cells; immutable structural data from level

	// Chunks
	chunks_w, chunks_h:                                         int,
	chunks:                                                     []Chunk,

	// Emitters
	emitters:                                                   [dynamic]Emitter,

	// Eroded platforms (tracked for restoration when sand moves away)
	eroded_platforms:                                           [dynamic][2]int,

	// Simulation state
	step_counter:                                               u32, // total sim steps (bit 0 = parity for updated flag)
	sub_step_acc:                                               u8, // counts fixed steps; fires sim when == SAND_SIM_INTERVAL

	// Interactor footprint cache (set each fixed step, used by sim to block movement into interactor)
	interactor_x0, interactor_y0, interactor_x1, interactor_y1: int,
	interactor_blocking:                                        bool,

	// Injected external constants (set by caller before init)
	gravity:                                                    f32,
	run_speed:                                                  f32,
	wall_detect_eps:                                            f32,
	fixed_dt:                                                   f32,
}

// Grid accessors

get :: proc(world: ^World, x, y: int) -> Cell {
	if x < 0 || x >= world.width || y < 0 || y >= world.height do return Cell{material = .Solid}
	return world.cells[y * world.width + x]
}

in_bounds :: proc(world: ^World, x, y: int) -> bool {
	return x >= 0 && x < world.width && y >= 0 && y < world.height
}

get_slope :: proc(world: ^World, x, y: int) -> Slope_Kind {
	if x < 0 || x >= world.width || y < 0 || y >= world.height do return .None
	return world.slopes[y * world.width + x]
}

// Wake neighbors, mark chunks dirty, transfer active counts across chunk boundaries.
finalize_move :: proc(world: ^World, sx, sy, dx, dy: int) {
	wake_neighbors(world, sx, sy)
	wake_neighbors(world, dx, dy)
	chunk_mark_dirty(world, sx, sy)
	chunk_mark_dirty(world, dx, dy)
	if sx / int(SAND_CHUNK_SIZE) != dx / int(SAND_CHUNK_SIZE) ||
	   sy / int(SAND_CHUNK_SIZE) != dy / int(SAND_CHUNK_SIZE) {
		src_chunk := chunk_at(world, sx, sy)
		dst_chunk := chunk_at(world, dx, dy)
		if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
		if dst_chunk != nil do dst_chunk.active_count += 1
	}
}

is_interactor_cell :: proc(world: ^World, x, y: int) -> bool {
	if !world.interactor_blocking do return false
	return(
		x >= world.interactor_x0 &&
		x <= world.interactor_x1 &&
		y >= world.interactor_y0 &&
		y <= world.interactor_y1 \
	)
}

wake_neighbors :: proc(world: ^World, x, y: int) {
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 do continue
			nx, ny := x + dx, y + dy
			if !in_bounds(world, nx, ny) do continue
			cell := &world.cells[ny * world.width + nx]
			if cell.material == .Sand || cell.material == .Wet_Sand || cell.material == .Water do cell.sleep_counter = 0
		}
	}
}

// Abstract level tile kind for init (mirrors Level_Tile_Kind subset relevant to sand)
Tile_Kind :: enum u8 {
	Empty,
	Solid,
	Platform,
	Slope_Right,
	Slope_Left,
	Slope_Ceil_Right,
	Slope_Ceil_Left,
}

// Level data needed for sand world initialization (caller populates, sand consumes)
Level_Data :: struct {
	width, height:  int,
	tiles:          []Tile_Kind, // current tiles (post-reclassification)
	original_tiles: []Tile_Kind, // pre-reclassification
	sand_piles:     [][2]int,
	sand_emitters:  [][2]int,
	water_piles:    [][2]int,
	water_emitters: [][2]int,
}

init :: proc(world: ^World, level: ^Level_Data) {
	world.width = level.width * int(SAND_CELLS_PER_TILE)
	world.height = level.height * int(SAND_CELLS_PER_TILE)
	n := world.width * world.height
	world.cells = make([]Cell, n)
	world.slopes = make([]Slope_Kind, n)
	world.step_counter = 1
	world.sub_step_acc = 0

	chunk_init(world)

	// Populate grid from level tiles. Surface floor slopes (post-reclassification)
	// become slope cells with Empty material; everything else solid/slope -> Solid.
	// Each level tile maps to SAND_CELLS_PER_TILE x SAND_CELLS_PER_TILE sand cells.
	for tile_y in 0 ..< level.height {
		for tile_x in 0 ..< level.width {
			tile_idx := tile_y * level.width + tile_x
			tile := level.tiles[tile_idx]
			orig := level.original_tiles[tile_idx]

			for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
				for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
					sx := tile_x * int(SAND_CELLS_PER_TILE) + cell_dx
					sy := tile_y * int(SAND_CELLS_PER_TILE) + cell_dy
					si := sy * world.width + sx

					if tile == .Slope_Right {
						// / diagonal: solid below, open above
						if cell_dx == cell_dy {
							world.slopes[si] = .Right
						} else if cell_dx > cell_dy {
							world.cells[si].material = .Solid
							world.cells[si].color_variant = wang_hash(sx, sy)
						}
					} else if tile == .Slope_Left {
						// \ diagonal: solid below, open above
						sum := cell_dx + cell_dy
						if sum == int(SAND_CELLS_PER_TILE) - 1 {
							world.slopes[si] = .Left
						} else if sum < int(SAND_CELLS_PER_TILE) - 1 {
							world.cells[si].material = .Solid
							world.cells[si].color_variant = wang_hash(sx, sy)
						}
					} else if orig == .Solid ||
					   orig == .Slope_Right ||
					   orig == .Slope_Left ||
					   orig == .Slope_Ceil_Right ||
					   orig == .Slope_Ceil_Left {
						world.cells[si].material = .Solid
						world.cells[si].color_variant = wang_hash(sx, sy)
					} else if orig == .Platform do world.cells[si].material = .Platform
				}
			}
		}
	}

	load_piles(world, level.sand_piles, .Sand)
	load_piles(world, level.water_piles, .Water)

	for pos in level.sand_emitters do append(&world.emitters, Emitter{tx = pos.x, ty = pos.y, material = .Sand})
	for pos in level.water_emitters do append(&world.emitters, Emitter{tx = pos.x, ty = pos.y, material = .Water})

	chunk_recount(world)
}

destroy :: proc(world: ^World) {
	delete(world.cells)
	delete(world.slopes)
	delete(world.chunks)
	delete(world.emitters)
	delete(world.eroded_platforms)
}

@(private = "file")
wang_hash :: proc(x, y: int) -> u8 {
	h := u32(x * 374761393 + y * 668265263)
	h = (h ~ (h >> 15)) * 2246822519
	h = (h ~ (h >> 13)) * 3266489917
	h = (h ~ (h >> 16))
	return u8(h & 3)
}

@(private = "file")
load_piles :: proc(world: ^World, piles: [][2]int, material: Material) {
	for pos in piles {
		for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
			for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
				sx := pos.x * int(SAND_CELLS_PER_TILE) + cell_dx
				sy := pos.y * int(SAND_CELLS_PER_TILE) + cell_dy
				idx := sy * world.width + sx
				world.cells[idx].material = material
				world.cells[idx].color_variant = wang_hash(sx, sy)
				chunk_mark_dirty(world, sx, sy)
			}
		}
	}
}
