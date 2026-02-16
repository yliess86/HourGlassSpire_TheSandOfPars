package engine

import "core:math"
import "core:math/linalg"

// Center-based axis-aligned bounding box.
Physics_Rect :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

Physics_Slope_Kind :: enum u8 {
	Right, // floor /   — rises left→right
	Left, // floor \   — rises right→left
	Ceil_Left, // ceiling / — solid below-right
	Ceil_Right, // ceiling \ — solid below-left
}

Physics_Slope :: struct {
	kind:   Physics_Slope_Kind,
	base_x: f32, // left edge X of bounding square
	base_y: f32, // bottom edge Y of bounding square
	span:   f32, // side length (N * tile_size)
}

Physics_Raycast_Hit :: struct {
	hit:      bool,
	distance: f32, // along ray direction
	point:    [2]f32, // world-space hit position
}

Physics_Body_Flag :: enum u8 {
	Dropping, // skip one-way platforms
	Grounded, // use larger slope snap distance
}

Physics_Body_Flags :: bit_set[Physics_Body_Flag;u8]

// Physics body: reference point + AABB descriptor.
// pos is the reference point (e.g. bottom-center for a character).
// The solver computes the working AABB as: center = pos + offset, extents = size.
Physics_Body :: struct {
	pos:    [2]f32,
	vel:    [2]f32,
	size:   [2]f32, // AABB extents
	offset: [2]f32, // from pos to AABB center
	flags:  Physics_Body_Flags,
}

// Static level geometry passed to the solver. Raw slices, no Level import.
Physics_Static_Geometry :: struct {
	ground:    []Physics_Rect,
	ceiling:   []Physics_Rect,
	walls:     []Physics_Rect,
	platforms: []Physics_Rect,
	slopes:    []Physics_Slope,
}

// Solver tuning parameters.
Physics_Solve_Config :: struct {
	step_height: f32,
	sweep_skin:  f32,
	slope_snap:  f32,
	eps:         f32,
}

// Compute the working AABB from a Body.
physics_body_rect :: proc(body: ^Physics_Body) -> Physics_Rect {
	return {pos = body.pos + body.offset, size = body.size}
}

// Compute the AABB center from a Body.
physics_body_center :: proc(body: ^Physics_Body) -> [2]f32 {
	return body.pos + body.offset
}

physics_rect_overlap :: proc(a, b: Physics_Rect) -> bool {
	abs_diff := linalg.abs(a.pos - b.pos)
	mid_point := 0.5 * (a.size + b.size)
	return abs_diff.x <= mid_point.x && abs_diff.y <= mid_point.y
}

