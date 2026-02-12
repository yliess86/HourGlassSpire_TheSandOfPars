package game

import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

sand_graphics_render :: proc(sand: ^Sand_World) {
	cam_bl := game.camera.pos - game.camera.size / 2
	cam_tr := game.camera.pos + game.camera.size / 2

	x0 := max(int(cam_bl.x / TILE_SIZE), 0)
	y0 := max(int(cam_bl.y / TILE_SIZE), 0)
	x1 := min(int(cam_tr.x / TILE_SIZE) + 1, sand.width)
	y1 := min(int(cam_tr.y / TILE_SIZE) + 1, sand.height)

	// Render sand cells (opaque)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			idx := y * sand.width + x
			cell := sand.cells[idx]
			if cell.material != .Sand do continue

			color := sand_graphics_sand_color(cell)
			slope := sand.slopes[idx]
			if slope != .None {
				sand_graphics_slope_tri(x, y, slope, color)
			} else {
				world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
				world_size := [2]f32{TILE_SIZE, TILE_SIZE}
				rect := game_world_to_screen(world_pos, world_size)
				sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
				sdl.RenderFillRect(game.win.renderer, &rect)
			}
		}
	}

	// Render water cells (with alpha blending, top-down depth gradient for stable surface color)
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)
	depth_max := int(WATER_COLOR_DEPTH_MAX)
	for x in x0 ..< x1 {
		// Pre-scan above visible area to find initial surface distance
		dist := 0
		above_is_water := false
		for y := y1; y < min(sand.height, y1 + depth_max); y += 1 {
			idx := y * sand.width + x
			if sand.slopes[idx] != .None {
				above_is_water = sand.cells[idx].material == .Water
				if above_is_water do dist += 1
				break
			}
			if sand.cells[idx].material == .Water {
				dist += 1
				above_is_water = true
			} else {
				break
			}
		}

		// Render visible cells top-to-bottom (dist = distance from surface)
		for y := y1 - 1; y >= y0; y -= 1 {
			idx := y * sand.width + x
			cell := sand.cells[idx]
			slope := sand.slopes[idx]
			if cell.material == .Water {
				if !above_is_water do dist = 0
				color := sand_graphics_water_color(dist)
				if slope != .None {
					sand_graphics_slope_tri(x, y, slope, color)
				} else {
					world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
					world_size := [2]f32{TILE_SIZE, TILE_SIZE}
					rect := game_world_to_screen(world_pos, world_size)
					sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
					sdl.RenderFillRect(game.win.renderer, &rect)
				}
				dist += 1
				above_is_water = true
			} else {
				dist = 0
				above_is_water = false
			}
		}
	}
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_NONE)
}

sand_graphics_sand_color :: proc(cell: Sand_Cell) -> [4]u8 {
	offset := i16(cell.color_variant) * i16(SAND_COLOR_VARIATION) - i16(SAND_COLOR_VARIATION) * 2
	return {
		u8(math.clamp(i16(SAND_COLOR.r) + offset, 0, 255)),
		u8(math.clamp(i16(SAND_COLOR.g) + offset, 0, 255)),
		u8(math.clamp(i16(SAND_COLOR.b) + offset, 0, 255)),
		SAND_COLOR.a,
	}
}

