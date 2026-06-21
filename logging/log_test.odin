package logging

import "base:runtime"
import "bbcode"
import "core:fmt"
import log "core:log"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

@(private)
test_mutex: sync.Mutex

@(test)
test_hex_parsing :: proc(t: ^testing.T) {
	r, g, b, ok := bbcode.parse_hex_color("#ff0000")
	testing.expect(t, ok, "Failed to parse #ff0000")
	testing.expect_value(t, r, 255)
	testing.expect_value(t, g, 0)
	testing.expect_value(t, b, 0)

	r, g, b, ok = bbcode.parse_hex_color("00ff00")
	testing.expect(t, ok, "Failed to parse 00ff00")
	testing.expect_value(t, r, 0)
	testing.expect_value(t, g, 255)
	testing.expect_value(t, b, 0)

	r, g, b, ok = bbcode.parse_hex_color("#00f")
	testing.expect(t, ok, "Failed to parse #00f")
	testing.expect_value(t, r, 0)
	testing.expect_value(t, g, 0)
	testing.expect_value(t, b, 255)
}

@(test)
test_color_processing :: proc(t: ^testing.T) {
	// Enable color
	res1 := bbcode.process_colors("hello [c=ff0000]red[/c] world", true, context.allocator)
	defer delete(res1)
	testing.expect_value(t, res1, "hello \x1b[0m\x1b[38;2;255;0;0mred\x1b[0m world")

	// Disable color (strip tags)
	res2 := bbcode.process_colors("hello [c=ff0000]red[/c] world", false, context.allocator)
	defer delete(res2)
	testing.expect_value(t, res2, "hello red world")

	// Nested colors
	res3 := bbcode.process_colors(
		"[c=ff0000]red [c=00ff00]green[/c] red[/c]",
		true,
		context.allocator,
	)
	defer delete(res3)
	testing.expect_value(
		t,
		res3,
		"\x1b[0m\x1b[38;2;255;0;0mred \x1b[0m\x1b[38;2;0;255;0mgreen\x1b[0m\x1b[38;2;255;0;0m red\x1b[0m",
	)

	// Predefined colors
	res4 := bbcode.process_colors(
		"hello [c=red]red[/c] and [c=blue]blue[/c]",
		true,
		context.allocator,
	)
	defer delete(res4)
	testing.expect_value(t, res4, "hello \x1b[0m\x1b[31mred\x1b[0m and \x1b[0m\x1b[34mblue\x1b[0m")

	// Bold and Italic styles (Enabled)
	res5 := bbcode.process_colors("hello [b]bold[/b] and [i]italic[/i]", true, context.allocator)
	defer delete(res5)
	testing.expect_value(
		t,
		res5,
		"hello \x1b[0m\x1b[1mbold\x1b[0m and \x1b[0m\x1b[3mitalic\x1b[0m",
	)

	// Nested Bold and Italic
	res6 := bbcode.process_colors("[b]bold [i]italic[/i] bold[/b]", true, context.allocator)
	defer delete(res6)
	testing.expect_value(
		t,
		res6,
		"\x1b[0m\x1b[1mbold \x1b[0m\x1b[1m\x1b[3mitalic\x1b[0m\x1b[1m bold\x1b[0m",
	)

	// Disable color (strip bold/italic tags)
	res7 := bbcode.process_colors("[b]bold [i]italic[/i] bold[/b]", false, context.allocator)
	defer delete(res7)
	testing.expect_value(t, res7, "bold italic bold")

	// Handles invalid/unknown BBCode tags and unescaped brackets gracefully by returning original string
	res8 := bbcode.process_colors(
		"TEXTURE: [ID 1] Texture loaded successfully",
		true,
		context.allocator,
	)
	defer delete(res8)
	testing.expect_value(t, res8, "TEXTURE: [ID 1] Texture loaded successfully")

	res9 := bbcode.process_colors("unescaped [ bracket", true, context.allocator)
	defer delete(res9)
	testing.expect_value(t, res9, "unescaped [ bracket")

	// Underline, strikethrough, and background colors
	res10 := bbcode.process_colors(
		"[u]underlined[/u] and [s]striked[/s] and [bg=red]red bg[/bg]",
		true,
		context.allocator,
	)
	defer delete(res10)
	testing.expect_value(
		t,
		res10,
		"\x1b[0m\x1b[4munderlined\x1b[0m and \x1b[0m\x1b[9mstriked\x1b[0m and \x1b[0m\x1b[41mred bg\x1b[0m",
	)

	res11 := bbcode.process_colors("[bg=ff0000]hex bg[/bg]", true, context.allocator)
	defer delete(res11)
	testing.expect_value(t, res11, "\x1b[0m\x1b[48;2;255;0;0mhex bg\x1b[0m")
}

