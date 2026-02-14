package game

import engine "../engine"
import "core:fmt"
import "core:math"

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

Player_Transform :: struct {
	pos:            [2]f32,
	vel:            [2]f32,
	impact_pending: f32, // landing speed, consumed by sand_player_interact
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

Player :: struct {
	transform: Player_Transform,
	collider:  engine.Collider_Rect,
	abilities: Player_Abilities,
	graphics:  Player_Graphics,
	fsm:       engine.FSM(Player, Player_State),
	sensor:    Player_Sensor,
}

player_sync_collider :: proc(player: ^Player) {
	player.collider.pos.x = player.transform.pos.x
	player.collider.pos.y = player.transform.pos.y + PLAYER_SIZE / 2
	player.collider.size = {PLAYER_SIZE, PLAYER_SIZE}
}

player_init :: proc(player: ^Player) {
	player_fsm_airborne_init(player)
	player_fsm_dashing_init(player)
	player_fsm_dropping_init(player)
	player_fsm_grounded_init(player)
	player_fsm_sand_swim_init(player)
	player_fsm_swimming_init(player)
	player_fsm_wall_run_horizontal_init(player)
	player_fsm_wall_run_vertical_init(player)
	player_fsm_wall_slide_init(player)
	engine.fsm_init(&player.fsm, player, Player_State.Grounded)

	player_sync_collider(player)
	player_sensor_update(player)
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

	engine.fsm_update(&player.fsm, dt)
	player_physics_update(player, dt)
	player_sensor_update(player)
}

player_debug :: proc(player: ^Player) {
	player_top := game_world_to_screen_point(
		{player.transform.pos.x, player.transform.pos.y + PLAYER_SIZE},
	)
	player_subti := player_top - {0, DEBUG_TEXT_STATE_GAP}
	player_title := player_subti - {0, DEBUG_TEXT_LINE_H}
	debug_text_center(player_title.x, player_title.y, fmt.ctprintf("%v", player.fsm.current))
	debug_text_center(
		player_subti.x,
		player_subti.y,
		fmt.ctprintf("%v", player.fsm.previous),
		DEBUG_COLOR_STATE_MUTED,
	)
}
