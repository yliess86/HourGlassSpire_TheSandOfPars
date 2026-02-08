package engine

import "core:math"
import "core:math/linalg"

Collider_Rect :: struct {
	pos:  [2]f32,
	size: [2]f32,
}


Collider_Hit :: struct {
	is_hit: bool,
	normal: [2]f32,
	depth:  f32,
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
) -> (resolved: bool, normal: f32) {
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

collider_resolve_rect_vs_rect :: proc(a, b: Collider_Rect) -> Collider_Hit {
	diff := a.pos - b.pos
	abs_diff := linalg.abs(diff)
	mid_point := 0.5 * (a.size + b.size)
	overlap := mid_point - abs_diff

	if overlap.x < 0 || overlap.y < 0 do return Collider_Hit{is_hit = false}

	is_x_least_depth := overlap.x < overlap.y
	normal: [2]f32 = ({math.sign(diff.x), 0}) if is_x_least_depth else ({0, math.sign(diff.y)})
	depth := overlap.x if is_x_least_depth else overlap.y
	return Collider_Hit{is_hit = true, normal = normal, depth = depth}
}
