package engine

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Config_Entry_Key :: distinct string

Config_Expression :: struct {
	value: f32,
}

Config_Color :: struct {
	value: [4]u8,
}

Config_String :: struct {
	value: string,
}

Config_Entry_Value :: union {
	Config_Expression,
	Config_Color,
	Config_String,
}

Config_Entry :: struct {
	key:   Config_Entry_Key,
	value: Config_Entry_Value,
}

Config :: struct {
	path:    string,
	entries: [dynamic]Config_Entry,
	lookup:  map[string]int,
}

config_load :: proc(path: string) -> (config: Config, ok: bool) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		fmt.eprintf("[config] Could not read '%s'\n", path)
		return {}, false
	}
	defer delete(data)

	config.path = strings.clone(path)
	config.entries = make([dynamic]Config_Entry)
	config.lookup = make(map[string]int)

	content := string(data)
	line_num := 0

	for line in strings.split_lines_iterator(&content) {
		line_num += 1
		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 do continue
		if trimmed[0] == '#' do continue
		if trimmed[0] == '[' do continue

		eq_idx := strings.index_byte(trimmed, '=')
		if eq_idx < 0 {
			fmt.eprintf("[config] Line %d: missing '=' in '%s'\n", line_num, trimmed)
			continue
		}

		key := strings.trim_space(trimmed[:eq_idx])
		raw_value := strings.trim_space(trimmed[eq_idx + 1:])
		expr := _strip_inline_comment(raw_value)

		if len(key) == 0 || len(expr) == 0 {
			fmt.eprintf("[config] Line %d: empty key or value\n", line_num)
			continue
		}

		val, eval_ok := _eval_expression(expr, &config)
		if !eval_ok {
			fmt.eprintf("[config] Line %d: failed to evaluate '%s'\n", line_num, expr)
			continue
		}

		idx := len(config.entries)
		append(
			&config.entries,
			Config_Entry{key = Config_Entry_Key(strings.clone(key)), value = val},
		)
		config.lookup[string(config.entries[idx].key)] = idx
	}

	return config, true
}

config_reload :: proc(config: ^Config) -> bool {
	data, read_ok := os.read_entire_file(config.path)
	if !read_ok {
		fmt.eprintf("[config] Could not re-read '%s'\n", config.path)
		return false
	}
	defer delete(data)

	for &entry in config.entries {
		delete(string(entry.key))
		if str, is_str := entry.value.(Config_String); is_str do delete(str.value)
	}
	clear(&config.entries)
	clear(&config.lookup)

	content := string(data)
	line_num := 0

	for line in strings.split_lines_iterator(&content) {
		line_num += 1
		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 do continue
		if trimmed[0] == '#' do continue
		if trimmed[0] == '[' do continue

		eq_idx := strings.index_byte(trimmed, '=')
		if eq_idx < 0 do continue

		key := strings.trim_space(trimmed[:eq_idx])
		raw_value := strings.trim_space(trimmed[eq_idx + 1:])
		expr := _strip_inline_comment(raw_value)

		if len(key) == 0 || len(expr) == 0 do continue

		val, eval_ok := _eval_expression(expr, config)
		if !eval_ok {
			fmt.eprintf("[config] Line %d: failed to evaluate '%s'\n", line_num, expr)
			continue
		}

		idx := len(config.entries)
		append(
			&config.entries,
			Config_Entry{key = Config_Entry_Key(strings.clone(key)), value = val},
		)
		config.lookup[string(config.entries[idx].key)] = idx
	}

	return true
}

config_get_f32 :: proc(config: ^Config, key: string) -> (val: f32, ok: bool) {
	idx, found := config.lookup[key]
	if !found do return 0, false
	expr, is_expr := config.entries[idx].value.(Config_Expression)
	if !is_expr do return 0, false
	return expr.value, true
}

config_get_u8 :: proc(config: ^Config, key: string) -> (val: u8, ok: bool) {
	f, f_ok := config_get_f32(config, key)
	if !f_ok do return 0, false
	return u8(clamp(f, 0, 255)), true
}

config_get_rgba :: proc(config: ^Config, key: string) -> (val: [4]u8, ok: bool) {
	idx, found := config.lookup[key]
	if !found do return {}, false
	color, is_color := config.entries[idx].value.(Config_Color)
	if !is_color do return {}, false
	return color.value, true
}

