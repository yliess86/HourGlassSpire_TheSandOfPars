package game

import engine "../engine"
import "core:fmt"
import sdl "vendor:sdl3"

TILE_PX :: 8
TILE_SIZE: f32 : f32(TILE_PX) / PPM // 0.5 meters

Tile_Kind :: enum u8 {
	Empty,
	Solid,
	Platform,
	Back_Wall,
	Window,
	Spawn,
	Slope_Right, // floor, rises left→right /
	Slope_Left, // floor, rises right→left \
	Slope_Ceil_Right, // ceiling, solid top-right \
	Slope_Ceil_Left, // ceiling, solid top-left /
}

// BMP palette: editor color → tile kind
@(private = "file")
PALETTE :: [Tile_Kind][3]u8 {
	.Empty            = {0, 0, 0},
	.Solid            = {255, 255, 255},
	.Platform         = {0, 255, 0},
	.Back_Wall        = {127, 127, 127},
	.Window           = {255, 255, 0},
	.Spawn            = {255, 0, 255},
	.Slope_Right      = {255, 0, 0},
	.Slope_Left       = {0, 0, 255},
	.Slope_Ceil_Right = {128, 0, 0},
	.Slope_Ceil_Left  = {0, 0, 128},
}

// Render colors
COLOR_TILE_SOLID: [3]u8 : {90, 80, 70}
COLOR_TILE_BACK_WALL: [3]u8 : {45, 40, 35}
COLOR_TILE_WINDOW: [3]u8 : {35, 30, 28}

Level :: struct {
	width, height:       int,
	tiles:               []Tile_Kind, // [y * width + x], y=0 = world bottom
	world_w, world_h:    f32, // meters
	player_spawn:        [2]f32, // bottom-center, meters
	ground_colliders:    [dynamic]engine.Collider_Rect,
	ceiling_colliders:   [dynamic]engine.Collider_Rect,
	side_wall_colliders: [dynamic]engine.Collider_Rect,
	platform_colliders:  [dynamic]engine.Collider_Rect,
	back_wall_colliders: [dynamic]engine.Collider_Rect,
	slope_colliders:     [dynamic]engine.Collider_Slope,
}

level_load :: proc(path: cstring) -> (level: Level, ok: bool) {
	raw_surface := sdl.LoadBMP(path)
	if raw_surface == nil {
		fmt.eprintf("Failed to load level BMP '%s': %s\n", path, sdl.GetError())
		return {}, false
	}

	// Convert to RGB24 to handle any BMP format (indexed, 4-bit, 32-bit, etc.)
	surface := sdl.ConvertSurface(raw_surface, .RGB24)
	sdl.DestroySurface(raw_surface)
	if surface == nil {
		fmt.eprintf("Failed to convert surface for '%s': %s\n", path, sdl.GetError())
		return {}, false
	}
	defer sdl.DestroySurface(surface)

	w := int(surface.w)
	h := int(surface.h)
	level.width = w
	level.height = h
	level.world_w = f32(w) * TILE_SIZE
	level.world_h = f32(h) * TILE_SIZE
	level.tiles = make([]Tile_Kind, w * h)

	pixels := ([^]u8)(surface.pixels)
	pitch := int(surface.pitch)

	spawn_x, spawn_y: int
	has_spawn := false

	for img_y in 0 ..< h {
		// SDL BMP: img_y=0 is top of image. Flip so y=0 = world bottom.
		world_y := h - 1 - img_y

		for x in 0 ..< w {
			offset := img_y * pitch + x * 3

			// RGB24: bytes are R, G, B in memory order
			r := pixels[offset + 0]
			g := pixels[offset + 1]
			b := pixels[offset + 2]

			rgb := [3]u8{r, g, b}
			kind := color_to_tile(rgb)
			idx := world_y * w + x
			level.tiles[idx] = kind

			if kind == .Spawn {
				level.player_spawn = {(f32(x) + 0.5) * TILE_SIZE, f32(world_y) * TILE_SIZE}
				spawn_x = x
				spawn_y = world_y
				has_spawn = true
				level.tiles[idx] = .Empty
			}
		}
	}

	// Fill spawn tile with the most common neighbor type
	if has_spawn {
		counts: [Tile_Kind]int
		for dy in -1 ..= 1 {
			for dx in -1 ..= 1 {
				if dx == 0 && dy == 0 do continue
				nx, ny := spawn_x + dx, spawn_y + dy
				if nx < 0 || nx >= w || ny < 0 || ny >= h do continue
				nk := level.tiles[ny * w + nx]
				if nk != .Empty && nk != .Spawn {
					counts[nk] += 1
				}
			}
		}
		best: Tile_Kind
		best_count := 0
		for kind in Tile_Kind {
			if counts[kind] > best_count {
				best = kind
				best_count = counts[kind]
			}
		}
		if best_count > 0 {
			level.tiles[spawn_y * w + spawn_x] = best
		}
	}

	// Merge tiles into collider rects
	level_merge_colliders(&level)

	return level, true
}

