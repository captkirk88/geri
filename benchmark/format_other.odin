#+build !windows
package benchmark

@(private)
get_total_physical_memory :: proc() -> int {
	return 16 * 1024 * 1024 * 1024 // Fallback to 16 GB
}
