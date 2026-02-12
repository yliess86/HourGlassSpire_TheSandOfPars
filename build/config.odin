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
	comment:   string,
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

// Extract the human-readable description comment from a raw INI value.
// Handles hex colors (#RRGGBBAA), type hints (# :u8), strings, and em-dash separators.
config_extract_comment :: proc(raw_value: string) -> string {
	in_str := false
	first_hash := -1
	second_hash := -1

	i := 0
	for i < len(raw_value) {
		c := raw_value[i]
		if c == '"' {
			in_str = !in_str
			i += 1
			continue
		}
		if in_str {
			i += 1
			continue
		}
		if c == '#' {
			// Skip hex colors: #RRGGBB or #RRGGBBAA
			hex_len := 0
			for j := i + 1; j < len(raw_value); j += 1 {
				d := raw_value[j]
				if (d >= '0' && d <= '9') || (d >= 'a' && d <= 'f') || (d >= 'A' && d <= 'F') {
					hex_len += 1
				} else {
					break
				}
			}
			if hex_len >= 6 && hex_len <= 8 {
				i += 1 + hex_len
				continue
			}

			if first_hash < 0 {
				first_hash = i
			} else if second_hash < 0 {
				second_hash = i
				break
			}
		}
		i += 1
	}

	if first_hash < 0 do return ""

	first := raw_value[first_hash:]

	// Type hint: "# :type" pattern
	if len(first) >= 3 && first[1] == ' ' && first[2] == ':' {
		if second_hash >= 0 {
			return strings.trim_space(raw_value[second_hash + 1:])
		}
		// Fallback: em-dash separator within single comment
		if idx := strings.index(first, "\xe2\x80\x94"); idx >= 0 {
			return strings.trim_space(first[idx + 3:])
		}
		return ""
	}

	return strings.trim_space(first[1:])
}

config_game_name: string

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
		comment := config_extract_comment(raw_value)
		append(
			&entries,
			Config_Entry {
				key = key,
				type = type,
				section = current_section,
				raw_value = raw_value,
				comment = comment,
			},
		)

		if key == "GAME_TITLE" && type == .String {
			start := strings.index_byte(raw_value, '"')
			end := strings.last_index_byte(raw_value, '"')
			if start >= 0 && end > start {
				title := raw_value[start + 1:end]
				parts := strings.fields(title)
				config_game_name = strings.concatenate(parts)
				delete(parts)
			}
		}
	}

	// Pass 2: re-infer types with full entries for forward string references
	for &entry in entries {
		if entry.type == .F32 {
			new_type := config_infer_type(entry.raw_value, entries[:])
			if new_type != .F32 do entry.type = new_type
		}
	}

	if len(config_game_name) == 0 do config_game_name = "game"

	// Generate output
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "// AUTO-GENERATED from assets/game.ini — do not edit manually\n")
	strings.write_string(&b, "package game\n\n")
	strings.write_string(&b, "import engine \"../engine\"\n")
	strings.write_string(&b, "import \"core:fmt\"\n")

	// Compute max declaration length for comment alignment
	type_str_len :: proc(t: Config_Entry_Type) -> int {
		switch t {
		case .F32:
			return 3 // "f32"
		case .U8:
			return 2 // "u8"
		case .RGBA:
			return 5 // "[4]u8"
		case .String:
			return 6 // "string"
		}
		return 0
	}
	max_decl_len := 0
	for entry in entries {
		decl_len := len(entry.key) + 2 + type_str_len(entry.type) // "key: type"
		if decl_len > max_decl_len do max_decl_len = decl_len
	}

	// Variable declarations grouped by section with aligned comments
	prev_section := ""
	for entry in entries {
		if entry.section != prev_section {
			strings.write_string(&b, "\n// [")
			strings.write_string(&b, entry.section)
			strings.write_string(&b, "]\n")
			prev_section = entry.section
		}
		type_str: string
		switch entry.type {
		case .F32:
			type_str = ": f32"
		case .U8:
			type_str = ": u8"
		case .RGBA:
			type_str = ": [4]u8"
		case .String:
			type_str = ": string"
		}
		strings.write_string(&b, entry.key)
		strings.write_string(&b, type_str)
		if len(entry.comment) > 0 {
			decl_len := len(entry.key) + len(type_str)
			for _ in 0 ..< max_decl_len - decl_len do strings.write_byte(&b, ' ')
			strings.write_string(&b, "  // ")
			strings.write_string(&b, entry.comment)
		}
		strings.write_byte(&b, '\n')
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
		strings.write_string(&b, "(&config_game, \"")
		strings.write_string(&b, entry.key)
		strings.write_string(&b, "\"); ok do ")
		strings.write_string(&b, entry.key)
		strings.write_string(&b, " = val\n")
	}
	strings.write_string(&b, "}\n")

	// config_game global
	strings.write_string(&b, "\nconfig_game: engine.Config\n")

	// config_load_and_apply proc
	strings.write_string(&b, "\nconfig_load_and_apply :: proc() {\n")
	strings.write_string(&b, "\tconfig, ok := engine.config_load(\"assets/game.ini\")\n")
	strings.write_string(&b, "\tif !ok {\n")
	strings.write_string(&b, "\t\tfmt.eprintf(\"[config] Failed to load config\\n\")\n")
	strings.write_string(&b, "\t\treturn\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "\tconfig_game = config\n")
	strings.write_string(&b, "\tconfig_apply()\n")
	strings.write_string(&b, "}\n")

	// config_reload_all proc
	strings.write_string(&b, "\nconfig_reload_all :: proc() {\n")
	strings.write_string(&b, "\tif len(config_game.path) == 0 {\n")
	strings.write_string(&b, "\t\tconfig_load_and_apply()\n")
	strings.write_string(&b, "\t\tgame_config_post_apply()\n")
	strings.write_string(&b, "\t\treturn\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "\tif engine.config_reload(&config_game) {\n")
	strings.write_string(&b, "\t\tconfig_apply()\n")
	strings.write_string(&b, "\t\tgame_config_post_apply()\n")
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
