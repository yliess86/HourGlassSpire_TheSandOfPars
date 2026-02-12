package build

import "core:fmt"
import "core:os"
import "core:strings"

Align_KV :: struct {
	key:  string,
	val:  string,
	th:   string, // type hint (e.g. "# :u8")
	desc: string, // description comment (e.g. "# some text")
}

// Return indices of '#' characters that begin comments (skip hex colors and strings).
align_find_comment_starts :: proc(text: string) -> [dynamic]int {
	positions: [dynamic]int
	in_string := false
	i := 0
	for i < len(text) {
		c := text[i]
		if c == '"' {
			in_string = !in_string
			i += 1
			continue
		}
		if in_string {
			i += 1
			continue
		}
		if c == '#' {
			// Count consecutive hex digits after '#'
			hex_len := 0
			for j := i + 1; j < len(text); j += 1 {
				d := text[j]
				if (d >= '0' && d <= '9') || (d >= 'a' && d <= 'f') || (d >= 'A' && d <= 'F') {
					hex_len += 1
				} else {
					break
				}
			}
			// Skip hex colors: #RRGGBB or #RRGGBBAA (6-8 hex digits, next char NOT hex)
			if hex_len >= 6 && hex_len <= 8 {
				i += 1 + hex_len
				continue
			}
			append(&positions, i)
		}
		i += 1
	}
	return positions
}

// Split a "KEY = value  # :type  # description" line into parts.
align_parse_kv_line :: proc(line: string) -> (kv: Align_KV, ok: bool) {
	eq_idx := strings.index_byte(line, '=')
	if eq_idx < 0 do return {}, false

	key := strings.trim_space(line[:eq_idx])
	rest := strings.trim_left_space(line[eq_idx + 1:])

	starts := align_find_comment_starts(rest)
	defer delete(starts)

	if len(starts) == 0 {
		return Align_KV{key = key, val = strings.trim_right_space(rest)}, true
	}

	first := starts[0]
	value := strings.trim_right_space(rest[:first])
	comment := rest[first:]

	// Type hint: "# :type" pattern
	if len(comment) >= 3 && comment[1] == ' ' && comment[2] == ':' {
		if len(starts) >= 2 {
			second := starts[1]
			th := strings.trim_right_space(rest[first:second])
			desc := strings.trim_right_space(rest[second:])
			return Align_KV{key = key, val = value, th = th, desc = desc}, true
		}
		// Check for em-dash separator within single comment
		if idx := strings.index(comment, "\xe2\x80\x94"); idx >= 0 {
			th := strings.trim_right_space(comment[:idx])
			desc := fmt.tprintf("# %s", strings.trim_space(comment[idx + 3:]))
			return Align_KV{key = key, val = value, th = th, desc = desc}, true
		}
		return Align_KV{key = key, val = value, th = strings.trim_right_space(comment)}, true
	}

	return Align_KV{key = key, val = value, desc = strings.trim_right_space(comment)}, true
}

Align_Line :: struct {
	is_kv: bool,
	kv:    Align_KV,
	raw:   string, // passthrough line
}

// Read, align, and write back an INI file. Returns true on success.
align_ini_file :: proc(path: string) -> bool {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintf("Error: could not read %s\n", path)
		return false
	}
	defer delete(data)

	content := string(data)
	lines: [dynamic]Align_Line
	defer delete(lines)

	max_key := 0
	max_val := 0

	// Pass 1: parse all lines, compute global max widths
	for line in strings.split_lines_iterator(&content) {
		trimmed := strings.trim_space(line)
		if len(trimmed) > 0 &&
		   trimmed[0] != '#' &&
		   trimmed[0] != '[' &&
		   strings.index_byte(trimmed, '=') >= 0 {
			kv, ok := align_parse_kv_line(line)
			if ok {
				if len(kv.key) > max_key do max_key = len(kv.key)
				// Value portion includes type hint
				v_len := len(kv.val)
				if len(kv.th) > 0 do v_len += 2 + len(kv.th) // "  # :type"
				if v_len > max_val do max_val = v_len
				append(&lines, Align_Line{is_kv = true, kv = kv})
				continue
			}
		}
		append(&lines, Align_Line{raw = line})
	}

	// Pass 2: emit aligned lines
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	for line, i in lines {
		if i > 0 do strings.write_byte(&b, '\n')
		if !line.is_kv {
			strings.write_string(&b, line.raw)
			continue
		}

		kv := line.kv

		// Key padded to max_key
		strings.write_string(&b, kv.key)
		for _ in 0 ..< max_key - len(kv.key) do strings.write_byte(&b, ' ')
		strings.write_string(&b, " = ")

		// Value + optional type hint
		val_part := kv.val
		if len(kv.th) > 0 {
			val_part = fmt.tprintf("%s  %s", kv.val, kv.th)
		}

		if len(kv.desc) > 0 {
			strings.write_string(&b, val_part)
			for _ in 0 ..< max_val - len(val_part) do strings.write_byte(&b, ' ')
			strings.write_string(&b, "  ")
			strings.write_string(&b, kv.desc)
		} else {
			strings.write_string(&b, val_part)
		}
	}
	strings.write_byte(&b, '\n')

	output := strings.to_string(b)
	write_ok := os.write_entire_file(path, transmute([]u8)output)
	if !write_ok {
		fmt.eprintf("Error: could not write %s\n", path)
		return false
	}

	fmt.printf("Aligned %s\n", path)
	return true
}
