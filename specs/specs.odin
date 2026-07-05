package specs

import os_geri "../os"

SystemSpecs :: struct {
	cpu_model:      string,
	cpu_cores_phys: int,
	cpu_cores_log:  int,
	gpu_model:      string,
	ram_total:      u64,
}

get_specs :: proc(allocator := context.allocator) -> SystemSpecs {
	s: SystemSpecs
	s.cpu_model, _ = os_geri.get_cpu_name(allocator)
	s.cpu_cores_phys, s.cpu_cores_log, _ = os_geri.get_cpu_cores()
	s.gpu_model, _ = os_geri.get_gpu_name(allocator)
	s.ram_total, _ = os_geri.get_total_ram()
	return s
}

free_specs :: proc(s: SystemSpecs, allocator := context.allocator) {
	delete(s.cpu_model, allocator)
	delete(s.gpu_model, allocator)
}
