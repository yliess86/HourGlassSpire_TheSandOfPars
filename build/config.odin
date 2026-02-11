package build

import "core:fmt"
import "core:os"
import "core:strings"

Config_Entry_Type :: enum {
	F32,
	U8,
	RGBA,
	String,
}

Config_Entry :: struct {
	key:       string,
	type:      Config_Entry_Type,
	section:   string,
	raw_value: string,
}

config_infer_type :: proc(raw_value: string, entries: []Config_Entry) -> Config_Entry_Type {
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

	// Check if any referenced identifier is a string — means this is a string expression
	expr := value
	if hash_idx >= 0 do expr = strings.trim_space(value[:hash_idx])
	pos := 0
	for pos < len(expr) {
		c := expr[pos]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			start := pos
			for pos < len(expr) && ((expr[pos] >= 'a' && expr[pos] <= 'z') || (expr[pos] >= 'A' && expr[pos] <= 'Z') || expr[pos] == '_' || (expr[pos] >= '0' && expr[pos] <= '9')) do pos += 1
			name := expr[start:pos]
			for entry in entries {
				if entry.key == name && entry.type == .String do return .String
			}
		} else {
			pos += 1
		}
	}

	return .F32
}

game_name: string

config_gen :: proc() -> bool {
	data, ok := os.read_entire_file("assets/game.ini")
	if !ok {
		fmt.eprintf("Error: could not read assets/game.ini\n")
		return false
	}
	defer delete(data)

	entries: [dynamic]Config_Entry
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

		// Pass 1: infer types from literal patterns only (no identifier lookup)
		type := config_infer_type(raw_value, {})
		append(
			&entries,
			Config_Entry{key = key, type = type, section = current_section, raw_value = raw_value},
		)

		if key == "GAME_TITLE" && type == .String {
			title := strings.trim(raw_value, "\"")
			parts := strings.fields(title)
			game_name = strings.concatenate(parts)
			delete(parts)
		}
	}

	// Pass 2: re-infer types with full entries for forward string references
	for &entry in entries {
		if entry.type == .F32 {
			new_type := config_infer_type(entry.raw_value, entries[:])
			if new_type != .F32 do entry.type = new_type
		}
	}

	if len(game_name) == 0 do game_name = "game"

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
