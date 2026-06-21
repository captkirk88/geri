package benchmark

import "base:runtime"
import "core:fmt"
import "core:image"
import bmp "core:image/bmp"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

Export_Format :: enum {
	Console,
	Markdown,
	HTML,
	Graph,
}

Export_Formats :: distinct bit_set[Export_Format; u8]

export_formats: Export_Formats = {.Console}

_md_header_printed := false
_html_header_printed := false

Benchmark_Result :: struct {
	name:       string,
	elapsed_ns: f64,
	runs:       int,
	avg_ns:     f64,
	bytes:      int,
}

results: [dynamic]Benchmark_Result

format_run :: proc(name: string, opts: ^time.Benchmark_Options) {
	if opts.processed == 0 && opts.count > 0 {
		opts.processed = opts.count
	} else if opts.processed == 0 {
		opts.processed = 1
	}

	elapsed_ns := f64(opts.duration)
	elapsed_val, elapsed_unit := format_duration(elapsed_ns)

	if .Console in export_formats {
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
	}

	if .Markdown in export_formats {
		if !_md_header_printed {
			if .Graph in export_formats {
				fmt.printf("# Benchmark Results\n\n")
				fmt.printf("![Benchmark Graph](BENCHMARKS.bmp)\n\n")
			}
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
	}

	if .HTML in export_formats {
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

	if .Graph in export_formats {
		avg_ns := elapsed_ns / f64(opts.processed) if opts.processed > 0 else 0.0
		append(
			&results,
			Benchmark_Result {
				name = strings.clone(name, runtime.default_allocator()),
				elapsed_ns = elapsed_ns,
				runs = opts.processed,
				avg_ns = avg_ns,
				bytes = int(opts.bytes),
			},
		)
	}
}

export_graph_image :: proc() {
	if len(results) == 0 {
		return
	}

	min_avg := math.inf_f64(1)
	max_avg := math.inf_f64(-1)
	fastest_idx := -1

	for res, i in results {
		if res.avg_ns > 0.0 {
			if res.avg_ns < min_avg {
				min_avg = res.avg_ns
				fastest_idx = i
			}
			if res.avg_ns > max_avg {
				max_avg = res.avg_ns
			}
		}
	}

	if min_avg == math.inf_f64(1) || max_avg == math.inf_f64(-1) {
		min_avg = 1.0
		max_avg = 1.0
	}

	// Image dimension calculations with scale = 2
	max_name_len := 0
	for res in results {
		if len(res.name) > max_name_len {
			max_name_len = len(res.name)
		}
	}
	if max_name_len < 10 { max_name_len = 10 }
	if max_name_len > 40 { max_name_len = 40 }

	label_col_w := max_name_len * 12
	bar_x_start := 20 + label_col_w + 20
	bar_w_max := 400
	bar_x_end := bar_x_start + bar_w_max
	val_x_start := bar_x_end + 20
	factor_x_start := val_x_start + 180 + 15
	width := factor_x_start + 240 + 20

	N := len(results)
	height := 60 + N * 60 + 30

	pixels := make([][4]u8, width * height, runtime.default_allocator())
	defer delete(pixels, runtime.default_allocator())

	// Clear background (Dark theme: #18181c)
	bg_color := [4]u8{24, 24, 28, 255}
	for p in 0 ..< len(pixels) {
		pixels[p] = bg_color
	}

	// Draw Title (scale = 2)
	title_color := [4]u8{255, 255, 255, 255}
	draw_string(pixels, width, height, "Benchmark Results", 20, 20, title_color, 2)

	// Separator line
	draw_rect(pixels, width, height, 20, 48, width - 40, 2, [4]u8{45, 45, 50, 255})

	for res, i in results {
		y_row := 60 + i * 60

		// Draw name label (scale = 2)
		label_color := [4]u8{200, 200, 200, 255}
		draw_string(pixels, width, height, res.name, 20, y_row + 18, label_color, 2)

		// Bar calculation
		ratio := 1.0
		if max_avg > min_avg && res.avg_ns > 0.0 {
			log_min := math.ln(min_avg)
			log_max := math.ln(max_avg)
			log_val := math.ln(res.avg_ns)
			ratio = 1.0 - (log_val - log_min) / (log_max - log_min)
		} else if res.avg_ns == 0.0 {
			ratio = 0.0
		}

		bar_w := int(math.round(ratio * f64(bar_w_max)))
		if bar_w < 2 && res.avg_ns > 0.0 { bar_w = 2 }
		if bar_w > bar_w_max { bar_w = bar_w_max }

		// Draw background track for bar (#2d2d32)
		track_color := [4]u8{45, 45, 50, 255}
		draw_rect(pixels, width, height, bar_x_start, y_row + 15, bar_w_max, 20, track_color)

		// Draw bar (Green if fastest, else Cyan)
		bar_color := [4]u8{52, 152, 219, 255} // Cyan #3498db
		if i == fastest_idx {
			bar_color = [4]u8{46, 204, 113, 255} // Green #2ecc71
		}
		draw_rect(pixels, width, height, bar_x_start, y_row + 15, bar_w, 20, bar_color)

		// Format value string
		avg_val, avg_unit := format_duration(res.avg_ns)
		val_str := fmt.tprintf("%.3f %s/run", avg_val, avg_unit)

		// Draw value text (scale = 2)
		val_color := [4]u8{240, 240, 240, 255}
		draw_string(pixels, width, height, val_str, val_x_start, y_row + 18, val_color, 2)

		// Draw runs string (scale = 2)
		runs_str := fmt.tprintf("(%d runs)", res.runs)
		runs_color := [4]u8{160, 160, 160, 255}
		draw_string(pixels, width, height, runs_str, factor_x_start, y_row + 18, runs_color, 2)
	}

	// Convert pixel array to image
	img, ok := image.pixels_to_image(pixels, width, height)
	if ok {
		save_err := bmp.save("BENCHMARKS.bmp", &img)
		if save_err != nil {
			fmt.eprintfln("Failed to save benchmark graph: %v", save_err)
		}
	}

	// Clean up results memory
	for res in results {
		delete(res.name, runtime.default_allocator())
	}
	delete(results)
	results = nil
}

format_finish_export :: proc() {
	if .HTML in export_formats {
		if _html_header_printed {
			fmt.printf("  </tbody>\n")
			fmt.printf("</table>\n")
			_html_header_printed = false
		}
	}
	if .Markdown in export_formats {
		_md_header_printed = false
	}
	if .Graph in export_formats {
		export_graph_image()
	}
}

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

@(private)
draw_char :: proc(pixels: [][4]u8, width, height: int, c: rune, px, py: int, col: [4]u8, scale: int = 1) {
	idx := int(c) - 32
	if idx < 0 || idx >= 95 {
		return
	}

	for col_idx in 0 ..< 5 {
		b := FONT_5X7[idx][col_idx]
		for row_idx in 0 ..< 7 {
			if (b & (1 << u8(row_idx))) != 0 {
				for sy in 0 ..< scale {
					for sx in 0 ..< scale {
						dx := px + col_idx * scale + sx
						dy := py + row_idx * scale + sy
						if dx >= 0 && dx < width && dy >= 0 && dy < height {
							pixels[dy * width + dx] = col
						}
					}
				}
			}
		}
	}
}

@(private)
draw_string :: proc(pixels: [][4]u8, width, height: int, str: string, px, py: int, col: [4]u8, scale: int = 1) {
	cx := px
	for c in str {
		draw_char(pixels, width, height, c, cx, py, col, scale)
		cx += 6 * scale
	}
}

@(private)
draw_rect :: proc(pixels: [][4]u8, width, height: int, rx, ry, rw, rh: int, col: [4]u8) {
	for dy in 0 ..< rh {
		for dx in 0 ..< rw {
			px := rx + dx
			py := ry + dy
			if px >= 0 && px < width && py >= 0 && py < height {
				pixels[py * width + px] = col
			}
		}
	}
}

// Minimal 5x7 ASCII bitmap font (ASCII 32 to 127)
@(private)
FONT_5X7 := [95][5]u8{
	{0x00, 0x00, 0x00, 0x00, 0x00}, // Space
	{0x00, 0x00, 0x5f, 0x00, 0x00}, // !
	{0x00, 0x07, 0x00, 0x07, 0x00}, // "
	{0x14, 0x7f, 0x14, 0x7f, 0x14}, // #
	{0x24, 0x2a, 0x7f, 0x2a, 0x12}, // $
	{0x23, 0x13, 0x08, 0x64, 0x62}, // %
	{0x36, 0x49, 0x55, 0x22, 0x50}, // &
	{0x00, 0x05, 0x03, 0x00, 0x00}, // '
	{0x00, 0x1c, 0x22, 0x41, 0x00}, // (
	{0x00, 0x41, 0x22, 0x1c, 0x00}, // )
	{0x08, 0x2a, 0x1c, 0x2a, 0x08}, // *
	{0x08, 0x08, 0x3e, 0x08, 0x08}, // +
	{0x00, 0x50, 0x30, 0x00, 0x00}, // ,
	{0x08, 0x08, 0x08, 0x08, 0x08}, // -
	{0x00, 0x60, 0x60, 0x00, 0x00}, // .
	{0x20, 0x10, 0x08, 0x04, 0x02}, // /
	{0x3e, 0x51, 0x49, 0x45, 0x3e}, // 0
	{0x00, 0x42, 0x7f, 0x40, 0x00}, // 1
	{0x42, 0x61, 0x51, 0x49, 0x46}, // 2
	{0x21, 0x41, 0x45, 0x4b, 0x31}, // 3
	{0x18, 0x14, 0x12, 0x7f, 0x10}, // 4
	{0x27, 0x45, 0x45, 0x45, 0x39}, // 5
	{0x3c, 0x4a, 0x49, 0x49, 0x30}, // 6
	{0x01, 0x71, 0x09, 0x05, 0x03}, // 7
	{0x36, 0x49, 0x49, 0x49, 0x36}, // 8
	{0x06, 0x49, 0x49, 0x29, 0x1e}, // 9
	{0x00, 0x36, 0x36, 0x00, 0x00}, // :
	{0x00, 0x56, 0x36, 0x00, 0x00}, // ;
	{0x00, 0x08, 0x14, 0x22, 0x41}, // <
	{0x14, 0x14, 0x14, 0x14, 0x14}, // =
	{0x41, 0x22, 0x14, 0x08, 0x00}, // >
	{0x02, 0x01, 0x51, 0x09, 0x06}, // ?
	{0x32, 0x49, 0x79, 0x41, 0x3e}, // @
	{0x7e, 0x11, 0x11, 0x11, 0x7e}, // A
	{0x7f, 0x49, 0x49, 0x49, 0x36}, // B
	{0x3e, 0x41, 0x41, 0x41, 0x22}, // C
	{0x7f, 0x41, 0x41, 0x22, 0x1c}, // D
	{0x7f, 0x49, 0x49, 0x49, 0x41}, // E
	{0x7f, 0x09, 0x09, 0x01, 0x01}, // F
	{0x3e, 0x41, 0x41, 0x51, 0x72}, // G
	{0x7f, 0x08, 0x08, 0x08, 0x7f}, // H
	{0x00, 0x41, 0x7f, 0x41, 0x00}, // I
	{0x20, 0x40, 0x41, 0x3f, 0x01}, // J
	{0x7f, 0x08, 0x14, 0x22, 0x41}, // K
	{0x7f, 0x40, 0x40, 0x40, 0x40}, // L
	{0x7f, 0x02, 0x0c, 0x02, 0x7f}, // M
	{0x7f, 0x04, 0x08, 0x10, 0x7f}, // N
	{0x3e, 0x41, 0x41, 0x41, 0x3e}, // O
	{0x7f, 0x09, 0x09, 0x09, 0x06}, // P
	{0x3e, 0x41, 0x51, 0x21, 0x5e}, // Q
	{0x7f, 0x09, 0x19, 0x29, 0x46}, // R
	{0x46, 0x49, 0x49, 0x49, 0x31}, // S
	{0x01, 0x01, 0x7f, 0x01, 0x01}, // T
	{0x3f, 0x40, 0x40, 0x40, 0x3f}, // U
	{0x1f, 0x20, 0x40, 0x20, 0x1f}, // V
	{0x7f, 0x20, 0x18, 0x20, 0x7f}, // W
	{0x63, 0x14, 0x08, 0x14, 0x63}, // X
	{0x03, 0x04, 0x78, 0x04, 0x03}, // Y
	{0x61, 0x51, 0x49, 0x45, 0x43}, // Z
	{0x00, 0x00, 0x7f, 0x41, 0x41}, // [
	{0x02, 0x04, 0x08, 0x10, 0x20}, // \
	{0x41, 0x41, 0x7f, 0x00, 0x00}, // ]
	{0x04, 0x02, 0x01, 0x02, 0x04}, // ^
	{0x40, 0x40, 0x40, 0x40, 0x40}, // _
	{0x00, 0x01, 0x02, 0x00, 0x00}, // `
	{0x20, 0x54, 0x54, 0x54, 0x78}, // a
	{0x7f, 0x48, 0x44, 0x44, 0x38}, // b
	{0x38, 0x44, 0x44, 0x44, 0x20}, // c
	{0x38, 0x44, 0x44, 0x48, 0x7f}, // d
	{0x38, 0x54, 0x54, 0x54, 0x18}, // e
	{0x08, 0x7e, 0x09, 0x01, 0x02}, // f
	{0x0c, 0x52, 0x52, 0x52, 0x3e}, // g
	{0x7f, 0x08, 0x04, 0x04, 0x78}, // h
	{0x00, 0x44, 0x7d, 0x40, 0x00}, // i
	{0x20, 0x40, 0x44, 0x3d, 0x00}, // j
	{0x00, 0x7f, 0x10, 0x28, 0x44}, // k
	{0x00, 0x41, 0x7f, 0x40, 0x00}, // l
	{0x7c, 0x04, 0x18, 0x04, 0x78}, // m
	{0x7c, 0x08, 0x04, 0x04, 0x78}, // n
	{0x38, 0x44, 0x44, 0x44, 0x38}, // o
	{0x7c, 0x14, 0x14, 0x14, 0x08}, // p
	{0x08, 0x14, 0x14, 0x14, 0x7c}, // q
	{0x00, 0x7c, 0x08, 0x04, 0x04}, // r
	{0x48, 0x54, 0x54, 0x54, 0x20}, // s
	{0x04, 0x3f, 0x44, 0x40, 0x20}, // t
	{0x3c, 0x40, 0x40, 0x20, 0x7c}, // u
	{0x1c, 0x20, 0x40, 0x20, 0x1c}, // v
	{0x3c, 0x40, 0x30, 0x40, 0x3c}, // w
	{0x44, 0x28, 0x10, 0x28, 0x44}, // x
	{0x0c, 0x50, 0x50, 0x50, 0x3c}, // y
	{0x44, 0x64, 0x54, 0x4c, 0x44}, // z
	{0x08, 0x36, 0x41, 0x00, 0x00}, // {
	{0x00, 0x00, 0x77, 0x00, 0x00}, // |
	{0x00, 0x00, 0x41, 0x36, 0x08}, // }
	{0x08, 0x08, 0x2a, 0x1c, 0x08}, // ~
}
