package logging

import "base:runtime"
import "bbcode"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

Time_Format :: enum {
	None,
	Short, // e.g. "HH:MM:SS" (local timezone offset)
	Long, // e.g. "YYYY-MM-DD HH:MM:SS" (local timezone offset)
	Short_UTC, // e.g. "HH:MM:SS" (UTC)
	Long_UTC, // e.g. "YYYY-MM-DD HH:MM:SS" (UTC)
	Custom, // timezone custom based using timezone_offset
}

// Log_Format configures how a log line is formatted and colored.
//
// Supported log.Options (re-exported from runtime.Logger_Option):
//   - .Level           : Include the log level prefix (e.g., "info: ", "warn : ").
//   - .Date            : Include the current date (YYYY-MM-DD) in the timestamp header.
//   - .Time            : Include the current time (HH:MM:SS) in the timestamp header.
//   - .Short_File_Path : Include the calling file's name (without directories) in the location header.
//   - .Long_File_Path  : Include the calling file's full path in the location header.
//   - .Line            : Include the line number of the log call site.
//   - .Procedure       : Include the name of the calling procedure (e.g., "main()").
//   - .Terminal_Color  : Enables standard ANSI terminal color escaping.
//   - .Thread_Id       : Include the OS thread ID of the calling thread.
Log_Tag :: bbcode.Log_Tag
Log_Tags :: bbcode.Log_Tags

Log_Format :: struct {
	template:        string,
	enable_color:    bool,
	time_format:     Time_Format,
	timezone_offset: int, // In minutes, only used if time_format == .Custom
	options:         log.Options,
}

DEFAULT_CONSOLE_FORMAT :: Log_Format {
	template     = "[time][location][level][message]",
	enable_color = true,
	time_format  = .Long,
	options      = log.Default_Console_Logger_Opts,
}

DEFAULT_FILE_FORMAT :: Log_Format {
	template     = "[[time]][[location]][[level]]: [message]",
	enable_color = false,
	time_format  = .Long,
	options      = log.Default_File_Logger_Opts,
}

Log_Output_Console :: struct {
	format:    Log_Format,
	allocator: runtime.Allocator,
}

Rolling_File_Roll_Mode :: enum {
	On_Launch,
	On_Calendar_Day,
}

Log_Output_Rolling_File :: struct {
	format:              Log_Format,
	directory:           string,
	base_name:           string,
	roll_mode:           Rolling_File_Roll_Mode,
	current_file_path:   string,
	current_file_handle: ^os.File,
	last_rolled_day:     int,
	last_rolled_year:    int,
	last_rolled_month:   int,
	mutex:               sync.Mutex,
}

Log_Proxy_Data :: struct {
	wrapped: ^Log_Output,
}

Log_Output :: struct {
	lowest_level:    log.Level,
	write_proc:      Log_Output_Write_Proc,
	destroy_proc:    Log_Output_Destroy_Proc,
	ptr:             rawptr,
	suppressed_tags: Log_Tags,
}

Log_Output_Write_Proc :: #type proc(
	output: ^Log_Output,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
)
Log_Output_Destroy_Proc :: #type proc(data: rawptr)

@(private)
log_outputs: [dynamic]Log_Output
@(private)
config_mutex: sync.Mutex

@(thread_local)
@(private)
_thread_suppressed_tags: Log_Tags

set_thread_suppressed_tags :: proc(tags: Log_Tags) {
	_thread_suppressed_tags = tags
}

get_thread_suppressed_tags :: proc() -> Log_Tags {
	return _thread_suppressed_tags
}

add_output :: proc(output: Log_Output) {
	sync.lock(&config_mutex)
	defer sync.unlock(&config_mutex)

	append(&log_outputs, output)
}

clear_outputs :: proc() {
	sync.lock(&config_mutex)
	defer sync.unlock(&config_mutex)

	for &output in log_outputs {
		close_output(&output)
	}
	clear(&log_outputs)
}

