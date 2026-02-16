package game

import engine "../engine"
import "core:math"
import "core:math/rand"

// --- Types ---

Player_State :: enum u8 {
	Airborne,
	Dashing,
	Dropping,
	Grounded,
	Sand_Swim,
	Swimming,
	Wall_Run_Horizontal,
	Wall_Run_Vertical,
	Wall_Slide,
}

Player_Abilities :: struct {
	dash_dir:                f32,
	dash_active_timer:       f32,
	dash_cooldown_timer:     f32,
	coyote_timer:            f32,
	jump_buffer_timer:       f32,
	wall_run_timer:          f32,
	wall_run_cooldown_timer: f32,
	wall_run_used:           bool,
	wall_run_dir:            f32,
	ground_sticky_timer:     f32,
	sand_hop_cooldown_timer: f32,
	footprint_last_x:        f32,
	footprint_side:          bool,
}

Player_Graphics :: struct {
	visual_look:     [2]f32,
	run_anim_timer:  f32,
	impact_timer:    f32,
	impact_strength: f32,
	impact_axis:     [2]f32,
}

Player_Sensor :: struct {
	in_platform:          bool, // overlapping any platform (for Dropping exit)
	on_back_wall:         bool, // overlapping a back wall collider
	on_ground:            bool, // any upward surface (ground + platform + slope)
	on_ground_snap_y:     f32, // surface Y of detected ground (for snapping on land)
	on_platform:          bool, // surface is a platform (for drop-through)
	on_sand:              bool, // standing on sand surface (sand is the ground)
	sand_immersion:       f32, // 0.0 (free) to 1.0 (buried)
	on_water:             bool, // overlapping water cells (informational, does not count as ground)
	water_immersion:      f32, // 0.0 (free) to 1.0 (submerged)
	on_side_wall:         bool,
	on_side_wall_dir:     f32, // +1 right, -1 left, 0 no side wall
	on_side_wall_snap_x:  f32, // inner edge X of detected left wall + PLAYER_SIZE/2 or right wall - PLAYER_SIZE/2
	on_sand_wall:         bool, // side wall is a sand/wet sand column (not solid)
	on_slope:             bool,
	on_slope_dir:         f32, // +1 uphill, -1 downhill, 0 flat
	// Debug: cached raycast hits for visualization
	debug_ground_hit:     engine.Physics_Raycast_Hit,
	debug_slope_hit:      engine.Physics_Raycast_Hit,
	debug_platform_hit:   engine.Physics_Raycast_Hit,
	debug_wall_left_hit:  engine.Physics_Raycast_Hit,
	debug_wall_right_hit: engine.Physics_Raycast_Hit,
}

Player :: struct {
	body:           engine.Physics_Body,
	impact_pending: f32, // landing speed, consumed by sand_interact
	abilities:      Player_Abilities,
	graphics:       Player_Graphics,
	state:          Player_State,
	previous_state: Player_State,
	sensor:         Player_Sensor,
}

// --- Public API ---

player_init :: proc(player: ^Player) {
	player.body.size = {PLAYER_SIZE, PLAYER_SIZE}
	player.body.offset = {0, PLAYER_SIZE / 2}
	player.state = .Grounded
	player.previous_state = .Grounded
	sensor_update(player)
}

player_fixed_update :: proc(player: ^Player, dt: f32) {
	player.abilities.dash_active_timer = math.max(0, player.abilities.dash_active_timer - dt)
	player.abilities.dash_cooldown_timer = math.max(0, player.abilities.dash_cooldown_timer - dt)
	player.abilities.coyote_timer = math.max(0, player.abilities.coyote_timer - dt)
	player.abilities.jump_buffer_timer = math.max(0, player.abilities.jump_buffer_timer - dt)
	player.abilities.wall_run_cooldown_timer = math.max(
		0,
		player.abilities.wall_run_cooldown_timer - dt,
	)
	player.abilities.sand_hop_cooldown_timer = math.max(
		0,
		player.abilities.sand_hop_cooldown_timer - dt,
	)
	player.abilities.dash_dir =
		game.input.axis.x != 0 ? math.sign(game.input.axis.x) : player.abilities.dash_dir

	if game.input.is_pressed[.JUMP] do player.abilities.jump_buffer_timer = PLAYER_JUMP_BUFFER_DURATION

	state_update(player, dt)
	physics_update(player, dt)
	sensor_update(player)
}

