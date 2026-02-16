// AUTO-GENERATED from assets/game.ini — do not edit manually
package game

import engine "../engine"
import "core:fmt"

// [game]
GAME_TITLE: string                           // main title shown in window and UI
GAME_SUBTITLE: string                        // subtitle appended to title

// [version]
VERSION_NAME: string                         // build label (e.g. "Game Jam", "Alpha")
VERSION_DATE: string
VERSION_TIME: string
VERSION_HASH: string

// [engine]
WINDOW_TITLE: string                         // SDL window title bar text
WINDOW_SCALE: u8                             // integer multiplier on logical resolution
LOGICAL_H: f32                               // logical viewport height in pixels (width from aspect ratio)
FPS: u8                                      // target frame rate
FIXED_STEPS: u8                              // physics sub-steps per frame (fixed_dt = 1/(FPS*FIXED_STEPS))

// [physics]
PPM: f32                                     // pixels per meter — world-to-pixel conversion factor
GRAVITY: f32                                 // downward acceleration (m/s²)
EPS: f32                                     // collision epsilon — smallest meaningful distance
TILE_SIZE: f32                               // side length of one tile in meters (1 BMP pixel = 1 tile)

// [camera]
CAMERA_FOLLOW_SPEED_MIN: f32                 // follow speed inside dead zone (slow drift)
CAMERA_FOLLOW_SPEED_MAX: f32                 // follow speed at viewport edge (fast catch-up)
CAMERA_DEAD_ZONE: f32                        // normalized half-viewport radius where camera doesn't move
CAMERA_BOUNDARY_ZONE: f32                    // meters from level edge where camera decelerates

// [level]
LEVEL_NAME: string                           // BMP filename in assets/ (without extension)
LEVEL_COLOR_BG: [4]u8                        // background clear color
LEVEL_COLOR_TILE_SOLID: [4]u8                // solid tile fill color
LEVEL_COLOR_TILE_BACK_WALL: [4]u8            // back wall / slope background fill color
LEVEL_PALETTE_EMPTY: [4]u8                   // BMP palette: empty / air
LEVEL_PALETTE_SOLID: [4]u8                   // BMP palette: solid wall
LEVEL_PALETTE_PLATFORM: [4]u8                // BMP palette: one-way platform
LEVEL_PALETTE_BACK_WALL: [4]u8               // BMP palette: background wall
LEVEL_PALETTE_SPAWN: [4]u8                   // BMP palette: player spawn point
LEVEL_PALETTE_SLOPE_RIGHT: [4]u8             // BMP palette: floor slope /
LEVEL_PALETTE_SLOPE_LEFT: [4]u8              // BMP palette: floor slope \
LEVEL_PALETTE_SLOPE_CEIL_RIGHT: [4]u8        // BMP palette: ceiling slope \
LEVEL_PALETTE_SLOPE_CEIL_LEFT: [4]u8         // BMP palette: ceiling slope /
LEVEL_PALETTE_SAND_PILE: [4]u8               // BMP palette: pre-placed sand
LEVEL_PALETTE_SAND_EMITTER: [4]u8            // BMP palette: sand emitter
LEVEL_PALETTE_WATER_PILE: [4]u8              // BMP palette: pre-placed water
LEVEL_PALETTE_WATER_EMITTER: [4]u8           // BMP palette: water emitter

// [player]
PLAYER_COLOR: [4]u8                          // player square color (RGBA)
PLAYER_SIZE: f32                             // player hitbox side length (square)
PLAYER_CHECK_GROUND_EPS: f32                 // raycast distance below feet for ground detection
PLAYER_CHECK_SIDE_WALL_EPS: f32              // raycast distance sideways for wall detection
PLAYER_COYOTE_TIME_DURATION: f32             // seconds after leaving ground where jump still allowed
PLAYER_DROP_NUDGE: f32                       // downward nudge when dropping through a platform
PLAYER_FAST_FALL_MULT: f32                   // gravity multiplier when ascending with jump released (short hop)
PLAYER_INPUT_AXIS_THRESHOLD: f32             // stick/axis magnitude to register directional input
PLAYER_MOVE_LERP_SPEED: f32                  // interpolation rate for horizontal movement smoothing

