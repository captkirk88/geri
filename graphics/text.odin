package graphics

import log "../logging"
import bbcode "../logging/bbcode"
import c "core:c"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

Text_Span :: struct {
	text:          string,
	color:         [4]f32,
	bg_color:      [4]f32,
	has_bg:        bool,
	bold:          bool,
	italic:        bool,
	underline:     bool,
	strikethrough: bool,
	font_size:     f32,
	font_path:     string,
}

Glyph_Key :: struct {
	r:            rune,
	pixel_height: int,
}

Font :: struct {
	info:         stbtt.fontinfo,
	data:         []byte,
	scale:        f32,
	pixel_height: f32,
	ascent:       int,
	descent:      int,
	line_gap:     int,
	glyphs:       map[Glyph_Key]Cached_Glyph,
}

Cached_Glyph :: struct {
	width, height: int,
	xoff, yoff:    int,
	advance:       int,
	pixels:        []u8,
}

text_is_y_down :: proc(vp: linalg.Matrix4f32) -> bool {
	// Using the linear-part determinant avoids sign flips during rotation.
	det2 := vp[0][0] * vp[1][1] - vp[0][1] * vp[1][0]
	return det2 < 0.0
}

font_init :: proc(f: ^Font, font_path: string, pixel_height: f32) -> bool {
	data, err := os.read_entire_file(font_path, context.allocator)
	if err != nil do return false

	f.data = data
	if !stbtt.InitFont(&f.info, raw_data(f.data), 0) {
		delete(f.data)
		return false
	}

	f.pixel_height = pixel_height
	f.scale = stbtt.ScaleForPixelHeight(&f.info, pixel_height)

	asc, desc, lg: c.int
	stbtt.GetFontVMetrics(&f.info, &asc, &desc, &lg)
	f.ascent = int(asc)
	f.descent = int(desc)
	f.line_gap = int(lg)

	f.glyphs = make(map[Glyph_Key]Cached_Glyph)
	return true
}

font_destroy :: proc(f: ^Font) {
	for _, g in f.glyphs {
		delete(g.pixels)
	}
	delete(f.glyphs)
	delete(f.data)
}

get_glyph :: proc(f: ^Font, r: rune, pixel_height: f32) -> Cached_Glyph {
	key := Glyph_Key {
		r            = r,
		pixel_height = int(pixel_height + 0.5),
	}
	if g, ok := f.glyphs[key]; ok do return g

	scale := stbtt.ScaleForPixelHeight(&f.info, pixel_height)

	w, h, xoff, yoff: c.int
	bitmap := stbtt.GetCodepointBitmap(&f.info, scale, scale, r, &w, &h, &xoff, &yoff)
	defer if bitmap != nil do stbtt.FreeBitmap(bitmap, nil)

	adv, lsb: c.int
	stbtt.GetCodepointHMetrics(&f.info, r, &adv, &lsb)

	pixels := make([]u8, int(w * h))
	if bitmap != nil {
		copy(pixels, bitmap[:w * h])
	}

	g := Cached_Glyph {
		width   = int(w),
		height  = int(h),
		xoff    = int(xoff),
		yoff    = int(yoff),
		advance = int(adv),
		pixels  = pixels,
	}
	f.glyphs[key] = g
	return g
}

append_glyph_preloaded :: proc(
	batch: ^Batch2D,
	f: ^Font,
	g: Cached_Glyph,
	x_pos, y_pos: f32,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	bold := false,
	italic := false,
) {
	if g.width == 0 || g.height == 0 do return

	is_y_down := text_is_y_down(vp)

	px := x_pos + f32(g.xoff)
	py := is_y_down ? (y_pos + f32(g.yoff)) : (y_pos - f32(g.yoff))

	for y in 0 ..< g.height {
		for x in 0 ..< g.width {
			val := g.pixels[y * g.width + x]
			if val > 0 {
				alpha := color[3] * (f32(val) / 255.0)
				c := [4]f32{color[0], color[1], color[2], alpha}

				gx := px + f32(x)
				gy := is_y_down ? (py + f32(y)) : (py - f32(y))

				if italic {
					skew := f32(g.height - y) * 0.2
					gx += skew
				}

				append_quad(batch, gx, gy - 1.0, gx + 1.0, gy, c, vp)
				if bold {
					append_quad(batch, gx + 1.0, gy - 1.0, gx + 2.0, gy, c, vp)
				}
			}
		}
	}
}