get_time_string :: proc(format: Log_Format, allocator := context.allocator) -> string {
	if format.time_format == .None {
		return ""
	}

	is_template_used := format.template != ""
	builder := strings.builder_make(allocator)
	when time.IS_SUPPORTED {
		t := time.now()

		offset_minutes := 0
		switch format.time_format {
		case .None:
		// handled above
		case .Short, .Long:
			offset_minutes = get_local_timezone_offset()
		case .Short_UTC, .Long_UTC:
			offset_minutes = 0
		case .Custom:
			offset_minutes = format.timezone_offset
		}

		t = time.from_nanoseconds(time.time_to_unix_nano(t) + i64(offset_minutes) * 60 * 1e9)

		y, m, d := time.date(t)
		h, min, s := time.clock(t)

		if !is_template_used {
			fmt.sbprint(&builder, "[")
		}

		is_long :=
			format.time_format == .Long ||
			format.time_format == .Long_UTC ||
			format.time_format == .Custom
		if is_long {
			fmt.sbprintf(&builder, "%04d-%02d-%02d ", y, int(m), d)
		}

		fmt.sbprintf(&builder, "%02d:%02d:%02d", h, min, s)

		if !is_template_used {
			fmt.sbprint(&builder, "] ")
		}
	}
	return strings.to_string(builder)
}

get_location_string :: proc(
	format: Log_Format,
	location: runtime.Source_Code_Location,
	allocator := context.allocator,
) -> string {
	opts := format.options
	if log.Location_Header_Opts & opts == nil {
		return ""
	}
	is_template_used := format.template != ""
	builder := strings.builder_make(allocator)
	if !is_template_used {
		fmt.sbprint(&builder, "[")
	}

	file := location.file_path
	if .Short_File_Path in opts {
		last := 0
		for r, i in location.file_path {
			if r == '/' || r == '\\' {
				last = i + 1
			}
		}
		file = location.file_path[last:]
	}

	if log.Location_File_Opts & opts != nil {
		fmt.sbprint(&builder, file)
	}
	if .Line in opts {
		if log.Location_File_Opts & opts != nil {
			fmt.sbprint(&builder, ":")
		}
		fmt.sbprint(&builder, location.line)
	}

	if .Procedure in opts {
		if (log.Location_File_Opts | {.Line}) & opts != nil {
			fmt.sbprint(&builder, ":")
		}
		fmt.sbprintf(&builder, "%s()", location.procedure)
	}

	if !is_template_used {
		fmt.sbprint(&builder, "] ")
	}
	return strings.to_string(builder)
}

get_level_string :: proc(
	level: log.Level,
	format: Log_Format,
	allocator := context.allocator,
) -> string {
	builder := strings.builder_make(allocator)
	is_template_used := format.template != ""
	write_level_header(&builder, level, format.enable_color, is_template_used)
	return strings.to_string(builder)
}

format_log_line :: proc(
	format: Log_Format,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
	suppressed_tags: Log_Tags = {},
	allocator := context.allocator,
) -> string {
	opts := format.options
	is_template_used := format.template != ""

	suppressed := suppressed_tags | _thread_suppressed_tags

	time_str := ""
	if .Time not_in suppressed {
		time_str = get_time_string(format, allocator)
	}
	defer if time_str != "" {delete(time_str, allocator)}

	location_str := ""
	if .Location not_in suppressed {
		location_str = get_location_string(format, location, allocator)
	}
	defer if location_str != "" {delete(location_str, allocator)}

	level_str := ""
	if .Level not_in suppressed {
		level_str = get_level_string(level, format, allocator)
	}
	defer if level_str != "" {delete(level_str, allocator)}

	thread_id_str := ""
	if .Thread_Id not_in suppressed && .Thread_Id in opts {
		if is_template_used {
			thread_id_str = fmt.aprintf("%d", os.get_current_thread_id(), allocator = allocator)
		} else {
			thread_id_str = fmt.aprintf("[%d] ", os.get_current_thread_id(), allocator = allocator)
		}
	}
	defer if thread_id_str != "" {delete(thread_id_str, allocator)}

	processed_message := ""
	if .Message not_in suppressed {
		processed_message = bbcode.process_colors(text, format.enable_color, allocator)
	}
	defer if processed_message != "" {delete(processed_message, allocator)}

	template := format.template
	if template == "" {
		template = "[time][location][level][message]"
	}

	res, err, ok := bbcode.validate_and_format_bbcode(
		template,
		format.enable_color,
		true,
		time_str,
		location_str,
		level_str,
		processed_message,
		thread_id_str,
		allocator,
		suppressed,
	)
	if !ok {
		panic(err)
	}

	return res
}