// [player_run]
PLAYER_RUN_SPEED: f32                        // max horizontal run speed (m/s)
PLAYER_RUN_SPEED_THRESHOLD: f32              // below this speed, considered standing still
PLAYER_RUN_BOB_AMPLITUDE: f32                // vertical bob amplitude while running (meters)
PLAYER_RUN_BOB_SPEED: f32                    // bob oscillation frequency (rad/s)

// [player_jump]
PLAYER_JUMP_FORCE: f32                       // upward impulse on jump (m/s)
PLAYER_JUMP_BUFFER_DURATION: f32             // seconds jump input is buffered before landing

// [player_dash]
PLAYER_DASH_SPEED: f32                       // dash velocity (4x run speed)
PLAYER_DASH_DURATION: f32                    // dash active time in seconds
PLAYER_DASH_COOLDOWN: f32                    // seconds between dashes

// [player_wall]
PLAYER_WALL_JUMP_EPS: f32                    // max wall distance to allow wall jump
PLAYER_WALL_JUMP_FORCE: f32                  // wall jump impulse (1.5x normal jump)
PLAYER_WALL_JUMP_VERTICAL_MULT: f32          // vertical component scale of wall jump (less upward)
PLAYER_WALL_SLIDE_SPEED: f32                 // max downward speed while wall sliding
PLAYER_WALL_RUN_COOLDOWN: f32                // seconds before wall run can be used again
PLAYER_WALL_RUN_VERTICAL_SPEED: f32          // initial upward speed for vertical wall run
PLAYER_WALL_RUN_VERTICAL_DECAY: f32          // exponential decay rate of vertical wall run speed
PLAYER_WALL_RUN_HORIZONTAL_SPEED: f32        // horizontal speed along back wall during wall run
PLAYER_WALL_RUN_HORIZONTAL_LIFT: f32         // initial upward boost entering horizontal wall run
PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT: f32    // gravity reduction during horizontal wall run (parabolic arc)

// [player_slopes]
PLAYER_SLOPE_SNAP: f32                       // max snap distance to stick to slope surface (airborne)
PLAYER_SLOPE_UPHILL_FACTOR: f32              // speed multiplier going uphill (slower)
PLAYER_SLOPE_DOWNHILL_FACTOR: f32            // speed multiplier going downhill (faster)
PLAYER_STEP_HEIGHT: f32                      // max obstacle height player can step over seamlessly
PLAYER_SWEEP_SKIN: f32                       // swept AABB skin width to prevent tunneling

// [player_graphics]
PLAYER_LOOK_DEFORM: f32                      // velocity-based squash/stretch deformation amount
PLAYER_LOOK_SMOOTH: f32                      // interpolation speed for look direction smoothing
PLAYER_IMPACT_DECAY: f32                     // damping rate of impact bounce spring
PLAYER_IMPACT_FREQ: f32                      // oscillation frequency of impact bounce (rad/s)
PLAYER_IMPACT_SCALE: f32                     // max squash/stretch scale from impact bounce
PLAYER_IMPACT_THRESHOLD: f32                 // min landing velocity to trigger impact bounce
PLAYER_VEL_DEFORM_Y_H: f32                   // velocity Y → height stretch sensitivity
PLAYER_VEL_DEFORM_X_H: f32                   // velocity X → height shrink sensitivity
PLAYER_VEL_DEFORM_Y_W: f32                   // velocity Y → width shrink sensitivity
PLAYER_VEL_DEFORM_X_W: f32                   // velocity X → width stretch sensitivity
PLAYER_LOOK_DEFORM_W_Y: f32                  // look Y → width coupling ratio
PLAYER_LOOK_DEFORM_W_X: f32                  // look X → width coupling ratio
PLAYER_BOB_DEFORM_W: f32                     // run bob → width coupling ratio
PLAYER_IMPACT_CUTOFF: f32                    // impact bounce envelope cutoff
PLAYER_IMPACT_DEFORM_W_Y: f32                // impact Y → width coupling ratio
PLAYER_IMPACT_DEFORM_H_X: f32                // impact X → height coupling ratio
PLAYER_DEFORM_MIN: f32                       // min deformation scale clamp
PLAYER_DEFORM_MAX: f32                       // max deformation scale clamp

