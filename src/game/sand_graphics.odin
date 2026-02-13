package game

import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

Sand_Render_Batch :: struct {
	vertices: [dynamic]sdl.Vertex,
	indices:  [dynamic]c.int,
}

// Pre-computed color LUTs (rebuilt on init + F5 reload)
WATER_COLOR_LUT_SIZE :: 32
sand_color_lut: [4]sdl.FColor
wet_sand_color_lut: [4]sdl.FColor
water_color_lut: [WATER_COLOR_LUT_SIZE]sdl.FColor

sand_graphics_init_lut :: proc() {
	for v in 0 ..< 4 {
		offset := i16(v) * i16(SAND_COLOR_VARIATION) - i16(SAND_COLOR_VARIATION) * 2
		sand_color_lut[v] = {
			f32(math.clamp(i16(SAND_COLOR.r) + offset, 0, 255)) / 255,
			f32(math.clamp(i16(SAND_COLOR.g) + offset, 0, 255)) / 255,
			f32(math.clamp(i16(SAND_COLOR.b) + offset, 0, 255)) / 255,
			f32(SAND_COLOR.a) / 255,
		}
	}
	for v in 0 ..< 4 {
		offset := i16(v) * i16(WET_SAND_COLOR_VARIATION) - i16(WET_SAND_COLOR_VARIATION) * 2
		wet_sand_color_lut[v] = {
			f32(math.clamp(i16(WET_SAND_COLOR.r) + offset, 0, 255)) / 255,
			f32(math.clamp(i16(WET_SAND_COLOR.g) + offset, 0, 255)) / 255,
			f32(math.clamp(i16(WET_SAND_COLOR.b) + offset, 0, 255)) / 255,
			f32(WET_SAND_COLOR.a) / 255,
		}
	}
	for d in 0 ..< WATER_COLOR_LUT_SIZE {
		t := math.clamp(f32(d) / f32(WATER_COLOR_DEPTH_MAX), 0, 1)
		offset := t * f32(WATER_COLOR_VARIATION) / 255
		water_color_lut[d] = {
			f32(WATER_COLOR.r) / 255 - min(offset, f32(WATER_COLOR.r) / 255),
			f32(WATER_COLOR.g) / 255 - min(offset, f32(WATER_COLOR.g) / 255),
			f32(WATER_COLOR.b) / 255 - min(offset, f32(WATER_COLOR.b) / 255),
			f32(WATER_COLOR.a) / 255,
		}
	}
}

sand_graphics_render :: proc(sand: ^Sand_World) {
	cam_bl := game.camera.pos - game.camera.size / 2
	cam_tr := game.camera.pos + game.camera.size / 2

	x0 := max(int(cam_bl.x / TILE_SIZE), 0)
	y0 := max(int(cam_bl.y / TILE_SIZE), 0)
	x1 := min(int(cam_tr.x / TILE_SIZE) + 1, sand.width)
	y1 := min(int(cam_tr.y / TILE_SIZE) + 1, sand.height)

	sand_batch := Sand_Render_Batch {
		vertices = make([dynamic]sdl.Vertex, 0, 7000, context.temp_allocator),
		indices  = make([dynamic]c.int, 0, 10000, context.temp_allocator),
	}
	water_batch := Sand_Render_Batch {
		vertices = make([dynamic]sdl.Vertex, 0, 7000, context.temp_allocator),
		indices  = make([dynamic]c.int, 0, 10000, context.temp_allocator),
	}

	// Batch sand + wet sand cells (opaque)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			idx := y * sand.width + x
			cell := sand.cells[idx]
			fc: sdl.FColor
			if cell.material == .Sand do fc = sand_color_lut[cell.color_variant]
			else if cell.material == .Wet_Sand do fc = wet_sand_color_lut[cell.color_variant]
			else do continue

			slope := sand.slopes[idx]
			if slope != .None do sand_graphics_batch_slope_tri(&sand_batch, x, y, slope, fc)
			else do sand_graphics_batch_rect(&sand_batch, x, y, fc)
		}
	}

	// Batch water cells (top-down depth gradient)
	depth_max := int(WATER_COLOR_DEPTH_MAX)
	for x in x0 ..< x1 {
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
			} else do break
		}

		for y := y1 - 1; y >= y0; y -= 1 {
			idx := y * sand.width + x
			cell := sand.cells[idx]
			slope := sand.slopes[idx]
			if cell.material == .Water {
				is_surface := !above_is_water
				if is_surface do dist = 0
				fc := water_color_lut[min(dist, WATER_COLOR_LUT_SIZE - 1)]
				if is_surface {
					phase :=
						f32(x) * WATER_SHIMMER_PHASE +
						f32(sand.step_counter) * WATER_SHIMMER_SPEED * 0.016
					shimmer := (math.sin(phase) * 0.5 + 0.5) * f32(WATER_SHIMMER_BRIGHTNESS) / 255
					fc.r = min(fc.r + shimmer, 1)
					fc.g = min(fc.g + shimmer, 1)
					fc.b = min(fc.b + shimmer, 1)
				}
				if slope != .None do sand_graphics_batch_slope_tri(&water_batch, x, y, slope, fc)
				else do sand_graphics_batch_rect(&water_batch, x, y, fc)
				dist += 1
				above_is_water = true
			} else {
				dist = 0
				above_is_water = false
			}
		}
	}

	// Draw sand batch (opaque)
	if len(sand_batch.indices) > 0 {
		sdl.RenderGeometry(
			game.win.renderer,
			nil,
			raw_data(sand_batch.vertices[:]),
			c.int(len(sand_batch.vertices)),
			raw_data(sand_batch.indices[:]),
			c.int(len(sand_batch.indices)),
		)
	}

	// Draw water batch (alpha-blended)
	if len(water_batch.indices) > 0 {
		sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_BLEND)
		sdl.RenderGeometry(
			game.win.renderer,
			nil,
			raw_data(water_batch.vertices[:]),
			c.int(len(water_batch.vertices)),
			raw_data(water_batch.indices[:]),
			c.int(len(water_batch.indices)),
		)
		sdl.SetRenderDrawBlendMode(game.win.renderer, sdl.BLENDMODE_NONE)
	}
}

