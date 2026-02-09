package game

import "core:math"
import engine "../engine"

// Player constants (meters, m/s, m/s²)
PLAYER_COLOR_GROUNDED: [3]u8 : {0, 150, 255} // blue (base)
PLAYER_COLOR_AIRBORNE: [3]u8 : {80, 200, 255} // light cyan
PLAYER_COLOR_WALL_SLIDE: [3]u8 : {255, 140, 60} // orange
PLAYER_COLOR_WALL_RUN_START: [3]u8 : {0, 255, 100} // bright green (full speed)
PLAYER_COLOR_WALL_RUN_END: [3]u8 : {180, 255, 60} // yellow-green (decayed)
PLAYER_COLOR_DASHING: [3]u8 : {255, 50, 200} // magenta
PLAYER_COLOR_DROPPING: [3]u8 : {180, 100, 255} // purple
PLAYER_COLOR_BACK_RUN: [3]u8 : {255, 100, 60} // red-orange
PLAYER_COLOR_BACK_CLIMB_START: [3]u8 : {0, 220, 180} // teal (full speed)
PLAYER_COLOR_BACK_CLIMB_END: [3]u8 : {100, 240, 200} // pale teal (decayed)
PLAYER_COLOR_BACK_SLIDE: [3]u8 : {200, 100, 50} // deep orange
PLAYER_SIZE: f32 : 24.0 / PPM
PLAYER_JUMP_FORCE: f32 : 700.0 / PPM
PLAYER_RUN_SPEED: f32 : 300.0 / PPM
PLAYER_WALL_JUMP_EPS: f32 : 2.0 / PPM
PLAYER_WALL_JUMP_FORCE: f32 : 1.5 * PLAYER_JUMP_FORCE
PLAYER_WALL_SLIDE_SPEED: f32 : 100.0 / PPM
PLAYER_DASH_SPEED: f32 : 4 * PLAYER_RUN_SPEED
PLAYER_DASH_DURATION: f32 : 0.15 // seconds
PLAYER_DASH_COOLDOWN: f32 : 0.75 // seconds
PLAYER_COYOTE_TIME_DURATION: f32 : 0.1 // seconds
PLAYER_JUMP_BUFFER_DURATION: f32 : 0.1 // seconds
PLAYER_LOOK_DEFORM: f32 : 0.15
PLAYER_LOOK_SMOOTH: f32 : 12.0
PLAYER_RUN_BOB_AMPLITUDE: f32 : 0.06
PLAYER_RUN_BOB_SPEED: f32 : 12.0
PLAYER_RUN_SPEED_THRESHOLD: f32 : 0.1 * PLAYER_RUN_SPEED
PLAYER_IMPACT_SCALE: f32 : 0.20
PLAYER_IMPACT_FREQ: f32 : 18.0
PLAYER_IMPACT_DECAY: f32 : 8.0
PLAYER_IMPACT_THRESHOLD: f32 : 50.0 / PPM
PLAYER_WALL_RUN_SPEED: f32 : 500.0 / PPM // initial upward speed
PLAYER_WALL_RUN_DECAY: f32 : 3.0 // exponential decay rate (1/s)
PLAYER_WALL_RUN_COOLDOWN: f32 : 0.4 // seconds before re-trigger
PLAYER_GROUND_CHECK_EPS: f32 : 1.0 / PPM // ground sensor downward extension
PLAYER_BACK_RUN_SPEED: f32 : 350.0 / PPM // horizontal speed
PLAYER_BACK_RUN_LIFT: f32 : 400.0 / PPM // initial upward velocity
PLAYER_BACK_RUN_GRAV_MULT: f32 : 0.5 // gravity multiplier (< 1 = wider arc)
PLAYER_BACK_RUN_COOLDOWN: f32 : 0.4 // seconds
PLAYER_BACK_CLIMB_SPEED: f32 : 500.0 / PPM // same as side wall run
PLAYER_BACK_CLIMB_DECAY: f32 : 3.0 // same decay rate
PLAYER_BACK_SLIDE_SPEED: f32 : 100.0 / PPM // same as side wall slide
PLAYER_SLOPE_UPHILL_FACTOR: f32 : 0.86
PLAYER_SLOPE_DOWNHILL_FACTOR: f32 : 1.15
PLAYER_SLOPE_SNAP: f32 : 3.0 / PPM

Player_State :: enum u8 {
	Grounded,
	Airborne,
	Wall_Slide,
	Wall_Run,
	Dashing,
	Dropping,
	Back_Wall_Run,
	Back_Wall_Climb,
	Back_Wall_Slide,
}

