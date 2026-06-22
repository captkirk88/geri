#+build !windows
#+build !linux
#+build !darwin
package sys_os

import "core:strings"
import sysinfo "core:sys/info"

get_cpu_name :: proc(allocator := context.allocator) -> (name: string, ok: bool) {
	c_name := sysinfo.cpu_name()
	if c_name != "" {
		return strings.clone(c_name, allocator), true
	}
	return "Unknown CPU", false
}

get_cpu_cores :: proc() -> (physical: int, logical: int, ok: bool) {
	phys, log, ok_cores := sysinfo.cpu_core_count()
	if ok_cores {
		return phys, log, true
	}
	return 0, 0, false
}

get_total_ram :: proc() -> (bytes: u64, ok: bool) {
	total, _, _, _, ram_ok := sysinfo.ram_stats()
	if ram_ok {
		return u64(total), true
	}
	return 0, false
}

get_gpu_name :: proc(allocator := context.allocator) -> (name: string, ok: bool) {
	return "Unknown GPU", false
}
