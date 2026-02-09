package engine

Camera :: struct {
	pos:  [2]f32, // center of viewport (world units / meters)
	size: [2]f32, // viewport dimensions (world units / meters)
}

camera_init :: proc(viewport_w, viewport_h: f32) -> Camera {
	return Camera{
		size = {viewport_w, viewport_h},
	}
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
