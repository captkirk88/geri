package logging_raylib

import "base:runtime"
import "core:c"
import "core:mem"
import "core:strings"
import stdlog "core:log"
import "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import log "../"

@(private)
rl_log_buf: []byte

raylib_callback :: proc "c" (logLevel: raylib.TraceLogLevel, text: cstring, args: ^c.va_list) {
	context = runtime.default_context()
	log.set_thread_suppressed_tags({.Location})
	defer log.set_thread_suppressed_tags({})

	level: stdlog.Level
	switch logLevel {
	case .TRACE, .DEBUG:
		level = .Debug
	case .ALL, .NONE, .INFO:
		level = .Info
	case .WARNING:
		level = .Warning
	case .ERROR:
		level = .Error
	case .FATAL:
		level = .Fatal
	}

	if rl_log_buf == nil {
		rl_log_buf = make([]byte, 1024, runtime.default_allocator())
	}

	for {
		n := int(stbsp.vsnprintf(raw_data(rl_log_buf), i32(len(rl_log_buf)), text, args))
		if n < len(rl_log_buf) {
			log_msg := string(rl_log_buf[:n])
			switch level {
			case .Debug:
				log.debug(log_msg)
			case .Info:
				log.info(log_msg)
			case .Warning:
				log.warn(log_msg)
			case .Error:
				log.error(log_msg)
			case .Fatal:
				log.fatal(log_msg)
			}
			mem.zero_slice(rl_log_buf[:n])
			break
		}
		new_buf, _ := mem.resize_bytes(
			rl_log_buf,
			len(rl_log_buf) * 2,
			allocator = runtime.default_allocator(),
		)
		rl_log_buf = new_buf
	}
}

raylib_log_write :: proc(
	output: ^log.Log_Output,
	level: stdlog.Level,
	text: string,
	options: stdlog.Options,
	location: runtime.Source_Code_Location,
) {
	rl_level: raylib.TraceLogLevel
	switch level {
	case .Debug:
		rl_level = .DEBUG
	case .Info:
		rl_level = .INFO
	case .Warning:
		rl_level = .WARNING
	case .Error:
		rl_level = .ERROR
	case .Fatal:
		rl_level = .FATAL
	}

	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	raylib.TraceLog(rl_level, c_text)
}

create_raylib_output :: proc(lowest_level: stdlog.Level) -> log.Log_Output {
	return log.Log_Output {
		lowest_level    = lowest_level,
		write_proc      = raylib_log_write,
		destroy_proc    = nil,
		ptr            = nil,
		suppressed_tags = {.Location},
	}
}

init_raylib_logging :: proc() {
	raylib.SetTraceLogLevel(.ALL)
	raylib.SetTraceLogCallback(raylib_callback)
}

deinit_raylib_logging :: proc() {
	raylib.SetTraceLogCallback(nil)
	if rl_log_buf != nil {
		delete(rl_log_buf)
		rl_log_buf = nil
	}
}
