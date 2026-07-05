package bbcode

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"

parse_opacity :: proc(val: string) -> f32 {
	f, ok := strconv.parse_f64(val)
	if !ok do return 1.0
	if f > 1.0 do return f32(f / 255.0)
	return f32(f)
}


Log_Tag :: enum {
	Time,
	Location,
	Level,
	Message,
	Thread_Id,
}

Log_Tags :: bit_set[Log_Tag]


ANSI_RESET :: "\x1b[0m"
ANSI_BOLD :: "\x1b[1m"
ANSI_ITALIC :: "\x1b[3m"

ANSI_BLACK :: "\x1b[30m"
ANSI_RED :: "\x1b[31m"
ANSI_GREEN :: "\x1b[32m"
ANSI_YELLOW :: "\x1b[33m"
ANSI_BLUE :: "\x1b[34m"
ANSI_MAGENTA :: "\x1b[35m"
ANSI_CYAN :: "\x1b[36m"
ANSI_WHITE :: "\x1b[37m"

ANSI_GRAY :: "\x1b[90m"
ANSI_BRIGHT_RED :: "\x1b[91m"
ANSI_BRIGHT_GREEN :: "\x1b[92m"
ANSI_BRIGHT_YELLOW :: "\x1b[93m"
ANSI_BRIGHT_BLUE :: "\x1b[94m"
ANSI_BRIGHT_MAGENTA :: "\x1b[95m"
ANSI_BRIGHT_CYAN :: "\x1b[96m"
ANSI_BRIGHT_WHITE :: "\x1b[97m"

ANSI_TRUECOLOR_FORMAT :: "\x1b[38;2;%d;%d;%dm"

ANSI_BG_BLACK :: "\x1b[40m"
ANSI_BG_RED :: "\x1b[41m"
ANSI_BG_GREEN :: "\x1b[42m"
ANSI_BG_YELLOW :: "\x1b[43m"
ANSI_BG_BLUE :: "\x1b[44m"
ANSI_BG_MAGENTA :: "\x1b[45m"
ANSI_BG_CYAN :: "\x1b[46m"
ANSI_BG_WHITE :: "\x1b[47m"
ANSI_BG_GRAY :: "\x1b[100m"

ANSI_TRUECOLOR_BG_FORMAT :: "\x1b[48;2;%d;%d;%dm"

ANSI_UNDERLINE :: "\x1b[4m"
ANSI_STRIKETHROUGH :: "\x1b[9m"

Color_Mapping :: struct {
	name: string,
	ansi: string,
}

PREDEFINED_COLORS := [?]Color_Mapping {
	{"black", ANSI_BLACK},
	{"red", ANSI_RED},
	{"green", ANSI_GREEN},
	{"yellow", ANSI_YELLOW},
	{"blue", ANSI_BLUE},
	{"magenta", ANSI_MAGENTA},
	{"purple", ANSI_MAGENTA},
	{"cyan", ANSI_CYAN},
	{"white", ANSI_WHITE},
	{"gray", ANSI_GRAY},
	{"grey", ANSI_GRAY},
	{"dark_gray", ANSI_GRAY},
	{"dark_grey", ANSI_GRAY},
	{"bright_black", ANSI_GRAY},
	{"bright_red", ANSI_BRIGHT_RED},
	{"bright_green", ANSI_BRIGHT_GREEN},
	{"bright_yellow", ANSI_BRIGHT_YELLOW},
	{"bright_blue", ANSI_BRIGHT_BLUE},
	{"bright_magenta", ANSI_BRIGHT_MAGENTA},
	{"bright_purple", ANSI_BRIGHT_MAGENTA},
	{"bright_cyan", ANSI_BRIGHT_CYAN},
	{"bright_white", ANSI_BRIGHT_WHITE},
	{"orange", "\x1b[38;2;255;128;0m"},
}

