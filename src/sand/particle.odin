package sand

import engine "../engine"
import "core:math"
import "core:math/rand"

// Emit displacement particles in a directional cone from a surface point
particles_emit :: proc(
	pool: ^engine.Particle_Pool,
	pos: [2]f32,
	spread_x, base_angle, half_spread: f32,
	vel_bias: [2]f32,
	color: [4]u8,
	count: int,
	speed_mult: f32 = 1.0,
) {
	for _ in 0 ..< count {
		spawn_pos := pos + {rand.float32() * spread_x * 2 - spread_x, 0}
		angle := base_angle + (rand.float32() * 2 - 1) * half_spread
		speed :=
			SAND_PARTICLE_SPEED *
			(SAND_PARTICLE_SPEED_RAND_MIN +
					(1.0 - SAND_PARTICLE_SPEED_RAND_MIN) * rand.float32()) *
			speed_mult
		vel := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed} + vel_bias
		engine.particle_pool_emit(
			pool,
			engine.Particle {
				pos = spawn_pos,
				vel = vel,
				lifetime = SAND_PARTICLE_LIFETIME *
				(SAND_PARTICLE_LIFETIME_RAND_MIN +
						(1.0 - SAND_PARTICLE_LIFETIME_RAND_MIN) * rand.float32()),
				age = 0,
				size = SAND_PARTICLE_SIZE,
				color = color,
			},
		)
	}
}

particles_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
	for i in 0 ..< pool.count {
		pool.items[i].vel.y -= SAND_PARTICLE_GRAVITY * dt
		pool.items[i].vel *= 1.0 - SAND_PARTICLE_FRICTION * dt
		pool.items[i].pos += pool.items[i].vel * dt
	}
}
