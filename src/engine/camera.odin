package engine

import sdl "vendor:sdl3"

Camera :: struct {
	pos:       [2]f32, // center of viewport (world units / meters)
	size:      [2]f32, // viewport dimensions (world units / meters)
	ppm:       f32, // pixels per meter
	logical_h: f32, // logical screen height in pixels
}

camera_init :: proc(viewport_w, viewport_h, ppm, logical_h: f32) -> Camera {
	return Camera{
		size      = {viewport_w, viewport_h},
		ppm       = ppm,
		logical_h = logical_h,
	}
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

camera_follow :: proc(cam: ^Camera, target: [2]f32) {
	cam.pos = target
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