PREDEFINED_BG_COLORS := [?]Color_Mapping {
	{"black", ANSI_BG_BLACK},
	{"red", ANSI_BG_RED},
	{"green", ANSI_BG_GREEN},
	{"yellow", ANSI_BG_YELLOW},
	{"blue", ANSI_BG_BLUE},
	{"magenta", ANSI_BG_MAGENTA},
	{"purple", ANSI_BG_MAGENTA},
	{"cyan", ANSI_BG_CYAN},
	{"white", ANSI_BG_WHITE},
	{"gray", ANSI_BG_GRAY},
	{"grey", ANSI_BG_GRAY},
	{"dark_gray", ANSI_BG_GRAY},
	{"dark_grey", ANSI_BG_GRAY},
	{"bright_black", ANSI_BG_GRAY},
	{"orange", "\x1b[48;2;255;128;0m"},
	{"bright_red", "\x1b[101m"},
	{"bright_green", "\x1b[102m"},
	{"bright_yellow", "\x1b[103m"},
	{"bright_blue", "\x1b[104m"},
	{"bright_magenta", "\x1b[105m"},
	{"bright_purple", "\x1b[105m"},
	{"bright_cyan", "\x1b[106m"},
	{"bright_white", "\x1b[107m"},
}

Color_Entry :: struct {
	ansi:    string,
	r, g, b: u8,
	is_hex:  bool,
}

parse_color :: proc(tag: string) -> (entry: Color_Entry, ok: bool) {
	for mapping in PREDEFINED_COLORS {
		if mapping.name == tag {
			return Color_Entry{ansi = mapping.ansi, is_hex = false}, true
		}
	}

	r, g, b, hex_ok := parse_hex_color(tag)
	if hex_ok {
		return Color_Entry{r = r, g = g, b = b, is_hex = true}, true
	}

	return {}, false
}

parse_bg_color :: proc(tag: string) -> (entry: Color_Entry, ok: bool) {
	for mapping in PREDEFINED_BG_COLORS {
		if mapping.name == tag {
			return Color_Entry{ansi = mapping.ansi, is_hex = false}, true
		}
	}

	r, g, b, hex_ok := parse_hex_color(tag)
	if hex_ok {
		return Color_Entry{r = r, g = g, b = b, is_hex = true}, true
	}

	return {}, false
}

write_bg_color_entry :: proc(builder: ^strings.Builder, entry: Color_Entry) {
	if entry.is_hex {
		fmt.sbprintf(builder, ANSI_TRUECOLOR_BG_FORMAT, entry.r, entry.g, entry.b)
	} else {
		strings.write_string(builder, entry.ansi)
	}
}

parse_hex_color :: proc(hex: string) -> (r, g, b: u8, ok: bool) {
	s := hex
	if len(s) > 0 && s[0] == '#' {
		s = s[1:]
	}

	hex_digit :: proc(c: u8) -> (u8, bool) {
		switch c {
		case '0' ..= '9':
			return c - '0', true
		case 'a' ..= 'f':
			return c - 'a' + 10, true
		case 'A' ..= 'F':
			return c - 'A' + 10, true
		}
		return 0, false
	}

	if len(s) == 6 {
		r1, ok1 := hex_digit(s[0])
		r2, ok2 := hex_digit(s[1])
		g1, ok3 := hex_digit(s[2])
		g2, ok4 := hex_digit(s[3])
		b1, ok5 := hex_digit(s[4])
		b2, ok6 := hex_digit(s[5])
		if ok1 && ok2 && ok3 && ok4 && ok5 && ok6 {
			return (r1 << 4) | r2, (g1 << 4) | g2, (b1 << 4) | b2, true
		}
	} else if len(s) == 3 {
		r1, ok1 := hex_digit(s[0])
		g1, ok2 := hex_digit(s[1])
		b1, ok3 := hex_digit(s[2])
		if ok1 && ok2 && ok3 {
			return r1 * 17, g1 * 17, b1 * 17, true
		}
	}
	return 0, 0, 0, false
}

