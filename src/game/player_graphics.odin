package game

import "core:math"
import sdl "vendor:sdl3"

player_render :: proc(player: ^Player) {
	vel_px := player.transform.vel * PPM
	size_px: f32 = PLAYER_SIZE * PPM

	// -- Visual Deformation (layered) --
	h_scale: f32 = 1.0
	w_scale: f32 = 1.0

	// Layer 1: Velocity squash/stretch
	h_scale += math.abs(vel_px.y) * 0.001 - math.abs(vel_px.x) * 0.00025
	w_scale += -math.abs(vel_px.y) * 0.0005 + math.abs(vel_px.x) * 0.0005

	// Layer 2: Input look
	look := player.graphics.visual_look
	h_scale += look.y * PLAYER_LOOK_DEFORM
	w_scale -= look.y * PLAYER_LOOK_DEFORM * 0.5
	w_scale += math.abs(look.x) * PLAYER_LOOK_DEFORM * 0.3

	// Layer 3: Run bob
	run_osc := math.sin(player.graphics.run_anim_timer) * PLAYER_RUN_BOB_AMPLITUDE
	h_scale += run_osc
	w_scale -= run_osc * 0.5

	// Layer 4: Impact bounce
	if player.graphics.impact_strength > 0 {
		t := player.graphics.impact_timer
		envelope := player.graphics.impact_strength * math.exp(-PLAYER_IMPACT_DECAY * t)
		osc := envelope * math.cos(PLAYER_IMPACT_FREQ * t) * PLAYER_IMPACT_SCALE
		if envelope * PLAYER_IMPACT_SCALE < 0.005 {
			player.graphics.impact_strength = 0
		}
		h_scale -= osc * player.graphics.impact_axis.y
		w_scale += osc * player.graphics.impact_axis.y * 0.5
		w_scale -= osc * player.graphics.impact_axis.x
		h_scale += osc * player.graphics.impact_axis.x * 0.5
	}

	h_scale = math.clamp(h_scale, 0.5, 1.5)
	w_scale = math.clamp(w_scale, 0.5, 1.5)

	h := size_px * h_scale
	w := size_px * w_scale

	// -- Player (deformed size, bottom-center anchored)
	// Convert deformed pixel size back to world units for world_to_screen
	w_world := w / PPM
	h_world := h / PPM
	player_bl := [2]f32{player.transform.pos.x - w_world / 2, player.transform.pos.y}
	rect_p := world_to_screen(player_bl, {w_world, h_world})

	sdl.SetRenderDrawColor(
		game.win.renderer,
		PLAYER_COLOR.r,
		PLAYER_COLOR.g,
		PLAYER_COLOR.b,
		PLAYER_COLOR.a,
	)
	sdl.RenderFillRect(game.win.renderer, &rect_p)
}

player_trigger_impact :: proc(player: ^Player, impact_speed: f32, axis: [2]f32) {
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
