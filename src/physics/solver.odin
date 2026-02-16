package physics

import "core:math"

// Separated-axis collision solver.
// Sweep X → resolve slopes → resolve X → sweep Y → resolve Y → resolve slopes.
solve :: proc(body: ^Body, geom: Static_Geometry, cfg: Solve_Config, dt: f32) {
	rect := body_rect(body)

	body.pos.x += solve_sweep_x(body, rect, geom, cfg, dt)
	rect = body_rect(body)

	solve_resolve_slopes(body, &rect, geom, cfg)
	solve_resolve_x(body, &rect, geom, cfg)

	body.pos.y += solve_sweep_y(body, rect, geom, cfg, dt)
	rect = body_rect(body)

	solve_resolve_y(body, &rect, geom, cfg)
	solve_resolve_slopes(body, &rect, geom, cfg)
}

@(private = "file")
solve_sweep_x :: proc(
	body: ^Body,
	rect: Rect,
	geom: Static_Geometry,
	cfg: Solve_Config,
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

		hit := raycast_rect(origin, 0, dir_x, travel, c, rect.size.y / 2)
		if hit.hit && hit.distance < nearest {
			nearest = hit.distance
		}
	}

	safe := nearest - cfg.sweep_skin if nearest < travel else travel
	return dir_x * math.max(safe, 0)
}

@(private = "file")
solve_sweep_y :: proc(
	body: ^Body,
	rect: Rect,
	geom: Static_Geometry,
	cfg: Solve_Config,
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
			hit := raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	if delta_y < 0 {
		for c in geom.ground {
			hit := raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
			if hit.hit && hit.distance < nearest {
				nearest = hit.distance
			}
		}
	}

	if delta_y < 0 && .Dropping not_in body.flags {
		for c in geom.platforms {
			if body.pos.y >= c.pos.y + c.size.y / 2 - cfg.eps {
				hit := raycast_rect(origin, 1, dir_y, travel, c, rect.size.x / 2)
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
solve_resolve_x :: proc(body: ^Body, rect: ^Rect, geom: Static_Geometry, cfg: Solve_Config) {
	for c in geom.walls {
		wall_top := c.pos.y + c.size.y / 2
		body_bottom := rect.pos.y - rect.size.y / 2
		if body_bottom >= wall_top - cfg.step_height + cfg.eps do continue

		resolved, _ := rect_resolve(rect, c, body.vel.x, 0)
		if resolved {
			body.pos.x = rect.pos.x - body.offset.x
			body.vel.x = 0
		}
	}
}

@(private = "file")
solve_resolve_y :: proc(body: ^Body, rect: ^Rect, geom: Static_Geometry, cfg: Solve_Config) {
	for c in geom.ceiling {
		resolved, _ := rect_resolve(rect, c, body.vel.y, 1)
		if resolved {
			body.pos.y = rect.pos.y - body.offset.y
			body.vel.y = 0
		}
	}

	if body.vel.y > 0 do return

	for c in geom.ground {
		resolved, _ := rect_resolve(rect, c, body.vel.y, 1)
		if resolved {
			body.pos.y = rect.pos.y - body.offset.y
			body.vel.y = 0
		}
	}

	if .Dropping not_in body.flags {
		for c in geom.platforms {
			if body.pos.y >= c.pos.y + c.size.y / 2 - cfg.eps {
				resolved, _ := rect_resolve(rect, c, body.vel.y, 1)
				if resolved {
					body.pos.y = rect.pos.y - body.offset.y
					body.vel.y = 0
				}
			}
		}
	}
}

@(private = "file")
solve_resolve_slopes :: proc(body: ^Body, rect: ^Rect, geom: Static_Geometry, cfg: Solve_Config) {
	// Floor slopes
	found_floor := false
	best_floor_y := f32(-1e18)
	for c in geom.slopes {
		if !slope_is_floor(c) do continue
		if body.pos.x >= c.base_x && body.pos.x <= c.base_x + c.span {
			sy := slope_surface_y(c, body.pos.x)
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
			rect^ = body_rect(body)
		} else if body.vel.y <= 0 {
			snap := 2 * cfg.step_height if .Grounded in body.flags else cfg.slope_snap
			if dist <= snap {
				body.pos.y = best_floor_y
				body.vel.y = 0
				rect^ = body_rect(body)
			}
		}
	}

	// Ceiling slopes
	body_top := body.pos.y + body.size.y
	for c in geom.slopes {
		if slope_is_floor(c) do continue
		if body.pos.x >= c.base_x && body.pos.x <= c.base_x + c.span {
			sy := slope_surface_y(c, body.pos.x)
			if body_top > sy {
				body.pos.y = sy - body.size.y
				if body.vel.y > 0 {
					body.vel.y = 0
				}
				rect^ = body_rect(body)
			}
		}
	}
}
