#+build windows
package logging

import win32 "core:sys/windows"

foreign import kernel32 "system:kernel32.lib"
foreign kernel32 {
	GetTimeZoneInformation :: proc(lpTimeZoneInformation: ^win32.TIME_ZONE_INFORMATION) -> win32.DWORD ---
}

get_local_timezone_offset :: proc() -> int {
	tz: win32.TIME_ZONE_INFORMATION
	res := GetTimeZoneInformation(&tz)
	bias := tz.Bias
	if res == 2 { // TIME_ZONE_ID_DAYLIGHT
		bias += tz.DaylightBias
	} else if res == 1 { // TIME_ZONE_ID_STANDARD
		bias += tz.StandardBias
	}
	return -int(bias)
}