@(test)
test_rolling_file_on_launch :: proc(t: ^testing.T) {
	sync.lock(&test_mutex)
	defer sync.unlock(&test_mutex)

	clear_outputs()
	defer clear_outputs()

	dir := "test_logs_launch"
	defer os.remove_all(dir)

	// Add rolling file output on launch
	add_output(
		create_rolling_file_output(.Debug, dir, "test_launch", .On_Launch, DEFAULT_FILE_FORMAT),
	)

	// Log some messages
	debug("launch msg 1")
	info("[c=ff0000]launch msg 2[/c]")

	// Verify file exists
	testing.expect(t, len(log_outputs) == 1, "Log output should be registered")
	rf := cast(^Log_Output_Rolling_File)log_outputs[0].ptr
	testing.expect(t, rf.current_file_handle != nil, "File handle should be open")
	testing.expect(t, os.exists(rf.current_file_path), "Log file should exist on disk")

	// Close handle so we can read the file
	os.close(rf.current_file_handle)
	rf.current_file_handle = nil

	data, err := os.read_entire_file(rf.current_file_path, context.allocator)
	testing.expect(t, err == nil, "Failed to read log file")
	defer delete(data)

	content := string(data)
	testing.expect(t, strings.contains(content, "launch msg 1"), "File should contain msg 1")
	testing.expect(t, strings.contains(content, "launch msg 2"), "File should contain msg 2")
	testing.expect(t, !strings.contains(content, "[c=ff0000]"), "File should strip color tags")
	testing.expect(
		t,
		!strings.contains(content, "\x1b["),
		"File should not contain ANSI escape codes",
	)
}

@(test)
test_rolling_file_on_day :: proc(t: ^testing.T) {
	sync.lock(&test_mutex)
	defer sync.unlock(&test_mutex)

	clear_outputs()
	defer clear_outputs()

	dir := "test_logs_day"
	defer os.remove_all(dir)

	add_output(
		create_rolling_file_output(.Debug, dir, "test_day", .On_Calendar_Day, DEFAULT_FILE_FORMAT),
	)

	info("day msg 1")

	// Verify file path matches expected calendar day format
	rf := cast(^Log_Output_Rolling_File)log_outputs[0].ptr
	testing.expect(t, rf.current_file_handle != nil, "File handle should be open")

	// We can manually change the date to force a roll
	rf.last_rolled_day = 1 // set it to something different than today to simulate day roll

	// Log another message to trigger rolling
	info("day msg 2")

	testing.expect(t, rf.current_file_handle != nil, "File handle should be open after roll")
}

@(private)
Test_Log_Buffer :: struct {
	lines: [dynamic]string,
}

@(private)
test_proxy_write :: proc(
	output: ^Log_Output,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
) {
	buf := cast(^Test_Log_Buffer)output.ptr
	append(&buf.lines, strings.clone(text, runtime.default_allocator()))
}

@(test)
test_proxy_output :: proc(t: ^testing.T) {
	sync.lock(&test_mutex)
	defer sync.unlock(&test_mutex)

	clear_outputs()
	defer clear_outputs()

	buf: Test_Log_Buffer
	buf.lines = make([dynamic]string, context.allocator)
	defer {
		for line in buf.lines {
			delete(line, runtime.default_allocator())
		}
		delete(buf.lines)
	}

	custom_out := Log_Output {
		lowest_level = .Debug,
		write_proc = test_proxy_write,
		ptr = &buf,
	}

	proxy_out := create_proxy_output(.Info, custom_out)
	add_output(proxy_out)

	debug("should not be written via proxy") // Debug level is lower than proxy Info level
	info("should be written via proxy")

	testing.expect(t, len(log_outputs) == 1, "Log output should be registered")
	testing.expect_value(t, len(buf.lines), 1)
	if len(buf.lines) == 1 {
		testing.expect_value(t, buf.lines[0], "should be written via proxy")
	}
}

