# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```sh
odin run src/game/        # build + run
odin check src/game/      # type-check only (no binary)
```

No test framework — verify by running the game.

## Architecture

Odin lang, SDL3 (`vendor:sdl3`). Main package `src/game/`, reusable engine package `src/engine/` (imported via `"../engine"`).

### File layout

| File | Purpose |
|---|---|
| `PLAYER.md` | Mermaid `stateDiagram-v2` of the player FSM — **keep in sync** when adding/removing states or transitions |
| `src/game/main.odin` | Constants, `Game_State` struct, game lifecycle (`init`/`clean`), loop, rendering, `world_to_screen`/`world_to_screen_point` camera helpers |
| `src/game/player.odin` | `Player_State` enum, player constants, `PLAYER_COLOR` table, `player_init`, `player_fixed_update`, `player_sync_collider`, `player_trigger_impact`, `player_debug` (facing dir + FSM state text) |
| `src/game/player_graphics.odin` | `player_color`, `player_render` (4-layer visual deformation: velocity, look, run bob, impact bounce) |
| `src/game/player_sensor.odin` | `Player_Sensor` struct, `player_sensor_update`, `player_sensor_debug` |
| `src/game/player_physics.odin` | `player_apply_movement`, `player_physics_update` (separated-axis solver), `player_resolve_x`, `player_resolve_y`, `player_resolve_slopes`, `player_physics_debug` (collider + position + velocity) |
| `src/game/player_fsm_grounded.odin` | `player_fsm_grounded_init` + `player_fsm_grounded_enter` + `player_fsm_grounded_update` |
| `src/game/player_fsm_airborne.odin` | `player_fsm_airborne_init` + `player_fsm_airborne_update` |
| `src/game/player_fsm_dashing.odin` | `player_fsm_dashing_init` + `player_fsm_dashing_enter` + `player_fsm_dashing_update` |
| `src/game/player_fsm_dropping.odin` | `player_fsm_dropping_init` + `player_fsm_dropping_update` |
| `src/game/player_fsm_wall_slide.odin` | `player_fsm_wall_slide_init` + `player_fsm_wall_slide_update` |
| `src/game/player_fsm_wall_run_vertical.odin` | `player_fsm_wall_run_vertical_init` + `player_fsm_wall_run_vertical_enter` + `player_fsm_wall_run_vertical_update` + `player_fsm_wall_run_vertical_exit` |
| `src/game/player_fsm_wall_run_horizontal.odin` | `player_fsm_wall_run_horizontal_init` + `player_fsm_wall_run_horizontal_enter` + `player_fsm_wall_run_horizontal_update` |
| `src/game/debug.odin` | `Debug_State` enum, debug drawing helpers (`debug_collider_rect`, `debug_point`, `debug_vector`, `debug_text`, etc.), debug constants |
| `src/game/level.odin` | `Tile_Kind` enum, `Level` struct, BMP loading (`sdl.LoadBMP`), greedy collider merging, diagonal slope merging, tile rendering, `level_debug` (collider outlines + anchors) |
| `src/engine/camera.odin` | `Camera` struct, follow + clamp within level bounds |
| `src/engine/window.odin` | SDL3 window/renderer init, VSync, logical presentation (aspect ratio from primary display) |
| `src/engine/clock.odin` | Frame timing, fixed timestep accumulator, frame-rate cap via `sdl.Delay`, dt capped at 0.1s |
| `src/engine/input.odin` | Keyboard + gamepad input with action bindings, `is_down`/`is_pressed`/`axis` |
| `src/engine/collider.odin` | AABB overlap check (`collider_check_rect_vs_rect`), single-axis dynamic resolve (`collider_resolve_dynamic_rect`), axis-aligned raycasts (`collider_raycast_rect`, `collider_raycast_slope`), slope helpers (`collider_slope_surface_y`, `collider_slope_surface_x`, `collider_slope_contains_x`, `collider_slope_is_floor`) |
| `src/engine/fsm.odin` | Generic parametric FSM with enter/update/exit handlers, tracks `previous` state |

### Game loop (`main.odin`)

Fixed-timestep loop: `game_update(dt)` → N × `game_fixed_update(fixed_dt)` → `game_render()`.
- `game_update` — polls SDL events, feeds input system (`input_pre_update` → poll → `input_post_update`)
- `game_fixed_update` — delegates to `player_fixed_update`, then camera follow + clamp
- `game_render` — SDL rect drawing with 4-layer visual deformation (velocity, look, run bob, impact bounce)

Global `game: Game_State` struct holds all state. No ECS.

### Player FSM (`player.odin`)

Player states: `Grounded`, `Airborne`, `Dashing`, `Dropping`, `Wall_Run_Horizontal`, `Wall_Slide`, `Wall_Run_Vertical`.
Uses generic `engine.FSM(Game_State, Player_State)` via `player_fsm` — each state has an `update` handler returning `Maybe(Player_State)` to signal transitions (nil = stay). `fsm_transition` prevents self-transitions (same-state returns are no-ops). Enter/exit handlers are wired for states that need setup/teardown: `Grounded` (enter: reset wall run cooldown/used, snap to ground), `Dashing` (enter: set dash timers), `Wall_Run_Vertical` (enter: set wall_run_used/timer; exit: set wall run cooldown), `Wall_Run_Horizontal` (enter: set wall_run_used/timer/dir).

Each state lives in its own file (`player_fsm_<state>.odin`) with a `player_fsm_<state>_init` proc (registers handlers on `player_fsm`) and a `player_fsm_<state>_update` proc, plus optional `player_fsm_<state>_enter` / `player_fsm_<state>_exit` procs. `player_init` calls all init procs then `fsm_init`.

Each FSM state handler has a doc comment block immediately above it describing the state's behavior and listing all exit transitions with their conditions. When modifying a state handler, always keep its doc comment in sync with the implementation. Also update the Mermaid diagram in `PLAYER.md` whenever states or transitions change.

### State Transitions

| State | Exits to | Condition |
|---|---|---|
| **Grounded** | Dropping | on_platform && down && jump buffered |
| | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Wall_Run_Vertical | on_side_wall && WALL_RUN held |
| | Wall_Run_Horizontal | on_back_wall && WALL_RUN && horizontal input |
| | Wall_Run_Vertical | on_back_wall && WALL_RUN (default) |
| | Airborne | !on_ground (fell off) |
| **Airborne** | Dashing | DASH pressed && cooldown ready |
| | Grounded | on_ground && vel.y <= 0 |
| | Wall_Run_Horizontal | on_back_wall && WALL_RUN && horizontal input && !wall_run_used && cooldown ready |
| | Wall_Run_Vertical | on_back_wall && WALL_RUN && cooldown ready && !wall_run_used (default) |
| | Wall_Slide | on_back_wall && SLIDE held |
| | Wall_Run_Vertical | on_side_wall && WALL_RUN && cooldown ready && !wall_run_used && vel.y > 0 |
| | Wall_Slide | on_side_wall && SLIDE held |
| **Wall_Slide** | Airborne | jump buffered && on_side_wall (wall jump) |
| | Dashing | DASH pressed && cooldown ready |
| | Grounded | on_ground |
| | Airborne | !on_side_wall && !on_back_wall (detached) |
| | Airborne | on_back_wall && !on_side_wall && SLIDE released |
| **Wall_Run_Vertical** | Airborne | jump buffered (wall jump if side, straight jump if back) |
| | Dashing | DASH pressed && cooldown ready |
| | Wall_Slide | speed decayed or released && SLIDE held |
| | Airborne | speed decayed or released or detached |
| | Grounded | on_ground && vel.y <= 0 |
| **Wall_Run_Horizontal** | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Airborne | !on_back_wall (ran off) |
| | Grounded | on_ground && vel.y <= 0 |
| | Airborne | vel.y < -WALL_SLIDE_SPEED (falling fast) |
| | Airborne | on_side_wall (hit side wall) |
| | Wall_Slide | WALL_RUN released && SLIDE held |
| | Airborne | WALL_RUN released |
| **Dashing** | Grounded | timer expired && on_ground |
| | Wall_Run_Vertical | timer expired && on_side_wall && WALL_RUN && cooldown ready && !wall_run_used && vel.y > 0 |
| | Wall_Slide | timer expired && on_side_wall && SLIDE held |
| | Airborne | timer expired (default) |
| **Dropping** | Airborne | !in_platform |

Update order in `player_fixed_update`: tick timers → track dash dir → buffer jump → FSM dispatch → **physics update** (separated-axis + slope resolve) → sensor query. Impact detection is triggered inline by FSM handlers; visual deformation is applied in `game_render`.

Physics uses a **separated-axis solver** (`player_physics_update` in `player_physics.odin`): Move X → Sync → Slope resolve → Resolve X (walls) → Move Y → Sync → Resolve Y (ceiling, ground, platforms) → Slope resolve. Each axis integrates velocity, then resolves collisions. Slope resolve runs twice: once after X to handle lateral slope interactions, once after Y for final surface snap.

| Resolve step | Colliders | Notes |
|---|---|---|
| Slope resolve (post-X) | `level.slope_colliders` | Snaps to surface if `vel.y <= 0` and within snap distance |
| X walls | `level.side_wall_colliders` | Step-height tolerance: skip if player bottom >= wall top - `PLAYER_STEP_HEIGHT` |
| Y ceiling | `level.ceiling_colliders` | Always resolved |
| Y ground | `level.ground_colliders` | Only when `vel.y <= 0` |
| Y platforms | `level.platform_colliders` | One-way: skipped during `Dropping`, requires `player_pos.y >= platform_top - EPS` |
| Slope resolve (post-Y) | `level.slope_colliders` | Final snap; grounded uses `2 * PLAYER_STEP_HEIGHT` snap distance, others use `PLAYER_SLOPE_SNAP` |

`Player_Sensor` struct (`player_sensor`, in `player_sensor.odin`) caches per-frame environment queries (on_ground, on_ground_snap_y, on_platform, in_platform, on_slope, on_slope_dir, on_side_wall, on_side_wall_dir, on_side_wall_snap_x, on_back_wall) — queried **after** collision resolution so sensors reflect the resolved position. Ground detection uses a downward raycast from feet against `ground_colliders`; slope ground detection raycasts from `PLAYER_STEP_HEIGHT` above feet; wall detection uses horizontal raycasts from player upper-center against `side_wall_colliders` (separate loops). `on_ground` includes slopes and platforms. Used by all state handlers on the next frame.

### Level (`level.odin`)

Levels loaded from BMP files (1 pixel = 1 tile, `TILE_PX :: 8` pixels = `TILE_SIZE = 0.5m`). `sdl.LoadBMP` reads the image; pixels are mapped to `Tile_Kind` via a color palette. Solid tiles are classified by **exposed face** into three arrays: `ground_colliders` (non-solid above, no floor slope above), `ceiling_colliders` (non-solid below, no ceiling slope below), `side_wall_colliders` (interior tiles exposed left/right, excluding slope-adjacent faces). Classification uses pre-reclassification tile kinds so slope fill areas don't generate false colliders. Each array is greedy row-merged into minimal `Collider_Rect`s. Platform tiles are merged separately into `platform_colliders`. Back wall colliders use an **inverted mask** approach: every tile defaults to back wall, with only `.Window` tiles punched out as holes — this produces 1-2 large `back_wall_colliders` rects instead of many small ones. Slope tiles are merged diagonally via `level_merge_slopes` into `Collider_Slope` entries in `slope_colliders` — each diagonal run of same-kind tiles becomes one slope. Level defines its own dimensions; the camera scrolls within them.

### Slopes (`level.odin`, `player_physics.odin`)

45° slope tiles in 4 variants: `Slope_Right` (floor /), `Slope_Left` (floor \), `Slope_Ceil_Left` (ceiling /), `Slope_Ceil_Right` (ceiling \). BMP palette: red `{255,0,0}`, blue `{0,0,255}`, dark red `{128,0,0}`, dark blue `{0,0,128}`.

`collider_slope_surface_y(slope, world_x)` computes the surface height at any X within the tile. Floor slopes push the player up; ceiling slopes push down. Collision runs in `player_resolve_slopes` (`player_physics.odin`) — called twice per frame: once after X move (lateral slope interactions) and once after Y move (final surface snap). Only active when `vel.y <= 0`. Grounded state uses a larger snap distance (`2 * PLAYER_STEP_HEIGHT`) than airborne (`PLAYER_SLOPE_SNAP`) for smoother traversal.

Downhill following: snap-based — slope resolve snaps the player to the surface if slightly above (gap < snap distance), handling both downhill traversal and flat-to-slope transitions.

Speed modifiers in `grounded_update`: `PLAYER_SLOPE_UPHILL_FACTOR` (0.75×) slows uphill, `PLAYER_SLOPE_DOWNHILL_FACTOR` (1.25×) speeds downhill.

Slopes render as filled triangles via `sdl.RenderGeometry` using `COLOR_TILE_SOLID`, with `COLOR_TILE_BACK_WALL` background rectangles behind them.

### Camera (`engine/camera.odin`)

2D viewport that follows the player. `camera_follow` snaps to target; `camera_clamp` keeps within level bounds (centers on axis if level is smaller than viewport). All rendering uses `world_to_screen` / `world_to_screen_point` which subtract the camera bottom-left and flip Y.

## Coordinate & Unit Conventions

- **All physics in meters.** `PPM: f32 : 16` (pixels per meter, power of 2 for exact f32 math) converts to pixel space.
- Physics constants are defined in pixel-intuitive values divided by PPM (e.g. `PLAYER_JUMP_FORCE: f32 : 700.0 / PPM`).
- Y-axis points **up** in game logic. Rendering flips via `world_to_screen(world_pos, world_size)` (camera-relative).
- `TILE_PX :: 8`, `TILE_SIZE: f32 : 0.5` — each BMP pixel = one tile = 0.5m.
- `LOGICAL_H :: 480`, logical width computed from display aspect ratio at runtime (`window_compute_logical_w`).
- `WINDOW_SCALE :: 2` — integer multiplier on logical resolution.
- `FPS :: 60`, `FIXED_STEPS :: 4` — fixed timestep = `1 / (FIXED_STEPS * FPS)`.
- `Collider_Rect.pos` = **center**, `size` = full width/height.
- `player_pos` = player's **bottom-center**; collider pos is offset by `PLAYER_SIZE/2` upward. `player_sync_collider()` keeps collider in sync.
- Time values (durations, cooldowns) in **seconds** — no PPM conversion.

## Player Abilities

| Ability | Key constants |
|---|---|
| Run | `PLAYER_RUN_SPEED`, movement via `math.lerp` with factor `15.0 * dt` |
| Jump | `PLAYER_JUMP_FORCE`, with `PLAYER_JUMP_BUFFER_DURATION` input buffering |
| Coyote time | `PLAYER_COYOTE_TIME_DURATION` — allows jump shortly after leaving ground |
| Wall slide | `PLAYER_WALL_SLIDE_SPEED` clamp, detected via horizontal raycasts with `PLAYER_WALL_JUMP_EPS` range. Unified for side and back walls via `Wall_Slide` state |
| Wall run vertical | `PLAYER_WALL_RUN_VERTICAL_SPEED`, `PLAYER_WALL_RUN_VERTICAL_DECAY` (exponential), `PLAYER_WALL_RUN_COOLDOWN`. Side wall requires `vel.y > 0` (upward momentum) to enter from airborne |
| Wall run horizontal | `PLAYER_WALL_RUN_HORIZONTAL_SPEED`, `PLAYER_WALL_RUN_HORIZONTAL_LIFT`, `PLAYER_WALL_RUN_HORIZONTAL_GRAV_MULT` (parabolic arc along back wall) |
| Wall jump | `PLAYER_WALL_JUMP_FORCE` (1.5× jump), 0.75× vertical component |
| Dash | `PLAYER_DASH_SPEED` (4× run), `PLAYER_DASH_DURATION`, `PLAYER_DASH_COOLDOWN`, direction-locked |
| Drop through | Down + jump on platform → nudge down and enter `Dropping` state |
| Gravity | `GRAVITY` with 3× multiplier when ascending with jump released (variable jump height / short hop). Grounded state zeroes Y velocity each frame to stay flush; slope snap keeps player on surface going downhill |
| Step height | `PLAYER_STEP_HEIGHT` — tolerance to step over small obstacles and slope tops; also used for wall collision filtering and slope snap distance when grounded |
| Impact bounce | Damped cosine spring deformation on ground/wall/platform impact. `PLAYER_IMPACT_SCALE`, `PLAYER_IMPACT_FREQ`, `PLAYER_IMPACT_DECAY`, `PLAYER_IMPACT_THRESHOLD`. Purely visual — triggered by `player_trigger_impact`, "stronger wins" policy prevents small bumps from resetting ongoing bounces |

## Debug Overlays

Cycle with **F3** (`DEBUG` action) through `NONE` → `PLAYER` → `BACKGROUND` → `ALL`. Rendered in `game_render_debug()`. Drawing helpers in `src/game/debug.odin`.

- `PLAYER` — player collider, position, facing direction, velocity vector, FSM state text, sensor rays
- `BACKGROUND` — level collider outlines (ground, ceiling, side wall, platform, back wall, slope) + element anchors
- `ALL` — all of the above
- FPS counter and sensor readout appear in all non-NONE debug modes

| Overlay | Color | Description |
|---|---|---|
| Ground collider outlines | Green | AABB wireframes for ground colliders + player collider |
| Ceiling collider outlines | Dark red | AABB wireframes for ceiling colliders |
| Side wall collider outlines | Orange | AABB wireframes for side wall colliders |
| Platform outlines | Blue | Platform collider wireframes |
| Back wall outlines | Dark cyan | Back wall collider wireframes |
| Slope outlines | Green | Triangle wireframes for slope colliders |
| Sensor rays | Yellow (hit) / Gray (miss) | Ground ray (downward) + wall rays (left/right) with hit marker |
| Element anchors | White | Cross at `.pos` center of ground, ceiling, side wall, and platform colliders |
| Player position | Magenta | Cross at `player_pos` (bottom-center) |
| Facing direction | Cyan | Vector from player center in `player_dash_dir` |
| Velocity vector | Yellow-green | Vector from player center, scaled by `DEBUG_VEL_SCALE` |
| FSM current state | White | Text centered above player via `sdl.RenderDebugText` |
| FSM previous state | Muted gray | Text centered below current state label |
| FPS counter | White | Top-left corner, `1.0 / dt` |
| Sensor readout | White | Top-left column below FPS, all sensor booleans + timers |

Constants prefixed `DEBUG_COLOR_*` (colors) and `DEBUG_*` (sizes/scales).

## Input Bindings

Actions: `MOVE_UP`, `MOVE_DOWN`, `MOVE_LEFT`, `MOVE_RIGHT`, `JUMP`, `DASH`, `WALL_RUN`, `SLIDE`, `DEBUG`, `QUIT`.

Keyboard: WASD move, Space jump, L dash, LShift wall run, LCtrl slide, F3 debug, Esc quit.
Gamepad: left stick / dpad move, South(A) jump, North(Y) dash, RB wall run, LB slide, Back debug, Start quit.
Input auto-switches between keyboard/gamepad based on last device event. Release events always clear `is_down` regardless of active input type. Axis input is normalized for diagonals. Gamepad axis deadzone: `INPUT_BINDING_GAMEPAD_AXIS_DEADZONE` (0.1).
