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
	Fire, // rising flame: extinguishes or turns to smoke
	Smoke, // rising gas: disperses sideways, decays over time
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
	.Fire = {behavior = .Gas, density = 0, inert = false},
	.Smoke = {behavior = .Gas, density = 1, inert = false},
}

SAND_INERT_MATERIALS :: bit_set[Sand_Material]{.Empty, .Solid, .Platform}
SAND_GRANULAR_MATERIALS :: bit_set[Sand_Material]{.Sand, .Wet_Sand}
SAND_DISPLACEABLE_MATERIALS :: bit_set[Sand_Material]{.Sand, .Wet_Sand, .Water}
SAND_SIMULATABLE_MATERIALS :: bit_set[Sand_Material]{.Sand, .Wet_Sand, .Water, .Fire, .Smoke}
SAND_GAS_MATERIALS :: bit_set[Sand_Material]{.Fire, .Smoke}

// --- Projectile ---

Sand_Projectile :: struct {
	pos:           [2]f32, // world position (meters)
	vel:           [2]f32, // velocity (m/s)
	material:      Sand_Material,
	color_variant: u8,
	generation:    u8, // 0 = player-triggered, 1+ = cascade
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

// --- Interaction Stats ---

Sand_Interaction_Stats :: struct {
	sand_displaced:     int, // count of sand cells displaced (for particles)
	wet_sand_displaced: int, // count of wet_sand cells displaced
	water_displaced:    int, // count of water cells displaced
	impact_factor:      f32, // 0..1 impact strength (for particle scaling)
	surface_y:          f32, // interpolated surface Y (for particle emit pos)
	surface_found:      bool, // whether surface was found
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

	// Projectiles (cells in flight, updated every fixed step)
	projectiles:                                                #soa[dynamic]Sand_Projectile,

	// Eroded platforms (tracked for restoration when sand moves away)
	eroded_platforms:                                           [dynamic][2]int,

	// Simulation state
	step_counter:                                               u32, // total sim steps (bit 0 = parity for updated flag)
	sub_step_acc:                                               u8, // counts fixed steps; fires sim when == SAND_SIM_INTERVAL

	// Interactor footprint cache (set each fixed step, used by sim to block movement into interactor)
	interactor_x0, interactor_y0, interactor_x1, interactor_y1: int,
	interactor_blocking:                                        bool,

	// Inline RNG state (xorshift32)
	rng_state:                                                  u32,

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
	fire_emitters:  [][2]int,
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
	world.rng_state = 0xDEADBEEF

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
	for pos in level.fire_emitters do append(&world.emitters, Sand_Emitter{tx = pos.x, ty = pos.y, material = .Fire})

	sand_chunk_recount(world)
}

sand_destroy :: proc(world: ^Sand_World) {
	delete(world.cells)
	delete(world.slopes)
	delete(world.chunks)
	delete(world.emitters)
	delete(world.eroded_platforms)
	delete(world.projectiles)
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
sand_rng_next :: proc(world: ^Sand_World) -> u32 {
	s := world.rng_state
	s ~= s << 13
	s ~= s >> 17
	s ~= s << 5
	world.rng_state = s
	return s
}

@(private = "file")
sand_rng_float :: proc(world: ^Sand_World) -> f32 {
	return f32(sand_rng_next(world) >> 8) / f32(1 << 24)
}

@(private = "file")
sand_rng_bool :: proc(world: ^Sand_World) -> bool {
	return sand_rng_next(world) & 1 == 0
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
	sand_wake_neighbors_cardinal(world, sx, sy)
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
			if cell.material not_in SAND_INERT_MATERIALS do cell.sleep_counter = 0
		}
	}
}

