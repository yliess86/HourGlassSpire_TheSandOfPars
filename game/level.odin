package game

import "core:fmt"
import engine "engine"
import sdl "vendor:sdl3"

TILE_PX :: 8
TILE_SIZE: f32 : f32(TILE_PX) / PPM // 0.5 meters

Tile_Kind :: enum u8 {
	Empty,
	Solid,
	Platform,
	Behind_Wall,
	Window,
	Spawn,
}

// BMP palette: editor color → tile kind
@(private = "file")
PALETTE :: [Tile_Kind][3]u8 {
	.Empty       = {0, 0, 0},
	.Solid       = {255, 255, 255},
	.Platform    = {0, 255, 0},
	.Behind_Wall = {127, 127, 127},
	.Window      = {255, 255, 0},
	.Spawn       = {255, 0, 255},
}

// Render colors
COLOR_TILE_SOLID:       [3]u8 : {90, 80, 70}
COLOR_TILE_BEHIND_WALL: [3]u8 : {45, 40, 35}
COLOR_TILE_WINDOW:      [3]u8 : {35, 30, 28}

Level :: struct {
	width, height:     int,
	tiles:             []Tile_Kind, // [y * width + x], y=0 = world bottom

	world_w, world_h:  f32, // meters
	player_spawn:      [2]f32, // bottom-center, meters

	ground_colliders:    [dynamic]engine.Collider_Rect,
	platform_colliders:  [dynamic]engine.Collider_Rect,
	wall_colliders:      [dynamic]engine.Collider_Rect,
	back_wall_colliders: [dynamic]engine.Collider_Rect,
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
level_merge_colliders :: proc(level: ^Level) {
	active: [dynamic]Merge_Run
	defer delete(active)

	for y in 0 ..< level.height {
		// Find horizontal runs in this row
		row_runs: [dynamic]Merge_Run
		defer delete(row_runs)

		x := 0
		for x < level.width {
			kind := level.tiles[y * level.width + x]
			if kind != .Solid && kind != .Platform && kind != .Behind_Wall && kind != .Window {
				x += 1
				continue
			}
			x0 := x
			for x < level.width && level.tiles[y * level.width + x] == kind {
				x += 1
			}
			append(&row_runs, Merge_Run{kind = kind, x0 = x0, x1 = x, y0 = y, y1 = y + 1})
		}

		// Try to extend active rects
		matched := make([]bool, len(row_runs))
		defer delete(matched)

		for &ar in active {
			for &rr, ri in row_runs {
				if !matched[ri] && rr.kind == ar.kind && rr.x0 == ar.x0 && rr.x1 == ar.x1 && ar.y1 == y {
					ar.y1 = y + 1
					matched[ri] = true
					break
				}
			}
		}

		// Emit active rects that couldn't extend
		i := 0
		for i < len(active) {
			if active[i].y1 <= y {
				emit_run(level, active[i])
				ordered_remove(&active, i)
			} else {
				i += 1
			}
		}

		// Add new unmatched row runs
		for rr, ri in row_runs {
			if !matched[ri] {
				append(&active, rr)
			}
		}
	}

	// Emit remaining
	for ar in active {
		emit_run(level, ar)
	}
}

@(private = "file")
emit_run :: proc(level: ^Level, run: Merge_Run) {
	w := f32(run.x1 - run.x0) * TILE_SIZE
	h := f32(run.y1 - run.y0) * TILE_SIZE
	cx := f32(run.x0) * TILE_SIZE + w / 2
	cy := f32(run.y0) * TILE_SIZE + h / 2

	rect := engine.Collider_Rect{
		pos  = {cx, cy},
		size = {w, h},
	}

	#partial switch run.kind {
	case .Solid:
		append(&level.ground_colliders, rect)
		append(&level.wall_colliders, rect)
	case .Platform:
		append(&level.platform_colliders, rect)
	case .Behind_Wall:
		append(&level.back_wall_colliders, rect)
	// Window tiles are purely visual — no colliders
	}
}

level_render :: proc(level: ^Level) {
	// Backdrop tiles first (Behind_Wall, Window)
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			color: [3]u8
			#partial switch kind {
			case .Behind_Wall:
				color = COLOR_TILE_BEHIND_WALL
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

	// Foreground tiles (Solid, Platform)
	for y in 0 ..< level.height {
		for x in 0 ..< level.width {
			kind := level.tiles[y * level.width + x]
			if kind != .Solid && kind != .Platform do continue
			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(game.win.renderer, COLOR_TILE_SOLID.r, COLOR_TILE_SOLID.g, COLOR_TILE_SOLID.b, 255)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}
}

level_destroy :: proc(level: ^Level) {
	delete(level.tiles)
	delete(level.ground_colliders)
	delete(level.platform_colliders)
	delete(level.wall_colliders)
	delete(level.back_wall_colliders)
}
