package game

import engine "../engine"
import "core:fmt"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl3"

// --- Rendering ---

player_graphics_render :: proc(player: ^Player) {
	vel_px := player.body.vel * PPM
	size_px: f32 = PLAYER_SIZE * PPM

	// -- Visual Deformation (layered) --
	h_scale: f32 = 1.0
	w_scale: f32 = 1.0

	// Layer 1: Velocity squash/stretch
	h_scale +=
		math.abs(vel_px.y) * PLAYER_VEL_DEFORM_Y_H - math.abs(vel_px.x) * PLAYER_VEL_DEFORM_X_H
	w_scale +=
		-math.abs(vel_px.y) * PLAYER_VEL_DEFORM_Y_W + math.abs(vel_px.x) * PLAYER_VEL_DEFORM_X_W

	// Layer 2: Input look
	look := player.graphics.visual_look
	h_scale += look.y * PLAYER_LOOK_DEFORM
	w_scale -= look.y * PLAYER_LOOK_DEFORM * PLAYER_LOOK_DEFORM_W_Y
	w_scale += math.abs(look.x) * PLAYER_LOOK_DEFORM * PLAYER_LOOK_DEFORM_W_X

	// Layer 3: Run bob
	run_osc := math.sin(player.graphics.run_anim_timer) * PLAYER_RUN_BOB_AMPLITUDE
	h_scale += run_osc
	w_scale -= run_osc * PLAYER_BOB_DEFORM_W

	// Layer 4: Impact bounce
	if player.graphics.impact_strength > 0 {
		t := player.graphics.impact_timer
		envelope := player.graphics.impact_strength * math.exp(-PLAYER_IMPACT_DECAY * t)
		osc := envelope * math.cos(PLAYER_IMPACT_FREQ * t) * PLAYER_IMPACT_SCALE
		if envelope * PLAYER_IMPACT_SCALE < PLAYER_IMPACT_CUTOFF {
			player.graphics.impact_strength = 0
		}
		h_scale -= osc * player.graphics.impact_axis.y
		w_scale += osc * player.graphics.impact_axis.y * PLAYER_IMPACT_DEFORM_W_Y
		w_scale -= osc * player.graphics.impact_axis.x
		h_scale += osc * player.graphics.impact_axis.x * PLAYER_IMPACT_DEFORM_H_X
	}

	h_scale = math.clamp(h_scale, PLAYER_DEFORM_MIN, PLAYER_DEFORM_MAX)
	w_scale = math.clamp(w_scale, PLAYER_DEFORM_MIN, PLAYER_DEFORM_MAX)

	h := size_px * h_scale
	w := size_px * w_scale

	// -- Player (deformed size, bottom-center anchored)
	// Convert deformed pixel size back to world units for game_world_to_screen
	w_world := w / PPM
	h_world := h / PPM
	player_bl := [2]f32{player.body.pos.x - w_world / 2, player.body.pos.y}
	rect_p := game_world_to_screen(player_bl, {w_world, h_world})

	sdl.SetRenderDrawColor(
		game.win.renderer,
		PLAYER_COLOR.r,
		PLAYER_COLOR.g,
		PLAYER_COLOR.b,
		PLAYER_COLOR.a,
	)
	sdl.RenderFillRect(game.win.renderer, &rect_p)
}

player_graphics_trigger_impact :: proc(player: ^Player, impact_speed: f32, axis: [2]f32) {
	strength := math.clamp(impact_speed / PLAYER_JUMP_FORCE, 0, 1)
	remaining :=
		player.graphics.impact_strength *
		math.exp(-PLAYER_IMPACT_DECAY * player.graphics.impact_timer)
	if strength > remaining {
		player.graphics.impact_timer = 0
		player.graphics.impact_strength = strength
		player.graphics.impact_axis = axis
	}
}

// --- Particles ---

player_graphics_dust_emit :: proc(
	pool: ^engine.Particle_Pool,
	pos: [2]f32,
	vel_base: [2]f32,
	count: int,
) {
	for _ in 0 ..< count {
		angle := rand.float32() * 2 * math.PI
		speed :=
			PLAYER_PARTICLE_DUST_SPEED_MIN +
			rand.float32() * (PLAYER_PARTICLE_DUST_SPEED_MAX - PLAYER_PARTICLE_DUST_SPEED_MIN)
		spread := [2]f32{math.cos(angle) * speed, math.sin(angle) * speed}
		lifetime :=
			PLAYER_PARTICLE_DUST_LIFETIME_MIN +
			rand.float32() *
				(PLAYER_PARTICLE_DUST_LIFETIME_MAX - PLAYER_PARTICLE_DUST_LIFETIME_MIN)
		engine.particle_pool_emit(
			pool,
			engine.Particle {
				pos = pos,
				vel = vel_base + spread,
				lifetime = lifetime,
				age = 0,
				size = PLAYER_PARTICLE_DUST_SIZE,
				color = PLAYER_PARTICLE_DUST_COLOR,
			},
		)
	}
}

