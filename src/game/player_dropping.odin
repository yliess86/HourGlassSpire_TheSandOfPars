package game

player_dropping_init :: proc() {
	player_fsm.handlers[.Dropping] = {
		update = player_dropping_update,
	}
}

// Dropping — falling through a one-way platform. Ignores platform collisions.
// - Airborne: !in_platform (exited all platforms)
player_dropping_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)
	if player_sensor.in_platform do return nil
	return .Airborne
}