Player_Sensor :: struct {
	on_ground:     bool, // any upward surface (ground + platform + slope)
	on_platform:   bool, // surface is a platform (for drop-through)
	in_platform:   bool, // overlapping any platform (for Dropping exit)
	on_left_wall:  bool,
	on_right_wall: bool,
	on_wall:       bool,
	on_back_wall:  bool, // overlapping a back wall collider
	on_slope:      bool,
	slope_dir:     f32, // +1 rises right, -1 rises left, 0 flat
	wall_l_snap_x: f32, // inner edge X of detected left wall + PLAYER_SIZE/2
	wall_r_snap_x: f32, // inner edge X of detected right wall - PLAYER_SIZE/2
}

player_fsm: engine.FSM(Game_State, Player_State)
player_sensor: Player_Sensor

// -- Init & Update

player_init :: proc() {
	player_fsm.handlers = {
		.Grounded = {update = grounded_update},
		.Airborne = {update = airborne_update},
		.Wall_Slide = {update = wall_slide_update},
		.Wall_Run = {update = wall_run_update},
		.Dashing = {update = dashing_update},
		.Dropping = {update = dropping_update},
		.Back_Wall_Run = {update = back_wall_run_update},
		.Back_Wall_Climb = {update = back_wall_climb_update},
		.Back_Wall_Slide = {update = back_wall_slide_update},
	}
	engine.fsm_init(&player_fsm, &game, Player_State.Grounded)
}

player_sync_collider :: proc() {
	game.player_collider.pos = {game.player_pos.x, game.player_pos.y + PLAYER_SIZE / 2}
}

player_fixed_update :: proc(dt: f32) {
	// ── 0. Tick timers ──────────────────────────────────────────────
	game.player_dash_active_timer = math.max(0, game.player_dash_active_timer - dt)
	game.player_dash_cooldown_timer = math.max(0, game.player_dash_cooldown_timer - dt)
	game.player_coyote_timer = math.max(0, game.player_coyote_timer - dt)
	game.player_jump_buffer_timer = math.max(0, game.player_jump_buffer_timer - dt)
	game.player_wall_run_cooldown_timer = math.max(0, game.player_wall_run_cooldown_timer - dt)
	game.player_back_climb_cooldown = math.max(0, game.player_back_climb_cooldown - dt)

	if game.input.is_pressed[.JUMP] do game.player_jump_buffer_timer = PLAYER_JUMP_BUFFER_DURATION
	game.player_dash_dir =
		game.input.axis.x != 0 ? math.sign(game.input.axis.x) : game.player_dash_dir

	// ── 1. FSM update (sets velocity, may snap position) ────────────
	engine.fsm_update(&player_fsm, dt)

	// Capture state for impact detection and platform checks
	start_vel := game.player_vel
	start_pos := game.player_pos

	// ── 2. X-Axis: move → resolve walls ─────────────────────────────
	game.player_pos.x += game.player_vel.x * dt
	player_sync_collider()

	for &c in game.level.wall_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(
			&game.player_collider,
			c,
			game.player_vel.x,
			0,
		)
		if resolved {
			game.player_pos.x = game.player_collider.pos.x
			game.player_vel.x = 0
		}
	}

	// ── 3. Y-Axis: move → resolve solids → resolve platforms ────────
	game.player_pos.y += game.player_vel.y * dt
	player_sync_collider()

	// 3a. Ground + ceiling (all solid colliders)
	for &c in game.level.ground_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(
			&game.player_collider,
			c,
			game.player_vel.y,
			1,
		)
		if resolved {
			game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
			game.player_vel.y = 0
		}
	}

	// 3b. One-way platforms (conditional)
	if player_fsm.current != .Dropping && game.player_vel.y <= 0 {
		for &c in game.level.platform_colliders {
			platform_top := c.pos.y + c.size.y / 2
			if start_pos.y < platform_top do continue

			resolved, normal := engine.collider_resolve_dynamic_rect(
				&game.player_collider,
				c,
				game.player_vel.y,
				1,
			)
			if resolved && normal > 0 {
				game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
				game.player_vel.y = 0
			}
		}
	}

	// ── 3c. Slope resolve ───────────────────────────────────────────
	player_resolve_slopes()

	// ── 3d. Re-resolve walls after slope push ───────────────────────
	// Slope resolve may push player into adjacent wall colliders
	player_sync_collider()
	for &c in game.level.wall_colliders {
		resolved, _ := engine.collider_resolve_dynamic_rect(
			&game.player_collider,
			c,
			0, // no velocity — just fix overlap
			0,
		)
		if resolved {
			game.player_pos.x = game.player_collider.pos.x
			game.player_vel.x = 0
		}
	}

	// ── 4. Finalize ─────────────────────────────────────────────────
	// Sensors (for next frame's FSM decisions)
	player_query_env()

	// Impact detection (compare pre-move velocity with post-resolve velocity)
	game.player_impact_timer += dt
	if start_vel.y < -PLAYER_IMPACT_THRESHOLD && game.player_vel.y == 0 {
		player_trigger_impact(math.abs(start_vel.y), {0, 1})
	}
	if player_fsm.current != .Wall_Slide &&
	   player_fsm.current != .Wall_Run &&
	   player_fsm.current != .Back_Wall_Run &&
	   player_fsm.current != .Back_Wall_Climb &&
	   player_fsm.current != .Back_Wall_Slide {
		if start_vel.x < -PLAYER_IMPACT_THRESHOLD && game.player_vel.x >= 0 {
			player_trigger_impact(math.abs(start_vel.x), {1, 0})
		}
		if start_vel.x > PLAYER_IMPACT_THRESHOLD && game.player_vel.x <= 0 {
			player_trigger_impact(math.abs(start_vel.x), {1, 0})
		}
	}

	// Visual deformation
	look_target: [2]f32 = game.input.axis if player_fsm.current != .Dashing else {0, 0}
	look_factor := PLAYER_LOOK_SMOOTH * dt
	game.player_visual_look.x = math.lerp(game.player_visual_look.x, look_target.x, look_factor)
	game.player_visual_look.y = math.lerp(game.player_visual_look.y, look_target.y, look_factor)

	if player_fsm.current == .Grounded &&
	   math.abs(game.player_vel.x) > PLAYER_RUN_SPEED_THRESHOLD {
		game.player_run_anim_timer +=
			dt * (math.abs(game.player_vel.x) / PLAYER_RUN_SPEED) * PLAYER_RUN_BOB_SPEED
	} else {
		game.player_run_anim_timer = 0
	}
}