write_color_entry :: proc(builder: ^strings.Builder, entry: Color_Entry) {
	if entry.is_hex {
		fmt.sbprintf(builder, ANSI_TRUECOLOR_FORMAT, entry.r, entry.g, entry.b)
	} else {
		strings.write_string(builder, entry.ansi)
	}
}

Tag_Type :: enum {
	Color,
	BgColor,
	Bold,
	Italic,
	Underline,
	Strikethrough,
	Opacity,
	BgOpacity,
	FontSize,
	FontPath,
}

Tag :: struct {
	type:      Tag_Type,
	color:     Color_Entry,
	color_str: string,
	opacity:   f32,
	font_size: f32,
	font_path: string,
}

Style :: struct {
	bold:          bool,
	italic:        bool,
	underline:     bool,
	strikethrough: bool,
	color_str:     string,
	bg_color_str:  string,
	has_bg:        bool,
	opacity:       f32,
	bg_opacity:    f32,
	font_size:     f32,
	font_path:     string,
}

Span :: struct {
	text:  string,
	style: Style,
}

Tag_Handler :: struct {
	open_match:  string,
	close_match: string,
	tag_type:    Tag_Type,
	validate:    proc(content: string) -> (err_msg: string, ok: bool),
	parse:       proc(content: string) -> Tag,
}

tag_matches :: proc(content: string, handler: Tag_Handler, is_close: bool) -> bool {
	if is_close {
		return content == handler.close_match
	} else {
		if strings.has_suffix(handler.open_match, "=") {
			return strings.has_prefix(content, handler.open_match)
		} else {
			return content == handler.open_match
		}
	}
}

validate_always_ok :: proc(content: string) -> (err_msg: string, ok: bool) {
	return "", true
}

validate_color :: proc(content: string) -> (err_msg: string, ok: bool) {
	idx := strings.index_byte(content, '=')
	if idx == -1 do return "BBCode Error: Missing value in color tag", false
	val := content[idx + 1:]
	_, ok_color := parse_color(val)
	if !ok_color {
		return fmt.tprintf("BBCode Error: Unknown or invalid color tag '%s'", content), false
	}
	return "", true
}

validate_bg_color :: proc(content: string) -> (err_msg: string, ok: bool) {
	idx := strings.index_byte(content, '=')
	if idx == -1 do return "BBCode Error: Missing value in background color tag", false
	val := content[idx + 1:]
	_, ok_color := parse_bg_color(val)
	if !ok_color {
		return fmt.tprintf("BBCode Error: Unknown or invalid background color tag '%s'", content),
			false
	}
	return "", true
}

validate_opacity :: proc(content: string) -> (err_msg: string, ok: bool) {
	idx := strings.index_byte(content, '=')
	if idx == -1 do return "BBCode Error: Missing value in opacity tag", false
	return "", true
}

validate_font_size :: proc(content: string) -> (err_msg: string, ok: bool) {
	idx := strings.index_byte(content, '=')
	if idx == -1 do return "BBCode Error: Missing value in font_size tag", false
	return "", true
}

parse_bold :: proc(content: string) -> Tag {
	return Tag{type = .Bold}
}

parse_italic :: proc(content: string) -> Tag {
	return Tag{type = .Italic}
}

parse_underline :: proc(content: string) -> Tag {
	return Tag{type = .Underline}
}

parse_strikethrough :: proc(content: string) -> Tag {
	return Tag{type = .Strikethrough}
}

parse_color_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	entry, _ := parse_color(val)
	return Tag{type = .Color, color = entry, color_str = val}
}

parse_bg_color_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	entry, _ := parse_bg_color(val)
	return Tag{type = .BgColor, color = entry, color_str = val}
}

parse_opacity_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	return Tag{type = .Opacity, opacity = parse_opacity(val)}
}

parse_bg_opacity_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	return Tag{type = .BgOpacity, opacity = parse_opacity(val)}
}

parse_font_size_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	f, ok := strconv.parse_f64(val)
	fs := f32(f) if ok else f32(0.0)
	return Tag{type = .FontSize, font_size = fs}
}