append_glyph :: proc(
	batch: ^Batch2D,
	f: ^Font,
	r: rune,
	x_pos, y_pos: f32,
	color: [4]f32,
	vp: linalg.Matrix4f32,
) -> f32 {
	g := get_glyph(f, r, f.pixel_height)
	append_glyph_preloaded(batch, f, g, x_pos, y_pos, color, vp)
	return f32(g.advance) * f.scale
}

measure_spans_width :: proc(font: ^Font, spans: []Text_Span, default_scale: f32) -> f32 {
	total_width: f32 = 0.0
	for span in spans {
		current_pixel_height :=
			span.font_size if span.font_size > 0.0 else (font != nil ? font.pixel_height : 0.0)
		active_font := font
		if span.font_path != "" {
			if custom_font, ok := custom_fonts_get(span.font_path, current_pixel_height); ok {
				active_font = custom_font
			}
		}
		scale_val :=
			stbtt.ScaleForPixelHeight(&active_font.info, current_pixel_height) if active_font != nil else default_scale
		for r in span.text {
			if r == '\n' do continue
			char_w :=
				active_font != nil ? (f32(get_glyph(active_font, r, current_pixel_height).advance) * scale_val) : (8.0 * default_scale)
			total_width += char_w
		}
	}
	return total_width
}

draw_text_ttf :: proc(
	batch: ^Batch2D,
	spans: []Text_Span,
	font: ^Font,
	cursor_x, cursor_y: ^f32,
	start_x: f32,
	is_y_down: bool,
	vp: linalg.Matrix4f32,
	max_width: f32,
	multiline: bool,
	total_width: f32,
) {
	accumulated_width: f32 = 0.0
	rendered_ellipsis := false

	for span in spans {
		current_pixel_height := span.font_size if span.font_size > 0.0 else font.pixel_height
		active_font := font
		if span.font_path != "" {
			if custom_font, ok := custom_fonts_get(span.font_path, current_pixel_height); ok {
				active_font = custom_font
			}
		}

		scale_val := stbtt.ScaleForPixelHeight(&active_font.info, current_pixel_height)

		for r, index in span.text {
			if r == '\n' {
				cursor_x^ = start_x
				line_offset :=
					f32(active_font.ascent - active_font.descent + active_font.line_gap) *
					scale_val
				if is_y_down {
					cursor_y^ += line_offset
				} else {
					cursor_y^ -= line_offset
				}
				continue
			}

			char_w := f32(get_glyph(active_font, r, current_pixel_height).advance) * scale_val

			// 1. Single-line Ellipsis Truncation
			if max_width > 0.0 && !multiline && total_width > max_width {
				g_dot := get_glyph(active_font, '.', current_pixel_height)
				dot_w := f32(g_dot.advance) * scale_val
				ellipsis_w := dot_w * 3.0
				if accumulated_width + char_w > max_width - ellipsis_w {
					if !rendered_ellipsis {
						for _ in 0 ..< 3 {
							append_glyph_preloaded(
								batch,
								active_font,
								g_dot,
								cursor_x^,
								cursor_y^,
								span.color,
								vp,
								span.bold,
								span.italic,
							)
							cursor_x^ += dot_w
						}
						rendered_ellipsis = true
					}
					break
				}
			}

			// 2. Multiline Word Wrapping (Allocation-free lookahead)
			if max_width > 0.0 && multiline && r != ' ' && r != '\t' {
				word_w: f32 = 0.0
				sub_str := span.text[index:]
				for cr in sub_str {
					if cr == ' ' || cr == '\t' || cr == '\n' do break
					cg := get_glyph(active_font, cr, current_pixel_height)
					word_w += f32(cg.advance) * scale_val
				}
				if cursor_x^ + word_w > start_x + max_width && cursor_x^ > start_x {
					cursor_x^ = start_x
					line_offset :=
						f32(active_font.ascent - active_font.descent + active_font.line_gap) *
						scale_val
					if is_y_down {
						cursor_y^ += line_offset
					} else {
						cursor_y^ -= line_offset
					}
				}
			}

			g := get_glyph(active_font, r, current_pixel_height)
			advance := f32(g.advance) * scale_val
			if span.has_bg {
				y0, y1: f32
				if is_y_down {
					y0 = cursor_y^ - f32(active_font.ascent) * scale_val
					y1 = cursor_y^ - f32(active_font.descent) * scale_val
				} else {
					y0 = cursor_y^ + f32(active_font.descent) * scale_val
					y1 = cursor_y^ + f32(active_font.ascent) * scale_val
				}
				append_quad(batch, cursor_x^, y0, cursor_x^ + advance, y1, span.bg_color, vp)
			}
			append_glyph_preloaded(
				batch,
				active_font,
				g,
				cursor_x^,
				cursor_y^,
				span.color,
				vp,
				span.bold,
				span.italic,
			)
			if span.underline {
				thickness := max(f32(1.0), scale_val)
				if is_y_down {
					y_under := cursor_y^ - f32(active_font.descent) * scale_val * 0.3
					append_quad(
						batch,
						cursor_x^,
						y_under,
						cursor_x^ + advance,
						y_under + thickness,
						span.color,
						vp,
					)
				} else {
					y_under := cursor_y^ + f32(active_font.descent) * scale_val * 0.3
					append_quad(
						batch,
						cursor_x^,
						y_under - thickness,
						cursor_x^ + advance,
						y_under,
						span.color,
						vp,
					)
				}
			}
			if span.strikethrough {
				y_strike :=
					is_y_down ? (cursor_y^ - f32(active_font.ascent) * scale_val * 0.3) : (cursor_y^ + f32(active_font.ascent) * scale_val * 0.3)
				thickness := max(f32(1.0), scale_val)
				append_quad(
					batch,
					cursor_x^,
					y_strike - thickness / 2.0,
					cursor_x^ + advance,
					y_strike + thickness / 2.0,
					span.color,
					vp,
				)
			}
			cursor_x^ += advance
			accumulated_width += char_w
		}
	}
}