// -- Helpers

player_apply_movement :: proc(dt: f32) {
	game.player_vel.x = math.lerp(
		game.player_vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED,
		15.0 * dt,
	)
	gravity_mult: f32 = 3.0 if game.player_vel.y > 0 && !game.input.is_down[.JUMP] else 1.0
	game.player_vel.y -= gravity_mult * GRAVITY * dt
}

player_query_env :: proc() {
	player_sync_collider()

	// Ground sensor: extend slightly downward for robustness against pre-resolve drift
	ground_sensor := engine.Collider_Rect {
		pos  = {
			game.player_collider.pos.x,
			game.player_collider.pos.y - PLAYER_GROUND_CHECK_EPS / 2,
		},
		size = {
			game.player_collider.size.x,
			game.player_collider.size.y + PLAYER_GROUND_CHECK_EPS,
		},
	}

	on_solid_ground := false
	for c in game.level.ground_colliders {
		diff := ground_sensor.pos - c.pos
		half_sum := 0.5 * (ground_sensor.size + c.size)
		overlap_x := half_sum.x - math.abs(diff.x)
		overlap_y := half_sum.y - math.abs(diff.y)
		if overlap_x > 0 &&
		   overlap_y > 0 &&
		   overlap_y <= overlap_x &&
		   diff.y > 0 &&
		   game.player_vel.y <= 0 { 	// overlapping// min-depth is Y (vertical contact, not wall)// player above collider// not moving upward
			on_solid_ground = true
			break
		}
	}

	// Wall sensors
	game.player_wall_sensor = {
		pos  = game.player_collider.pos,
		size = {PLAYER_SIZE + 2 * PLAYER_WALL_JUMP_EPS, PLAYER_SIZE},
	}
	player_sensor.on_left_wall = false
	player_sensor.on_right_wall = false
	for w in game.level.wall_colliders {
		if !engine.collider_check_rect_vs_rect(game.player_wall_sensor, w) do continue
		// Skip floor-level colliders — their top edge is at the player's feet
		wall_top := w.pos.y + w.size.y / 2
		if wall_top <= game.player_pos.y do continue
		if w.pos.x < game.player_collider.pos.x {
			if !player_sensor.on_left_wall {
				player_sensor.on_left_wall = true
				player_sensor.wall_l_snap_x = w.pos.x + w.size.x / 2 + PLAYER_SIZE / 2
			}
		} else {
			if !player_sensor.on_right_wall {
				player_sensor.on_right_wall = true
				player_sensor.wall_r_snap_x = w.pos.x - w.size.x / 2 - PLAYER_SIZE / 2
			}
		}
		if player_sensor.on_left_wall && player_sensor.on_right_wall do break
	}
	player_sensor.on_wall = player_sensor.on_left_wall || player_sensor.on_right_wall

	// Platform: check overlap + direction
	player_sensor.in_platform = false
	player_sensor.on_platform = false
	for c in game.level.platform_colliders {
		if engine.collider_check_rect_vs_rect(game.player_collider, c) {
			player_sensor.in_platform = true
			if game.player_collider.pos.y > c.pos.y && game.player_vel.y <= 0 {
				player_sensor.on_platform = true
			}
		}
	}

	// Slope sensor — trust the resolve result (computed earlier this frame)
	player_sensor.on_slope = game.player_on_slope
	player_sensor.slope_dir = game.player_slope_dir

	player_sensor.on_ground =
		on_solid_ground || player_sensor.on_platform || player_sensor.on_slope

	// Back wall sensor: overlap check with player collider
	player_sensor.on_back_wall = false
	for c in game.level.back_wall_colliders {
		if engine.collider_check_rect_vs_rect(game.player_collider, c) {
			player_sensor.on_back_wall = true
			break
		}
	}

}

