package engine

import "core:math"
import "core:math/rand"

// --- Materials & Properties ---

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

// Movement archetype for cellular automaton dispatch
Sand_Behavior :: enum u8 {
	Static, // immovable (Solid, Platform, Empty)
	Powder, // granular: falls, piles with diagonal repose (Sand, Wet_Sand)
	Liquid, // fluid: falls, flows horizontally, pressure-driven rise (Water)
	Gas, // rises (future use)
}

// Data-driven material properties for simulation dispatch
Sand_Material_Props :: struct {
	behavior: Sand_Behavior,
	density:  u8, // higher density sinks below lower; 0 = displaceable by anything
	inert:    bool, // skip simulation dispatch entirely
}

// Single source of truth for material physics.
// Density ordering drives buoyancy: Wet_Sand(4) > Sand(3) > Water(1) > Empty(0).
SAND_MAT_PROPS := [Sand_Material]Sand_Material_Props {
	.Empty = {behavior = .Static, density = 0, inert = true},
	.Solid = {behavior = .Static, density = 255, inert = true},
	.Sand = {behavior = .Powder, density = 3, inert = false},
	.Water = {behavior = .Liquid, density = 1, inert = false},
	.Platform = {behavior = .Static, density = 255, inert = true},
	.Wet_Sand = {behavior = .Powder, density = 4, inert = false},
}

// --- Cell & Flag layout ---

Sand_Cell :: struct {
	material:      Sand_Material, // 1 byte
	sleep_counter: u8, // frames without movement; sleeps at threshold
	color_variant: u8, // 0-3, random brightness offset for visual variety
	flags:         u8, // bit 0: parity, bits 1-3: fall_count (0-7), bits 4-5: flow dir (Water) / dry counter (Wet_Sand)
}

SAND_FLAG_PARITY :: u8(0x01) // bit 0
SAND_FLAG_FALL_MASK :: u8(0x0E) // bits 1-3
SAND_FLAG_FALL_SHIFT :: u8(1)
SAND_FLAG_FLOW_MASK :: u8(0x30) // bits 4-5 (water flow direction)
SAND_FLAG_FLOW_LEFT :: u8(0x10) // 01 = flowed left
SAND_FLAG_FLOW_RIGHT :: u8(0x20) // 10 = flowed right
SAND_FLAG_DRY_MASK :: u8(0x30) // bits 4-5 (Wet_Sand drying counter, same bits as flow — no conflict)
SAND_FLAG_DRY_SHIFT :: u8(4)

@(private = "file")
sand_cell_fall_count :: proc(cell: ^Sand_Cell) -> u8 {
	return (cell.flags & SAND_FLAG_FALL_MASK) >> SAND_FLAG_FALL_SHIFT
}

@(private = "file")
sand_cell_set_fall_count :: proc(cell: ^Sand_Cell, count: u8) {
	cell.flags = (cell.flags & ~SAND_FLAG_FALL_MASK) | (min(count, 7) << SAND_FLAG_FALL_SHIFT)
}

@(private = "file")
sand_cell_reset_fall :: proc(cell: ^Sand_Cell) {
	cell.flags &= ~SAND_FLAG_FALL_MASK
}

// --- Chunk ---

Sand_Chunk :: struct {
	active_count: u16, // non-Empty, non-Solid cells in chunk
	dirty:        bool, // a particle moved in/out this step
	needs_sim:    bool, // dirty OR neighbor dirty -> participate in next step
}

sand_chunk_at :: proc(world: ^Sand_World, tx, ty: int) -> ^Sand_Chunk {
	cx := tx / int(SAND_CHUNK_SIZE)
	cy := ty / int(SAND_CHUNK_SIZE)
	if cx < 0 || cx >= world.chunks_w || cy < 0 || cy >= world.chunks_h do return nil
	return &world.chunks[cy * world.chunks_w + cx]
}

sand_chunk_mark_dirty :: proc(world: ^Sand_World, tx, ty: int) {
	chunk := sand_chunk_at(world, tx, ty)
	if chunk != nil do chunk.dirty = true
}