parse_font_path_tag :: proc(content: string) -> Tag {
	idx := strings.index_byte(content, '=')
	val := content[idx + 1:]
	if len(val) >= 2 && val[0] == '"' && val[len(val) - 1] == '"' {
		val = val[1:len(val) - 1]
	}
	return Tag{type = .FontPath, font_path = val}
}

TAG_HANDLERS := []Tag_Handler {
	{
		open_match = "b",
		close_match = "/b",
		tag_type = .Bold,
		validate = validate_always_ok,
		parse = parse_bold,
	},
	{
		open_match = "i",
		close_match = "/i",
		tag_type = .Italic,
		validate = validate_always_ok,
		parse = parse_italic,
	},
	{
		open_match = "u",
		close_match = "/u",
		tag_type = .Underline,
		validate = validate_always_ok,
		parse = parse_underline,
	},
	{
		open_match = "s",
		close_match = "/s",
		tag_type = .Strikethrough,
		validate = validate_always_ok,
		parse = parse_strikethrough,
	},
	{
		open_match = "c=",
		close_match = "/c",
		tag_type = .Color,
		validate = validate_color,
		parse = parse_color_tag,
	},
	{
		open_match = "color=",
		close_match = "/color",
		tag_type = .Color,
		validate = validate_color,
		parse = parse_color_tag,
	},
	{
		open_match = "bg=",
		close_match = "/bg",
		tag_type = .BgColor,
		validate = validate_bg_color,
		parse = parse_bg_color_tag,
	},
	{
		open_match = "bg_color=",
		close_match = "/bg_color",
		tag_type = .BgColor,
		validate = validate_bg_color,
		parse = parse_bg_color_tag,
	},
	{
		open_match = "opacity=",
		close_match = "/opacity",
		tag_type = .Opacity,
		validate = validate_opacity,
		parse = parse_opacity_tag,
	},
	{
		open_match = "bg_opacity=",
		close_match = "/bg_opacity",
		tag_type = .BgOpacity,
		validate = validate_opacity,
		parse = parse_bg_opacity_tag,
	},
	{
		open_match = "font_size=",
		close_match = "/font_size",
		tag_type = .FontSize,
		validate = validate_font_size,
		parse = parse_font_size_tag,
	},
	{
		open_match = "font=",
		close_match = "/font",
		tag_type = .FontPath,
		validate = validate_always_ok,
		parse = parse_font_path_tag,
	},
}

remove_last_tag :: proc(stack: ^[dynamic]Tag, type: Tag_Type) {
	for i := len(stack^) - 1; i >= 0; i -= 1 {
		if stack[i].type == type {
			ordered_remove(stack, i)
			break
		}
	}
}

apply_styles :: proc(builder: ^strings.Builder, stack: [dynamic]Tag) {
	strings.write_string(builder, ANSI_RESET)

	active_color: ^Color_Entry = nil
	active_bg_color: ^Color_Entry = nil
	has_bold := false
	has_italic := false
	has_underline := false
	has_strikethrough := false

	for &tag in stack {
		#partial switch tag.type {
		case .Color:
			active_color = &tag.color
		case .BgColor:
			active_bg_color = &tag.color
		case .Bold:
			has_bold = true
		case .Italic:
			has_italic = true
		case .Underline:
			has_underline = true
		case .Strikethrough:
			has_strikethrough = true
		}
	}

	if has_bold {
		strings.write_string(builder, ANSI_BOLD)
	}
	if has_italic {
		strings.write_string(builder, ANSI_ITALIC)
	}
	if has_underline {
		strings.write_string(builder, ANSI_UNDERLINE)
	}
	if has_strikethrough {
		strings.write_string(builder, ANSI_STRIKETHROUGH)
	}
	if active_color != nil {
		write_color_entry(builder, active_color^)
	}
	if active_bg_color != nil {
		write_bg_color_entry(builder, active_bg_color^)
	}
}

