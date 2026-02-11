package engine

import "core:math"
import sdl "vendor:sdl3"

Camera :: struct {
	pos:              [2]f32, // center of viewport (world units / meters)
	size:             [2]f32, // viewport dimensions (world units / meters)
	ppm:              f32, // pixels per meter
	logical_h:        f32, // logical screen height in pixels
	// Follow parameters
	follow_speed_min: f32,
	follow_speed_max: f32,
	dead_zone:        f32,
	boundary_zone:    f32,
}

camera_init :: proc(viewport_w, viewport_h, ppm, logical_h: f32) -> Camera {
	return Camera{size = {viewport_w, viewport_h}, ppm = ppm, logical_h = logical_h}
}

// World-space rect (bottom-left + size in meters) → screen-space SDL rect (Y-flipped)
camera_world_to_screen :: proc(cam: ^Camera, world_pos, world_size: [2]f32) -> sdl.FRect {
	cam_bl := cam.pos - cam.size / 2
	rel := (world_pos - cam_bl) * cam.ppm
	sz := world_size * cam.ppm
	return {rel.x, cam.logical_h - rel.y - sz.y, sz.x, sz.y}
}

// World position → screen pixel (Y-flipped)
camera_world_to_screen_point :: proc(cam: ^Camera, world_pos: [2]f32) -> [2]f32 {
	cam_bl := cam.pos - cam.size / 2
	rel := (world_pos - cam_bl) * cam.ppm
	return {rel.x, cam.logical_h - rel.y}
}

camera_smoothstep :: proc(edge0, edge1, x: f32) -> f32 {
	t := clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
}

camera_follow :: proc(cam: ^Camera, target: [2]f32, bounds_min, bounds_max: [2]f32, dt: f32) {
	for i in 0 ..< 2 {
		offset := target[i] - cam.pos[i]
		half_vp := cam.size[i] / 2

		// Dead zone ramp: 0 inside dead zone, ramps to 1 at viewport edge
		normalized := abs(offset) / half_vp if half_vp > 0 else f32(0)
		t := camera_smoothstep(cam.dead_zone, 1.0, normalized)
		speed := math.lerp(cam.follow_speed_min, cam.follow_speed_max, t)

		// Boundary deceleration: slow down near level edges
		level_size := bounds_max[i] - bounds_min[i]
		if level_size > cam.size[i] && cam.boundary_zone > 0 {
			cam_edge_lo := cam.pos[i] - half_vp
			cam_edge_hi := cam.pos[i] + half_vp
			dist_lo := cam_edge_lo - bounds_min[i]
			dist_hi := bounds_max[i] - cam_edge_hi

			// Use the edge we're moving toward
			dist := dist_lo if offset < 0 else dist_hi
			boundary_t := camera_smoothstep(0, cam.boundary_zone, dist)
			speed = math.lerp(cam.follow_speed_min, speed, boundary_t)
		}

		cam.pos[i] += offset * (1 - math.exp(-speed * dt))
	}
}

camera_clamp :: proc(cam: ^Camera, bounds_min, bounds_max: [2]f32) {
	level_size := bounds_max - bounds_min

	// Per-axis: if level is smaller than viewport, center on level; otherwise clamp
	for i in 0 ..< 2 {
		if level_size[i] <= cam.size[i] {
			cam.pos[i] = bounds_min[i] + level_size[i] / 2
		} else {
			half := cam.size[i] / 2
			if cam.pos[i] - half < bounds_min[i] do cam.pos[i] = bounds_min[i] + half
			if cam.pos[i] + half > bounds_max[i] do cam.pos[i] = bounds_max[i] - half
		}
	}
}
