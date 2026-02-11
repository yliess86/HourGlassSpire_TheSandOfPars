// AUTO-GENERATED from assets/game.ini — do not edit manually
package game

import engine "../engine"
import "core:fmt"

// [engine]
WINDOW_TITLE: string
WINDOW_SCALE: u8
LOGICAL_H: f32
FPS: u8
FIXED_STEPS: u8

// [physics]
PPM: f32
GRAVITY: f32
EPS: f32
TILE_SIZE: f32

// [camera]
CAMERA_FOLLOW_SPEED_MIN: f32
CAMERA_FOLLOW_SPEED_MAX: f32
CAMERA_DEAD_ZONE: f32
CAMERA_BOUNDARY_ZONE: f32

// [level]
LEVEL_COLOR_BG: [4]u8
LEVEL_COLOR_TILE_SOLID: [4]u8
LEVEL_COLOR_TILE_BACK_WALL: [4]u8
LEVEL_COLOR_TILE_WINDOW: [4]u8

// [player]
PLAYER_COLOR: [4]u8
PLAYER_SIZE: f32
PLAYER_CHECK_GROUND_EPS: f32
PLAYER_CHECK_SIDE_WALL_EPS: f32
PLAYER_COYOTE_TIME_DURATION: f32
PLAYER_DROP_NUDGE: f32
PLAYER_FAST_FALL_MULT: f32
PLAYER_INPUT_AXIS_THRESHOLD: f32
PLAYER_MOVE_LERP_SPEED: f32

// [player_run]
PLAYER_RUN_SPEED: f32
PLAYER_RUN_SPEED_THRESHOLD: f32
PLAYER_RUN_BOB_AMPLITUDE: f32
PLAYER_RUN_BOB_SPEED: f32

// [player_jump]
PLAYER_JUMP_FORCE: f32
PLAYER_JUMP_BUFFER_DURATION: f32

// [player_dash]
PLAYER_DASH_SPEED: f32
PLAYER_DASH_DURATION: f32
PLAYER_DASH_COOLDOWN: f32

// [player_wall]
PLAYER_WALL_JUMP_EPS: f32
PLAYER_WALL_JUMP_FORCE: f32
PLAYER_WALL_JUMP_VERTICAL_MULT: f32
PLAYER_WALL_SLIDE_SPEED: f32
PLAYER_WALL_RUN_COOLDOWN: f32
PLAYER_WALL_RUN_VERTICAL_SPEED: f32
PLAYER_WALL_RUN_VERTICAL_DECAY: f32
PLAYER_WALL_RUN_HORIZONTAL_SPEED: f32
PLAYER_WALL_RUN_HORIZONTAL_LIFT: f32
PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT: f32

// [player_slopes]
PLAYER_SLOPE_SNAP: f32
PLAYER_SLOPE_UPHILL_FACTOR: f32
PLAYER_SLOPE_DOWNHILL_FACTOR: f32
PLAYER_STEP_HEIGHT: f32

// [player_graphics]
PLAYER_LOOK_DEFORM: f32
PLAYER_LOOK_SMOOTH: f32
PLAYER_IMPACT_DECAY: f32
PLAYER_IMPACT_FREQ: f32
PLAYER_IMPACT_SCALE: f32
PLAYER_IMPACT_THRESHOLD: f32

// [player_particles]
PLAYER_PARTICLE_DUST_SIZE: f32
PLAYER_PARTICLE_DUST_GRAVITY: f32
PLAYER_PARTICLE_DUST_LIFETIME_MIN: f32
PLAYER_PARTICLE_DUST_LIFETIME_MAX: f32
PLAYER_PARTICLE_DUST_SPEED_MIN: f32
PLAYER_PARTICLE_DUST_SPEED_MAX: f32
PLAYER_PARTICLE_DUST_FRICTION: f32
PLAYER_PARTICLE_STEP_SIZE: f32
PLAYER_PARTICLE_STEP_LIFETIME: f32

// [player_particle_colors]
PLAYER_PARTICLE_DUST_COLOR: [4]u8
PLAYER_PARTICLE_STEP_COLOR: [4]u8

// [input]
INPUT_AXIS_DEADZONE: f32
INPUT_KB_MOVE_UP: string
INPUT_KB_MOVE_DOWN: string
INPUT_KB_MOVE_LEFT: string
INPUT_KB_MOVE_RIGHT: string
INPUT_KB_JUMP: string
INPUT_KB_DASH: string
INPUT_KB_WALL_RUN: string
INPUT_KB_SLIDE: string
INPUT_KB_DEBUG: string
INPUT_KB_RELOAD: string
INPUT_KB_QUIT: string
INPUT_GP_MOVE_UP: string
INPUT_GP_MOVE_DOWN: string
INPUT_GP_MOVE_LEFT: string
INPUT_GP_MOVE_RIGHT: string
INPUT_GP_JUMP: string
INPUT_GP_DASH: string
INPUT_GP_WALL_RUN: string
INPUT_GP_SLIDE: string
INPUT_GP_DEBUG: string
INPUT_GP_QUIT: string