// Map RGB to tile kind (nearest match)
@(private = "file")
color_to_tile :: proc(rgb: [3]u8) -> Tile_Kind {
	for color, kind in PALETTE {
		if rgb == color do return kind
	}
	return .Empty
}

// Greedy row-merge: converts tile grid → minimal axis-aligned rectangles
@(private = "file")
Merge_Run :: struct {
	kind:   Tile_Kind,
	x0, x1: int, // tile x range [x0, x1)
	y0:     int, // bottom row
	y1:     int, // top row (exclusive)
}

@(private = "file")
slope_is_kind :: proc(kind: Tile_Kind) -> bool {
	return(
		kind == .Slope_Right ||
		kind == .Slope_Left ||
		kind == .Slope_Ceil_Right ||
		kind == .Slope_Ceil_Left \
	)
}

@(private = "file")
level_merge_colliders :: proc(level: ^Level) {
	// Save original tile kinds before reclassification so the
	// classification pass can detect slope neighbors that get cleared.
	n := level.width * level.height
	original_tiles := make([]Tile_Kind, n)
	defer delete(original_tiles)
	copy(original_tiles, level.tiles)

	// Reclassify interior slope tiles to .Empty so only surface
	// (hypotenuse) tiles remain as slopes for diagonal merging.
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			if !slope_is_kind(kind) do continue

			// Floor slopes: interior if same-kind tile directly above
			// Ceiling slopes: interior if same-kind tile directly below
			is_floor := kind == .Slope_Right || kind == .Slope_Left
			check_y := (y + 1) if is_floor else (y - 1)

			if check_y >= 0 && check_y < level.height {
				if level.tiles[check_y * level.width + x] == kind {
					level.tiles[y * level.width + x] = .Empty
				}
			}
		}
	}

	// Classify solid tiles by exposed face.
	// Uses original_tiles for neighbor checks so reclassified slope
	// tiles (now .Empty) are still recognized as slope geometry.
	ground_mask := make([]bool, n)
	defer delete(ground_mask)
	ceiling_mask := make([]bool, n)
	defer delete(ceiling_mask)
	side_wall_mask := make([]bool, n)
	defer delete(side_wall_mask)

	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			idx := y * level.width + x
			if level.tiles[idx] != .Solid do continue

			above_solid := y < level.height - 1 && level.tiles[(y + 1) * level.width + x] == .Solid
			below_solid := y > 0 && level.tiles[(y - 1) * level.width + x] == .Solid

			// Floor slope above → slope handles the surface, no ground needed
			above_kind :=
				original_tiles[(y + 1) * level.width + x] if y < level.height - 1 else Tile_Kind.Empty
			floor_slope_above := above_kind == .Slope_Right || above_kind == .Slope_Left

			// Ceiling slope below → slope handles the surface, no ceiling needed
			below_kind := original_tiles[(y - 1) * level.width + x] if y > 0 else Tile_Kind.Empty
			ceil_slope_below := below_kind == .Slope_Ceil_Right || below_kind == .Slope_Ceil_Left

			is_ground := !above_solid && !floor_slope_above
			is_ceiling := !below_solid && !ceil_slope_below

			if is_ground do ground_mask[idx] = true
			if is_ceiling do ceiling_mask[idx] = true

			if !is_ground && !is_ceiling {
				left_solid := x > 0 && level.tiles[y * level.width + (x - 1)] == .Solid
				right_solid :=
					x < level.width - 1 && level.tiles[y * level.width + (x + 1)] == .Solid

				exposed_left := !left_solid
				exposed_right := !right_solid

				// Check original tiles for slope neighbors (reclassified ones are .Empty now)
				if exposed_left &&
				   x > 0 &&
				   slope_is_kind(original_tiles[y * level.width + (x - 1)]) {
					exposed_left = false
				}
				if exposed_right &&
				   x < level.width - 1 &&
				   slope_is_kind(original_tiles[y * level.width + (x + 1)]) {
					exposed_right = false
				}

				if exposed_left || exposed_right {
					side_wall_mask[idx] = true
				}
			}
		}
	}

	level_merge_mask(level.width, level.height, ground_mask, &level.ground_colliders)
	level_merge_mask(level.width, level.height, ceiling_mask, &level.ceiling_colliders)
	level_merge_mask(level.width, level.height, side_wall_mask, &level.side_wall_colliders)

	// Inverted back wall mask: everything is back wall except Window tiles
	back_wall_mask := make([]bool, n)
	defer delete(back_wall_mask)
	for i in 0 ..< n {back_wall_mask[i] = true}
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			if level.tiles[y * level.width + x] == .Window {
				back_wall_mask[y * level.width + x] = false
			}
		}
	}
	level_merge_mask(level.width, level.height, back_wall_mask, &level.back_wall_colliders)

	// Greedy row-merge for Platform tiles
	active: [dynamic]Merge_Run
	defer delete(active)

	for y in 0 ..< level.height {
		row_runs: [dynamic]Merge_Run
		defer delete(row_runs)

		x := 0
		for x < level.width {
			kind := level.tiles[y * level.width + x]
			if kind != .Platform {
				x += 1
				continue
			}
			x0 := x
			for x < level.width && level.tiles[y * level.width + x] == kind {
				x += 1
			}
			append(&row_runs, Merge_Run{kind = kind, x0 = x0, x1 = x, y0 = y, y1 = y + 1})
		}

		matched := make([]bool, len(row_runs))
		defer delete(matched)

		for &ar in active {
			for &rr, ri in row_runs {
				if !matched[ri] &&
				   rr.kind == ar.kind &&
				   rr.x0 == ar.x0 &&
				   rr.x1 == ar.x1 &&
				   ar.y1 == y {
					ar.y1 = y + 1
					matched[ri] = true
					break
				}
			}
		}

		i := 0
		for i < len(active) {
			if active[i].y1 <= y {
				emit_run(level, active[i])
				ordered_remove(&active, i)
			} else {
				i += 1
			}
		}

		for rr, ri in row_runs {
			if !matched[ri] {
				append(&active, rr)
			}
		}
	}

	for ar in active {
		emit_run(level, ar)
	}

	// Merge slope tiles into diagonal runs
	level_merge_slopes(level)
}

