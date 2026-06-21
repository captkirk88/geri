package bbcode

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:unicode"
import "base:runtime"

Tag_Func_Context :: struct {
	enable_color:    bool,
	allow_variables: bool,
	time_str:        string,
	location_str:    string,
	level_str:       string,
	message_str:     string,
	thread_id_str:   string,
	suppressed_tags: Log_Tags,
}

Tag_Func :: #type proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool)

Tag_Func_Entry :: struct {
	name: string,
	fn:   Tag_Func,
}

@(private)
_tag_funcs: [dynamic]Tag_Func_Entry

@(private)
_tag_funcs_lock: sync.Mutex

@(private)
_tag_funcs_initialized := false

@(private,init)
init_tag_funcs_internal :: proc "contextless" () {
	if !_tag_funcs_initialized {
		context = runtime.default_context()
		_tag_funcs = make([dynamic]Tag_Func_Entry, runtime.default_allocator())
		append(&_tag_funcs, Tag_Func_Entry{"len", tag_len})
		append(&_tag_funcs, Tag_Func_Entry{"hour", tag_hour})
		append(&_tag_funcs, Tag_Func_Entry{"if", tag_if})
		append(&_tag_funcs, Tag_Func_Entry{"upper", tag_upper})
		append(&_tag_funcs, Tag_Func_Entry{"lower", tag_lower})
		_tag_funcs_initialized = true
	}
}

get_tag_funcs :: proc() -> []Tag_Func_Entry {
	sync.lock(&_tag_funcs_lock)
	defer sync.unlock(&_tag_funcs_lock)
	init_tag_funcs_internal()
	return _tag_funcs[:]
}

register_tag_func :: proc(name: string, fn: Tag_Func) {
	sync.lock(&_tag_funcs_lock)
	defer sync.unlock(&_tag_funcs_lock)
	init_tag_funcs_internal()

	for &entry in _tag_funcs {
		if entry.name == name {
			entry.fn = fn
			return
		}
	}

	append(&_tag_funcs, Tag_Func_Entry{name, fn})
}

deinit_tag_funcs :: proc() {
	sync.lock(&_tag_funcs_lock)
	defer sync.unlock(&_tag_funcs_lock)
	if _tag_funcs_initialized {
		delete(_tag_funcs)
		_tag_funcs_initialized = false
	}
}

tag_len :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	evaluated, err, val_ok := validate_and_format_bbcode(
		args,
		ctx.enable_color,
		ctx.allow_variables,
		ctx.time_str,
		ctx.location_str,
		ctx.level_str,
		ctx.message_str,
		ctx.thread_id_str,
		allocator,
		ctx.suppressed_tags,
	)
	if !val_ok {
		return "", err, false
	}
	defer delete(evaluated, allocator)

	length := len(evaluated)
	return fmt.aprintf("%d", length, allocator = allocator), "", true
}

tag_hour :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	hour, hour_ok := get_hour_from_time_str(ctx.time_str)
	if !hour_ok {
		return strings.clone("0", allocator), "", true
	}
	return fmt.aprintf("%d", hour, allocator = allocator), "", true
}

