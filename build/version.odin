package build

import "core:c/libc"
import "core:crypto/legacy/md5"
import "core:fmt"
import "core:os"
import "core:strings"

version_stamp :: proc() -> (compact_name: string, hash_out: string, ok: bool) {
	data, read_ok := os.read_entire_file("assets/game.ini")
	if !read_ok {
		fmt.eprintf("Error: could not read assets/game.ini\n")
		return {}, {}, false
	}
	defer delete(data)

	content := string(data)

	// Extract VERSION_NAME value
	name := "Unknown"
	name_key :: "VERSION_NAME"
	if name_idx := strings.index(content, name_key); name_idx >= 0 {
		rest := content[name_idx + len(name_key):]
		if eq := strings.index_byte(rest, '='); eq >= 0 {
			after_eq := strings.trim_space(rest[eq + 1:])
			if len(after_eq) > 0 && after_eq[0] == '"' {
				end_quote := strings.index_byte(after_eq[1:], '"')
				if end_quote >= 0 do name = after_eq[1:][:end_quote]
			}
		}
	}

	// Get current UTC time
	raw_time := libc.time(nil)
	utc := libc.gmtime(&raw_time)

	date_str := fmt.tprintf("%02d-%02d-%04d", utc.tm_mday, utc.tm_mon + 1, utc.tm_year + 1900)
	time_str := fmt.tprintf("%02d:%02d:%02d", utc.tm_hour, utc.tm_min, utc.tm_sec)

	// Hash the full version string (MD5, first 7 hex chars)
	full := fmt.tprintf("%s - %s - %s", name, date_str, time_str)
	ctx: md5.Context
	md5.init(&ctx)
	md5.update(&ctx, transmute([]u8)full)
	digest: [md5.DIGEST_SIZE]u8
	md5.final(&ctx, digest[:])
	hash_str := fmt.tprintf("%02x%02x%02x%02x", digest[0], digest[1], digest[2], digest[3])[:7]

	fmt.printf("Version: %s\n", full)
	fmt.printf("Hash:    %s\n", hash_str)

	// Replace values in the file
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	remaining := content
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "VERSION_DATE") && strings.contains(trimmed, "=") {
			fmt.sbprintf(&b, "VERSION_DATE = \"%s\"\n", date_str)
		} else if strings.has_prefix(trimmed, "VERSION_TIME") && strings.contains(trimmed, "=") {
			fmt.sbprintf(&b, "VERSION_TIME = \"%s\"\n", time_str)
		} else if strings.has_prefix(trimmed, "VERSION_HASH") && strings.contains(trimmed, "=") {
			fmt.sbprintf(&b, "VERSION_HASH = \"%s\"\n", hash_str)
		} else {
			strings.write_string(&b, line)
			strings.write_string(&b, "\n")
		}
	}

	// Trim trailing extra newline (split_lines_iterator adds one after last line)
	output := strings.to_string(b)
	for strings.has_suffix(output, "\n\n") {
		output = output[:len(output) - 1]
	}

	write_ok := os.write_entire_file("assets/game.ini", transmute([]u8)output)
	if !write_ok {
		fmt.eprintf("Error: could not write assets/game.ini\n")
		return {}, {}, false
	}

	// Compact name: remove spaces (e.g. "Game Jam" → "GameJam")
	compact_name = strings.concatenate(strings.fields(name))
	hash_out = strings.clone(hash_str)
	return compact_name, hash_out, true
}