@(test)
test_bbcode_validation :: proc(t: ^testing.T) {
	// 1. Valid BBCode template parsing
	res, err, ok := bbcode.validate_and_format_bbcode(
		"[b][time][/b] [level] [message]",
		true,
		true,
		"2026-06-20",
		"",
		"info:",
		"hello",
		"",
		context.allocator,
	)
	defer delete(res)
	testing.expect(t, ok, "Expected valid BBCode template to succeed")
	testing.expect_value(t, res, "\x1b[0m\x1b[1m2026-06-20\x1b[0m info: hello")

	// 2. Unclosed tag error
	_, err2, ok2 := bbcode.validate_and_format_bbcode(
		"[b]unclosed",
		true,
		false,
		allocator = context.allocator,
	)
	defer if !ok2 {delete(err2)}
	testing.expect(t, !ok2, "Expected unclosed tag to fail")
	testing.expect_value(t, err2, "BBCode Error: Unclosed tags remaining at end of string")

	// 3. Unknown tag error
	_, err3, ok3 := bbcode.validate_and_format_bbcode(
		"[unknown]text",
		true,
		false,
		allocator = context.allocator,
	)
	defer if !ok3 {delete(err3)}
	testing.expect(t, !ok3, "Expected unknown tag to fail")

	// 4. Unescaped [ error
	_, err4, ok4 := bbcode.validate_and_format_bbcode(
		"unescaped [ bracket",
		true,
		false,
		allocator = context.allocator,
	)
	defer if !ok4 {delete(err4)}
	testing.expect(t, !ok4, "Expected unescaped [ to fail")

	// 5. Unescaped ] error
	_, err5, ok5 := bbcode.validate_and_format_bbcode(
		"unescaped ] bracket",
		true,
		false,
		allocator = context.allocator,
	)
	defer if !ok5 {delete(err5)}
	testing.expect(t, !ok5, "Expected unescaped ] to fail")

	// 6. Escaped bracket sequence
	res6, err6, ok6 := bbcode.validate_and_format_bbcode(
		"escaped \\[b\\] and \\[i\\] and [b]real bold[/b]",
		true,
		false,
		allocator = context.allocator,
	)
	defer delete(res6)
	testing.expect(t, ok6, "Expected escaped brackets to succeed")
	testing.expect_value(t, res6, "escaped [b] and [i] and \x1b[0m\x1b[1mreal bold\x1b[0m")

	// 7. Double bracket tag evaluation
	res7, err7, ok7 := bbcode.validate_and_format_bbcode(
		"double [[level]] and [b]real bold[/b]",
		true,
		true,
		"",
		"",
		"info",
		"",
		"",
		allocator = context.allocator,
	)
	defer delete(res7)
	testing.expect(t, ok7, "Expected double brackets to succeed")
	testing.expect_value(t, res7, "double [info] and \x1b[0m\x1b[1mreal bold\x1b[0m")
}

