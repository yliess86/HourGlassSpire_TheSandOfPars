package game

import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

// Render sand particles (camera-culled)
sand_render :: proc(sand: ^Sand_World) {
	cam_bl := game.camera.pos - game.camera.size / 2
	cam_tr := game.camera.pos + game.camera.size / 2

	x0 := max(int(cam_bl.x / TILE_SIZE), 0)
	y0 := max(int(cam_bl.y / TILE_SIZE), 0)
	x1 := min(int(cam_tr.x / TILE_SIZE) + 1, sand.width)
	y1 := min(int(cam_tr.y / TILE_SIZE) + 1, sand.height)

	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			cell := sand.cells[y * sand.width + x]
			if cell.material != .Sand do continue

			color := sand_cell_color(cell)
			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}
}

sand_cell_color :: proc(cell: Sand_Cell) -> [4]u8 {
	offset := i16(cell.color_variant) * i16(SAND_COLOR_VARIATION) - i16(SAND_COLOR_VARIATION) * 2
	return {
		u8(math.clamp(i16(SAND_COLOR.r) + offset, 0, 255)),
		u8(math.clamp(i16(SAND_COLOR.g) + offset, 0, 255)),
		u8(math.clamp(i16(SAND_COLOR.b) + offset, 0, 255)),
		SAND_COLOR.a,
	}
}

// Debug visualization: stress heatmap, chunk outlines, stats, emitter markers
sand_debug :: proc(sand: ^Sand_World) {
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
			if cell.material == .Sand {
				pressure += 1.0
			} else if cell.material == .Solid || cell.material == .Platform {
				pressure = 0
			} else {
				pressure = max(pressure - 0.5, 0)
			}

			if pressure > 0 && cell.material == .Sand {
				color: [4]u8
				t := math.clamp(pressure / SAND_DEBUG_PRESSURE_MAX, 0, 1)
				if t < 0.33 {
					color = SAND_DEBUG_COLOR_LOW
				} else if t < 0.66 {
					color = SAND_DEBUG_COLOR_MID
				} else {
					color = SAND_DEBUG_COLOR_HIGH
				}

				world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
				world_size := [2]f32{TILE_SIZE, TILE_SIZE}
				rect := world_to_screen(world_pos, world_size)
				sdl.SetRenderDrawColor(game.win.renderer, color.r, color.g, color.b, color.a)
				sdl.RenderFillRect(game.win.renderer, &rect)
			}
		}
	}

	// Sleeping particles dimmed overlay (includes particles in inactive chunks)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			cell := sand.cells[y * sand.width + x]
			if cell.material != .Sand do continue

			is_sleeping := cell.sleep_counter >= SAND_SLEEP_THRESHOLD
			if !is_sleeping {
				chunk := sand_chunk_at(sand, x, y)
				is_sleeping = chunk != nil && !chunk.needs_sim
			}
			if !is_sleeping do continue

			world_pos := [2]f32{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE}
			world_size := [2]f32{TILE_SIZE, TILE_SIZE}
			rect := world_to_screen(world_pos, world_size)
			sdl.SetRenderDrawColor(game.win.renderer, 0, 0, 0, SAND_DEBUG_SLEEP_DIM)
			sdl.RenderFillRect(game.win.renderer, &rect)
		}
	}

	// Chunk boundaries and active chunk highlighting
	for cy in 0 ..< sand.chunks_h {
		for cx in 0 ..< sand.chunks_w {
			chunk_x0 := f32(cx * int(SAND_CHUNK_SIZE)) * TILE_SIZE
			chunk_y0 := f32(cy * int(SAND_CHUNK_SIZE)) * TILE_SIZE
			chunk_w :=
				f32(min((cx + 1) * int(SAND_CHUNK_SIZE), sand.width) - cx * int(SAND_CHUNK_SIZE)) *
				TILE_SIZE
			chunk_h :=
				f32(
					min((cy + 1) * int(SAND_CHUNK_SIZE), sand.height) - cy * int(SAND_CHUNK_SIZE),
				) *
				TILE_SIZE

			world_pos := [2]f32{chunk_x0, chunk_y0}
			world_size := [2]f32{chunk_w, chunk_h}
			rect := world_to_screen(world_pos, world_size)

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
		rect := world_to_screen(world_pos, world_size)
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
	particle_count := 0
	sleeping_count := 0
	for y in 0 ..< sand.height {
		for x in 0 ..< sand.width {
			cell := sand.cells[y * sand.width + x]
			if cell.material != .Sand do continue
			particle_count += 1
			if cell.sleep_counter >= SAND_SLEEP_THRESHOLD {
				sleeping_count += 1
			} else {
				chunk := sand_chunk_at(sand, x, y)
				if chunk != nil && !chunk.needs_sim {
					sleeping_count += 1
				}
			}
		}
	}
	active_chunks := 0
	for chunk in sand.chunks {
		if chunk.needs_sim do active_chunks += 1
	}

	// Render stats below existing debug text
	stats_y := DEBUG_TEXT_MARGIN_Y + 14 * DEBUG_TEXT_LINE_H
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y,
		"Sand:",
		fmt.ctprintf("%d", particle_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + DEBUG_TEXT_LINE_H,
		"Sleep:",
		fmt.ctprintf("%d/%d", sleeping_count, particle_count),
	)
	debug_value_with_label(
		DEBUG_TEXT_MARGIN_X,
		stats_y + 2 * DEBUG_TEXT_LINE_H,
		"Chunks:",
		fmt.ctprintf("%d/%d", active_chunks, len(sand.chunks)),
	)
}