player_sand_footprint_update :: proc(world: ^engine.Sand_World, player: ^Player) {
	if player.state != .Grounded do return
	if !player.sensor.on_sand do return
	if math.abs(player.body.vel.x) < engine.SAND_FOOTPRINT_MIN_SPEED do return
	if math.abs(player.body.pos.x - player.abilities.footprint_last_x) < engine.SAND_FOOTPRINT_STRIDE do return

	player.abilities.footprint_last_x = player.body.pos.x
	player.abilities.footprint_side = !player.abilities.footprint_side

	foot_gy := int(player.body.pos.y / engine.SAND_CELL_SIZE) - 1
	foot_gx := int(player.body.pos.x / engine.SAND_CELL_SIZE)

	if !engine.sand_in_bounds(world, foot_gx, foot_gy) do return
	idx := foot_gy * world.width + foot_gx
	foot_mat := world.cells[idx].material
	if foot_mat != .Sand && foot_mat != .Wet_Sand do return

	push_dx: int = player.body.vel.x > 0 ? -1 : 1
	saved := world.cells[idx]
	world.cells[idx] = engine.Sand_Cell{}

	chunk := engine.sand_chunk_at(world, foot_gx, foot_gy)
	if chunk != nil && chunk.active_count > 0 do chunk.active_count -= 1
	engine.sand_chunk_mark_dirty(world, foot_gx, foot_gy)

	// Pile removed sand beside the footprint (no wake for persistence)
	placed := false
	for try_dx in ([2]int{push_dx, -push_dx}) {
		nx := foot_gx + try_dx
		if !engine.sand_in_bounds(world, nx, foot_gy) do continue
		if world.cells[foot_gy * world.width + nx].material != .Empty do continue
		world.cells[foot_gy * world.width + nx] = saved
		world.cells[foot_gy * world.width + nx].sleep_counter = engine.SAND_SLEEP_THRESHOLD
		n_chunk := engine.sand_chunk_at(world, nx, foot_gy)
		if n_chunk != nil do n_chunk.active_count += 1
		engine.sand_chunk_mark_dirty(world, nx, foot_gy)
		placed = true
		break
	}

	// Restore cell if no neighbor had room (mass conservation)
	if !placed {
		world.cells[idx] = saved
		if chunk != nil do chunk.active_count += 1
	}
}

// --- Helpers ---

@(private = "file")
move_factor :: proc(p: ^Player, sand_penalty, water_penalty: f32) -> f32 {
	sand := max(1.0 - p.sensor.sand_immersion * sand_penalty, 0)
	water := max(1.0 - p.sensor.water_immersion * water_penalty, 0)
	return max(sand * water, 0)
}

@(private = "file")
wall_jump :: proc(p: ^Player) -> bool {
	if p.abilities.jump_buffer_timer <= 0 || !p.sensor.on_side_wall do return false
	p.body.pos.x -= p.sensor.on_side_wall_dir * EPS
	p.body.vel.y = PLAYER_WALL_JUMP_VERTICAL_MULT * PLAYER_JUMP_FORCE
	p.body.vel.x = -p.sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
	if p.sensor.on_sand_wall {
		p.body.vel.y *= engine.SAND_WALL_JUMP_MULT
		p.body.vel.x *= engine.SAND_WALL_JUMP_MULT
	}
	p.abilities.jump_buffer_timer = 0
	wall_pos := [2]f32 {
		p.body.pos.x + p.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
		p.body.pos.y + PLAYER_SIZE / 2,
	}
	player_graphics_dust_emit(
		&game.dust,
		wall_pos,
		{-p.sensor.on_side_wall_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
		int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
	)
	player_graphics_step_emit(&game.steps, wall_pos)
	return true
}

// --- State Machine ---

@(private = "file")
state_update :: proc(p: ^Player, dt: f32) {
	next: Maybe(Player_State)
	switch p.state {
	case .Grounded:
		next = update_grounded(p, dt)
	case .Airborne:
		next = update_airborne(p, dt)
	case .Dashing:
		next = update_dashing(p, dt)
	case .Dropping:
		next = update_dropping(p, dt)
	case .Sand_Swim, .Swimming:
		next = update_submerged(p, dt)
	case .Wall_Slide:
		next = update_wall_slide(p, dt)
	case .Wall_Run_Vertical:
		next = update_wall_run_vertical(p, dt)
	case .Wall_Run_Horizontal:
		next = update_wall_run_horizontal(p, dt)
	}
	if n, ok := next.?; ok do state_transition(p, n)
}

@(private = "file")
state_transition :: proc(p: ^Player, next: Player_State) {
	if p.state == next do return
	#partial switch p.state {
	case .Wall_Run_Vertical:
		p.abilities.wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
	}
	p.previous_state = p.state
	p.state = next
	#partial switch next {
	case .Grounded:
		enter_grounded(p)
	case .Dashing:
		enter_dashing(p)
	case .Sand_Swim, .Swimming:
		enter_submerged(p)
	case .Wall_Run_Vertical:
		enter_wall_run_vertical(p)
	case .Wall_Run_Horizontal:
		enter_wall_run_horizontal(p)
	}
}

// --- Enter Handlers ---