@(private = "file")
sand_wake_neighbors_cardinal :: proc(world: ^Sand_World, x, y: int) {
	for d in ([4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) {
		nx, ny := x + d.x, y + d.y
		if !sand_in_bounds(world, nx, ny) do continue
		cell := &world.cells[ny * world.width + nx]
		if cell.material not_in SAND_INERT_MATERIALS do cell.sleep_counter = 0
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
		if col_mat in SAND_GRANULAR_MATERIALS do return f32(gy + 1) * SAND_CELL_SIZE, true
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
		if mat not_in SAND_GRANULAR_MATERIALS do break
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
			if mat not_in SAND_GRANULAR_MATERIALS do continue
			sand_displace_cell(world, wall_gx, try_gy, push_dx)
			break
		}
	}
}

// Displacement, drag, pressure, burial, buoyancy — modifies vel in place, returns stats for particles
sand_apply_physics :: proc(
	world: ^Sand_World,
	pos: [2]f32,
	vel: ^[2]f32,
	size: f32,
	impact_pending: ^f32,
	sand_immersion: f32,
	is_dashing: bool,
	is_submerged: bool,
	dt: f32,
) -> Sand_Interaction_Stats {
	if world.width == 0 || world.height == 0 do return {}

	x0, y0, x1, y1 := sand_footprint_cells(world, pos, size)
	world.interactor_x0 = x0
	world.interactor_y0 = y0
	world.interactor_x1 = x1
	world.interactor_y1 = y1
	world.interactor_blocking = true

	if is_dashing {
		sand_carved, water_carved := sand_dash_carve(world, pos, vel, size, dt)
		return {sand_displaced = sand_carved, water_displaced = water_carved}
	}

	impact_factor: f32 = 0
	if impact_pending^ > 0 {
		speed := impact_pending^
		impact_pending^ = 0
		range := SAND_IMPACT_MAX_SPEED - SAND_IMPACT_MIN_SPEED
		if range > 0 do impact_factor = math.clamp((speed - SAND_IMPACT_MIN_SPEED) / range, 0, 1)
	}

	extra := int(impact_factor * f32(SAND_IMPACT_RADIUS))
	cx0 := max(x0 - extra, 0)
	cy0 := max(y0 - extra, 0)
	cx1 := min(x1 + extra, world.width - 1)

	sand_displaced := 0
	wet_sand_displaced := 0
	water_displaced := 0
	center_cx := int(pos.x / SAND_CELL_SIZE)

	center_cy := int((pos.y + size / 2) / SAND_CELL_SIZE)

	for ty in cy0 ..= y1 {
		for tx in cx0 ..= cx1 {
			if !sand_in_bounds(world, tx, ty) do continue
			mat := world.cells[ty * world.width + tx].material
			is_gas := mat in SAND_GAS_MATERIALS
			if !is_gas && mat not_in SAND_DISPLACEABLE_MATERIALS do continue

			push_dx: int = tx >= center_cx ? 1 : -1
			in_ring := tx < x0 || tx > x1 || ty < y0

			displaced := false
			if in_ring && impact_factor > 0 {
				// Projectile: radial velocity from player center
				dx_f := f32(tx - center_cx)
				dy_f := f32(ty - center_cy)
				dist := math.sqrt(dx_f * dx_f + dy_f * dy_f)
				if dist < 0.1 do dist = 1
				eject_speed := impact_factor * SAND_PROJ_IMPACT_MULT * world.gravity
				eject_vel := [2]f32{dx_f / dist * eject_speed, dy_f / dist * eject_speed}
				// Upward bias
				eject_vel.y = math.abs(eject_vel.y) + eject_speed * 0.5
				// Water splash: more upward, spread horizontal
				if mat == .Water {
					eject_vel.y *= SAND_PROJ_WATER_UP_MULT
					eject_vel.x += (sand_rng_float(world) * 2 - 1) * SAND_PROJ_WATER_SPREAD
				}
				sand_projectile_emit(world, tx, ty, eject_vel)
				displaced = true
			} else if is_gas {
				// Projectile: push direction + player velocity component
				gas_vel := [2]f32 {
					f32(push_dx) * SAND_PROJ_GAS_PUSH + vel.x * SAND_PROJ_GAS_PLAYER_MULT,
					SAND_PROJ_GAS_PUSH * 0.5 + vel.y * SAND_PROJ_GAS_PLAYER_MULT,
				}
				sand_projectile_emit(world, tx, ty, gas_vel)
				displaced = true
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

	surf_y, surf_ok := sand_surface_query(world, pos.x, pos.y)

	if is_submerged {
		if sand_displaced > 0 do sand_apply_drag(vel, SAND_SWIM_DRAG_FACTOR * SAND_PLAYER_DRAG_MAX, SAND_PLAYER_DRAG_Y_FACTOR, false)
		if wet_sand_displaced > 0 do sand_apply_drag(vel, SAND_SWIM_DRAG_FACTOR * WET_SAND_PLAYER_DRAG_MAX, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
		if water_displaced > 0 do sand_apply_drag(vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)
	} else {
		if sand_displaced > 0 {
			sand_apply_drag(
				vel,
				sand_immersion * sand_immersion * SAND_PLAYER_DRAG_MAX,
				SAND_PLAYER_DRAG_Y_FACTOR,
				true,
			)
		}
		if wet_sand_displaced > 0 {
			drag := min(
				f32(wet_sand_displaced) * WET_SAND_PLAYER_DRAG_PER_CELL,
				WET_SAND_PLAYER_DRAG_MAX,
			)
			sand_apply_drag(vel, drag, WET_SAND_PLAYER_DRAG_Y_FACTOR, true)
		}
		if water_displaced > 0 do sand_apply_drag(vel, min(f32(water_displaced) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX), WATER_PLAYER_DRAG_Y_FACTOR, false)

		above_count := 0
		for tx in x0 ..= x1 {
			gap := 0
			for ty := y1 + 1; ty < world.height; ty += 1 {
				cell := sand_get(world, tx, ty)
				if cell.material in SAND_GRANULAR_MATERIALS {
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
			vel.y -= capped * SAND_PRESSURE_FORCE * dt
		}

		if sand_immersion > SAND_BURIAL_THRESHOLD && vel.y <= 0 {
			activity := math.clamp(
				math.abs(vel.x) / world.run_speed,
				0,
				SAND_QUICKSAND_MAX_ACTIVITY,
			)
			base_sink := SAND_QUICKSAND_BASE_SINK * world.gravity * dt
			move_sink := SAND_QUICKSAND_MOVE_MULT * activity * world.gravity * dt
			vel.y -= base_sink + move_sink
		}
	}

	water_immersion := sand_compute_immersion(world, pos, size, {.Water})
	if water_immersion > WATER_BUOYANCY_THRESHOLD {
		buoyancy := water_immersion * WATER_BUOYANCY_FORCE
		vel.y += buoyancy * dt
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
		vel.x += current_avg * WATER_CURRENT_FORCE * dt
	}

	return {
		sand_displaced = sand_displaced,
		wet_sand_displaced = wet_sand_displaced,
		water_displaced = water_displaced,
		impact_factor = impact_factor,
		surface_y = surf_y,
		surface_found = surf_ok,
	}
}

// Carve tunnel through sand during dash
@(private = "file")
sand_dash_carve :: proc(
	world: ^Sand_World,
	pos: [2]f32,
	vel: ^[2]f32,
	size: f32,
	dt: f32,
) -> (
	sand_carved, water_carved: int,
) {
	prev_x := pos.x - vel.x * dt
	curr_x := pos.x

	gx_start := max(int(math.min(prev_x, curr_x) / SAND_CELL_SIZE) - 1, 0)
	gx_end := min(int(math.max(prev_x, curr_x) / SAND_CELL_SIZE) + 1, world.width - 1)
	gy_start := max(int(pos.y / SAND_CELL_SIZE), 0)
	gy_end := min(int((pos.y + size) / SAND_CELL_SIZE), world.height - 1)

	push_dx: int = vel.x > 0 ? 1 : -1

	for gx in gx_start ..= gx_end {
		for gy in gy_start ..= gy_end {
			if !sand_in_bounds(world, gx, gy) do continue
			idx := gy * world.width + gx
			mat := world.cells[idx].material
			if mat not_in SAND_SIMULATABLE_MATERIALS do continue

			// Projectile: upward + random horizontal spread perpendicular to dash
			eject_vel := [2]f32 {
				(sand_rng_float(world) * 2 - 1) * SAND_PROJ_DASH_SPREAD,
				SAND_PROJ_DASH_SPEED,
			}
			sand_projectile_emit(world, gx, gy, eject_vel)
			if mat in SAND_GRANULAR_MATERIALS do sand_carved += 1
			else do water_carved += 1
		}
	}

	fx0, fy0, fx1, fy1 := sand_footprint_cells(world, pos, size)
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
	if sand_count > 0 do sand_apply_drag(vel, min(f32(sand_count) * SAND_PLAYER_DRAG_PER_CELL, SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, SAND_PLAYER_DRAG_Y_FACTOR, false)
	if wet_sand_count > 0 do sand_apply_drag(vel, min(f32(wet_sand_count) * WET_SAND_PLAYER_DRAG_PER_CELL, WET_SAND_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WET_SAND_PLAYER_DRAG_Y_FACTOR, false)
	if water_count > 0 do sand_apply_drag(vel, min(f32(water_count) * WATER_PLAYER_DRAG_PER_CELL, WATER_PLAYER_DRAG_MAX) * SAND_DASH_DRAG_FACTOR, WATER_PLAYER_DRAG_Y_FACTOR, false)
	return
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

	if dst_mat in SAND_DISPLACEABLE_MATERIALS && depth < int(SAND_DISPLACE_CHAIN) {
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
	for i in 0 ..< len(pool.particles) {
		pool.particles[i].vel.y -= SAND_PARTICLE_GRAVITY * dt
		pool.particles[i].vel *= 1.0 - SAND_PARTICLE_FRICTION * dt
		pool.particles[i].pos += pool.particles[i].vel * dt
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
	cs := int(SAND_CHUNK_SIZE)
	for y in 0 ..< world.height {
		cy := y / cs
		if parity == 0 {
			for cx in 0 ..< world.chunks_w {
				chunk := &world.chunks[cy * world.chunks_w + cx]
				if !chunk.needs_sim do continue
				x_start := cx * cs
				x_end := min(x_start + cs, world.width)
				for x in x_start ..< x_end do sand_dispatch_cell(world, x, y, parity)
			}
		} else {
			for cx := world.chunks_w - 1; cx >= 0; cx -= 1 {
				chunk := &world.chunks[cy * world.chunks_w + cx]
				if !chunk.needs_sim do continue
				x_start := cx * cs
				x_end := min(x_start + cs, world.width)
				for x := x_end - 1; x >= x_start; x -= 1 do sand_dispatch_cell(world, x, y, parity)
			}
		}
	}
	sand_restore_platforms(world)
}

// Dispatch cell update using material properties
@(private = "file")
sand_dispatch_cell :: proc(world: ^Sand_World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	if cell.material in SAND_INERT_MATERIALS do return
	if u32(cell.flags & SAND_FLAG_PARITY) == (parity & 1) do return

	sand_erode_adjacent_platforms(world, x, y)
	if cell.material == .Water do sand_try_wet_neighbors(world, x, y, WATER_CONTACT_WET_CHANCE)
	if cell.sleep_counter >= SAND_SLEEP_THRESHOLD do return

	switch SAND_MAT_PROPS[cell.material].behavior {
	case .Powder:
		sand_update_cell_powder(world, x, y, parity)
	case .Liquid:
		sand_update_cell_liquid(world, x, y, parity)
	case .Gas:
		sand_update_cell_gas(world, x, y, parity)
	case .Static:
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
		if sand_rng_float(world) > swap_chance do return false

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
			if sand_rng_float(world) > swap_chance do break
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
	if sand_rng_float(world) < repose_chance {
		first_dx: int = sand_rng_bool(world) ? -1 : 1
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
			first_dx: int = sand_rng_bool(world) ? -1 : 1
			if sand_try_move(world, x, y, x + first_dx, y - 1, parity) do moved = true
			else if sand_try_move(world, x, y, x - first_dx, y - 1, parity) do moved = true
			else {
				first_dx2: int = sand_rng_bool(world) ? -1 : 1
				if sand_try_flow(world, x, y, first_dx2, parity) do moved = true
				else if sand_try_flow(world, x, y, -first_dx2, parity) do moved = true
			}
		}
	}

	if !moved && slope == .None do moved = sand_try_rise(world, x, y, parity)
	if !moved do if world.cells[idx].sleep_counter < 255 do world.cells[idx].sleep_counter += 1
}

// Gas material update: fire extinguishes/converts to smoke, smoke decays. Both rise upward with dispersion.
@(private = "file")
sand_update_cell_gas :: proc(world: ^Sand_World, x, y: int, parity: u32) {
	idx := y * world.width + x
	cell := &world.cells[idx]
	mat := cell.material

	// Fire: chance to extinguish or convert to smoke
	if mat == .Fire {
		if sand_rng_float(world) < FIRE_LIFETIME_CHANCE {
			world.cells[idx] = Sand_Cell{}
			sand_wake_neighbors(world, x, y)
			sand_chunk_mark_dirty(world, x, y)
			chunk := sand_chunk_at(world, x, y)
			if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
			return
		}
		if sand_rng_float(world) < FIRE_SMOKE_CHANCE {
			cell.material = .Smoke
			cell.color_variant = sand_wang_hash(x, y)
			cell.sleep_counter = 0
			sand_wake_neighbors(world, x, y)
			sand_chunk_mark_dirty(world, x, y)
			return
		}
	}

	// Smoke: chance to decay
	if mat == .Smoke && sand_rng_float(world) < SMOKE_DECAY_CHANCE {
		world.cells[idx] = Sand_Cell{}
		sand_wake_neighbors(world, x, y)
		sand_chunk_mark_dirty(world, x, y)
		chunk := sand_chunk_at(world, x, y)
		if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
		return
	}

	// Movement: try up, then diagonal up, then sideways (smoke only)
	rise_chance: f32 = FIRE_RISE_SPEED if mat == .Fire else SMOKE_RISE_CHANCE
	moved := false
	if sand_rng_float(world) < rise_chance {
		if sand_try_move(world, x, y, x, y + 1, parity) do moved = true
		else {
			first_dx: int = sand_rng_bool(world) ? -1 : 1
			if sand_try_move(world, x, y, x + first_dx, y + 1, parity) do moved = true
			else if sand_try_move(world, x, y, x - first_dx, y + 1, parity) do moved = true
		}
	}

	// Smoke dispersion: try sideways
	if !moved && mat == .Smoke && sand_rng_float(world) < SMOKE_DISPERSE_CHANCE {
		first_dx: int = sand_rng_bool(world) ? -1 : 1
		if sand_try_move(world, x, y, x + first_dx, y, parity) do moved = true
		else if sand_try_move(world, x, y, x - first_dx, y, parity) do moved = true
	}

	if !moved do if cell.sleep_counter < 255 do cell.sleep_counter += 1
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

	scan_cap := int(WATER_FLOW_DISTANCE) * 2
	depth_below := 0
	for scan_y := y - 1; scan_y >= max(0, y - scan_cap); scan_y -= 1 {
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
			for scan_y := y; scan_y >= max(0, y - scan_cap); scan_y -= 1 {
				if world.cells[scan_y * world.width + nx].material != .Water do break
				neighbor_height += 1
			}
			for scan_y := y + 1; scan_y < min(world.height, y + 1 + scan_cap); scan_y += 1 {
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

	if sand_rng_float(world) >= WATER_PRESSURE_CHANCE do return false

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
		if sand_rng_float(world) >= chance do continue
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
			if mat in SAND_DISPLACEABLE_MATERIALS {
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
		rate: f32
		#partial switch emitter.material {
		case .Water:
			rate = WATER_EMITTER_RATE
		case .Fire:
			rate = FIRE_EMITTER_RATE
		case:
			rate = SAND_EMITTER_RATE
		}
		cpt := f32(SAND_CELLS_PER_TILE)
		emitter.accumulator += rate * dt

		for emitter.accumulator >= 1.0 {
			emitter.accumulator -= 1.0

			base_sand_x := emitter.tx * int(SAND_CELLS_PER_TILE)
			base_sand_y :=
				(emitter.ty + 1 if emitter.material == .Fire else emitter.ty - 1) *
				int(SAND_CELLS_PER_TILE)

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

// --- Projectiles ---

// Remove a cell from the grid and launch it as a projectile with given velocity
sand_projectile_emit :: proc(world: ^Sand_World, gx, gy: int, vel: [2]f32, generation: u8 = 0) {
	if !sand_in_bounds(world, gx, gy) do return
	idx := gy * world.width + gx
	cell := world.cells[idx]
	if cell.material in SAND_INERT_MATERIALS do return

	// Remove from grid
	world.cells[idx] = Sand_Cell{}
	chunk := sand_chunk_at(world, gx, gy)
	if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
	sand_wake_neighbors(world, gx, gy)
	sand_chunk_mark_dirty(world, gx, gy)

	// Create projectile at cell center
	pos := [2]f32{(f32(gx) + 0.5) * SAND_CELL_SIZE, (f32(gy) + 0.5) * SAND_CELL_SIZE}
	append_soa(
		&world.projectiles,
		Sand_Projectile {
			pos = pos,
			vel = vel,
			material = cell.material,
			color_variant = cell.color_variant,
			generation = generation,
		},
	)
}

// Integrate projectiles, deposit when settled or blocked
sand_projectile_update :: proc(world: ^Sand_World, dt: f32) {
	// Soft cap: force-deposit oldest if over limit
	for len(world.projectiles) > int(SAND_PROJ_MAX_COUNT) {
		sand_projectile_deposit(world, 0, true)
	}

	i := len(world.projectiles) - 1
	for i >= 0 {
		proj := &world.projectiles[i]
		behavior := SAND_MAT_PROPS[proj.material].behavior

		// Material-based forces
		switch behavior {
		case .Powder:
			proj.vel.y -= world.gravity * dt
		case .Liquid:
			proj.vel.y -= world.gravity * SAND_PROJ_WATER_GRAV_MULT * dt
		case .Gas:
			proj.vel.y += SAND_PROJ_GAS_RISE * dt
		case .Static:
		}

		// Air drag
		drag := max(f32(0), 1 - SAND_PROJ_DRAG * dt)
		proj.vel *= drag

		// Integrate position
		proj.pos += proj.vel * dt

		// Fire/smoke decay
		decayed := false
		if proj.material == .Fire {
			if sand_rng_float(world) < FIRE_LIFETIME_CHANCE * dt * f32(SAND_SIM_INTERVAL) {
				decayed = true
			} else if sand_rng_float(world) < FIRE_SMOKE_CHANCE * dt * f32(SAND_SIM_INTERVAL) {
				proj.material = .Smoke
				proj.color_variant = u8(sand_rng_next(world) & 3)
			}
		} else if proj.material == .Smoke {
			if sand_rng_float(world) < SMOKE_DECAY_CHANCE * dt * f32(SAND_SIM_INTERVAL) do decayed = true
		}
		if decayed {
			unordered_remove_soa(&world.projectiles, i)
			i -= 1
			continue
		}

		// Convert to grid coords
		gx := int(proj.pos.x / SAND_CELL_SIZE)
		gy := int(proj.pos.y / SAND_CELL_SIZE)

		// Out of bounds: force deposit at boundary
		if !sand_in_bounds(world, gx, gy) {
			gx = math.clamp(gx, 0, world.width - 1)
			gy = math.clamp(gy, 0, world.height - 1)
			proj.pos.x = (f32(gx) + 0.5) * SAND_CELL_SIZE
			proj.pos.y = (f32(gy) + 0.5) * SAND_CELL_SIZE
			sand_projectile_deposit(world, i, true)
			i -= 1
			continue
		}

		// Check deposit conditions: target occupied or speed below threshold
		speed := math.sqrt(proj.vel.x * proj.vel.x + proj.vel.y * proj.vel.y)
		target_occupied := world.cells[gy * world.width + gx].material != .Empty
		should_deposit := target_occupied || speed < SAND_PROJ_SETTLE_SPEED

		if should_deposit {
			sand_projectile_deposit(world, i, false)
		}
		i -= 1
	}
}

// Deposit a projectile back to the grid via spiral search
@(private = "file")
sand_projectile_deposit :: proc(world: ^Sand_World, idx: int, force: bool) {
	proj := world.projectiles[idx]
	gx := int(proj.pos.x / SAND_CELL_SIZE)
	gy := int(proj.pos.y / SAND_CELL_SIZE)
	gx = math.clamp(gx, 0, world.width - 1)
	gy = math.clamp(gy, 0, world.height - 1)

	// Spiral search for empty cell
	radius := int(SAND_PROJ_DEPOSIT_RADIUS)
	placed := false
	best_x, best_y := gx, gy
	best_dist_sq := max(int)

	for dy in -radius ..= radius {
		for dx in -radius ..= radius {
			nx, ny := gx + dx, gy + dy
			if !sand_in_bounds(world, nx, ny) do continue
			if sand_is_interactor_cell(world, nx, ny) do continue
			if world.cells[ny * world.width + nx].material != .Empty do continue
			dist_sq := dx * dx + dy * dy
			if dist_sq < best_dist_sq {
				best_dist_sq = dist_sq
				best_x, best_y = nx, ny
				placed = true
			}
		}
	}

	if !placed && !force {
		return // Keep alive for retry
	}

	if placed {
		dst_idx := best_y * world.width + best_x
		world.cells[dst_idx] = Sand_Cell {
			material      = proj.material,
			sleep_counter = 0,
			color_variant = proj.color_variant,
			flags         = u8(world.step_counter & 1), // set parity
		}
		chunk := sand_chunk_at(world, best_x, best_y)
		if chunk != nil do chunk.active_count += 1
		sand_wake_neighbors(world, best_x, best_y)
		sand_chunk_mark_dirty(world, best_x, best_y)

		// Cascade: high-speed deposit ejects neighbors
		speed := math.sqrt(proj.vel.x * proj.vel.x + proj.vel.y * proj.vel.y)
		if speed > SAND_PROJ_CASCADE_SPEED && proj.generation < SAND_PROJ_CASCADE_MAX_GEN {
			sand_projectile_cascade(world, best_x, best_y, proj.vel, proj.generation)
		}
	}

	unordered_remove_soa(&world.projectiles, idx)
}

// Eject 1-4 neighbor cells as cascade projectiles
@(private = "file")
sand_projectile_cascade :: proc(
	world: ^Sand_World,
	cx, cy: int,
	impact_vel: [2]f32,
	parent_gen: u8,
) {
	offsets := [4][2]int{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
	ejected := 0
	for off in offsets {
		nx, ny := cx + off.x, cy + off.y
		if !sand_in_bounds(world, nx, ny) do continue
		mat := world.cells[ny * world.width + nx].material
		if mat in SAND_INERT_MATERIALS do continue
		if sand_rng_bool(world) do continue // 50% chance per neighbor

		eject_vel := impact_vel * SAND_PROJ_CASCADE_TRANSFER
		eject_vel.x += f32(off.x) * math.abs(impact_vel.y) * 0.3
		eject_vel.y += f32(off.y) * math.abs(impact_vel.x) * 0.3
		sand_projectile_emit(world, nx, ny, eject_vel, parent_gen + 1)
		ejected += 1
		if ejected >= 4 do break
	}
}