player_resolve_slopes :: proc() {
	game.player_on_slope = false

	// Floor slopes
	player_sync_collider()
	for s in game.level.slope_colliders {
		if !engine.collider_slope_is_floor(s) do continue
		resolved, slope_dir := engine.collider_resolve_rect_vs_slope(&game.player_collider, s)
		if resolved {
			game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
			if game.player_vel.y < 0 do game.player_vel.y = 0
			game.player_on_slope = true
			game.player_slope_dir = slope_dir
		}
	}

	// Ceiling slopes (re-sync after floor push)
	player_sync_collider()
	for s in game.level.slope_colliders {
		if engine.collider_slope_is_floor(s) do continue
		resolved, _ := engine.collider_resolve_rect_vs_slope(&game.player_collider, s)
		if resolved {
			game.player_pos.y = game.player_collider.pos.y - PLAYER_SIZE / 2
			if game.player_vel.y > 0 do game.player_vel.y = 0
		}
	}

	// Downhill snap: if slightly above a slope and not rising, snap down
	if !game.player_on_slope && game.player_vel.y <= 0 {
		for s in game.level.slope_colliders {
			if !engine.collider_slope_is_floor(s) do continue
			half_w := PLAYER_SIZE / 2
			if game.player_pos.x + half_w < s.base_x || game.player_pos.x - half_w > s.base_x + s.span do continue
			sample_x :=
				game.player_pos.x + half_w if s.kind == .Right else game.player_pos.x - half_w
			surface_y := engine.collider_slope_surface_y(s, sample_x)
			gap := game.player_pos.y - surface_y
			if gap > 0 && gap < PLAYER_SLOPE_SNAP {
				game.player_pos.y = surface_y
				player_sync_collider()
				if game.player_vel.y < 0 do game.player_vel.y = 0
				game.player_on_slope = true
				game.player_slope_dir = 1 if s.kind == .Right else -1
				break
			}
		}
	}
}

player_check_dash :: proc() -> bool {
	if game.input.is_pressed[.DASH] && game.player_dash_cooldown_timer <= 0 {
		game.player_dash_active_timer = PLAYER_DASH_DURATION
		game.player_dash_cooldown_timer = PLAYER_DASH_COOLDOWN
		return true
	}
	return false
}

player_trigger_impact :: proc(impact_speed: f32, axis: [2]f32) {
	strength := math.clamp(impact_speed / PLAYER_JUMP_FORCE, 0, 1)
	remaining :=
		game.player_impact_strength * math.exp(-PLAYER_IMPACT_DECAY * game.player_impact_timer)
	if strength > remaining {
		game.player_impact_timer = 0
		game.player_impact_strength = strength
		game.player_impact_axis = axis
	}
}

