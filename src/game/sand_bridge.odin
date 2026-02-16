package game

import engine "../engine"
import sand "../sand"
import "core:math"

// Bridge between Player and sand.Interactor.
// Only file that knows about both types.

sand_interactor_from_player :: proc(player: ^Player) -> sand.Interactor {
	return sand.Interactor {
		pos = player.body.pos,
		vel = player.body.vel,
		size = PLAYER_SIZE,
		impact_pending = player.impact_pending,
		sand_immersion = player.sensor.sand_immersion,
		is_dashing = player.state == .Dashing,
		is_submerged = player.state == .Sand_Swim,
	}
}

sand_interactor_apply :: proc(player: ^Player, interactor: ^sand.Interactor) {
	player.body.vel = interactor.vel
	player.impact_pending = interactor.impact_pending
}

// Emit displacement/carve particles based on interactor outputs
sand_interact_particles :: proc(pool: ^engine.Particle_Pool, it: ^sand.Interactor) {
	if it.out_sand_displaced <= 0 && it.out_wet_sand_displaced <= 0 && it.out_water_displaced <= 0 do return

	if it.is_dashing {
		sand_interact_particles_dash(pool, it)
	} else {
		sand_interact_particles_displace(pool, it)
	}
}

@(private = "file")
sand_interact_particles_dash :: proc(pool: ^engine.Particle_Pool, it: ^sand.Interactor) {
	sand_carved := it.out_sand_displaced
	water_carved := it.out_water_displaced
	if sand_carved <= 0 && water_carved <= 0 do return

	dash_dir: f32 = it.vel.x > 0 ? 1 : -1
	emit_pos := [2]f32{it.pos.x + dash_dir * it.size / 2, it.pos.y + it.size / 2}
	spread: f32 = it.size / 4
	base_angle: f32 = math.PI / 2
	half_spread: f32 = math.PI / 3
	vel_bias := [2]f32{-dash_dir * PLAYER_DASH_SPEED * sand.SAND_DASH_PARTICLE_VEL_BIAS, 0}

	if sand_carved > 0 {
		sand.particles_emit(
			pool,
			emit_pos,
			spread,
			base_angle,
			half_spread,
			vel_bias,
			sand.SAND_COLOR,
			min(sand_carved, int(sand.SAND_DASH_PARTICLE_MAX)),
			sand.SAND_DASH_PARTICLE_SPEED_MULT,
		)
	}
	if water_carved > 0 {
		sand.particles_emit(
			pool,
			emit_pos,
			spread,
			base_angle,
			half_spread,
			vel_bias,
			sand.WATER_COLOR,
			min(water_carved, int(sand.SAND_DASH_PARTICLE_MAX)),
			sand.SAND_DASH_PARTICLE_SPEED_MULT,
		)
	}
}

@(private = "file")
sand_interact_particles_displace :: proc(pool: ^engine.Particle_Pool, it: ^sand.Interactor) {
	emit_y := it.out_surface_y if it.out_surface_found else it.pos.y
	emit_pos := [2]f32{it.pos.x, emit_y}
	spread := it.size / 2
	base_angle: f32 = math.PI / 2
	impact := it.out_impact_factor

	half_spread: f32 = math.PI / 3
	vel_bias: [2]f32
	if impact > 0 {
		half_spread = sand.SAND_IMPACT_PARTICLE_SPREAD
		vel_bias = {0, abs(it.vel.y) * sand.SAND_IMPACT_PARTICLE_VEL_BIAS}
	} else if abs(it.vel.x) > 0 {
		vel_bias = {
			-it.vel.x * sand.SAND_PARTICLE_VEL_BIAS_X,
			abs(it.vel.x) * sand.SAND_PARTICLE_VEL_BIAS_Y,
		}
	}

	if it.out_sand_displaced > 0 {
		count :=
			impact > 0 ? int(math.lerp(f32(sand.SAND_IMPACT_PARTICLE_MIN), f32(sand.SAND_IMPACT_PARTICLE_MAX), impact)) : min(it.out_sand_displaced, int(sand.SAND_DISPLACE_PARTICLE_MAX))
		speed_mult := math.lerp(f32(1), sand.SAND_IMPACT_PARTICLE_SPEED_MULT, impact)
		sand.particles_emit(
			pool,
			emit_pos,
			spread,
			base_angle,
			half_spread,
			vel_bias,
			sand.SAND_COLOR,
			count,
			speed_mult,
		)
	}
	if it.out_wet_sand_displaced > 0 {
		sand.particles_emit(
			pool,
			emit_pos,
			spread,
			base_angle,
			half_spread,
			vel_bias,
			sand.WET_SAND_COLOR,
			min(it.out_wet_sand_displaced, int(sand.SAND_DISPLACE_PARTICLE_MAX)),
		)
	}
	if it.out_water_displaced > 0 {
		sand.particles_emit(
			pool,
			emit_pos,
			spread,
			base_angle,
			half_spread,
			vel_bias,
			sand.WATER_COLOR,
			min(it.out_water_displaced, int(sand.SAND_DISPLACE_PARTICLE_MAX)),
		)
	}
}

// Construct sand.Level_Data from game Level (caller must delete .tiles and .original_tiles)
sand_level_data_from_level :: proc(level: ^Level) -> sand.Level_Data {
	n := level.width * level.height
	tiles := make([]sand.Tile_Kind, n)
	original_tiles := make([]sand.Tile_Kind, n)
	for i in 0 ..< n {
		tiles[i] = level_tile_to_sand(level.tiles[i])
		original_tiles[i] = level_tile_to_sand(level.original_tiles[i])
	}
	return sand.Level_Data {
		width = level.width,
		height = level.height,
		tiles = tiles,
		original_tiles = original_tiles,
		sand_piles = level.sand_piles[:],
		sand_emitters = level.sand_emitters[:],
		water_piles = level.water_piles[:],
		water_emitters = level.water_emitters[:],
	}
}

@(private = "file")
level_tile_to_sand :: proc(tile: Level_Tile_Kind) -> sand.Tile_Kind {
	switch tile {
	case .Solid:
		return .Solid
	case .Platform:
		return .Platform
	case .Slope_Right:
		return .Slope_Right
	case .Slope_Left:
		return .Slope_Left
	case .Slope_Ceil_Right:
		return .Slope_Ceil_Right
	case .Slope_Ceil_Left:
		return .Slope_Ceil_Left
	case .Empty, .Back_Wall, .Spawn, .Sand_Pile, .Water_Pile:
		return .Empty
	case .Sand_Emitter, .Water_Emitter:
		return .Solid
	}
	return .Empty
}
