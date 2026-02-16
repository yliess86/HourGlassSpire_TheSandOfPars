package engine

Particle :: struct {
	pos:      [2]f32,
	vel:      [2]f32,
	lifetime: f32,
	age:      f32,
	size:     f32,
	color:    [4]u8,
}

Particle_Pool :: struct {
	particles: #soa[dynamic]Particle,
}

particle_pool_emit :: proc(pool: ^Particle_Pool, p: Particle) {
	append_soa(&pool.particles, p)
}

particle_pool_update :: proc(pool: ^Particle_Pool, dt: f32) {
	for i := len(pool.particles) - 1; i >= 0; i -= 1 {
		pool.particles[i].age += dt
		if pool.particles[i].age >= pool.particles[i].lifetime {
			unordered_remove_soa(&pool.particles, i)
		}
	}
}

particle_pool_destroy :: proc(pool: ^Particle_Pool) {
	delete(pool.particles)
}