// Resolve a dynamic AABB against a static AABB on a single axis.
// Modifies dynamic_rect.pos[axis] in-place if resolved.
// Returns: resolved (did we push?), normal (+1 or -1 push direction, 0 if no hit).
physics_rect_resolve :: proc(
	dynamic_rect: ^Physics_Rect,
	static_rect: Physics_Rect,
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
physics_slope_surface_y :: proc(s: Physics_Slope, world_x: f32) -> f32 {
	local_x := math.clamp(world_x - s.base_x, 0, s.span)
	switch s.kind {
	case .Right, .Ceil_Left:
		return s.base_y + local_x // /
	case .Left, .Ceil_Right:
		return s.base_y + s.span - local_x // \
	}
	return s.base_y
}

// Surface X at a given world Y (inverse of surface_y)
physics_slope_surface_x :: proc(s: Physics_Slope, world_y: f32) -> f32 {
	local_y := math.clamp(world_y - s.base_y, 0, s.span)
	switch s.kind {
	case .Right, .Ceil_Left:
		return s.base_x + local_y // /
	case .Left, .Ceil_Right:
		return s.base_x + s.span - local_y // \
	}
	return s.base_x
}

physics_slope_is_floor :: proc(s: Physics_Slope) -> bool {
	return s.kind == .Right || s.kind == .Left
}

// Axis-aligned ray vs AABB.
// cross_half_size widens the cross-axis check (0 = point ray, >0 = thick ray).
physics_raycast_rect :: proc(
	origin: [2]f32,
	axis: int,
	sign: f32,
	max_dist: f32,
	rect: Physics_Rect,
	cross_half_size: f32 = 0,
) -> Physics_Raycast_Hit {
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
physics_raycast_slope :: proc(
	origin: [2]f32,
	axis: int,
	sign: f32,
	max_dist: f32,
	slope: Physics_Slope,
	cross_half_size: f32 = 0,
) -> Physics_Raycast_Hit {
	cross := 1 - axis
	slope_base_cross := slope.base_x if axis == 1 else slope.base_y
	if origin[cross] + cross_half_size < slope_base_cross || origin[cross] - cross_half_size > slope_base_cross + slope.span do return {}

	surface_val :=
		physics_slope_surface_y(slope, origin.x) if axis == 1 else physics_slope_surface_x(slope, origin.y)

	dist := sign * (surface_val - origin[axis])
	if dist < 0 || dist > max_dist do return {}

	point: [2]f32
	point[axis] = surface_val
	point[cross] = origin[cross]
	return {hit = true, distance = dist, point = point}
}

// Separated-axis collision solver.
// Sweep X → resolve slopes → resolve X → sweep Y → resolve Y → resolve slopes.
physics_solve :: proc(
	body: ^Physics_Body,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
	dt: f32,
) {
	rect := physics_body_rect(body)

	body.pos.x += physics_solve_sweep_x(body, rect, geom, cfg, dt)
	rect = physics_body_rect(body)

	physics_solve_resolve_slopes(body, &rect, geom, cfg)
	physics_solve_resolve_x(body, &rect, geom, cfg)

	body.pos.y += physics_solve_sweep_y(body, rect, geom, cfg, dt)
	rect = physics_body_rect(body)

	physics_solve_resolve_y(body, &rect, geom, cfg)
	physics_solve_resolve_slopes(body, &rect, geom, cfg)
}

@(private = "file")
physics_solve_sweep_x :: proc(
	body: ^Physics_Body,
	rect: Physics_Rect,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
	dt: f32,
) -> f32 {
	delta_x := body.vel.x * dt
	if delta_x == 0 do return 0

	dir_x: f32 = math.sign(delta_x)
	origin: [2]f32 = {rect.pos.x + dir_x * rect.size.x / 2, rect.pos.y}
	travel := math.abs(delta_x)
	nearest: f32 = travel

	for c in geom.walls {
		wall_top := c.pos.y + c.size.y / 2
		body_bottom := rect.pos.y - rect.size.y / 2
		if body_bottom >= wall_top - cfg.step_height + cfg.eps do continue

		hit := physics_raycast_rect(origin, 0, dir_x, travel, c, rect.size.y / 2)
		if hit.hit && hit.distance < nearest {
			nearest = hit.distance
		}
	}

	safe := nearest - cfg.sweep_skin if nearest < travel else travel
	return dir_x * math.max(safe, 0)
}

@(private = "file")
physics_solve_sweep_y :: proc(
	body: ^Physics_Body,
	rect: Physics_Rect,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
	dt: f32,
) -> f32 {
	delta_y := body.vel.y * dt
	if delta_y == 0 do return 0

	dir_y: f32 = math.sign(delta_y)
	origin: [2]f32 = {rect.pos.x, rect.pos.y + dir_y * rect.size.y / 2}
	travel := math.abs(delta_y)
	nearest: f32 = travel

	if delta_y > 0 {
		for c in geom.ceiling {
			hit := physics_raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	if delta_y < 0 {
		for c in geom.ground {
			hit := physics_raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	if delta_y < 0 && .Dropping not_in body.flags {
		for c in geom.platforms {
			if body.pos.y >= c.pos.y + c.size.y / 2 - cfg.eps {
				hit := physics_raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
				if hit.hit && hit.distance < nearest {
					nearest = hit.distance
				}
			}
		}
	}

	safe := nearest - cfg.sweep_skin if nearest < travel else travel
	return dir_y * math.max(safe, 0)
}

@(private = "file")
physics_solve_resolve_x :: proc(
	body: ^Physics_Body,
	rect: ^Physics_Rect,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
) {
	for c in geom.walls {
		wall_top := c.pos.y + c.size.y / 2
		body_bottom := rect.pos.y - rect.size.y / 2
		if body_bottom >= wall_top - cfg.step_height + cfg.eps do continue

		resolved, _ := physics_rect_resolve(rect, c, body.vel.x, 0)
		if resolved {
			body.pos.x = rect.pos.x - body.offset.x
			body.vel.x = 0
		}
	}
}

@(private = "file")
physics_solve_resolve_y :: proc(
	body: ^Physics_Body,
	rect: ^Physics_Rect,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
) {
	for c in geom.ceiling {
		resolved, _ := physics_rect_resolve(rect, c, body.vel.y, 1)
		if resolved {
			body.pos.y = rect.pos.y - body.offset.y
			body.vel.y = 0
		}
	}

	if body.vel.y > 0 do return

	for c in geom.ground {
		resolved, _ := physics_rect_resolve(rect, c, body.vel.y, 1)
		if resolved {
			body.pos.y = rect.pos.y - body.offset.y
			body.vel.y = 0
		}
	}

	if .Dropping not_in body.flags {
		for c in geom.platforms {
			if body.pos.y >= c.pos.y + c.size.y / 2 - cfg.eps {
				resolved, _ := physics_rect_resolve(rect, c, body.vel.y, 1)
				if resolved {
					body.pos.y = rect.pos.y - body.offset.y
					body.vel.y = 0
				}
			}
		}
	}
}

@(private = "file")
physics_solve_resolve_slopes :: proc(
	body: ^Physics_Body,
	rect: ^Physics_Rect,
	geom: Physics_Static_Geometry,
	cfg: Physics_Solve_Config,
) {
	// Floor slopes
	found_floor := false
	best_floor_y := f32(-1e18)
	for c in geom.slopes {
		if !physics_slope_is_floor(c) do continue
		if body.pos.x >= c.base_x && body.pos.x <= c.base_x + c.span {
			sy := physics_slope_surface_y(c, body.pos.x)
			if sy > best_floor_y {
				best_floor_y = sy
				found_floor = true
			}
		}
	}

	if found_floor {
		dist := body.pos.y - best_floor_y
		if dist < 0 {
			body.pos.y = best_floor_y
			body.vel.y = math.max(body.vel.y, 0)
			rect^ = physics_body_rect(body)
		} else if body.vel.y <= 0 {
			snap := 2 * cfg.step_height if .Grounded in body.flags else cfg.slope_snap
			if dist <= snap {
				body.pos.y = best_floor_y
				body.vel.y = 0
				rect^ = physics_body_rect(body)
			}
		}
	}

	// Ceiling slopes
	body_top := body.pos.y + body.size.y
	for c in geom.slopes {
		if physics_slope_is_floor(c) do continue
		if body.pos.x >= c.base_x && body.pos.x <= c.base_x + c.span {
			sy := physics_slope_surface_y(c, body.pos.x)
			if body_top > sy {
				body.pos.y = sy - body.size.y
				if body.vel.y > 0 {
					body.vel.y = 0
				}
				rect^ = physics_body_rect(body)
			}
		}
	}
}
