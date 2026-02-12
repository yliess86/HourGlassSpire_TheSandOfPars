package build

import "core:fmt"
import "core:os"
import "core:strings"

when ODIN_OS == .Windows {DIST_HOST_OS :: "windows"} else when ODIN_OS == .Darwin {DIST_HOST_OS :: "macos"} else do DIST_HOST_OS :: "linux"
DIST_SDL_VERSION :: "3.4.0"
DIST_SDL_WIN_URL ::
	"https://github.com/libsdl-org/SDL/releases/download/release-" +
	DIST_SDL_VERSION +
	"/SDL3-devel-" +
	DIST_SDL_VERSION +
	"-VC.zip"
DIST_SDL_MAC_URL ::
	"https://github.com/libsdl-org/SDL/releases/download/release-" +
	DIST_SDL_VERSION +
	"/SDL3-" +
	DIST_SDL_VERSION +
	".dmg"
DIST_SDL_WIN_ZIP :: "libs/SDL3-devel-VC.zip"
DIST_SDL_MAC_DMG :: "libs/SDL3.dmg"

Dist_Target :: struct {
	name:        string, // user-facing name, e.g. "windows_x64"
	odin_target: string, // odin -target: value
	target_os:   string, // "windows", "macos", "linux"
	exe_ext:     string, // ".exe" or ""
}

DIST_TARGETS :: [6]Dist_Target {
	{name = "windows_x64", odin_target = "windows_amd64", target_os = "windows", exe_ext = ".exe"},
	{name = "windows_x86", odin_target = "windows_i386", target_os = "windows", exe_ext = ".exe"},
	{name = "macos_arm64", odin_target = "darwin_arm64", target_os = "macos", exe_ext = ""},
	{name = "macos_x64", odin_target = "darwin_amd64", target_os = "macos", exe_ext = ""},
	{name = "linux_x64", odin_target = "linux_amd64", target_os = "linux", exe_ext = ""},
	{name = "linux_arm64", odin_target = "linux_arm64", target_os = "linux", exe_ext = ""},
}

dist_find_target :: proc(name: string) -> (Dist_Target, bool) {
	for t in DIST_TARGETS do if t.name == name do return t, true
	return {}, false
}

dist_default_target :: proc() -> string {
	when ODIN_OS == .Windows {
		return "windows_x64"
	} else when ODIN_OS == .Darwin {
		when ODIN_ARCH == .arm64 {
			return "macos_arm64"
		} else do return "macos_x64"
	} else do return "linux_x64"
}

dist_setup_sdl :: proc(target_os: string) -> bool {
	sys_make_dir("libs")

	switch target_os {
	case "windows":
		if os.exists("libs/windows/SDL3.dll") do return true
		if !sys_download(DIST_SDL_WIN_URL, DIST_SDL_WIN_ZIP) {
			fmt.eprintf("Error: failed to download SDL3 for Windows\n")
			return false
		}
		sys_make_dir("libs/windows")
		when ODIN_OS == .Windows {
			sys_run(
				strings.concatenate(
					{
						"powershell -Command \"Expand-Archive -Force '",
						DIST_SDL_WIN_ZIP,
						"' 'libs/sdl3_tmp'\"",
					},
				),
			)
			sys_copy(
				"libs\\sdl3_tmp\\SDL3-" + DIST_SDL_VERSION + "\\lib\\x64\\SDL3.dll",
				"libs\\windows\\SDL3.dll",
			)
			sys_run("rmdir /S /Q libs\\sdl3_tmp")
		} else {
			if !sys_run("unzip -o " + DIST_SDL_WIN_ZIP + " -d libs/sdl3_tmp") {
				fmt.eprintf("Error: failed to extract SDL3 zip\n")
				return false
			}
			sys_copy(
				"libs/sdl3_tmp/SDL3-" + DIST_SDL_VERSION + "/lib/x64/SDL3.dll",
				"libs/windows/SDL3.dll",
			)
			sys_run("rm -rf libs/sdl3_tmp")
		}
		os.remove(DIST_SDL_WIN_ZIP)
		return os.exists("libs/windows/SDL3.dll")

	case "macos":
		if os.exists("libs/macos/libSDL3.dylib") do return true
		when ODIN_OS != .Darwin {
			fmt.eprintf("Error: macOS DMG extraction requires a macOS host\n")
			return false
		}
		if !sys_download(DIST_SDL_MAC_URL, DIST_SDL_MAC_DMG) {
			fmt.eprintf("Error: failed to download SDL3 for macOS\n")
			return false
		}
		sys_make_dir("libs/macos")
		sys_run("hdiutil attach " + DIST_SDL_MAC_DMG + " -mountpoint /tmp/sdl3_mount -quiet")
		sys_run(
			"cp /tmp/sdl3_mount/SDL3.xcframework/macos-arm64_x86_64/SDL3.framework/Versions/A/SDL3 libs/macos/libSDL3.dylib",
		)
		sys_run("hdiutil detach /tmp/sdl3_mount -quiet")
		os.remove(DIST_SDL_MAC_DMG)
		return os.exists("libs/macos/libSDL3.dylib")

	case "linux":
		if os.exists("libs/linux/libSDL3.so.0") do return true
		fmt.eprintf("Warning: libs/linux/libSDL3.so.0 not found\n")
		fmt.eprintf("  Place it manually or install SDL3 on the target system\n")
		return false
	}
	return false
}