player_graphics_dust_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
	for i in 0 ..< pool.count {
		pool.items[i].vel.y -= PLAYER_PARTICLE_DUST_GRAVITY * dt
		pool.items[i].vel *= 1.0 - PLAYER_PARTICLE_DUST_FRICTION * dt
		pool.items[i].pos += pool.items[i].vel * dt
	}
}

player_graphics_step_emit :: proc(pool: ^engine.Particle_Pool, pos: [2]f32) {
	engine.particle_pool_emit(
		pool,
		engine.Particle {
			pos = pos,
			vel = {0, 0},
			lifetime = PLAYER_PARTICLE_STEP_LIFETIME,
			age = 0,
			size = PLAYER_PARTICLE_STEP_SIZE,
			color = PLAYER_PARTICLE_STEP_COLOR,
		},
	)
}

player_graphics_step_update :: proc(pool: ^engine.Particle_Pool, dt: f32) {
	engine.particle_pool_update(pool, dt)
}

player_graphics_particle_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(255 * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := game_world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}

player_graphics_sand_particle_render :: proc(pool: ^engine.Particle_Pool) {
	for i in 0 ..< pool.count {
		p := &pool.items[i]
		t := p.age / p.lifetime
		alpha := u8(f32(p.color.a) * (1.0 - t))
		sdl.SetRenderDrawColor(game.win.renderer, p.color.r, p.color.g, p.color.b, alpha)
		rect := game_world_to_screen(p.pos - {p.size / 2, 0}, {p.size, p.size})
		sdl.RenderFillRect(game.win.renderer, &rect)
	}
}

// --- Sand Dust ---

@(private = "file")
sand_dust_counter: u8

player_graphics_sand_dust_tick :: proc(player: ^Player) {
	sand_dust_counter += 1
	if sand_dust_counter < engine.SAND_DUST_INTERVAL do return
	sand_dust_counter = 0

	if !player.sensor.on_sand do return
	if player.state != .Grounded do return
	if math.abs(player.body.vel.x) < engine.SAND_DUST_MIN_SPEED do return

	emit_x := player.body.pos.x - math.sign(player.body.vel.x) * PLAYER_SIZE / 4
	emit_pos := [2]f32{emit_x, player.body.pos.y}
	vel := [2]f32 {
		-math.sign(player.body.vel.x) *
		engine.SAND_DUST_SPEED *
		(engine.SAND_DUST_SPEED_RAND_MIN +
				(1.0 - engine.SAND_DUST_SPEED_RAND_MIN) * rand.float32()),
		engine.SAND_DUST_LIFT * rand.float32(),
	}
	dust_color := [4]u8 {
		min(engine.SAND_COLOR.r + engine.SAND_DUST_LIGHTEN, 255),
		min(engine.SAND_COLOR.g + engine.SAND_DUST_LIGHTEN, 255),
		min(engine.SAND_COLOR.b + engine.SAND_DUST_LIGHTEN, 255),
		engine.SAND_COLOR.a,
	}
	engine.particle_pool_emit(
		&game.dust,
		engine.Particle {
			pos = emit_pos,
			vel = vel,
			lifetime = engine.SAND_DUST_LIFETIME *
			(engine.SAND_DUST_LIFETIME_RAND_MIN +
					(1.0 - engine.SAND_DUST_LIFETIME_RAND_MIN) * rand.float32()),
			age = 0,
			size = engine.SAND_DUST_SIZE,
			color = dust_color,
		},
	)
}

// --- Debug ---

player_graphics_debug :: proc(player: ^Player) {
	player_top := game_world_to_screen_point({player.body.pos.x, player.body.pos.y + PLAYER_SIZE})
	player_subti := player_top - {0, DEBUG_TEXT_STATE_GAP}
	player_title := player_subti - {0, DEBUG_TEXT_LINE_H}
	debug_text_center(player_title.x, player_title.y, fmt.ctprintf("%v", player.state))
	debug_text_center(
		player_subti.x,
		player_subti.y,
		fmt.ctprintf("%v", player.previous_state),
		DEBUG_COLOR_STATE_MUTED,
	)
}