@(private = "file")
emit_run :: proc(level: ^Level, run: Merge_Run) {
	w := f32(run.x1 - run.x0) * TILE_SIZE
	h := f32(run.y1 - run.y0) * TILE_SIZE
	cx := f32(run.x0) * TILE_SIZE + w / 2
	cy := f32(run.y0) * TILE_SIZE + h / 2

	rect := engine.Collider_Rect {
		pos  = {cx, cy},
		size = {w, h},
	}

	append(&level.platform_colliders, rect)
}

@(private = "file")
level_merge_mask :: proc(
	width, height: int,
	mask: []bool,
	target: ^[dynamic]engine.Collider_Rect,
) {
	active: [dynamic]Merge_Run
	defer delete(active)

	for y in 0 ..< height {
		row_runs: [dynamic]Merge_Run
		defer delete(row_runs)

		x := 0
		for x < width {
			if !mask[y * width + x] {
				x += 1
				continue
			}
			x0 := x
			for x < width && mask[y * width + x] {
				x += 1
			}
			append(&row_runs, Merge_Run{kind = .Solid, x0 = x0, x1 = x, y0 = y, y1 = y + 1})
		}

		matched := make([]bool, len(row_runs))
		defer delete(matched)

		for &ar in active {
			for &rr, ri in row_runs {
				if !matched[ri] && rr.x0 == ar.x0 && rr.x1 == ar.x1 && ar.y1 == y {
					ar.y1 = y + 1
					matched[ri] = true
					break
				}
			}
		}

		i := 0
		for i < len(active) {
			if active[i].y1 <= y {
				emit_rect(target, active[i])
				ordered_remove(&active, i)
			} else {
				i += 1
			}
		}

		for rr, ri in row_runs {
			if !matched[ri] {
				append(&active, rr)
			}
		}
	}

	for ar in active {
		emit_rect(target, ar)
	}
}

