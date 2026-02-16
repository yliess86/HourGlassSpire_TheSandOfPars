package game

import engine "../engine"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl3"

// Sand dust: emits light sand-colored particles when running on sand
@(private = "file")
sand_dust_counter: u8

sand_dust_tick :: proc(player: ^Player) {
	sand_dust_counter += 1
	if sand_dust_counter < engine.SAND_DUST_INTERVAL do return
	sand_dust_counter = 0

	if !player.sensor.on_sand do return
	if player.state != .Grounded do return
	if math.abs(player.body.vel.x) < engine.SAND_DUST_MIN_SPEED do return

	emit_x := player.body.pos.x - math.sign(player.body.vel.x) * PLAYER_SIZE / 4
	emit_pos := [2]f32{emit_x, player.body.pos.y}
	vel := [2]f32 {
		-math.sign(player.body.vel.x) *
		engine.SAND_DUST_SPEED *
		(engine.SAND_DUST_SPEED_RAND_MIN +
				(1.0 - engine.SAND_DUST_SPEED_RAND_MIN) * rand.float32()),
		engine.SAND_DUST_LIFT * rand.float32(),
	}
	dust_color := [4]u8 {
		min(engine.SAND_COLOR.r + engine.SAND_DUST_LIGHTEN, 255),
		min(engine.SAND_COLOR.g + engine.SAND_DUST_LIGHTEN, 255),
		min(engine.SAND_COLOR.b + engine.SAND_DUST_LIGHTEN, 255),
		engine.SAND_COLOR.a,
	}
	engine.particle_pool_emit(
		&game.dust,
		engine.Particle {
			pos = emit_pos,
			vel = vel,
			lifetime = engine.SAND_DUST_LIFETIME *
			(engine.SAND_DUST_LIFETIME_RAND_MIN +
					(1.0 - engine.SAND_DUST_LIFETIME_RAND_MIN) * rand.float32()),
			age = 0,
			size = engine.SAND_DUST_SIZE,
			color = dust_color,
		},
	)
}

sand_footprint_update :: proc(world: ^engine.Sand_World, player: ^Player) {
	if player.state != .Grounded do return
	if !player.sensor.on_sand do return
	if math.abs(player.body.vel.x) < engine.SAND_FOOTPRINT_MIN_SPEED do return
	if math.abs(player.body.pos.x - player.abilities.footprint_last_x) < engine.SAND_FOOTPRINT_STRIDE do return

	player.abilities.footprint_last_x = player.body.pos.x
	player.abilities.footprint_side = !player.abilities.footprint_side

	foot_gy := int(player.body.pos.y / engine.SAND_CELL_SIZE) - 1
	foot_gx := int(player.body.pos.x / engine.SAND_CELL_SIZE)

	if !engine.sand_in_bounds(world, foot_gx, foot_gy) do return
	idx := foot_gy * world.width + foot_gx
	foot_mat := world.cells[idx].material
	if foot_mat != .Sand && foot_mat != .Wet_Sand do return

	push_dx: int = player.body.vel.x > 0 ? -1 : 1
	saved := world.cells[idx]
	world.cells[idx] = engine.Sand_Cell{}

	chunk := engine.sand_chunk_at(world, foot_gx, foot_gy)
	if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
	engine.sand_chunk_mark_dirty(world, foot_gx, foot_gy)

	// Pile removed sand beside the footprint (no wake for persistence)
	placed := false
	for try_dx in ([2]int{push_dx, -push_dx}) {
		nx := foot_gx + try_dx
		if !engine.sand_in_bounds(world, nx, foot_gy) do continue
		if world.cells[foot_gy * world.width + nx].material != .Empty do continue
		world.cells[foot_gy * world.width + nx] = saved
		world.cells[foot_gy * world.width + nx].sleep_counter = engine.SAND_SLEEP_THRESHOLD
		n_chunk := engine.sand_chunk_at(world, nx, foot_gy)
		if n_chunk != nil do n_chunk.active_count += 1
		engine.sand_chunk_mark_dirty(world, nx, foot_gy)
		placed = true
		break
	}

	// Restore cell if no neighbor had room (mass conservation)
	if !placed {
		world.cells[idx] = saved
		if chunk != nil do chunk.active_count += 1
	}
}

sand_particles_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(f32(p.color.a) * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := game_world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}
