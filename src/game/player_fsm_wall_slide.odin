package game

import sand "../sand"
import "core:math"
import "core:math/rand"

player_fsm_wall_slide_init :: proc(player: ^Player) {
	player.fsm.handlers[.Wall_Slide] = {
		update = player_fsm_wall_slide_update,
	}
}

// Wall_Slide — sliding down a wall (side or back). Clamps fall speed, dampens X.
// Side wall: snaps to wall, wall jump on buffer, stays while on wall.
// Back wall: lerps X to 0, no wall jump, exits on SLIDE release.
// - Airborne: jump buffered && on_side_wall (wall jump)
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground (landed)
// - Airborne: !on_side_wall && !on_back_wall (detached)
// - Airborne: on_back_wall && !on_side_wall && SLIDE released
player_fsm_wall_slide_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(ctx, dt)

	if ctx.body.vel.y < 0 do ctx.body.vel.y = math.max(ctx.body.vel.y, -PLAYER_WALL_SLIDE_SPEED)
	ctx.body.vel.x = math.lerp(ctx.body.vel.x, 0, PLAYER_MOVE_LERP_SPEED * dt)

	if ctx.sensor.on_side_wall {
		ctx.body.pos.x = ctx.sensor.on_side_wall_snap_x
		ctx.body.vel.x = 0
	}

	if ctx.sensor.on_sand_wall do sand.wall_erode(&game.sand_world, ctx.body.pos, PLAYER_SIZE, ctx.sensor.on_side_wall_dir)

	if player_wall_jump(ctx) do return .Airborne

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground do return .Grounded
	if !ctx.sensor.on_side_wall && !ctx.sensor.on_back_wall do return .Airborne
	if ctx.sensor.on_back_wall && !ctx.sensor.on_side_wall && !game.input.is_down[.SLIDE] do return .Airborne

	// Sparse dust from hand position while sliding
	if rand.float32() < PLAYER_PARTICLE_DUST_WALL_SLIDE_CHANCE {
		if ctx.sensor.on_side_wall {
			hand_pos := [2]f32 {
				ctx.body.pos.x + ctx.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
				ctx.body.pos.y + PLAYER_SIZE,
			}
			player_particles_dust_emit(
				&game.dust,
				hand_pos,
				{0, PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT),
			)
		} else if ctx.sensor.on_back_wall {
			hand_pos := [2]f32{ctx.body.pos.x - PLAYER_SIZE / 2, ctx.body.pos.y + PLAYER_SIZE}
			player_particles_dust_emit(
				&game.dust,
				hand_pos,
				{0, PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT),
			)
		}
	}

	return nil
}
