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
	if abs_diff.x >= half_sum.x || abs_diff.y >= half_sum.y {
		return false, 0
	}

	overlap := half_sum[axis] - abs_diff[axis]
	if overlap <= 0 do return false, 0

	direction := diff[axis]
	if vel_on_axis != 0 && math.sign(vel_on_axis) == math.sign(direction) {
		return false, 0
	}

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

// Whether X falls within [base_x, base_x + span]
collider_slope_contains_x :: proc(s: Collider_Slope, x: f32) -> bool {
	return x >= s.base_x && x <= s.base_x + s.span
}

// Floor slope?
collider_slope_is_floor :: proc(s: Collider_Slope) -> bool {
	return s.kind == .Right || s.kind == .Left
}

// Broad-phase: does rect overlap the slope's bounding square?
collider_check_rect_vs_slope :: proc(r: Collider_Rect, s: Collider_Slope) -> bool {
	slope_rect := Collider_Rect {
		pos  = {s.base_x + s.span / 2, s.base_y + s.span / 2},
		size = {s.span, s.span},
	}
	return collider_check_rect_vs_rect(r, slope_rect)
}

// Resolve rect against slope surface. Pushes rect out of slope.
// For floor: pushes up if rect bottom < surface. For ceiling: pushes down if rect top > surface.
// Returns (resolved, slope_dir): slope_dir is +1 (Right), -1 (Left), 0 (ceiling/no hit).
collider_resolve_rect_vs_slope :: proc(
	rect: ^Collider_Rect,
	slope: Collider_Slope,
) -> (
	resolved: bool,
	slope_dir: f32,
) {
	// Sample at uphill edge for floor slopes to prevent corner clipping
	sample_x := rect.pos.x
	switch slope.kind {
	case .Right:
		sample_x = rect.pos.x + rect.size.x / 2 // uphill edge
	case .Left:
		sample_x = rect.pos.x - rect.size.x / 2 // uphill edge
	case .Ceil_Left, .Ceil_Right: // center is fine for ceilings
	}

	// Range check: floor slopes use rect-overlap so the slope activates when the
	// uphill edge first touches the boundary (where surface_y == base_y, matching
	// flat ground). Ceiling slopes keep center-based check.
	if collider_slope_is_floor(slope) {
		rect_left := rect.pos.x - rect.size.x / 2
		rect_right := rect.pos.x + rect.size.x / 2
		if rect_right < slope.base_x || rect_left > slope.base_x + slope.span do return false, 0
	} else {
		if rect.pos.x < slope.base_x || rect.pos.x > slope.base_x + slope.span do return false, 0
	}
	surface_y := collider_slope_surface_y(slope, sample_x)
	switch slope.kind {
	case .Right, .Left:
		rect_bottom := rect.pos.y - rect.size.y / 2
		if rect_bottom <= surface_y {
			rect.pos.y = surface_y + rect.size.y / 2
			return true, 1 if slope.kind == .Right else -1
		}
	case .Ceil_Left, .Ceil_Right:
		rect_top := rect.pos.y + rect.size.y / 2
		if rect_top > surface_y {
			rect.pos.y = surface_y - rect.size.y / 2
			return true, 0
		}
	}
	return false, 0
}