validate_and_format_bbcode :: proc(
	text: string,
	enable_color: bool,
	allow_variables: bool,
	time_str := "",
	location_str := "",
	level_str := "",
	message_str := "",
	thread_id_str := "",
	allocator := context.allocator,
	suppressed_tags: Log_Tags = {},
) -> (
	result: string,
	err_msg: string,
	ok: bool,
) {
	builder := strings.builder_make(allocator)

	tag_stack: [dynamic]Tag
	tag_stack.allocator = allocator
	defer delete(tag_stack)

	i := 0
	n := len(text)
	for i < n {
		if text[i] == '\\' && i + 1 < n && (text[i + 1] == '[' || text[i + 1] == ']') {
			strings.write_byte(&builder, text[i + 1])
			i += 2
			continue
		}

		if text[i] == '[' {
			is_double := i + 1 < n && text[i + 1] == '['

			close_idx := -1
			if is_double {
				bracket_count := 2
				j := i + 2
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						if bracket_count == 2 && j + 1 < n && text[j + 1] == ']' {
							close_idx = j
							break
						}
						bracket_count -= 1
						j += 1
					} else {
						j += 1
					}
				}
			} else {
				bracket_count := 1
				j := i + 1
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						bracket_count -= 1
						if bracket_count == 0 {
							close_idx = j
							break
						}
						j += 1
					} else {
						j += 1
					}
				}
			}

			if close_idx == -1 {
				strings.builder_destroy(&builder)
				return "",
					strings.clone(
						"BBCode Error: Unescaped or unclosed bracket '[' found",
						allocator,
					),
					false
			}

			tag_content := text[i + 2:close_idx] if is_double else text[i + 1:close_idx]

			is_suppressed := false
			if tag_content == "time" && .Time in suppressed_tags {
				is_suppressed = true
			} else if tag_content == "location" && .Location in suppressed_tags {
				is_suppressed = true
			} else if tag_content == "level" && .Level in suppressed_tags {
				is_suppressed = true
			} else if tag_content == "message" && .Message in suppressed_tags {
				is_suppressed = true
			} else if tag_content == "thread_id" && .Thread_Id in suppressed_tags {
				is_suppressed = true
			}

			if is_suppressed {
				i = close_idx + 2 if is_double else close_idx + 1
				continue
			}

			if is_double {
				strings.write_byte(&builder, '[')
			}
			err, tag_ok := process_tag(
				tag_content,
				&tag_stack,
				&builder,
				enable_color,
				allow_variables,
				time_str,
				location_str,
				level_str,
				message_str,
				thread_id_str,
				allocator,
				suppressed_tags,
			)
			if !tag_ok {
				strings.builder_destroy(&builder)
				return "", err, false
			}
			if is_double {
				strings.write_byte(&builder, ']')
			}

			i = close_idx + 2 if is_double else close_idx + 1
			continue
		} else if text[i] == ']' {
			strings.builder_destroy(&builder)
			return "",
				strings.clone("BBCode Error: Unescaped closing bracket ']' found", allocator),
				false
		}

		strings.write_byte(&builder, text[i])
		i += 1
	}

	if len(tag_stack) > 0 {
		strings.builder_destroy(&builder)
		return "",
			strings.clone("BBCode Error: Unclosed tags remaining at end of string", allocator),
			false
	}

	return strings.to_string(builder), "", true
}