draw_text_fallback :: proc(
	batch: ^Batch2D,
	spans: []Text_Span,
	scale: f32,
	cursor_x, cursor_y: ^f32,
	start_x: f32,
	is_y_down: bool,
	vp: linalg.Matrix4f32,
	max_width: f32,
	multiline: bool,
	total_width: f32,
) {
	accumulated_width: f32 = 0.0
	rendered_ellipsis := false

	for span in spans {
		for r, index in span.text {
			ch := u8(r)
			if ch == '\n' {
				cursor_x^ = start_x
				if is_y_down {
					cursor_y^ += 10.0 * scale
				} else {
					cursor_y^ -= 10.0 * scale
				}
				continue
			}

			char_w := 8.0 * scale

			// 1. Single-line Ellipsis Truncation
			if max_width > 0.0 && !multiline && total_width > max_width {
				ellipsis_w := char_w * 3.0
				if accumulated_width + char_w > max_width - ellipsis_w {
					if !rendered_ellipsis {
						for _ in 0 ..< 3 {
							append_char(
								batch,
								'.',
								cursor_x^,
								cursor_y^,
								scale,
								span.color,
								vp,
								span.bold,
								span.italic,
							)
							cursor_x^ += char_w
						}
						rendered_ellipsis = true
					}
					break
				}
			}

			// 2. Multiline Word Wrapping (Allocation-free lookahead)
			if max_width > 0.0 && multiline && ch != ' ' && ch != '\t' {
				word_w: f32 = 0.0
				sub_str := span.text[index:]
				for cr in sub_str {
					if cr == ' ' || cr == '\t' || cr == '\n' do break
					word_w += char_w
				}
				if cursor_x^ + word_w > start_x + max_width && cursor_x^ > start_x {
					cursor_x^ = start_x
					if is_y_down {
						cursor_y^ += 10.0 * scale
					} else {
						cursor_y^ -= 10.0 * scale
					}
				}
			}

			if span.has_bg {
				append_quad(
					batch,
					cursor_x^,
					cursor_y^,
					cursor_x^ + 8.0 * scale,
					cursor_y^ + 8.0 * scale,
					span.bg_color,
					vp,
				)
			}
			append_char(
				batch,
				ch,
				cursor_x^,
				cursor_y^,
				scale,
				span.color,
				vp,
				span.bold,
				span.italic,
			)
			if span.underline {
				if is_y_down {
					append_quad(
						batch,
						cursor_x^,
						cursor_y^ + 8.0 * scale,
						cursor_x^ + 8.0 * scale,
						cursor_y^ + 8.0 * scale + scale,
						span.color,
						vp,
					)
				} else {
					append_quad(
						batch,
						cursor_x^,
						cursor_y^ - scale,
						cursor_x^ + 8.0 * scale,
						cursor_y^,
						span.color,
						vp,
					)
				}
			}
			if span.strikethrough {
				y_strike := is_y_down ? (cursor_y^ + 4.0 * scale) : (cursor_y^ + 3.0 * scale)
				append_quad(
					batch,
					cursor_x^,
					y_strike,
					cursor_x^ + 8.0 * scale,
					y_strike + scale,
					span.color,
					vp,
				)
			}
			cursor_x^ += char_w
			accumulated_width += char_w
		}
	}
}

