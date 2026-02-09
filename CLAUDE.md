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
| `src/game/player.odin` | `Player_State` enum, `Player_Sensor` struct, FSM handlers, movement & collision helpers |
| `src/game/level.odin` | `Tile_Kind` enum, `Level` struct, BMP loading (`sdl.LoadBMP`), greedy collider merging, tile rendering |
| `src/engine/camera.odin` | `Camera` struct, follow + clamp within level bounds |
| `src/engine/window.odin` | SDL3 window/renderer init, VSync, logical presentation (aspect ratio from primary display) |
| `src/engine/clock.odin` | Frame timing, fixed timestep accumulator, frame-rate cap via `sdl.Delay`, dt capped at 0.1s |
| `src/engine/input.odin` | Keyboard + gamepad input with action bindings, `is_down`/`is_pressed`/`axis` |
| `src/engine/collider.odin` | AABB overlap check (`collider_check_rect_vs_rect`), single-axis dynamic resolve (`collider_resolve_dynamic_rect`) |
| `src/engine/fsm.odin` | Generic parametric FSM with enter/update/exit handlers, tracks `previous` state |

### Game loop (`main.odin`)

Fixed-timestep loop: `game_update(dt)` → N × `game_fixed_update(fixed_dt)` → `game_render()`.
- `game_update` — polls SDL events, feeds input system (`input_pre_update` → poll → `input_post_update`)
- `game_fixed_update` — delegates to `player_fixed_update`, then camera follow + clamp
- `game_render` — SDL rect drawing with 4-layer visual deformation (velocity, look, run bob, impact bounce)

Global `game: Game_State` struct holds all state. No ECS.

### Player FSM (`player.odin`)

Player states: `Grounded`, `Airborne`, `Wall_Slide`, `Wall_Run`, `Dashing`, `Dropping`, `Back_Wall_Run`, `Back_Wall_Climb`, `Back_Wall_Slide`.
Uses generic `engine.FSM(Game_State, Player_State)` via `player_fsm` — each state has an `update` handler returning `Maybe(Player_State)` to signal transitions (nil = stay). `fsm_transition` prevents self-transitions (same-state returns are no-ops). Currently no enter/exit handlers are wired.

Each FSM state handler has a doc comment block immediately above it describing the state's behavior and listing all exit transitions with their conditions. When modifying a state handler, always keep its doc comment in sync with the implementation. Also update the Mermaid diagram in `PLAYER.md` whenever states or transitions change.

### State Transitions

| State | Exits to | Condition |
|---|---|---|
| **Grounded** | Dropping | on_platform && down && jump buffered |
| | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Wall_Run | on_wall && WALL_RUN held |
| | Back_Wall_Run | on_back_wall && WALL_RUN && horizontal input && !back_run_used |
| | Back_Wall_Climb | on_back_wall && WALL_RUN (default) |
| | Airborne | !on_ground (fell off) |
| **Airborne** | Dashing | DASH pressed && cooldown ready |
| | Grounded | on_ground |
| | Wall_Run | on_wall && WALL_RUN && cooldown ready && !wall_run_used && vel.y > 0 |
| | Wall_Slide | on_wall && SLIDE held |
| | Back_Wall_Run | on_back_wall && WALL_RUN && horizontal input && !back_run_used && cooldown ready |
| | Back_Wall_Climb | on_back_wall && WALL_RUN && cooldown ready (default) |
| | Back_Wall_Slide | on_back_wall && SLIDE held |
| **Wall_Slide** | Airborne | jump buffered (wall jump) |
| | Wall_Run | WALL_RUN held && cooldown ready && !wall_run_used && vel.y > 0 |
| | Dashing | DASH pressed && cooldown ready |
| | Grounded | on_ground |
| | Airborne | !on_wall (detached) |
| **Wall_Run** | Airborne | jump buffered (wall jump) |
| | Dashing | DASH pressed && cooldown ready |
| | Wall_Slide | speed decayed or released && SLIDE held |
| | Airborne | speed decayed or released or detached |
| | Grounded | on_ground |
| **Dashing** | Grounded | timer expired && on_ground |
| | Wall_Run | timer expired && on_wall && WALL_RUN && !wall_run_used && vel.y > 0 |
| | Wall_Slide | timer expired && on_wall && SLIDE held |
| | Airborne | timer expired (default) |
| **Dropping** | Airborne | coyote jump |
| | Dashing | DASH pressed && cooldown ready |
| | Airborne | !in_platform |
| **Back_Wall_Run** | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Airborne | !on_back_wall or falling fast or hit side wall |
| | Grounded | on_ground |
| **Back_Wall_Climb** | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Airborne | !on_back_wall or speed decayed or released |
| | Back_Wall_Slide | speed decayed or released && SLIDE held |
| | Grounded | on_ground |
| **Back_Wall_Slide** | Airborne | jump buffered |
| | Dashing | DASH pressed && cooldown ready |
| | Airborne | !on_back_wall or SLIDE released |
| | Grounded | on_ground |
| | Back_Wall_Climb | WALL_RUN && cooldown ready |

Update order in `player_fixed_update`: tick timers → buffer jump → track dash dir → FSM dispatch → **separated-axis physics** → **slope resolve** → sensor query → impact detection → visual deformation.

Physics uses a **separated-axis solver** (`collider_resolve_dynamic_rect`): Move X → Resolve X (walls) → Move Y → Resolve Y (ground/ceiling, then one-way platforms) → Slope resolve. Each axis integrates velocity, then resolves collisions inline — no separate integration step at the end.

