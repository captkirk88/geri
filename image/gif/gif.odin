package gif

import log "../../logging"
import "core:os"
import stbi "vendor:stb/image"

// LZW compressor state for packing variable-width codes (9-12 bits) into a byte stream.
@(private)
Gif_Lzw :: struct {
	data:    [dynamic]byte, // Output compressed GIF data stream
	numBits: int, // Current LZW code bit-width (starts at 9, caps at 12)
	buf:     [256]byte, // Buffer to assemble a single GIF sub-block (max 255 bytes)
	idx:     int, // Current byte count in the assembly buffer (s.buf)
	outBits: int, // Bit reservoir holding accumulated bits to output
	curBits: int, // Number of active bits currently sitting in s.outBits
}

// Writes an LZW code of variable width (s.numBits) into the bit reservoir,
// flushing full bytes into the sub-block buffer.
@(private)
gif_lzw_write :: proc(s: ^Gif_Lzw, code: int) {
	// Shift code into position and merge into the bit reservoir
	s.outBits |= code << u32(s.curBits)
	s.curBits += s.numBits

	// While there is at least one full byte available in the reservoir
	for s.curBits >= 8 {
		s.buf[s.idx] = byte(s.outBits & 0xFF) // Extract lowest 8 bits (0xFF = 255)
		s.idx += 1
		s.outBits >>= 8 // Discard written byte
		s.curBits -= 8 // Decrement bit counter

		// GIF sub-blocks are limited to a maximum payload size of 255 bytes.
		// When full, we write the block size byte (255) followed by the 255 payload bytes.
		if s.idx >= 255 {
			append(&s.data, 255)
			append(&s.data, ..s.buf[:255])
			s.idx = 0
		}
	}
}


// NeuQuant Neural-Network Color Quantization algorithm (originally by Anthony Dekker).
// Organizes a self-organizing map to find the optimal 256 representative colors for the image.
@(private)
quantize_neuquant :: proc(rgba: []byte, palette: ^[256][3]byte, numColors: int) {
	// NeuQuant algorithm constants
	intbiasshift :: 16 // bias for fractions
	intbias :: 1 << intbiasshift
	gammashift :: 10 // gamma = 1024
	betashift :: 10
	beta :: intbias >> betashift // beta = 1/1024
	betagamma :: intbias << (gammashift - betashift)

	// Range constants for decreasing learning radius
	radiusbiasshift :: 6 // at 32.0 biased by 6 bits
	radiusbias :: 1 << radiusbiasshift
	radiusdec :: 30 // factor of 1/30 each cycle

	// Learning rate constants
	alphabiasshift :: 10 // alpha starts at 1.0
	initalpha :: 1 << alphabiasshift

	// Radpower constants
	radbiasshift :: 8
	radbias :: 1 << radbiasshift
	alpharadbshift :: alphabiasshift + radbiasshift
	alpharadbias :: 1 << alpharadbshift

	network: [256][3]int
	bias: [256]int
	freq: [256]int

	// Initialize the network with evenly spaced colors
	for i in 0 ..< numColors {
		network[i][0] = (i << 12) / numColors
		network[i][1] = (i << 12) / numColors
		network[i][2] = (i << 12) / numColors
		freq[i] = intbias / numColors
	}

	// Prime numbers for sampling steps
	step := 4
	primes := [4]int{499, 491, 487, 503}
	for i in 0 ..< 4 {
		if len(rgba) > primes[i] * 4 && (len(rgba) % primes[i] != 0) {
			step = primes[i] * 4
		}
	}

	sample := 10 // Sample 1 in every 10 pixels for speed (retains high representative quality)
	alphadec := 30 + ((sample - 1) / 3)
	samplepixels := len(rgba) / (4 * sample)
	delta := samplepixels / 100
	if delta == 0 do delta = 1
	alpha := initalpha

	radius := (numColors >> 3) * radiusbias
	rad := radius >> radiusbiasshift
	if rad <= 1 do rad = 0
	radSq := rad * rad

	radpower: [32]int
	for i in 0 ..< rad {
		radpower[i] = alpha * (((radSq - i * i) * radbias) / radSq)
	}

	pix := 0
	i := 0
	for i < samplepixels {
		r := int(rgba[pix + 0]) << 4
		g := int(rgba[pix + 1]) << 4
		b := int(rgba[pix + 2]) << 4

		bestd := int(0x7FFFFFFF)
		bestbiasd := int(0x7FFFFFFF)
		bestpos := -1
		j := -1

		// Find the neuron closest to the target pixel color
		for k in 0 ..< numColors {
			dist := abs(network[k][0] - r) + abs(network[k][1] - g) + abs(network[k][2] - b)
			if dist < bestd {
				bestd = dist
				bestpos = k
			}
			biasdist := dist - (bias[k] >> (intbiasshift - 4))
			if biasdist < bestbiasd {
				bestbiasd = biasdist
				j = k
			}
			betafreq := freq[k] >> betashift
			freq[k] -= betafreq
			bias[k] += betafreq << gammashift
		}
		freq[bestpos] += beta
		bias[bestpos] -= betagamma

		// Shift the winning neuron towards the target color
		network[j][0] -= ((network[j][0] - r) * alpha) / initalpha
		network[j][1] -= ((network[j][1] - g) * alpha) / initalpha
		network[j][2] -= ((network[j][2] - b) * alpha) / initalpha

		// Also shift neighboring neurons based on the current learning radius
		if rad != 0 {
			lo := j - rad
			if lo < -1 do lo = -1
			hi := j + rad
			if hi > numColors do hi = numColors

			m := 1
			for jj := j + 1; jj < hi; jj += 1 {
				a := radpower[m]
				m += 1
				network[jj][0] -= ((network[jj][0] - r) * a) / alpharadbias
				network[jj][1] -= ((network[jj][1] - g) * a) / alpharadbias
				network[jj][2] -= ((network[jj][2] - b) * a) / alpharadbias
			}
			m = 1
			for k := j - 1; k > lo; k -= 1 {
				a := radpower[m]
				m += 1
				network[k][0] -= ((network[k][0] - r) * a) / alpharadbias
				network[k][1] -= ((network[k][1] - g) * a) / alpharadbias
				network[k][2] -= ((network[k][2] - b) * a) / alpharadbias
			}
		}

		pix += step
		if pix >= len(rgba) do pix -= len(rgba)

		i += 1
		// Update the learning parameters over iterations (cooling phase)
		if i % delta == 0 {
			alpha -= alpha / alphadec
			radius -= radius / radiusdec
			rad = radius >> radiusbiasshift
			if rad <= 1 do rad = 0
			radSq = rad * rad
			for j_idx in 0 ..< rad {
				radpower[j_idx] = alpha * ((radSq - j_idx * j_idx) * radbias / radSq)
			}
		}
	}

	// Write final un-biased neuron values to the palette structure
	for k in 0 ..< numColors {
		palette[k][0] = byte(network[k][0] >> 4)
		palette[k][1] = byte(network[k][1] >> 4)
		palette[k][2] = byte(network[k][2] >> 4)
	}
}