@(private = "file")
enter_grounded :: proc(p: ^Player) {
	p.impact_pending = math.abs(p.body.vel.y)
	p.abilities.wall_run_cooldown_timer = 0
	p.abilities.wall_run_used = false
	if p.sensor.on_ground {
		p.body.pos.y = p.sensor.on_ground_snap_y
	}
	player_graphics_dust_emit(&game.dust, p.body.pos, {0, 0}, int(PLAYER_PARTICLE_DUST_LAND_COUNT))
}

@(private = "file")
enter_dashing :: proc(p: ^Player) {
	p.abilities.dash_active_timer = PLAYER_DASH_DURATION
	p.abilities.dash_cooldown_timer = PLAYER_DASH_COOLDOWN
	player_graphics_dust_emit(
		&game.dust,
		p.body.pos + {0, PLAYER_SIZE / 2},
		{-p.abilities.dash_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
		int(PLAYER_PARTICLE_DUST_DASH_COUNT),
	)
}

@(private = "file")
enter_submerged :: proc(p: ^Player) {
	p.abilities.wall_run_cooldown_timer = 0
	p.abilities.wall_run_used = false
}

@(private = "file")
enter_wall_run_vertical :: proc(p: ^Player) {
	p.abilities.wall_run_used = true
	p.abilities.wall_run_timer = 0
}

@(private = "file")
enter_wall_run_horizontal :: proc(p: ^Player) {
	p.abilities.wall_run_used = true
	p.abilities.wall_run_timer = 0
	p.abilities.wall_run_dir = p.abilities.dash_dir
}

// --- Update Handlers ---

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
@(private = "file")
update_grounded :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	prev := p.graphics.run_anim_timer
	if math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD {
		p.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * dt
		if math.floor(prev / math.PI) != math.floor(p.graphics.run_anim_timer / math.PI) {
			player_graphics_dust_emit(
				&game.dust,
				p.body.pos,
				{0, 0},
				int(PLAYER_PARTICLE_DUST_STEP_COUNT),
			)
		}
	} else do p.graphics.run_anim_timer = 0

	speed_factor: f32 = 1.0
	if p.sensor.on_slope {
		uphill := math.sign(game.input.axis.x) == p.sensor.on_slope_dir
		speed_factor = PLAYER_SLOPE_UPHILL_FACTOR if uphill else PLAYER_SLOPE_DOWNHILL_FACTOR
	}
	p.body.vel.x = math.lerp(
		p.body.vel.x,
		game.input.axis.x *
		PLAYER_RUN_SPEED *
		speed_factor *
		move_factor(p, engine.SAND_MOVE_PENALTY, engine.WATER_MOVE_PENALTY),
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	p.body.vel.y = -engine.SAND_SINK_SPEED if p.sensor.on_sand else 0
	p.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION

	if p.sensor.sand_immersion > engine.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
	if p.sensor.water_immersion > engine.WATER_SWIM_ENTER_THRESHOLD do return .Swimming

	if p.sensor.on_platform &&
	   game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD &&
	   p.abilities.jump_buffer_timer > 0 {
		p.body.pos.y -= PLAYER_DROP_NUDGE
		p.abilities.jump_buffer_timer = 0
		p.abilities.coyote_timer = 0
		return .Dropping
	}

	if p.abilities.jump_buffer_timer > 0 {
		sand_jump := 1.0 - p.sensor.sand_immersion * engine.SAND_JUMP_PENALTY
		water_jump := 1.0 - p.sensor.water_immersion * engine.WATER_JUMP_PENALTY
		jump_factor := max(sand_jump * water_jump, 0)
		if jump_factor > 0 {
			p.body.vel.y = PLAYER_JUMP_FORCE * jump_factor
			p.abilities.jump_buffer_timer = 0
			p.abilities.coyote_timer = 0
			player_graphics_dust_emit(
				&game.dust,
				p.body.pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MAX},
				int(PLAYER_PARTICLE_DUST_JUMP_COUNT),
			)
			return .Airborne
		}
		p.abilities.jump_buffer_timer = 0
	}

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if p.sensor.on_side_wall && game.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if p.sensor.on_back_wall && game.input.is_down[.WALL_RUN] && math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD && !(p.sensor.on_slope && math.sign(game.input.axis.x) == p.sensor.on_slope_dir) do return .Wall_Run_Horizontal
	if p.sensor.on_back_wall && game.input.is_down[.WALL_RUN] do return .Wall_Run_Vertical
	if !p.sensor.on_ground do return .Airborne

	return nil
}

