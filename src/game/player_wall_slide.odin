package game

import "core:math"

player_wall_slide_init :: proc() {
	player_fsm.handlers[.Wall_Slide] = {
		update = player_wall_slide_update,
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
player_wall_slide_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	if ctx.player_vel.y < 0 do ctx.player_vel.y = math.max(ctx.player_vel.y, -PLAYER_WALL_SLIDE_SPEED)
	ctx.player_vel.x = math.lerp(ctx.player_vel.x, 0, 15.0 * dt)

	if player_sensor.on_side_wall {
		ctx.player_pos.x = player_sensor.on_side_wall_snap_x
		ctx.player_vel.x = 0
	}

	if ctx.player_jump_buffer_timer > 0 && player_sensor.on_side_wall {
		ctx.player_pos.x -= player_sensor.on_side_wall_dir * EPS
		ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
		ctx.player_vel.x = -player_sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 do return .Dashing
	if player_sensor.on_ground do return .Grounded
	if !player_sensor.on_side_wall && !player_sensor.on_back_wall do return .Airborne
	if player_sensor.on_back_wall && !player_sensor.on_side_wall && !ctx.input.is_down[.SLIDE] do return .Airborne

	return nil
}
