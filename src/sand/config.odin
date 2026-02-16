// AUTO-GENERATED from assets/game.ini — do not edit manually
package sand

import engine "../engine"
import "core:fmt"

// [sand]
SAND_CHUNK_SIZE: u8                   // spatial chunk side length in tiles
SAND_CELLS_PER_TILE: u8               // sand grid cells per level tile (power of 2: 1, 2, 4, 8)
SAND_CELL_SIZE: f32                   // derived cell size in meters
SAND_SIM_INTERVAL: u8                 // sim every Nth fixed step (4 = 60Hz at 240Hz fixed)
SAND_SLEEP_THRESHOLD: u8              // idle steps before cell sleeps (skipped in sim)
SAND_COLOR: [4]u8                     // base sand particle color
SAND_COLOR_VARIATION: u8              // per-particle brightness offset for visual variety
SAND_EMITTER_RATE: f32                // particles spawned per second per emitter
SAND_PLAYER_DRAG_PER_CELL: f32        // velocity drag added per displaced sand cell
SAND_PLAYER_DRAG_MAX: f32             // max total drag factor cap (0-1)
SAND_PLAYER_DRAG_Y_FACTOR: f32        // Y drag is this fraction of X drag (preserves jump feel)
SAND_PRESSURE_FORCE: f32              // downward force per sqrt(sand cells) above player
SAND_PRESSURE_GAP_TOLERANCE: u8       // empty cells to scan past in pressure column
SAND_BURIAL_THRESHOLD: f32            // sand/footprint overlap ratio to count as buried
SAND_DISPLACE_CHAIN: u8               // max recursive push depth when displacing sand
SAND_DISPLACE_PARTICLE_MAX: u8        // max displacement particles per material type
SAND_SINK_SPEED: f32                  // sinking rate (m/s) when standing on sand
SAND_MOVE_PENALTY: f32                // run speed reduction per immersion (0=none, 1=zero at full)
SAND_JUMP_PENALTY: f32                // jump force reduction per immersion (0=none, 1=no jump)
SAND_FALL_ACCEL_DIVISOR: u8           // extra_steps = fall_count / divisor
SAND_FALL_MAX_STEPS: u8               // max cells moved per sim step
SAND_REPOSE_CHANCE: f32               // probability of attempting diagonal move (0-1, lower = steeper piles)
SAND_WATER_SWAP_CHANCE: f32           // probability sand sinks through water per tick (organic mixing)
SAND_WALL_RUN_PENALTY: f32            // wall run speed reduction per immersion (0=none, 1=zero)
SAND_PARTICLE_SPEED: f32              // displacement particle outward velocity (m/s)
SAND_PARTICLE_LIFETIME: f32           // displacement particle lifetime (seconds)
SAND_PARTICLE_SIZE: f32               // displacement particle size (meters)
SAND_PARTICLE_GRAVITY: f32            // displacement particle gravity (m/s²)
SAND_PARTICLE_FRICTION: f32           // air friction on displacement particles
SAND_DUST_MIN_SPEED: f32              // minimum horizontal speed for dust emission (m/s)
SAND_DUST_SPEED: f32                  // horizontal dust drift speed (m/s)
SAND_DUST_LIFT: f32                   // upward dust speed (m/s)
SAND_DUST_LIFETIME: f32               // dust particle lifetime (seconds)
SAND_DUST_SIZE: f32                   // dust particle size (meters)
SAND_DUST_LIGHTEN: u8                 // RGB offset to lighten sand color for dust
SAND_DUST_INTERVAL: u8                // emit every N fixed steps
SAND_IMPACT_MIN_SPEED: f32            // below this: no extra displacement (m/s)
SAND_IMPACT_MAX_SPEED: f32            // at/above this: maximum crater (m/s)
SAND_IMPACT_RADIUS: u8                // max extra cells at max impact
SAND_IMPACT_PARTICLE_SPEED_MULT: f32  // particle speed multiplier at max impact
SAND_IMPACT_PARTICLE_MIN: u8          // displacement particles at zero impact
SAND_IMPACT_PARTICLE_MAX: u8          // displacement particles at max impact
SAND_EJECT_MAX_HEIGHT: u8             // max cells above footprint for crater rim ejection
SAND_FOOTPRINT_STRIDE: f32            // meters between footprints (~1 tile)
SAND_FOOTPRINT_MIN_SPEED: f32         // minimum horizontal speed for footprints (m/s)
SAND_DASH_DRAG_FACTOR: f32            // drag multiplier during dash (20% of normal)
SAND_DASH_PARTICLE_MAX: u8            // max particles per fixed step during dash
SAND_DASH_PARTICLE_SPEED_MULT: f32    // particle speed multiplier during dash
SAND_QUICKSAND_BASE_SINK: f32         // gravity multiplier when still in sand
SAND_QUICKSAND_MOVE_MULT: f32         // extra gravity per activity unit
SAND_SURFACE_SCAN_HEIGHT: u8          // cells to scan vertically for surface
SAND_SURFACE_SMOOTH: u8               // 0=staircase (current), 1=interpolated
SAND_SWIM_ENTER_THRESHOLD: f32        // sand immersion to enter sand swim
SAND_SWIM_EXIT_THRESHOLD: f32         // sand immersion to exit sand swim (hysteresis)
SAND_SWIM_SURFACE_THRESHOLD: f32      // immersion considered near surface for jump-out
SAND_SWIM_GRAVITY_MULT: f32           // gravity multiplier while sand swimming
SAND_SWIM_UP_SPEED: f32               // upward speed when pressing up (m/s)
SAND_SWIM_DOWN_SPEED: f32             // downward speed when pressing down (m/s)
SAND_SWIM_SINK_SPEED: f32             // passive sinking speed (no input) (m/s)
SAND_SWIM_DAMPING: f32                // velocity damping factor per second
SAND_SWIM_JUMP_FORCE: f32             // jump force when leaping out near surface
SAND_SWIM_MOVE_PENALTY: f32           // horizontal speed reduction per immersion
SAND_SWIM_LERP_SPEED: f32             // interpolation rate for movement smoothing
SAND_SWIM_DRAG_FACTOR: f32            // residual displacement drag during sand swim
SAND_SWIM_JUMP_PARTICLE_COUNT: u8     // sand particles on sand swim jump-out
SAND_SWIM_HOP_FORCE: f32              // upward impulse per sand hop
SAND_SWIM_HOP_COOLDOWN: f32           // min seconds between hops
SAND_SWIM_HOP_PARTICLE_COUNT: u8      // particles per hop
SAND_WALL_MIN_HEIGHT: u8              // min contiguous cells for wall detection
SAND_WALL_ERODE_RATE: u8              // cells displaced per fixed step during wall-run
SAND_WALL_JUMP_MULT: f32              // wall jump force multiplier from sand wall
SAND_IMPACT_PARTICLE_SPREAD: f32      // half-spread angle for impact particles (PI/2.5 radians)
SAND_IMPACT_PARTICLE_VEL_BIAS: f32    // impact Y velocity bias multiplier
SAND_PARTICLE_VEL_BIAS_X: f32         // horizontal velocity bias multiplier
SAND_PARTICLE_VEL_BIAS_Y: f32         // vertical bias from horizontal movement
SAND_DASH_PARTICLE_VEL_BIAS: f32      // dash carve particle velocity bias multiplier
SAND_PARTICLE_SPEED_RAND_MIN: f32     // min fraction for speed randomization
SAND_PARTICLE_LIFETIME_RAND_MIN: f32  // min fraction for lifetime randomization
SAND_DUST_SPEED_RAND_MIN: f32         // min fraction for dust speed randomization
SAND_DUST_LIFETIME_RAND_MIN: f32      // min fraction for dust lifetime randomization
SAND_QUICKSAND_MAX_ACTIVITY: f32      // max activity factor clamp for quicksand

