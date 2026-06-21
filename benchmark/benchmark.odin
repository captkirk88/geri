package benchmark

import "core:testing"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

Export_Format :: enum {
	Console,
	Markdown,
	HTML,
}

export_format: Export_Format = .Console

_md_header_printed := false
_html_header_printed := false

@(init)
_init_benchmark_format :: proc "contextless" () {
	context = runtime.default_context()
	buf: [64]u8
	format_str := os.get_env(buf[:], "BENCH_FORMAT")
	format_str = strings.to_lower(format_str)
	switch format_str {
	case "markdown":
		export_format = .Markdown
	case "html":
		export_format = .HTML
	case:
		export_format = .Console
	}

	if ODIN_DEBUG {
		fmt.eprintfln("Benchmark export format set to: %s", format_str)
	}
}

@(fini)
_fini_benchmarks :: proc "contextless" () {
	context = runtime.default_context()
	// Ensure we close any open HTML tags if we were exporting in HTML format
	finish_export()
}

// A helper to make benchmarking more useful and less verbose.
run :: proc(
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

	// We can track allocations explicitly if we want to improve this further in the future
	time.benchmark(&opts)

	if opts.processed == 0 && opts.count > 0 {
		opts.processed = opts.count
	} else if opts.processed == 0 {
		opts.processed = 1
	}

	elapsed_ns := f64(opts.duration)
	elapsed_val, elapsed_unit := format_duration(elapsed_ns)

	switch export_format {
	case .Console:
		fmt.printf("==========================================\n")
		fmt.printf(" Benchmark: %s\n", name)
		fmt.printf("==========================================\n")
		fmt.printf(" Elapsed : %.3f %s\n", elapsed_val, elapsed_unit)
		fmt.printf(" Runs    : %d\n", opts.processed)
		if opts.processed > 0 {
			avg_val, avg_unit := format_duration(elapsed_ns / f64(opts.processed))
			fmt.printf(" Average : %.3f %s/run\n", avg_val, avg_unit)
		}
		if opts.bytes > 0 {
			fmt.printf(" Bytes   : %d\n", opts.bytes)
		}
		fmt.printf("==========================================\n\n")

	case .Markdown:
		if !_md_header_printed {
			fmt.printf("| Benchmark | Elapsed | Runs | Average | Bytes |\n")
			fmt.printf("| :--- | :--- | :--- | :--- | :--- |\n")
			_md_header_printed = true
		}
		avg_str := "-"
		if opts.processed > 0 {
			avg_val, avg_unit := format_duration(elapsed_ns / f64(opts.processed))
			avg_str = fmt.tprintf("%.3f %s/run", avg_val, avg_unit)
		}
		bytes_str := "-"
		if opts.bytes > 0 {
			bytes_str = fmt.tprintf("%d", opts.bytes)
		}
		fmt.printf(
			"| %s | %.3f %s | %d | %s | %s |\n",
			name,
			elapsed_val,
			elapsed_unit,
			opts.processed,
			avg_str,
			bytes_str,
		)

	case .HTML:
		if !_html_header_printed {
			fmt.printf("<table>\n")
			fmt.printf("  <thead>\n")
			fmt.printf(
				"    <tr><th>Benchmark</th><th>Elapsed</th><th>Runs</th><th>Average</th><th>Bytes</th></tr>\n",
			)
			fmt.printf("  </thead>\n")
			fmt.printf("  <tbody>\n")
			_html_header_printed = true
		}
		avg_str := "-"
		if opts.processed > 0 {
			avg_val, avg_unit := format_duration(elapsed_ns / f64(opts.processed))
			avg_str = fmt.tprintf("%.3f %s/run", avg_val, avg_unit)
		}
		bytes_str := "-"
		if opts.bytes > 0 {
			bytes_str = fmt.tprintf("%d", opts.bytes)
		}
		fmt.printf(
			"    <tr><td>%s</td><td>%.3f %s</td><td>%d</td><td>%s</td><td>%s</td></tr>\n",
			name,
			elapsed_val,
			elapsed_unit,
			opts.processed,
			avg_str,
			bytes_str,
		)
	}
}

// Optional helper to close HTML tags
finish_export :: proc() {
	if export_format == .HTML && _html_header_printed {
		fmt.printf("  </tbody>\n")
		fmt.printf("</table>\n")
		_html_header_printed = false // reset
	}
	if export_format == .Markdown {
		_md_header_printed = false // reset
	}
}

// A helper to format durations in a more human-readable way.
format_duration :: proc(ns: f64) -> (duration: f64, format: string) {
	if ns >= 1e9 {
		duration = ns / 1e9
		format = "s"
		return
	} else if ns >= 1e6 {
		duration = ns / 1e6
		format = "ms"
		return
	} else if ns >= 1e3 {
		duration = ns / 1e3
		format = "us"
		return
	}
	duration = ns
	format = "ns"
	return
}
