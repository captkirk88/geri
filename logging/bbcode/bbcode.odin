package bbcode

import "base:runtime"
import "core:fmt"
import "core:strings"

Log_Tag :: enum {
	Time,
	Location,
	Level,
	Message,
	Thread_Id,
}

Log_Tags :: bit_set[Log_Tag]


ANSI_RESET :: "\x1b[0m"
ANSI_BOLD  :: "\x1b[1m"
ANSI_ITALIC :: "\x1b[3m"

ANSI_BLACK   :: "\x1b[30m"
ANSI_RED     :: "\x1b[31m"
ANSI_GREEN   :: "\x1b[32m"
ANSI_YELLOW  :: "\x1b[33m"
ANSI_BLUE    :: "\x1b[34m"
ANSI_MAGENTA :: "\x1b[35m"
ANSI_CYAN    :: "\x1b[36m"
ANSI_WHITE   :: "\x1b[37m"

ANSI_GRAY           :: "\x1b[90m"
ANSI_BRIGHT_RED     :: "\x1b[91m"
ANSI_BRIGHT_GREEN   :: "\x1b[92m"
ANSI_BRIGHT_YELLOW  :: "\x1b[93m"
ANSI_BRIGHT_BLUE    :: "\x1b[94m"
ANSI_BRIGHT_MAGENTA :: "\x1b[95m"
ANSI_BRIGHT_CYAN    :: "\x1b[96m"
ANSI_BRIGHT_WHITE   :: "\x1b[97m"

ANSI_TRUECOLOR_FORMAT :: "\x1b[38;2;%d;%d;%dm"

ANSI_BG_BLACK   :: "\x1b[40m"
ANSI_BG_RED     :: "\x1b[41m"
ANSI_BG_GREEN   :: "\x1b[42m"
ANSI_BG_YELLOW  :: "\x1b[43m"
ANSI_BG_BLUE    :: "\x1b[44m"
ANSI_BG_MAGENTA :: "\x1b[45m"
ANSI_BG_CYAN    :: "\x1b[46m"
ANSI_BG_WHITE   :: "\x1b[47m"
ANSI_BG_GRAY    :: "\x1b[100m"

ANSI_TRUECOLOR_BG_FORMAT :: "\x1b[48;2;%d;%d;%dm"

ANSI_UNDERLINE     :: "\x1b[4m"
ANSI_STRIKETHROUGH :: "\x1b[9m"

Color_Mapping :: struct {
	name: string,
	ansi: string,
}

PREDEFINED_COLORS := [?]Color_Mapping{
	{"black",          ANSI_BLACK},
	{"red",            ANSI_RED},
	{"green",          ANSI_GREEN},
	{"yellow",         ANSI_YELLOW},
	{"blue",           ANSI_BLUE},
	{"magenta",        ANSI_MAGENTA},
	{"purple",         ANSI_MAGENTA},
	{"cyan",           ANSI_CYAN},
	{"white",          ANSI_WHITE},
	{"gray",           ANSI_GRAY},
	{"grey",           ANSI_GRAY},
	{"dark_gray",      ANSI_GRAY},
	{"dark_grey",      ANSI_GRAY},
	{"bright_black",   ANSI_GRAY},
	{"bright_red",     ANSI_BRIGHT_RED},
	{"bright_green",   ANSI_BRIGHT_GREEN},
	{"bright_yellow",  ANSI_BRIGHT_YELLOW},
	{"bright_blue",    ANSI_BRIGHT_BLUE},
	{"bright_magenta", ANSI_BRIGHT_MAGENTA},
	{"bright_purple",  ANSI_BRIGHT_MAGENTA},
	{"bright_cyan",    ANSI_BRIGHT_CYAN},
	{"bright_white",   ANSI_BRIGHT_WHITE},
}

