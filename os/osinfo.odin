package os_geri

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
	best_model: string
	max_vram: i64 = -1
	it: sysinfo.GPU_Iterator
	gpu, _, ok_gpu := sysinfo.iterate_gpus(&it)
	for ok_gpu {
		if gpu.vram > max_vram {
			max_vram = gpu.vram
			best_model = gpu.model
		}
		gpu, _, ok_gpu = sysinfo.iterate_gpus(&it)
	}
	if best_model != "" {
		return strings.clone(best_model, allocator), true
	}
	return "Uknown GPU", false
}