@(test)
test_time_formatting :: proc(t: ^testing.T) {
	// None
	fmt_none := Log_Format {
		time_format = .None,
	}
	t_none := get_time_string(fmt_none, context.allocator)
	defer delete(t_none)
	testing.expect_value(t, t_none, "")

	// Long UTC (e.g. YYYY-MM-DD HH:MM:SS)
	fmt_long_utc := Log_Format {
		time_format = .Long_UTC,
	}
	t_long_utc := get_time_string(fmt_long_utc, context.allocator)
	defer delete(t_long_utc)
	testing.expect(
		t,
		len(t_long_utc) == len("[YYYY-MM-DD HH:MM:SS] "),
		"Long UTC time string length should be standard",
	)

	// Short UTC (e.g. HH:MM:SS)
	fmt_short_utc := Log_Format {
		time_format = .Short_UTC,
	}
	t_short_utc := get_time_string(fmt_short_utc, context.allocator)
	defer delete(t_short_utc)
	testing.expect(
		t,
		len(t_short_utc) == len("[HH:MM:SS] "),
		"Short UTC time string length should be standard",
	)

	// Custom (UTC+2 = +120 minutes)
	fmt_custom := Log_Format {
		time_format     = .Custom,
		timezone_offset = 120,
	}
	t_custom := get_time_string(fmt_custom, context.allocator)
	defer delete(t_custom)
	testing.expect(
		t,
		len(t_custom) == len("[YYYY-MM-DD HH:MM:SS] "),
		"Custom time string length should be standard",
	)
}

