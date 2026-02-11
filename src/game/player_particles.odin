package game

import engine "../engine"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl3"

player_dust_emit :: proc(pool: ^engine.Particle_Pool, pos: [2]f32, vel_base: [2]f32, count: int) {
	for _ in 0 ..< count {
		angle := rand.float32() * 2 * math.PI
		speed := PLAYER_PARTICLE_DUST_SPEED_MIN + rand.float32() * (PLAYER_PARTICLE_DUST_SPEED_MAX - PLAYER_PARTICLE_DUST_SPEED_MIN)
		spread := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed}
		lifetime := PLAYER_PARTICLE_DUST_LIFETIME_MIN + rand.float32() * (PLAYER_PARTICLE_DUST_LIFETIME_MAX - PLAYER_PARTICLE_DUST_LIFETIME_MIN)
		engine.particle_pool_emit(pool, engine.Particle{
			pos      = pos,
			vel      = vel_base + spread,
			lifetime = lifetime,
			age      = 0,
			size     = PLAYER_PARTICLE_DUST_SIZE,
			color    = PLAYER_PARTICLE_DUST_COLOR,
		})
	}
}

player_dust_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
	for i in 0 ..< pool.count {
		pool.items[i].vel.y -= PLAYER_PARTICLE_DUST_GRAVITY * dt
		pool.items[i].vel *= 1.0 - PLAYER_PARTICLE_DUST_FRICTION * dt
		pool.items[i].pos += pool.items[i].vel * dt
	}
}

player_step_emit :: proc(pool: ^engine.Particle_Pool, pos: [2]f32) {
	engine.particle_pool_emit(pool, engine.Particle{
		pos      = pos,
		vel      = {0, 0},
		lifetime = PLAYER_PARTICLE_STEP_LIFETIME,
		age      = 0,
		size     = PLAYER_PARTICLE_STEP_SIZE,
		color    = PLAYER_PARTICLE_STEP_COLOR,
	})
}

player_step_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
}

player_step_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(255 * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}

player_dust_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(255 * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}
