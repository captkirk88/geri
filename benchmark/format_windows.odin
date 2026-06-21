#+build windows
package benchmark

import windows "core:sys/windows"

@(private)
get_total_physical_memory :: proc() -> int {
	mem_info: windows.MEMORYSTATUSEX
	mem_info.dwLength = size_of(windows.MEMORYSTATUSEX)
	if windows.GlobalMemoryStatusEx(&mem_info) {
		return int(mem_info.ullTotalPhys)
	}
	return 16 * 1024 * 1024 * 1024 // Fallback to 16 GB
}