@(private = "file")
sand_chunk_init :: proc(world: ^Sand_World) {
	world.chunks_w = (world.width + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	world.chunks_h = (world.height + int(SAND_CHUNK_SIZE) - 1) / int(SAND_CHUNK_SIZE)
	world.chunks = make([]Sand_Chunk, world.chunks_w * world.chunks_h)
}

// Propagate dirty flags: any chunk that is dirty, or has a dirty neighbor, needs simulation
@(private = "file")
sand_chunk_propagate_dirty :: proc(world: ^Sand_World) {
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
@(private = "file")
sand_chunk_recount :: proc(world: ^Sand_World) {
	for &chunk in world.chunks do chunk.active_count = 0
	for y in 0 ..< world.height {
		for x in 0 ..< world.width {
			cell := world.cells[y * world.width + x]
			if cell.material != .Empty && cell.material != .Solid {
				chunk := sand_chunk_at(world, x, y)
				if chunk != nil do chunk.active_count += 1
			}
		}
	}
	// Mark chunks with active particles as dirty so they get simulated on first step
	for &chunk in world.chunks do if chunk.active_count > 0 do chunk.dirty = true
}

// --- Interactor ---

Sand_Interactor :: struct {
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

// --- Emitter ---

Sand_Emitter :: struct {
	tx, ty:      int, // tile coordinates of emitter
	accumulator: f32, // fractional particle accumulation
	material:    Sand_Material, // what this emitter spawns (.Sand or .Water)
}

// --- World ---

Sand_World :: struct {
	width, height:                                              int, // grid dimensions (= level dimensions * SAND_CELLS_PER_TILE)
	cells:                                                      []Sand_Cell, // flat [y * width + x], y=0 = bottom
	slopes:                                                     []Sand_Slope_Kind, // parallel to cells; immutable structural data from level

	// Chunks
	chunks_w, chunks_h:                                         int,
	chunks:                                                     []Sand_Chunk,

	// Emitters
	emitters:                                                   [dynamic]Sand_Emitter,

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

// --- Level data for init ---

Sand_Tile_Kind :: enum u8 {
	Empty,
	Solid,
	Platform,
	Slope_Right,
	Slope_Left,
	Slope_Ceil_Right,
	Slope_Ceil_Left,
}

Sand_Level_Data :: struct {
	width, height:  int,
	tiles:          []Sand_Tile_Kind, // current tiles (post-reclassification)
	original_tiles: []Sand_Tile_Kind, // pre-reclassification
	sand_piles:     [][2]int,
	sand_emitters:  [][2]int,
	water_piles:    [][2]int,
	water_emitters: [][2]int,
}

// --- Grid accessors ---

sand_get :: proc(world: ^Sand_World, x, y: int) -> Sand_Cell {
	if x < 0 || x >= world.width || y < 0 || y >= world.height do return Sand_Cell{material = .Solid}
	return world.cells[y * world.width + x]
}

sand_in_bounds :: proc(world: ^Sand_World, x, y: int) -> bool {
	return x >= 0 && x < world.width && y >= 0 && y < world.height
}

sand_get_slope :: proc(world: ^Sand_World, x, y: int) -> Sand_Slope_Kind {
	if x < 0 || x >= world.width || y < 0 || y >= world.height do return .None
	return world.slopes[y * world.width + x]
}

// --- Init / Destroy ---

sand_init :: proc(world: ^Sand_World, level: ^Sand_Level_Data) {
	world.width = level.width * int(SAND_CELLS_PER_TILE)
	world.height = level.height * int(SAND_CELLS_PER_TILE)
	n := world.width * world.height
	world.cells = make([]Sand_Cell, n)
	world.slopes = make([]Sand_Slope_Kind, n)
	world.step_counter = 1
	world.sub_step_acc = 0

	sand_chunk_init(world)

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
							world.cells[si].color_variant = sand_wang_hash(sx, sy)
						}
					} else if tile == .Slope_Left {
						// \ diagonal: solid below, open above
						sum := cell_dx + cell_dy
						if sum == int(SAND_CELLS_PER_TILE) - 1 {
							world.slopes[si] = .Left
						} else if sum < int(SAND_CELLS_PER_TILE) - 1 {
							world.cells[si].material = .Solid
							world.cells[si].color_variant = sand_wang_hash(sx, sy)
						}
					} else if orig == .Solid ||
					   orig == .Slope_Right ||
					   orig == .Slope_Left ||
					   orig == .Slope_Ceil_Right ||
					   orig == .Slope_Ceil_Left {
						world.cells[si].material = .Solid
						world.cells[si].color_variant = sand_wang_hash(sx, sy)
					} else if orig == .Platform do world.cells[si].material = .Platform
				}
			}
		}
	}

	sand_load_piles(world, level.sand_piles, .Sand)
	sand_load_piles(world, level.water_piles, .Water)

	for pos in level.sand_emitters do append(&world.emitters, Sand_Emitter{tx = pos.x, ty = pos.y, material = .Sand})
	for pos in level.water_emitters do append(&world.emitters, Sand_Emitter{tx = pos.x, ty = pos.y, material = .Water})

	sand_chunk_recount(world)
}

sand_destroy :: proc(world: ^Sand_World) {
	delete(world.cells)
	delete(world.slopes)
	delete(world.chunks)
	delete(world.emitters)
	delete(world.eroded_platforms)
}

@(private = "file")
sand_wang_hash :: proc(x, y: int) -> u8 {
	h := u32(x * 374761393 + y * 668265263)
	h = (h ~ (h >> 15)) * 2246822519
	h = (h ~ (h >> 13)) * 3266489917
	h = (h ~ (h >> 16))
	return u8(h & 3)
}

@(private = "file")
sand_load_piles :: proc(world: ^Sand_World, piles: [][2]int, material: Sand_Material) {
	for pos in piles {
		for cell_dy in 0 ..< int(SAND_CELLS_PER_TILE) {
			for cell_dx in 0 ..< int(SAND_CELLS_PER_TILE) {
				sx := pos.x * int(SAND_CELLS_PER_TILE) + cell_dx
				sy := pos.y * int(SAND_CELLS_PER_TILE) + cell_dy
				idx := sy * world.width + sx
				world.cells[idx].material = material
				world.cells[idx].color_variant = sand_wang_hash(sx, sy)
				sand_chunk_mark_dirty(world, sx, sy)
			}
		}
	}
}

// --- Internal helpers ---

// Wake neighbors, mark chunks dirty, transfer active counts across chunk boundaries.
@(private = "file")
sand_finalize_move :: proc(world: ^Sand_World, sx, sy, dx, dy: int) {
	sand_wake_neighbors(world, sx, sy)
	sand_wake_neighbors(world, dx, dy)
	sand_chunk_mark_dirty(world, sx, sy)
	sand_chunk_mark_dirty(world, dx, dy)
	if sx / int(SAND_CHUNK_SIZE) != dx / int(SAND_CHUNK_SIZE) ||
	   sy / int(SAND_CHUNK_SIZE) != dy / int(SAND_CHUNK_SIZE) {
		src_chunk := sand_chunk_at(world, sx, sy)
		dst_chunk := sand_chunk_at(world, dx, dy)
		if src_chunk != nil && src_chunk.active_count > 0 do src_chunk.active_count -= 1
		if dst_chunk != nil do dst_chunk.active_count += 1
	}
}

@(private = "file")
sand_is_interactor_cell :: proc(world: ^Sand_World, x, y: int) -> bool {
	if !world.interactor_blocking do return false
	return(
		x >= world.interactor_x0 &&
		x <= world.interactor_x1 &&
		y >= world.interactor_y0 &&
		y <= world.interactor_y1 \
	)
}

@(private = "file")
sand_wake_neighbors :: proc(world: ^Sand_World, x, y: int) {
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 do continue
			nx, ny := x + dx, y + dy
			if !sand_in_bounds(world, nx, ny) do continue
			cell := &world.cells[ny * world.width + nx]
			if cell.material == .Sand || cell.material == .Wet_Sand || cell.material == .Water do cell.sleep_counter = 0
		}
	}
}

// --- Interaction ---

// Compute immersion ratio (0.0-1.0) for a set of materials in an AABB footprint
sand_compute_immersion :: proc(
	world: ^Sand_World,
	pos: [2]f32,
	size: f32,
	materials: bit_set[Sand_Material],
) -> f32 {
	if world.width == 0 || world.height == 0 do return 0
	x0, y0, x1, y1 := sand_footprint_cells(world, pos, size)
	total := max((x1 - x0 + 1) * (y1 - y0 + 1), 1)
	count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if sand_in_bounds(world, tx, ty) && sand_get(world, tx, ty).material in materials do count += 1
		}
	}
	return f32(count) / f32(total)
}

