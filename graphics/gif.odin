package graphics

import log "../logging"
import "core:os"
import stbi "vendor:stb/image"

Bit_Writer :: struct {
	data:         [dynamic]byte,
	current_byte: byte,
	bit_offset:   int,
	block:        [256]byte,
	block_len:    int,
}

@(private)
bit_writer_write :: proc(w: ^Bit_Writer, value: int, bits: int) {
	val := value
	for b in 0 ..< bits {
		bit := byte((val >> u32(b)) & 1)
		w.current_byte |= (bit << u32(w.bit_offset))
		w.bit_offset += 1
		if w.bit_offset == 8 {
			w.block[w.block_len] = w.current_byte
			w.block_len += 1
			if w.block_len == 255 {
				append(&w.data, 255)
				append(&w.data, ..w.block[:255])
				w.block_len = 0
			}
			w.current_byte = 0
			w.bit_offset = 0
		}
	}
}

@(private)
bit_writer_flush :: proc(w: ^Bit_Writer) {
	if w.bit_offset > 0 {
		w.block[w.block_len] = w.current_byte
		w.block_len += 1
	}
	if w.block_len > 0 {
		append(&w.data, byte(w.block_len))
		append(&w.data, ..w.block[:w.block_len])
	}
	append(&w.data, 0)
}

@(private)
quantize_frame :: proc(
	rgba: []byte,
	width, height: int,
) -> (
	indexed_pixels: []byte,
	palette: [256][3]byte,
) {
	indexed_pixels = make([]byte, width * height)
	palette_size := 0

	// Hash table to cache RGB color keys to palette indices
	// Size is 2048 to keep load factor low and lookup fast
	color_hash: [2048]u32
	color_indices: [2048]byte
	hash_table_size := 0

	for i in 0 ..< (width * height) {
		r := rgba[i * 4 + 0]
		g := rgba[i * 4 + 1]
		b := rgba[i * 4 + 2]
		color_key := (u32(r) << 16) | (u32(g) << 8) | u32(b)
		stored_val := color_key + 1

		// Probe hash table
		h := (color_key * 0x45d9f3b) & 2047
		found := -1
		for color_hash[h] != 0 {
			if color_hash[h] == stored_val {
				found = int(color_indices[h])
				break
			}
			h = (h + 1) & 2047
		}

		if found != -1 {
			indexed_pixels[i] = byte(found)
		} else {
			if palette_size < 256 {
				palette[palette_size] = {r, g, b}
				indexed_pixels[i] = byte(palette_size)

				// Cache index
				if hash_table_size < 1500 {
					color_hash[h] = stored_val
					color_indices[h] = byte(palette_size)
					hash_table_size += 1
				}
				palette_size += 1
			} else {
				// Palette is full, find closest match via Euclidean distance
				min_dist := int(100000000)
				best_idx := 0
				for p in 0 ..< 256 {
					pr := int(palette[p][0])
					pg := int(palette[p][1])
					pb := int(palette[p][2])

					dist :=
						(int(r) - pr) * (int(r) - pr) +
						(int(g) - pg) * (int(g) - pg) +
						(int(b) - pb) * (int(b) - pb)

					if dist < min_dist {
						min_dist = dist
						best_idx = p
					}
				}
				indexed_pixels[i] = byte(best_idx)

				// Cache closest index to avoid repeating Euclidean search for this color
				if hash_table_size < 1500 {
					color_hash[h] = stored_val
					color_indices[h] = byte(best_idx)
					hash_table_size += 1
				}
			}
		}
	}

	return indexed_pixels, palette
}