@(private)
console_write :: proc(
	output: ^Log_Output,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
) {
	c_data := cast(^Log_Output_Console)output.ptr
	allocator := runtime.default_allocator()
	line := format_log_line(
		c_data.format,
		level,
		text,
		options,
		location,
		output.suppressed_tags,
		allocator,
	)
	defer delete(line, allocator)

	h := os.stdout
	if level >= .Error {
		h = os.stderr
	}

	fmt.fprintf(h, "%s", line, newline = true)
}

@(private)
console_destroy :: proc(data: rawptr) {
	c_data := cast(^Log_Output_Console)data
	free(c_data, c_data.allocator)
}

create_console_output :: proc(
	lowest_level: log.Level,
	format: Log_Format,
	allocator: runtime.Allocator = context.allocator,
	suppressed_tags: Log_Tags = {},
) -> Log_Output {
	alloc := allocator
	if alloc.procedure == nil {
		alloc = runtime.default_allocator()
	}
	ptr := new(Log_Output_Console, alloc)
	ptr.format = format
	ptr.allocator = alloc
	return Log_Output {
		lowest_level = lowest_level,
		write_proc = console_write,
		destroy_proc = console_destroy,
		ptr = ptr,
		suppressed_tags = suppressed_tags,
	}
}

@(private)
rolling_file_write :: proc(
	output: ^Log_Output,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
) {
	rf := cast(^Log_Output_Rolling_File)output.ptr
	sync.lock(&rf.mutex)
	defer sync.unlock(&rf.mutex)

	if check_and_roll_file(rf) {
		line := format_log_line(
			rf.format,
			level,
			text,
			options,
			location,
			output.suppressed_tags,
			runtime.default_allocator(),
		)
		defer delete(line, runtime.default_allocator())

		fmt.fprintf(rf.current_file_handle, "%s\n", line)
	}
}

@(private)
rolling_file_destroy :: proc(data: rawptr) {
	rf := cast(^Log_Output_Rolling_File)data
	if rf.current_file_handle != nil {
		os.close(rf.current_file_handle)
	}
	delete(rf.directory, runtime.default_allocator())
	delete(rf.base_name, runtime.default_allocator())
	delete(rf.current_file_path, runtime.default_allocator())
	free(rf, runtime.default_allocator())
}

create_rolling_file_output :: proc(
	lowest_level: log.Level,
	directory: string,
	base_name: string,
	roll_mode: Rolling_File_Roll_Mode,
	format: Log_Format,
	suppressed_tags: Log_Tags = {},
) -> Log_Output {
	rf := new(Log_Output_Rolling_File, runtime.default_allocator())
	rf.directory = strings.clone(directory, runtime.default_allocator())
	rf.base_name = strings.clone(base_name, runtime.default_allocator())
	rf.roll_mode = roll_mode
	rf.format = format
	return Log_Output {
		lowest_level = lowest_level,
		write_proc = rolling_file_write,
		destroy_proc = rolling_file_destroy,
		ptr = rf,
		suppressed_tags = suppressed_tags,
	}
}