// [player_particles]
PLAYER_PARTICLE_DUST_SIZE: f32               // dust particle radius
PLAYER_PARTICLE_DUST_GRAVITY: f32            // gravity on dust particles (m/s²)
PLAYER_PARTICLE_DUST_LIFETIME_MIN: f32       // min dust particle lifetime (seconds)
PLAYER_PARTICLE_DUST_LIFETIME_MAX: f32       // max dust particle lifetime (seconds)
PLAYER_PARTICLE_DUST_SPEED_MIN: f32          // min dust emit speed (m/s)
PLAYER_PARTICLE_DUST_SPEED_MAX: f32          // max dust emit speed (m/s)
PLAYER_PARTICLE_DUST_FRICTION: f32           // air friction on dust particles
PLAYER_PARTICLE_STEP_SIZE: f32               // footstep mark size
PLAYER_PARTICLE_STEP_LIFETIME: f32           // footstep mark duration (seconds)
PLAYER_PARTICLE_DUST_LAND_COUNT: u8          // dust particles emitted on landing
PLAYER_PARTICLE_DUST_STEP_COUNT: u8          // dust particles per footstep
PLAYER_PARTICLE_DUST_JUMP_COUNT: u8          // dust particles on jump
PLAYER_PARTICLE_DUST_DASH_COUNT: u8          // dust particles on dash start
PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT: u8     // dust particles on wall jump
PLAYER_PARTICLE_DUST_WALL_RUN_COUNT: u8      // dust particles per wall run step
PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT: u8    // dust particles per wall slide tick
PLAYER_PARTICLE_DUST_WALL_SLIDE_CHANCE: f32  // probability of emitting dust per wall slide tick

// [player_particle_colors]
PLAYER_PARTICLE_DUST_COLOR: [4]u8            // dust particle color (sandy beige)
PLAYER_PARTICLE_STEP_COLOR: [4]u8            // footstep mark color (dark brown)

// [input]
INPUT_AXIS_DEADZONE: f32                     // gamepad stick deadzone (0-1)
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
DEBUG_COLOR_COLLIDER: [4]u8                  // ground collider outline (green)
DEBUG_COLOR_COLLIDER_BACK_WALL: [4]u8        // back wall collider outline (dark cyan)
DEBUG_COLOR_COLLIDER_CEILING: [4]u8          // ceiling collider outline (dark red)
DEBUG_COLOR_COLLIDER_SIDE_WALL: [4]u8        // side wall collider outline (orange)
DEBUG_COLOR_COLLIDER_PLATFORM: [4]u8         // platform collider outline (blue)
DEBUG_COLOR_FACING_DIR: [4]u8                // player facing direction arrow (cyan)
DEBUG_COLOR_PLAYER: [4]u8                    // player position cross (magenta)
DEBUG_COLOR_STATE: [4]u8                     // current FSM state text (white)
DEBUG_COLOR_STATE_MUTED: [4]u8               // previous FSM state text (muted white)
DEBUG_COLOR_RAY_GROUND: [4]u8                // ground raycast hit (green)
DEBUG_COLOR_RAY_SLOPE: [4]u8                 // slope raycast hit (light green)
DEBUG_COLOR_RAY_PLATFORM: [4]u8              // platform raycast hit (blue)
DEBUG_COLOR_RAY_WALL: [4]u8                  // wall raycast hit (orange)
DEBUG_COLOR_RAY_HIT_POINT: [4]u8             // raycast hit point marker (red)
DEBUG_COLOR_RAY_MISS: [4]u8                  // raycast miss (gray)
DEBUG_COLOR_VELOCITY: [4]u8                  // velocity vector arrow (yellow-green)
DEBUG_COLOR_GRID: [4]u8                      // tile grid lines (white, alpha controlled separately)
DEBUG_COLOR_CAMERA_ZONE: [4]u8               // camera dead zone rectangle (translucent white)

