#+build linux
package logging

import "core:c"

foreign import libc "system:c"

time_t :: c.longlong

tm :: struct {
	tm_sec:    c.int,
	tm_min:    c.int,
	tm_hour:   c.int,
	tm_mday:   c.int,
	tm_mon:    c.int,
	tm_year:   c.int,
	tm_wday:   c.int,
	tm_yday:   c.int,
	tm_isdst:  c.int,
	tm_gmtoff: c.long,
	tm_zone:   cstring,
}

foreign libc {
	time        :: proc(t: ^time_t) -> time_t ---
	localtime_r :: proc(t: ^time_t, result: ^tm) -> ^tm ---
}

get_local_timezone_offset :: proc() -> int {
	t := time(nil)
	local_tm: tm
	if localtime_r(&t, &local_tm) != nil {
		return int(local_tm.tm_gmtoff / 60)
	}
	return 0
}