player_get_color :: proc() -> [3]u8 {
	lerp_color :: proc(a, b: [3]u8, t: f32) -> [3]u8 {
		return {
			u8(math.lerp(f32(a.r), f32(b.r), t)),
			u8(math.lerp(f32(a.g), f32(b.g), t)),
			u8(math.lerp(f32(a.b), f32(b.b), t)),
		}
	}

	switch player_fsm.current {
	case .Grounded:
		return PLAYER_COLOR_GROUNDED
	case .Airborne:
		return PLAYER_COLOR_AIRBORNE
	case .Wall_Slide:
		return PLAYER_COLOR_WALL_SLIDE
	case .Wall_Run:
		t := math.clamp(game.player_wall_run_timer * PLAYER_WALL_RUN_DECAY, 0, 1)
		return lerp_color(PLAYER_COLOR_WALL_RUN_START, PLAYER_COLOR_WALL_RUN_END, t)
	case .Dashing:
		return PLAYER_COLOR_DASHING
	case .Dropping:
		return PLAYER_COLOR_DROPPING
	case .Back_Wall_Run:
		return PLAYER_COLOR_BACK_RUN
	case .Back_Wall_Climb:
		t := math.clamp(game.player_back_climb_timer * PLAYER_BACK_CLIMB_DECAY, 0, 1)
		return lerp_color(PLAYER_COLOR_BACK_CLIMB_START, PLAYER_COLOR_BACK_CLIMB_END, t)
	case .Back_Wall_Slide:
		return PLAYER_COLOR_BACK_SLIDE
	}
	return PLAYER_COLOR_GROUNDED
}

// -- State handlers

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
// - Dropping: on_platform && down held && jump buffered
// - Airborne: jump buffered (jump)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Run: on_wall && WALL_RUN held && !wall_run_used
// - Back_Wall_Run: on_back_wall && WALL_RUN held && horizontal input && !back_run_used
// - Back_Wall_Climb: on_back_wall && WALL_RUN held (default)
// - Airborne: !on_ground (fell off edge)
grounded_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	// Slope speed modifiers
	if player_sensor.on_slope {
		moving_uphill := math.sign(ctx.player_vel.x) == player_sensor.slope_dir
		if moving_uphill {
			ctx.player_vel.x *= PLAYER_SLOPE_UPHILL_FACTOR
		} else if ctx.player_vel.x != 0 {
			ctx.player_vel.x *= PLAYER_SLOPE_DOWNHILL_FACTOR
		}
	}

	ctx.player_vel.y = 0 // stay flush — slope snap handles downhill contact
	ctx.player_wall_run_cooldown_timer = 0
	ctx.player_back_run_used = false
	ctx.player_back_climb_cooldown = 0

	// Refresh coyote timer
	ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION

	// Drop through platform (before jump so down+jump → drop)
	if player_sensor.on_platform && ctx.input.axis.y < -0.5 && ctx.player_jump_buffer_timer > 0 {
		ctx.player_pos.y -= 2.0 / PPM
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		return .Dropping
	}

	// Jump
	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		return .Airborne
	}

	// Dash
	if player_check_dash() do return .Dashing

	// Side wall run from ground
	if player_sensor.on_wall && ctx.input.is_down[.WALL_RUN] && !ctx.player_wall_run_used {
		ctx.player_wall_run_timer = 0
		return .Wall_Run
	}

	// Back wall run (WALL_RUN + explicit horizontal input + not used)
	if player_sensor.on_back_wall &&
	   ctx.input.is_down[.WALL_RUN] &&
	   math.abs(ctx.input.axis.x) > 0.5 &&
	   !ctx.player_back_run_used {
		ctx.player_back_run_timer = 0
		ctx.player_back_run_dir = ctx.player_dash_dir
		return .Back_Wall_Run
	}

	// Back wall climb (WALL_RUN held — default when no horizontal input)
	if player_sensor.on_back_wall && ctx.input.is_down[.WALL_RUN] {
		ctx.player_back_climb_timer = 0
		return .Back_Wall_Climb
	}

	// Fell off edge (on_ground covers both ground and platforms)
	if !player_sensor.on_ground do return .Airborne

	ctx.player_wall_run_used = false
	return nil
}