@(private = "file")
emit_rect :: proc(target: ^[dynamic]engine.Collider_Rect, run: Merge_Run) {
	w := f32(run.x1 - run.x0) * TILE_SIZE
	h := f32(run.y1 - run.y0) * TILE_SIZE
	cx := f32(run.x0) * TILE_SIZE + w / 2
	cy := f32(run.y0) * TILE_SIZE + h / 2
	append(target, engine.Collider_Rect{pos = {cx, cy}, size = {w, h}})
}

@(private = "file")
tile_to_slope_kind :: proc(kind: Tile_Kind) -> engine.Collider_Slope_Kind {
	#partial switch kind {
	case .Slope_Right:
		return .Right
	case .Slope_Left:
		return .Left
	case .Slope_Ceil_Left:
		return .Ceil_Left
	case .Slope_Ceil_Right:
		return .Ceil_Right
	}
	return .Right
}

// Merge diagonal runs of same-kind slope tiles into single Collider_Slope entries.
// / slopes (Right, Ceil_Left): diagonal dx=+1, dy=+1
// \ slopes (Left, Ceil_Right): diagonal dx=+1, dy=-1
@(private = "file")
level_merge_slopes :: proc(level: ^Level) {
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			if !slope_is_kind(kind) do continue

			// Check if previous diagonal neighbor is the same kind.
			// If so, skip — this tile will be merged from the start of its run.
			prev_x, prev_y: int
			if kind == .Slope_Right || kind == .Slope_Ceil_Left {
				// / diagonal: previous is (x-1, y-1)
				prev_x = x - 1
				prev_y = y - 1
			} else {
				// \ diagonal: previous is (x-1, y+1)
				prev_x = x - 1
				prev_y = y + 1
			}
			if prev_x >= 0 && prev_y >= 0 && prev_y < level.height {
				if level.tiles[prev_y * level.width + prev_x] == kind {
					continue // not the start of a run
				}
			}

			// This is the start of a diagonal run — trace forward
			run := 1
			dx, dy: int
			if kind == .Slope_Right || kind == .Slope_Ceil_Left {
				dx = 1; dy = 1
			} else {
				dx = 1; dy = -1
			}
			nx, ny := x + dx, y + dy
			for nx < level.width && ny >= 0 && ny < level.height {
				if level.tiles[ny * level.width + nx] != kind do break
				run += 1
				nx += dx
				ny += dy
			}

			// Compute merged slope
			span := f32(run) * TILE_SIZE
			base_x := f32(x) * TILE_SIZE
			base_y: f32
			if kind == .Slope_Right || kind == .Slope_Ceil_Left {
				// / — start tile is bottom-left of the run
				base_y = f32(y) * TILE_SIZE
			} else {
				// \ — start tile is top-left; bottom is (run-1) tiles lower
				base_y = f32(y - run + 1) * TILE_SIZE
			}

			append(
				&level.slope_colliders,
				engine.Collider_Slope {
					kind = tile_to_slope_kind(kind),
					base_x = base_x,
					base_y = base_y,
					span = span,
				},
			)
		}
	}
}