// [debug]
DEBUG_GRID_ALPHA: u8                         // tile grid line opacity (0-255)
DEBUG_CROSS_HALF: f32                        // half-size of debug cross markers in pixels
DEBUG_FACING_LENGTH: f32                     // facing direction arrow length in meters
DEBUG_TEXT_CHAR_W: f32                       // debug text character width in pixels
DEBUG_TEXT_LINE_H: f32                       // debug text line height in pixels
DEBUG_TEXT_MARGIN_X: f32                     // debug HUD left margin in pixels
DEBUG_TEXT_MARGIN_Y: f32                     // debug HUD top margin in pixels
DEBUG_TEXT_STATE_GAP: f32                    // vertical gap between FSM state labels in pixels
DEBUG_VEL_SCALE: f32                         // velocity vector display scale (world units per m/s)
DEBUG_TEXT_TITLE_GAP: f32                    // multiplier on line height after title

config_apply :: proc() {
	if val, ok := engine.config_get_string(&config_game, "GAME_TITLE"); ok do GAME_TITLE = val
	if val, ok := engine.config_get_string(&config_game, "GAME_SUBTITLE"); ok do GAME_SUBTITLE = val
	if val, ok := engine.config_get_string(&config_game, "VERSION_NAME"); ok do VERSION_NAME = val
	if val, ok := engine.config_get_string(&config_game, "VERSION_DATE"); ok do VERSION_DATE = val
	if val, ok := engine.config_get_string(&config_game, "VERSION_TIME"); ok do VERSION_TIME = val
	if val, ok := engine.config_get_string(&config_game, "VERSION_HASH"); ok do VERSION_HASH = val
	if val, ok := engine.config_get_string(&config_game, "WINDOW_TITLE"); ok do WINDOW_TITLE = val
	if val, ok := engine.config_get_u8(&config_game, "WINDOW_SCALE"); ok do WINDOW_SCALE = val
	if val, ok := engine.config_get_f32(&config_game, "LOGICAL_H"); ok do LOGICAL_H = val
	if val, ok := engine.config_get_u8(&config_game, "FPS"); ok do FPS = val
	if val, ok := engine.config_get_u8(&config_game, "FIXED_STEPS"); ok do FIXED_STEPS = val
	if val, ok := engine.config_get_f32(&config_game, "PPM"); ok do PPM = val
	if val, ok := engine.config_get_f32(&config_game, "GRAVITY"); ok do GRAVITY = val
	if val, ok := engine.config_get_f32(&config_game, "EPS"); ok do EPS = val
	if val, ok := engine.config_get_f32(&config_game, "TILE_SIZE"); ok do TILE_SIZE = val
	if val, ok := engine.config_get_f32(&config_game, "CAMERA_FOLLOW_SPEED_MIN"); ok do CAMERA_FOLLOW_SPEED_MIN = val
	if val, ok := engine.config_get_f32(&config_game, "CAMERA_FOLLOW_SPEED_MAX"); ok do CAMERA_FOLLOW_SPEED_MAX = val
	if val, ok := engine.config_get_f32(&config_game, "CAMERA_DEAD_ZONE"); ok do CAMERA_DEAD_ZONE = val
	if val, ok := engine.config_get_f32(&config_game, "CAMERA_BOUNDARY_ZONE"); ok do CAMERA_BOUNDARY_ZONE = val
	if val, ok := engine.config_get_string(&config_game, "LEVEL_NAME"); ok do LEVEL_NAME = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_COLOR_BG"); ok do LEVEL_COLOR_BG = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_COLOR_TILE_SOLID"); ok do LEVEL_COLOR_TILE_SOLID = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_COLOR_TILE_BACK_WALL"); ok do LEVEL_COLOR_TILE_BACK_WALL = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_EMPTY"); ok do LEVEL_PALETTE_EMPTY = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SOLID"); ok do LEVEL_PALETTE_SOLID = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_PLATFORM"); ok do LEVEL_PALETTE_PLATFORM = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_BACK_WALL"); ok do LEVEL_PALETTE_BACK_WALL = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SPAWN"); ok do LEVEL_PALETTE_SPAWN = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SLOPE_RIGHT"); ok do LEVEL_PALETTE_SLOPE_RIGHT = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SLOPE_LEFT"); ok do LEVEL_PALETTE_SLOPE_LEFT = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SLOPE_CEIL_RIGHT"); ok do LEVEL_PALETTE_SLOPE_CEIL_RIGHT = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SLOPE_CEIL_LEFT"); ok do LEVEL_PALETTE_SLOPE_CEIL_LEFT = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SAND_PILE"); ok do LEVEL_PALETTE_SAND_PILE = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_SAND_EMITTER"); ok do LEVEL_PALETTE_SAND_EMITTER = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_WATER_PILE"); ok do LEVEL_PALETTE_WATER_PILE = val
	if val, ok := engine.config_get_rgba(&config_game, "LEVEL_PALETTE_WATER_EMITTER"); ok do LEVEL_PALETTE_WATER_EMITTER = val
	if val, ok := engine.config_get_rgba(&config_game, "PLAYER_COLOR"); ok do PLAYER_COLOR = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_SIZE"); ok do PLAYER_SIZE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_CHECK_GROUND_EPS"); ok do PLAYER_CHECK_GROUND_EPS = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_CHECK_SIDE_WALL_EPS"); ok do PLAYER_CHECK_SIDE_WALL_EPS = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_COYOTE_TIME_DURATION"); ok do PLAYER_COYOTE_TIME_DURATION = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DROP_NUDGE"); ok do PLAYER_DROP_NUDGE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_FAST_FALL_MULT"); ok do PLAYER_FAST_FALL_MULT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_INPUT_AXIS_THRESHOLD"); ok do PLAYER_INPUT_AXIS_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_MOVE_LERP_SPEED"); ok do PLAYER_MOVE_LERP_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_RUN_SPEED"); ok do PLAYER_RUN_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_RUN_SPEED_THRESHOLD"); ok do PLAYER_RUN_SPEED_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_RUN_BOB_AMPLITUDE"); ok do PLAYER_RUN_BOB_AMPLITUDE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_RUN_BOB_SPEED"); ok do PLAYER_RUN_BOB_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_JUMP_FORCE"); ok do PLAYER_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_JUMP_BUFFER_DURATION"); ok do PLAYER_JUMP_BUFFER_DURATION = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DASH_SPEED"); ok do PLAYER_DASH_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DASH_DURATION"); ok do PLAYER_DASH_DURATION = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DASH_COOLDOWN"); ok do PLAYER_DASH_COOLDOWN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_JUMP_EPS"); ok do PLAYER_WALL_JUMP_EPS = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_JUMP_FORCE"); ok do PLAYER_WALL_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_JUMP_VERTICAL_MULT"); ok do PLAYER_WALL_JUMP_VERTICAL_MULT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_SLIDE_SPEED"); ok do PLAYER_WALL_SLIDE_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_COOLDOWN"); ok do PLAYER_WALL_RUN_COOLDOWN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_VERTICAL_SPEED"); ok do PLAYER_WALL_RUN_VERTICAL_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_VERTICAL_DECAY"); ok do PLAYER_WALL_RUN_VERTICAL_DECAY = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_HORIZONTAL_SPEED"); ok do PLAYER_WALL_RUN_HORIZONTAL_SPEED = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_HORIZONTAL_LIFT"); ok do PLAYER_WALL_RUN_HORIZONTAL_LIFT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT"); ok do PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_SLOPE_SNAP"); ok do PLAYER_SLOPE_SNAP = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_SLOPE_UPHILL_FACTOR"); ok do PLAYER_SLOPE_UPHILL_FACTOR = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_SLOPE_DOWNHILL_FACTOR"); ok do PLAYER_SLOPE_DOWNHILL_FACTOR = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_STEP_HEIGHT"); ok do PLAYER_STEP_HEIGHT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_SWEEP_SKIN"); ok do PLAYER_SWEEP_SKIN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_LOOK_DEFORM"); ok do PLAYER_LOOK_DEFORM = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_LOOK_SMOOTH"); ok do PLAYER_LOOK_SMOOTH = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_DECAY"); ok do PLAYER_IMPACT_DECAY = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_FREQ"); ok do PLAYER_IMPACT_FREQ = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_SCALE"); ok do PLAYER_IMPACT_SCALE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_THRESHOLD"); ok do PLAYER_IMPACT_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_VEL_DEFORM_Y_H"); ok do PLAYER_VEL_DEFORM_Y_H = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_VEL_DEFORM_X_H"); ok do PLAYER_VEL_DEFORM_X_H = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_VEL_DEFORM_Y_W"); ok do PLAYER_VEL_DEFORM_Y_W = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_VEL_DEFORM_X_W"); ok do PLAYER_VEL_DEFORM_X_W = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_LOOK_DEFORM_W_Y"); ok do PLAYER_LOOK_DEFORM_W_Y = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_LOOK_DEFORM_W_X"); ok do PLAYER_LOOK_DEFORM_W_X = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_BOB_DEFORM_W"); ok do PLAYER_BOB_DEFORM_W = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_CUTOFF"); ok do PLAYER_IMPACT_CUTOFF = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_DEFORM_W_Y"); ok do PLAYER_IMPACT_DEFORM_W_Y = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_IMPACT_DEFORM_H_X"); ok do PLAYER_IMPACT_DEFORM_H_X = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DEFORM_MIN"); ok do PLAYER_DEFORM_MIN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_DEFORM_MAX"); ok do PLAYER_DEFORM_MAX = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_SIZE"); ok do PLAYER_PARTICLE_DUST_SIZE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_GRAVITY"); ok do PLAYER_PARTICLE_DUST_GRAVITY = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_LIFETIME_MIN"); ok do PLAYER_PARTICLE_DUST_LIFETIME_MIN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_LIFETIME_MAX"); ok do PLAYER_PARTICLE_DUST_LIFETIME_MAX = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_SPEED_MIN"); ok do PLAYER_PARTICLE_DUST_SPEED_MIN = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_SPEED_MAX"); ok do PLAYER_PARTICLE_DUST_SPEED_MAX = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_FRICTION"); ok do PLAYER_PARTICLE_DUST_FRICTION = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_STEP_SIZE"); ok do PLAYER_PARTICLE_STEP_SIZE = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_STEP_LIFETIME"); ok do PLAYER_PARTICLE_STEP_LIFETIME = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_LAND_COUNT"); ok do PLAYER_PARTICLE_DUST_LAND_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_STEP_COUNT"); ok do PLAYER_PARTICLE_DUST_STEP_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_JUMP_COUNT"); ok do PLAYER_PARTICLE_DUST_JUMP_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_DASH_COUNT"); ok do PLAYER_PARTICLE_DUST_DASH_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT"); ok do PLAYER_PARTICLE_DUST_WALL_JUMP_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_WALL_RUN_COUNT"); ok do PLAYER_PARTICLE_DUST_WALL_RUN_COUNT = val
	if val, ok := engine.config_get_u8(&config_game, "PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT"); ok do PLAYER_PARTICLE_DUST_WALL_SLIDE_COUNT = val
	if val, ok := engine.config_get_f32(&config_game, "PLAYER_PARTICLE_DUST_WALL_SLIDE_CHANCE"); ok do PLAYER_PARTICLE_DUST_WALL_SLIDE_CHANCE = val
	if val, ok := engine.config_get_rgba(&config_game, "PLAYER_PARTICLE_DUST_COLOR"); ok do PLAYER_PARTICLE_DUST_COLOR = val
	if val, ok := engine.config_get_rgba(&config_game, "PLAYER_PARTICLE_STEP_COLOR"); ok do PLAYER_PARTICLE_STEP_COLOR = val
	if val, ok := engine.config_get_f32(&config_game, "INPUT_AXIS_DEADZONE"); ok do INPUT_AXIS_DEADZONE = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_MOVE_UP"); ok do INPUT_KB_MOVE_UP = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_MOVE_DOWN"); ok do INPUT_KB_MOVE_DOWN = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_MOVE_LEFT"); ok do INPUT_KB_MOVE_LEFT = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_MOVE_RIGHT"); ok do INPUT_KB_MOVE_RIGHT = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_JUMP"); ok do INPUT_KB_JUMP = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_DASH"); ok do INPUT_KB_DASH = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_WALL_RUN"); ok do INPUT_KB_WALL_RUN = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_SLIDE"); ok do INPUT_KB_SLIDE = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_DEBUG"); ok do INPUT_KB_DEBUG = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_RELOAD"); ok do INPUT_KB_RELOAD = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_KB_QUIT"); ok do INPUT_KB_QUIT = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_MOVE_UP"); ok do INPUT_GP_MOVE_UP = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_MOVE_DOWN"); ok do INPUT_GP_MOVE_DOWN = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_MOVE_LEFT"); ok do INPUT_GP_MOVE_LEFT = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_MOVE_RIGHT"); ok do INPUT_GP_MOVE_RIGHT = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_JUMP"); ok do INPUT_GP_JUMP = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_DASH"); ok do INPUT_GP_DASH = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_WALL_RUN"); ok do INPUT_GP_WALL_RUN = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_SLIDE"); ok do INPUT_GP_SLIDE = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_DEBUG"); ok do INPUT_GP_DEBUG = val
	if val, ok := engine.config_get_string(&config_game, "INPUT_GP_QUIT"); ok do INPUT_GP_QUIT = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_COLLIDER"); ok do DEBUG_COLOR_COLLIDER = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_COLLIDER_BACK_WALL"); ok do DEBUG_COLOR_COLLIDER_BACK_WALL = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_COLLIDER_CEILING"); ok do DEBUG_COLOR_COLLIDER_CEILING = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_COLLIDER_SIDE_WALL"); ok do DEBUG_COLOR_COLLIDER_SIDE_WALL = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_COLLIDER_PLATFORM"); ok do DEBUG_COLOR_COLLIDER_PLATFORM = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_FACING_DIR"); ok do DEBUG_COLOR_FACING_DIR = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_PLAYER"); ok do DEBUG_COLOR_PLAYER = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_STATE"); ok do DEBUG_COLOR_STATE = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_STATE_MUTED"); ok do DEBUG_COLOR_STATE_MUTED = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_GROUND"); ok do DEBUG_COLOR_RAY_GROUND = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_SLOPE"); ok do DEBUG_COLOR_RAY_SLOPE = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_PLATFORM"); ok do DEBUG_COLOR_RAY_PLATFORM = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_WALL"); ok do DEBUG_COLOR_RAY_WALL = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_HIT_POINT"); ok do DEBUG_COLOR_RAY_HIT_POINT = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_RAY_MISS"); ok do DEBUG_COLOR_RAY_MISS = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_VELOCITY"); ok do DEBUG_COLOR_VELOCITY = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_GRID"); ok do DEBUG_COLOR_GRID = val
	if val, ok := engine.config_get_rgba(&config_game, "DEBUG_COLOR_CAMERA_ZONE"); ok do DEBUG_COLOR_CAMERA_ZONE = val
	if val, ok := engine.config_get_u8(&config_game, "DEBUG_GRID_ALPHA"); ok do DEBUG_GRID_ALPHA = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_CROSS_HALF"); ok do DEBUG_CROSS_HALF = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_FACING_LENGTH"); ok do DEBUG_FACING_LENGTH = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_CHAR_W"); ok do DEBUG_TEXT_CHAR_W = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_LINE_H"); ok do DEBUG_TEXT_LINE_H = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_MARGIN_X"); ok do DEBUG_TEXT_MARGIN_X = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_MARGIN_Y"); ok do DEBUG_TEXT_MARGIN_Y = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_STATE_GAP"); ok do DEBUG_TEXT_STATE_GAP = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_VEL_SCALE"); ok do DEBUG_VEL_SCALE = val
	if val, ok := engine.config_get_f32(&config_game, "DEBUG_TEXT_TITLE_GAP"); ok do DEBUG_TEXT_TITLE_GAP = val
}

config_game: engine.Config

config_load_and_apply :: proc() {
	config, ok := engine.config_load("assets/game.ini")
	if !ok {
		fmt.eprintf("[game config] Failed to load config\n")
		return
	}
	config_game = config
	config_apply()
}

config_reload :: proc() -> bool {
	if len(config_game.path) == 0 {
		config_load_and_apply()
		return true
	}
	if engine.config_reload(&config_game) {
		config_apply()
		return true
	}
	return false
}
