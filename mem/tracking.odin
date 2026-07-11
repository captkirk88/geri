// Package mem_tracking provides memory tracking utilities for Geri applications and benchmarks.
//
// Usage:
// ```odin
//   tracker: mem_tracking.Tracker
//   mem_tracking.tracker_init(&tracker)
//   defer mem_tracking.tracker_destroy(&tracker)
//
//   context.allocator = mem_tracking.tracker_allocator(&tracker)
//
//   // ... do some setup work ...
//   mem_tracking.tracker_snapshot(&tracker) // isolate setup allocations
//
//   // ... run code under measurement ...
//   stats := mem_tracking.tracker_stats(&tracker)
//   mem_tracking.tracker_report(&tracker, "My Label")
// ```
package mem_tracking

import bench "../benchmark"
import log "../logging"
import core_log "core:log"
import core_mem "core:mem"
import "core:sync"

// Tracker wraps core:mem.Tracking_Allocator with snapshot support for
// isolating setup-phase allocations from measurement-phase allocations.
// It is fully thread-safe for use across thread pools.
Tracker :: struct {
	_inner:      core_mem.Tracking_Allocator,
	mutex:       sync.Mutex,
	// Allocation totals at the time of the last snapshot() call.
	// Stats methods return values relative to this baseline.
	_snap_alloc: i64,
	_snap_free:  i64,
	_snap_peak:  i64,
	_snap_count: i64,
}

// Tracker_Stats holds a point-in-time summary of allocation activity since
// the last snapshot (or since init if no snapshot has been taken).
Tracker_Stats :: struct {
	// Bytes currently live (allocated but not freed) above baseline.
	current_bytes: i64,
	// Peak live bytes above baseline.
	peak_bytes:    i64,
	// Total bytes allocated above baseline.
	total_alloc:   i64,
	// Total bytes freed above baseline.
	total_free:    i64,
	// Number of allocation calls above baseline.
	alloc_count:   i64,
	// Number of still-live (leaked) allocation entries.
	leak_count:    int,
}

// tracker_init initialises a Tracker, using the provided backing allocator
// (defaults to context.allocator when backing is zero).
tracker_init :: proc(t: ^Tracker, backing: core_mem.Allocator = context.allocator) {
	core_mem.tracking_allocator_init(&t._inner, backing)
}

// tracker_destroy frees all internal state owned by the Tracker.
// Any outstanding (leaked) allocations are reported via log.warn before destruction.
tracker_destroy :: proc(t: ^Tracker) {
	old_alloc := context.allocator
	context.allocator = t._inner.backing
	defer context.allocator = old_alloc

	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)

	if len(t._inner.allocation_map) > 0 {
		log.write(
			.Warning,
			"[mem.Tracker] %d leak(s) detected at destroy:",
			len(t._inner.allocation_map),
		)
		for _, entry in t._inner.allocation_map {
			log.write(.Warning, "    %v -> %s", entry.location, bench.format_bytes(entry.size))
		}
	}
	if len(t._inner.bad_free_array) > 0 {
		log.write(
			.Warning,
			"[mem.Tracker] %d bad free(s) detected at destroy:",
			len(t._inner.bad_free_array),
		)
		for entry in t._inner.bad_free_array {
			log.write(.Warning, "    %v — ptr %p", entry.location, entry.memory)
		}
	}
	core_mem.tracking_allocator_destroy(&t._inner)
}

// tracker_reset clears all recorded allocations and resets the snapshot
// baseline to zero.  The backing allocator is retained.
tracker_reset :: proc(t: ^Tracker) {
	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)

	core_mem.tracking_allocator_reset(&t._inner)
	t._snap_alloc = 0
	t._snap_free = 0
	t._snap_peak = 0
	t._snap_count = 0
}

tracker_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: core_mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	result: []byte,
	err: core_mem.Allocator_Error,
) {
	t := (^Tracker)(allocator_data)
	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)

	ta := core_mem.tracking_allocator(&t._inner)
	return ta.procedure(ta.data, mode, size, alignment, old_memory, old_size, loc)
}

