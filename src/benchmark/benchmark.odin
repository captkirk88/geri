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
			remaining = remaining[idx + 1:]
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

Bench_Tracking_Allocator :: struct {
	track:   mem.Tracking_Allocator,
	enabled: bool,
}

my_tracking_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	result: []byte,
	err: mem.Allocator_Error,
) {
	my_track := (^Bench_Tracking_Allocator)(allocator_data)
	if my_track.enabled {
		tracking_alloc := mem.tracking_allocator(&my_track.track)
		return tracking_alloc.procedure(
			tracking_alloc.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
	} else {
		return my_track.track.backing.procedure(
			my_track.track.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
	}
}

run_options :: proc(name: string, opts: ^time.Benchmark_Options) {
	my_track: Bench_Tracking_Allocator
	mem.tracking_allocator_init(&my_track.track, context.allocator)
	defer mem.tracking_allocator_destroy(&my_track.track)
	my_track.enabled = false

	my_allocator := runtime.Allocator {
		procedure = my_tracking_allocator_proc,
		data      = &my_track,
	}

	old_alloc := context.allocator
	context.allocator = my_allocator

	if opts.setup != nil {
		err := opts->setup(my_allocator)
		if err != .Okay {
			context.allocator = old_alloc
			return
		}
	}

	my_track.enabled = true

	start := time.tick_now()
	bench_err := opts->bench(my_allocator)
	diff := time.tick_since(start)
	opts.duration = diff

	my_track.enabled = false

	if bench_err != .Okay {
		context.allocator = old_alloc
		return
	}

	opts.bytes = int(my_track.track.peak_memory_allocated)

	if opts.teardown != nil {
		opts->teardown(my_allocator)
	}

	context.allocator = old_alloc

	times_per_second := f64(time.Second) / f64(diff)
	opts.rounds_per_second = times_per_second * f64(opts.count)
	opts.megabytes_per_second = f64(opts.processed) / f64(1024 * 1024) * times_per_second

	format_run(name, opts)
}


run :: proc {
	run_simple,
	run_options,
}

// Optional helper to close exports
finish_export :: proc() {
	format_finish_export()
}
