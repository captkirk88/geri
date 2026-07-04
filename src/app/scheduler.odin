package app

import ecs "../ecs"
import sys "../ecs/systems"
import log "../logging"
import reflect "../reflect"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sync"
import "core:thread"

System_Metadata :: struct {
	system: ^sys.System,
	name:   string,
	before: [dynamic]rawptr, // procedure pointers of systems that must run after this one
	after:  [dynamic]rawptr, // procedure pointers of systems that must run before this one
}

Schedule :: struct {
	systems:           #soa[dynamic]System_Metadata,
	levels:            [dynamic][dynamic]int,
	needs_compilation: bool,
	parallel:          bool,
}

// Instantiates a new, uncompiled Schedule pointer.
schedule_new :: proc(thread_count := 4, allocator := context.allocator) -> ^Schedule {
	sched := new(Schedule, allocator)
	sched.systems = make(#soa[dynamic]System_Metadata, allocator)
	sched.levels = make([dynamic][dynamic]int, allocator)
	sched.needs_compilation = true
	sched.parallel = false

	return sched
}

// Destroys the Schedule instance, freeing resources.
schedule_destroy :: proc(w: ^ecs.World, sched: ^Schedule) {
	for i in 0 ..< len(sched.systems) {
		sys.destroy_system(w, sched.systems.system[i], w.allocator)
		delete(sched.systems.before[i])
		delete(sched.systems.after[i])
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

	append_soa(&sched.systems, meta)
	sched.needs_compilation = true
}

// Registers a pre-built ^System into the schedule (e.g., from run_if or pipe).
schedule_add_system_raw :: proc(
	sched: ^Schedule,
	w: ^ecs.World,
	system: ^sys.System,
	name: string = "<composite>",
	before: []rawptr = nil,
	after: []rawptr = nil,
) {
	meta: System_Metadata
	meta.system = system
	meta.name = name
	meta.before = make([dynamic]rawptr, w.allocator)
	meta.after = make([dynamic]rawptr, w.allocator)

	for b in before {
		append(&meta.before, b)
	}
	for a in after {
		append(&meta.after, a)
	}

	append_soa(&sched.systems, meta)
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
	for i in 0 ..< N {
		sys_map[sched.systems.system[i].procedure] = i
	}

	// 2. Add explicit before/after dependencies
	for i in 0 ..< N {
		for b in sched.systems.before[i] {
			if b_idx, ok := sys_map[b]; ok {
				append(&adj[i], b_idx)
			}
		}
		for a in sched.systems.after[i] {
			if a_idx, ok := sys_map[a]; ok {
				append(&adj[a_idx], i)
			}
		}
	}

	// 3. Resolve resource conflict dependencies
	res_accesses := make([][]typeid, N, context.temp_allocator)
	for i in 0 ..< N {
		res_accesses[i] = get_system_resources(sched.systems.system[i], context.temp_allocator)
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
		log.error("cycle detected in schedule system dependencies!")
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

System_Task_Data :: struct {
	system: ^sys.System,
	wg:     ^sync.Wait_Group,
}

system_task_proc :: proc(task: thread.Task) {
	data := cast(^System_Task_Data)task.data
	sys.execute_system(data.system)
	sync.wait_group_done(data.wg)
}

// Runs all systems in the schedule, compiling if needed and running parallel systems on the thread pool if configured.
schedule_run :: proc(w: ^ecs.World, sched: ^Schedule, pool: ^thread.Pool = nil) {
	if sched.needs_compilation {
		compile_schedule(sched)
	}
	levels_count := len(sched.levels)

	if levels_count == 0 {
		return
	}

	for lvl_idx in 0 ..< levels_count {
		level := sched.levels[lvl_idx]
		level_len := len(level)

		for i in 0 ..< level_len {
			sys_idx := level[i]
			sys.build_system(w, sched.systems.system[sys_idx])
		}

		if level_len == 1 {
			sys_idx := level[0]
			sys.execute_system(sched.systems.system[sys_idx])
		} else {
			if sched.parallel && pool != nil {
				wg: sync.Wait_Group
				sync.wait_group_add(&wg, level_len)

				tasks := make([]System_Task_Data, level_len, context.temp_allocator)
				for i in 0 ..< level_len {
					sys_idx := level[i]
					tasks[i] = System_Task_Data{sched.systems.system[sys_idx], &wg}
					thread.pool_add_task(pool, context.temp_allocator, system_task_proc, &tasks[i])
				}

				sync.wait_group_wait(&wg)
			} else {
				for i in 0 ..< level_len {
					sys_idx := level[i]
					sys.execute_system(sched.systems.system[sys_idx])
				}
			}
		}

		for i in 0 ..< level_len {
			sys_idx := level[i]
			sys.flush_system(w, sched.systems.system[sys_idx])
		}
	}
}

// Modifies an already registered system's before/after execution constraints in the schedule.
// Returns true if the system was found and modified.
schedule_modify_system :: proc(
	sched: ^Schedule,
	procedure: rawptr,
	before: []rawptr = nil,
	after: []rawptr = nil,
) -> bool {
	for i in 0 ..< len(sched.systems) {
		if sched.systems.system[i].procedure == procedure {
			for b in before {
				append(&sched.systems.before[i], b)
			}
			for a in after {
				append(&sched.systems.after[i], a)
			}
			sched.needs_compilation = true
			return true
		}
	}
	return false
}