// [debug_colors]
DEBUG_COLOR_COLLIDER: [4]u8
DEBUG_COLOR_COLLIDER_BACK_WALL: [4]u8
DEBUG_COLOR_COLLIDER_CEILING: [4]u8
DEBUG_COLOR_COLLIDER_SIDE_WALL: [4]u8
DEBUG_COLOR_COLLIDER_PLATFORM: [4]u8
DEBUG_COLOR_FACING_DIR: [4]u8
DEBUG_COLOR_PLAYER: [4]u8
DEBUG_COLOR_STATE: [4]u8
DEBUG_COLOR_STATE_MUTED: [4]u8
DEBUG_COLOR_RAY_GROUND: [4]u8
DEBUG_COLOR_RAY_SLOPE: [4]u8
DEBUG_COLOR_RAY_PLATFORM: [4]u8
DEBUG_COLOR_RAY_WALL: [4]u8
DEBUG_COLOR_RAY_HIT_POINT: [4]u8
DEBUG_COLOR_RAY_MISS: [4]u8
DEBUG_COLOR_VELOCITY: [4]u8
DEBUG_COLOR_GRID: [4]u8
DEBUG_COLOR_CAMERA_ZONE: [4]u8

// [debug]
DEBUG_GRID_ALPHA: u8
DEBUG_CROSS_HALF: f32
DEBUG_FACING_LENGTH: f32
DEBUG_TEXT_CHAR_W: f32
DEBUG_TEXT_LINE_H: f32
DEBUG_TEXT_MARGIN_X: f32
DEBUG_TEXT_MARGIN_Y: f32
DEBUG_TEXT_STATE_GAP: f32
DEBUG_VEL_SCALE: f32