// Maps 32-bit RGBA pixels to 8-bit color palette indices using Floyd-Steinberg error diffusion dithering.
@(private)
dither_and_map_frame :: proc(rgba: []byte, width, height: int, palette: [256][3]byte) -> []byte {
	size := width * height
	indexed := make([]byte, size)

	// Create a copy of the pixel buffer to accumulate dithered color adjustments locally
	dithered := make([]byte, size * 4)
	copy(dithered, rgba)
	defer delete(dithered)

	// Helper to clamp integers within 0-255 range safely
	clamp_byte :: proc(val: int) -> byte {
		return byte(val < 0 ? 0 : (val > 255 ? 255 : val))
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			k := (y * width + x) * 4
			r := int(dithered[k + 0])
			g := int(dithered[k + 1])
			b := int(dithered[k + 2])

			// Locate the closest matching color in the 256-color palette (minimum Euclidean distance)
			best_dist := int(0x7FFFFFFF)
			best_idx := 0
			for p in 0 ..< 256 {
				pr := int(palette[p][0])
				pg := int(palette[p][1])
				pb := int(palette[p][2])

				dist := (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb)
				if dist < best_dist {
					best_dist = dist
					best_idx = p
				}
			}

			indexed[y * width + x] = byte(best_idx)

			// Calculate the difference between the target pixel color and the actual palette color
			err_r := r - int(palette[best_idx][0])
			err_g := g - int(palette[best_idx][1])
			err_b := b - int(palette[best_idx][2])

			// Floyd-Steinberg error diffusion pattern:
			//        [[x]]   7/16
			// 3/16   5/16  1/16

			// Right pixel (x + 1, y)
			if x + 1 < width {
				n_k := (y * width + (x + 1)) * 4
				dithered[n_k + 0] = clamp_byte(int(dithered[n_k + 0]) + (err_r * 7 / 16))
				dithered[n_k + 1] = clamp_byte(int(dithered[n_k + 1]) + (err_g * 7 / 16))
				dithered[n_k + 2] = clamp_byte(int(dithered[n_k + 2]) + (err_b * 7 / 16))
			}

			if y + 1 < height {
				// Bottom-left pixel (x - 1, y + 1)
				if x - 1 >= 0 {
					n_k := ((y + 1) * width + (x - 1)) * 4
					dithered[n_k + 0] = clamp_byte(int(dithered[n_k + 0]) + (err_r * 3 / 16))
					dithered[n_k + 1] = clamp_byte(int(dithered[n_k + 1]) + (err_g * 3 / 16))
					dithered[n_k + 2] = clamp_byte(int(dithered[n_k + 2]) + (err_b * 3 / 16))
				}
				// Bottom pixel (x, y + 1)
				{
					n_k := ((y + 1) * width + x) * 4
					dithered[n_k + 0] = clamp_byte(int(dithered[n_k + 0]) + (err_r * 5 / 16))
					dithered[n_k + 1] = clamp_byte(int(dithered[n_k + 1]) + (err_g * 5 / 16))
					dithered[n_k + 2] = clamp_byte(int(dithered[n_k + 2]) + (err_b * 5 / 16))
				}
				// Bottom-right pixel (x + 1, y + 1)
				if x + 1 < width {
					n_k := ((y + 1) * width + (x + 1)) * 4
					dithered[n_k + 0] = clamp_byte(int(dithered[n_k + 0]) + (err_r * 1 / 16))
					dithered[n_k + 1] = clamp_byte(int(dithered[n_k + 1]) + (err_g * 1 / 16))
					dithered[n_k + 2] = clamp_byte(int(dithered[n_k + 2]) + (err_b * 1 / 16))
				}
			}
		}
	}

	return indexed
}

