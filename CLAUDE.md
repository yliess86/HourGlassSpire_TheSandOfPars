# CLAUDE.md

## Build & Run

```sh
odin run build/                      # gen_config + build (-debug) + run
odin run build/ -- run release       # gen_config + build (-o:speed) + run
odin run build/ -- build             # gen_config + build (-debug) only
odin run build/ -- build release     # gen_config + build (-o:speed) only
odin run build/ -- check             # gen_config + type-check only
odin run build/ -- gen               # regenerate config.odin only
odin run build/ -- align             # align = signs and # comments in game.ini
odin run build/ -- version           # stamp current UTC date/time into game.ini
odin run build/ -- release           # stamp version, commit, tag (release-<hash>), and push
odin run build/ -- dist              # build release for current platform
odin run build/ -- dist windows_x64  # cross-compile for Windows x64
odin run build/ -- dist macos_arm64  # cross-compile for macOS ARM64
odin run build/ -- dist linux_x64    # cross-compile for Linux x64
odin run build/ -- setup             # download SDL3 libs for current platform
odin run build/ -- clean             # remove bin/, dist/, and libs/
odin run build/ -- clean bin dist    # remove specific targets (bin, dist, libs)
```

No test framework — verify by running game.

**Before every commit**, run `odin run build/ -- version` to stamp UTC date/time into `assets/game.ini` and regenerate `src/game/config.odin`. Stage both files.

## Architecture

Odin, SDL3 (`vendor:sdl3`). Main package `src/game/`, engine `src/engine/` (`"../engine"`).

### File layout