// tracker_allocator returns a mem.Allocator backed by this Tracker.
// Assign it to context.allocator to intercept all subsequent allocations.
tracker_allocator :: proc(t: ^Tracker) -> core_mem.Allocator {
	return core_mem.Allocator{procedure = tracker_allocator_proc, data = t}
}

// tracker_snapshot captures the current allocation totals as a baseline.
// Call this after setup work so that tracker_stats / tracker_report only
// reflect allocations made *after* the snapshot.
//
// Example – isolating setup from the code under test:
// ```odin
//   mem_tracking.tracker_init(&tracker)
//   setup_my_world()                    // allocations here are excluded
//   mem_tracking.tracker_snapshot(&tracker)
//   run_hot_path()                      // only these are counted
//   mem_tracking.tracker_report(&tracker, "Hot Path")
// ```
tracker_snapshot :: proc(t: ^Tracker) {
	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)

	t._snap_alloc = t._inner.total_memory_allocated
	t._snap_free = t._inner.total_memory_freed
	t._snap_peak = t._inner.peak_memory_allocated
	t._snap_count = i64(t._inner.total_allocation_count)
}

// Internal helper for stats lookup without locking (to prevent recursive deadlocks).
@(private)
_tracker_stats :: proc(t: ^Tracker) -> Tracker_Stats {
	alloc_delta := t._inner.total_memory_allocated - t._snap_alloc
	free_delta := t._inner.total_memory_freed - t._snap_free
	// Peak above baseline: clamp to 0 to avoid negatives when no new peak
	// was set after the snapshot.
	peak_delta := max(t._inner.peak_memory_allocated - t._snap_peak, 0)

	return Tracker_Stats {
		current_bytes = alloc_delta - free_delta,
		peak_bytes = peak_delta,
		total_alloc = alloc_delta,
		total_free = free_delta,
		alloc_count = i64(t._inner.total_allocation_count) - t._snap_count,
		leak_count = len(t._inner.allocation_map),
	}
}

// tracker_stats returns a Tracker_Stats value computed relative to the
// last snapshot (or from zero if no snapshot has been taken).
tracker_stats :: proc(t: ^Tracker) -> Tracker_Stats {
	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)
	return _tracker_stats(t)
}

// tracker_report logs a human-readable memory usage report via the logging
// package (info level), using benchmark.format_bytes for byte formatting.
tracker_report :: proc(t: ^Tracker, label: string = "", level: core_log.Level = .Info) {
	old_alloc := context.allocator
	context.allocator = t._inner.backing
	defer context.allocator = old_alloc

	sync.lock(&t.mutex)
	defer sync.unlock(&t.mutex)

	stats := _tracker_stats(t)
	title := label if label != "" else "Memory Report"

	log.write(level, "[mem.Tracker | %s]", title)
	log.write(level, "  Current live:  %s", bench.format_bytes(int(stats.current_bytes)))
	log.write(level, "  Peak live:     %s", bench.format_bytes(int(stats.peak_bytes)))
	log.write(level, "  Total alloc:   %s", bench.format_bytes(int(stats.total_alloc)))
	log.write(level, "  Total freed:   %s", bench.format_bytes(int(stats.total_free)))
	log.write(level, "  Alloc calls:   %d", stats.alloc_count)

	if stats.leak_count > 0 {
		log.write(.Warning, "  Leaks:         %d  ← LEAKED", stats.leak_count)
		for _, entry in t._inner.allocation_map {
			log.write(.Warning, "    %v — %s", entry.location, bench.format_bytes(entry.size))
		}
	} else {
		log.write(level, "  Leaks:         0")
	}

	if len(t._inner.bad_free_array) > 0 {
		log.write(.Warning, "  Bad frees:     %d  ← BAD FREE", len(t._inner.bad_free_array))
		for entry in t._inner.bad_free_array {
			log.write(.Warning, "    %v — ptr %p", entry.location, entry.memory)
		}
	}
}
