package benchmark

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(init)
_init_benchmark_format :: proc "contextless" () {
	context = runtime.default_context()
	buf: [256]u8
	format_str := os.get_env(buf[:], "BENCH_FORMAT")
	format_str = strings.to_lower(format_str)

	export_formats = {}
	if len(format_str) == 0 {
		export_formats = {.Console}
		return
	}

	remaining := format_str
	for len(remaining) > 0 {
		part := remaining
		idx := strings.index(remaining, ";")
		if idx >= 0 {
			part = remaining[:idx]
			remaining = remaining[idx+1:]
		} else {
			remaining = ""
		}

		part = strings.trim_space(part)
		if len(part) == 0 do continue

		switch part {
		case "markdown", "md":
			export_formats += {.Markdown}
		case "html":
			export_formats += {.HTML}
		case "graph", "g":
			export_formats += {.Graph}
		case "console", "c":
			export_formats += {.Console}
		}
	}

	if export_formats == {} {
		export_formats = {.Console}
	}

	if ODIN_DEBUG {
		fmt.eprintfln("Benchmark export formats set to: %v", export_formats)
	}
}

@(fini)
_fini_benchmarks :: proc "contextless" () {
	context = runtime.default_context()
	finish_export()
}

// A helper to make benchmarking more useful and less verbose.
run_simple :: proc(
	name: string,
	count: int,
	user_data: rawptr,
	bench_fn: proc(
		opts: ^time.Benchmark_Options,
		allocator: mem.Allocator,
	) -> time.Benchmark_Error,
) {
	opts := time.Benchmark_Options {
		user_data = user_data,
		count     = count,
		bench     = bench_fn,
	}
	run_options(name, &opts)
}

run_options :: proc(name: string, opts: ^time.Benchmark_Options) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	tracking_alloc := mem.tracking_allocator(&track)

	old_alloc := context.allocator
	context.allocator = tracking_alloc

	time.benchmark(opts, tracking_alloc)

	opts.bytes = int(track.peak_memory_allocated)

	context.allocator = old_alloc
	format_run(name, opts)
}

run :: proc{run_simple, run_options}

// Optional helper to close exports
finish_export :: proc() {
	format_finish_export()
}