// [sand_debug]
SAND_DEBUG_COLOR_LOW: [4]u8           // heatmap color for low pressure (blue)
SAND_DEBUG_COLOR_MID: [4]u8           // heatmap color for mid pressure (yellow)
SAND_DEBUG_COLOR_HIGH: [4]u8          // heatmap color for high pressure (red)
SAND_DEBUG_COLOR_CHUNK: [4]u8         // active chunk highlight color
SAND_DEBUG_COLOR_EMITTER: [4]u8       // emitter marker outline color (cyan)
SAND_DEBUG_SLEEP_DIM: u8              // overlay alpha for sleeping particles
SAND_DEBUG_PRESSURE_MAX: f32          // heatmap pressure cap (above this = max color)
SAND_DEBUG_PRESSURE_DECAY: f32        // pressure decay through empty cells
SAND_DEBUG_HEATMAP_LOW: f32           // heatmap low→mid threshold
SAND_DEBUG_HEATMAP_HIGH: f32          // heatmap mid→high threshold
SAND_DEBUG_CHUNK_OUTLINE_ALPHA: u8    // chunk boundary outline alpha
SAND_DEBUG_STATS_LINE_OFFSET: u8      // line count offset for stats Y position

// [water]
WATER_COLOR: [4]u8                    // base water particle color (translucent cyan)
WATER_COLOR_VARIATION: u8             // max RGB darkening at depth
WATER_COLOR_DEPTH_MAX: u8             // cell distance from surface where darkening reaches maximum
WATER_FLOW_DISTANCE: u8               // max horizontal flow per step (depth-proportional: surface=1, +1 per depth cell)
WATER_EMITTER_RATE: f32               // particles spawned per second per water emitter
WATER_PLAYER_DRAG_PER_CELL: f32       // velocity drag added per displaced water cell
WATER_PLAYER_DRAG_MAX: f32            // max total drag factor cap (0-1)
WATER_PLAYER_DRAG_Y_FACTOR: f32       // Y drag is this fraction of X drag (water is denser)
WATER_BUOYANCY_FORCE: f32             // upward force per immersion ratio (0-1)
WATER_BUOYANCY_THRESHOLD: f32         // water immersion ratio to trigger buoyancy
WATER_MOVE_PENALTY: f32               // run speed reduction per water immersion
WATER_JUMP_PENALTY: f32               // jump force reduction per water immersion
WATER_SWIM_ENTER_THRESHOLD: f32       // immersion ratio to enter swimming
WATER_SWIM_EXIT_THRESHOLD: f32        // immersion ratio to exit swimming (hysteresis)
WATER_SWIM_SURFACE_THRESHOLD: f32     // immersion ratio considered "at surface" for jump-out
WATER_SWIM_GRAVITY_MULT: f32          // gravity multiplier while swimming
WATER_SWIM_UP_SPEED: f32              // upward speed when pressing up
WATER_SWIM_DOWN_SPEED: f32            // downward speed when pressing down
WATER_SWIM_FLOAT_SPEED: f32           // passive float-up speed (no input)
WATER_SWIM_DAMPING: f32               // velocity damping factor per second
WATER_SWIM_JUMP_FORCE: f32            // jump force when leaping out at surface
WATER_CURRENT_FORCE: f32              // horizontal force from flowing water (m/s^2)
WATER_SHIMMER_SPEED: f32              // oscillation speed (radians/sec)
WATER_SHIMMER_PHASE: f32              // spatial frequency (radians/cell)
WATER_SHIMMER_BRIGHTNESS: u8          // max RGB highlight on surface (0-255)
WATER_PRESSURE_MIN_DEPTH: u8          // minimum water cells below before upward movement
WATER_PRESSURE_SCAN_RANGE: u8         // horizontal scan distance for taller columns
WATER_PRESSURE_CHANCE: f32            // probability of rising per eligible step
WATER_SURFACE_TENSION_DEPTH: u8       // minimum depth before surface cells flow horizontally
WATER_CONTACT_WET_CHANCE: f32         // probability per neighbor per tick of wetting adjacent dry sand