player_graphics_physics_debug :: proc(player: ^Player) {
	if game.debug == .PLAYER || game.debug == .ALL {
		rect := engine.physics_body_rect(&player.body)
		debug_collider_rect(rect)
		debug_point(player.body.pos, DEBUG_COLOR_PLAYER)

		player_mid_y: [2]f32 = {player.body.pos.x, player.body.pos.y + PLAYER_SIZE / 2}
		player_vel := player.body.vel * PPM * DEBUG_VEL_SCALE
		player_dash_dir: [2]f32 = {player.abilities.dash_dir * DEBUG_FACING_LENGTH, 0}
		debug_vector(player_mid_y, player_vel, DEBUG_COLOR_VELOCITY)
		debug_vector(player_mid_y, player_dash_dir, DEBUG_COLOR_FACING_DIR)
	}
}

player_graphics_sensor_debug :: proc(player: ^Player, screen_pos: [2]f32) {
	if game.debug == .PLAYER || game.debug == .ALL {
		// Ground ray (green)
		{
			origin := player.body.pos + {0, EPS}
			end_point := origin - {0, PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(origin, end_point, player.sensor.debug_ground_hit, DEBUG_COLOR_RAY_GROUND)
		}
		// Slope ray (light green, starts higher, longer range)
		{
			origin := player.body.pos + {0, PLAYER_STEP_HEIGHT}
			end_point := origin - {0, PLAYER_STEP_HEIGHT + PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(origin, end_point, player.sensor.debug_slope_hit, DEBUG_COLOR_RAY_SLOPE)
		}
		// Platform ray (blue)
		{
			origin := player.body.pos + {0, EPS}
			end_point := origin - {0, PLAYER_CHECK_GROUND_EPS + EPS}
			debug_ray(
				origin,
				end_point,
				player.sensor.debug_platform_hit,
				DEBUG_COLOR_RAY_PLATFORM,
			)
		}
		// Wall left ray (orange)
		{
			origin := player.body.pos + {-PLAYER_SIZE / 2 + EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin - {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			debug_ray(origin, end_point, player.sensor.debug_wall_left_hit, DEBUG_COLOR_RAY_WALL)
		}
		// Wall right ray (orange)
		{
			origin := player.body.pos + {PLAYER_SIZE / 2 - EPS, PLAYER_SIZE / 2 + PLAYER_SIZE / 4}
			end_point := origin + {PLAYER_CHECK_SIDE_WALL_EPS + EPS, 0}
			debug_ray(origin, end_point, player.sensor.debug_wall_right_hit, DEBUG_COLOR_RAY_WALL)
		}
		// Back wall indicator (dark cyan outline when overlapping)
		if player.sensor.on_back_wall {
			debug_collider_rect(
				engine.physics_body_rect(&player.body),
				DEBUG_COLOR_COLLIDER_BACK_WALL,
			)
		}
	}

	Label_Value :: struct {
		label, value: cstring,
	}

	entries := [?]Label_Value {
		{"in_platform:", fmt.ctprintf("%v", player.sensor.in_platform)},
		{"on_back_wall:", fmt.ctprintf("%v", player.sensor.on_back_wall)},
		{"on_ground:", fmt.ctprintf("%v", player.sensor.on_ground)},
		{"on_platform:", fmt.ctprintf("%v", player.sensor.on_platform)},
		{"on_sand:", fmt.ctprintf("%v", player.sensor.on_sand)},
		{"sand_immersion:", fmt.ctprintf("%.2f", player.sensor.sand_immersion)},
		{"on_water:", fmt.ctprintf("%v", player.sensor.on_water)},
		{"water_immersion:", fmt.ctprintf("%.2f", player.sensor.water_immersion)},
		{"on_side_wall:", fmt.ctprintf("%v", player.sensor.on_side_wall)},
		{"on_side_wall_dir:", fmt.ctprintf("%.0f", player.sensor.on_side_wall_dir)},
		{"on_side_wall_snap_x:", fmt.ctprintf("%.2f", player.sensor.on_side_wall_snap_x)},
		{"on_sand_wall:", fmt.ctprintf("%v", player.sensor.on_sand_wall)},
		{"on_slope:", fmt.ctprintf("%v", player.sensor.on_slope)},
		{"on_slope_dir:", fmt.ctprintf("%.0f", player.sensor.on_slope_dir)},
	}
	for entry, i in entries {
		debug_value_with_label(
			DEBUG_TEXT_MARGIN_X,
			2 * DEBUG_TEXT_LINE_H + DEBUG_TEXT_MARGIN_Y + f32(i) * DEBUG_TEXT_LINE_H,
			entry.label,
			entry.value,
		)
	}
}