@(test)
test_public_bbcode_api :: proc(t: ^testing.T) {
	// validate
	err, ok := bbcode.validate("[b]hello[/b]")
	testing.expect(t, ok, "validate expected true")
	testing.expect_value(t, err, "")

	err2, ok2 := bbcode.validate("[b]hello")
	testing.expect(t, !ok2, "validate expected false")
	testing.expect_value(t, err2, "BBCode Error: Unclosed tags remaining at end of string")

	// format
	res, ferr, fok := bbcode.format("hello [b]world[/b]", true, context.allocator)
	defer delete(res)
	testing.expect(t, fok, "format expected true")
	testing.expect_value(t, res, "hello \x1b[0m\x1b[1mworld\x1b[0m")

	// strip
	plain, serr, sok := bbcode.strip("hello [b]world[/b]", context.allocator)
	defer delete(plain)
	testing.expect(t, sok, "strip expected true")
	testing.expect_value(t, plain, "hello world")

	// Test conditional if statements
	// Condition evaluates to true
	res_if1, err_if1, ok_if1 := bbcode.validate_and_format_bbcode(
		"[if time<20h: [b][time][/b]]",
		true,
		true,
		"[18:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_if1)
	defer if !ok_if1 {delete(err_if1)}
	testing.expect(t, ok_if1, "Expected true condition to succeed")
	testing.expect_value(t, res_if1, "\x1b[0m\x1b[1m[18:00:00]\x1b[0m")

	// Condition evaluates to false (hour is 21, not < 20)
	res_if2, err_if2, ok_if2 := bbcode.validate_and_format_bbcode(
		"[if time<20h: [b][time][/b]]",
		true,
		true,
		"[21:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_if2)
	defer if !ok_if2 {delete(err_if2)}
	testing.expect(t, ok_if2, "Expected false condition to succeed")
	testing.expect_value(t, res_if2, "")

	// Condition len(message) > 200 (True)
	msg_long := strings.repeat("A", 250, context.allocator)
	defer delete(msg_long)
	res_if3, err_if3, ok_if3 := bbcode.validate_and_format_bbcode(
		"[if len(message) > 200: \"Nope\"]",
		true,
		true,
		"",
		"",
		"",
		msg_long,
		"",
		context.allocator,
	)
	defer delete(res_if3)
	defer if !ok_if3 {delete(err_if3)}
	testing.expect(t, ok_if3, "Expected len(message) > 200 condition to succeed")
	testing.expect_value(t, res_if3, "Nope")

	// Condition len(message) > 200 (False)
	res_if4, err_if4, ok_if4 := bbcode.validate_and_format_bbcode(
		"[if len(message) > 200: \"Nope\"]",
		true,
		true,
		"",
		"",
		"",
		"short message",
		"",
		context.allocator,
	)
	defer delete(res_if4)
	defer if !ok_if4 {delete(err_if4)}
	testing.expect(t, ok_if4, "Expected false condition to succeed")
	testing.expect_value(t, res_if4, "")

	// Nested Condition [len [message]] > 20 (True)
	res_nested1, err_nested1, ok_nested1 := bbcode.validate_and_format_bbcode(
		"[if [len [message]] > 20: \"Long!\"]",
		true,
		true,
		"",
		"",
		"",
		"this is a very long message indeed",
		"",
		context.allocator,
	)
	defer delete(res_nested1)
	defer if !ok_nested1 {delete(err_nested1)}
	testing.expect(t, ok_nested1, "Expected nested condition to succeed")
	testing.expect_value(t, res_nested1, "Long!")

	// Nested Condition [len [message]] > 20 (False)
	res_nested2, err_nested2, ok_nested2 := bbcode.validate_and_format_bbcode(
		"[if [len [message]] > 20: \"Long!\"]",
		true,
		true,
		"",
		"",
		"",
		"short msg",
		"",
		context.allocator,
	)
	defer delete(res_nested2)
	defer if !ok_nested2 {delete(err_nested2)}
	testing.expect(t, ok_nested2, "Expected nested condition to succeed")
	testing.expect_value(t, res_nested2, "")

	// Nested tag functions in conditional tag: [if [hour] < 20: [b][time][/b]] (True)
	res_nested3, err_nested3, ok_nested3 := bbcode.validate_and_format_bbcode(
		"[if [hour] < 20: [b][time][/b]]",
		true,
		true,
		"[18:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_nested3)
	defer if !ok_nested3 {delete(err_nested3)}
	testing.expect(t, ok_nested3, "Expected nested condition to succeed")
	testing.expect_value(t, res_nested3, "\x1b[0m\x1b[1m[18:00:00]\x1b[0m")

	// Nested tag functions in conditional tag: [if [hour] < 20: [b][time][/b]] (False)
	res_nested4, err_nested4, ok_nested4 := bbcode.validate_and_format_bbcode(
		"[if [hour] < 20: [b][time][/b]]",
		true,
		true,
		"[21:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_nested4)
	defer if !ok_nested4 {delete(err_nested4)}
	testing.expect(t, ok_nested4, "Expected nested condition to succeed")
	testing.expect_value(t, res_nested4, "")

	// Ternary (with else statement) condition: [if [hour] < 20: "Day" ? "Night"] (True)
	res_ternary1, err_ternary1, ok_ternary1 := bbcode.validate_and_format_bbcode(
		"[if [hour] < 20: \"Day\" ? \"Night\"]",
		true,
		true,
		"[18:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_ternary1)
	defer if !ok_ternary1 {delete(err_ternary1)}
	testing.expect(t, ok_ternary1, "Expected ternary condition to succeed")
	testing.expect_value(t, res_ternary1, "Day")

	// Ternary (with else statement) condition: [if [hour] < 20: "Day" ? "Night"] (False)
	res_ternary2, err_ternary2, ok_ternary2 := bbcode.validate_and_format_bbcode(
		"[if [hour] < 20: \"Day\" ? \"Night\"]",
		true,
		true,
		"[21:00:00]",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_ternary2)
	defer if !ok_ternary2 {delete(err_ternary2)}
	testing.expect(t, ok_ternary2, "Expected ternary condition to succeed")
	testing.expect_value(t, res_ternary2, "Night")

	// Ternary with nested tags in both branches (True)
	res_ternary3, err_ternary3, ok_ternary3 := bbcode.validate_and_format_bbcode(
		"[if [len [message]] > 20: [b]Long Message[/b] ? [i][message][/i]]",
		true,
		true,
		"",
		"",
		"",
		"very long message here!",
		"",
		context.allocator,
	)
	defer delete(res_ternary3)
	defer if !ok_ternary3 {delete(err_ternary3)}
	testing.expect(t, ok_ternary3, "Expected nested ternary condition to succeed")
	testing.expect_value(t, res_ternary3, "\x1b[0m\x1b[1mLong Message\x1b[0m")

	// Ternary with nested tags in both branches (False)
	res_ternary4, err_ternary4, ok_ternary4 := bbcode.validate_and_format_bbcode(
		"[if [len [message]] > 20: [b]Long Message[/b] ? [i][message][/i]]",
		true,
		true,
		"",
		"",
		"",
		"short",
		"",
		context.allocator,
	)
	defer delete(res_ternary4)
	defer if !ok_ternary4 {delete(err_ternary4)}
	testing.expect(t, ok_ternary4, "Expected nested ternary condition to succeed")
	testing.expect_value(t, res_ternary4, "\x1b[0m\x1b[3mshort\x1b[0m")
}

@(test)
test_dynamic_tag_registration :: proc(t: ^testing.T) {
	defer bbcode.deinit_tag_funcs()

	tag_prefix :: proc(
		args: string,
		ctx: bbcode.Tag_Func_Context,
		allocator: runtime.Allocator,
	) -> (
		result: string,
		err_msg: string,
		ok: bool,
	) {
		evaluated, err, val_ok := bbcode.validate_and_format_bbcode(
			args,
			ctx.enable_color,
			ctx.allow_variables,
			ctx.time_str,
			ctx.location_str,
			ctx.level_str,
			ctx.message_str,
			ctx.thread_id_str,
			allocator,
		)
		if !val_ok {
			return "", err, false
		}
		defer delete(evaluated, allocator)

		return fmt.aprintf("PREFIX: %s", evaluated, allocator = allocator), "", true
	}

	bbcode.register_tag_func("prefix", tag_prefix)

	res, err, ok := bbcode.validate_and_format_bbcode(
		"[prefix hello [b]world[/b]]",
		true,
		true,
		"",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res)
	testing.expect(t, ok, "Expected dynamic tag formatting to succeed")
	testing.expect_value(t, res, "PREFIX: hello \x1b[0m\x1b[1mworld\x1b[0m")
}

@(test)
test_builtin_upper_lower :: proc(t: ^testing.T) {
	// Built-in [upper] test with nested bold tag and enable_color = true
	res_upper, err_upper, ok_upper := bbcode.validate_and_format_bbcode(
		"[upper hello [b]world[/b]]",
		true,
		true,
		"",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_upper)
	testing.expect(t, ok_upper, "Expected upper to succeed")
	testing.expect_value(t, res_upper, "HELLO \x1b[0m\x1b[1mWORLD\x1b[0m")

	// Built-in [lower] test with nested bold tag and enable_color = true
	res_lower, err_lower, ok_lower := bbcode.validate_and_format_bbcode(
		"[lower HELLO [b]WORLD[/b]]",
		true,
		true,
		"",
		"",
		"",
		"",
		"",
		context.allocator,
	)
	defer delete(res_lower)
	testing.expect(t, ok_lower, "Expected lower to succeed")
	testing.expect_value(t, res_lower, "hello \x1b[0m\x1b[1mworld\x1b[0m")

	// Test regression for template variables with custom template (no colon, no space)
	level_str := get_level_string(
		.Info,
		Log_Format{template = "custom", enable_color = true},
		context.allocator,
	)
	defer delete(level_str, context.allocator)

	res_temp, err_temp, ok_temp := bbcode.validate_and_format_bbcode(
		"[u][b][level][/b][/u][message]",
		true,
		true,
		"",
		"",
		level_str,
		"Hello, World!",
		"",
		context.allocator,
	)
	defer delete(res_temp)
	testing.expect(t, ok_temp, "Expected template formatting to succeed")
	testing.expect_value(
		t,
		res_temp,
		"\x1b[0m\x1b[4m\x1b[0m\x1b[1m\x1b[4m\x1b[1;37minfo\x1b[0m\x1b[0m\x1b[4m\x1b[0mHello, World!",
	)

	// Test default layout template variable (has colon, space after reset)
	level_str_default := get_level_string(
		.Info,
		Log_Format{template = "", enable_color = true},
		context.allocator,
	)
	defer delete(level_str_default, context.allocator)

	res_default, err_default, ok_default := bbcode.validate_and_format_bbcode(
		"[u][b][level][/b][/u][message]",
		true,
		true,
		"",
		"",
		level_str_default,
		"Hello, World!",
		"",
		context.allocator,
	)
	defer delete(res_default)
	testing.expect(t, ok_default, "Expected default layout formatting to succeed")
	testing.expect_value(
		t,
		res_default,
		"\x1b[0m\x1b[4m\x1b[0m\x1b[1m\x1b[4m\x1b[1;37minfo:\x1b[0m \x1b[0m\x1b[4m\x1b[0mHello, World!",
	)
}

@(test)
test_tag_suppression :: proc(t: ^testing.T) {
	format_suppressed := Log_Format {
		template     = "[[time]][[location]][level]: [message]",
		enable_color = false,
		time_format  = .Long,
	}

	loc := runtime.Source_Code_Location {
		file_path = "test_file.odin",
		line      = 42,
		procedure = "test_proc",
	}

	line := format_log_line(
		format_suppressed,
		.Info,
		"Hello, Suppressed!",
		{},
		loc,
		{.Location, .Time},
		context.allocator,
	)
	defer delete(line)

	testing.expect_value(t, line, "info: Hello, Suppressed!")
}

@(test)
test_thread_tag_suppression :: proc(t: ^testing.T) {
	format := Log_Format {
		template     = "[[time]][[location]][level]: [message]",
		enable_color = false,
		time_format  = .Long,
	}

	loc := runtime.Source_Code_Location {
		file_path = "test_file.odin",
		line      = 42,
		procedure = "test_proc",
	}

	set_thread_suppressed_tags({.Location, .Time})
	defer set_thread_suppressed_tags({})

	line := format_log_line(
		format,
		.Info,
		"Hello, Thread Suppressed!",
		{},
		loc,
		{},
		context.allocator,
	)
	defer delete(line)

	testing.expect_value(t, line, "info: Hello, Thread Suppressed!")
}

@(test)
test_output_struct_tag_suppression :: proc(t: ^testing.T) {
	out := create_console_output(
		.Info,
		Log_Format {
			template = "[[time]][[location]][level]: [message]",
			enable_color = false,
			time_format = .Long,
		},
		context.allocator,
	)
	out.suppressed_tags = {.Location, .Time}
	defer close_output(&out)

	c_data := cast(^Log_Output_Console)out.ptr
	loc := runtime.Source_Code_Location {
		file_path = "test_file.odin",
		line      = 42,
		procedure = "test_proc",
	}

	line := format_log_line(
		c_data.format,
		.Info,
		"Hello, Output Struct Suppressed!",
		{},
		loc,
		out.suppressed_tags,
		context.allocator,
	)
	defer delete(line)

	testing.expect_value(t, line, "info: Hello, Output Struct Suppressed!")
}

@(test)
test_conditional_string_comparison :: proc(t: ^testing.T) {
	// Template checks level == debug and level == info
	format := Log_Format {
		template     = "[if level==debug: \"is_debug\" ? \"not_debug\"]",
		enable_color = false,
	}

	line1 := format_log_line(format, .Debug, "Hello", {}, {}, {}, context.allocator)
	defer delete(line1)
	testing.expect_value(t, line1, "is_debug")

	line2 := format_log_line(format, .Info, "Hello", {}, {}, {}, context.allocator)
	defer delete(line2)
	testing.expect_value(t, line2, "not_debug")
}

@(test)
test_user_template_conditional :: proc(t: ^testing.T) {
	format := Log_Format {
		template     = "[c=green][time][/c] [c=yellow][[location]][/c] [b][level][/b]: [if level==debug: [c=yellow][message][/c] ? [c=gray][message][/c]]",
		enable_color = true,
	}

	line := format_log_line(format, .Debug, "Hello debug message", {}, {}, {}, context.allocator)
	defer delete(line)

	// Since we enabled color, let's see what is printed.
	// We want to make sure the message is printed in yellow (i.e. [c=yellow]) and not in gray (i.e. [c=gray]).
	// [c=yellow] message should be present in the output, indicating it took the true branch.
	testing.expect(
		t,
		strings.contains(line, "Hello debug message"),
		"Expected message to be in the output",
	)

	// Yellow ANSI code is ANSI_YELLOW ("\x1b[33m").
	// Gray ANSI code is ANSI_GRAY ("\x1b[90m").
	testing.expect(
		t,
		strings.contains(line, "\x1b[33mHello debug message"),
		"Expected debug message to be formatted in yellow",
	)
	testing.expect(
		t,
		!strings.contains(line, "\x1b[90mHello debug message"),
		"Did not expect debug message to be formatted in gray",
	)
}