@(private)
proxy_write :: proc(
	output: ^Log_Output,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
) {
	proxy := cast(^Log_Proxy_Data)output.ptr
	if proxy.wrapped != nil && proxy.wrapped.write_proc != nil {
		if level >= proxy.wrapped.lowest_level {
			proxy.wrapped.write_proc(proxy.wrapped, level, text, options, location)
		}
	}
}

@(private)
proxy_destroy :: proc(data: rawptr) {
	proxy := cast(^Log_Proxy_Data)data
	if proxy.wrapped != nil {
		if proxy.wrapped.destroy_proc != nil {
			proxy.wrapped.destroy_proc(proxy.wrapped.ptr)
		}
		free(proxy.wrapped, runtime.default_allocator())
	}
	free(proxy, runtime.default_allocator())
}

create_proxy_output :: proc(
	lowest_level: log.Level,
	wrapped: Log_Output,
	suppressed_tags: Log_Tags = {},
) -> Log_Output {
	proxy := new(Log_Proxy_Data, runtime.default_allocator())

	wrapped_heap := new(Log_Output, runtime.default_allocator())
	wrapped_heap^ = wrapped

	proxy.wrapped = wrapped_heap

	return Log_Output {
		lowest_level = lowest_level,
		write_proc = proxy_write,
		destroy_proc = proxy_destroy,
		ptr = proxy,
		suppressed_tags = suppressed_tags,
	}
}

@(private)
close_output :: proc(output: ^Log_Output) {
	if output.destroy_proc != nil {
		output.destroy_proc(output.ptr)
	}
	output.ptr = nil
}

@(private)
check_and_roll_file :: proc(rf: ^Log_Output_Rolling_File) -> bool {
	t := time.now()
	y, m, d := time.date(t)

	need_roll := false
	if rf.current_file_handle == nil {
		need_roll = true
	} else if rf.roll_mode == .On_Calendar_Day {
		if y != rf.last_rolled_year || int(m) != rf.last_rolled_month || d != rf.last_rolled_day {
			need_roll = true
		}
	}

	if need_roll {
		if rf.current_file_handle != nil {
			os.close(rf.current_file_handle)
			rf.current_file_handle = nil
		}

		if rf.directory != "" {
			os.make_directory_all(rf.directory)
		}

		filename: string
		if rf.roll_mode == .On_Launch {
			h, min, s := time.clock(t)
			filename = fmt.aprintf(
				"%s/%s_%04d-%02d-%02d_%02d-%02d-%02d.log",
				rf.directory,
				rf.base_name,
				y,
				int(m),
				d,
				h,
				min,
				s,
				allocator = runtime.default_allocator(),
			)
		} else {
			filename = fmt.aprintf(
				"%s/%s_%04d-%02d-%02d.log",
				rf.directory,
				rf.base_name,
				y,
				int(m),
				d,
				allocator = runtime.default_allocator(),
			)
		}

		delete(rf.current_file_path, runtime.default_allocator())
		rf.current_file_path = filename

		f, err := os.open(
			rf.current_file_path,
			{.Write, .Create, .Append},
			os.Permissions_Default_File,
		)
		if err != nil {
			fmt.eprintfln("Failed to open log file %s: %v", rf.current_file_path, err)
			return false
		}
		rf.current_file_handle = f
		rf.last_rolled_year = y
		rf.last_rolled_month = int(m)
		rf.last_rolled_day = d
	}

	return rf.current_file_handle != nil
}

@(private)
Level_Headers := [?]string {
	0 ..< 10 = "debug:",
	10 ..< 20 = "info:",
	20 ..< 30 = "warn :",
	30 ..< 40 = "error:",
	40 ..< 50 = "FATAL:",
}

@(private)
Level_Headers_Template := [?]string {
	0 ..< 10 = "debug",
	10 ..< 20 = "info",
	20 ..< 30 = "warn",
	30 ..< 40 = "error",
	40 ..< 50 = "FATAL",
}

