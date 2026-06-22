#+build linux
package sys_os

import core_os "core:os"
import "core:strings"
import sysinfo "core:sys/info"

get_cpu_name :: proc(allocator := context.allocator) -> (name: string, ok: bool) {
	c_name := sysinfo.cpu_name()
	if c_name != "" {
		return strings.clone(c_name, allocator), true
	}
	return "", false
}

get_cpu_cores :: proc() -> (physical: int, logical: int, ok: bool) {
	return sysinfo.cpu_core_count()
}

get_total_ram :: proc() -> (bytes: u64, ok: bool) {
	total, _, _, _, ram_ok := sysinfo.ram_stats()
	if ram_ok {
		return u64(total), true
	}
	return 0, false
}

get_gpu_name :: proc(allocator := context.allocator) -> (name: string, ok: bool) {
	desc := core_os.Process_Desc {
		command = []string{"/usr/bin/lspci"},
	}
	state, stdout, _, err := core_os.process_exec(desc, context.temp_allocator)
	if err == nil && state.exit_code == 0 {
		out_str := string(stdout)
		for line in strings.split_lines_iterator(&out_str) {
			lower_line := strings.to_lower(line)
			if strings.contains(lower_line, "vga") ||
			   strings.contains(lower_line, "3d") ||
			   strings.contains(lower_line, "display") {
				idx := strings.index(line, ": ")
				if idx >= 0 {
					gpu_desc := strings.trim_space(line[idx + 2:])
					return strings.clone(gpu_desc, allocator), true
				}
				return strings.clone(line, allocator), true
			}
		}
	}

	// Try with just "lspci"
	desc.command = []string{"lspci"}
	state, stdout, _, err = core_os.process_exec(desc, context.temp_allocator)
	if err == nil && state.exit_code == 0 {
		out_str := string(stdout)
		for line in strings.split_lines_iterator(&out_str) {
			lower_line := strings.to_lower(line)
			if strings.contains(lower_line, "vga") ||
			   strings.contains(lower_line, "3d") ||
			   strings.contains(lower_line, "display") {
				idx := strings.index(line, ": ")
				if idx >= 0 {
					gpu_desc := strings.trim_space(line[idx + 2:])
					return strings.clone(gpu_desc, allocator), true
				}
				return strings.clone(line, allocator), true
			}
		}
	}

	return strings.clone("Unknown GPU", allocator), false
}