@(private)
process_tag :: proc(
	tag_content: string,
	tag_stack: ^[dynamic]Tag,
	builder: ^strings.Builder,
	enable_color: bool,
	allow_variables: bool,
	time_str, location_str, level_str, message_str, thread_id_str: string,
	allocator: runtime.Allocator,
	suppressed_tags: Log_Tags = {},
) -> (
	err_msg: string,
	ok: bool,
) {
	is_close := strings.has_prefix(tag_content, "/")

	for handler in TAG_HANDLERS {
		if tag_matches(tag_content, handler, is_close) {
			if is_close {
				has_tag := false
				for t in tag_stack {
					if t.type == handler.tag_type {has_tag = true; break}
				}
				if !has_tag {
					return fmt.aprintf(
							"BBCode Error: Closing tag [%s] has no matching open tag",
							tag_content,
							allocator = allocator,
						),
						false
				}
				remove_last_tag(tag_stack, handler.tag_type)
				if enable_color {
					apply_styles(builder, tag_stack^)
				}
			} else {
				err, val_ok := handler.validate(tag_content)
				if !val_ok {
					return strings.clone(err, allocator), false
				}
				tag := handler.parse(tag_content)
				append(tag_stack, tag)
				if enable_color {
					apply_styles(builder, tag_stack^)
				}
			}
			return "", true
		}
	}

	if tag_content == "time" {
		if !allow_variables {
			return strings.clone(
					"BBCode Error: Tag 'time' is not allowed in this context",
					allocator,
				),
				false
		}
		strings.write_string(builder, time_str)
	} else if tag_content == "location" {
		if !allow_variables {
			return strings.clone(
					"BBCode Error: Tag 'location' is not allowed in this context",
					allocator,
				),
				false
		}
		strings.write_string(builder, location_str)
	} else if tag_content == "level" {
		if !allow_variables {
			return strings.clone(
					"BBCode Error: Tag 'level' is not allowed in this context",
					allocator,
				),
				false
		}
		strings.write_string(builder, level_str)
	} else if tag_content == "message" {
		if !allow_variables {
			return strings.clone(
					"BBCode Error: Tag 'message' is not allowed in this context",
					allocator,
				),
				false
		}
		strings.write_string(builder, message_str)
	} else if tag_content == "thread_id" {
		if !allow_variables {
			return strings.clone(
					"BBCode Error: Tag 'thread_id' is not allowed in this context",
					allocator,
				),
				false
		}
		strings.write_string(builder, thread_id_str)
	} else {
		name, args := parse_tag_name_and_args(tag_content)
		is_tag_func := false
		for entry in get_tag_funcs() {
			if entry.name == name {
				is_tag_func = true
				ctx := Tag_Func_Context {
					enable_color    = enable_color,
					allow_variables = allow_variables,
					time_str        = time_str,
					location_str    = location_str,
					level_str       = level_str,
					message_str     = message_str,
					thread_id_str   = thread_id_str,
					suppressed_tags = suppressed_tags,
				}
				res, err, tag_ok := entry.fn(args, ctx, allocator)
				if !tag_ok {
					return err, false
				}
				strings.write_string(builder, res)
				delete(res, allocator)
				break
			}
		}

		if !is_tag_func {
			err_str := fmt.aprintf(
				"BBCode Error: Unknown or invalid tag '%s'",
				tag_content,
				allocator = allocator,
			)
			return err_str, false
		}
	}

	return "", true
}