| File | Purpose |
|---|---|
| `PLAYER.md` | Mermaid `stateDiagram-v2` of player FSM — **keep in sync** on state/transition changes |
| `assets/game.ini` | All game constants — hot-reloadable with F5 |
| `src/game/config.odin` | **AUTO-GENERATED** from `game.ini` by `build/`. Do not edit manually |
| `build/main.odin` | Build entry: CLI parsing, dev build + run, `clean` |
| `build/sys.odin` | OS helpers: `sys_run`, `sys_make_dir`, `sys_copy`, `sys_download` |
| `build/config.odin` | Config codegen: parses `game.ini`, generates `config.odin`. Supports `proc_prefix` and same-package generation |
| `build/align.odin` | INI file alignment: aligns `=` signs and `#` comments in `game.ini` |
| `build/version.odin` | Version stamping: `VERSION_NAME`, UTC date/time + MD5 hash |
| `build/dist.odin` | Distribution: dist targets, SDL3 download/setup, release bundle |
| `src/engine/config.odin` | INI parser, expression evaluator, config load/reload/get API |
| `src/engine/camera.odin` | `Camera` struct, `camera_world_to_screen`/`_point`, dead-zone follow + boundary decel + clamp |
| `src/engine/window.odin` | SDL3 window/renderer init, VSync, logical presentation |
| `src/engine/clock.odin` | Frame timing, fixed timestep accumulator, dt capped at 0.1s |
| `src/engine/input.odin` | Generic `Input($Action)` with bindings, deadzone; `is_down`/`is_pressed`/`axis`. `Input_Family` enum, `INPUT_BUTTON_NAMES`, `input_family` |
| `src/engine/particle.odin` | `Particle`, `Particle_Pool` (#soa dynamic), emit/update/destroy |
| `src/engine/physics.odin` | `Physics_Body`, `Physics_Static_Geometry`, separated-axis collision solver, raycasts, slope helpers |
| `src/engine/sand.odin` | `Sand_Material`, `Sand_Cell`/`Sand_World`, grid accessors, sim, interaction, emitters, chunks |
| `src/engine/sand_config.odin` | **AUTO-GENERATED** sand constants from `game.ini`. Do not edit manually |
| `src/game/main.odin` | Entry point: game loop (fixed-timestep update, render, present) |
| `src/game/game.odin` | `Game_State` struct, `game` global, lifecycle, update/render, `game_world_to_screen` wrappers |
| `src/game/player.odin` | `Player_State` enum, `Player`/`Player_Sensor` structs, `player_init`/`player_fixed_update`, state machine, physics solver, sensor queries, footprints |
| `src/game/player_graphics.odin` | `player_color`, 4-layer visual deformation, particle emit/update/render, debug overlays |
| `src/game/debug.odin` | `Debug_State` enum, drawing helpers, `debug_camera`, controls overlay |
| `src/game/level.odin` | BMP loading, tile classification by exposed face, greedy collider merging, slope merging, rendering |
| `src/game/input.odin` | `Input_Action` enum, `INPUT_DEFAULT_BINDINGS`, `input_binding_apply` |
| `src/game/sand_graphics.odin` | Camera-culled rendering: sand opaque with color variants, water alpha-blended with depth gradient + shimmer, surface smoothing |

### Game loop

Fixed-timestep: `game_update(dt)` → N × `game_fixed_update(fixed_dt)` → `game_render()`.
- `game_update` — SDL events → input system
- `game_fixed_update` — player → sand interaction → sand sim → emitters → particles → camera
- `game_render` — level tiles → particles → player → sand (back-to-front)

Global `game: Game_State`. Player nested as `game.player: Player` with sub-structs: `body` (Physics_Body), `abilities`, `graphics`, `state`/`previous_state`, `sensor`. Sand state: `game.sand_world: engine.Sand_World`. All player procs take `player: ^Player`; call sites pass `&game.player`.

### Player State Machine

States: `Grounded`, `Airborne`, `Dashing`, `Dropping`, `Sand_Swim`, `Swimming`, `Wall_Run_Horizontal`, `Wall_Slide`, `Wall_Run_Vertical`.

Plain `switch player.state` dispatch in file-private `state_update` (in `player.odin`). Each case calls a private `update_<state>` proc returning `Maybe(Player_State)` for transitions (nil = stay). `state_transition` prevents self-transitions, runs exit/enter logic. `Sand_Swim` + `Swimming` share `update_submerged`.

**Keep each state's doc comment in sync with implementation. Update `PLAYER.md` on state/transition changes.**

### State Transitions

| State | Exits to | Condition |
|---|---|---|
| **Grounded** | Dropping | on_platform && down && jump buffered |
| | Airborne | jump buffered |
| | Dashing | DASH && cooldown ready |
| | Sand_Swim | sand_immersion > enter threshold |
| | Swimming | water_immersion > enter threshold |
| | Wall_Run_Vertical | on_side_wall && WALL_RUN |
| | Wall_Run_Horizontal | on_back_wall && WALL_RUN && horizontal input |
| | Wall_Run_Vertical | on_back_wall && WALL_RUN (default) |
| | Airborne | !on_ground |
| **Airborne** | Dashing | DASH && cooldown ready |
| | Grounded | on_ground && vel.y <= 0 |
| | Sand_Swim | sand_immersion > enter threshold |
| | Swimming | water_immersion > enter threshold |
| | Wall_Run_Horizontal | on_back_wall && WALL_RUN && h-input && !used && cooldown ready |
| | Wall_Run_Vertical | on_back_wall && WALL_RUN && cooldown && !used (default) |
| | Wall_Slide | on_back_wall && SLIDE |
| | Wall_Run_Vertical | on_side_wall && WALL_RUN && cooldown && !used && vel.y > 0 |
| | Wall_Slide | on_side_wall && SLIDE |
| **Wall_Slide** | Airborne | jump buffered && on_side_wall (wall jump) |
| | Dashing | DASH && cooldown ready |
| | Grounded | on_ground |
| | Airborne | !on_side_wall && !on_back_wall |
| | Airborne | on_back_wall && !on_side_wall && SLIDE released |
| **Wall_Run_Vertical** | Airborne | jump buffered (wall jump side / straight back) |
| | Dashing | DASH && cooldown ready |
| | Wall_Slide | speed decayed/released && SLIDE |
| | Airborne | speed decayed/released/detached |
| | Grounded | on_ground && vel.y <= 0 |
| **Wall_Run_Horizontal** | Airborne | jump buffered |
| | Dashing | DASH && cooldown ready |
| | Airborne | !on_back_wall |
| | Grounded | on_ground && vel.y <= 0 |
| | Airborne | vel.y < -WALL_SLIDE_SPEED |
| | Airborne | on_side_wall |
| | Wall_Slide | WALL_RUN released && SLIDE |
| | Airborne | WALL_RUN released |
| **Swimming** | Airborne | jump && immersion < surface threshold |
| | Dashing | DASH && cooldown ready |
| | Grounded | on_ground && immersion < exit threshold |
| | Airborne | immersion < exit threshold |
| **Sand_Swim** | Airborne | jump pressed near surface (sand_immersion < surface threshold) |
| | Dashing | DASH && cooldown ready |
| | Grounded | on_ground && sand_immersion < exit threshold |
| | Airborne | sand_immersion < exit threshold |
| **Dashing** | Sand_Swim | timer expired && sand_immersion > enter threshold |
| | Swimming | timer expired && water_immersion > enter threshold |
| | Grounded | timer expired && on_ground |
| | Wall_Run_Vertical | timer expired && on_side_wall && WALL_RUN && cooldown && !used && vel.y > 0 |
| | Wall_Slide | timer expired && on_side_wall && SLIDE |
| | Airborne | timer expired (default) |
| **Dropping** | Airborne | !in_platform |

### Physics

Update order in `player_fixed_update`: tick timers → track dash dir → buffer jump → FSM → **physics** → sensor query.

Separated-axis solver: Move X → Sync → Slope resolve → Resolve X → Move Y → Sync → Resolve Y → Slope resolve.

| Resolve step | Colliders | Notes |
|---|---|---|
| Slope (post-X) | `slope_colliders` | Floor: snap feet if vel.y <= 0. Ceiling: push down on head penetration |
| X walls | `side_wall_colliders` | Step-height tolerance: skip if bottom >= wall top - `PLAYER_STEP_HEIGHT` |
| Y ceiling | `ceiling_colliders` | Always |
| Y ground | `ground_colliders` | Only vel.y <= 0 |
| Y platforms | `platform_colliders` | One-way: skip during Dropping, requires pos.y >= top - EPS |
| Slope (post-Y) | `slope_colliders` | Floor: grounded uses `2*STEP_HEIGHT` snap, else `SLOPE_SNAP`. Ceiling: push down |

**Sensor** (`player.sensor`): caches per-frame queries **after** collision resolution — on_ground (includes slopes/platforms/sand), on_platform, in_platform, on_slope/dir, on_sand, sand_immersion (0-1), on_water, water_immersion (0-1), on_side_wall/dir/snap_x, on_back_wall, on_sand_wall (vertical sand column acts as wall). Ground = downward raycast from feet; slope = raycast from STEP_HEIGHT above; walls = horizontal raycasts from upper-center; sand walls = `SAND_WALL_MIN_HEIGHT` contiguous sand/wet-sand cells when no solid side wall.

### Level

BMP files (1 px = 1 tile, `TILE_SIZE = 0.5m`). Pixels mapped to `Level_Tile_Kind` via color palette. Solid tiles classified by exposed face → `ground_colliders`, `ceiling_colliders`, `side_wall_colliders` (greedy row-merged). Platforms merged separately. Back walls use inverted mask (Empty = holes → 1-2 large rects). Slopes merged diagonally via `level_merge_slopes`.

**Slope variants:** `Slope_Right` (floor /), `Slope_Left` (floor \), `Slope_Ceil_Left` (ceiling /), `Slope_Ceil_Right` (ceiling \). BMP: red `{255,0,0}`, blue `{0,0,255}`, dark red `{128,0,0}`, dark blue `{0,0,128}`. Render as filled triangles via `sdl.RenderGeometry`.

**Sand/water tile extraction during load:** `Sand_Pile` yellow `{255,255,0}` → `.Back_Wall`. `Sand_Emitter` orange `{255,128,0}` → `.Solid`. `Water_Pile` cyan `{0,255,255}` → `.Back_Wall`. `Water_Emitter` green `{0,255,128}` → `.Solid`. Positions stored, consumed by `sand_init`.

### Slopes

`collider_slope_surface_y(slope, x)` = surface height at X. `player_physics_resolve_slopes` runs twice/frame (post-X, post-Y). Floor slopes (vel.y <= 0): snap feet; grounded `2*STEP_HEIGHT`, airborne `SLOPE_SNAP`. Ceiling slopes: push down on head penetration, zero vel.y.

Downhill: snap-based — resolve snaps player to surface if gap < snap distance. Speed mods in grounded: `SLOPE_UPHILL_FACTOR` (0.75x), `SLOPE_DOWNHILL_FACTOR` (1.25x). Dash: uphill decomposes along 45deg, ramps off top; downhill lifts off with `vel.y = EPS`.

### Sand System

CA sand/water sim in `src/engine/sand.odin` on level-aligned grid (`SAND_CELLS_PER_TILE` cells per tile, configurable resolution). `Sand_World` stores flat `[]Sand_Cell` (y*w+x, y=0=bottom) + parallel `[]Sand_Slope_Kind` (immutable structural data from level) + chunks + emitters + player footprint cache. Grid dimensions = level dimensions × `SAND_CELLS_PER_TILE`. Cell size = `TILE_SIZE / SAND_CELLS_PER_TILE`. Distance/accumulation constants in `game.ini` auto-scale with CPT via expressions. Data-driven material properties (`Sand_Material_Props`, `Sand_Behavior` enum, `SAND_MAT_PROPS` table) unify sim dispatch.

**Materials:** Empty, Solid (level), Sand (falls), Water (flows horizontally, buoyant), Platform (one-way), Wet_Sand (sand that contacted water: heavier, stickier, darker; dries without water).

**Sim:** Every `SAND_SIM_INTERVAL` fixed steps. Bottom-to-top, alternating L/R parity. Sand: down → diagonal; sinks through water. Wet sand: same as sand but lower repose chance (stickier), higher water swap chance. Water: down → diagonal → horizontal (up to `WATER_FLOW_DISTANCE` cells); wets adjacent sand on contact (`WATER_CONTACT_WET_CHANCE`); surface tension prevents thin film spreading. On slope cells, sand/water slides only in the slope's downhill diagonal direction. Wet sand dries after `WET_SAND_DRY_STEPS` without adjacent water; spreads wetness to neighbors (`WET_SAND_SPREAD_CHANCE`). Sleep after `SAND_SLEEP_THRESHOLD` idle steps; movement wakes 8 neighbors. Parity flag prevents double-moves. Player footprint blocking: sim and displacement respect cached player bounds (`sand_is_player_cell`), preventing sand/water from moving into the player.

**Chunks:** 32x32 partitions. Track active_count, dirty/needs_sim. Dirty propagates to 8-neighbors. Skip chunks with needs_sim=false.

**Emitters:** Accumulate fractional particles at `SAND_EMITTER_RATE`/`WATER_EMITTER_RATE`. Spawn one tile below when ready.

**Player interaction** (`engine.sand_apply_physics` each fixed step, called directly from `player_fixed_update`):
1. **Impact craters** — landing speed stored in `abilities.impact_pending`; crater radius + particle count scale with impact factor. Ejects sand upward around footprint
2. **Displacement** — push sand/wet sand/water out of player footprint. Slope-aware: on slopes, pushes align with surface geometry (downhill diagonals allowed, through-surface blocked). Chaining blocked through slope cells. Flat fallbacks: primary → down → diag → opposite → opposite diag
3. **Drag** — sand: quadratic by immersion. Wet sand: separate higher drag constants. Water: separate drag constants. Dash: reduced drag via `SAND_DASH_DRAG_FACTOR`
4. **Pressure** — contiguous sand/wet sand above → downward force. Water excluded
5. **Burial / quicksand** — sand ratio > threshold → extra gravity. Activity-scaled: moving makes you sink faster (`SAND_QUICKSAND_MOVE_MULT`)
6. **Buoyancy** — water immersion > threshold → upward force
7. **Dash carving** — dashes tunnel through sand/water, ejecting cells upward/sideways with particles
8. **Footprints** — running on sand surface creates depressions at `SAND_FOOTPRINT_STRIDE` intervals, piling removed sand beside

**Sand walls:** Vertical sand columns (≥ `SAND_WALL_MIN_HEIGHT` cells) detected as walls. Wall states erode sand walls via `sand_wall_erode`. Wall jumps from sand walls use `SAND_WALL_JUMP_MULT`.

**Rendering:** Sand + wet sand = opaque rects (triangles on slope cells), color variants via `SAND_COLOR_VARIATION`/`WET_SAND_COLOR_VARIATION`. Water = alpha-blended, depth-darkened gradient (triangles on slopes), surface shimmer effect. Optional `SAND_SURFACE_SMOOTH` for interpolated surface height. Rendered after player.

### Camera

Dead-zone follow: offset normalized to half-viewport → smoothstep ramp → `lerp(speed_min, speed_max, t)` → boundary decel near level edges → `offset * (1 - exp(-speed * dt))`. `camera_clamp` hard safety after smooth follow. Params synced from config, hot-reload with F5. Snaps to spawn on init.

Game wrappers: `game_world_to_screen`/`game_world_to_screen_point` pass `&game.camera`.

## Configuration (`assets/game.ini`)

INI with sections, expressions (`+`,`-`,`*`,`/`, parens, variable refs), `#RRGGBBAA` colors. Runtime-loaded, hot-reload F5. Type hints: `# :u8` = unsigned byte, else `f32`, `[4]u8` for colors, `string` for quoted.

**Workflow:** edit `game.ini` → `odin run build/ -- gen` → update source → `odin run build/ -- check`.

**Sections:** `[game]`, `[version]`, `[engine]`, `[physics]`, `[camera]` (`CAMERA_*`), `[level]` (`LEVEL_COLOR_*`), `[player]`/`[player_run]`/`[player_jump]`/`[player_dash]`/`[player_wall]`/`[player_slopes]`/`[player_graphics]`/`[player_particles]`/`[player_particle_colors]`, `[sand]` (`SAND_*`), `[sand_debug]` (`SAND_DEBUG_*`), `[water]` (`WATER_*`), `[wet_sand]` (`WET_SAND_*`), `[input]` (`INPUT_KB_*`/`INPUT_GP_*`), `[debug_colors]` (`DEBUG_COLOR_*`), `[debug]` (`DEBUG_*`).

## Units & Coordinates

- Physics in **meters**. `PPM = 16` (power of 2). Constants defined as pixel values / PPM in `game.ini`
- Y-axis **up**. Rendering flips via `game_world_to_screen`
- `LEVEL_TILE_PX :: 8`, `TILE_SIZE = 0.5m`. `LOGICAL_H = 480`, `WINDOW_SCALE = 3`
- `FPS = 60`, `FIXED_STEPS = 4` → fixed_dt = `1/(4*60)`
- `Collider_Rect.pos` = **center**. `player.transform.pos` = **bottom-center**; collider offset by `PLAYER_SIZE/2` up
- Time values in **seconds**

## Player Abilities

- **Run:** `PLAYER_RUN_SPEED`, lerp factor `15*dt`
- **Jump:** `PLAYER_JUMP_FORCE`, buffered (`JUMP_BUFFER_DURATION`), coyote time (`COYOTE_TIME_DURATION`)
- **Variable jump:** `PLAYER_FAST_FALL_MULT` gravity when ascending with jump released (short hop)
- **Wall slide:** `WALL_SLIDE_SPEED` clamp, raycasts with `WALL_JUMP_EPS`. Unified side+back walls. Sand walls erode on contact
- **Wall run vertical:** `WALL_RUN_VERTICAL_SPEED`/`_DECAY` (exponential), `WALL_RUN_COOLDOWN`. Side wall needs vel.y > 0 from airborne
- **Wall run horizontal:** `WALL_RUN_HORIZONTAL_SPEED`/`_LIFT`/`_GRAV_MULT` (parabolic arc on back wall)
- **Wall jump:** `WALL_JUMP_FORCE` (1.5x), 0.75x vertical. Sand walls: `SAND_WALL_JUMP_MULT`
- **Dash:** `DASH_SPEED` (4x run), `DASH_DURATION`, `DASH_COOLDOWN`, direction-locked. Uphill: 45deg decompose, ramp off top. Downhill: lift off
- **Drop through:** down + jump on platform → nudge down → Dropping state
- **Step height:** `PLAYER_STEP_HEIGHT` — step over obstacles, wall collision filter, grounded slope snap
- **Submerged** (shared handler for Sand_Swim + Swimming): enter/exit thresholds (hysteresis), material-specific params at runtime. Water: reduced gravity, faster movement, passive float, jump-out at surface. Sand: heavy drag, slow movement, passive sink, spammable sand hop (`SAND_SWIM_HOP_FORCE`/`_COOLDOWN`) for escaping deep burial
- **Impact bounce:** damped cosine spring, purely visual. "Stronger wins" policy

## Debug Overlays

Cycle F3: `NONE` → `PLAYER` → `BACKGROUND` → `SAND` → `ALL` → `CONTROLS`. FPS + sensor readout in all non-NONE modes. Label shows current + next state hint. Adaptive input family (keyboard/gamepad).

- **PLAYER** — collider, position, facing, velocity, FSM state, sensor rays, camera dead zone
- **BACKGROUND** — level collider outlines (ground/ceiling/wall/platform/back wall/slope) + anchors + tile grid
- **SAND** — stress heatmap, sleeping overlay, chunk boundaries, emitter markers, sand/water stats
- **ALL** — everything
- **CONTROLS** — input controls overlay

Config: `DEBUG_COLOR_*` (colors), `DEBUG_*` (sizes/scales), `SAND_DEBUG_*` in `[sand_debug]`.

## Input

Actions: `MOVE_UP`/`DOWN`/`LEFT`/`RIGHT`, `JUMP`, `DASH`, `WALL_RUN`, `SLIDE`, `DEBUG`, `RELOAD`, `QUIT`.

Generic `engine.Input(Input_Action)`. Bindings data-driven via `[input]` in `game.ini` — `INPUT_KB_*` (SDL scancode names), `INPUT_GP_*` (SDL button names). Hot-reload with F5. Auto-switches keyboard/gamepad on last device event.

Defaults — KB: WASD, Space, L, LShift, LCtrl, F3, F5, Esc. GP: stick/dpad, A, Y, RB, LB, Back, Start.

## Odin Coding Style

**File prefix:** All symbols prefixed with file name. `player.odin` → `player_init`, `Player_State`.

**Case:** Functions `snake_case`. Types `Pascal_Snake_Case`. Constants `UPPER_SNAKE_CASE`. Variables `snake_case`.

**Names:** Clear, not verbose. Common abbreviations ok (`pos`, `vel`, `dt`, `ctx`, `dir`, `idx`).

**Function calls:** Keep single line. Use intermediate variables to shorten args. Trailing comma when multi-line unavoidable.

**Functions:** Split when clearly separable. Prefer short, focused. `@(private = "file")` for helpers.

**Style:** Guard clauses for early return. Doc comments only for non-obvious logic. Import order: local → core → vendor. Single blank line between top-level decls. No blanks between related struct fields.
