package game

import "core:math"

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
	player_apply_movement(ctx, dt)

	if ctx.transform.vel.y < 0 do ctx.transform.vel.y = math.max(ctx.transform.vel.y, -PLAYER_WALL_SLIDE_SPEED)
	ctx.transform.vel.x = math.lerp(ctx.transform.vel.x, 0, PLAYER_MOVE_LERP_SPEED * dt)

	if ctx.sensor.on_side_wall {
		ctx.transform.pos.x = ctx.sensor.on_side_wall_snap_x
		ctx.transform.vel.x = 0
	}

	if ctx.abilities.jump_buffer_timer > 0 && ctx.sensor.on_side_wall {
		ctx.transform.pos.x -= ctx.sensor.on_side_wall_dir * EPS
		ctx.transform.vel.y = PLAYER_WALL_JUMP_VERTICAL_MULT * PLAYER_JUMP_FORCE
		ctx.transform.vel.x = -ctx.sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
		ctx.abilities.jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if ctx.sensor.on_ground do return .Grounded
	if !ctx.sensor.on_side_wall && !ctx.sensor.on_back_wall do return .Airborne
	if ctx.sensor.on_back_wall && !ctx.sensor.on_side_wall && !game.input.is_down[.SLIDE] do return .Airborne

	return nil
}
