package game

player_fsm_dropping_init :: proc(player: ^Player) {
	player.fsm.handlers[.Dropping] = {
		update = player_fsm_dropping_update,
	}
}

// Dropping — falling through a one-way platform. Ignores platform collisions.
// - Airborne: !in_platform (exited all platforms)
player_fsm_dropping_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(ctx, dt)
	if ctx.sensor.in_platform do return nil
	return .Airborne
}