// Airborne — in the air under gravity. Supports coyote jump and wall jump.
@(private = "file")
update_airborne :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	apply_movement(p, dt)

	if p.abilities.jump_buffer_timer > 0 && p.abilities.coyote_timer > 0 {
		p.body.vel.y = PLAYER_JUMP_FORCE
		p.abilities.jump_buffer_timer = 0
		p.abilities.coyote_timer = 0
	}

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if p.sensor.on_ground && p.body.vel.y <= 0 {
		p.body.vel.y = 0
		return .Grounded
	}
	if p.sensor.sand_immersion > engine.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
	if p.sensor.water_immersion > engine.WATER_SWIM_ENTER_THRESHOLD do return .Swimming

	if p.sensor.on_back_wall {
		if game.input.is_down[.WALL_RUN] && math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD && !(p.sensor.on_slope && math.sign(game.input.axis.x) == p.sensor.on_slope_dir) && !p.abilities.wall_run_used && p.abilities.wall_run_cooldown_timer <= 0 do return .Wall_Run_Horizontal
		if game.input.is_down[.WALL_RUN] && p.abilities.wall_run_cooldown_timer <= 0 && !p.abilities.wall_run_used do return .Wall_Run_Vertical
		if game.input.is_down[.SLIDE] do return .Wall_Slide
	}

	if p.sensor.on_side_wall {
		if math.abs(p.body.vel.x) > PLAYER_IMPACT_THRESHOLD do player_graphics_trigger_impact(p, math.abs(p.body.vel.x), {1, 0})
		if p.abilities.jump_buffer_timer > 0 {
			if p.sensor.on_side_wall {
				offset_x := -EPS * p.sensor.on_side_wall_dir
				p.body.pos.x = p.sensor.on_side_wall_snap_x + offset_x
				p.body.vel.y = PLAYER_WALL_JUMP_VERTICAL_MULT * PLAYER_JUMP_FORCE
				p.body.vel.x = -p.sensor.on_side_wall_dir * PLAYER_WALL_JUMP_FORCE
				wall_pos := [2]f32 {
					p.body.pos.x + p.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
					p.body.pos.y + PLAYER_SIZE / 2,
				}
				player_graphics_dust_emit(
					&game.dust,
					wall_pos,
					{-p.sensor.on_side_wall_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
					int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
				)
			}
			p.abilities.jump_buffer_timer = 0
			return nil
		}
		if game.input.is_down[.WALL_RUN] && p.abilities.wall_run_cooldown_timer <= 0 && !p.abilities.wall_run_used && p.body.vel.y > 0 do return .Wall_Run_Vertical
		if game.input.is_down[.SLIDE] do return .Wall_Slide
	}

	return nil
}

// Dashing — direction-locked burst. Zero gravity. Slope-aware.
@(private = "file")
update_dashing :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	if p.abilities.dash_active_timer <= 0 {
		apply_movement(p, dt)
		if p.sensor.sand_immersion > engine.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
		if p.sensor.water_immersion > engine.WATER_SWIM_ENTER_THRESHOLD do return .Swimming
		if p.sensor.on_ground do return .Grounded
		if p.sensor.on_side_wall {
			if math.abs(p.body.vel.x) > PLAYER_IMPACT_THRESHOLD do player_graphics_trigger_impact(p, math.abs(p.body.vel.x), {1, 0})
			if game.input.is_down[.WALL_RUN] && p.abilities.wall_run_cooldown_timer <= 0 && !p.abilities.wall_run_used && p.body.vel.y > 0 do return .Wall_Run_Vertical
			if game.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	speed :=
		PLAYER_DASH_SPEED * move_factor(p, engine.SAND_MOVE_PENALTY, engine.WATER_MOVE_PENALTY)
	if p.sensor.on_slope {
		uphill := p.abilities.dash_dir == p.sensor.on_slope_dir
		if uphill {
			speed *= PLAYER_SLOPE_UPHILL_FACTOR
			SLOPE_45 :: 0.70710678
			p.body.vel.x = p.abilities.dash_dir * speed * SLOPE_45
			p.body.vel.y = speed * SLOPE_45
		} else {
			p.body.vel.x = p.abilities.dash_dir * speed
			p.body.vel.y = EPS
		}
	} else {
		p.body.vel.x = p.abilities.dash_dir * speed
		if p.body.vel.y <= 0 do p.body.vel.y = 0
	}
	return nil
}

// Dropping — falling through a one-way platform.
@(private = "file")
update_dropping :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	apply_movement(p, dt)
	if p.sensor.in_platform do return nil
	return .Airborne
}