dist_build :: proc(target: Dist_Target) {
	tmp_dir := fmt.tprintf(".dist_tmp_%s", target.name)
	tmp_assets := fmt.tprintf("%s/assets", tmp_dir)
	tmp_bin := fmt.tprintf("%s/%s%s", tmp_dir, config_game_name, target.exe_ext)

	dist_dir := fmt.tprintf("dist/%s", target.name)

	fmt.printf("Building distribution for %s...\n", target.name)

	// 1. Clean + create temp directories
	sys_run(fmt.tprintf("rm -rf %s", tmp_dir))
	sys_make_dir(tmp_dir)
	sys_make_dir(tmp_assets)

	// 2. Compile release build into temp dir
	extra_flags: string
	switch target.target_os {
	case "windows":
		when ODIN_OS == .Windows do extra_flags = " -subsystem:windows"
	case "linux":
		extra_flags = " -extra-linker-flags:\"-Wl,-rpath,'\\$ORIGIN'\""
	}
	build_cmd := fmt.tprintf(
		"odin build src/game/ -out:%s -target:%s -o:speed%s",
		tmp_bin,
		target.odin_target,
		extra_flags,
	)
	if !sys_run(build_cmd) {
		sys_run(fmt.tprintf("rm -rf %s", tmp_dir))
		fmt.eprintf("Dist build failed for %s\n", target.name)
		os.exit(1)
	}

	// 3. Copy all assets into temp dir
	if !sys_copy_dir("assets", tmp_assets) do fmt.eprintf("Warning: some assets failed to copy\n")

	// 4. Bundle SDL3 into temp dir
	sdl_ok := dist_setup_sdl(target.target_os)

	switch target.target_os {
	case "windows":
		if sdl_ok {
			if !sys_copy("libs/windows/SDL3.dll", fmt.tprintf("%s/SDL3.dll", tmp_dir)) do fmt.eprintf("Warning: failed to copy SDL3.dll\n")
		} else do fmt.eprintf("Warning: SDL3.dll not bundled — add it manually\n")

	case "macos":
		if sdl_ok {
			if !sys_copy("libs/macos/libSDL3.dylib", fmt.tprintf("%s/libSDL3.dylib", tmp_dir)) {
				fmt.eprintf("Warning: failed to copy libSDL3.dylib\n")
			}
			sys_run(
				fmt.tprintf(
					"install_name_tool -change @rpath/libSDL3.0.dylib @executable_path/libSDL3.dylib %s",
					tmp_bin,
				),
			)
		} else do fmt.eprintf("Warning: libSDL3.dylib not bundled — add it manually\n")

	case "linux":
		if sdl_ok {
			if !sys_copy("libs/linux/libSDL3.so.0", fmt.tprintf("%s/libSDL3.so.0", tmp_dir)) do fmt.eprintf("Warning: failed to copy libSDL3.so.0\n")
		}
	}

	// 5. Move temp dir to final dist location
	sys_make_dir("dist")
	sys_run(fmt.tprintf("rm -rf %s", dist_dir))
	if !sys_run(fmt.tprintf("mv %s %s", tmp_dir, dist_dir)) {
		fmt.eprintf("Error: failed to move %s to %s\n", tmp_dir, dist_dir)
		os.exit(1)
	}

	fmt.printf("Distribution ready: %s/\n", dist_dir)
}