@(private = "file")
sand_graphics_batch_rect :: proc(batch: ^Sand_Render_Batch, x, y: int, fc: sdl.FColor) {
	rect := game_world_to_screen({f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}, {TILE_SIZE, TILE_SIZE})
	base := c.int(len(batch.vertices))
	append(
		&batch.vertices,
		sdl.Vertex{position = {rect.x, rect.y}, color = fc, tex_coord = {0, 0}},
		sdl.Vertex{position = {rect.x + rect.w, rect.y}, color = fc, tex_coord = {0, 0}},
		sdl.Vertex{position = {rect.x, rect.y + rect.h}, color = fc, tex_coord = {0, 0}},
		sdl.Vertex{position = {rect.x + rect.w, rect.y + rect.h}, color = fc, tex_coord = {0, 0}},
	)
	append(&batch.indices, base, base + 1, base + 2, base + 1, base + 3, base + 2)
}

@(private = "file")
sand_graphics_batch_slope_tri :: proc(
	batch: ^Sand_Render_Batch,
	x, y: int,
	slope: Sand_Slope_Kind,
	fc: sdl.FColor,
) {
	wx := f32(x) * TILE_SIZE
	wy := f32(y) * TILE_SIZE
	v0, v1, v2: [2]f32
	if slope == .Right {
		v0 = {wx, wy}
		v1 = {wx, wy + TILE_SIZE}
		v2 = {wx + TILE_SIZE, wy + TILE_SIZE}
	} else {
		v0 = {wx, wy + TILE_SIZE}
		v1 = {wx + TILE_SIZE, wy + TILE_SIZE}
		v2 = {wx + TILE_SIZE, wy}
	}
	sp0 := game_world_to_screen_point(v0)
	sp1 := game_world_to_screen_point(v1)
	sp2 := game_world_to_screen_point(v2)
	base := c.int(len(batch.vertices))
	append(
		&batch.vertices,
		sdl.Vertex{position = sdl.FPoint(sp0), color = fc, tex_coord = {0, 0}},
		sdl.Vertex{position = sdl.FPoint(sp1), color = fc, tex_coord = {0, 0}},
		sdl.Vertex{position = sdl.FPoint(sp2), color = fc, tex_coord = {0, 0}},
	)
	append(&batch.indices, base, base + 1, base + 2)
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
			if cell.material == .Sand || cell.material == .Wet_Sand || cell.material == .Water do pressure += 1.0
			else if cell.material == .Solid || cell.material == .Platform do pressure = 0
			else do pressure = max(pressure - 0.5, 0)

			if pressure > 0 &&
			   (cell.material == .Sand || cell.material == .Wet_Sand || cell.material == .Water) {
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
			if cell.material != .Sand && cell.material != .Wet_Sand && cell.material != .Water do continue

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
	wet_sand_count := 0
	water_count := 0
	sand_sleeping := 0
	wet_sand_sleeping := 0
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
			} else if cell.material == .Wet_Sand {
				wet_sand_count += 1
				if is_sleeping do wet_sand_sleeping += 1
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
		"Wet Sand:",
		fmt.ctprintf("%d", wet_sand_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 2 * DEBUG_TEXT_LINE_H,
		"Water:",
		fmt.ctprintf("%d", water_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 3 * DEBUG_TEXT_LINE_H,
		"Chunks:",
		fmt.ctprintf("%d/%d", active_chunks, len(sand.chunks)),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 4 * DEBUG_TEXT_LINE_H,
		"Sand Sleep:",
		fmt.ctprintf("%d/%d", sand_sleeping, sand_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 5 * DEBUG_TEXT_LINE_H,
		"Wet Sleep:",
		fmt.ctprintf("%d/%d", wet_sand_sleeping, wet_sand_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 6 * DEBUG_TEXT_LINE_H,
		"Water Sleep:",
		fmt.ctprintf("%d/%d", water_sleeping, water_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 7 * DEBUG_TEXT_LINE_H,
		"Chunk Sleep:",
		fmt.ctprintf("%d/%d", sleeping_chunks, len(sand.chunks)),
	)
}
