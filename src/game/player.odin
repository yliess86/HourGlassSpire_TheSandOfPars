package game

import engine "../engine"
import "core:math"

// Player constants (meters, m/s, m/s²)
PLAYER_COYOTE_TIME_DURATION: f32 : 0.1 // seconds
PLAYER_DASH_COOLDOWN: f32 : 0.75 // seconds
PLAYER_DASH_DURATION: f32 : 0.15 // seconds
PLAYER_DASH_SPEED: f32 : 4 * PLAYER_RUN_SPEED
PLAYER_GROUND_CHECK_EPS: f32 : 1.0 / PPM // ground sensor downward extension
PLAYER_IMPACT_DECAY: f32 : 8.0
PLAYER_IMPACT_FREQ: f32 : 18.0
PLAYER_IMPACT_SCALE: f32 : 0.20
PLAYER_IMPACT_THRESHOLD: f32 : 50.0 / PPM
PLAYER_JUMP_BUFFER_DURATION: f32 : 0.1 // seconds
PLAYER_JUMP_FORCE: f32 : 700.0 / PPM
PLAYER_LOOK_DEFORM: f32 : 0.15
PLAYER_LOOK_SMOOTH: f32 : 12.0
PLAYER_RUN_BOB_AMPLITUDE: f32 : 0.06
PLAYER_RUN_BOB_SPEED: f32 : 12.0
PLAYER_RUN_SPEED: f32 : 300.0 / PPM
PLAYER_RUN_SPEED_THRESHOLD: f32 : 0.1 * PLAYER_RUN_SPEED
PLAYER_SIZE: f32 : 24.0 / PPM
PLAYER_SLOPE_DOWNHILL_FACTOR: f32 : 1.15
PLAYER_SLOPE_SNAP: f32 : 3.0 / PPM
PLAYER_SLOPE_UPHILL_FACTOR: f32 : 0.86
PLAYER_WALL_JUMP_EPS: f32 : 2.0 / PPM
PLAYER_WALL_JUMP_FORCE: f32 : 1.5 * PLAYER_JUMP_FORCE
PLAYER_WALL_RUN_COOLDOWN: f32 : 0.4 // seconds before re-trigger
PLAYER_WALL_RUN_DECAY: f32 : 3.0 // exponential decay rate (1/s)
PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT: f32 : 0.5 // gravity multiplier (< 1 = wider arc)
PLAYER_WALL_RUN_HORIZONTAL_LIFT: f32 : 400.0 / PPM // initial upward velocity
PLAYER_WALL_RUN_HORIZONTAL_SPEED: f32 : 350.0 / PPM // horizontal speed
PLAYER_WALL_RUN_VERTICAL_SPEED: f32 : 500.0 / PPM // initial upward speed
PLAYER_WALL_SLIDE_SPEED: f32 : 100.0 / PPM // same as side wall slide

Player_State :: enum u8 {
	Airborne,
	Dashing,
	Dropping,
	Grounded,
	Wall_Run_Horizontal,
	Wall_Run_Vertical,
	Wall_Slide,
}

PLAYER_COLOR := [Player_State][3]u8 {
	.Airborne            = {80, 200, 255},
	.Dashing             = {255, 50, 200},
	.Dropping            = {180, 100, 255},
	.Grounded            = {0, 150, 255},
	.Wall_Run_Horizontal = {255, 100, 60},
	.Wall_Run_Vertical   = {255, 100, 60},
	.Wall_Slide          = {255, 140, 60},
}

Player_Sensor :: struct {
	in_platform:         bool, // overlapping any platform (for Dropping exit)
	on_back_wall:        bool, // overlapping a back wall collider
	on_ground:           bool, // any upward surface (ground + platform + slope)
	on_platform:         bool, // surface is a platform (for drop-through)
	on_side_wall:        bool,
	on_side_wall_dir:    f32, // +1 right‹, -1 left, 0 no side wall
	on_side_wall_snap_x: f32, // inner edge X of detected left wall + PLAYER_SIZE/2 or right wall - PLAYER_SIZE/2
	on_slope:            bool,
	on_slope_dir:        f32, // +1 rises right, -1 rises left, 0 flat
}

player_fsm: engine.FSM(Game_State, Player_State)
player_sensor: Player_Sensor

// -- Init & Update

player_init :: proc() {
	player_airborne_init()
	player_dashing_init()
	player_dropping_init()
	player_grounded_init()
	player_wall_run_horizontal_init()
	player_wall_run_vertical_init()
	player_wall_slide_init()
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
	   player_fsm.current != .Wall_Run_Vertical &&
	   player_fsm.current != .Wall_Run_Horizontal {
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

player_color :: proc() -> [3]u8 {
	return PLAYER_COLOR[player_fsm.current]
}

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

	on_ground := false
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
			on_ground = true
			break
		}
	}

	// Wall sensors
	game.player_wall_sensor = {
		pos  = game.player_collider.pos,
		size = {PLAYER_SIZE + 2 * PLAYER_WALL_JUMP_EPS, PLAYER_SIZE},
	}
	player_sensor.on_side_wall = false
	player_sensor.on_side_wall_dir = 0
	for wall_collider in game.level.wall_colliders {
		if !engine.collider_check_rect_vs_rect(game.player_wall_sensor, wall_collider) do continue
		// Skip floor/ceiling contacts: require actual vertical overlap between
		// the player's collider and the wall (not just edge-touching from standing on it).
		overlap_y :=
			0.5 * (game.player_collider.size.y + wall_collider.size.y) -
			math.abs(game.player_collider.pos.y - wall_collider.pos.y)
		if overlap_y < PLAYER_GROUND_CHECK_EPS do continue
		wall_dir: f32 = wall_collider.pos.x < game.player_collider.pos.x ? -1 : 1
		wall_offset := wall_dir * (wall_collider.size.x / 2 + PLAYER_SIZE / 2)
		player_sensor.on_side_wall = true
		player_sensor.on_side_wall_dir = wall_dir
		player_sensor.on_side_wall_snap_x = wall_collider.pos.x - wall_offset
		break
	}

	// Platform: check overlap + direction
	player_sensor.in_platform = false
	player_sensor.on_platform = false
	for c in game.level.platform_colliders {
		if engine.collider_check_rect_vs_rect(game.player_collider, c) {
			player_sensor.in_platform = true
			if game.player_collider.pos.y > c.pos.y && game.player_vel.y <= 0 {
				player_sensor.on_platform = true
				break
			}
		}
	}

	// Slope sensor — trust the resolve result (computed earlier this frame)
	player_sensor.on_slope = game.player_on_slope
	player_sensor.on_slope_dir = game.player_slope_dir
	player_sensor.on_ground = on_ground || player_sensor.on_platform || player_sensor.on_slope

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
			break
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