// Find topmost sand cell surface Y in a column near the player's feet
@(private = "file")
sand_column_surface_y :: proc(world: ^Sand_World, gx, base_gy, scan_height: int) -> (f32, bool) {
	for gy := base_gy + scan_height; gy >= max(base_gy - 1, 0); gy -= 1 {
		if !sand_in_bounds(world, gx, gy) do continue
		col_mat := sand_get(world, gx, gy).material
		if col_mat == .Sand || col_mat == .Wet_Sand do return f32(gy + 1) * SAND_CELL_SIZE, true
	}
	return 0, false
}

// Interpolated sand surface height at a given X position and base Y
sand_surface_query :: proc(world: ^Sand_World, center_x, base_y: f32) -> (f32, bool) {
	center_gx := int(center_x / SAND_CELL_SIZE)
	base_gy := int(base_y / SAND_CELL_SIZE)
	scan := int(SAND_SURFACE_SCAN_HEIGHT)

	left_y, left_ok := sand_column_surface_y(world, center_gx, base_gy, scan)
	if !left_ok do return 0, false

	frac_x := center_x / SAND_CELL_SIZE - f32(center_gx)
	adj_gx := center_gx + 1 if frac_x >= 0.5 else center_gx - 1

	right_y, right_ok := sand_column_surface_y(world, adj_gx, base_gy, scan)
	if !right_ok do return left_y, true

	if adj_gx > center_gx do return math.lerp(left_y, right_y, frac_x), true
	return math.lerp(right_y, left_y, frac_x), true
}

// Count contiguous sand/wet sand cells in a column from ty_start to ty_end (inclusive)
@(private = "file")
sand_count_wall_column :: proc(world: ^Sand_World, tx, ty_start, ty_end: int) -> int {
	count := 0
	for ty in ty_start ..= ty_end {
		if !sand_in_bounds(world, tx, ty) do break
		mat := sand_get(world, tx, ty).material
		if mat != .Sand && mat != .Wet_Sand do break
		count += 1
	}
	return count
}

// Detect a sand wall adjacent to an AABB (left or right column)
sand_detect_wall :: proc(world: ^Sand_World, pos: [2]f32, size: f32) -> (bool, f32, f32) {
	if world.width == 0 || world.height == 0 do return false, 0, 0

	gy_start := int(pos.y / SAND_CELL_SIZE)
	gy_end := int((pos.y + size) / SAND_CELL_SIZE)

	left_x := pos.x - size / 2 - world.wall_detect_eps
	left_gx := int(left_x / SAND_CELL_SIZE)
	if sand_in_bounds(world, left_gx, gy_start) {
		count := sand_count_wall_column(world, left_gx, gy_start, gy_end)
		if count >= int(SAND_WALL_MIN_HEIGHT) {
			snap_x := f32(left_gx + 1) * SAND_CELL_SIZE + size / 2
			return true, -1, snap_x
		}
	}

	right_x := pos.x + size / 2 + world.wall_detect_eps
	right_gx := int(right_x / SAND_CELL_SIZE)
	if sand_in_bounds(world, right_gx, gy_start) {
		count := sand_count_wall_column(world, right_gx, gy_start, gy_end)
		if count >= int(SAND_WALL_MIN_HEIGHT) {
			snap_x := f32(right_gx) * SAND_CELL_SIZE - size / 2
			return true, 1, snap_x
		}
	}

	return false, 0, 0
}

// Erode sand wall: remove cells from the wall column near a position
sand_wall_erode :: proc(world: ^Sand_World, pos: [2]f32, size, dir: f32) {
	if world.width == 0 || world.height == 0 do return

	wall_x := pos.x + dir * (size / 2 + world.wall_detect_eps)
	wall_gx := int(wall_x / SAND_CELL_SIZE)
	center_gy := int((pos.y + size / 2) / SAND_CELL_SIZE)
	push_dx: int = dir > 0 ? 1 : -1

	for _ in 0 ..< int(SAND_WALL_ERODE_RATE) {
		for try_gy in ([3]int{center_gy, center_gy + 1, center_gy - 1}) {
			if !sand_in_bounds(world, wall_gx, try_gy) do continue
			mat := sand_get(world, wall_gx, try_gy).material
			if mat != .Sand && mat != .Wet_Sand do continue
			sand_displace_cell(world, wall_gx, try_gy, push_dx)
			break
		}
	}
}

