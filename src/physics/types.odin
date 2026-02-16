package physics

// Center-based axis-aligned bounding box.
Rect :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

Slope_Kind :: enum u8 {
	Right, // floor /   — rises left→right
	Left, // floor \   — rises right→left
	Ceil_Left, // ceiling / — solid below-right
	Ceil_Right, // ceiling \ — solid below-left
}

Slope :: struct {
	kind:   Slope_Kind,
	base_x: f32, // left edge X of bounding square
	base_y: f32, // bottom edge Y of bounding square
	span:   f32, // side length (N * tile_size)
}

Raycast_Hit :: struct {
	hit:      bool,
	distance: f32, // along ray direction
	point:    [2]f32, // world-space hit position
}

Body_Flag :: enum u8 {
	Dropping, // skip one-way platforms
	Grounded, // use larger slope snap distance
}

Body_Flags :: bit_set[Body_Flag;u8]

// Physics body: reference point + AABB descriptor.
// pos is the reference point (e.g. bottom-center for a character).
// The solver computes the working AABB as: center = pos + offset, extents = size.
Body :: struct {
	pos:    [2]f32,
	vel:    [2]f32,
	size:   [2]f32, // AABB extents
	offset: [2]f32, // from pos to AABB center
	flags:  Body_Flags,
}

// Static level geometry passed to the solver. Raw slices, no Level import.
Static_Geometry :: struct {
	ground:    []Rect,
	ceiling:   []Rect,
	walls:     []Rect,
	platforms: []Rect,
	slopes:    []Slope,
}

// Solver tuning parameters.
Solve_Config :: struct {
	step_height: f32,
	sweep_skin:  f32,
	slope_snap:  f32,
	eps:         f32,
}

// Compute the working AABB from a Body.
body_rect :: proc(body: ^Body) -> Rect {
	return {pos = body.pos + body.offset, size = body.size}
}
