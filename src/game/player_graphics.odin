package game

import "core:math"
import sdl "vendor:sdl3"

player_color :: proc() -> [3]u8 {
	return PLAYER_COLOR[player_fsm.current]
}

player_render :: proc() {
	vel_px := game.player_vel * PPM
	size_px: f32 = PLAYER_SIZE * PPM

	// -- Visual Deformation (layered) --
	h_scale: f32 = 1.0
	w_scale: f32 = 1.0

	// Layer 1: Velocity squash/stretch
	h_scale += math.abs(vel_px.y) * 0.001 - math.abs(vel_px.x) * 0.00025
	w_scale += -math.abs(vel_px.y) * 0.0005 + math.abs(vel_px.x) * 0.0005

	// Layer 2: Input look
	look := game.player_visual_look
	h_scale += look.y * PLAYER_LOOK_DEFORM
	w_scale -= look.y * PLAYER_LOOK_DEFORM * 0.5
	w_scale += math.abs(look.x) * PLAYER_LOOK_DEFORM * 0.3

	// Layer 3: Run bob
	run_osc := math.sin(game.player_run_anim_timer) * PLAYER_RUN_BOB_AMPLITUDE
	h_scale += run_osc
	w_scale -= run_osc * 0.5

	// Layer 4: Impact bounce
	if game.player_impact_strength > 0 {
		t := game.player_impact_timer
		envelope := game.player_impact_strength * math.exp(-PLAYER_IMPACT_DECAY * t)
		osc := envelope * math.cos(PLAYER_IMPACT_FREQ * t) * PLAYER_IMPACT_SCALE
		if envelope * PLAYER_IMPACT_SCALE < 0.005 {
			game.player_impact_strength = 0
		}
		h_scale -= osc * game.player_impact_axis.y
		w_scale += osc * game.player_impact_axis.y * 0.5
		w_scale -= osc * game.player_impact_axis.x
		h_scale += osc * game.player_impact_axis.x * 0.5
	}

	h_scale = math.clamp(h_scale, 0.5, 1.5)
	w_scale = math.clamp(w_scale, 0.5, 1.5)

	h := size_px * h_scale
	w := size_px * w_scale

	// -- Player (deformed size, bottom-center anchored)
	// Convert deformed pixel size back to world units for world_to_screen
	w_world := w / PPM
	h_world := h / PPM
	player_bl := [2]f32{game.player_pos.x - w_world / 2, game.player_pos.y}
	rect_p := world_to_screen(player_bl, {w_world, h_world})

	color := player_color()
	sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, 255)
	sdl.RenderFillRect(game.win.renderer, &rect_p)
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
