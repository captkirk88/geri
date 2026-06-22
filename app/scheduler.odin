package app

import ecs "../ecs"
import sys "../ecs/systems"
import reflect "../reflect"
import "base:intrinsics"
import "base:runtime"
import "core:bufio"
import "core:container/queue"
import "core:fmt"
import "core:sync"
import "core:thread"

System_Metadata :: struct {
	system: ^sys.System,
	name:   string,
	before: [dynamic]rawptr, // procedure pointers of systems that must run after this one
	after:  [dynamic]rawptr, // procedure pointers of systems that must run before this one
}

Schedule :: struct {
	mutex:             sync.Mutex,
	systems:           [dynamic]System_Metadata,
	levels:            [dynamic][dynamic]int,
	needs_compilation: bool,

	// Pre-initialized Thread Pool
	threads:           [dynamic]^thread.Thread,
	task_queue:        queue.Queue(^sys.System),
	queue_cond:        sync.Cond,
	finished_cond:     sync.Cond,
	remaining_tasks:   int,
	should_exit:       bool,
}

// Worker thread procedure for executing systems from the schedule's queue.
worker_proc :: proc(t: ^thread.Thread) {
	sched := (^Schedule)(t.data)

	for {
		sync.mutex_lock(&sched.mutex)
		for queue.len(sched.task_queue) == 0 && !sched.should_exit {
			sync.cond_wait(&sched.queue_cond, &sched.mutex)
		}

		if sched.should_exit {
			sync.mutex_unlock(&sched.mutex)
			break
		}

		system := queue.pop_front(&sched.task_queue)
		sync.mutex_unlock(&sched.mutex)

		sys.execute_system(system)

		sync.mutex_lock(&sched.mutex)
		sched.remaining_tasks -= 1
		if sched.remaining_tasks == 0 {
			sync.cond_broadcast(&sched.finished_cond)
		}
		sync.mutex_unlock(&sched.mutex)
	}
}

// Instantiates a new, uncompiled Schedule pointer, spawning its worker threads immediately.
schedule_new :: proc(thread_count := 4, allocator := context.allocator) -> ^Schedule {
	sched := new(Schedule, allocator)
	sched.systems = make([dynamic]System_Metadata, allocator)
	sched.levels = make([dynamic][dynamic]int, allocator)
	sched.needs_compilation = true

	sched.threads = make([dynamic]^thread.Thread, allocator)
	queue.init(&sched.task_queue, 16, allocator)
	sched.should_exit = false

	for i in 0 ..< thread_count {
		t := thread.create(worker_proc)
		if t != nil {
			t.data = rawptr(sched)
			append(&sched.threads, t)
			thread.start(t)
		}
	}

	return sched
}

// Destroys the Schedule instance, notifying and joining all worker threads, then freeing resources.
schedule_destroy :: proc(w: ^ecs.World, sched: ^Schedule) {
	sync.mutex_lock(&sched.mutex)
	sched.should_exit = true
	sync.cond_broadcast(&sched.queue_cond)
	sync.mutex_unlock(&sched.mutex)

	for t in sched.threads {
		thread.join(t)
		thread.destroy(t)
	}
	delete(sched.threads)
	queue.destroy(&sched.task_queue)

	sync.mutex_lock(&sched.mutex)
	defer sync.mutex_unlock(&sched.mutex)

	for meta in sched.systems {
		sys.destroy_system(w, meta.system, w.allocator)
		delete(meta.before)
		delete(meta.after)
	}
	delete(sched.systems)

	for lvl in sched.levels {
		delete(lvl)
	}
	delete(sched.levels)

	free(sched, w.allocator)
}

// Registers a system procedure into the schedule with sorting constraint rules.
schedule_add_system :: proc(
	sched: ^Schedule,
	w: ^ecs.World,
	procedure: $T,
	name := #caller_expression(procedure),
	before: []rawptr = nil,
	after: []rawptr = nil,
) where intrinsics.type_is_proc(T) {
	sync.mutex_lock(&sched.mutex)
	defer sync.mutex_unlock(&sched.mutex)

	s := sys.new_system(procedure, w.allocator)

	meta: System_Metadata
	meta.system = s
	meta.name = name
	meta.before = make([dynamic]rawptr, w.allocator)
	meta.after = make([dynamic]rawptr, w.allocator)

	for b in before {
		append(&meta.before, b)
	}
	for a in after {
		append(&meta.after, a)
	}

	append(&sched.systems, meta)
	sched.needs_compilation = true
}

// Reflects on the system's parameter block to find and return the types of all global resources accessed by the system.
get_system_resources :: proc(
	system: ^sys.System,
	allocator := context.temp_allocator,
) -> []typeid {
	if system.params_type == nil do return nil
	info := reflect.base_info_of(system.params_type)
	params_info, ok := info.variant.(runtime.Type_Info_Parameters)
	if !ok do return nil

	res_types := make([dynamic]typeid, allocator)

	for p_info in params_info.types {
		base_info := runtime.type_info_base(p_info)
		if reflect.match_struct_field(base_info, "ptr", 1) {
			s := base_info.variant.(runtime.Type_Info_Struct)
			elem_type := reflect.get_pointer_elem_type(s, 0)
			if elem_type != typeid_of(ecs.Commands) {
				append(&res_types, elem_type)
			}
		}
	}
	return res_types[:]
}