// Airborne — in the air under gravity. Supports coyote jump (stays Airborne) and wall jump (stays Airborne).
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground (landed)
// - Wall_Run: on_wall && WALL_RUN held && wall_run_cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: on_wall && SLIDE held
// - Back_Wall_Run: on_back_wall && WALL_RUN held && horizontal input && !back_run_used && back_climb_cooldown ready
// - Back_Wall_Climb: on_back_wall && WALL_RUN held && back_climb_cooldown ready (default)
// - Back_Wall_Slide: on_back_wall && SLIDE held
airborne_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	// Coyote jump
	if ctx.player_jump_buffer_timer > 0 && ctx.player_coyote_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		// Stay airborne (already jumping)
	}

	// Dash
	if player_check_dash() do return .Dashing

	// Landing (ground or platform)
	if player_sensor.on_ground do return .Grounded

	// Side wall contact (priority over back wall — physically constraining)
	if player_sensor.on_wall {
		if math.abs(ctx.player_vel.x) > PLAYER_IMPACT_THRESHOLD {
			player_trigger_impact(math.abs(ctx.player_vel.x), {1, 0})
		}
		// Wall jump directly from airborne
		if ctx.player_jump_buffer_timer > 0 {
			if player_sensor.on_left_wall {
				ctx.player_pos.x += EPS
				ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
				ctx.player_vel.x = PLAYER_WALL_JUMP_FORCE
			} else if player_sensor.on_right_wall {
				ctx.player_pos.x -= EPS
				ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
				ctx.player_vel.x = -PLAYER_WALL_JUMP_FORCE
			}
			ctx.player_jump_buffer_timer = 0
			return nil // stay Airborne with wall-jump velocity
		}
		if ctx.input.is_down[.WALL_RUN] &&
		   ctx.player_wall_run_cooldown_timer <= 0 &&
		   !ctx.player_wall_run_used &&
		   ctx.player_vel.y > 0 {
			ctx.player_wall_run_timer = 0
			return .Wall_Run
		}
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
	}

	// Back wall contact
	if player_sensor.on_back_wall {
		// Back wall run: WALL_RUN + explicit horizontal input + not used
		if ctx.input.is_down[.WALL_RUN] &&
		   math.abs(ctx.input.axis.x) > 0.5 &&
		   !ctx.player_back_run_used &&
		   ctx.player_back_climb_cooldown <= 0 {
			ctx.player_back_run_timer = 0
			ctx.player_back_run_dir = ctx.player_dash_dir
			return .Back_Wall_Run
		}
		// Back wall climb: WALL_RUN held (default)
		if ctx.input.is_down[.WALL_RUN] && ctx.player_back_climb_cooldown <= 0 {
			ctx.player_back_climb_timer = 0
			return .Back_Wall_Climb
		}
		// Back wall slide: SLIDE
		if ctx.input.is_down[.SLIDE] do return .Back_Wall_Slide
	}

	return nil
}

// Wall_Slide — sliding down a side wall. Snaps to wall, clamps fall speed.
// - Airborne: jump buffered (wall jump)
// - Wall_Run: WALL_RUN held && wall_run_cooldown ready && !wall_run_used && vel.y > 0
// - Dashing: DASH pressed && cooldown ready
// - Grounded: on_ground (landed)
// - Airborne: !on_wall (detached)
wall_slide_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	// Wall snap
	if player_sensor.on_left_wall {
		ctx.player_pos.x = player_sensor.wall_l_snap_x
		ctx.player_vel.x = math.max(0, ctx.player_vel.x)
	}
	if player_sensor.on_right_wall {
		ctx.player_pos.x = player_sensor.wall_r_snap_x
		ctx.player_vel.x = math.min(0, ctx.player_vel.x)
	}

	// Slow down X velocity
	ctx.player_vel.x = math.lerp(ctx.player_vel.x, 0, 15.0 * dt)

	// Slide speed clamp
	if ctx.player_vel.y < 0 {
		ctx.player_vel.y = math.max(ctx.player_vel.y, -PLAYER_WALL_SLIDE_SPEED)
	}

	// Wall jump
	if ctx.player_jump_buffer_timer > 0 {
		if player_sensor.on_left_wall {
			ctx.player_pos.x += EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = PLAYER_WALL_JUMP_FORCE
		} else if player_sensor.on_right_wall {
			ctx.player_pos.x -= EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = -PLAYER_WALL_JUMP_FORCE
		}
		ctx.player_jump_buffer_timer = 0
		return .Airborne
	}

	// Wall run
	if ctx.input.is_down[.WALL_RUN] &&
	   ctx.player_wall_run_cooldown_timer <= 0 &&
	   !ctx.player_wall_run_used &&
	   ctx.player_vel.y > 0 {
		ctx.player_wall_run_timer = 0
		return .Wall_Run
	}

	// Dash
	if player_check_dash() do return .Dashing

	// Ground
	if player_sensor.on_ground do return .Grounded

	// Detach
	if !player_sensor.on_wall do return .Airborne

	return nil
}