// Render the open triangle of a slope cell with the given color
@(private = "file")
sand_graphics_slope_tri :: proc(x, y: int, slope: Sand_Slope_Kind, color: [4]u8) {
	wx := f32(x) * TILE_SIZE
	wy := f32(y) * TILE_SIZE

	v0, v1, v2: [2]f32
	if slope == .Right {
		// / open triangle: BL → TL → TR
		v0 = {wx, wy}
		v1 = {wx, wy + TILE_SIZE}
		v2 = {wx + TILE_SIZE, wy + TILE_SIZE}
	} else {
		// \ open triangle: TL → TR → BR
		v0 = {wx, wy + TILE_SIZE}
		v1 = {wx + TILE_SIZE, wy + TILE_SIZE}
		v2 = {wx + TILE_SIZE, wy}
	}

	sp0 := game_world_to_screen_point(v0)
	sp1 := game_world_to_screen_point(v1)
	sp2 := game_world_to_screen_point(v2)
	fc := sdl.FColor {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
	verts := [3]sdl.Vertex {
		{position = sdl.FPoint(sp0), color = fc, tex_coord = {0, 0}},
		{position = sdl.FPoint(sp1), color = fc, tex_coord = {0, 0}},
		{position = sdl.FPoint(sp2), color = fc, tex_coord = {0, 0}},
	}
	sdl.RenderGeometry(game.win.renderer, nil, raw_data(&verts), 3, nil, 0)
}

@(private = "file")
sand_graphics_water_color :: proc(dist: int) -> [4]u8 {
	t := math.clamp(f32(dist) / f32(WATER_COLOR_DEPTH_MAX), 0, 1)
	offset := u8(t * f32(WATER_COLOR_VARIATION))
	return {
		WATER_COLOR.r - min(offset, WATER_COLOR.r),
		WATER_COLOR.g - min(offset, WATER_COLOR.g),
		WATER_COLOR.b - min(offset, WATER_COLOR.b),
		WATER_COLOR.a,
	}
}

sand_graphics_debug :: proc(sand: ^Sand_World) {
	if game.debug != .SAND && game.debug != .ALL do return

	cam_bl := game.camera.pos - game.camera.size / 2
	cam_tr := game.camera.pos + game.camera.size / 2

	x0 := max(int(cam_bl.x / TILE_SIZE), 0)
	y0 := max(int(cam_bl.y / TILE_SIZE), 0)
	x1 := min(int(cam_tr.x / TILE_SIZE) + 1, sand.width)
	y1 := min(int(cam_tr.y / TILE_SIZE) + 1, sand.height)

	// Stress heatmap: compute pressure per visible column (top-down)
	sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)
	for x in x0 ..< x1 {
		pressure: f32 = 0
		for y := min(y1, sand.height) - 1; y >= y0; y -= 1 {
			cell := sand.cells[y * sand.width + x]
			if cell.material == .Sand || cell.material == .Water do pressure += 1.0
			else if cell.material == .Solid || cell.material == .Platform do pressure = 0
			else do pressure = max(pressure - 0.5, 0)

			if pressure > 0 && (cell.material == .Sand || cell.material == .Water) {
				color: [4]u8
				t := math.clamp(pressure / SAND_DEBUG_PRESSURE_MAX, 0, 1)
				if t < 0.33 do color = SAND_DEBUG_COLOR_LOW
				else if t < 0.66 do color = SAND_DEBUG_COLOR_MID
				else do color = SAND_DEBUG_COLOR_HIGH

				world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
				world_size := [2]f32{TILE_SIZE, TILE_SIZE}
				rect := game_world_to_screen(world_pos, world_size)
				sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
				sdl.RenderFillRect(game.win.renderer, &rect)
			}
		}
	}

	// Sleeping particles dimmed overlay (includes particles in inactive chunks)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			cell := sand.cells[y * sand.width + x]
			if cell.material != .Sand && cell.material != .Water do continue

			is_sleeping := cell.sleep_counter >= SAND_SLEEP_THRESHOLD
			if !is_sleeping {
				chunk := sand_chunk_at(sand, x, y)
				is_sleeping = chunk != nil && !chunk.needs_sim
				continue
			}

			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := game_world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(game.win.renderer, 0, 0, 0, SAND_DEBUG_SLEEP_DIM)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}

	// Chunk boundaries and active chunk highlighting
	for cy in 0 ..< sand.chunks_h {
		for cx in 0 ..< sand.chunks_w {
			cs := int(SAND_CHUNK_SIZE)
			chunk_x0 := f32(cx * cs) * TILE_SIZE
			chunk_y0 := f32(cy * cs) * TILE_SIZE
			chunk_w := f32(min((cx + 1) * cs, sand.width) - cx * cs) * TILE_SIZE
			chunk_h := f32(min((cy + 1) * cs, sand.height) - cy * cs) * TILE_SIZE

			world_pos := [2]f32{chunk_x0, chunk_y0}
			world_size := [2]f32{chunk_w, chunk_h}
			rect := game_world_to_screen(world_pos, world_size)

			chunk := sand.chunks[cy * sand.chunks_w + cx]
			if chunk.needs_sim {
				sdl.SetRenderDrawColor(
					game.win.renderer,
					SAND_DEBUG_COLOR_CHUNK.r,
					SAND_DEBUG_COLOR_CHUNK.g,
					SAND_DEBUG_COLOR_CHUNK.b,
					SAND_DEBUG_COLOR_CHUNK.a,
				)
				sdl.RenderFillRect(game.win.renderer, &rect)
			}

			sdl.SetRenderDrawColor(
				game.win.renderer,
				SAND_DEBUG_COLOR_CHUNK.r,
				SAND_DEBUG_COLOR_CHUNK.g,
				SAND_DEBUG_COLOR_CHUNK.b,
				128,
			)
			sdl.RenderRect(game.win.renderer, &rect)
		}
	}

	// Emitter markers
	for emitter in sand.emitters {
		world_pos := [2]f32{f32(emitter.tx) * TILE_SIZE, f32(emitter.ty) * TILE_SIZE}
		world_size := [2]f32{TILE_SIZE, TILE_SIZE}
		rect := game_world_to_screen(world_pos, world_size)
		sdl.SetRenderDrawColor(
			game.win.renderer,
			SAND_DEBUG_COLOR_EMITTER.r,
			SAND_DEBUG_COLOR_EMITTER.g,
			SAND_DEBUG_COLOR_EMITTER.b,
			SAND_DEBUG_COLOR_EMITTER.a,
		)
		sdl.RenderRect(game.win.renderer, &rect)
	}

	// Stats text
	sand_count := 0
	water_count := 0
	sand_sleeping := 0
	water_sleeping := 0
	for y in 0 ..< sand.height {
		for x in 0 ..< sand.width {
			cell := sand.cells[y * sand.width + x]
			is_sleeping := cell.sleep_counter >= SAND_SLEEP_THRESHOLD
			if !is_sleeping {
				chunk := sand_chunk_at(sand, x, y)
				if chunk != nil && !chunk.needs_sim do is_sleeping = true
			}
			if cell.material == .Sand {
				sand_count += 1
				if is_sleeping do sand_sleeping += 1
			} else if cell.material == .Water {
				water_count += 1
				if is_sleeping do water_sleeping += 1
			}
		}
	}
	active_chunks := 0
	for chunk in sand.chunks do if chunk.needs_sim do active_chunks += 1
	sleeping_chunks := len(sand.chunks) - active_chunks

	// Render stats below existing debug text (account for 2 extra sensor lines)
	stats_y := DEBUG_TEXT_MARGIN_Y + 16 * DEBUG_TEXT_LINE_H
	debug_value_with_label(DEBUG_TEXT_MARGIN_X, stats_y, "Sand:", fmt.ctprintf("%d", sand_count))
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + DEBUG_TEXT_LINE_H,
		"Water:",
		fmt.ctprintf("%d", water_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 2 * DEBUG_TEXT_LINE_H,
		"Chunks:",
		fmt.ctprintf("%d/%d", active_chunks, len(sand.chunks)),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 3 * DEBUG_TEXT_LINE_H,
		"Sand Sleep:",
		fmt.ctprintf("%d/%d", sand_sleeping, sand_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 4 * DEBUG_TEXT_LINE_H,
		"Water Sleep:",
		fmt.ctprintf("%d/%d", water_sleeping, water_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 5 * DEBUG_TEXT_LINE_H,
		"Chunk Sleep:",
		fmt.ctprintf("%d/%d", sleeping_chunks, len(sand.chunks)),
	)
}
