package game

import sand "../sand"
import "core:math"
import "core:math/rand"

player_state_update :: proc(p: ^Player, dt: f32) {
	next: Maybe(Player_State)
	switch p.state {
	case .Grounded:
		next = player_state_update_grounded(p, dt)
	case .Airborne:
		next = player_state_update_airborne(p, dt)
	case .Dashing:
		next = player_state_update_dashing(p, dt)
	case .Dropping:
		next = player_state_update_dropping(p, dt)
	case .Sand_Swim, .Swimming:
		next = player_state_update_submerged(p, dt)
	case .Wall_Slide:
		next = player_state_update_wall_slide(p, dt)
	case .Wall_Run_Vertical:
		next = player_state_update_wall_run_vertical(p, dt)
	case .Wall_Run_Horizontal:
		next = player_state_update_wall_run_horizontal(p, dt)
	}
	if n, ok := next.?; ok do player_state_transition(p, n)
}

player_state_transition :: proc(p: ^Player, next: Player_State) {
	if p.state == next do return
	#partial switch p.state {
	case .Wall_Run_Vertical:
		p.abilities.wall_run_cooldown_timer = PLAYER_WALL_RUN_COOLDOWN
	}
	p.previous_state = p.state
	p.state = next
	#partial switch next {
	case .Grounded:
		player_state_enter_grounded(p)
	case .Dashing:
		player_state_enter_dashing(p)
	case .Sand_Swim, .Swimming:
		player_state_enter_submerged(p)
	case .Wall_Run_Vertical:
		player_state_enter_wall_run_vertical(p)
	case .Wall_Run_Horizontal:
		player_state_enter_wall_run_horizontal(p)
	}
}

// --- Enter handlers ---

@(private = "file")
player_state_enter_grounded :: proc(p: ^Player) {
	p.impact_pending = math.abs(p.body.vel.y)
	p.abilities.wall_run_cooldown_timer = 0
	p.abilities.wall_run_used = false
	if p.sensor.on_ground {
		p.body.pos.y = p.sensor.on_ground_snap_y
	}
	player_particles_dust_emit(
		&game.dust,
		p.body.pos,
		{0, 0},
		int(PLAYER_PARTICLE_DUST_LAND_COUNT),
	)
}

@(private = "file")
player_state_enter_dashing :: proc(p: ^Player) {
	p.abilities.dash_active_timer = PLAYER_DASH_DURATION
	p.abilities.dash_cooldown_timer = PLAYER_DASH_COOLDOWN
	player_particles_dust_emit(
		&game.dust,
		p.body.pos + {0, PLAYER_SIZE / 2},
		{-p.abilities.dash_dir * PLAYER_PARTICLE_DUST_SPEED_MAX, 0},
		int(PLAYER_PARTICLE_DUST_DASH_COUNT),
	)
}

@(private = "file")
player_state_enter_submerged :: proc(p: ^Player) {
	p.abilities.wall_run_cooldown_timer = 0
	p.abilities.wall_run_used = false
}

@(private = "file")
player_state_enter_wall_run_vertical :: proc(p: ^Player) {
	p.abilities.wall_run_used = true
	p.abilities.wall_run_timer = 0
}

@(private = "file")
player_state_enter_wall_run_horizontal :: proc(p: ^Player) {
	p.abilities.wall_run_used = true
	p.abilities.wall_run_timer = 0
	p.abilities.wall_run_dir = p.abilities.dash_dir
}

// --- Update handlers ---