// Wall_Run — running up a side wall with exponential speed decay. No gravity. Sets wall_run_used on exit.
// - Airborne: jump buffered (wall jump away from wall)
// - Dashing: DASH pressed && cooldown ready
// - Wall_Slide: speed decayed below slide speed && SLIDE held
// - Airborne: speed decayed below slide speed && !SLIDE
// - Wall_Slide: WALL_RUN released && SLIDE held
// - Airborne: WALL_RUN released && !SLIDE
// - Airborne: !on_wall (detached)
// - Grounded: on_ground (landed)
wall_run_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_wall_run_timer += dt

	// X-axis movement (same lerp as player_apply_movement but no gravity)
	ctx.player_vel.x = math.lerp(ctx.player_vel.x, ctx.input.axis.x * PLAYER_RUN_SPEED, 15.0 * dt)

	// Wall snap (identical to Wall_Slide)
	if player_sensor.on_left_wall {
		ctx.player_pos.x = player_sensor.wall_l_snap_x
		ctx.player_vel.x = math.max(0, ctx.player_vel.x)
	}
	if player_sensor.on_right_wall {
		ctx.player_pos.x = player_sensor.wall_r_snap_x
		ctx.player_vel.x = math.min(0, ctx.player_vel.x)
	}

	// Upward speed with exponential decay
	ctx.player_vel.y =
		PLAYER_WALL_RUN_SPEED * math.exp(-PLAYER_WALL_RUN_DECAY * ctx.player_wall_run_timer)

	// Wall jump (same physics as Wall_Slide)
	if ctx.player_jump_buffer_timer > 0 {
		if player_sensor.on_left_wall {
			ctx.player_pos.x += EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = PLAYER_WALL_JUMP_FORCE
		} else if player_sensor.on_right_wall {
			ctx.player_pos.x -= EPS
			ctx.player_vel.y = 0.75 * PLAYER_JUMP_FORCE
			ctx.player_vel.x = -PLAYER_WALL_JUMP_FORCE
		}
		ctx.player_jump_buffer_timer = 0
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		return .Airborne
	}

	// Dash
	if player_check_dash() {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		return .Dashing
	}

	// Speed decayed
	if ctx.player_vel.y <= PLAYER_WALL_SLIDE_SPEED {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	// Button released
	if !ctx.input.is_down[.WALL_RUN] {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	// Detached from wall
	if !player_sensor.on_wall {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		ctx.player_coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	// Ground
	if player_sensor.on_ground {
		ctx.player_wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
		ctx.player_wall_run_used = true
		return .Grounded
	}

	return nil
}

// Dashing — direction-locked horizontal burst. Zero gravity. Transitions on timer expiry.
// - Grounded: timer expired && on_ground
// - Wall_Run: timer expired && on_wall && WALL_RUN held && wall_run_cooldown ready && !wall_run_used && vel.y > 0
// - Wall_Slide: timer expired && on_wall && SLIDE held
// - Airborne: timer expired (default)
dashing_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	// Timer expired — apply normal movement on expiry frame, then transition
	if ctx.player_dash_active_timer <= 0 {
		player_apply_movement(dt)
		if player_sensor.on_ground do return .Grounded
		if player_sensor.on_wall {
			if math.abs(ctx.player_vel.x) > PLAYER_IMPACT_THRESHOLD {
				player_trigger_impact(math.abs(ctx.player_vel.x), {1, 0})
			}
			if ctx.input.is_down[.WALL_RUN] &&
			   ctx.player_wall_run_cooldown_timer <= 0 &&
			   !ctx.player_wall_run_used &&
			   ctx.player_vel.y > 0 {
				ctx.player_wall_run_timer = 0
				return .Wall_Run
			}
			if ctx.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	// Active dash
	ctx.player_vel.x = ctx.player_dash_dir * PLAYER_DASH_SPEED
	ctx.player_vel.y = 0

	return nil
}

// Dropping — falling through a one-way platform. Ignores platform collisions.
// - Airborne: jump_buffer > 0 && coyote_timer > 0 (coyote jump)
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !in_platform (exited all platforms)
dropping_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	// Coyote jump
	if ctx.player_jump_buffer_timer > 0 && ctx.player_coyote_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_coyote_timer = 0
		return .Airborne
	}

	// Dash
	if player_check_dash() do return .Dashing

	// Still overlapping a platform — keep dropping through
	if player_sensor.in_platform do return nil

	// Exited all platforms
	return .Airborne
}

// -- Back Wall State Handlers

// Back_Wall_Run — horizontal parabolic arc along a back wall. Direction-locked.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (ran off)
// - Grounded: on_ground (landed)
// - Airborne: vel.y < -BACK_SLIDE_SPEED (falling fast)
// - Airborne: on_wall (hit side wall)
back_wall_run_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_back_run_timer += dt

	// Direction-locked horizontal + parabolic vertical
	ctx.player_vel.x = PLAYER_BACK_RUN_SPEED * ctx.player_back_run_dir
	ctx.player_vel.y =
		PLAYER_BACK_RUN_LIFT - GRAVITY * PLAYER_BACK_RUN_GRAV_MULT * ctx.player_back_run_timer

	// Jump
	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_back_run_used = true
		return .Airborne
	}

	// Dash
	if player_check_dash() {
		ctx.player_back_run_used = true
		return .Dashing
	}

	// Ran off back wall
	if !player_sensor.on_back_wall {
		ctx.player_back_run_used = true
		return .Airborne
	}

	// Landed
	if player_sensor.on_ground {
		ctx.player_back_run_used = true
		return .Grounded
	}

	// Past arc, falling fast
	if ctx.player_vel.y < -PLAYER_BACK_SLIDE_SPEED {
		ctx.player_back_run_used = true
		return .Airborne
	}

	// Hit side wall
	if player_sensor.on_wall {
		ctx.player_back_run_used = true
		return .Airborne
	}

	return nil
}