// Encodes a stream of indexed pixels using the standard LZW algorithm for GIFs.
@(private)
gif_lzw_encode :: proc(pixels: []byte, state: ^Gif_Lzw) {
	// maxcode tracks when to increase the bit-width of LZW codes.
	// Starts at 511 (highest code fit in 9 bits).
	maxcode := 511

	// LZW dictionary lookup using a closed hash table (linear probing)
	hashSize :: 5003
	codetab: [hashSize]i16
	hashTbl: [hashSize]i32
	for i in 0 ..< hashSize {
		hashTbl[i] = -1 // -1 / 0xFFFFFFFF means the hash table slot is empty
	}

	// Output the LZW Clear Code (0x100 = 256) to initialize the decoder's string table.
	gif_lzw_write(state, 0x100)

	// LZW code space:
	// - 0 to 255: Literal color indices from the palette
	// - 256 (0x100): Clear Code (resets string table)
	// - 257 (0x101): End of Information (EOI) Code
	// - 258 (0x102): First available code for custom sequences
	free_ent := 0x102
	if len(pixels) == 0 do return
	ent := int(pixels[0])

	i := 1
	look_loop: for i < len(pixels) {
		c := int(pixels[i])
		i += 1

		// Encode key: format key as a 20-bit integer: (character << 12) + prefix_code.
		fcode := (c << 12) + ent
		key := (c << 4) ~ ent // Hash function: XOR of shifted character and prefix code

		// Probe the hash table using linear probing
		for hashTbl[key] >= 0 {
			if hashTbl[key] == i32(fcode) {
				// Found sequence in dictionary: update prefix code (ent) and continue
				ent = int(codetab[key])
				continue look_loop
			}
			key += 1
			if key >= hashSize do key -= hashSize
		}

		// Mismatch: output the prefix code (ent)
		gif_lzw_write(state, ent)
		ent = c // Start a new sequence with the mismatched character

		// If there is room in the LZW dictionary (max code limit is 12-bit / 4096 entries)
		if free_ent < 4096 {
			// If we have assigned the maximum code represented by the current bit-width,
			// increment the code size (s.numBits) so the decoder correctly decodes larger code values.
			if free_ent > maxcode {
				state.numBits += 1
				if state.numBits == 12 {
					maxcode = 4096 // Prevents further bit width increases (caps at 12 bits)
				} else {
					maxcode = (1 << u32(state.numBits)) - 1
				}
			}
			// Insert the new sequence into the hash table
			codetab[key] = i16(free_ent)
			free_ent += 1
			hashTbl[key] = i32(fcode)
		} else {
			// Dictionary is full: clear hash table, reset code size to 9 bits, and output a Clear Code (0x100)
			for k in 0 ..< hashSize {
				hashTbl[k] = -1
			}
			free_ent = 0x102
			gif_lzw_write(state, 0x100)
			state.numBits = 9
			maxcode = 511
		}
	}

	// Output the remaining prefix, EOI code (0x101 = 257), and final zero-padding to flush the reservoir.
	gif_lzw_write(state, ent)
	gif_lzw_write(state, 0x101)
	gif_lzw_write(state, 0)

	// Flush any partially filled bytes remaining in the assembly buffer to the data array
	if state.idx > 0 {
		append(&state.data, byte(state.idx))
		append(&state.data, ..state.buf[:state.idx])
	}
	append(&state.data, 0) // Write the sub-block terminator (0 size block) to mark end of LZW stream
}