@(private)
lzw_compress :: proc(pixels: []byte, w: ^Bit_Writer) {
	dict: [8192]u32
	codes: [8192]i16

	clear_code := i16(256)
	eoi_code := i16(257)

	bit_writer_write(w, int(clear_code), 9)

	code_size := 9
	next_code := i16(258)

	prefix := i16(pixels[0])

	for i in 1 ..< len(pixels) {
		c := pixels[i]
		key := (u32(prefix) << 8) | u32(c)
		code := dict_lookup(&dict, &codes, key)
		if code != -1 {
			prefix = code
		} else {
			bit_writer_write(w, int(prefix), code_size)
			if next_code < 4096 {
				dict_insert(&dict, &codes, key, next_code)
				next_code += 1
				if next_code > (1 << u32(code_size)) && code_size < 12 {
					code_size += 1
				}
			} else {
				bit_writer_write(w, int(clear_code), code_size)
				dict = {}
				codes = {}
				code_size = 9
				next_code = 258
			}
			prefix = i16(c)
		}
	}
	bit_writer_write(w, int(prefix), code_size)
	bit_writer_write(w, int(eoi_code), code_size)
}

@(private)
hash :: proc(key: u32) -> u32 {
	h := key * 0x45d9f3b
	h = ((h >> 16) ~ h) * 0x45d9f3b
	h = (h >> 16) ~ h
	return h & 8191
}

@(private)
dict_insert :: proc(dict: ^[8192]u32, codes: ^[8192]i16, key: u32, code: i16) {
	h := hash(key)
	stored_key := key + 1
	for dict[h] != 0 {
		h = (h + 1) & 8191
	}
	dict[h] = stored_key
	codes[h] = code
}

@(private)
dict_lookup :: proc(dict: ^[8192]u32, codes: ^[8192]i16, key: u32) -> i16 {
	h := hash(key)
	stored_key := key + 1
	for dict[h] != 0 {
		if dict[h] == stored_key do return codes[h]
		h = (h + 1) & 8191
	}
	return -1
}

write_gif :: proc(path: string, width, height: int, frames: [][]byte) -> bool {
	log.debug(
		"write_gif start: path=%s, width=%d, height=%d, frames=%d",
		path,
		width,
		height,
		len(frames),
	)
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		log.error("os.open failed with error: %v", err)
		return false
	}
	defer os.close(f)

	os.write(f, []byte{'G', 'I', 'F', '8', '9', 'a'})

	w_bytes := [2]byte{byte(width & 0xFF), byte((width >> 8) & 0xFF)}
	h_bytes := [2]byte{byte(height & 0xFF), byte((height >> 8) & 0xFF)}

	packed_fields := byte(0x70)

	os.write(f, w_bytes[:])
	os.write(f, h_bytes[:])
	os.write(f, []byte{packed_fields, 0, 0})

	loop_block := []byte {
		0x21,
		0xFF,
		0x0B,
		'N',
		'E',
		'T',
		'S',
		'C',
		'A',
		'P',
		'E',
		'2',
		'.',
		'0',
		0x03,
		0x01,
		0x00,
		0x00,
		0x00,
	}
	os.write(f, loop_block)

	for frame_data in frames {
		indexed, palette := quantize_frame(frame_data, width, height)
		defer delete(indexed)

		delay := u16(2)
		delay_lo := byte(delay & 0xFF)
		delay_hi := byte((delay >> 8) & 0xFF)

		gce := []byte{0x21, 0xF9, 0x04, 0x04, delay_lo, delay_hi, 0, 0}
		os.write(f, gce)

		id_packed := byte(0x87)

		id := []byte{0x2C, 0, 0, 0, 0, w_bytes[0], w_bytes[1], h_bytes[0], h_bytes[1], id_packed}
		os.write(f, id)

		lct_buf := make([]byte, 256 * 3)
		defer delete(lct_buf)
		for p in 0 ..< 256 {
			lct_buf[p * 3 + 0] = palette[p][0]
			lct_buf[p * 3 + 1] = palette[p][1]
			lct_buf[p * 3 + 2] = palette[p][2]
		}
		os.write(f, lct_buf)

		os.write(f, []byte{8})

		w: Bit_Writer
		w.data = make([dynamic]byte, 0, 1024)
		defer delete(w.data)

		lzw_compress(indexed, &w)
		bit_writer_flush(&w)

		os.write(f, w.data[:])
	}

	os.write(f, []byte{0x3B})
	return true
}