draw_text :: proc(
	batch: ^Batch2D,
	text: string,
	x, y: f32,
	font: ^Font = nil,
	scale: f32 = 1.0,
	default_color: [4]f32 = {1, 1, 1, 1},
	vp: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY,
	max_width: f32 = 0.0,
	multiline: bool = false,
) {
	spans := parse_bbcode_spans(text, default_color, context.temp_allocator)
	is_y_down := text_is_y_down(vp)
	total_width := measure_spans_width(font, spans, scale)

	cursor_x := x
	cursor_y := y

	if font != nil {
		draw_text_ttf(
			batch,
			spans,
			font,
			&cursor_x,
			&cursor_y,
			x,
			is_y_down,
			vp,
			max_width,
			multiline,
			total_width,
		)
	} else {
		draw_text_fallback(
			batch,
			spans,
			scale,
			&cursor_x,
			&cursor_y,
			x,
			is_y_down,
			vp,
			max_width,
			multiline,
			total_width,
		)
	}
}

parse_color_to_rgb :: proc(name: string) -> [3]f32 {
	switch name {
	case "red":
		return {1.0, 0.0, 0.0}
	case "green":
		return {0.0, 1.0, 0.0}
	case "blue":
		return {0.0, 0.0, 1.0}
	case "yellow":
		return {1.0, 1.0, 0.0}
	case "magenta", "purple":
		return {1.0, 0.0, 1.0}
	case "cyan":
		return {0.0, 1.0, 1.0}
	case "white":
		return {1.0, 1.0, 1.0}
	case "black":
		return {0.0, 0.0, 0.0}
	case "gray", "grey":
		return {0.5, 0.5, 0.5}
	case "orange":
		return {1.0, 0.5, 0.0}
	}

	s := name
	if len(s) > 0 && s[0] == '#' do s = s[1:]

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
			r := f32((r1 << 4) | r2) / 255.0
			g := f32((g1 << 4) | g2) / 255.0
			b := f32((b1 << 4) | b2) / 255.0
			return {r, g, b}
		}
	} else if len(s) == 3 {
		r1, ok1 := hex_digit(s[0])
		g1, ok2 := hex_digit(s[1])
		b1, ok3 := hex_digit(s[2])
		if ok1 && ok2 && ok3 {
			r := f32(r1 * 17) / 255.0
			g := f32(g1 * 17) / 255.0
			b := f32(b1 * 17) / 255.0
			return {r, g, b}
		}
	}

	return {1.0, 1.0, 1.0}
}

parse_opacity :: proc(val: string) -> f32 {
	f, ok := strconv.parse_f64(val)
	if !ok do return 1.0
	if f > 1.0 do return f32(f / 255.0)
	return f32(f)
}

parse_bbcode_spans :: proc(
	text: string,
	default_color: [4]f32 = {1, 1, 1, 1},
	allocator := context.allocator,
) -> []Text_Span {
	bb_spans, err_msg, ok := bbcode.parse_spans(text, allocator)
	if !ok {
		delete(err_msg, allocator)
		s := Text_Span {
			text  = strings.clone(text, allocator),
			color = default_color,
		}
		res := make([]Text_Span, 1, allocator)
		res[0] = s
		return res
	}

	res := make([]Text_Span, len(bb_spans), allocator)
	for span, i in bb_spans {
		color := default_color
		if span.style.color_str != "" {
			rgb := parse_color_to_rgb(span.style.color_str)
			color = {rgb[0], rgb[1], rgb[2], span.style.opacity}
		} else {
			color.a = span.style.opacity
		}

		bg_color: [4]f32
		if span.style.bg_color_str != "" {
			rgb := parse_color_to_rgb(span.style.bg_color_str)
			bg_color = {rgb[0], rgb[1], rgb[2], span.style.bg_opacity}
		}

		res[i] = Text_Span {
			text          = span.text,
			color         = color,
			bg_color      = bg_color,
			has_bg        = span.style.has_bg,
			bold          = span.style.bold,
			italic        = span.style.italic,
			underline     = span.style.underline,
			strikethrough = span.style.strikethrough,
			font_size     = span.style.font_size,
			font_path     = span.style.font_path,
		}
	}

	delete(bb_spans, allocator)
	return res
}

