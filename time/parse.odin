package gtime

import "core:strconv"
import "core:strings"
import "core:time"

parse_duration :: proc(s: string) -> (time.Duration, bool) {
	if len(s) < 2 do return 0, false

	if strings.has_suffix(s, "ms") {
		num_part := s[:len(s) - 2]
		val, ok := strconv.parse_f64(num_part)
		if !ok do return 0, false
		return time.Duration(val * f64(time.Millisecond)), true
	}

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

import "core:testing"

@(test)
test_parse_duration :: proc(t: ^testing.T) {
	d, ok := parse_duration("100ms")
	testing.expect(t, ok, "Failed to parse 100ms")
	testing.expect_value(t, d, 100 * time.Millisecond)

	d, ok = parse_duration("2.5s")
	testing.expect(t, ok, "Failed to parse 2.5s")
	testing.expect_value(t, d, time.Duration(2.5 * f64(time.Second)))

	d, ok = parse_duration("5m")
	testing.expect(t, ok, "Failed to parse 5m")
	testing.expect_value(t, d, 5 * time.Minute)

	d, ok = parse_duration("1h")
	testing.expect(t, ok, "Failed to parse 1h")
	testing.expect_value(t, d, 1 * time.Hour)

	_, ok = parse_duration("invalid")
	testing.expect(t, !ok, "Should fail to parse invalid duration")
}