// [wet_sand]
WET_SAND_DRY_STEPS: u8                // sim steps without adjacent water before drying back to sand
WET_SAND_SPREAD_CHANCE: f32           // probability per neighbor per tick of spreading wetness to adjacent dry sand
WET_SAND_REPOSE_CHANCE: f32           // diagonal move probability (lower = steeper piles than dry sand)
WET_SAND_WATER_SWAP_CHANCE: f32       // probability of sinking through water (higher = denser than dry)
WET_SAND_COLOR: [4]u8                 // darker, browner sand color
WET_SAND_COLOR_VARIATION: u8          // less visual variation than dry sand
WET_SAND_PLAYER_DRAG_PER_CELL: f32    // much higher drag per cell than dry sand
WET_SAND_PLAYER_DRAG_MAX: f32         // higher drag cap
WET_SAND_PLAYER_DRAG_Y_FACTOR: f32    // slightly more vertical drag

config_apply :: proc() {
	if val, ok := engine.config_get_u8(&config_sand, "SAND_CHUNK_SIZE"); ok do SAND_CHUNK_SIZE = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_CELLS_PER_TILE"); ok do SAND_CELLS_PER_TILE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_CELL_SIZE"); ok do SAND_CELL_SIZE = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SIM_INTERVAL"); ok do SAND_SIM_INTERVAL = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SLEEP_THRESHOLD"); ok do SAND_SLEEP_THRESHOLD = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_COLOR"); ok do SAND_COLOR = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_COLOR_VARIATION"); ok do SAND_COLOR_VARIATION = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_EMITTER_RATE"); ok do SAND_EMITTER_RATE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PLAYER_DRAG_PER_CELL"); ok do SAND_PLAYER_DRAG_PER_CELL = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PLAYER_DRAG_MAX"); ok do SAND_PLAYER_DRAG_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PLAYER_DRAG_Y_FACTOR"); ok do SAND_PLAYER_DRAG_Y_FACTOR = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PRESSURE_FORCE"); ok do SAND_PRESSURE_FORCE = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_PRESSURE_GAP_TOLERANCE"); ok do SAND_PRESSURE_GAP_TOLERANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_BURIAL_THRESHOLD"); ok do SAND_BURIAL_THRESHOLD = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DISPLACE_CHAIN"); ok do SAND_DISPLACE_CHAIN = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DISPLACE_PARTICLE_MAX"); ok do SAND_DISPLACE_PARTICLE_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SINK_SPEED"); ok do SAND_SINK_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_MOVE_PENALTY"); ok do SAND_MOVE_PENALTY = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_JUMP_PENALTY"); ok do SAND_JUMP_PENALTY = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_FALL_ACCEL_DIVISOR"); ok do SAND_FALL_ACCEL_DIVISOR = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_FALL_MAX_STEPS"); ok do SAND_FALL_MAX_STEPS = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_REPOSE_CHANCE"); ok do SAND_REPOSE_CHANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_WATER_SWAP_CHANCE"); ok do SAND_WATER_SWAP_CHANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_WALL_RUN_PENALTY"); ok do SAND_WALL_RUN_PENALTY = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_SPEED"); ok do SAND_PARTICLE_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_LIFETIME"); ok do SAND_PARTICLE_LIFETIME = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_SIZE"); ok do SAND_PARTICLE_SIZE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_GRAVITY"); ok do SAND_PARTICLE_GRAVITY = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_FRICTION"); ok do SAND_PARTICLE_FRICTION = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_MIN_SPEED"); ok do SAND_DUST_MIN_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_SPEED"); ok do SAND_DUST_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_LIFT"); ok do SAND_DUST_LIFT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_LIFETIME"); ok do SAND_DUST_LIFETIME = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_SIZE"); ok do SAND_DUST_SIZE = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DUST_LIGHTEN"); ok do SAND_DUST_LIGHTEN = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DUST_INTERVAL"); ok do SAND_DUST_INTERVAL = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_IMPACT_MIN_SPEED"); ok do SAND_IMPACT_MIN_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_IMPACT_MAX_SPEED"); ok do SAND_IMPACT_MAX_SPEED = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_IMPACT_RADIUS"); ok do SAND_IMPACT_RADIUS = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_IMPACT_PARTICLE_SPEED_MULT"); ok do SAND_IMPACT_PARTICLE_SPEED_MULT = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_IMPACT_PARTICLE_MIN"); ok do SAND_IMPACT_PARTICLE_MIN = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_IMPACT_PARTICLE_MAX"); ok do SAND_IMPACT_PARTICLE_MAX = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_EJECT_MAX_HEIGHT"); ok do SAND_EJECT_MAX_HEIGHT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_FOOTPRINT_STRIDE"); ok do SAND_FOOTPRINT_STRIDE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_FOOTPRINT_MIN_SPEED"); ok do SAND_FOOTPRINT_MIN_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DASH_DRAG_FACTOR"); ok do SAND_DASH_DRAG_FACTOR = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DASH_PARTICLE_MAX"); ok do SAND_DASH_PARTICLE_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DASH_PARTICLE_SPEED_MULT"); ok do SAND_DASH_PARTICLE_SPEED_MULT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_QUICKSAND_BASE_SINK"); ok do SAND_QUICKSAND_BASE_SINK = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_QUICKSAND_MOVE_MULT"); ok do SAND_QUICKSAND_MOVE_MULT = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SURFACE_SCAN_HEIGHT"); ok do SAND_SURFACE_SCAN_HEIGHT = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SURFACE_SMOOTH"); ok do SAND_SURFACE_SMOOTH = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_ENTER_THRESHOLD"); ok do SAND_SWIM_ENTER_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_EXIT_THRESHOLD"); ok do SAND_SWIM_EXIT_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_SURFACE_THRESHOLD"); ok do SAND_SWIM_SURFACE_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_GRAVITY_MULT"); ok do SAND_SWIM_GRAVITY_MULT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_UP_SPEED"); ok do SAND_SWIM_UP_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_DOWN_SPEED"); ok do SAND_SWIM_DOWN_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_SINK_SPEED"); ok do SAND_SWIM_SINK_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_DAMPING"); ok do SAND_SWIM_DAMPING = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_JUMP_FORCE"); ok do SAND_SWIM_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_MOVE_PENALTY"); ok do SAND_SWIM_MOVE_PENALTY = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_LERP_SPEED"); ok do SAND_SWIM_LERP_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_DRAG_FACTOR"); ok do SAND_SWIM_DRAG_FACTOR = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SWIM_JUMP_PARTICLE_COUNT"); ok do SAND_SWIM_JUMP_PARTICLE_COUNT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_HOP_FORCE"); ok do SAND_SWIM_HOP_FORCE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_SWIM_HOP_COOLDOWN"); ok do SAND_SWIM_HOP_COOLDOWN = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_SWIM_HOP_PARTICLE_COUNT"); ok do SAND_SWIM_HOP_PARTICLE_COUNT = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_WALL_MIN_HEIGHT"); ok do SAND_WALL_MIN_HEIGHT = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_WALL_ERODE_RATE"); ok do SAND_WALL_ERODE_RATE = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_WALL_JUMP_MULT"); ok do SAND_WALL_JUMP_MULT = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_IMPACT_PARTICLE_SPREAD"); ok do SAND_IMPACT_PARTICLE_SPREAD = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_IMPACT_PARTICLE_VEL_BIAS"); ok do SAND_IMPACT_PARTICLE_VEL_BIAS = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_VEL_BIAS_X"); ok do SAND_PARTICLE_VEL_BIAS_X = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_VEL_BIAS_Y"); ok do SAND_PARTICLE_VEL_BIAS_Y = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DASH_PARTICLE_VEL_BIAS"); ok do SAND_DASH_PARTICLE_VEL_BIAS = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_SPEED_RAND_MIN"); ok do SAND_PARTICLE_SPEED_RAND_MIN = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_PARTICLE_LIFETIME_RAND_MIN"); ok do SAND_PARTICLE_LIFETIME_RAND_MIN = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_SPEED_RAND_MIN"); ok do SAND_DUST_SPEED_RAND_MIN = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DUST_LIFETIME_RAND_MIN"); ok do SAND_DUST_LIFETIME_RAND_MIN = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_QUICKSAND_MAX_ACTIVITY"); ok do SAND_QUICKSAND_MAX_ACTIVITY = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_DEBUG_COLOR_LOW"); ok do SAND_DEBUG_COLOR_LOW = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_DEBUG_COLOR_MID"); ok do SAND_DEBUG_COLOR_MID = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_DEBUG_COLOR_HIGH"); ok do SAND_DEBUG_COLOR_HIGH = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_DEBUG_COLOR_CHUNK"); ok do SAND_DEBUG_COLOR_CHUNK = val
	if val, ok := engine.config_get_rgba(&config_sand, "SAND_DEBUG_COLOR_EMITTER"); ok do SAND_DEBUG_COLOR_EMITTER = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DEBUG_SLEEP_DIM"); ok do SAND_DEBUG_SLEEP_DIM = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DEBUG_PRESSURE_MAX"); ok do SAND_DEBUG_PRESSURE_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DEBUG_PRESSURE_DECAY"); ok do SAND_DEBUG_PRESSURE_DECAY = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DEBUG_HEATMAP_LOW"); ok do SAND_DEBUG_HEATMAP_LOW = val
	if val, ok := engine.config_get_f32(&config_sand, "SAND_DEBUG_HEATMAP_HIGH"); ok do SAND_DEBUG_HEATMAP_HIGH = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DEBUG_CHUNK_OUTLINE_ALPHA"); ok do SAND_DEBUG_CHUNK_OUTLINE_ALPHA = val
	if val, ok := engine.config_get_u8(&config_sand, "SAND_DEBUG_STATS_LINE_OFFSET"); ok do SAND_DEBUG_STATS_LINE_OFFSET = val
	if val, ok := engine.config_get_rgba(&config_sand, "WATER_COLOR"); ok do WATER_COLOR = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_COLOR_VARIATION"); ok do WATER_COLOR_VARIATION = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_COLOR_DEPTH_MAX"); ok do WATER_COLOR_DEPTH_MAX = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_FLOW_DISTANCE"); ok do WATER_FLOW_DISTANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_EMITTER_RATE"); ok do WATER_EMITTER_RATE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_PLAYER_DRAG_PER_CELL"); ok do WATER_PLAYER_DRAG_PER_CELL = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_PLAYER_DRAG_MAX"); ok do WATER_PLAYER_DRAG_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_PLAYER_DRAG_Y_FACTOR"); ok do WATER_PLAYER_DRAG_Y_FACTOR = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_BUOYANCY_FORCE"); ok do WATER_BUOYANCY_FORCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_BUOYANCY_THRESHOLD"); ok do WATER_BUOYANCY_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_MOVE_PENALTY"); ok do WATER_MOVE_PENALTY = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_JUMP_PENALTY"); ok do WATER_JUMP_PENALTY = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_ENTER_THRESHOLD"); ok do WATER_SWIM_ENTER_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_EXIT_THRESHOLD"); ok do WATER_SWIM_EXIT_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_SURFACE_THRESHOLD"); ok do WATER_SWIM_SURFACE_THRESHOLD = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_GRAVITY_MULT"); ok do WATER_SWIM_GRAVITY_MULT = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_UP_SPEED"); ok do WATER_SWIM_UP_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_DOWN_SPEED"); ok do WATER_SWIM_DOWN_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_FLOAT_SPEED"); ok do WATER_SWIM_FLOAT_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_DAMPING"); ok do WATER_SWIM_DAMPING = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SWIM_JUMP_FORCE"); ok do WATER_SWIM_JUMP_FORCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_CURRENT_FORCE"); ok do WATER_CURRENT_FORCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SHIMMER_SPEED"); ok do WATER_SHIMMER_SPEED = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_SHIMMER_PHASE"); ok do WATER_SHIMMER_PHASE = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_SHIMMER_BRIGHTNESS"); ok do WATER_SHIMMER_BRIGHTNESS = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_PRESSURE_MIN_DEPTH"); ok do WATER_PRESSURE_MIN_DEPTH = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_PRESSURE_SCAN_RANGE"); ok do WATER_PRESSURE_SCAN_RANGE = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_PRESSURE_CHANCE"); ok do WATER_PRESSURE_CHANCE = val
	if val, ok := engine.config_get_u8(&config_sand, "WATER_SURFACE_TENSION_DEPTH"); ok do WATER_SURFACE_TENSION_DEPTH = val
	if val, ok := engine.config_get_f32(&config_sand, "WATER_CONTACT_WET_CHANCE"); ok do WATER_CONTACT_WET_CHANCE = val
	if val, ok := engine.config_get_u8(&config_sand, "WET_SAND_DRY_STEPS"); ok do WET_SAND_DRY_STEPS = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_SPREAD_CHANCE"); ok do WET_SAND_SPREAD_CHANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_REPOSE_CHANCE"); ok do WET_SAND_REPOSE_CHANCE = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_WATER_SWAP_CHANCE"); ok do WET_SAND_WATER_SWAP_CHANCE = val
	if val, ok := engine.config_get_rgba(&config_sand, "WET_SAND_COLOR"); ok do WET_SAND_COLOR = val
	if val, ok := engine.config_get_u8(&config_sand, "WET_SAND_COLOR_VARIATION"); ok do WET_SAND_COLOR_VARIATION = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_PLAYER_DRAG_PER_CELL"); ok do WET_SAND_PLAYER_DRAG_PER_CELL = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_PLAYER_DRAG_MAX"); ok do WET_SAND_PLAYER_DRAG_MAX = val
	if val, ok := engine.config_get_f32(&config_sand, "WET_SAND_PLAYER_DRAG_Y_FACTOR"); ok do WET_SAND_PLAYER_DRAG_Y_FACTOR = val
}

config_sand: engine.Config

config_load_and_apply :: proc() {
	config, ok := engine.config_load("assets/game.ini")
	if !ok {
		fmt.eprintf("[sand config] Failed to load config\n")
		return
	}
	config_sand = config
	config_apply()
}

config_reload :: proc() -> bool {
	if len(config_sand.path) == 0 {
		config_load_and_apply()
		return true
	}
	if engine.config_reload(&config_sand) {
		config_apply()
		return true
	}
	return false
}
