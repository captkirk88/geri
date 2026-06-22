#+build !windows
package benchmark

import os "os:."

@(private)
get_total_physical_memory :: proc() -> int {
	ram, ok := os.get_total_ram()
	if ok do return int(ram)
	return 16 * 1024 * 1024 * 1024 // Fallback to 16 GB
}
