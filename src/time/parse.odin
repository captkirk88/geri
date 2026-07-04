package gtime

import "core:strconv"
import "core:time"

parse_duration :: proc(s: string) -> (time.Duration, bool) {
	if len(s) < 2 do return 0, false

	suffix := s[len(s) - 1]
	num_part := s[:len(s) - 1]

	val, ok := strconv.parse_f64(num_part)
	if !ok do return 0, false

	switch suffix {
	case 's':
		return time.Duration(val * f64(time.Second)), true
	case 'm':
		return time.Duration(val * f64(time.Minute)), true
	case 'h':
		return time.Duration(val * f64(time.Hour)), true
	case:
		return 0, false
	}
}