// Grounded — on solid ground or platform. Zeroes Y velocity, resets cooldowns.
@(private = "file")
player_state_update_grounded :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	prev := p.graphics.run_anim_timer
	if math.abs(game.input.axis.x) > PLAYER_INPUT_AXIS_THRESHOLD {
		p.graphics.run_anim_timer += PLAYER_RUN_BOB_SPEED * dt
		if math.floor(prev / math.PI) != math.floor(p.graphics.run_anim_timer / math.PI) {
			player_particles_dust_emit(
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
		player_move_factor(p, sand.SAND_MOVE_PENALTY, sand.WATER_MOVE_PENALTY),
		PLAYER_MOVE_LERP_SPEED * dt,
	)
	p.body.vel.y = -sand.SAND_SINK_SPEED if p.sensor.on_sand else 0
	p.abilities.coyote_timer = PLAYER_COYOTE_TIME_DURATION

	if p.sensor.sand_immersion > sand.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
	if p.sensor.water_immersion > sand.WATER_SWIM_ENTER_THRESHOLD do return .Swimming

	if p.sensor.on_platform &&
	   game.input.axis.y < -PLAYER_INPUT_AXIS_THRESHOLD &&
	   p.abilities.jump_buffer_timer > 0 {
		p.body.pos.y -= PLAYER_DROP_NUDGE
		p.abilities.jump_buffer_timer = 0
		p.abilities.coyote_timer = 0
		return .Dropping
	}

	if p.abilities.jump_buffer_timer > 0 {
		sand_jump := 1.0 - p.sensor.sand_immersion * sand.SAND_JUMP_PENALTY
		water_jump := 1.0 - p.sensor.water_immersion * sand.WATER_JUMP_PENALTY
		jump_factor := max(sand_jump * water_jump, 0)
		if jump_factor > 0 {
			p.body.vel.y = PLAYER_JUMP_FORCE * jump_factor
			p.abilities.jump_buffer_timer = 0
			p.abilities.coyote_timer = 0
			player_particles_dust_emit(
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
player_state_update_airborne :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(p, dt)

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
	if p.sensor.sand_immersion > sand.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
	if p.sensor.water_immersion > sand.WATER_SWIM_ENTER_THRESHOLD do return .Swimming

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
				player_particles_dust_emit(
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
player_state_update_dashing :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	if p.abilities.dash_active_timer <= 0 {
		player_physics_apply_movement(p, dt)
		if p.sensor.sand_immersion > sand.SAND_SWIM_ENTER_THRESHOLD do return .Sand_Swim
		if p.sensor.water_immersion > sand.WATER_SWIM_ENTER_THRESHOLD do return .Swimming
		if p.sensor.on_ground do return .Grounded
		if p.sensor.on_side_wall {
			if math.abs(p.body.vel.x) > PLAYER_IMPACT_THRESHOLD do player_graphics_trigger_impact(p, math.abs(p.body.vel.x), {1, 0})
			if game.input.is_down[.WALL_RUN] && p.abilities.wall_run_cooldown_timer <= 0 && !p.abilities.wall_run_used && p.body.vel.y > 0 do return .Wall_Run_Vertical
			if game.input.is_down[.SLIDE] do return .Wall_Slide
		}
		return .Airborne
	}

	speed :=
		PLAYER_DASH_SPEED * player_move_factor(p, sand.SAND_MOVE_PENALTY, sand.WATER_MOVE_PENALTY)
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
player_state_update_dropping :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(p, dt)
	if p.sensor.in_platform do return nil
	return .Airborne
}

// Submerged — shared handler for Sand_Swim and Swimming.
@(private = "file")
player_state_update_submerged :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	in_sand := p.state == .Sand_Swim

	move_penalty := sand.SAND_SWIM_MOVE_PENALTY if in_sand else sand.WATER_MOVE_PENALTY
	lerp_speed := sand.SAND_SWIM_LERP_SPEED if in_sand else PLAYER_MOVE_LERP_SPEED
	up_speed := sand.SAND_SWIM_UP_SPEED if in_sand else sand.WATER_SWIM_UP_SPEED
	down_speed := sand.SAND_SWIM_DOWN_SPEED if in_sand else sand.WATER_SWIM_DOWN_SPEED
	idle_speed := -sand.SAND_SWIM_SINK_SPEED if in_sand else sand.WATER_SWIM_FLOAT_SPEED
	grav_mult := sand.SAND_SWIM_GRAVITY_MULT if in_sand else sand.WATER_SWIM_GRAVITY_MULT
	damping_k := sand.SAND_SWIM_DAMPING if in_sand else sand.WATER_SWIM_DAMPING
	surface_threshold :=
		sand.SAND_SWIM_SURFACE_THRESHOLD if in_sand else sand.WATER_SWIM_SURFACE_THRESHOLD
	exit_threshold := sand.SAND_SWIM_EXIT_THRESHOLD if in_sand else sand.WATER_SWIM_EXIT_THRESHOLD
	jump_force := sand.SAND_SWIM_JUMP_FORCE if in_sand else sand.WATER_SWIM_JUMP_FORCE
	immersion := p.sensor.sand_immersion if in_sand else p.sensor.water_immersion

	// Horizontal movement
	move_factor := max(1.0 - immersion * move_penalty, 0)
	p.body.vel.x = math.lerp(
		p.body.vel.x,
		game.input.axis.x * PLAYER_RUN_SPEED * move_factor,
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
	   p.sensor.sand_immersion >= sand.SAND_SWIM_SURFACE_THRESHOLD &&
	   p.abilities.sand_hop_cooldown_timer <= 0 {
		p.body.vel.y = sand.SAND_SWIM_HOP_FORCE
		p.abilities.sand_hop_cooldown_timer = sand.SAND_SWIM_HOP_COOLDOWN
		sand.particles_emit(
			&game.sand_particles,
			p.body.pos + {0, PLAYER_SIZE},
			PLAYER_SIZE / 2,
			math.PI / 2,
			math.PI / 3,
			{0, 0},
			sand.SAND_COLOR,
			int(sand.SAND_SWIM_HOP_PARTICLE_COUNT),
		)
	}

	// Jump out near surface
	if p.abilities.jump_buffer_timer > 0 && immersion < surface_threshold {
		p.body.vel.y = jump_force
		p.abilities.jump_buffer_timer = 0
		if in_sand {
			sand.particles_emit(
				&game.sand_particles,
				p.body.pos + {0, PLAYER_SIZE},
				PLAYER_SIZE / 2,
				math.PI / 2,
				math.PI / 3,
				{0, abs(p.body.vel.y) * sand.SAND_IMPACT_PARTICLE_VEL_BIAS},
				sand.SAND_COLOR,
				int(sand.SAND_SWIM_JUMP_PARTICLE_COUNT),
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
player_state_update_wall_slide :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	player_physics_apply_movement(p, dt)

	if p.body.vel.y < 0 do p.body.vel.y = math.max(p.body.vel.y, -PLAYER_WALL_SLIDE_SPEED)
	p.body.vel.x = math.lerp(p.body.vel.x, 0, PLAYER_MOVE_LERP_SPEED * dt)

	if p.sensor.on_side_wall {
		p.body.pos.x = p.sensor.on_side_wall_snap_x
		p.body.vel.x = 0
	}

	if p.sensor.on_sand_wall do sand.wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if player_wall_jump(p) do return .Airborne

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
			player_particles_dust_emit(
				&game.dust,
				hand_pos,
				{0, PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT),
			)
		} else if p.sensor.on_back_wall {
			hand_pos := [2]f32{p.body.pos.x - PLAYER_SIZE / 2, p.body.pos.y + PLAYER_SIZE}
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

// Wall_Run_Vertical — running up a wall with exponential speed decay.
@(private = "file")
player_state_update_wall_run_vertical :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	p.abilities.wall_run_timer += dt

	speed := PLAYER_WALL_RUN_VERTICAL_SPEED
	decay := PLAYER_WALL_RUN_VERTICAL_DECAY
	combined := player_move_factor(p, sand.SAND_WALL_RUN_PENALTY, sand.WATER_MOVE_PENALTY)
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

	if p.sensor.on_sand_wall do sand.wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if player_wall_jump(p) do return .Airborne
	if p.abilities.jump_buffer_timer > 0 {
		// Back wall: straight-up jump
		p.body.vel.y = PLAYER_JUMP_FORCE
		if p.sensor.on_sand_wall do p.body.vel.y *= sand.SAND_WALL_JUMP_MULT
		p.abilities.jump_buffer_timer = 0
		player_particles_dust_emit(
			&game.dust,
			p.body.pos,
			{0, -PLAYER_PARTICLE_DUST_SPEED_MAX},
			int(PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT),
		)
		player_particles_step_emit(&game.steps, p.body.pos)
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
			player_particles_dust_emit(
				&game.dust,
				wall_pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_particles_step_emit(&game.steps, wall_pos)
		} else {
			player_particles_dust_emit(
				&game.dust,
				p.body.pos,
				{0, -PLAYER_PARTICLE_DUST_SPEED_MIN},
				int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
			)
			player_particles_step_emit(&game.steps, p.body.pos)
		}
	}

	return nil
}

// Wall_Run_Horizontal — horizontal parabolic arc along a back wall.
@(private = "file")
player_state_update_wall_run_horizontal :: proc(p: ^Player, dt: f32) -> Maybe(Player_State) {
	p.abilities.wall_run_timer += dt
	combined := player_move_factor(p, sand.SAND_WALL_RUN_PENALTY, sand.WATER_MOVE_PENALTY)
	p.body.vel.x = PLAYER_WALL_RUN_HORIZONTAL_SPEED * p.abilities.wall_run_dir * combined
	p.body.vel.y =
		PLAYER_WALL_RUN_HORIZONTAL_LIFT * combined -
		GRAVITY * PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT * p.abilities.wall_run_timer

	if p.sensor.on_sand_wall do sand.wall_erode(&game.sand_world, p.body.pos, PLAYER_SIZE, p.sensor.on_side_wall_dir)

	if p.abilities.jump_buffer_timer > 0 {
		p.body.vel.y = PLAYER_JUMP_FORCE
		if p.sensor.on_sand_wall do p.body.vel.y *= sand.SAND_WALL_JUMP_MULT
		p.abilities.jump_buffer_timer = 0
		player_particles_step_emit(&game.steps, p.body.pos)
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
		player_particles_dust_emit(
			&game.dust,
			p.body.pos,
			{-p.abilities.wall_run_dir * PLAYER_PARTICLE_DUST_SPEED_MIN, 0},
			int(PLAYER_PARTICLE_DUST_WALL_RUN_COUNT),
		)
		player_particles_step_emit(&game.steps, p.body.pos)
	}

	return nil
}
