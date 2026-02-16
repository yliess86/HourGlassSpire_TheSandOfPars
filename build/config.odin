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

SAND_SECTIONS :: [?]string{"sand", "sand_debug", "water", "wet_sand"}

config_is_sand_section :: proc(section: string) -> bool {
	for s in SAND_SECTIONS do if section == s do return true
	return false
}

type_str_len :: proc(t: Config_Entry_Type) -> int {
	switch t {
	case .F32:
		return 3
	case .U8:
		return 2
	case .RGBA:
		return 5
	case .String:
		return 6
	}
	return 0
}

Config_File :: struct {
	pkg:         string,
	path:        string,
	import_path: string, // empty = same package (no import)
	config_var:  string,
	proc_prefix: string, // prefix for generated procs (e.g. "sand_")
}

config_write_file :: proc(file: Config_File, entries: []Config_Entry) -> bool {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(
		&b,
		"// AUTO-GENERATED from assets/game.ini \xe2\x80\x94 do not edit manually\n",
	)
	fmt.sbprintf(&b, "package %s\n\n", file.pkg)
	same_pkg := len(file.import_path) == 0
	if !same_pkg do fmt.sbprintf(&b, "import engine \"%s\"\n", file.import_path)
	strings.write_string(&b, "import \"core:fmt\"\n")

	// Compute max declaration length for comment alignment
	max_decl_len := 0
	for entry in entries {
		decl_len := len(entry.key) + 2 + type_str_len(entry.type)
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

	// Resolve engine prefix: "engine." for cross-package, "" for same-package
	engine_prefix := "" if same_pkg else "engine."
	prefix := file.proc_prefix

	// config_apply proc
	fmt.sbprintf(&b, "\n%sconfig_apply :: proc() {{\n", prefix)
	for entry in entries {
		fmt.sbprintf(&b, "\tif val, ok := %sconfig_get_", engine_prefix)
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
		fmt.sbprintf(&b, "(&%s, \"", file.config_var)
		strings.write_string(&b, entry.key)
		strings.write_string(&b, "\"); ok do ")
		strings.write_string(&b, entry.key)
		strings.write_string(&b, " = val\n")
	}
	strings.write_string(&b, "}\n")

	// config global
	fmt.sbprintf(&b, "\n%s: %sConfig\n", file.config_var, engine_prefix)

	// config_load_and_apply proc
	fmt.sbprintf(&b, "\n%sconfig_load_and_apply :: proc() {{\n", prefix)
	fmt.sbprintf(&b, "\tconfig, ok := %sconfig_load(\"assets/game.ini\")\n", engine_prefix)
	strings.write_string(&b, "\tif !ok {\n")
	fmt.sbprintf(&b, "\t\tfmt.eprintf(\"[%s config] Failed to load config\\n\")\n", file.pkg)
	strings.write_string(&b, "\t\treturn\n")
	strings.write_string(&b, "\t}\n")
	fmt.sbprintf(&b, "\t%s = config\n", file.config_var)
	fmt.sbprintf(&b, "\t%sconfig_apply()\n", prefix)
	strings.write_string(&b, "}\n")

	// config_reload proc
	fmt.sbprintf(&b, "\n%sconfig_reload :: proc() -> bool {{\n", prefix)
	strings.write_string(&b, "\tif len(")
	strings.write_string(&b, file.config_var)
	strings.write_string(&b, ".path) == 0 {\n")
	fmt.sbprintf(&b, "\t\t%sconfig_load_and_apply()\n", prefix)
	strings.write_string(&b, "\t\treturn true\n")
	strings.write_string(&b, "\t}\n")
	fmt.sbprintf(&b, "\tif %sconfig_reload(&", engine_prefix)
	strings.write_string(&b, file.config_var)
	strings.write_string(&b, ") {\n")
	fmt.sbprintf(&b, "\t\t%sconfig_apply()\n", prefix)
	strings.write_string(&b, "\t\treturn true\n")
	strings.write_string(&b, "\t}\n")
	strings.write_string(&b, "\treturn false\n")
	strings.write_string(&b, "}\n")

	output := strings.to_string(b)
	write_ok := os.write_entire_file(file.path, transmute([]u8)output)
	if !write_ok {
		fmt.eprintf("Error: could not write %s\n", file.path)
		return false
	}

	fmt.printf("Generated %s with %d entries\n", file.path, len(entries))
	return true
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

	// Partition entries: game vs sand
	game_entries: [dynamic]Config_Entry
	defer delete(game_entries)
	sand_entries: [dynamic]Config_Entry
	defer delete(sand_entries)

	for entry in entries {
		if config_is_sand_section(entry.section) do append(&sand_entries, entry)
		else do append(&game_entries, entry)
	}

	// Generate game config
	game_ok := config_write_file(
		{
			pkg = "game",
			path = "src/game/config.odin",
			import_path = "../engine",
			config_var = "config_game",
			proc_prefix = "",
		},
		game_entries[:],
	)
	if !game_ok do return false

	// Generate sand config (inside engine package)
	sand_ok := config_write_file(
		{
			pkg = "engine",
			path = "src/engine/sand_config.odin",
			import_path = "",
			config_var = "sand_config",
			proc_prefix = "sand_",
		},
		sand_entries[:],
	)
	if !sand_ok do return false

	return true
}