// Submerged — shared handler for Sand_Swim and Swimming.
@(private = "file")
update_submerged :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	in_sand := p.state == .Sand_Swim

	move_penalty := engine.SAND_SWIM_MOVE_PENALTY if in_sand else engine.WATER_MOVE_PENALTY
	lerp_speed := engine.SAND_SWIM_LERP_SPEED if in_sand else PLAYER_MOVE_LERP_SPEED
	up_speed := engine.SAND_SWIM_UP_SPEED if in_sand else engine.WATER_SWIM_UP_SPEED
	down_speed := engine.SAND_SWIM_DOWN_SPEED if in_sand else engine.WATER_SWIM_DOWN_SPEED
	idle_speed := -engine.SAND_SWIM_SINK_SPEED if in_sand else engine.WATER_SWIM_FLOAT_SPEED
	grav_mult := engine.SAND_SWIM_GRAVITY_MULT if in_sand else engine.WATER_SWIM_GRAVITY_MULT
	damping_k := engine.SAND_SWIM_DAMPING if in_sand else engine.WATER_SWIM_DAMPING
	surface_threshold :=
		engine.SAND_SWIM_SURFACE_THRESHOLD if in_sand else engine.WATER_SWIM_SURFACE_THRESHOLD
	exit_threshold :=
		engine.SAND_SWIM_EXIT_THRESHOLD if in_sand else engine.WATER_SWIM_EXIT_THRESHOLD
	jump_force := engine.SAND_SWIM_JUMP_FORCE if in_sand else engine.WATER_SWIM_JUMP_FORCE
	immersion := p.sensor.sand_immersion if in_sand else p.sensor.water_immersion

	// Horizontal movement
	move_fac := max(1.0 - immersion * move_penalty, 0)
	p.body.vel.x = math.lerp(
		p.body.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * move_fac,
		lerp_speed * dt,
	)

	// Vertical: up input, down input, or passive float/sink
	if game.input.axis.y > PLAYER_INPUT_AXIS_THRESHOLD {
		p.body.vel.y = math.lerp(p.body.vel.y, up_speed, lerp_speed * dt)
	} else if game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD {
		p.body.vel.y = math.lerp(p.body.vel.y, -down_speed, lerp_speed * dt)
	} else {
		p.body.vel.y = math.lerp(p.body.vel.y, idle_speed, lerp_speed * dt)
	}

	// Reduced gravity + velocity damping
	p.body.vel.y -= grav_mult * GRAVITY * dt
	p.body.vel *= math.exp(-damping_k * dt)

	// Sand hop — spam jump when deep to boil upward (sand only)
	if in_sand &&
	   game.input.is_pressed[.JUMP] &&
	   p.sensor.sand_immersion >= engine.SAND_SWIM_SURFACE_THRESHOLD &&
	   p.abilities.sand_hop_cooldown_timer <= 0 {
		p.body.vel.y = engine.SAND_SWIM_HOP_FORCE
		p.abilities.sand_hop_cooldown_timer = engine.SAND_SWIM_HOP_COOLDOWN
		engine.sand_particles_emit(
			&game.sand_particles,
			p.body.pos + {0, PLAYER_SIZE},
			PLAYER_SIZE / 2,
			math.PI / 2,
			math.PI / 3,
			{0, 0},
			engine.SAND_COLOR,
			int(engine.SAND_SWIM_HOP_PARTICLE_COUNT),
		)
	}

	// Jump out near surface
	if p.abilities.jump_buffer_timer > 0 && immersion < surface_threshold {
		p.body.vel.y = jump_force
		p.abilities.jump_buffer_timer = 0
		if in_sand {
			engine.sand_particles_emit(
				&game.sand_particles,
				p.body.pos + {0, PLAYER_SIZE},
				PLAYER_SIZE / 2,
				math.PI / 2,
				math.PI / 3,
				{0, abs(p.body.vel.y) * engine.SAND_IMPACT_PARTICLE_VEL_BIAS},
				engine.SAND_COLOR,
				int(engine.SAND_SWIM_JUMP_PARTICLE_COUNT),
			)
		}
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if p.sensor.on_ground && immersion < exit_threshold do return .Grounded
	if immersion < exit_threshold do return .Airborne

	return nil
}

// Wall_Slide — sliding down a wall. Clamps fall speed, dampens X.
@(private = "file")
update_wall_slide :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	apply_movement(p, dt)

	if p.body.vel.y < 0 do p.body.vel.y = math.max(p.body.vel.y, -PLAYER_WALL_SLIDE_SPEED)
	p.body.vel.x = math.lerp(p.body.vel.x, 0, PLAYER_MOVE_LERP_SPEED * dt)

	if p.sensor.on_side_wall {
		p.body.pos.x = p.sensor.on_side_wall_snap_x
		p.body.vel.x = 0
	}

	if p.sensor.on_sand_wall do engine.sand_wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if wall_jump(p) do return .Airborne

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if p.sensor.on_ground do return .Grounded
	if !p.sensor.on_side_wall && !p.sensor.on_back_wall do return .Airborne
	if p.sensor.on_back_wall && !p.sensor.on_side_wall && !game.input.is_down[.SLIDE] do return .Airborne

	// Sparse dust from hand position while sliding
	if rand.float32() < PLAYER_PARTICLE_DUST_WALL_SLIDE_CHANCE {
		if p.sensor.on_side_wall {
			hand_pos := [2]f32 {
				p.body.pos.x + p.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
				p.body.pos.y + PLAYER_SIZE,
			}
			player_graphics_dust_emit(
				&game.dust,
				hand_pos,
				{0, PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT),
			)
		} else if p.sensor.on_back_wall {
			hand_pos := [2]f32{p.body.pos.x - PLAYER_SIZE / 2, p.body.pos.y + PLAYER_SIZE}
			player_graphics_dust_emit(
				&game.dust,
				hand_pos,
				{0, PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT),
			)
		}
	}

	return nil
}

