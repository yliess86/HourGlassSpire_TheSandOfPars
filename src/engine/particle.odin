package engine

Particle :: struct {
	pos:      [2]f32,
	vel:      [2]f32,
	lifetime: f32,
	age:      f32,
	size:     f32,
	color:    [4]u8,
}

PARTICLE_POOL_MAX :: 256

Particle_Pool :: struct {
	items: [PARTICLE_POOL_MAX]Particle,
	count: int,
}

particle_pool_emit :: proc(pool: ^Particle_Pool, p: Particle) {
	if pool.count >= PARTICLE_POOL_MAX do return
	pool.items[pool.count] = p
	pool.count += 1
}

particle_pool_update :: proc(pool: ^Particle_Pool, dt: f32) {
	i := pool.count - 1
	for i >= 0 {
		pool.items[i].age += dt
		if pool.items[i].age >= pool.items[i].lifetime {
			pool.count -= 1
			pool.items[i] = pool.items[pool.count]
		}
		i -= 1
	}
}