PREDEFINED_BG_COLORS := [?]Color_Mapping{
	{"black",          ANSI_BG_BLACK},
	{"red",            ANSI_BG_RED},
	{"green",          ANSI_BG_GREEN},
	{"yellow",         ANSI_BG_YELLOW},
	{"blue",           ANSI_BG_BLUE},
	{"magenta",        ANSI_BG_MAGENTA},
	{"purple",         ANSI_BG_MAGENTA},
	{"cyan",           ANSI_BG_CYAN},
	{"white",          ANSI_BG_WHITE},
	{"gray",           ANSI_BG_GRAY},
	{"grey",           ANSI_BG_GRAY},
	{"dark_gray",      ANSI_BG_GRAY},
	{"dark_grey",      ANSI_BG_GRAY},
	{"bright_black",   ANSI_BG_GRAY},
	{"bright_red",     "\x1b[101m"},
	{"bright_green",   "\x1b[102m"},
	{"bright_yellow",  "\x1b[103m"},
	{"bright_blue",    "\x1b[104m"},
	{"bright_magenta", "\x1b[105m"},
	{"bright_purple",  "\x1b[105m"},
	{"bright_cyan",    "\x1b[106m"},
	{"bright_white",   "\x1b[107m"},
}

Color_Entry :: struct {
	ansi:   string,
	r, g, b: u8,
	is_hex: bool,
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
		case '0'..='9': return c - '0', true
		case 'a'..='f': return c - 'a' + 10, true
		case 'A'..='F': return c - 'A' + 10, true
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
}

