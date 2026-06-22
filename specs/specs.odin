package specs

import my_os "os:."

SystemSpecs :: struct {
	cpu_model:      string,
	cpu_cores_phys: int,
	cpu_cores_log:  int,
	gpu_model:      string,
	ram_total:      u64,
}

get_specs :: proc(allocator := context.allocator) -> SystemSpecs {
	s: SystemSpecs
	s.cpu_model, _ = my_os.get_cpu_name(allocator)
	s.cpu_cores_phys, s.cpu_cores_log, _ = my_os.get_cpu_cores()
	s.gpu_model, _ = my_os.get_gpu_name(allocator)
	s.ram_total, _ = my_os.get_total_ram()
	return s
}

free_specs :: proc(s: SystemSpecs, allocator := context.allocator) {
	delete(s.cpu_model, allocator)
	delete(s.gpu_model, allocator)
}