// Wall_Run_Vertical — running up a wall with exponential speed decay.
@(private = "file")
update_wall_run_vertical :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	p.abilities.wall_run_timer += dt

	speed := PLAYER_WALL_RUN_VERTICAL_SPEED
	decay := PLAYER_WALL_RUN_VERTICAL_DECAY
	combined := move_factor(p, engine.SAND_WALL_RUN_PENALTY, engine.WATER_MOVE_PENALTY)
	p.body.vel.y = speed * combined * math.exp(-decay * p.abilities.wall_run_timer)
	p.body.vel.x = 0

	if p.sensor.on_side_wall {
		p.body.vel.x = math.lerp(
			p.body.vel.x,
			game.input.axis.x * PLAYER_RUN_SPEED,
			PLAYER_MOVE_LERP_SPEED * dt,
		)
		p.body.pos.x = p.sensor.on_side_wall_snap_x
	}

	if p.sensor.on_sand_wall do engine.sand_wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if wall_jump(p) do return .Airborne
	if p.abilities.jump_buffer_timer > 0 {
		// Back wall: straight-up jump
		p.body.vel.y = PLAYER_JUMP_FORCE
		if p.sensor.on_sand_wall do p.body.vel.y *= engine.SAND_WALL_JUMP_MULT
		p.abilities.jump_buffer_timer = 0
		player_graphics_dust_emit(
			&game.dust,
			p.body.pos,
			{0, -PLAYER_PARTICLE_DUST_SPEED_MAX},
			int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
		)
		player_graphics_step_emit(&game.steps, p.body.pos)
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing

	if p.body.vel.y <= PLAYER_WALL_SLIDE_SPEED {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if p.sensor.on_side_wall do p.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !game.input.is_down[.WALL_RUN] {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if p.sensor.on_side_wall do p.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	if !p.sensor.on_side_wall && !p.sensor.on_back_wall do return .Airborne
	if p.sensor.on_ground && p.body.vel.y <= 0 do return .Grounded

	// Footstep-synced dust while running on wall
	prev := p.graphics.run_anim_timer
	p.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * dt
	if math.floor(prev / math.PI) != math.floor(p.graphics.run_anim_timer / math.PI) {
		if p.sensor.on_side_wall {
			wall_pos := [2]f32 {
				p.body.pos.x + p.sensor.on_side_wall_dir * PLAYER_SIZE / 2,
				p.body.pos.y,
			}
			player_graphics_dust_emit(
				&game.dust,
				wall_pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_graphics_step_emit(&game.steps, wall_pos)
		} else {
			player_graphics_dust_emit(
				&game.dust,
				p.body.pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_graphics_step_emit(&game.steps, p.body.pos)
		}
	}

	return nil
}

// Wall_Run_Horizontal — horizontal parabolic arc along a back wall.
@(private = "file")
update_wall_run_horizontal :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	p.abilities.wall_run_timer += dt
	combined := move_factor(p, engine.SAND_WALL_RUN_PENALTY, engine.WATER_MOVE_PENALTY)
	p.body.vel.x = PLAYER_WALL_RUN_HORIZONTAL_SPEED * p.abilities.wall_run_dir * combined
	p.body.vel.y =
		PLAYER_WALL_RUN_HORIZONTAL_LIFT * combined -
		GRAVITY * PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT * p.abilities.wall_run_timer

	if p.sensor.on_sand_wall do engine.sand_wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if p.abilities.jump_buffer_timer > 0 {
		p.body.vel.y = PLAYER_JUMP_FORCE
		if p.sensor.on_sand_wall do p.body.vel.y *= engine.SAND_WALL_JUMP_MULT
		p.abilities.jump_buffer_timer = 0
		player_graphics_step_emit(&game.steps, p.body.pos)
		return .Airborne
	}

	if game.input.is_pressed[.DASH] && p.abilities.dash_cooldown_timer <= 0 do return .Dashing
	if !p.sensor.on_back_wall do return .Airborne
	if p.sensor.on_ground && p.body.vel.y <= 0 do return .Grounded
	if p.body.vel.y < -PLAYER_WALL_SLIDE_SPEED do return .Airborne
	if p.sensor.on_side_wall do return .Airborne

	if !game.input.is_down[.WALL_RUN] {
		if game.input.is_down[.SLIDE] do return .Wall_Slide
		if p.sensor.on_side_wall do p.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION
		return .Airborne
	}

	// Footstep-synced dust trailing behind run direction
	prev := p.graphics.run_anim_timer
	fall_speed := max(f32(0), -p.body.vel.y)
	bob_mult := 1.0 + fall_speed / PLAYER_WALL_RUN_HORIZONTAL_LIFT
	p.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * bob_mult * dt
	if math.floor(prev / math.PI) != math.floor(p.graphics.run_anim_timer / math.PI) {
		player_graphics_dust_emit(
			&game.dust,
			p.body.pos,
			{-p.abilities.wall_run_dir * PLAYER_PARTICLE_DUST_SPEED_MIN, 0},
			int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
		)
		player_graphics_step_emit(&game.steps, p.body.pos)
	}

	return nil
}

// --- Physics ---

@(private = "file")
apply_movement :: proc(p: ^Player, dt: f32) {
	p.body.vel.x = math.lerp(
		p.body.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * move_factor(p, engine.SAND_MOVE_PENALTY, 0),
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	gravity_mult: f32 =
		PLAYER_FAST_FALL_MULT if p.body.vel.y > 0 && !game.input.is_down[.JUMP] else 1.0
	p.body.vel.y -= gravity_mult * GRAVITY * dt
}

@(private = "file")
physics_update :: proc(player: ^Player, dt: f32) {
	player.body.flags = {}
	if player.state == .Dropping do player.body.flags += {.Dropping}
	if player.state == .Grounded do player.body.flags += {.Grounded}

	geom := engine.Physics_Static_Geometry {
		ground    = game.level.ground_colliders[:],
		ceiling   = game.level.ceiling_colliders[:],
		walls     = game.level.side_wall_colliders[:],
		platforms = game.level.platform_colliders[:],
		slopes    = game.level.slope_colliders[:],
	}

	cfg := engine.Physics_Solve_Config {
		step_height = PLAYER_STEP_HEIGHT,
		sweep_skin  = PLAYER_SWEEP_SKIN,
		slope_snap  = PLAYER_SLOPE_SNAP,
		eps         = EPS,
	}

	engine.physics_solve(&player.body, geom, cfg, dt)
}

// --- Sensor ---

@(private = "file")
sensor_update :: proc(player: ^Player) {
	in_platform: bool
	on_back_wall: bool
	on_ground: bool
	on_ground_snap_y: f32 = -1e18
	on_platform: bool
	on_sand: bool
	on_side_wall: bool
	on_side_wall_dir: f32
	on_side_wall_snap_x: f32
	on_sand_wall: bool
	on_slope: bool
	on_slope_dir: f32

	debug_ground_hit: engine.Physics_Raycast_Hit
	debug_slope_hit: engine.Physics_Raycast_Hit
	debug_platform_hit: engine.Physics_Raycast_Hit
	debug_wall_left_hit: engine.Physics_Raycast_Hit
	debug_wall_right_hit: engine.Physics_Raycast_Hit

	for c in game.level.ground_colliders {
		if on_ground do break
		origin := player.body.pos + {0, EPS}
		max_dist := PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.physics_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			debug_ground_hit = hit
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
		}
	}

	for c in game.level.side_wall_colliders {
		if on_side_wall do break

		hit_l := engine.Physics_Raycast_Hit{}
		{
			origin := player.body.pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_l = engine.physics_raycast_rect(origin, 0, -1, max_dist, c, cross_half_size)
		}
		if hit_l.hit {
			on_side_wall = true
			on_side_wall_dir = -1
			on_side_wall_snap_x = hit_l.point.x + PLAYER_SIZE / 2
			debug_wall_left_hit = hit_l
		}

		hit_r := engine.Physics_Raycast_Hit{}
		{
			origin := player.body.pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			max_dist := PLAYER_CHECK_SIDE_WALL_EPS + EPS
			cross_half_size := PLAYER_SIZE / 4
			hit_r = engine.physics_raycast_rect(origin, 0, 1, max_dist, c, cross_half_size)
		}
		if hit_r.hit {
			on_side_wall = true
			on_side_wall_dir = 1
			on_side_wall_snap_x = hit_r.point.x - PLAYER_SIZE / 2
			debug_wall_right_hit = hit_r
		}
	}

	// Sand wall detection (only if no solid side wall)
	if !on_side_wall {
		found, dir, snap_x := engine.sand_detect_wall(
			&game.sand_world,
			player.body.pos,
			PLAYER_SIZE,
		)
		if found {
			on_side_wall = true
			on_side_wall_dir = dir
			on_side_wall_snap_x = snap_x
			on_sand_wall = true
		}
	}

	for c in game.level.slope_colliders {
		origin := player.body.pos + {0, PLAYER_STEP_HEIGHT}
		max_dist := PLAYER_STEP_HEIGHT + PLAYER_CHECK_GROUND_EPS + EPS
		cross_half_size := PLAYER_SIZE / 2
		hit := engine.physics_raycast_slope(origin, 1, -1, max_dist, c, cross_half_size)
		if hit.hit {
			on_ground = true
			on_slope = true
			on_slope_dir = 1 if c.kind == .Right || c.kind == .Ceil_Left else -1
			debug_slope_hit = hit
			if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			break
		}
	}

	rect := engine.physics_body_rect(&player.body)

	for c in game.level.platform_colliders {
		if in_platform && on_platform do break
		if !in_platform && engine.physics_rect_overlap(c, rect) {
			in_platform = true
		}
		if !on_platform && player.body.vel.y <= 0 {
			origin := player.body.pos + {0, EPS}
			max_dist := PLAYER_CHECK_GROUND_EPS + EPS
			cross_half_size := PLAYER_SIZE / 2
			hit := engine.physics_raycast_rect(origin, 1, -1, max_dist, c, cross_half_size)
			if hit.hit {
				on_ground = true
				on_platform = true
				debug_platform_hit = hit
				if hit.point.y > on_ground_snap_y do on_ground_snap_y = hit.point.y
			}
		}
	}

	for c in game.level.back_wall_colliders {
		overlap := engine.physics_rect_overlap(c, rect)
		if overlap {
			on_back_wall = true
			break
		}
	}

	// Sand ground detection (only if no solid/slope/platform ground)
	if !on_ground {
		if engine.SAND_SURFACE_SMOOTH > 0 {
			surface_y, found := engine.sand_surface_query(
				&game.sand_world,
				player.body.pos.x,
				player.body.pos.y,
			)
			if found {
				dist := player.body.pos.y - surface_y
				if dist >= -PLAYER_STEP_HEIGHT && dist <= PLAYER_CHECK_GROUND_EPS {
					on_ground = true
					on_sand = true
					if surface_y > on_ground_snap_y do on_ground_snap_y = surface_y
				}
			}
		} else {
			foot_gx0 := int((player.body.pos.x - PLAYER_SIZE / 2) / engine.SAND_CELL_SIZE)
			foot_gx1 := int((player.body.pos.x + PLAYER_SIZE / 2) / engine.SAND_CELL_SIZE)
			foot_gy := int(player.body.pos.y / engine.SAND_CELL_SIZE)
			for check_gy in ([2]int{foot_gy, foot_gy - 1}) {
				if on_sand do break
				for gx in foot_gx0 ..= foot_gx1 {
					if !engine.sand_in_bounds(&game.sand_world, gx, check_gy) do continue
					sensor_mat := engine.sand_get(&game.sand_world, gx, check_gy).material
					if sensor_mat != .Sand && sensor_mat != .Wet_Sand do continue
					surface_y := f32(check_gy + 1) * engine.SAND_CELL_SIZE
					dist := player.body.pos.y - surface_y
					if dist >= -PLAYER_STEP_HEIGHT && dist <= PLAYER_CHECK_GROUND_EPS {
						on_ground = true
						on_sand = true
						if surface_y > on_ground_snap_y do on_ground_snap_y = surface_y
					}
				}
			}
		}
	}

	player.sensor.in_platform = in_platform
	player.sensor.on_back_wall = on_back_wall
	player.sensor.on_ground = on_ground
	player.sensor.on_ground_snap_y = on_ground_snap_y
	player.sensor.on_platform = on_platform
	player.sensor.on_sand = on_sand
	player.sensor.sand_immersion = engine.sand_compute_immersion(
		&game.sand_world,
		player.body.pos,
		PLAYER_SIZE,
		{.Sand, .Wet_Sand},
	)
	water_immersion := engine.sand_compute_immersion(
		&game.sand_world,
		player.body.pos,
		PLAYER_SIZE,
		{.Water},
	)
	player.sensor.on_water = water_immersion > 0
	player.sensor.water_immersion = water_immersion
	player.sensor.on_side_wall = on_side_wall
	player.sensor.on_side_wall_dir = on_side_wall_dir
	player.sensor.on_side_wall_snap_x = on_side_wall_snap_x
	player.sensor.on_sand_wall = on_sand_wall
	player.sensor.on_slope = on_slope
	player.sensor.on_slope_dir = on_slope_dir
	player.sensor.debug_ground_hit = debug_ground_hit
	player.sensor.debug_slope_hit = debug_slope_hit
	player.sensor.debug_platform_hit = debug_platform_hit
	player.sensor.debug_wall_left_hit = debug_wall_left_hit
	player.sensor.debug_wall_right_hit = debug_wall_right_hit
}