tag_if :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	cond_raw, then_raw, else_raw, has_else, args_ok := split_if_args(args)
	if !args_ok {
		return "", strings.clone("BBCode Error: Conditional tag 'if' must have format 'if <condition>: <value>' or 'if <condition>: <then-value> ? <else-value>'", allocator), false
	}

	cond_evaluated, err_cond, ok_cond := validate_and_format_bbcode(
		cond_raw,
		ctx.enable_color,
		ctx.allow_variables,
		ctx.time_str,
		ctx.location_str,
		ctx.level_str,
		ctx.message_str,
		ctx.thread_id_str,
		allocator,
		ctx.suppressed_tags,
	)
	if !ok_cond {
		return "", err_cond, false
	}
	defer delete(cond_evaluated, allocator)

	if !validate_condition(cond_evaluated) {
		return "", fmt.aprintf("BBCode Error: Invalid condition syntax '%s'", cond_evaluated, allocator = allocator), false
	}

	if evaluate_condition_str(cond_evaluated, ctx) {
		val_trimmed := strings.trim_space(then_raw)
		if len(val_trimmed) >= 2 && val_trimmed[0] == '"' && val_trimmed[len(val_trimmed)-1] == '"' {
			val_trimmed = val_trimmed[1:len(val_trimmed)-1]
		}

		formatted, format_err, format_ok := validate_and_format_bbcode(
			val_trimmed,
			ctx.enable_color,
			ctx.allow_variables,
			ctx.time_str,
			ctx.location_str,
			ctx.level_str,
			ctx.message_str,
			ctx.thread_id_str,
			allocator,
			ctx.suppressed_tags,
		)
		if !format_ok {
			return "", format_err, false
		}
		return formatted, "", true
	} else if has_else {
		val_trimmed := strings.trim_space(else_raw)
		if len(val_trimmed) >= 2 && val_trimmed[0] == '"' && val_trimmed[len(val_trimmed)-1] == '"' {
			val_trimmed = val_trimmed[1:len(val_trimmed)-1]
		}

		formatted, format_err, format_ok := validate_and_format_bbcode(
			val_trimmed,
			ctx.enable_color,
			ctx.allow_variables,
			ctx.time_str,
			ctx.location_str,
			ctx.level_str,
			ctx.message_str,
			ctx.thread_id_str,
			allocator,
			ctx.suppressed_tags,
		)
		if !format_ok {
			return "", format_err, false
		}
		return formatted, "", true
	}

	return "", "", true
}

@(private)
split_if_args :: proc(args: string) -> (cond: string, then_val: string, else_val: string, has_else: bool, ok: bool) {
	// Find the first top-level ':'
	colon_idx := -1
	bracket_level := 0
	for i := 0; i < len(args); i += 1 {
		if args[i] == '[' {
			bracket_level += 1
		} else if args[i] == ']' {
			bracket_level -= 1
		} else if bracket_level == 0 && args[i] == ':' {
			colon_idx = i
			break
		}
	}

	if colon_idx == -1 {
		return "", "", "", false, false // missing ':' condition separator
	}

	cond = strings.trim_space(args[:colon_idx])
	rest := args[colon_idx+1:]

	// Find the top-level '?' in the rest
	question_idx := -1
	bracket_level = 0
	for i := 0; i < len(rest); i += 1 {
		if rest[i] == '[' {
			bracket_level += 1
		} else if rest[i] == ']' {
			bracket_level -= 1
		} else if bracket_level == 0 && rest[i] == '?' {
			question_idx = i
			break
		}
	}

	if question_idx != -1 {
		then_val = strings.trim_space(rest[:question_idx])
		else_val = strings.trim_space(rest[question_idx+1:])
		return cond, then_val, else_val, true, true
	} else {
		then_val = strings.trim_space(rest)
		return cond, then_val, "", false, true
	}
}


@(private)
parse_tag_name_and_args :: proc(tag_content: string) -> (name: string, args: string) {
	s := strings.trim_space(tag_content)
	
	first_space := -1
	for i := 0; i < len(s); i += 1 {
		if s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r' {
			first_space = i
			break
		}
	}

	if first_space == -1 {
		return s, ""
	}

	return s[:first_space], strings.trim_space(s[first_space+1:])
}

@(private)
get_hour_from_time_str :: proc(time_str: string) -> (hour: int, ok: bool) {
	s := time_str
	if len(s) == 0 { return 0, false }
	if s[0] == '[' {
		s = s[1:]
	}
	if len(s) >= 19 && s[4] == '-' && s[7] == '-' {
		s = s[11:]
	}
	if len(s) >= 2 && s[2] == ':' {
		h_str := s[0:2]
		val := 0
		for c in h_str {
			if c < '0' || c > '9' { return 0, false }
			val = val * 10 + int(c - '0')
		}
		return val, true
	}
	return 0, false
}

@(private)
parse_int :: proc(s: string) -> (val: int, ok: bool) {
	if len(s) == 0 { return 0, false }
	res := 0
	sign := 1
	start := 0
	if s[0] == '-' {
		sign = -1
		start = 1
	} else if s[0] == '+' {
		start = 1
	}
	if start == len(s) { return 0, false }
	for i := start; i < len(s); i += 1 {
		if s[i] < '0' || s[i] > '9' { return 0, false }
		res = res * 10 + int(s[i] - '0')
	}
	return res * sign, true
}

