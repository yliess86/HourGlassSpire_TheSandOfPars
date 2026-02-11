package engine

import "core:math"
import "core:math/linalg"

Collider_Rect :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

Collider_Slope_Kind :: enum u8 {
	Right, // floor /   — rises left→right
	Left, // floor \   — rises right→left
	Ceil_Left, // ceiling / — solid below-right
	Ceil_Right, // ceiling \ — solid below-left
}

Collider_Slope :: struct {
	kind:   Collider_Slope_Kind,
	base_x: f32, // left edge X of bounding square
	base_y: f32, // bottom edge Y of bounding square
	span:   f32, // side length (N * tile_size)
}

Collider_Raycast_Hit :: struct {
	hit:      bool,
	distance: f32, // along ray direction
	point:    [2]f32, // world-space hit position
}


collider_check_rect_vs_rect :: proc(a, b: Collider_Rect) -> bool {
	abs_diff := linalg.abs(a.pos - b.pos)
	mid_point := 0.5 * (a.size + b.size)
	return abs_diff.x <= mid_point.x && abs_diff.y <= mid_point.y
}

// Resolve a dynamic AABB against a static AABB on a single axis.
// Modifies dynamic_rect.pos[axis] in-place if resolved.
// Returns: resolved (did we push?), normal (+1 or -1 push direction, 0 if no hit).
collider_resolve_dynamic_rect :: proc(
	dynamic_rect: ^Collider_Rect,
	static_rect: Collider_Rect,
	vel_on_axis: f32,
	axis: int,
) -> (
	resolved: bool,
	normal: f32,
) {
	diff := dynamic_rect.pos - static_rect.pos
	abs_diff: [2]f32 = {math.abs(diff.x), math.abs(diff.y)}
	half_sum := 0.5 * (dynamic_rect.size + static_rect.size)
	if abs_diff.x >= half_sum.x || abs_diff.y >= half_sum.y do return false, 0

	overlap := half_sum[axis] - abs_diff[axis]
	if overlap <= 0 do return false, 0

	direction := diff[axis]
	if vel_on_axis != 0 && math.sign(vel_on_axis) == math.sign(direction) do return false, 0

	push_dir: f32 = math.sign(direction)
	if push_dir == 0 {
		push_dir = -math.sign(vel_on_axis)
		if push_dir == 0 do return false, 0
	}
	dynamic_rect.pos[axis] += overlap * push_dir

	return true, push_dir
}

// Surface Y at a given world X (clamped to slope range)
collider_slope_surface_y :: proc(s: Collider_Slope, world_x: f32) -> f32 {
	local_x := math.clamp(world_x - s.base_x, 0, s.span)
	switch s.kind {
	case .Right, .Ceil_Left:
		return s.base_y + local_x // /
	case .Left, .Ceil_Right:
		return s.base_y + s.span - local_x // \
	}
	return s.base_y
}

// Surface X at a given world Y (Inverse of surface_y)
collider_slope_surface_x :: proc(s: Collider_Slope, world_y: f32) -> f32 {
	local_y := math.clamp(world_y - s.base_y, 0, s.span)
	switch s.kind {
	case .Right, .Ceil_Left:
		return s.base_x + local_y // /
	case .Left, .Ceil_Right:
		return s.base_x + s.span - local_y // \
	}
	return s.base_x
}

// Whether X falls within [base_x, base_x + span]
collider_slope_contains_x :: proc(s: Collider_Slope, x: f32) -> bool {
	return x >= s.base_x && x <= s.base_x + s.span
}

// Floor slope?
collider_slope_is_floor :: proc(s: Collider_Slope) -> bool {
	return s.kind == .Right || s.kind == .Left
}

// Axis-aligned ray vs AABB.
// cross_half_size widens the cross-axis check (0 = point ray, >0 = thick ray).
collider_raycast_rect :: proc(
	origin: [2]f32,
	axis: int,
	sign: f32,
	max_dist: f32,
	rect: Collider_Rect,
	cross_half_size: f32 = 0,
) -> Collider_Raycast_Hit {
	cross := 1 - axis
	if math.abs(origin[cross] - rect.pos[cross]) > rect.size[cross] / 2 + cross_half_size do return {}

	face := rect.pos[axis] - sign * rect.size[axis] / 2
	dist := sign * (face - origin[axis])
	if dist < 0 || dist > max_dist do return {}

	point: [2]f32
	point[axis] = origin[axis] + sign * dist
	point[cross] = origin[cross]
	return {hit = true, distance = dist, point = point}
}

// Axis-aligned raycast against a slope's surface.
// axis: 1 = Vertical (Y-axis ray), 0 = Horizontal (X-axis ray)
// sign: +1 = Positive dir (Up/Right), -1 = Negative dir (Down/Left)
// cross_half_size: Widens the check on the CROSS axis (thick ray width)
collider_raycast_slope :: proc(
	origin: [2]f32,
	axis: int,
	sign: f32,
	max_dist: f32,
	slope: Collider_Slope,
	cross_half_size: f32 = 0,
) -> Collider_Raycast_Hit {
	cross := 1 - axis
	slope_base_cross := slope.base_x if axis == 1 else slope.base_y
	if origin[cross] + cross_half_size < slope_base_cross || origin[cross] - cross_half_size > slope_base_cross + slope.span do return {}

	surface_val :=
		collider_slope_surface_y(slope, origin.x) if axis == 1 else collider_slope_surface_x(slope, origin.y)

	dist := sign * (surface_val - origin[axis])
	if dist < 0 || dist > max_dist do return {}

	point: [2]f32
	point[axis] = surface_val
	point[cross] = origin[cross]
	return {hit = true, distance = dist, point = point}
}
