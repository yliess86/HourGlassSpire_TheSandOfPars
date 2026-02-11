package game

import engine "../engine"
import sdl "vendor:sdl3"

main :: proc() {
	defer game_clean()
	game_init()

	for game.running {
		engine.clock_update(&game.clock)
		game_update(game.clock.dt)
		for engine.clock_tick(&game.clock) do game_fixed_update(game.clock.fixed_dt)
		sdl.SetRenderDrawColor(game.win.renderer, LEVEL_COLOR_BG.r, LEVEL_COLOR_BG.g, LEVEL_COLOR_BG.b, LEVEL_COLOR_BG.a)
		sdl.RenderClear(game.win.renderer)
		game_render()
		if game.debug != .NONE do game_render_debug()
		sdl.RenderPresent(game.win.renderer)
		free_all(context.temp_allocator)
	}
}