Tag :: struct {
	type:  Tag_Type,
	color: Color_Entry,
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
		switch tag.type {
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
) -> (result: string, err_msg: string, ok: bool) {
	builder := strings.builder_make(allocator)

	tag_stack: [dynamic]Tag
	tag_stack.allocator = allocator
	defer delete(tag_stack)

	i := 0
	n := len(text)
	for i < n {
		if text[i] == '\\' && i + 1 < n && (text[i+1] == '[' || text[i+1] == ']') {
			strings.write_byte(&builder, text[i+1])
			i += 2
			continue
		}

		if text[i] == '[' {
			is_double := i + 1 < n && text[i+1] == '['

			close_idx := -1
			if is_double {
				bracket_count := 2
				j := i + 2
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j+1] == '[' || text[j+1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						if bracket_count == 2 && j + 1 < n && text[j+1] == ']' {
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
					if text[j] == '\\' && j + 1 < n && (text[j+1] == '[' || text[j+1] == ']') {
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
				return "", strings.clone("BBCode Error: Unescaped or unclosed bracket '[' found", allocator), false
			}

			tag_content := text[i+2 : close_idx] if is_double else text[i+1 : close_idx]

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
			return "", strings.clone("BBCode Error: Unescaped closing bracket ']' found", allocator), false
		}

		strings.write_byte(&builder, text[i])
		i += 1
	}

	if len(tag_stack) > 0 {
		strings.builder_destroy(&builder)
		return "", strings.clone("BBCode Error: Unclosed tags remaining at end of string", allocator), false
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
) -> (err_msg: string, ok: bool) {
	if tag_content == "b" {
		append(tag_stack, Tag{type = .Bold})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/b" {
		has_bold := false
		for t in tag_stack {
			if t.type == .Bold { has_bold = true; break }
		}
		if !has_bold {
			return strings.clone("BBCode Error: Closing tag [/b] has no matching [b]", allocator), false
		}
		remove_last_tag(tag_stack, .Bold)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "i" {
		append(tag_stack, Tag{type = .Italic})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/i" {
		has_italic := false
		for t in tag_stack {
			if t.type == .Italic { has_italic = true; break }
		}
		if !has_italic {
			return strings.clone("BBCode Error: Closing tag [/i] has no matching [i]", allocator), false
		}
		remove_last_tag(tag_stack, .Italic)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "u" {
		append(tag_stack, Tag{type = .Underline})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/u" {
		has_underline := false
		for t in tag_stack {
			if t.type == .Underline { has_underline = true; break }
		}
		if !has_underline {
			return strings.clone("BBCode Error: Closing tag [/u] has no matching [u]", allocator), false
		}
		remove_last_tag(tag_stack, .Underline)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "s" {
		append(tag_stack, Tag{type = .Strikethrough})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/s" {
		has_strikethrough := false
		for t in tag_stack {
			if t.type == .Strikethrough { has_strikethrough = true; break }
		}
		if !has_strikethrough {
			return strings.clone("BBCode Error: Closing tag [/s] has no matching [s]", allocator), false
		}
		remove_last_tag(tag_stack, .Strikethrough)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if strings.has_prefix(tag_content, "c=") {
		color_tag := tag_content[2:]
		entry, ok_color := parse_color(color_tag)
		if !ok_color {
			err_str := fmt.aprintf("BBCode Error: Unknown or invalid color tag '%s'", tag_content, allocator = allocator)
			return err_str, false
		}
		append(tag_stack, Tag{type = .Color, color = entry})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/c" {
		has_color := false
		for t in tag_stack {
			if t.type == .Color { has_color = true; break }
		}
		if !has_color {
			return strings.clone("BBCode Error: Closing tag [/c] has no matching [c=...]", allocator), false
		}
		remove_last_tag(tag_stack, .Color)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if strings.has_prefix(tag_content, "bg=") {
		color_tag := tag_content[3:]
		entry, ok_color := parse_bg_color(color_tag)
		if !ok_color {
			err_str := fmt.aprintf("BBCode Error: Unknown or invalid background color tag '%s'", tag_content, allocator = allocator)
			return err_str, false
		}
		append(tag_stack, Tag{type = .BgColor, color = entry})
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "/bg" {
		has_bg := false
		for t in tag_stack {
			if t.type == .BgColor { has_bg = true; break }
		}
		if !has_bg {
			return strings.clone("BBCode Error: Closing tag [/bg] has no matching [bg=...]", allocator), false
		}
		remove_last_tag(tag_stack, .BgColor)
		if enable_color {
			apply_styles(builder, tag_stack^)
		}
	} else if tag_content == "time" {
		if !allow_variables {
			return strings.clone("BBCode Error: Tag 'time' is not allowed in this context", allocator), false
		}
		strings.write_string(builder, time_str)
	} else if tag_content == "location" {
		if !allow_variables {
			return strings.clone("BBCode Error: Tag 'location' is not allowed in this context", allocator), false
		}
		strings.write_string(builder, location_str)
	} else if tag_content == "level" {
		if !allow_variables {
			return strings.clone("BBCode Error: Tag 'level' is not allowed in this context", allocator), false
		}
		strings.write_string(builder, level_str)
	} else if tag_content == "message" {
		if !allow_variables {
			return strings.clone("BBCode Error: Tag 'message' is not allowed in this context", allocator), false
		}
		strings.write_string(builder, message_str)
	} else if tag_content == "thread_id" {
		if !allow_variables {
			return strings.clone("BBCode Error: Tag 'thread_id' is not allowed in this context", allocator), false
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
			err_str := fmt.aprintf("BBCode Error: Unknown or invalid tag '%s'", tag_content, allocator = allocator)
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
		if text[i] == '\\' && i + 1 < n && (text[i+1] == '[' || text[i+1] == ']') {
			i += 2
			continue
		}

		if text[i] == '[' {
			is_double := i + 1 < n && text[i+1] == '['

			close_idx := -1
			if is_double {
				bracket_count := 2
				j := i + 2
				for j < n {
					if text[j] == '\\' && j + 1 < n && (text[j+1] == '[' || text[j+1] == ']') {
						j += 2
						continue
					}
					if text[j] == '[' {
						bracket_count += 1
						j += 1
					} else if text[j] == ']' {
						if bracket_count == 2 && j + 1 < n && text[j+1] == ']' {
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
					if text[j] == '\\' && j + 1 < n && (text[j+1] == '[' || text[j+1] == ']') {
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

			tag_content := text[i+2 : close_idx] if is_double else text[i+1 : close_idx]
			if tag_content == "b" {
				append(&tag_stack, Tag_Type.Bold)
			} else if tag_content == "/b" {
				if !pop_expected_tag(&tag_stack, Tag_Type.Bold) {
					return "BBCode Error: Closing tag [/b] has no matching [b]", false
				}
			} else if tag_content == "i" {
				append(&tag_stack, Tag_Type.Italic)
			} else if tag_content == "/i" {
				if !pop_expected_tag(&tag_stack, Tag_Type.Italic) {
					return "BBCode Error: Closing tag [/i] has no matching [i]", false
				}
			} else if tag_content == "u" {
				append(&tag_stack, Tag_Type.Underline)
			} else if tag_content == "/u" {
				if !pop_expected_tag(&tag_stack, Tag_Type.Underline) {
					return "BBCode Error: Closing tag [/u] has no matching [u]", false
				}
			} else if tag_content == "s" {
				append(&tag_stack, Tag_Type.Strikethrough)
			} else if tag_content == "/s" {
				if !pop_expected_tag(&tag_stack, Tag_Type.Strikethrough) {
					return "BBCode Error: Closing tag [/s] has no matching [s]", false
				}
			} else if strings.has_prefix(tag_content, "c=") {
				color_tag := tag_content[2:]
				_, ok_color := parse_color(color_tag)
				if !ok_color {
					return fmt.tprintf("BBCode Error: Unknown or invalid color tag '%s'", tag_content), false
				}
				append(&tag_stack, Tag_Type.Color)
			} else if tag_content == "/c" {
				if !pop_expected_tag(&tag_stack, Tag_Type.Color) {
					return "BBCode Error: Closing tag [/c] has no matching [c=...]", false
				}
			} else if strings.has_prefix(tag_content, "bg=") {
				color_tag := tag_content[3:]
				_, ok_color := parse_bg_color(color_tag)
				if !ok_color {
					return fmt.tprintf("BBCode Error: Unknown or invalid background color tag '%s'", tag_content), false
				}
				append(&tag_stack, Tag_Type.BgColor)
			} else if tag_content == "/bg" {
				if !pop_expected_tag(&tag_stack, Tag_Type.BgColor) {
					return "BBCode Error: Closing tag [/bg] has no matching [bg=...]", false
				}
			} else if tag_content == "time" || tag_content == "location" || tag_content == "level" || tag_content == "message" || tag_content == "thread_id" {
				if !allow_variables {
					return fmt.tprintf("BBCode Error: Tag '%s' is not allowed in this context", tag_content), false
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
								return "BBCode Error: Conditional tag 'if' must have format 'if <condition>: <value>' or 'if <condition>: <then-value> ? <else-value>'", false
							}

							if !validate_condition(cond) {
								return fmt.tprintf("BBCode Error: Invalid condition syntax '%s'", cond), false
							}

							then_trimmed := strings.trim_space(then_val)
							if len(then_trimmed) >= 2 && then_trimmed[0] == '"' && then_trimmed[len(then_trimmed)-1] == '"' {
								then_trimmed = then_trimmed[1:len(then_trimmed)-1]
							}

							then_err, then_ok := validate(then_trimmed, allow_variables)
							if !then_ok {
								return then_err, false
							}

							if has_else {
								else_trimmed := strings.trim_space(else_val)
								if len(else_trimmed) >= 2 && else_trimmed[0] == '"' && else_trimmed[len(else_trimmed)-1] == '"' {
									else_trimmed = else_trimmed[1:len(else_trimmed)-1]
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
					return fmt.tprintf("BBCode Error: Unknown or invalid tag '%s'", tag_content), false
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

format :: proc(text: string, enable_color := true, allocator := context.allocator) -> (result: string, err_msg: string, ok: bool) {
	err, val_ok := validate(text, false)
	if !val_ok {
		return "", strings.clone(err, allocator), false
	}

	res, format_err, format_ok := validate_and_format_bbcode(text, enable_color, false, allocator = allocator)
	return res, format_err, format_ok
}

strip :: proc(text: string, allocator := context.allocator) -> (result: string, err_msg: string, ok: bool) {
	return format(text, false, allocator)
}

process_colors :: proc(text: string, enable_color: bool, allocator := context.allocator) -> string {
	res, err, ok := validate_and_format_bbcode(text, enable_color, false, allocator = allocator)
	if !ok {
		delete(err, allocator)
		return strings.clone(text, allocator)
	}
	return res
}
