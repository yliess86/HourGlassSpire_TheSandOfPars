package game

import engine "../engine"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl3"

Atmosphere :: struct {
	pool:        engine.Particle_Pool,
	accumulator: f32,
	time:        f32,
}

atmosphere_update :: proc(atm: ^Atmosphere, level: ^Level, dt: f32) {
	atm.time += dt

	// Spawn dust motes inside window rects
	total_area: f32
	for wr in level.window_rects {
		total_area += wr.size.x * wr.size.y
	}
	if total_area <= 0 do return

	atm.accumulator += total_area * ATMOSPHERE_DUST_SPAWN_RATE * dt
	for atm.accumulator >= 1.0 {
		atm.accumulator -= 1.0

		// Pick a random window rect weighted by area
		target := rand.float32() * total_area
		cum: f32
		for wr in level.window_rects {
			area := wr.size.x * wr.size.y
			cum += area
			if target <= cum {
				half := wr.size / 2
				pos :=
					wr.pos +
					[2]f32 {
							rand.float32_range(-half.x, half.x),
							rand.float32_range(-half.y, half.y),
						}
				phase := rand.float32() * math.TAU
				engine.particle_pool_emit(
					&atm.pool,
					{
						pos = pos,
						vel = {phase, ATMOSPHERE_DUST_SPEED_Y},
						lifetime = ATMOSPHERE_DUST_LIFETIME * rand.float32_range(0.7, 1.0),
						size = ATMOSPHERE_DUST_SIZE,
						color = ATMOSPHERE_DUST_COLOR,
					},
				)
				break
			}
		}
	}

	// Update particles: age + drift + sway
	for i := len(atm.pool.particles) - 1; i >= 0; i -= 1 {
		atm.pool.particles[i].age += dt
		if atm.pool.particles[i].age >= atm.pool.particles[i].lifetime {
			unordered_remove_soa(&atm.pool.particles, i)
			continue
		}
		atm.pool.particles[i].pos.y += ATMOSPHERE_DUST_SPEED_Y * dt
		phase := atm.pool.particles[i].vel.x // stored spawn phase in vel.x
		atm.pool.particles[i].pos.x +=
			math.cos(atm.time * ATMOSPHERE_DUST_SWAY_FREQ + phase) * ATMOSPHERE_DUST_SWAY_AMP * dt
	}
}

atmosphere_render :: proc(atm: ^Atmosphere) {
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_ADD)
	for i in 0 ..< len(atm.pool.particles) {
		p := atm.pool.particles[i]
		alpha_t := 1.0 - p.age / p.lifetime
		// Fade in during first 20%, fade out during last 30%
		fade_in := math.clamp(p.age / (p.lifetime * 0.2), 0, 1)
		fade := fade_in * alpha_t
		a := u8(f32(p.color.a) * fade)
		if a == 0 do continue
		rect := game_world_to_screen(p.pos - p.size / 2, {p.size, p.size})
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, a)
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}

atmosphere_destroy :: proc(atm: ^Atmosphere) {
	engine.particle_pool_destroy(&atm.pool)
}