config_apply :: proc() {
	if val, ok := engine.config_get_string(&game_config, "WINDOW_TITLE"); ok do WINDOW_TITLE = val
	if val, ok := engine.config_get_u8(&game_config, "WINDOW_SCALE"); ok do WINDOW_SCALE = val
	if val, ok := engine.config_get_f32(&game_config, "LOGICAL_H"); ok do LOGICAL_H = val
	if val, ok := engine.config_get_u8(&game_config, "FPS"); ok do FPS = val
	if val, ok := engine.config_get_u8(&game_config, "FIXED_STEPS"); ok do FIXED_STEPS = val
	if val, ok := engine.config_get_f32(&game_config, "PPM"); ok do PPM = val
	if val, ok := engine.config_get_f32(&game_config, "GRAVITY"); ok do GRAVITY = val
	if val, ok := engine.config_get_f32(&game_config, "EPS"); ok do EPS = val
	if val, ok := engine.config_get_f32(&game_config, "TILE_SIZE"); ok do TILE_SIZE = val
	if val, ok := engine.config_get_f32(&game_config, "CAMERA_FOLLOW_SPEED_MIN"); ok do CAMERA_FOLLOW_SPEED_MIN = val
	if val, ok := engine.config_get_f32(&game_config, "CAMERA_FOLLOW_SPEED_MAX"); ok do CAMERA_FOLLOW_SPEED_MAX = val
	if val, ok := engine.config_get_f32(&game_config, "CAMERA_DEAD_ZONE"); ok do CAMERA_DEAD_ZONE = val
	if val, ok := engine.config_get_f32(&game_config, "CAMERA_BOUNDARY_ZONE"); ok do CAMERA_BOUNDARY_ZONE = val
	if val, ok := engine.config_get_rgba(&game_config, "LEVEL_COLOR_BG"); ok do LEVEL_COLOR_BG = val
	if val, ok := engine.config_get_rgba(&game_config, "LEVEL_COLOR_TILE_SOLID"); ok do LEVEL_COLOR_TILE_SOLID = val
	if val, ok := engine.config_get_rgba(&game_config, "LEVEL_COLOR_TILE_BACK_WALL"); ok do LEVEL_COLOR_TILE_BACK_WALL = val
	if val, ok := engine.config_get_rgba(&game_config, "LEVEL_COLOR_TILE_WINDOW"); ok do LEVEL_COLOR_TILE_WINDOW = val
	if val, ok := engine.config_get_rgba(&game_config, "PLAYER_COLOR"); ok do PLAYER_COLOR = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_SIZE"); ok do PLAYER_SIZE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_CHECK_GROUND_EPS"); ok do PLAYER_CHECK_GROUND_EPS = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_CHECK_SIDE_WALL_EPS"); ok do PLAYER_CHECK_SIDE_WALL_EPS = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_COYOTE_TIME_DURATION"); ok do PLAYER_COYOTE_TIME_DURATION = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_DROP_NUDGE"); ok do PLAYER_DROP_NUDGE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_FAST_FALL_MULT"); ok do PLAYER_FAST_FALL_MULT = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_INPUT_AXIS_THRESHOLD"); ok do PLAYER_INPUT_AXIS_THRESHOLD = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_MOVE_LERP_SPEED"); ok do PLAYER_MOVE_LERP_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_RUN_SPEED"); ok do PLAYER_RUN_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_RUN_SPEED_THRESHOLD"); ok do PLAYER_RUN_SPEED_THRESHOLD = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_RUN_BOB_AMPLITUDE"); ok do PLAYER_RUN_BOB_AMPLITUDE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_RUN_BOB_SPEED"); ok do PLAYER_RUN_BOB_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_JUMP_FORCE"); ok do PLAYER_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_JUMP_BUFFER_DURATION"); ok do PLAYER_JUMP_BUFFER_DURATION = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_DASH_SPEED"); ok do PLAYER_DASH_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_DASH_DURATION"); ok do PLAYER_DASH_DURATION = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_DASH_COOLDOWN"); ok do PLAYER_DASH_COOLDOWN = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_JUMP_EPS"); ok do PLAYER_WALL_JUMP_EPS = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_JUMP_FORCE"); ok do PLAYER_WALL_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_JUMP_VERTICAL_MULT"); ok do PLAYER_WALL_JUMP_VERTICAL_MULT = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_SLIDE_SPEED"); ok do PLAYER_WALL_SLIDE_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_COOLDOWN"); ok do PLAYER_WALL_RUN_COOLDOWN = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_VERTICAL_SPEED"); ok do PLAYER_WALL_RUN_VERTICAL_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_VERTICAL_DECAY"); ok do PLAYER_WALL_RUN_VERTICAL_DECAY = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_HORIZONTAL_SPEED"); ok do PLAYER_WALL_RUN_HORIZONTAL_SPEED = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_HORIZONTAL_LIFT"); ok do PLAYER_WALL_RUN_HORIZONTAL_LIFT = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT"); ok do PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_SLOPE_SNAP"); ok do PLAYER_SLOPE_SNAP = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_SLOPE_UPHILL_FACTOR"); ok do PLAYER_SLOPE_UPHILL_FACTOR = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_SLOPE_DOWNHILL_FACTOR"); ok do PLAYER_SLOPE_DOWNHILL_FACTOR = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_STEP_HEIGHT"); ok do PLAYER_STEP_HEIGHT = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_LOOK_DEFORM"); ok do PLAYER_LOOK_DEFORM = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_LOOK_SMOOTH"); ok do PLAYER_LOOK_SMOOTH = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_IMPACT_DECAY"); ok do PLAYER_IMPACT_DECAY = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_IMPACT_FREQ"); ok do PLAYER_IMPACT_FREQ = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_IMPACT_SCALE"); ok do PLAYER_IMPACT_SCALE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_IMPACT_THRESHOLD"); ok do PLAYER_IMPACT_THRESHOLD = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_SIZE"); ok do PLAYER_PARTICLE_DUST_SIZE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_GRAVITY"); ok do PLAYER_PARTICLE_DUST_GRAVITY = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_LIFETIME_MIN"); ok do PLAYER_PARTICLE_DUST_LIFETIME_MIN = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_LIFETIME_MAX"); ok do PLAYER_PARTICLE_DUST_LIFETIME_MAX = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_SPEED_MIN"); ok do PLAYER_PARTICLE_DUST_SPEED_MIN = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_SPEED_MAX"); ok do PLAYER_PARTICLE_DUST_SPEED_MAX = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_DUST_FRICTION"); ok do PLAYER_PARTICLE_DUST_FRICTION = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_STEP_SIZE"); ok do PLAYER_PARTICLE_STEP_SIZE = val
	if val, ok := engine.config_get_f32(&game_config, "PLAYER_PARTICLE_STEP_LIFETIME"); ok do PLAYER_PARTICLE_STEP_LIFETIME = val
	if val, ok := engine.config_get_rgba(&game_config, "PLAYER_PARTICLE_DUST_COLOR"); ok do PLAYER_PARTICLE_DUST_COLOR = val
	if val, ok := engine.config_get_rgba(&game_config, "PLAYER_PARTICLE_STEP_COLOR"); ok do PLAYER_PARTICLE_STEP_COLOR = val
	if val, ok := engine.config_get_f32(&game_config, "INPUT_AXIS_DEADZONE"); ok do INPUT_AXIS_DEADZONE = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_MOVE_UP"); ok do INPUT_KB_MOVE_UP = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_MOVE_DOWN"); ok do INPUT_KB_MOVE_DOWN = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_MOVE_LEFT"); ok do INPUT_KB_MOVE_LEFT = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_MOVE_RIGHT"); ok do INPUT_KB_MOVE_RIGHT = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_JUMP"); ok do INPUT_KB_JUMP = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_DASH"); ok do INPUT_KB_DASH = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_WALL_RUN"); ok do INPUT_KB_WALL_RUN = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_SLIDE"); ok do INPUT_KB_SLIDE = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_DEBUG"); ok do INPUT_KB_DEBUG = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_RELOAD"); ok do INPUT_KB_RELOAD = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_KB_QUIT"); ok do INPUT_KB_QUIT = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_MOVE_UP"); ok do INPUT_GP_MOVE_UP = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_MOVE_DOWN"); ok do INPUT_GP_MOVE_DOWN = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_MOVE_LEFT"); ok do INPUT_GP_MOVE_LEFT = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_MOVE_RIGHT"); ok do INPUT_GP_MOVE_RIGHT = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_JUMP"); ok do INPUT_GP_JUMP = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_DASH"); ok do INPUT_GP_DASH = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_WALL_RUN"); ok do INPUT_GP_WALL_RUN = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_SLIDE"); ok do INPUT_GP_SLIDE = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_DEBUG"); ok do INPUT_GP_DEBUG = val
	if val, ok := engine.config_get_string(&game_config, "INPUT_GP_QUIT"); ok do INPUT_GP_QUIT = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_COLLIDER"); ok do DEBUG_COLOR_COLLIDER = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_COLLIDER_BACK_WALL"); ok do DEBUG_COLOR_COLLIDER_BACK_WALL = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_COLLIDER_CEILING"); ok do DEBUG_COLOR_COLLIDER_CEILING = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_COLLIDER_SIDE_WALL"); ok do DEBUG_COLOR_COLLIDER_SIDE_WALL = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_COLLIDER_PLATFORM"); ok do DEBUG_COLOR_COLLIDER_PLATFORM = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_FACING_DIR"); ok do DEBUG_COLOR_FACING_DIR = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_PLAYER"); ok do DEBUG_COLOR_PLAYER = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_STATE"); ok do DEBUG_COLOR_STATE = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_STATE_MUTED"); ok do DEBUG_COLOR_STATE_MUTED = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_GROUND"); ok do DEBUG_COLOR_RAY_GROUND = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_SLOPE"); ok do DEBUG_COLOR_RAY_SLOPE = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_PLATFORM"); ok do DEBUG_COLOR_RAY_PLATFORM = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_WALL"); ok do DEBUG_COLOR_RAY_WALL = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_HIT_POINT"); ok do DEBUG_COLOR_RAY_HIT_POINT = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_RAY_MISS"); ok do DEBUG_COLOR_RAY_MISS = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_VELOCITY"); ok do DEBUG_COLOR_VELOCITY = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_GRID"); ok do DEBUG_COLOR_GRID = val
	if val, ok := engine.config_get_rgba(&game_config, "DEBUG_COLOR_CAMERA_ZONE"); ok do DEBUG_COLOR_CAMERA_ZONE = val
	if val, ok := engine.config_get_u8(&game_config, "DEBUG_GRID_ALPHA"); ok do DEBUG_GRID_ALPHA = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_CROSS_HALF"); ok do DEBUG_CROSS_HALF = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_FACING_LENGTH"); ok do DEBUG_FACING_LENGTH = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_TEXT_CHAR_W"); ok do DEBUG_TEXT_CHAR_W = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_TEXT_LINE_H"); ok do DEBUG_TEXT_LINE_H = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_TEXT_MARGIN_X"); ok do DEBUG_TEXT_MARGIN_X = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_TEXT_MARGIN_Y"); ok do DEBUG_TEXT_MARGIN_Y = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_TEXT_STATE_GAP"); ok do DEBUG_TEXT_STATE_GAP = val
	if val, ok := engine.config_get_f32(&game_config, "DEBUG_VEL_SCALE"); ok do DEBUG_VEL_SCALE = val
}

game_config: engine.Config

config_load_and_apply :: proc() {
	config, ok := engine.config_load("assets/game.ini")
	if !ok {
		fmt.eprintf("[config] Failed to load config\n")
		return
	}
	game_config = config
	config_apply()
}

config_reload_all :: proc() {
	if len(game_config.path) == 0 {
		config_load_and_apply()
		config_post_apply()
		return
	}
	if engine.config_reload(&game_config) {
		config_apply()
		config_post_apply()
		fmt.eprintf("[config] Reloaded\n")
	}
}
