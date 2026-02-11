package game

player_fsm_wall_run_horizontal_init :: proc(player: ^Player) {
	player.fsm.handlers[.Wall_Run_Horizontal] = {
		enter  = player_fsm_wall_run_horizontal_enter,
		update = player_fsm_wall_run_horizontal_update,
	}
}

player_fsm_wall_run_horizontal_enter :: proc(ctx: ^Player) {
	ctx.abilities.wall_run_used = true
	ctx.abilities.wall_run_timer = 0
	ctx.abilities.wall_run_dir = ctx.abilities.dash_dir
}

// Wall_Run_Horizontal — horizontal parabolic arc along a back wall. Direction-locked.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (ran off)
// - Grounded: on_ground (landed) AND falling
// - Airborne: vel.y < -WALL_SLIDE_SPEED (falling fast)
// - Airborne: on_side_wall (hit side wall)
player_fsm_wall_run_horizontal_update :: proc(ctx: ^Player, dt: f32) -> Maybe(Player_State) {
	ctx.abilities.wall_run_timer += dt
	ctx.transform.vel.x = PLAYER_WALL_RUN_HORIZONTAL_SPEED * ctx.abilities.wall_run_dir
	ctx.transform.vel.y =
		PLAYER_WALL_RUN_HORIZONTAL_LIFT -
		GRAVITY * PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT * ctx.abilities.wall_run_timer

	if ctx.abilities.jump_buffer_timer > 0 {
		ctx.transform.vel.y = PLAYER_JUMP_FORCE
		ctx.abilities.jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && ctx.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if !ctx.sensor.on_back_wall do return .Airborne
	if ctx.sensor.on_ground && ctx.transform.vel.y <= 0 do return .Grounded
	if ctx.transform.vel.y < -PLAYER_WALL_SLIDE_SPEED do return .Airborne
	if ctx.sensor.on_side_wall do return .Airborne

	if !game.input.is_down[.WALL_RUN] {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if ctx.sensor.on_side_wall do ctx.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	return nil
}