strip_ansi :: proc(s: string, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	in_escape := false
	for r in s {
		if r == '\x1b' {
			in_escape = true
		} else if in_escape {
			if r == 'm' {
				in_escape = false
			}
		} else {
			strings.write_rune(&builder, r)
		}
	}
	return strings.to_string(builder)
}

@(private)
resolve_value :: proc(val: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> string {
	s := strings.trim_space(val)
	if len(s) > 0 && s[len(s)-1] == 'h' {
		s = s[:len(s)-1]
	}
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return strings.clone(s[1:len(s)-1], allocator)
	}
	if len(s) >= 2 && s[0] == '\'' && s[len(s)-1] == '\'' {
		return strings.clone(s[1:len(s)-1], allocator)
	}

	if strings.has_prefix(s, "len(") && strings.has_suffix(s, ")") {
		var_name := strings.trim_space(s[4:len(s)-1])
		val_str := ""
		switch var_name {
		case "time":      val_str = strip_ansi(ctx.time_str, context.temp_allocator)
		case "location":  val_str = strip_ansi(ctx.location_str, context.temp_allocator)
		case "level":
			temp := strip_ansi(ctx.level_str, context.temp_allocator)
			temp = strings.trim_space(temp)
			if len(temp) > 0 && temp[len(temp)-1] == ':' {
				temp = temp[:len(temp)-1]
				temp = strings.trim_space(temp)
			}
			val_str = temp
		case "message":   val_str = strip_ansi(ctx.message_str, context.temp_allocator)
		case "thread_id": val_str = strip_ansi(ctx.thread_id_str, context.temp_allocator)
		}
		return fmt.aprintf("%d", len(val_str), allocator = allocator)
	}

	switch s {
	case "time":
		hour, ok := get_hour_from_time_str(ctx.time_str)
		if ok {
			return fmt.aprintf("%d", hour, allocator = allocator)
		}
		return strip_ansi(ctx.time_str, allocator)
	case "location":
		return strip_ansi(ctx.location_str, allocator)
	case "level":
		temp := strip_ansi(ctx.level_str, allocator)
		temp = strings.trim_space(temp)
		if len(temp) > 0 && temp[len(temp)-1] == ':' {
			temp = temp[:len(temp)-1]
			temp = strings.trim_space(temp)
		}
		return temp
	case "message":
		return strip_ansi(ctx.message_str, allocator)
	case "thread_id":
		return strip_ansi(ctx.thread_id_str, allocator)
	}

	return strings.clone(s, allocator)
}

@(private)
evaluate_condition_str :: proc(cond: string, ctx: Tag_Func_Context) -> bool {
	s := strings.trim_space(cond)

	op_idx := -1
	op_len := 0
	
	bracket_level := 0
	for i := 0; i < len(s); i += 1 {
		if s[i] == '[' {
			bracket_level += 1
		} else if s[i] == ']' {
			bracket_level -= 1
		} else if bracket_level == 0 {
			if i + 1 < len(s) {
				sub := s[i:i+2]
				if sub == "<=" || sub == ">=" || sub == "==" || sub == "!=" {
					op_idx = i
					op_len = 2
					break
				}
			}
			if s[i] == '<' || s[i] == '>' {
				op_idx = i
				op_len = 1
				break
			}
		}
	}

	if op_idx == -1 {
		return false
	}

	lhs_raw := strings.trim_space(s[:op_idx])
	rhs_raw := strings.trim_space(s[op_idx+op_len:])
	op := s[op_idx : op_idx+op_len]

	allocator := context.temp_allocator
	lhs_val := resolve_value(lhs_raw, ctx, allocator)
	rhs_val := resolve_value(rhs_raw, ctx, allocator)

	// Try parsing both as integers
	lhs_num, lhs_is_num := parse_int(lhs_val)
	rhs_num, rhs_is_num := parse_int(rhs_val)

	if lhs_is_num && rhs_is_num {
		switch op {
		case "<":  return lhs_num < rhs_num
		case ">":  return lhs_num > rhs_num
		case "<=": return lhs_num <= rhs_num
		case ">=": return lhs_num >= rhs_num
		case "==": return lhs_num == rhs_num
		case "!=": return lhs_num != rhs_num
		}
	} else {
		// String comparisons are case-insensitive
		lhs_lower := strings.to_lower(lhs_val, allocator)
		rhs_lower := strings.to_lower(rhs_val, allocator)
		switch op {
		case "==": return lhs_lower == rhs_lower
		case "!=": return lhs_lower != rhs_lower
		case "<":  return lhs_lower < rhs_lower
		case ">":  return lhs_lower > rhs_lower
		case "<=": return lhs_lower <= rhs_lower
		case ">=": return lhs_lower >= rhs_lower
		}
	}

	return false
}