@(private)
write_level_header :: proc(
	builder: ^strings.Builder,
	level: log.Level,
	enable_color: bool,
	is_template_used: bool,
) {
	col := ""
	reset := ""
	if enable_color {
		reset = ANSI_RESET
		switch level {
		case .Debug:
			col = ANSI_BOLD_GRAY
		case .Info:
			col = ANSI_BOLD_WHITE
		case .Warning:
			col = ANSI_BOLD_YELLOW
		case .Error, .Fatal:
			col = ANSI_BOLD_RED
		}
	}

	fmt.sbprint(builder, col)
	if is_template_used {
		fmt.sbprint(builder, Level_Headers_Template[level])
		fmt.sbprint(builder, reset)
	} else {
		fmt.sbprint(builder, Level_Headers[level])
		fmt.sbprint(builder, reset)
		fmt.sbprint(builder, " ")
	}
}


@(private)
custom_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	context.allocator = runtime.default_allocator()

	for &output in log_outputs {
		if level < output.lowest_level {
			continue
		}

		if output.write_proc != nil {
			output.write_proc(&output, level, text, options, location)
		}
	}
}

@(init)
init_log :: proc "contextless" () {
	if (logger.procedure != nil) {
		return
	}
	context = runtime.default_context()
	context.allocator = runtime.default_allocator()

	logger = log.Logger {
		procedure    = custom_logger_proc,
		data         = nil,
		lowest_level = .Debug,
		options      = log.Default_Console_Logger_Opts,
	}

	log_outputs = make([dynamic]Log_Output, runtime.default_allocator())
	append(&log_outputs, create_console_output(.Info, DEFAULT_CONSOLE_FORMAT))
}

@(fini)
deinit_log :: proc "contextless" () {
	if (logger.procedure == nil) {
		return
	}
	context = runtime.default_context()
	context.allocator = runtime.default_allocator()

	for &output in log_outputs {
		close_output(&output)
	}
	delete(log_outputs)
	log_outputs = nil

	logger = {}
}

// Log a formatted debug message
debug :: proc(format: string, args: ..any, location := #caller_location) {
	if !ODIN_DEBUG && !ODIN_TEST {
		return
	}
	context.logger = logger
	if len(args) > 0 {
		log.logf(.Debug, format, ..args, location = location)
	} else {
		log.log(.Debug, format, location = location)
	}
}

// Log a formatted warning message
warn :: proc(format: string, args: ..any, location := #caller_location) {
	context.logger = logger
	if len(args) > 0 {
		log.logf(.Warning, format, ..args, location = location)
	} else {
		log.log(.Warning, format, location = location)
	}
}

// Log a formatted informational message
info :: proc(format: string, args: ..any, location := #caller_location) {
	context.logger = logger
	if len(args) > 0 {
		log.logf(.Info, format, ..args, location = location)
	} else {
		log.log(.Info, format, location = location)
	}
}

// Log a formatted error message
error :: proc(format: string, args: ..any, location := #caller_location) {
	if len(args) > 0 {
		log.logf(.Error, format, ..args, location = location)
	} else {
		log.log(.Error, format, location = location)
	}
}

// Log a formatted fatal error and exit the program
fatal :: proc(format: string, args: ..any, location := #caller_location) {
	context.logger = logger
	if len(args) > 0 {
		log.logf(.Fatal, format, ..args, location = location)
	} else {
		log.log(.Fatal, format, location = location)
	}
}

// Log a panic message and exit the program
panic :: proc(args: ..any, location := #caller_location) {
	context.logger = logger
	log.panic(args, location = location)
}
// Log a formatted panic message and exit the program
panicf :: proc(format: string, args: ..any, location := #caller_location) {
	context.logger = logger
	if len(args) > 0 {
		log.panicf(format, ..args, location = location)
	} else {
		log.panic(format, location = location)
	}
}

@(private)
logger: log.Logger
