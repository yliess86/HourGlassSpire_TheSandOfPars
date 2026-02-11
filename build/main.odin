package build

import "core:fmt"
import "core:os"

when ODIN_OS == .Windows {EXE_EXT :: ".exe"} else do EXE_EXT :: ""
CLEAN_DIRS :: [?]string{"bin", "dist", "libs"}

clean :: proc(args: []string) {
	targets: [len(CLEAN_DIRS)]bool

	if len(args) == 0 do for &t in targets do t = true
	else {
		for arg in args {
			found := false
			for dir, i in CLEAN_DIRS {
				if arg == dir {
					targets[i] = true
					found = true
					break
				}
			}
			if !found {
				fmt.eprintf("Unknown clean target: %s\n", arg)
				fmt.eprintf("  Available targets: bin, dist, libs\n")
				os.exit(1)
			}
		}
	}

	for dir, i in CLEAN_DIRS {
		if !targets[i] do continue
		if os.exists(dir) {
			sys_run(fmt.tprintf("rm -rf %s", dir))
			fmt.printf("Cleaned %s/\n", dir)
		}
	}
}

main :: proc() {
	mode := "run"
	if len(os.args) > 1 do mode = os.args[1]

	if mode == "setup" {
		dist_setup_sdl(DIST_HOST_OS)
		return
	}

	if mode == "clean" {
		clean(os.args[2:])
		return
	}

	switch mode {
	case "run", "build", "check", "gen", "dist", "version", "release":
	case:
		fmt.eprintf("Usage: odin run build/ -- [run|build|check|gen|dist|setup|clean]\n")
		fmt.eprintf("  run [release]    — gen_config + build + run (default: -debug)\n")
		fmt.eprintf("  build [release]  — gen_config + build only (default: -debug)\n")
		fmt.eprintf("  check            — gen_config + type-check only\n")
		fmt.eprintf("  gen              — regenerate config.odin only\n")
		fmt.eprintf("  dist [target]    — gen_config + release build + bundle\n")
		fmt.eprintf("  version          — stamp current UTC date/time into game.ini\n")
		fmt.eprintf("  release          — stamp version, commit, tag, and push\n")
		fmt.eprintf("  setup            — download SDL3 libs for current platform\n")
		fmt.eprintf("  clean [targets]  — remove build artifacts\n")
		fmt.eprintf("                     targets: bin, dist, libs (default: all)\n")
		fmt.eprintf("\n")
		fmt.eprintf(
			"Dist targets: windows_x64, windows_x86, macos_arm64, macos_x64, linux_x64, linux_arm64\n",
		)
		fmt.eprintf("  odin run build/ -- dist              # current platform\n")
		fmt.eprintf("  odin run build/ -- dist windows_x64  # cross-compile\n")
		os.exit(1)
	}

	// Stamp version before config_gen for version/release modes
	ver_name, ver_hash: string
	if mode == "version" || mode == "release" {
		stamp_ok: bool
		ver_name, ver_hash, stamp_ok = version_stamp()
		if !stamp_ok do os.exit(1)
	}

	if !config_gen() do os.exit(1)
	if mode == "gen" do return
	if mode == "version" do return

	if mode == "release" {
		tag := fmt.tprintf("release-%s", ver_hash)
		msg := fmt.tprintf("%s: %s", ver_name, tag)
		if !sys_run("git add assets/game.ini src/game/config.odin") do os.exit(1)
		if !sys_run(fmt.tprintf("git commit -m \"%s\"", msg)) do os.exit(1)
		if !sys_run(fmt.tprintf("git tag %s", tag)) do os.exit(1)
		if !sys_run(fmt.tprintf("git push origin HEAD %s", tag)) do os.exit(1)

		fmt.printf("Released %s\n", tag)
		return
	}

	game_bin := fmt.tprintf("bin/%s%s", game_name, EXE_EXT)

	if mode == "dist" {
		target_name := dist_default_target()
		if len(os.args) > 2 do target_name = os.args[2]

		target, found := dist_find_target(target_name)
		if !found {
			fmt.eprintf("Unknown dist target: %s\n", target_name)
			fmt.eprintf(
				"Available targets: windows_x64, windows_x86, macos_arm64, macos_x64, linux_x64, linux_arm64\n",
			)
			os.exit(1)
		}

		dist_build(target)
		return
	}

	sys_make_dir("bin")
	when ODIN_OS == .Windows {
		if !os.exists("bin/SDL3.dll") {
			dist_setup_sdl(DIST_HOST_OS)
			if os.exists("libs/windows/SDL3.dll") do sys_copy("libs\\windows\\SDL3.dll", "bin\\SDL3.dll")
		}
	}

	release := len(os.args) > 2 && os.args[2] == "release"

	ok: bool
	switch mode {
	case "check":
		ok = sys_run("odin check src/game/")
	case "build", "run":
		if release do ok = sys_run(fmt.tprintf("odin build src/game/ -out:%s -o:speed", game_bin))
		else do ok = sys_run(fmt.tprintf("odin build src/game/ -out:%s -debug", game_bin))
	}
	if !ok {
		fmt.eprintf("Build failed\n")
		os.exit(1)
	}
	if mode != "run" do return

	when ODIN_OS == .Windows {ok = sys_run(game_bin)} else do ok = sys_run(fmt.tprintf("./%s", game_bin))
	if !ok do os.exit(1)
}
