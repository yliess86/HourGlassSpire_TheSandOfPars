package engine

import sdl "vendor:sdl3"

Clock :: struct {
	now_ticks:        u64,
	last_ticks:       u64,
	perf_freq:        u64,
	dt:               f32,
	fixed_dt:         f32,
	fixed_acc:        f32,
	target_fps:       u64,
	target_frame_sec: f32,
}

clock_init :: proc(target_fps: u64, fixed_steps: u64) -> (clock: Clock) {
	return Clock {
		now_ticks = sdl.GetPerformanceCounter(),
		last_ticks = sdl.GetPerformanceCounter(),
		perf_freq = sdl.GetPerformanceFrequency(),
		fixed_dt = 1.0 / (f32(fixed_steps) * f32(target_fps)),
		target_fps = target_fps,
		target_frame_sec = 1.0 / f32(target_fps),
	}
}

clock_update :: proc(clock: ^Clock) {
	clock.now_ticks = sdl.GetPerformanceCounter()
	frame_ticks := clock.now_ticks - clock.last_ticks
	frame_sec := f32(frame_ticks) / f32(clock.perf_freq)

	if frame_sec < clock.target_frame_sec {
		sleep_sec := clock.target_frame_sec - frame_sec
		sdl.Delay(u32(sleep_sec * 1_000.0))

		clock.now_ticks = sdl.GetPerformanceCounter()
		frame_ticks = clock.now_ticks - clock.last_ticks
		frame_sec = f32(frame_ticks) / f32(clock.perf_freq)
	}

	clock.last_ticks = clock.now_ticks
	if frame_sec > 0.1 do frame_sec = 0.1

	clock.dt = frame_sec
	clock.fixed_acc += clock.dt
}

clock_tick :: proc(clock: ^Clock) -> bool {
	if clock.fixed_acc >= clock.fixed_dt {
		clock.fixed_acc -= clock.fixed_dt
		return true
	}
	return false
}
