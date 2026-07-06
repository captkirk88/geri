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

// TODO parallize writing each frame
// Writes a series of RGBA frames to a GIF file at the specified path.
write :: proc(path: string, width, height: int, frames: [][]byte) -> bool {
	log.debug(
		"write_gif start: path=%s, width=%d, height=%d, frames=%d",
		path,
		width,
		height,
		len(frames),
	)
	defer log.debug("write_gif end")
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		log.error("os.open failed with error: %v", err)
		return false
	}
	// Close file descriptor upon function exit
	defer os.close(f)

	// 1. Write the GIF Header
	// "GIF89a" specifies version 89a, which supports animation and Graphic Control Extensions.
	os.write(f, []byte{'G', 'I', 'F', '8', '9', 'a'})

	// Split 16-bit width and height dimensions into little-endian byte arrays (2 bytes each).
	w_bytes := [2]byte{byte(width & 0xFF), byte((width >> 8) & 0xFF)}
	h_bytes := [2]byte{byte(height & 0xFF), byte((height >> 8) & 0xFF)}

	// Logical Screen Descriptor packed fields byte (0x70 = binary 01110000):
	// - Bit 7 = 0: No Global Color Table (we use Local Color Tables per frame to support unique color sets).
	// - Bits 6-4 = 111 (7): 8 bits of color resolution.
	// - Bit 3 = 0: Sorted palette flag is disabled.
	// - Bits 2-0 = 000 (0): Size of Global Color Table (0 since GCT flag is 0).
	packed_fields := byte(0x70)

	os.write(f, w_bytes[:])
	os.write(f, h_bytes[:])
	// Logical Screen Descriptor packed fields, followed by:
	// - Background Color Index (0)
	// - Pixel Aspect Ratio (0, which defaults to 1:1 square pixels)
	os.write(f, []byte{packed_fields, 0, 0})

	// 2. Write the Application Extension Block (Netscape 2.0 Loop Extension)
	// This instructs viewers/browsers to loop the animation.
	loop_block := []byte {
		0x21, // Extension Introducer (marks the start of an extension block)
		0xFF, // Application Extension Label
		0x0B, // Block Size: 11 bytes (length of application identifier string)
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
		'0', // Application Identifier
		0x03, // Sub-block Size: 3 bytes
		0x01, // Sub-block ID: 1 (indicates that loop count data follows)
		0x00,
		0x00, // Loop count: 0 (unsigned 16-bit little-endian value, 0 means repeat forever)
		0x00, // Block Terminator (marks the end of the loop block)
	}
	os.write(f, loop_block)

	// Write each frame to the GIF
	for frame_data in frames {
		palette: [256][3]byte
		quantize_neuquant(frame_data, &palette, 256)
		indexed := dither_and_map_frame(frame_data, width, height, palette)
		defer delete(indexed)

		// Delay time between frames in centiseconds (1/100 of a second).
		// A delay of 2 centiseconds translates to 50 frames per second.
		delay := u16(2)
		delay_lo := byte(delay & 0xFF)
		delay_hi := byte((delay >> 8) & 0xFF)

		// 3. Write Graphic Control Extension (GCE)
		// Controls transparency and frame rendering/disposal settings.
		gce := []byte {
			0x21, // Extension Introducer
			0xF9, // Graphic Control Label
			0x04, // Block Size: 4 bytes
			0x04, // Packed Fields (0x04 = binary 00000100):
			// - Bits 7-5: Reserved (000)
			// - Bits 4-2: Disposal Method (001 = 1 = "Do not dispose" / overlay on top of last frame)
			// - Bit 1: User Input Flag (0 = disabled)
			// - Bit 0: Transparent Color Flag (0 = disabled)
			delay_lo, // Delay time low byte
			delay_hi, // Delay time high byte
			0, // Transparent Color Index (0 since transparency flag is disabled)
			0, // Block Terminator (0)
		}
		os.write(f, gce)

		// Image Descriptor Packed Fields byte (0x87 = binary 10000111):
		// - Bit 7 = 1: Local Color Table Flag (Local palette is present for this frame).
		// - Bit 6 = 0: Interlace Flag (0 = sequential layout, 1 = interlaced).
		// - Bit 5 = 0: Sorted palette flag is disabled.
		// - Bits 4-3 = 00: Reserved bits.
		// - Bits 2-0 = 111 (7): Size of Local Color Table (7 represents 2^(7+1) = 256 colors).
		id_packed := byte(0x87)

		// 4. Write Image Descriptor Block
		// Specifies the frame boundaries and position on the logical screen.
		id := []byte {
			0x2C, // Image Separator (always ',')
			0,
			0, // Image Left position (0)
			0,
			0, // Image Top position (0)
			w_bytes[0], // Frame Width low byte
			w_bytes[1], // Frame Width high byte
			h_bytes[0], // Frame Height low byte
			h_bytes[1], // Frame Height high byte
			id_packed, // Packed layout and color table options
		}
		os.write(f, id)

		// 5. Write the Local Color Table (Palette)
		// Formatted as 256 consecutive RGB triplets (768 bytes total).
		lct_buf := make([]byte, 256 * 3)
		defer delete(lct_buf)
		for p in 0 ..< 256 {
			lct_buf[p * 3 + 0] = palette[p][0] // Red
			lct_buf[p * 3 + 1] = palette[p][1] // Green
			lct_buf[p * 3 + 2] = palette[p][2] // Blue
		}
		os.write(f, lct_buf)

		// 6. Write LZW Minimum Code Size
		// The LZW encoder starts with a base code size of 8 bits for color palettes.
		os.write(f, []byte{8})

		// Initialize LZW writer state
		w: Gif_Lzw
		w.data = make([dynamic]byte, 0, 1024)
		defer delete(w.data)
		w.numBits = 9 // Initial LZW code width is min_code_size (8) + 1 = 9 bits.

		// Compress and write LZW stream blocks
		gif_lzw_encode(indexed, &w)

		os.write(f, w.data[:])
	}

	// 7. Write the GIF Trailer (0x3B = ';')
	// Marks the end of the GIF file.
	os.write(f, []byte{0x3B})
	return true
}
