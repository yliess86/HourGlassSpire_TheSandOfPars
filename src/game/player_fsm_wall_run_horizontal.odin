package game

player_fsm_wall_run_horizontal_init :: proc() {
	player_fsm.handlers[.Wall_Run_Horizontal] = {
		enter  = player_fsm_wall_run_horizontal_enter,
		update = player_fsm_wall_run_horizontal_update,
	}
}

player_fsm_wall_run_horizontal_enter :: proc(ctx: ^Game_State) {
	ctx.player_wall_run_used = true
	ctx.player_wall_run_timer = 0
	ctx.player_wall_run_dir = ctx.player_dash_dir
}

// Wall_Run_Horizontal — horizontal parabolic arc along a back wall. Direction-locked.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (ran off)
// - Grounded: on_ground (landed) AND falling
// - Airborne: vel.y < -WALL_SLIDE_SPEED (falling fast)
// - Airborne: on_side_wall (hit side wall)
player_fsm_wall_run_horizontal_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_wall_run_timer += dt
	ctx.player_vel.x = PLAYER_WALL_RUN_HORIZONTAL_SPEED * ctx.player_wall_run_dir
	ctx.player_vel.y =
		PLAYER_WALL_RUN_HORIZONTAL_LIFT -
		GRAVITY * PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT * ctx.player_wall_run_timer

	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 do return .Dashing
	if !player_sensor.on_back_wall do return .Airborne
	if player_sensor.on_ground && ctx.player_vel.y <= 0 do return .Grounded
	if ctx.player_vel.y < -PLAYER_WALL_SLIDE_SPEED do return .Airborne
	if player_sensor.on_side_wall do return .Airborne

	if !ctx.input.is_down[.WALL_RUN] {
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		if player_sensor.on_side_wall do ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	return nil
}