font8x8_basic := [128][8]u8 {
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0000 (nul)
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0001
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0002
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0003
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0004
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0005
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0006
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0007
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0008
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0009
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000A
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000B
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000C
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000D
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000E
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+000F
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0010
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0011
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0012
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0013
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0014
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0015
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0016
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0017
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0018
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0019
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001A
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001B
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001C
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001D
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001E
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+001F
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0020 (space)
	{0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00}, // U+0021 (!)
	{0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0022 (")
	{0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00}, // U+0023 (#)
	{0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x0C, 0x00}, // U+0024 ($)
	{0x00, 0x63, 0x33, 0x18, 0x0C, 0x66, 0x63, 0x00}, // U+0025 (%)
	{0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00}, // U+0026 (&)
	{0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0027 (')
	{0x18, 0x0C, 0x06, 0x06, 0x06, 0x0C, 0x18, 0x00}, // U+0028 (()
	{0x06, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x06, 0x00}, // U+0029 ())
	{0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00}, // U+002A (*)
	{0x00, 0x0C, 0x0C, 0x3F, 0x0C, 0x0C, 0x00, 0x00}, // U+002B (+)
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x06}, // U+002C (,)
	{0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00}, // U+002D (-)
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00}, // U+002E (.)
	{0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00}, // U+002F (/)
	{0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00}, // U+0030 (0)
	{0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00}, // U+0031 (1)
	{0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00}, // U+0032 (2)
	{0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00}, // U+0033 (3)
	{0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00}, // U+0034 (4)
	{0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00}, // U+0035 (5)
	{0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00}, // U+0036 (6)
	{0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00}, // U+0037 (7)
	{0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00}, // U+0038 (8)
	{0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00}, // U+0039 (9)
	{0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x00}, // U+003A (:)
	{0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x06}, // U+003B (;)
	{0x18, 0x0C, 0x06, 0x03, 0x06, 0x0C, 0x18, 0x00}, // U+003C (<)
	{0x00, 0x00, 0x3F, 0x00, 0x00, 0x3F, 0x00, 0x00}, // U+003D (=)
	{0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00}, // U+003E (>)
	{0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00}, // U+003F (?)
	{0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00}, // U+0040 (@)
	{0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00}, // U+0041 (A)
	{0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00}, // U+0042 (B)
	{0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00}, // U+0043 (C)
	{0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00}, // U+0044 (D)
	{0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00}, // U+0045 (E)
	{0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00}, // U+0046 (F)
	{0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00}, // U+0047 (G)
	{0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00}, // U+0048 (H)
	{0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00}, // U+0049 (I)
	{0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00}, // U+004A (J)
	{0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00}, // U+004B (K)
	{0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00}, // U+004C (L)
	{0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00}, // U+004D (M)
	{0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00}, // U+004E (N)
	{0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00}, // U+004F (O)
	{0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00}, // U+0050 (P)
	{0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00}, // U+0051 (Q)
	{0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00}, // U+0052 (R)
	{0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00}, // U+0053 (S)
	{0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00}, // U+0054 (T)
	{0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00}, // U+0055 (U)
	{0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00}, // U+0056 (V)
	{0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00}, // U+0057 (W)
	{0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00}, // U+0058 (X)
	{0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00}, // U+0059 (Y)
	{0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00}, // U+005A (Z)
	{0x1E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1E, 0x00}, // U+005B ([)
	{0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00}, // U+005C (\)
	{0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0x00}, // U+005D (])
	{0x08, 0x1C, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00}, // U+005E (^)
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF}, // U+005F (_)
	{0x0C, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+0060 (`)
	{0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00}, // U+0061 (a)
	{0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00}, // U+0062 (b)
	{0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00}, // U+0063 (c)
	{0x38, 0x30, 0x30, 0x3e, 0x33, 0x33, 0x6E, 0x00}, // U+0064 (d)
	{0x00, 0x00, 0x1E, 0x33, 0x3f, 0x03, 0x1E, 0x00}, // U+0065 (e)
	{0x1C, 0x36, 0x06, 0x0f, 0x06, 0x06, 0x0F, 0x00}, // U+0066 (f)
	{0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F}, // U+0067 (g)
	{0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00}, // U+0068 (h)
	{0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00}, // U+0069 (i)
	{0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E}, // U+006A (j)
	{0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00}, // U+006B (k)
	{0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00}, // U+006C (l)
	{0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00}, // U+006D (m)
	{0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00}, // U+006E (n)
	{0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00}, // U+006F (o)
	{0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F}, // U+0070 (p)
	{0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78}, // U+0071 (q)
	{0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00}, // U+0072 (r)
	{0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00}, // U+0073 (s)
	{0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00}, // U+0074 (t)
	{0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00}, // U+0075 (u)
	{0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00}, // U+0076 (v)
	{0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00}, // U+0077 (w)
	{0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00}, // U+0078 (x)
	{0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F}, // U+0079 (y)
	{0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00}, // U+007A (z)
	{0x38, 0x0C, 0x0C, 0x07, 0x0C, 0x0C, 0x38, 0x00}, // U+007B ({)
	{0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00}, // U+007C (|)
	{0x07, 0x0C, 0x0C, 0x38, 0x0C, 0x0C, 0x07, 0x00}, // U+007D (})
	{0x6E, 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+007E (~)
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // U+007F
}

append_quad :: proc(batch: ^Batch2D, x0, y0, x1, y1: f32, color: [4]f32, vp: linalg.Matrix4f32) {
	local_x0 := x0
	local_y0 := y0
	local_x1 := x1
	local_y1 := y1
	if !batch2d_clip_quad(batch, &local_x0, &local_y0, &local_x1, &local_y1) do return

	project_point :: proc(vp: linalg.Matrix4f32, p: [2]f32) -> [2]f32 {
		p4 := [4]f32{p.x, p.y, 0.0, 1.0}
		res4 := vp * p4
		if res4.w != 0.0 do return res4.xy / res4.w
		return res4.xy
	}

	base_idx := u32(len(batch.vertices))
	append(
		&batch.vertices,
		Vertex2D{position = project_point(vp, {local_x0, local_y0}), color = color},
		Vertex2D{position = project_point(vp, {local_x1, local_y0}), color = color},
		Vertex2D{position = project_point(vp, {local_x1, local_y1}), color = color},
		Vertex2D{position = project_point(vp, {local_x0, local_y1}), color = color},
	)
	append(
		&batch.indices,
		base_idx + 0,
		base_idx + 1,
		base_idx + 2,
		base_idx + 0,
		base_idx + 2,
		base_idx + 3,
	)
}

append_char :: proc(
	batch: ^Batch2D,
	ch: u8,
	x_pos, y_pos: f32,
	scale: f32,
	color: [4]f32,
	vp: linalg.Matrix4f32,
	bold := false,
	italic := false,
) {
	c_idx := int(ch)
	if c_idx >= 128 do return
	bitmap := font8x8_basic[c_idx]

	is_y_down := vp[1][1] < 0.0

	for y in 0 ..< 8 {
		row_byte := bitmap[y]
		for x in 0 ..< 8 {
			bit := (row_byte >> uint(x)) & 1
			if bit == 1 {
				px := x_pos + f32(x) * scale
				py := is_y_down ? (y_pos + f32(y) * scale) : (y_pos + f32(7 - y) * scale)

				if italic {
					skew := is_y_down ? (f32(y) * scale * 0.2) : (f32(7 - y) * scale * 0.2)
					px += skew
				}

				append_quad(batch, px, py, px + scale, py + scale, color, vp)
				if bold {
					append_quad(batch, px + scale, py, px + scale * 2.0, py + scale, color, vp)
				}
			}
		}
	}
}


Custom_Font_Cache_Entry :: struct {
	font:   Font,
	exists: bool,
}

custom_fonts: map[string]Custom_Font_Cache_Entry

custom_fonts_get :: proc(path: string, pixel_height: f32) -> (^Font, bool) {
	if custom_fonts == nil {
		custom_fonts = make(map[string]Custom_Font_Cache_Entry)
	}

	if entry, ok := &custom_fonts[path]; ok {
		if !entry.exists do return nil, false
		return &entry.font, true
	}

	font: Font
	if !font_init(&font, path, pixel_height) {
		cloned_path := strings.clone(path)
		custom_fonts[cloned_path] = Custom_Font_Cache_Entry {
			exists = false,
		}
		return nil, false
	}

	cloned_path := strings.clone(path)
	custom_fonts[cloned_path] = Custom_Font_Cache_Entry {
		font   = font,
		exists = true,
	}
	entry, _ := &custom_fonts[cloned_path]
	return &entry.font, true
}

custom_fonts_destroy :: proc() {
	if custom_fonts == nil do return
	for path, &entry in custom_fonts {
		if entry.exists {
			font_destroy(&entry.font)
		}
		delete(path)
	}
	delete(custom_fonts)
	custom_fonts = nil
}
