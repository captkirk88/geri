#+build !windows
#+build !linux
package logging

get_local_timezone_offset :: proc() -> int {
	return 0
}