// Back_Wall_Climb — climbing up a back wall with exponential speed decay. X velocity locked.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (left back wall)
// - Grounded: on_ground (landed)
// - Back_Wall_Slide: speed decayed && SLIDE held
// - Airborne: speed decayed && !SLIDE
// - Back_Wall_Slide: WALL_RUN released && SLIDE held
// - Airborne: WALL_RUN released && !SLIDE
back_wall_climb_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	ctx.player_back_climb_timer += dt

	// Lock horizontal movement during climb
	ctx.player_vel.x = 0

	// Upward speed with exponential decay
	ctx.player_vel.y =
		PLAYER_BACK_CLIMB_SPEED * math.exp(-PLAYER_BACK_CLIMB_DECAY * ctx.player_back_climb_timer)

	// Jump
	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		return .Airborne
	}

	// Dash
	if player_check_dash() {
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		return .Dashing
	}

	// Left back wall
	if !player_sensor.on_back_wall {
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		return .Airborne
	}

	// Landed
	if player_sensor.on_ground {
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		return .Grounded
	}

	// Speed decayed below slide speed
	if ctx.player_vel.y <= PLAYER_BACK_SLIDE_SPEED {
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		if ctx.input.is_down[.SLIDE] do return .Back_Wall_Slide
		return .Airborne
	}

	// WALL_RUN released
	if !ctx.input.is_down[.WALL_RUN] {
		ctx.player_back_climb_cooldown = PLAYER_WALL_RUN_COOLDOWN
		if ctx.input.is_down[.SLIDE] do return .Back_Wall_Slide
		return .Airborne
	}

	return nil
}

// Back_Wall_Slide — sliding down a back wall. Clamps fall speed.
// - Airborne: jump buffered
// - Dashing: DASH pressed && cooldown ready
// - Airborne: !on_back_wall (left back wall)
// - Airborne: SLIDE released
// - Grounded: on_ground (landed)
// - Back_Wall_Climb: WALL_RUN held && back_climb_cooldown ready
back_wall_slide_update :: proc(ctx: ^Game_State, dt: f32) -> Maybe(Player_State) {
	player_apply_movement(dt)

	// Slow down X velocity
	ctx.player_vel.x = math.lerp(ctx.player_vel.x, 0, 15.0 * dt)

	// Clamp downward speed
	if ctx.player_vel.y < -PLAYER_BACK_SLIDE_SPEED {
		ctx.player_vel.y = -PLAYER_BACK_SLIDE_SPEED
	}

	// Jump
	if ctx.player_jump_buffer_timer > 0 {
		ctx.player_vel.y = PLAYER_JUMP_FORCE
		ctx.player_jump_buffer_timer = 0
		return .Airborne
	}

	// Dash
	if player_check_dash() do return .Dashing

	// Left back wall
	if !player_sensor.on_back_wall do return .Airborne

	// SLIDE released
	if !ctx.input.is_down[.SLIDE] do return .Airborne

	// Landed
	if player_sensor.on_ground do return .Grounded

	// Transition to back wall climb
	if ctx.input.is_down[.WALL_RUN] && ctx.player_back_climb_cooldown <= 0 {
		ctx.player_back_climb_timer = 0
		return .Back_Wall_Climb
	}

	return nil
}
