package main

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"

Entry_Type :: enum {
	F32,
	U8,
	RGBA,
	String,
}

Entry :: struct {
	key:     string,
	type:    Entry_Type,
	section: string,
}

gen_config_infer_type :: proc(raw_value: string) -> Entry_Type {
	value := strings.trim_space(raw_value)
	if len(value) > 0 && value[0] == '"' do return .String
	if len(value) > 0 && value[0] == '#' && len(value) >= 9 do return .RGBA

	hash_idx := -1
	for i in 0 ..< len(value) {
		if value[i] == '#' {
			hash_idx = i
			break
		}
	}
	if hash_idx >= 0 {
		comment := value[hash_idx:]
		if strings.contains(comment, ":u8") do return .U8
	}

	return .F32
}

gen_config :: proc() -> bool {
	data, ok := os.read_entire_file("assets/game.ini")
	if !ok {
		fmt.eprintf("Error: could not read assets/game.ini\n")
		return false
	}
	defer delete(data)

	entries: [dynamic]Entry
	defer delete(entries)

	content := string(data)
	current_section := ""

	for line in strings.split_lines_iterator(&content) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue
		if trimmed[0] == '#' do continue

		if trimmed[0] == '[' {
			end := strings.index_byte(trimmed, ']')
			if end > 0 do current_section = trimmed[1:end]
			continue
		}

		eq_idx := strings.index_byte(trimmed, '=')
		if eq_idx < 0 do continue

		key := strings.trim_space(trimmed[:eq_idx])
		raw_value := strings.trim_space(trimmed[eq_idx + 1:])
		if len(key) == 0 || len(raw_value) == 0 do continue

		type := gen_config_infer_type(raw_value)
		append(&entries, Entry{key = key, type = type, section = current_section})
	}

	// Generate output
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "// AUTO-GENERATED from assets/game.ini — do not edit manually\n")
	strings.write_string(&b, "package game\n\n")
	strings.write_string(&b, "import engine \"../engine\"\n")
	strings.write_string(&b, "import \"core:fmt\"\n")

	// Variable declarations grouped by section
	prev_section := ""
	for entry in entries {
		if entry.section != prev_section {
			strings.write_string(&b, "\n// [")
			strings.write_string(&b, entry.section)
			strings.write_string(&b, "]\n")
			prev_section = entry.section
		}
		strings.write_string(&b, entry.key)
		switch entry.type {
		case .F32:
			strings.write_string(&b, ": f32\n")
		case .U8:
			strings.write_string(&b, ": u8\n")
		case .RGBA:
			strings.write_string(&b, ": [4]u8\n")
		case .String:
			strings.write_string(&b, ": string\n")
		}
	}

	// config_apply proc
	strings.write_string(&b, "\nconfig_apply :: proc() {\n")
	for entry in entries {
		strings.write_string(&b, "\tif val, ok := engine.config_get_")
		switch entry.type {
		case .F32:
			strings.write_string(&b, "f32")
		case .U8:
			strings.write_string(&b, "u8")
		case .RGBA:
			strings.write_string(&b, "rgba")
		case .String:
			strings.write_string(&b, "string")
		}
		strings.write_string(&b, "(&game_config, \"")
		strings.write_string(&b, entry.key)
		strings.write_string(&b, "\"); ok do ")
		strings.write_string(&b, entry.key)
		strings.write_string(&b, " = val\n")
	}
	strings.write_string(&b, "}\n")

	// game_config global
	strings.write_string(&b, "\ngame_config: engine.Config\n")

	// config_load_and_apply proc
	strings.write_string(&b, "\nconfig_load_and_apply :: proc() {\n")
	strings.write_string(&b, "\tconfig, ok := engine.config_load(\"assets/game.ini\")\n")
	strings.write_string(&b, "\tif !ok {\n")
	strings.write_string(&b, "\t\tfmt.eprintf(\"[config] Failed to load config\\n\")\n")
	strings.write_string(&b, "\t\treturn\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "\tgame_config = config\n")
	strings.write_string(&b, "\tconfig_apply()\n")
	strings.write_string(&b, "}\n")

	// config_reload_all proc
	strings.write_string(&b, "\nconfig_reload_all :: proc() {\n")
	strings.write_string(&b, "\tif len(game_config.path) == 0 {\n")
	strings.write_string(&b, "\t\tconfig_load_and_apply()\n")
	strings.write_string(&b, "\t\tconfig_post_apply()\n")
	strings.write_string(&b, "\t\treturn\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "\tif engine.config_reload(&game_config) {\n")
	strings.write_string(&b, "\t\tconfig_apply()\n")
	strings.write_string(&b, "\t\tconfig_post_apply()\n")
	strings.write_string(&b, "\t\tfmt.eprintf(\"[config] Reloaded\\n\")\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "}\n")

	output := strings.to_string(b)
	write_ok := os.write_entire_file("src/game/config.odin", transmute([]u8)output)
	if !write_ok {
		fmt.eprintf("Error: could not write src/game/config.odin\n")
		return false
	}

	fmt.printf("Generated src/game/config.odin with %d entries\n", len(entries))
	return true
}

run_command :: proc(cmd: string) -> i32 {
	return libc.system(strings.clone_to_cstring(cmd))
}

when ODIN_OS == .Windows {
	EXE_EXT :: ".exe"
} else {
	EXE_EXT :: ""
}

GAME_BIN :: "bin/HourGlassSpire" + EXE_EXT

main :: proc() {
	mode := "run"
	if len(os.args) > 1 do mode = os.args[1]

	switch mode {
	case "run", "build", "check", "gen":
	case:
		fmt.eprintf("Usage: odin run build.odin -file -- [run|build|check|gen]\n")
		fmt.eprintf("  run   — gen_config + build + run (default)\n")
		fmt.eprintf("  build — gen_config + build only\n")
		fmt.eprintf("  check — gen_config + type-check only\n")
		fmt.eprintf("  gen   — regenerate config.odin only\n")
		os.exit(1)
	}

	if !gen_config() do os.exit(1)
	if mode == "gen" do return

	os.make_directory("bin")
	rc: i32
	switch mode {
	case "check":
		rc = run_command("odin check src/game/")
	case "build", "run":
		rc = run_command("odin build src/game/ -out:" + GAME_BIN + " -debug")
	}
	if rc != 0 {
		fmt.eprintf("Build failed (exit code %d)\n", rc)
		os.exit(1)
	}
	if mode != "run" do return

	when ODIN_OS == .Windows {
		rc = run_command(GAME_BIN)
	} else {
		rc = run_command("./" + GAME_BIN)
	}
	if rc != 0 do os.exit(1)
}