config_get_string :: proc(config: ^Config, key: string) -> (val: string, ok: bool) {
	idx, found := config.lookup[key]
	if !found do return "", false
	str, is_str := config.entries[idx].value.(Config_String)
	if !is_str do return "", false
	return str.value, true
}

config_destroy :: proc(config: ^Config) {
	for &entry in config.entries {
		delete(string(entry.key))
		if str, is_str := entry.value.(Config_String); is_str do delete(str.value)
	}
	delete(config.entries)
	delete(config.lookup)
	delete(config.path)
}

@(private = "file")
Token_Kind :: enum u8 {
	Number,
	Ident,
	Hex_Color,
	Plus,
	Minus,
	Star,
	Slash,
	Lparen,
	Rparen,
	EOF,
}

@(private = "file")
Token_Value :: union {
	f32,
	[4]u8,
	string,
}

@(private = "file")
Token :: struct {
	kind:  Token_Kind,
	value: Token_Value,
}

@(private = "file")
Tokenizer :: struct {
	src: string,
	pos: int,
}

@(private = "file")
_strip_inline_comment :: proc(s: string) -> string {
	if len(s) > 0 && s[0] == '"' {
		for i in 1 ..< len(s) {
			if s[i] == '"' {
				rest := s[i + 1:]
				for j in 0 ..< len(rest) {
					if rest[j] == '#' do return strings.trim_space(s[:i + 1 + j])
				}
				return strings.trim_space(s[:i + 1])
			}
		}
		return s
	}

	if len(s) > 0 && s[0] == '#' {
		for i in 1 ..< len(s) {
			if s[i] == '#' && i > 0 && (s[i - 1] == ' ' || s[i - 1] == '\t') {
				return strings.trim_space(s[:i])
			}
		}
		return s
	}

	for i in 0 ..< len(s) {
		if s[i] == '#' {
			if i == 0 do return ""
			return strings.trim_space(s[:i])
		}
	}
	return s
}

@(private = "file")
_skip_whitespace :: proc(t: ^Tokenizer) {
	for t.pos < len(t.src) && (t.src[t.pos] == ' ' || t.src[t.pos] == '\t') do t.pos += 1
}

@(private = "file")
_is_alpha :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

@(private = "file")
_is_alnum :: proc(c: u8) -> bool {
	return _is_alpha(c) || (c >= '0' && c <= '9')
}

@(private = "file")
_is_hex :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

@(private = "file")
_hex_digit :: proc(c: u8) -> u8 {
	if c >= '0' && c <= '9' do return c - '0'
	if c >= 'a' && c <= 'f' do return c - 'a' + 10
	if c >= 'A' && c <= 'F' do return c - 'A' + 10
	return 0
}

@(private = "file")
SINGLE_CHAR_TOKENS := [256]Maybe(Token_Kind) {
	'+' = .Plus,
	'-' = .Minus,
	'*' = .Star,
	'/' = .Slash,
	'(' = .Lparen,
	')' = .Rparen,
}

@(private = "file")
_next_token :: proc(t: ^Tokenizer) -> (tok: Token, ok: bool) {
	_skip_whitespace(t)
	if t.pos >= len(t.src) do return Token{kind = .EOF}, true

	c := t.src[t.pos]

	if c == '#' {
		start := t.pos + 1
		end := start
		for end < len(t.src) && _is_hex(t.src[end]) do end += 1
		hex_len := end - start
		if hex_len == 8 {
			r := _hex_digit(t.src[start + 0]) * 16 + _hex_digit(t.src[start + 1])
			g := _hex_digit(t.src[start + 2]) * 16 + _hex_digit(t.src[start + 3])
			b := _hex_digit(t.src[start + 4]) * 16 + _hex_digit(t.src[start + 5])
			a := _hex_digit(t.src[start + 6]) * 16 + _hex_digit(t.src[start + 7])
			t.pos = end
			return Token{kind = .Hex_Color, value = [4]u8{r, g, b, a}}, true
		}
		return {}, false
	}

	if (c >= '0' && c <= '9') || c == '.' {
		start := t.pos
		has_dot := false
		for t.pos < len(t.src) {
			ch := t.src[t.pos]
			if ch == '.' {
				if has_dot do break
				has_dot = true
				t.pos += 1
			} else if ch >= '0' && ch <= '9' do t.pos += 1
			else do break
		}
		num_str := t.src[start:t.pos]
		val, parse_ok := strconv.parse_f32(num_str)
		if !parse_ok do return {}, false
		return Token{kind = .Number, value = val}, true
	}

	if _is_alpha(c) {
		start := t.pos
		for t.pos < len(t.src) && _is_alnum(t.src[t.pos]) do t.pos += 1
		return Token{kind = .Ident, value = t.src[start:t.pos]}, true
	}

	t.pos += 1
	kind, is_single := SINGLE_CHAR_TOKENS[c].?
	if is_single do return Token{kind = kind}, true
	return {}, false
}