validate :: proc(text: string, allow_variables := false) -> (err_msg: string, ok: bool) {
	tag_stack: [dynamic]Tag_Type
	defer delete(tag_stack)

	i := 0
	n := len(text)
	for i < n {
		if text[i] == '\\' && i + 1 < n && (text[i + 1] == '[' || text[i + 1] == ']') {
			i += 2
			continue
		}

		if text[i] == '[' {
			is_double := i + 1 < n && text[i + 1] == '['

			close_idx := -1
			if is_double {
				bracket_count := 2
				j := i + 2
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						if bracket_count == 2 && j + 1 < n && text[j + 1] == ']' {
							close_idx = j
							break
						}
						bracket_count -= 1
						j += 1
					} else {
						j += 1
					}
				}
			} else {
				bracket_count := 1
				j := i + 1
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						bracket_count -= 1
						if bracket_count == 0 {
							close_idx = j
							break
						}
						j += 1
					} else {
						j += 1
					}
				}
			}

			if close_idx == -1 {
				return "BBCode Error: Unescaped or unclosed bracket '[' found", false
			}
			tag_content := text[i + 2:close_idx] if is_double else text[i + 1:close_idx]
			found_handler := false
			is_close := strings.has_prefix(tag_content, "/")

			for handler in TAG_HANDLERS {
				if tag_matches(tag_content, handler, is_close) {
					found_handler = true
					if is_close {
						if !pop_expected_tag(&tag_stack, handler.tag_type) {
							return fmt.tprintf(
									"BBCode Error: Closing tag [%s] has no matching open tag",
									tag_content,
								),
								false
						}
					} else {
						err, val_ok := handler.validate(tag_content)
						if !val_ok do return err, false
						append(&tag_stack, handler.tag_type)
					}
					break
				}
			}

			if !found_handler {
				if tag_content == "time" ||
				   tag_content == "location" ||
				   tag_content == "level" ||
				   tag_content == "message" ||
				   tag_content == "thread_id" {
					if !allow_variables {
						return fmt.tprintf(
								"BBCode Error: Tag '%s' is not allowed in this context",
								tag_content,
							),
							false
					}
				} else {
					name, args := parse_tag_name_and_args(tag_content)
					is_tag_func := false
					for entry in get_tag_funcs() {
						if entry.name == name {
							is_tag_func = true
							if name == "if" {
								cond, then_val, else_val, has_else, args_ok := split_if_args(args)
								if !args_ok {
									return "BBCode Error: Conditional tag 'if' must have format 'if <condition>: <value>' or 'if <condition>: <then-value> ? <else-value>'",
										false
								}

								if !validate_condition(cond) {
									return fmt.tprintf(
											"BBCode Error: Invalid condition syntax '%s'",
											cond,
										),
										false
								}

								then_trimmed := strings.trim_space(then_val)
								if len(then_trimmed) >= 2 &&
								   then_trimmed[0] == '"' &&
								   then_trimmed[len(then_trimmed) - 1] == '"' {
									then_trimmed = then_trimmed[1:len(then_trimmed) - 1]
								}

								then_err, then_ok := validate(then_trimmed, allow_variables)
								if !then_ok {
									return then_err, false
								}

								if has_else {
									else_trimmed := strings.trim_space(else_val)
									if len(else_trimmed) >= 2 &&
									   else_trimmed[0] == '"' &&
									   else_trimmed[len(else_trimmed) - 1] == '"' {
										else_trimmed = else_trimmed[1:len(else_trimmed) - 1]
									}

									else_err, else_ok := validate(else_trimmed, allow_variables)
									if !else_ok {
										return else_err, false
									}
								}
							} else {
								if args != "" {
									val_err, val_ok := validate(args, allow_variables)
									if !val_ok {
										return val_err, false
									}
								}
							}
							break
						}
					}

					if !is_tag_func {
						return fmt.tprintf(
								"BBCode Error: Unknown or invalid tag '%s'",
								tag_content,
							),
							false
					}
				}
			}

			i = close_idx + 2 if is_double else close_idx + 1
			continue
		} else if text[i] == ']' {
			return "BBCode Error: Unescaped closing bracket ']' found", false
		}

		i += 1
	}

	if len(tag_stack) > 0 {
		return "BBCode Error: Unclosed tags remaining at end of string", false
	}

	return "", true
}

@(private)
pop_expected_tag :: proc(stack: ^[dynamic]Tag_Type, expected: Tag_Type) -> bool {
	for i := len(stack^) - 1; i >= 0; i -= 1 {
		if stack[i] == expected {
			ordered_remove(stack, i)
			return true
		}
	}
	return false
}

format :: proc(
	text: string,
	enable_color := true,
	allocator := context.allocator,
) -> (
	result: string,
	err_msg: string,
	ok: bool,
) {
	err, val_ok := validate(text, false)
	if !val_ok {
		return "", strings.clone(err, allocator), false
	}

	res, format_err, format_ok := validate_and_format_bbcode(
		text,
		enable_color,
		false,
		allocator = allocator,
	)
	return res, format_err, format_ok
}

strip :: proc(
	text: string,
	allocator := context.allocator,
) -> (
	result: string,
	err_msg: string,
	ok: bool,
) {
	return format(text, false, allocator)
}