| Resolve step | Axis | Colliders | Notes |
|---|---|---|---|
| X walls | 0 | `level.wall_colliders` | Always resolved (including Wall_Slide/Wall_Run) |
| Y solids | 1 | `level.ground_colliders` | Handles both floor and ceiling via direction check |
| Y platforms | 1 | `level.platform_colliders` | One-way: skipped during `Dropping`, requires `vel.y <= 0` and `start_pos.y >= platform_top` |
| Slopes | post | `level.slope_tiles` | Heightmap-based: floor slopes push up, ceiling slopes push down. Downhill snap prevents bouncing |

`Player_Sensor` struct (`player_sensor`) caches per-frame environment queries (on_ground, on_platform, in_platform, on_slope, on_left/right_wall, on_wall) — queried **after** collision resolution so sensors reflect the resolved position. `on_ground` includes slopes. Used by all state handlers on the next frame.

### Level (`level.odin`)

Levels loaded from BMP files (1 pixel = 1 tile, `TILE_PX :: 8` pixels = `TILE_SIZE = 0.5m`). `sdl.LoadBMP` reads the image; pixels are mapped to `Tile_Kind` via a color palette. Greedy row-merge converts the tile grid into minimal `Collider_Rect` arrays (`ground_colliders`, `wall_colliders`, `platform_colliders`). Solid tiles go into both ground and wall arrays (axis-locked resolve passes handle the distinction). Slope tiles are stored individually as `Slope_Tile` in `slope_tiles` (not merged). Level defines its own dimensions; the camera scrolls within them.

### Slopes (`level.odin`, `player.odin`)

45° slope tiles in 4 variants: `Slope_Right` (floor /), `Slope_Left` (floor \), `Slope_Ceil_Left` (ceiling /), `Slope_Ceil_Right` (ceiling \). BMP palette: red `{255,0,0}`, blue `{0,0,255}`, dark red `{128,0,0}`, dark blue `{0,0,128}`.

`slope_surface_y(slope, world_x)` computes the surface height at any X within the tile. Floor slopes push the player up; ceiling slopes push down. Collision runs as a post-processing step after AABB resolve (`player_resolve_slopes`). Floor slope sampling uses the most-restrictive edge (leading edge going uphill) for robust handling of players wider than one tile.

Downhill snap (`PLAYER_SLOPE_SNAP`) prevents bouncing when walking downhill by snapping the player to the surface if they were on a slope last frame and are now slightly above one.

Speed modifiers in `grounded_update`: `PLAYER_SLOPE_UPHILL_FACTOR` (0.75×) slows uphill, `PLAYER_SLOPE_DOWNHILL_FACTOR` (1.25×) speeds downhill.

Slopes render as filled triangles via `sdl.RenderGeometry` using `COLOR_TILE_SOLID`.

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
| Wall slide | `PLAYER_WALL_SLIDE_SPEED` clamp, detected via inflated `PLAYER_WALL_JUMP_EPS` sensor |
| Wall run | `PLAYER_WALL_RUN_SPEED`, `PLAYER_WALL_RUN_DECAY` (exponential), `PLAYER_WALL_RUN_COOLDOWN`. Requires `vel.y > 0` (upward momentum) to enter — cannot transition from wall slide or horizontal dash |
| Wall jump | `PLAYER_WALL_JUMP_FORCE` (1.5× jump), 0.75× vertical component |
| Dash | `PLAYER_DASH_SPEED` (4× run), `PLAYER_DASH_DURATION`, `PLAYER_DASH_COOLDOWN`, direction-locked |
| Drop through | Down + jump on platform → nudge down and enter `Dropping` state |
| Gravity | `GRAVITY` with 3× multiplier when ascending with jump released (variable jump height / short hop). Grounded state zeroes Y velocity each frame to stay flush |
| Impact bounce | Damped cosine spring deformation on ground/wall/platform impact. `PLAYER_IMPACT_SCALE`, `PLAYER_IMPACT_FREQ`, `PLAYER_IMPACT_DECAY`, `PLAYER_IMPACT_THRESHOLD`. Purely visual — triggered by `player_trigger_impact`, "stronger wins" policy prevents small bumps from resetting ongoing bounces |

## Debug Overlays

Toggle with **F3** (`DEBUG` action). Rendered in `game_render_debug()`.

| Overlay | Color | Description |
|---|---|---|
| Collider outlines | Green | AABB wireframes for all colliders + slope diagonals and bounding boxes |
| Wall sensor | Yellow | Player wall-jump detection zone |
| Element anchors | White | Cross at `.pos` center of every level collider |
| Player position | Magenta | Cross at `player_pos` (bottom-center) |
| Facing direction | Cyan | Horizontal line from player center in `player_dash_dir` |
| Velocity vector | Yellow-green | Line from player center, scaled by `DEBUG_VEL_SCALE` |
| FSM current state | White | Text centered above player via `sdl.RenderDebugText` |
| FSM previous state | Muted gray | Text centered below current state label |
| FPS counter | White | Top-left corner, `1.0 / dt` |
| Sensor readout | White | Top-right corner, ground/platform/in_plat/wall_l/wall_r/on_slope/slope_dir booleans |

Constants prefixed `COLOR_DEBUG_*` (colors) and `DEBUG_*` (sizes/scales).

## Input Bindings

Actions: `MOVE_UP`, `MOVE_DOWN`, `MOVE_LEFT`, `MOVE_RIGHT`, `JUMP`, `DASH`, `WALL_RUN`, `DEBUG`, `QUIT`.

Keyboard: WASD move, Space jump, L dash, LShift wall run, F3 debug, Esc quit.
Gamepad: left stick / dpad move, South(A) jump, North(Y) dash, RB wall run, Back debug, Start quit.
Input auto-switches between keyboard/gamepad based on last device event. Release events always clear `is_down` regardless of active input type. Axis input is normalized for diagonals. Gamepad axis deadzone: `INPUT_BINDING_GAMEPAD_AXIS_DEADZONE` (0.1).