level_render :: proc(level: ^Level) {
	// Backdrop tiles first (Behind_Wall, Window)
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			color: [3]u8
			#partial switch kind {
			case .Back_Wall:
				color = COLOR_TILE_BACK_WALL
			case .Window:
				color = COLOR_TILE_WINDOW
			case:
				continue
			}
			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, 255)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}

	// Slope backgrounds (behind the triangles)
	sdl.SetRenderDrawColor(
		game.win.renderer,
		COLOR_TILE_BACK_WALL.r,
		COLOR_TILE_BACK_WALL.g,
		COLOR_TILE_BACK_WALL.b,
		255,
	)
	for s in level.slope_colliders {
		world_pos := [2]f32{s.base_x, s.base_y}
		world_size := [2]f32{s.span, s.span}
		rect := world_to_screen(world_pos, world_size)
		sdl.RenderFillRect(game.win.renderer, &rect)
	}

	// Foreground tiles (Solid, Platform)
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			if kind != .Solid && kind != .Platform do continue
			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(
				game.win.renderer,
				COLOR_TILE_SOLID.r,
				COLOR_TILE_SOLID.g,
				COLOR_TILE_SOLID.b,
				255,
			)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}

	// Slope triangles (filled)
	slope_color := sdl.FColor {
		f32(COLOR_TILE_SOLID.r) / 255,
		f32(COLOR_TILE_SOLID.g) / 255,
		f32(COLOR_TILE_SOLID.b) / 255,
		1,
	}
	for s in level.slope_colliders {
		v0, v1, v2: [2]f32
		switch s.kind {
		case .Right:
			v0 = {s.base_x, s.base_y}
			v1 = {s.base_x + s.span, s.base_y}
			v2 = {s.base_x + s.span, s.base_y + s.span}
		case .Left:
			v0 = {s.base_x, s.base_y}
			v1 = {s.base_x + s.span, s.base_y}
			v2 = {s.base_x, s.base_y + s.span}
		case .Ceil_Left:
			v0 = {s.base_x, s.base_y}
			v1 = {s.base_x, s.base_y + s.span}
			v2 = {s.base_x + s.span, s.base_y + s.span}
		case .Ceil_Right:
			v0 = {s.base_x + s.span, s.base_y}
			v1 = {s.base_x, s.base_y + s.span}
			v2 = {s.base_x + s.span, s.base_y + s.span}
		}
		sp0 := world_to_screen_point(v0)
		sp1 := world_to_screen_point(v1)
		sp2 := world_to_screen_point(v2)
		verts := [3]sdl.Vertex {
			{position = sdl.FPoint(sp0), color = slope_color, tex_coord = {0, 0}},
			{position = sdl.FPoint(sp1), color = slope_color, tex_coord = {0, 0}},
			{position = sdl.FPoint(sp2), color = slope_color, tex_coord = {0, 0}},
		}
		sdl.RenderGeometry(game.win.renderer, nil, raw_data(&verts), 3, nil, 0)
	}
}

level_destroy :: proc(level: ^Level) {
	delete(level.tiles)
	delete(level.ground_colliders)
	delete(level.ceiling_colliders)
	delete(level.side_wall_colliders)
	delete(level.platform_colliders)
	delete(level.back_wall_colliders)
	delete(level.slope_colliders)
}

level_debug :: proc(level: ^Level) {
	if game.debug == .BACKGROUND || game.debug == .ALL {
		for c in level.ground_colliders do debug_collider_rect(c)
		for c in level.ceiling_colliders do debug_collider_rect(c, DEBUG_COLOR_COLLIDER_CEILING)
		for c in level.side_wall_colliders do debug_collider_rect(c, DEBUG_COLOR_COLLIDER_SIDE_WALL)
		for c in level.platform_colliders do debug_collider_plateform(c)
		for c in level.back_wall_colliders do debug_collider_back_wall(c)
		for s in level.slope_colliders do debug_collider_slope(s)
		for c in level.ground_colliders do debug_point(c.pos)
		for c in level.ceiling_colliders do debug_point(c.pos)
		for c in level.side_wall_colliders do debug_point(c.pos)
		for c in level.platform_colliders do debug_point(c.pos)
	}
}