process_colors :: proc(
	text: string,
	enable_color: bool,
	allocator := context.allocator,
) -> string {
	res, err, ok := validate_and_format_bbcode(text, enable_color, false, allocator = allocator)
	if !ok {
		delete(err, allocator)
		return strings.clone(text, allocator)
	}
	return res
}

parse_spans :: proc(
	text: string,
	allocator := context.allocator,
) -> (
	spans: []Span,
	err_msg: string,
	ok: bool,
) {
	if err, val_ok := validate(text, false); !val_ok {
		return nil, strings.clone(err, allocator), false
	}

	spans_dyn := make([dynamic]Span, allocator)
	tag_stack: [dynamic]Tag
	tag_stack.allocator = allocator
	defer delete(tag_stack)

	get_current_style :: proc(stack: [dynamic]Tag) -> Style {
		style := Style {
			opacity    = 1.0,
			bg_opacity = 1.0,
		}
		for tag in stack {
			switch tag.type {
			case .Bold:
				style.bold = true
			case .Italic:
				style.italic = true
			case .Underline:
				style.underline = true
			case .Strikethrough:
				style.strikethrough = true
			case .Color:
				style.color_str = tag.color_str
			case .BgColor:
				style.bg_color_str = tag.color_str
				style.has_bg = true
			case .Opacity:
				style.opacity = tag.opacity
			case .BgOpacity:
				style.bg_opacity = tag.opacity
			case .FontSize:
				style.font_size = tag.font_size
			case .FontPath:
				style.font_path = tag.font_path
			}
		}
		return style
	}

	current_text := strings.builder_make(allocator)
	defer strings.builder_destroy(&current_text)

	flush_current_span :: proc(
		spans: ^[dynamic]Span,
		current_text: ^strings.Builder,
		style: Style,
		allocator: runtime.Allocator,
	) {
		txt := strings.to_string(current_text^)
		if len(txt) > 0 {
			append(spans, Span{text = strings.clone(txt, allocator), style = style})
			strings.builder_reset(current_text)
		}
	}

	i := 0
	n := len(text)
	for i < n {
		if text[i] == '\\' && i + 1 < n && (text[i + 1] == '[' || text[i + 1] == ']') {
			strings.write_byte(&current_text, text[i + 1])
			i += 2
			continue
		}

		if text[i] == '[' {
			is_double := i + 1 < n && text[i + 1] == '['
			close_idx := -1
			if is_double {
				bracket_count := 2
				j := i + 2
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						if bracket_count == 2 && j + 1 < n && text[j + 1] == ']' {
							close_idx = j
							break
						}
						bracket_count -= 1
						j += 1
					} else {
						j += 1
					}
				}
			} else {
				bracket_count := 1
				j := i + 1
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j + 1] == '[' || text[j + 1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						bracket_count -= 1
						if bracket_count == 0 {
							close_idx = j
							break
						}
						j += 1
					} else {
						j += 1
					}
				}
			}

			tag_content := text[i + 2:close_idx] if is_double else text[i + 1:close_idx]

			flush_current_span(&spans_dyn, &current_text, get_current_style(tag_stack), allocator)

			if is_double {
				strings.write_byte(&current_text, '[')
			}

			is_close := strings.has_prefix(tag_content, "/")
			for handler in TAG_HANDLERS {
				if tag_matches(tag_content, handler, is_close) {
					if is_close {
						remove_last_tag(&tag_stack, handler.tag_type)
					} else {
						tag := handler.parse(tag_content)
						append(&tag_stack, tag)
					}
					break
				}
			}

			if is_double {
				strings.write_byte(&current_text, ']')
			}

			i = close_idx + 2 if is_double else close_idx + 1
			continue
		}

		strings.write_byte(&current_text, text[i])
		i += 1
	}

	flush_current_span(&spans_dyn, &current_text, get_current_style(tag_stack), allocator)

	res_slice := make([]Span, len(spans_dyn), allocator)
	copy(res_slice, spans_dyn[:])
	delete(spans_dyn)

	return res_slice, "", true
}