// Checks if a path exists from start node index to end node index in a dependency adjacency list.
@(private)
is_reachable :: proc(adj: [dynamic][dynamic]int, start, end: int, N: int) -> bool {
	visited := make([]bool, N, context.temp_allocator)
	queue := make([dynamic]int, context.temp_allocator)
	append(&queue, start)
	visited[start] = true

	for len(queue) > 0 {
		curr := pop_front(&queue)
		if curr == end do return true
		for neighbor in adj[curr] {
			if !visited[neighbor] {
				visited[neighbor] = true
				append(&queue, neighbor)
			}
		}
	}
	return false
}

// Resolves system constraints (explicit before/after ordering & automatic resource access conflicts) and clusters them into parallel execution levels.
@(private)
compile_schedule :: proc(sched: ^Schedule) {
	N := len(sched.systems)
	if N == 0 {
		sched.needs_compilation = false
		return
	}

	// Clear previous levels
	for l in sched.levels {
		delete(l)
	}
	clear(&sched.levels)

	adj := make([dynamic][dynamic]int, N, context.temp_allocator)
	for &list in adj {
		list = make([dynamic]int, context.temp_allocator)
	}

	// 1. Map system procedure pointer (rawptr) to system index in sched.systems
	sys_map := make(map[rawptr]int, N, context.temp_allocator)
	for s, idx in sched.systems {
		sys_map[s.system.procedure] = idx
	}

	// 2. Add explicit before/after dependencies
	for meta, idx in sched.systems {
		for b in meta.before {
			if b_idx, ok := sys_map[b]; ok {
				append(&adj[idx], b_idx)
			}
		}
		for a in meta.after {
			if a_idx, ok := sys_map[a]; ok {
				append(&adj[a_idx], idx)
			}
		}
	}

	// 3. Resolve resource conflict dependencies
	res_accesses := make([][]typeid, N, context.temp_allocator)
	for meta, idx in sched.systems {
		res_accesses[idx] = get_system_resources(meta.system, context.temp_allocator)
	}

	for i in 0 ..< N {
		for j in (i + 1) ..< N {
			conflicts := false
			for r_i in res_accesses[i] {
				for r_j in res_accesses[j] {
					if r_i == r_j {
						conflicts = true
						break
					}
				}
				if conflicts do break
			}

			if conflicts {
				if is_reachable(adj, i, j, N) {
					continue
				}
				if is_reachable(adj, j, i, N) {
					continue
				}
				append(&adj[i], j)
			}
		}
	}

	// 4. Kahn's algorithm to compute in-degrees and group into levels
	in_degree := make([]int, N, context.temp_allocator)
	for i in 0 ..< N {
		for neighbor in adj[i] {
			in_degree[neighbor] += 1
		}
	}

	levels_map := make([]int, N, context.temp_allocator)
	for i in 0 ..< N {
		levels_map[i] = -1
	}

	queue := make([dynamic]int, context.temp_allocator)
	for i in 0 ..< N {
		if in_degree[i] == 0 {
			levels_map[i] = 0
			append(&queue, i)
		}
	}

	visited_count := 0
	max_level := 0

	for len(queue) > 0 {
		curr := pop_front(&queue)
		visited_count += 1
		curr_level := levels_map[curr]
		if curr_level > max_level {
			max_level = curr_level
		}

		for neighbor in adj[curr] {
			in_degree[neighbor] -= 1
			if levels_map[neighbor] < curr_level + 1 {
				levels_map[neighbor] = curr_level + 1
			}
			if in_degree[neighbor] == 0 {
				append(&queue, neighbor)
			}
		}
	}

	if visited_count < N {
		fmt.eprintln("Error: Cycle detected in schedule system dependencies!")
	}

	levels_count := max_level + 1
	for l in 0 ..< levels_count {
		level_list := make([dynamic]int, sched.systems.allocator)
		for idx in 0 ..< N {
			if levels_map[idx] == l {
				append(&level_list, idx)
			}
		}
		if len(level_list) > 0 {
			append(&sched.levels, level_list)
		} else {
			delete(level_list)
		}
	}

	sched.needs_compilation = false
}

// Runs all systems in the schedule, compiling if needed and running parallel systems on multiple threads.
schedule_run :: proc(w: ^ecs.World, sched: ^Schedule, thread_count := 4) {
	sync.mutex_lock(&sched.mutex)
	if sched.needs_compilation {
		compile_schedule(sched)
	}
	levels_count := len(sched.levels)
	sync.mutex_unlock(&sched.mutex)

	if levels_count == 0 {
		return
	}

	for lvl_idx in 0 ..< levels_count {
		sync.mutex_lock(&sched.mutex)
		level := sched.levels[lvl_idx]
		level_len := len(level)

		for i in 0 ..< level_len {
			sys_idx := level[i]
			meta := sched.systems[sys_idx]
			sys.build_system(w, meta.system)
		}

		if level_len == 1 || thread_count <= 1 || len(sched.threads) == 0 {
			sync.mutex_unlock(&sched.mutex)
			for i in 0 ..< level_len {
				sys_idx := level[i]
				meta := sched.systems[sys_idx]
				sys.execute_system(meta.system)
			}
		} else {
			sched.remaining_tasks = level_len
			for i in 0 ..< level_len {
				sys_idx := level[i]
				meta := sched.systems[sys_idx]
				queue.push_back(&sched.task_queue, meta.system)
			}
			sync.cond_broadcast(&sched.queue_cond)

			for sched.remaining_tasks > 0 {
				sync.cond_wait(&sched.finished_cond, &sched.mutex)
			}
			sync.mutex_unlock(&sched.mutex)
		}

		sync.mutex_lock(&sched.mutex)
		for i in 0 ..< level_len {
			sys_idx := level[i]
			meta := sched.systems[sys_idx]
			sys.flush_system(w, meta.system)
		}
		sync.mutex_unlock(&sched.mutex)
	}
}