@(private)
validate_condition :: proc(cond: string) -> bool {
	s := cond
	op_idx := -1
	op_len := 0
	
	bracket_level := 0
	for i := 0; i < len(s); i += 1 {
		if s[i] == '[' {
			bracket_level += 1
		} else if s[i] == ']' {
			bracket_level -= 1
		} else if bracket_level == 0 {
			if i + 1 < len(s) {
				sub := s[i:i+2]
				if sub == "<=" || sub == ">=" || sub == "==" || sub == "!=" {
					op_idx = i
					op_len = 2
					break
				}
			}
			if s[i] == '<' || s[i] == '>' {
				op_idx = i
				op_len = 1
				break
			}
		}
	}

	if op_idx == -1 {
		return false
	}

	lhs := strings.trim_space(s[:op_idx])
	rhs := strings.trim_space(s[op_idx+op_len:])

	lhs_ok := false
	if lhs == "time" {
		lhs_ok = true
	} else if strings.has_prefix(lhs, "len(") && strings.has_suffix(lhs, ")") {
		var_name := strings.trim_space(lhs[4:len(lhs)-1])
		if var_name == "time" || var_name == "location" || var_name == "level" || var_name == "message" || var_name == "thread_id" {
			lhs_ok = true
		}
	} else {
		_, val_ok := validate(lhs, true)
		lhs_ok = val_ok
	}

	if !lhs_ok { return false }

	rhs_clean := rhs
	if len(rhs_clean) > 0 && rhs_clean[len(rhs_clean)-1] == 'h' {
		rhs_clean = rhs_clean[:len(rhs_clean)-1]
	}
	if len(rhs_clean) >= 2 && rhs_clean[0] == '"' && rhs_clean[len(rhs_clean)-1] == '"' {
		rhs_clean = rhs_clean[1:len(rhs_clean)-1]
	}

	_, rhs_ok := validate(rhs_clean, true)
	return rhs_ok
}

tag_upper :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	evaluated, err, val_ok := validate_and_format_bbcode(
		args,
		ctx.enable_color,
		ctx.allow_variables,
		ctx.time_str,
		ctx.location_str,
		ctx.level_str,
		ctx.message_str,
		ctx.thread_id_str,
		allocator,
		ctx.suppressed_tags,
	)
	if !val_ok {
		return "", err, false
	}
	defer delete(evaluated, allocator)

	return ansi_casing(evaluated, true, allocator), "", true
}

tag_lower :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	evaluated, err, val_ok := validate_and_format_bbcode(
		args,
		ctx.enable_color,
		ctx.allow_variables,
		ctx.time_str,
		ctx.location_str,
		ctx.level_str,
		ctx.message_str,
		ctx.thread_id_str,
		allocator,
		ctx.suppressed_tags,
	)
	if !val_ok {
		return "", err, false
	}
	defer delete(evaluated, allocator)

	return ansi_casing(evaluated, false, allocator), "", true
}

@(private)
ansi_casing :: proc(s: string, to_upper: bool, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	in_escape := false
	for r in s {
		if r == '\x1b' {
			in_escape = true
			strings.write_rune(&builder, r)
		} else if in_escape {
			strings.write_rune(&builder, r)
			if r == 'm' {
				in_escape = false
			}
		} else {
			cased := unicode.to_upper(r) if to_upper else unicode.to_lower(r)
			strings.write_rune(&builder, cased)
		}
	}
	return strings.to_string(builder)
}