// Gif_Writer holds the open file handle and fixed dimensions for incremental frame writing.
Gif_Writer :: struct {
	file:    ^os.File,
	width:   int,
	height:  int,
	w_bytes: [2]byte,
	h_bytes: [2]byte,
}

// open creates and initialises a GIF file for streaming, writing the GIF header and the
// Netscape 2.0 loop block. Call write_frame for each frame, then close to finalise.
open :: proc(path: string, width, height: int) -> (writer: Gif_Writer, ok: bool) {
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		log.error("failed: %v", err)
		return {}, false
	}

	writer.file = f
	writer.width = width
	writer.height = height
	writer.w_bytes = [2]byte{byte(width & 0xFF), byte((width >> 8) & 0xFF)}
	writer.h_bytes = [2]byte{byte(height & 0xFF), byte((height >> 8) & 0xFF)}

	// 1. Write the GIF Header ("GIF89a")
	os.write(f, []byte{'G', 'I', 'F', '8', '9', 'a'})

	// Logical Screen Descriptor:
	// packed_fields 0x70 = no GCT, 8-bit color resolution, unsorted, GCT size 0.
	os.write(f, writer.w_bytes[:])
	os.write(f, writer.h_bytes[:])
	os.write(f, []byte{0x70, 0, 0})

	// 2. Netscape 2.0 Application Extension (loop forever)
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

	return writer, true
}

// write_frame encodes and appends a single RGBA frame to an open Gif_Writer.
write_frame :: proc(w: ^Gif_Writer, rgba: []byte) {
	palette: [256][3]byte
	quantize_neuquant(rgba, &palette, 256)
	indexed := dither_and_map_frame(rgba, w.width, w.height, palette)
	defer delete(indexed)

	// Delay: 2 centiseconds = 50 fps
	delay := u16(2)
	delay_lo := byte(delay & 0xFF)
	delay_hi := byte((delay >> 8) & 0xFF)

	// 3. Graphic Control Extension
	gce := []byte {
		0x21, // Extension Introducer
		0xF9, // Graphic Control Label
		0x04, // Block Size: 4 bytes
		0x04, // Packed Fields: disposal = do-not-dispose, no transparency
		delay_lo,
		delay_hi,
		0, // Transparent Color Index (unused)
		0, // Block Terminator
	}
	os.write(w.file, gce)

	// 4. Image Descriptor (0x87 = local color table present, 256 colors)
	id := []byte {
		0x2C, // Image Separator
		0,
		0, // Left
		0,
		0, // Top
		w.w_bytes[0],
		w.w_bytes[1], // Width
		w.h_bytes[0],
		w.h_bytes[1], // Height
		0x87, // Packed: LCT flag set, LCT size = 7 (2^8 = 256 colors)
	}
	os.write(w.file, id)

	// 5. Local Color Table
	lct_buf := make([]byte, 256 * 3)
	defer delete(lct_buf)
	for p in 0 ..< 256 {
		lct_buf[p * 3 + 0] = palette[p][0]
		lct_buf[p * 3 + 1] = palette[p][1]
		lct_buf[p * 3 + 2] = palette[p][2]
	}
	os.write(w.file, lct_buf)

	// 6. LZW Minimum Code Size + compressed image data
	os.write(w.file, []byte{8})
	lzw: Gif_Lzw
	lzw.data = make([dynamic]byte, 0, 1024)
	defer delete(lzw.data)
	lzw.numBits = 9
	gif_lzw_encode(indexed, &lzw)
	os.write(w.file, lzw.data[:])
}

// close writes the GIF trailer and closes the file.
close :: proc(w: ^Gif_Writer) {
	if w.file != nil {
		os.write(w.file, []byte{0x3B}) // GIF Trailer
		os.close(w.file)
		w.file = nil
	}
}

// write encodes all frames to a GIF file in one call. Convenience wrapper around open/write_frame/close.
write :: proc(path: string, width, height: int, frames: [][]byte) -> bool {
	writer, ok := open(path, width, height)
	if !ok do return false
	for frame in frames {
		write_frame(&writer, frame)
	}
	close(&writer)
	return true
}