// Recursive descent expression parser
// value   → HEX_COLOR  |  expr
// expr    → term (('+' | '-') term)*
// term    → unary (('*' | '/') unary)*
// unary   → '-' unary  |  primary
// primary → NUMBER  |  IDENT  |  '(' expr ')'

@(private = "file")
Parser :: struct {
	tokenizer: Tokenizer,
	current:   Token,
	config:    ^Config,
	ok:        bool,
}

@(private = "file")
_parser_init :: proc(src: string, config: ^Config) -> Parser {
	p := Parser {
		tokenizer = Tokenizer{src = src, pos = 0},
		config = config,
		ok = true,
	}
	tok, tok_ok := _next_token(&p.tokenizer)
	p.current = tok
	p.ok = tok_ok
	return p
}

@(private = "file")
_parser_advance :: proc(p: ^Parser) {
	tok, tok_ok := _next_token(&p.tokenizer)
	p.current = tok
	if !tok_ok do p.ok = false
}

@(private = "file")
_parse_primary :: proc(p: ^Parser) -> f32 {
	if !p.ok do return 0

	#partial switch p.current.kind {
	case .Number:
		val := p.current.value.(f32)
		_parser_advance(p)
		return val
	case .Ident:
		name := p.current.value.(string)
		_parser_advance(p)

		idx, found := p.config.lookup[name]
		if !found {
			p.ok = false
			return 0
		}
		expr, is_expr := p.config.entries[idx].value.(Config_Expression)
		if !is_expr {
			p.ok = false
			return 0
		}
		return expr.value
	case .Lparen:
		_parser_advance(p) // consume '('
		val := _parse_expr(p)
		if p.current.kind != .Rparen {
			p.ok = false
			return 0
		}
		_parser_advance(p) // consume ')'
		return val
	}

	p.ok = false
	return 0
}

@(private = "file")
_parse_unary :: proc(p: ^Parser) -> f32 {
	if !p.ok do return 0
	if p.current.kind == .Minus {
		_parser_advance(p)
		return -_parse_unary(p)
	}
	return _parse_primary(p)
}

@(private = "file")
_parse_term :: proc(p: ^Parser) -> f32 {
	if !p.ok do return 0
	left := _parse_unary(p)
	for p.ok && (p.current.kind == .Star || p.current.kind == .Slash) {
		op := p.current.kind
		_parser_advance(p)
		right := _parse_unary(p)
		if op == .Star do left *= right
		else {
			if right == 0 {
				p.ok = false
				return 0
			}
			left /= right
		}
	}
	return left
}

@(private = "file")
_parse_expr :: proc(p: ^Parser) -> f32 {
	if !p.ok do return 0
	left := _parse_term(p)
	for p.ok && (p.current.kind == .Plus || p.current.kind == .Minus) {
		op := p.current.kind
		_parser_advance(p)
		right := _parse_term(p)
		if op == .Plus do left += right
		else do left -= right
	}
	return left
}

@(private = "file")
_eval_expression :: proc(expr: string, config: ^Config) -> (val: Config_Entry_Value, ok: bool) {
	trimmed := strings.trim_space(expr)

	if len(trimmed) >= 2 && trimmed[0] == '"' {
		for i in 1 ..< len(trimmed) {
			if trimmed[i] == '"' do return Config_String{value = strings.clone(trimmed[1:i])}, true
		}
		return nil, false
	}

	if len(trimmed) > 0 && trimmed[0] == '#' {
		t := Tokenizer {
			src = trimmed,
			pos = 0,
		}
		tok, tok_ok := _next_token(&t)
		if tok_ok && tok.kind == .Hex_Color do return Config_Color{value = tok.value.([4]u8)}, true
		return nil, false
	}

	p := _parser_init(trimmed, config)
	result := _parse_expr(&p)
	if !p.ok do return nil, false
	if p.current.kind != .EOF do return nil, false
	return Config_Expression{value = result}, true
}
