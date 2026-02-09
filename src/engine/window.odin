package engine

import "core:fmt"
import sdl "vendor:sdl3"

Window :: struct {
	handle:    ^sdl.Window,
	renderer:  ^sdl.Renderer,
	logical_w: i32,
	logical_h: i32,
}

window_clean :: proc(win: ^Window) {
	sdl.DestroyRenderer(win.renderer)
	sdl.DestroyWindow(win.handle)
	sdl.Quit()
}

window_init :: proc(title: cstring, logical_h: i32, scale: i32) -> (win: Window, ok: bool) {
	if !sdl.Init({.VIDEO, .GAMEPAD}) {
		fmt.eprintf("SDL could not initialize! SDL_Error: %s\n", sdl.GetError())
		return {}, false
	}

	logical_w := window_compute_logical_w(logical_h)
	w, h := logical_w * scale, logical_h * scale

	handle := sdl.CreateWindow(title, w, h, {})
	if handle == nil {
		fmt.eprintf("Window could not be created! SDL_Error: %s\n", sdl.GetError())
		return {}, false
	}

	renderer := sdl.CreateRenderer(handle, nil)
	if renderer == nil {
		fmt.eprintf("Renderer could not be created! SDL_Error: %s\n", sdl.GetError())
		return {}, false
	}

	sdl.SetRenderVSync(renderer, 1)
	sdl.SetRenderLogicalPresentation(renderer, logical_w, logical_h, .INTEGER_SCALE)

	return Window{handle, renderer, logical_w, logical_h}, true
}

window_compute_logical_w :: proc(logical_h: i32) -> i32 {
	display := sdl.GetPrimaryDisplay()
	mode := sdl.GetDesktopDisplayMode(display)
	aspect_ratio := f32(mode.w) / f32(mode.h) if mode != nil else 4.0 / 3.0
	return i32(f32(logical_h) * aspect_ratio)
}