// Interactor-sand/water coupling: displacement, drag, pressure, burial, buoyancy
sand_interact :: proc(world: ^Sand_World, it: ^Sand_Interactor, dt: f32) {
	if world.width == 0 || world.height == 0 do return

	x0, y0, x1, y1 := sand_footprint_cells(world, it.pos, it.size)
	world.interactor_x0 = x0
	world.interactor_y0 = y0
	world.interactor_x1 = x1
	world.interactor_y1 = y1
	world.interactor_blocking = true

	if it.is_dashing {
		sand_dash_carve(world, it, dt)
		return
	}

	impact_factor: f32 = 0
	if it.impact_pending > 0 {
		speed := it.impact_pending
		it.impact_pending = 0
		range := SAND_IMPACT_MAX_SPEED - SAND_IMPACT_MIN_SPEED
		if range > 0 do impact_factor = math.clamp((speed - SAND_IMPACT_MIN_SPEED) / range, 0, 1)
	}
	it.out_impact_factor = impact_factor

	extra := int(impact_factor * f32(SAND_IMPACT_RADIUS))
	cx0 := max(x0 - extra, 0)
	cy0 := max(y0 - extra, 0)
	cx1 := min(x1 + extra, world.width - 1)

	sand_displaced := 0
	wet_sand_displaced := 0
	water_displaced := 0
	center_cx := int(it.pos.x / SAND_CELL_SIZE)

	for ty in cy0 ..= y1 {
		for tx in cx0 ..= cx1 {
			if !sand_in_bounds(world, tx, ty) do continue
			mat := world.cells[ty * world.width + tx].material
			if mat != .Sand && mat != .Wet_Sand && mat != .Water do continue

			push_dx: int = tx >= center_cx ? 1 : -1
			in_ring := tx < x0 || tx > x1 || ty < y0

			displaced := false
			if in_ring && impact_factor > 0 {
				displaced = sand_eject_cell_up(world, tx, ty, y1, push_dx)
			} else {
				displaced = sand_displace_cell(world, tx, ty, push_dx)
			}

			if displaced {
				if mat == .Water do water_displaced += 1
				else if mat == .Wet_Sand do wet_sand_displaced += 1
				else do sand_displaced += 1
			}
		}
	}

	it.out_sand_displaced = sand_displaced
	it.out_wet_sand_displaced = wet_sand_displaced
	it.out_water_displaced = water_displaced

	surf_y, surf_ok := sand_surface_query(world, it.pos.x, it.pos.y)
	it.out_surface_y = surf_y
	it.out_surface_found = surf_ok

	if it.is_submerged {
		if sand_displaced > 0 do sand_apply_drag(&it.vel, SAND_SWIM_DRAG_FACTOR * SAND_PLAYER_DRAG_MAX, SAND_PLAYER_DRAG_Y_FACTOR, false)
		if wet_sand_displaced > 0 do sand_apply_drag(&it.vel, SAND_SWIM_DRAG_FACTOR * WET_SAND_PLAYER_DRAG_MAX, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
		if water_displaced > 0 do sand_apply_drag(&it.vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)
	} else {
		if sand_displaced > 0 {
			immersion := it.sand_immersion
			sand_apply_drag(
				&it.vel,
				immersion * immersion * SAND_PLAYER_DRAG_MAX,
				SAND_PLAYER_DRAG_Y_FACTOR,
				true,
			)
		}
		if wet_sand_displaced > 0 {
			drag := min(
				f32(wet_sand_displaced) * WET_SAND_PLAYER_DRAG_PER_CELL,
				WET_SAND_PLAYER_DRAG_MAX,
			)
			sand_apply_drag(&it.vel, drag, WET_SAND_PLAYER_DRAG_Y_FACTOR, true)
		}
		if water_displaced > 0 do sand_apply_drag(&it.vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)

		above_count := 0
		for tx in x0 ..= x1 {
			gap := 0
			for ty := y1 + 1; ty < world.height; ty += 1 {
				cell := sand_get(world, tx, ty)
				if cell.material == .Sand || cell.material == .Wet_Sand {
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
			it.vel.y -= capped * SAND_PRESSURE_FORCE * dt
		}

		if it.sand_immersion > SAND_BURIAL_THRESHOLD && it.vel.y <= 0 {
			activity := math.clamp(
				math.abs(it.vel.x) / world.run_speed,
				0,
				SAND_QUICKSAND_MAX_ACTIVITY,
			)
			base_sink := SAND_QUICKSAND_BASE_SINK * world.gravity * dt
			move_sink := SAND_QUICKSAND_MOVE_MULT * activity * world.gravity * dt
			it.vel.y -= base_sink + move_sink
		}
	}

	water_immersion := sand_compute_immersion(world, it.pos, it.size, {.Water})
	if water_immersion > WATER_BUOYANCY_THRESHOLD {
		buoyancy := water_immersion * WATER_BUOYANCY_FORCE
		it.vel.y += buoyancy * dt
	}

	flow_sum: f32 = 0
	flow_count := 0
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if !sand_in_bounds(world, tx, ty) do continue
			cell := world.cells[ty * world.width + tx]
			if cell.material != .Water do continue
			flow_dir := cell.flags & SAND_FLAG_FLOW_MASK
			if flow_dir ==
			   SAND_FLAG_FLOW_LEFT {flow_sum -= 1; flow_count += 1} else if flow_dir == SAND_FLAG_FLOW_RIGHT {flow_sum += 1; flow_count += 1}
		}
	}
	if flow_count > 0 {
		current_avg := flow_sum / f32(flow_count)
		it.vel.x += current_avg * WATER_CURRENT_FORCE * dt
	}
}

// Carve tunnel through sand during dash
@(private = "file")
sand_dash_carve :: proc(world: ^Sand_World, it: ^Sand_Interactor, dt: f32) {
	prev_x := it.pos.x - it.vel.x * dt
	curr_x := it.pos.x

	gx_start := max(int(math.min(prev_x, curr_x) / SAND_CELL_SIZE) - 1, 0)
	gx_end := min(int(math.max(prev_x, curr_x) / SAND_CELL_SIZE) + 1, world.width - 1)
	gy_start := max(int(it.pos.y / SAND_CELL_SIZE), 0)
	gy_end := min(int((it.pos.y + it.size) / SAND_CELL_SIZE), world.height - 1)

	sand_carved := 0
	water_carved := 0
	push_dx: int = it.vel.x > 0 ? 1 : -1

	for gx in gx_start ..= gx_end {
		for gy in gy_start ..= gy_end {
			if !sand_in_bounds(world, gx, gy) do continue
			idx := gy * world.width + gx
			mat := world.cells[idx].material
			if mat != .Sand && mat != .Wet_Sand && mat != .Water do continue

			if !sand_eject_cell_up(world, gx, gy, gy_end, push_dx) do continue
			if mat == .Sand || mat == .Wet_Sand do sand_carved += 1
			else do water_carved += 1
		}
	}

	it.out_sand_displaced = sand_carved
	it.out_water_displaced = water_carved

	fx0, fy0, fx1, fy1 := sand_footprint_cells(world, it.pos, it.size)
	sand_count := 0
	wet_sand_count := 0
	water_count := 0
	for ty in fy0 ..= fy1 {
		for tx in fx0 ..= fx1 {
			if !sand_in_bounds(world, tx, ty) do continue
			mat := world.cells[ty * world.width + tx].material
			if mat == .Sand do sand_count += 1
			else if mat == .Wet_Sand do wet_sand_count += 1
			else if mat == .Water do water_count += 1
		}
	}
	if sand_count > 0 do sand_apply_drag(&it.vel, min(f32(sand_count) * SAND_PLAYER_DRAG_PER_CELL, SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, SAND_PLAYER_DRAG_Y_FACTOR, false)
	if wet_sand_count > 0 do sand_apply_drag(&it.vel, min(f32(wet_sand_count) * WET_SAND_PLAYER_DRAG_PER_CELL, WET_SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
	if water_count > 0 do sand_apply_drag(&it.vel, min(f32(water_count) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WATER_PLAYER_DRAG_Y_FACTOR, false)
}

@(private = "file")
sand_apply_drag :: proc(vel: ^[2]f32, drag, y_factor: f32, skip_positive_y: bool) {
	vel.x *= (1.0 - drag)
	if !skip_positive_y || vel.y <= 0 do vel.y *= (1.0 - drag * y_factor)
}

// Compute the cell range overlapping an AABB given bottom-center pos and square size
@(private = "file")
sand_footprint_cells :: proc(world: ^Sand_World, pos: [2]f32, size: f32) -> (x0, y0, x1, y1: int) {
	x0 = int((pos.x - size / 2) / SAND_CELL_SIZE)
	y0 = int(pos.y / SAND_CELL_SIZE)
	x1 = int((pos.x + size / 2) / SAND_CELL_SIZE)
	y1 = int((pos.y + size) / SAND_CELL_SIZE)

	x0 = math.clamp(x0, 0, world.width - 1)
	y0 = math.clamp(y0, 0, world.height - 1)
	x1 = math.clamp(x1, 0, world.width - 1)
	y1 = math.clamp(y1, 0, world.height - 1)
	return
}

// Try to displace a sand/water cell at (tx,ty) in push_dx direction.
// Slope-aware: aligns push directions with slope surface geometry.
@(private = "file")
sand_displace_cell :: proc(world: ^Sand_World, tx, ty, push_dx: int) -> bool {
	slope := sand_get_slope(world, tx, ty)

	if slope == .Right {
		if push_dx < 0 {
			if sand_try_displace_to(world, tx, ty, tx - 1, ty - 1) do return true
			if sand_try_displace_to(world, tx, ty, tx - 1, ty) do return true
		} else {
			if sand_try_displace_to(world, tx, ty, tx + 1, ty + 1) do return true
			if sand_try_displace_to(world, tx, ty, tx + 1, ty) do return true
		}
		if sand_try_displace_to(world, tx, ty, tx, ty + 1) do return true
	} else if slope == .Left {
		if push_dx > 0 {
			if sand_try_displace_to(world, tx, ty, tx + 1, ty - 1) do return true
			if sand_try_displace_to(world, tx, ty, tx + 1, ty) do return true
		} else {
			if sand_try_displace_to(world, tx, ty, tx - 1, ty + 1) do return true
			if sand_try_displace_to(world, tx, ty, tx - 1, ty) do return true
		}
		if sand_try_displace_to(world, tx, ty, tx, ty + 1) do return true
	}

	if sand_try_displace_to(world, tx, ty, tx + push_dx, ty) do return true
	if slope == .None {
		if sand_try_displace_to(world, tx, ty, tx, ty - 1) do return true
	}
	if slope == .None || (slope == .Right && push_dx < 0) || (slope == .Left && push_dx > 0) {
		if sand_try_displace_to(world, tx, ty, tx + push_dx, ty - 1) do return true
	}
	if sand_try_displace_to(world, tx, ty, tx - push_dx, ty) do return true
	if slope == .None || (slope == .Right && push_dx > 0) || (slope == .Left && push_dx < 0) {
		if sand_try_displace_to(world, tx, ty, tx - push_dx, ty - 1) do return true
	}
	return false
}

// Try to move a cell from (sx,sy) to (dx,dy) for displacement.
// Chain displacement: if destination is sand or water, recursively push it further.
@(private = "file")
sand_try_displace_to :: proc(world: ^Sand_World, sx, sy, dx, dy: int, depth: int = 0) -> bool {
	if !sand_in_bounds(world, dx, dy) do return false
	if sand_is_interactor_cell(world, dx, dy) do return false
	dst_idx := dy * world.width + dx
	dst_mat := world.cells[dst_idx].material

	if (dst_mat == .Sand || dst_mat == .Wet_Sand || dst_mat == .Water) &&
	   depth < int(SAND_DISPLACE_CHAIN) {
		if sand_get_slope(world, dx, dy) != .None do return false
		chain_dx := dx + (dx - sx)
		chain_dy := dy + (dy - sy)
		if !sand_try_displace_to(world, dx, dy, chain_dx, chain_dy, depth + 1) do return false
	} else if dst_mat != .Empty do return false

	src_idx := sy * world.width + sx
	world.cells[dst_idx] = world.cells[src_idx]
	world.cells[dst_idx].sleep_counter = 0
	sand_cell_reset_fall(&world.cells[dst_idx])
	world.cells[src_idx] = Sand_Cell{}
	sand_finalize_move(world, sx, sy, dx, dy)

	return true
}

// Eject a sand/water cell upward (for crater rim splash), fallback to sideways
@(private = "file")
sand_eject_cell_up :: proc(world: ^Sand_World, tx, ty, ceil_ty, push_dx: int) -> bool {
	for eject_y := ceil_ty + 1;
	    eject_y < min(ceil_ty + int(SAND_EJECT_MAX_HEIGHT), world.height);
	    eject_y += 1 {
		if !sand_in_bounds(world, tx, eject_y) do continue
		if world.cells[eject_y * world.width + tx].material != .Empty do continue

		src_idx := ty * world.width + tx
		dst_idx := eject_y * world.width + tx
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].sleep_counter = 0
		sand_cell_reset_fall(&world.cells[dst_idx])
		world.cells[src_idx] = Sand_Cell{}
		sand_finalize_move(world, tx, ty, tx, eject_y)
		return true
	}
	return sand_displace_cell(world, tx, ty, push_dx)
}

// --- Particles ---

// Emit displacement particles in a directional cone from a surface point
sand_particles_emit :: proc(
	pool: ^Particle_Pool,
	pos: [2]f32,
	spread_x, base_angle, half_spread: f32,
	vel_bias: [2]f32,
	color: [4]u8,
	count: int,
	speed_mult: f32 = 1.0,
) {
	for _ in 0 ..< count {
		spawn_pos := pos + {rand.float32() * spread_x * 2 - spread_x, 0}
		angle := base_angle + (rand.float32() * 2 - 1) * half_spread
		speed :=
			SAND_PARTICLE_SPEED *
			(SAND_PARTICLE_SPEED_RAND_MIN +
					(1.0 - SAND_PARTICLE_SPEED_RAND_MIN) * rand.float32()) *
			speed_mult
		vel := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed} + vel_bias
		particle_pool_emit(
			pool,
			Particle {
				pos = spawn_pos,
				vel = vel,
				lifetime = SAND_PARTICLE_LIFETIME *
				(SAND_PARTICLE_LIFETIME_RAND_MIN +
						(1.0 - SAND_PARTICLE_LIFETIME_RAND_MIN) * rand.float32()),
				age = 0,
				size = SAND_PARTICLE_SIZE,
				color = color,
			},
		)
	}
}

sand_particles_update :: proc(pool: ^Particle_Pool, dt: f32) {
	particle_pool_update(pool, dt)
	for i in 0 ..< pool.count {
		pool.items[i].vel.y -= SAND_PARTICLE_GRAVITY * dt
		pool.items[i].vel *= 1.0 - SAND_PARTICLE_FRICTION * dt
		pool.items[i].pos += pool.items[i].vel * dt
	}
}

// --- Simulation ---

// Tick the sub-step counter; fires step when interval is reached
sand_sub_step_tick :: proc(world: ^Sand_World) {
	world.sub_step_acc += 1
	if world.sub_step_acc >= SAND_SIM_INTERVAL {
		world.sub_step_acc = 0
		sand_step(world)
	}
}

// Core simulation step: cellular automaton rules with sleep/wake
@(private = "file")
sand_step :: proc(world: ^Sand_World) {
	parity := world.step_counter & 1
	world.step_counter += 1
	sand_chunk_propagate_dirty(world)
	for y in 0 ..< world.height {
		if parity == 0 do for x in 0 ..< world.width do sand_dispatch_cell(world, x, y, parity)
		else do for x := world.width - 1; x >= 0; x -= 1 do sand_dispatch_cell(world, x, y, parity)
	}
	sand_restore_platforms(world)
}

// Dispatch cell update using material properties
@(private = "file")
sand_dispatch_cell :: proc(world: ^Sand_World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	props := SAND_MAT_PROPS[cell.material]
	if props.inert do return

	chunk := sand_chunk_at(world, x, y)
	if chunk != nil && !chunk.needs_sim do return
	if u32(cell.flags & SAND_FLAG_PARITY) == (parity & 1) do return

	sand_erode_adjacent_platforms(world, x, y)
	if cell.material == .Water do sand_try_wet_neighbors(world, x, y, WATER_CONTACT_WET_CHANCE)
	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	switch props.behavior {
	case .Powder:
		sand_update_cell_powder(world, x, y, parity)
	case .Liquid:
		sand_update_cell_liquid(world, x, y, parity)
	case .Static, .Gas:
	}
}

// Unified density-based movement. Moves src to dst if target is empty or has lower density.
@(private = "file")
sand_try_move :: proc(world: ^Sand_World, sx, sy, dx, dy: int, parity: u32) -> bool {
	if !sand_in_bounds(world, dx, dy) do return false
	if sand_is_interactor_cell(world, dx, dy) do return false

	src_idx := sy * world.width + sx
	dst_idx := dy * world.width + dx
	src_mat := world.cells[src_idx].material
	dst_mat := world.cells[dst_idx].material

	if dst_mat == .Empty {
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].flags =
			(world.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		world.cells[dst_idx].sleep_counter = 0
		world.cells[src_idx] = Sand_Cell{}
		sand_finalize_move(world, sx, sy, dx, dy)
		return true
	}

	src_density := SAND_MAT_PROPS[src_mat].density
	dst_density := SAND_MAT_PROPS[dst_mat].density

	if src_density > dst_density {
		// Density swap: heavier sinks, lighter rises
		swap_chance: f32 = 1.0
		is_wet := src_mat == .Wet_Sand
		if dst_mat == .Water {
			swap_chance = WET_SAND_WATER_SWAP_CHANCE if is_wet else SAND_WATER_SWAP_CHANCE
		}
		if rand.float32() > swap_chance do return false

		tmp := world.cells[dst_idx]
		world.cells[dst_idx] = world.cells[src_idx]
		world.cells[dst_idx].flags =
			(world.cells[dst_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		world.cells[dst_idx].sleep_counter = 0
		// Reaction: dry sand contacting water becomes wet sand
		if src_mat == .Sand && dst_mat == .Water {
			world.cells[dst_idx].material = .Wet_Sand
			world.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
		}
		world.cells[src_idx] = tmp
		world.cells[src_idx].sleep_counter = 0
		world.cells[src_idx].flags =
			(world.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)

		sand_wake_neighbors(world, sx, sy)
		sand_wake_neighbors(world, dx, dy)
		sand_chunk_mark_dirty(world, sx, sy)
		sand_chunk_mark_dirty(world, dx, dy)
		return true
	}

	return false
}

// Granular material update: slope slide → multi-step descent → diagonal repose
@(private = "file")
sand_update_cell_powder :: proc(world: ^Sand_World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	is_wet := cell.material == .Wet_Sand

	// Slope cells: slide diagonally downhill only
	slope := world.slopes[idx]
	if slope != .None {
		dx: int = slope == .Right ? -1 : 1
		if sand_try_move(world, x, y, x + dx, y - 1, parity) {
			sand_cell_reset_fall(&world.cells[(y - 1) * world.width + (x + dx)])
		} else if cell.sleep_counter < 255 {
			cell.sleep_counter += 1
		}
		if is_wet {sand_try_wet_neighbors(world, x, y, WET_SAND_SPREAD_CHANCE); sand_wet_sand_dry_tick(world, x, y)}
		return
	}

	// Multi-step vertical descent with fall acceleration
	fall_count := sand_cell_fall_count(cell)
	divisor := max(u8(1), SAND_FALL_ACCEL_DIVISOR)
	max_steps := int(min(1 + fall_count / divisor, SAND_FALL_MAX_STEPS))
	src_density := SAND_MAT_PROPS[cell.material].density

	cx, cy := x, y
	steps_taken := 0

	for _ in 0 ..< max_steps {
		if !sand_in_bounds(world, cx, cy - 1) do break
		if sand_is_interactor_cell(world, cx, cy - 1) do break
		dst_idx := (cy - 1) * world.width + cx
		dst_mat := world.cells[dst_idx].material

		if dst_mat == .Empty {
			src_idx := cy * world.width + cx
			world.cells[dst_idx] = world.cells[src_idx]
			world.cells[dst_idx].sleep_counter = 0
			world.cells[src_idx] = Sand_Cell{}
			cy -= 1
			steps_taken += 1
		} else if src_density > SAND_MAT_PROPS[dst_mat].density {
			// Density swap (e.g. sand sinking through water)
			swap_chance: f32 = 1.0
			if dst_mat == .Water {
				swap_chance = WET_SAND_WATER_SWAP_CHANCE if is_wet else SAND_WATER_SWAP_CHANCE
			}
			if rand.float32() > swap_chance do break
			src_idx := cy * world.width + cx
			tmp := world.cells[dst_idx]
			world.cells[dst_idx] = world.cells[src_idx]
			world.cells[dst_idx].sleep_counter = 0
			if dst_mat == .Water {
				world.cells[dst_idx].flags &= ~SAND_FLAG_DRY_MASK
				if !is_wet do world.cells[dst_idx].material = .Wet_Sand
			}
			world.cells[src_idx] = tmp
			world.cells[src_idx].sleep_counter = 0
			world.cells[src_idx].flags =
				(world.cells[src_idx].flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
			sand_cell_reset_fall(&world.cells[dst_idx])
			cy -= 1
			steps_taken += 1
			break
		} else do break
	}

	if steps_taken > 0 {
		final := &world.cells[cy * world.width + cx]
		final.flags = (final.flags & ~SAND_FLAG_PARITY) | u8(parity & 1)
		new_fall := min(fall_count + u8(steps_taken), 7)
		sand_cell_set_fall_count(final, new_fall)
		sand_finalize_move(world, x, y, cx, cy)
		if is_wet {sand_try_wet_neighbors(world, cx, cy, WET_SAND_SPREAD_CHANCE); sand_wet_sand_dry_tick(world, cx, cy)}
		return
	}

	// No downward movement: try diagonal (probability-gated for steeper piles)
	repose_chance: f32 = WET_SAND_REPOSE_CHANCE if is_wet else SAND_REPOSE_CHANCE
	cell = &world.cells[cy * world.width + cx]
	if rand.float32() < repose_chance {
		first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
		if sand_try_move(world, cx, cy, cx + first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&world.cells[(cy - 1) * world.width + (cx + first_dx)])
			if is_wet {sand_try_wet_neighbors(world, cx + first_dx, cy - 1, WET_SAND_SPREAD_CHANCE); sand_wet_sand_dry_tick(world, cx + first_dx, cy - 1)}
			return
		} else if sand_try_move(world, cx, cy, cx - first_dx, cy - 1, parity) {
			sand_cell_reset_fall(&world.cells[(cy - 1) * world.width + (cx - first_dx)])
			if is_wet {sand_try_wet_neighbors(world, cx - first_dx, cy - 1, WET_SAND_SPREAD_CHANCE); sand_wet_sand_dry_tick(world, cx - first_dx, cy - 1)}
			return
		}
	}
	// Stuck
	sand_cell_reset_fall(cell)
	if cell.sleep_counter < 255 do cell.sleep_counter += 1
	if is_wet {sand_try_wet_neighbors(world, cx, cy, WET_SAND_SPREAD_CHANCE); sand_wet_sand_dry_tick(world, cx, cy)}
}

// Liquid material update: down → diagonal → horizontal flow → pressure rise
@(private = "file")
sand_update_cell_liquid :: proc(world: ^Sand_World, x, y: int, parity: u32) {
	idx := y * world.width + x
	slope := world.slopes[idx]
	moved := false

	if slope == .Right {
		if sand_try_move(world, x, y, x - 1, y - 1, parity) do moved = true
		else if sand_try_flow(world, x, y, -1, parity) do moved = true
	} else if slope == .Left {
		if sand_try_move(world, x, y, x + 1, y - 1, parity) do moved = true
		else if sand_try_flow(world, x, y, 1, parity) do moved = true
	} else {
		if sand_try_move(world, x, y, x, y - 1, parity) do moved = true
		else {
			first_dx: int = (rand.int31() & 1) == 0 ? -1 : 1
			if sand_try_move(world, x, y, x + first_dx, y - 1, parity) do moved = true
			else if sand_try_move(world, x, y, x - first_dx, y - 1, parity) do moved = true
			else {
				first_dx2: int = (rand.int31() & 1) == 0 ? -1 : 1
				if sand_try_flow(world, x, y, first_dx2, parity) do moved = true
				else if sand_try_flow(world, x, y, -first_dx2, parity) do moved = true
			}
		}
	}

	if !moved && slope == .None do moved = sand_try_rise(world, x, y, parity)
	if !moved do if world.cells[idx].sleep_counter < 255 do world.cells[idx].sleep_counter += 1
}

// Horizontal multi-cell flow with surface tension
@(private = "file")
sand_try_flow :: proc(world: ^Sand_World, x, y, dx: int, parity: u32) -> bool {
	is_surface :=
		!sand_in_bounds(world, x, y + 1) ||
		world.cells[(y + 1) * world.width + x].material != .Water
	if is_surface {
		depth_below := 0
		for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
			if world.cells[scan_y * world.width + x].material != .Water do break
			depth_below += 1
		}
		if depth_below < int(WATER_SURFACE_TENSION_DEPTH) {
			has_water_neighbor :=
				(sand_in_bounds(world, x - 1, y) &&
					world.cells[y * world.width + (x - 1)].material == .Water) ||
				(sand_in_bounds(world, x + 1, y) &&
						world.cells[y * world.width + (x + 1)].material == .Water)
			if !has_water_neighbor do return false
		}
	}

	depth := 0
	for scan_y := y + 1; scan_y < world.height; scan_y += 1 {
		if world.cells[scan_y * world.width + x].material != .Water do break
		depth += 1
		if depth >= int(WATER_FLOW_DISTANCE) do break
	}
	max_flow := min(1 + depth, int(WATER_FLOW_DISTANCE))

	target_x := -1
	for i in 1 ..= max_flow {
		nx := x + i * dx
		if !sand_in_bounds(world, nx, y) do break
		if sand_is_interactor_cell(world, nx, y) do break
		if world.cells[y * world.width + nx].material != .Empty do break

		below_empty :=
			sand_in_bounds(world, nx, y - 1) &&
			world.cells[(y - 1) * world.width + nx].material == .Empty
		if below_empty {
			target_x = nx
			break
		}
		target_x = nx
	}

	if target_x < 0 do return false

	src_idx := y * world.width + x
	dst_idx := y * world.width + target_x
	world.cells[dst_idx] = world.cells[src_idx]
	flow_bits: u8 = SAND_FLAG_FLOW_RIGHT if dx > 0 else SAND_FLAG_FLOW_LEFT
	world.cells[dst_idx].flags = u8(parity & 1) | flow_bits
	world.cells[dst_idx].sleep_counter = 0
	world.cells[src_idx] = Sand_Cell{}
	sand_finalize_move(world, x, y, target_x, y)

	return true
}

// Pressure-driven upward water movement when column below is deep enough
@(private = "file")
sand_try_rise :: proc(world: ^Sand_World, x, y: int, parity: u32) -> bool {
	if !sand_in_bounds(world, x, y + 1) do return false
	if sand_is_interactor_cell(world, x, y + 1) do return false
	if world.cells[(y + 1) * world.width + x].material != .Empty do return false

	depth_below := 0
	for scan_y := y - 1; scan_y >= 0; scan_y -= 1 {
		if world.cells[scan_y * world.width + x].material != .Water do break
		depth_below += 1
	}
	if depth_below < int(WATER_PRESSURE_MIN_DEPTH) do return false

	my_height := depth_below + 1
	found_taller := false
	for dist in 1 ..= int(WATER_PRESSURE_SCAN_RANGE) {
		for sign in ([2]int{-1, 1}) {
			nx := x + dist * sign
			if !sand_in_bounds(world, nx, y) do continue
			neighbor_height := 0
			for scan_y := y; scan_y >= 0; scan_y -= 1 {
				if world.cells[scan_y * world.width + nx].material != .Water do break
				neighbor_height += 1
			}
			for scan_y := y + 1; scan_y < world.height; scan_y += 1 {
				if world.cells[scan_y * world.width + nx].material != .Water do break
				neighbor_height += 1
			}
			if neighbor_height > my_height {
				found_taller = true
				break
			}
		}
		if found_taller do break
	}
	if !found_taller do return false

	if rand.float32() >= WATER_PRESSURE_CHANCE do return false

	return sand_try_move(world, x, y, x, y + 1, parity)
}

// Probabilistically convert adjacent dry sand into wet sand
@(private = "file")
sand_try_wet_neighbors :: proc(world: ^Sand_World, x, y: int, chance: f32) {
	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if !sand_in_bounds(world, nx, ny) do continue
		n_idx := ny * world.width + nx
		if world.cells[n_idx].material != .Sand do continue
		if rand.float32() >= chance do continue
		world.cells[n_idx].material = .Wet_Sand
		world.cells[n_idx].flags &= ~SAND_FLAG_DRY_MASK
		world.cells[n_idx].sleep_counter = 0
		sand_wake_neighbors(world, nx, ny)
		sand_chunk_mark_dirty(world, nx, ny)
	}
}

// Drying logic: increment counter when no adjacent water; convert to Sand when threshold reached
@(private = "file")
sand_wet_sand_dry_tick :: proc(world: ^Sand_World, x, y: int) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	if cell.material != .Wet_Sand do return

	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if sand_in_bounds(world, nx, ny) && world.cells[ny * world.width + nx].material == .Water {
			cell.flags &= ~SAND_FLAG_DRY_MASK
			return
		}
	}

	count := (cell.flags & SAND_FLAG_DRY_MASK) >> SAND_FLAG_DRY_SHIFT
	count += 1
	if count >= WET_SAND_DRY_STEPS {
		cell.material = .Sand
		cell.flags &= ~SAND_FLAG_DRY_MASK
		sand_wake_neighbors(world, x, y)
	} else {
		cell.flags = (cell.flags & ~SAND_FLAG_DRY_MASK) | (count << SAND_FLAG_DRY_SHIFT)
	}
}

@(private = "file")
sand_erode_adjacent_platforms :: proc(world: ^Sand_World, x, y: int) {
	for dx in ([2]int{-1, 1}) {
		nx := x + dx
		if !sand_in_bounds(world, nx, y) do continue
		n_idx := y * world.width + nx
		if world.cells[n_idx].material != .Platform do continue

		cpt := int(SAND_CELLS_PER_TILE)
		tile_base_x := (nx / cpt) * cpt
		tile_base_y := (y / cpt) * cpt

		for sub_dy in 0 ..< cpt {
			for sub_dx in 0 ..< cpt {
				sx := tile_base_x + sub_dx
				sy := tile_base_y + sub_dy
				if !sand_in_bounds(world, sx, sy) do continue
				sub_idx := sy * world.width + sx
				if world.cells[sub_idx].material != .Platform do continue

				world.cells[sub_idx] = Sand_Cell{}
				sand_wake_neighbors(world, sx, sy)
				sand_chunk_mark_dirty(world, sx, sy)

				chunk := sand_chunk_at(world, sx, sy)
				if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1

				append(&world.eroded_platforms, [2]int{sx, sy})
			}
		}

		world.cells[y * world.width + x].sleep_counter = 0
	}
}

@(private = "file")
sand_restore_platforms :: proc(world: ^Sand_World) {
	i := 0
	for i < len(world.eroded_platforms) {
		pos := world.eroded_platforms[i]
		px, py := pos.x, pos.y
		idx := py * world.width + px

		if world.cells[idx].material != .Empty {
			i += 1
			continue
		}

		has_adjacent_sand := false
		for offset in ([3][2]int{{-1, 0}, {1, 0}, {0, 1}}) {
			nx := px + offset.x
			ny := py + offset.y
			if !sand_in_bounds(world, nx, ny) do continue
			mat := world.cells[ny * world.width + nx].material
			if mat == .Sand || mat == .Wet_Sand || mat == .Water {
				has_adjacent_sand = true
				break
			}
		}

		if has_adjacent_sand {
			i += 1
			continue
		}

		world.cells[idx].material = .Platform
		sand_wake_neighbors(world, px, py)
		sand_chunk_mark_dirty(world, px, py)
		chunk := sand_chunk_at(world, px, py)
		if chunk != nil do chunk.active_count += 1

		unordered_remove(&world.eroded_platforms, i)
	}
}

// --- Emitters ---

// Update all emitters: accumulate fractional particles and spawn when ready
sand_emitter_update :: proc(world: ^Sand_World) {
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
					if !sand_in_bounds(world, sand_x, sand_y) do continue

					idx := sand_y * world.width + sand_x
					if world.cells[idx].material == .Empty {
						hash := u32(sand_x * 7 + sand_y * 13 + int(world.step_counter))
						world.cells[idx] = Sand_Cell {
							material      = emitter.material,
							sleep_counter = 0,
							color_variant = u8(hash & 3),
							flags         = 0,
						}

						chunk := sand_chunk_at(world, sand_x, sand_y)
						if chunk != nil do chunk.active_count += 1
					}

					sand_wake_neighbors(world, sand_x, sand_y)
					sand_chunk_mark_dirty(world, sand_x, sand_y)
				}
			}
		}
	}
}
