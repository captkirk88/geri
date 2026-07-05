package ecs

import "base:runtime"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import reflect "../reflect"


Archetype_Edge :: struct {
	add:       ^Archetype,
	remove:    ^Archetype,
	add_index: i32,
}

Column :: struct {
	ptr:  rawptr,
	size: int,
	type: typeid,
}

Archetype :: struct {
	// Component types in this archetype, sorted by typeid for efficient lookup
	types:     []typeid,
	// Size of each component type in the archetype, indexed by the same order as `types`
	sizes:     []int,
	// Contiguous arrays of component data for each type, indexed by the same order as `types`
	columns:   []Column,
	// Contiguous array of entity handles corresponding to the component rows
	entities:  [dynamic]Entity,
	// Maps component typeid to column index for O(1) lookup
	lookup:    map[typeid]int,
	// Edges to other archetypes when adding/removing a component type
	edges:     map[typeid]Archetype_Edge,
	allocator: runtime.Allocator,
	// Number of entities currently stored in this archetype
	len:       int,
	// Capacity of the archetype (size of allocated columns)
	cap:       int,
	lock:      sync.Mutex,
}

/*
    Initializes a new archetype given a set of component types.
    Calculates sizes and initializes storage columns.
*/
arch_init :: proc(a: ^Archetype, types: []typeid, allocator := context.allocator) {
	a.allocator = allocator
	a.types = make([]typeid, len(types), allocator = a.allocator)
	copy(a.types, types)

	// Sort types to ensure archetypes with the same components have identical type arrays
	slice.sort_by(a.types, proc(i, j: typeid) -> bool {
		return transmute(uintptr)i < transmute(uintptr)j
	})

	count := len(a.types)
	a.sizes = make([]int, count, a.allocator)
	a.columns = make([]Column, count, allocator = a.allocator)
	a.entities = make([dynamic]Entity, allocator = a.allocator)
	a.cap = 0

	for t, i in a.types {
		size := reflect.size_of_type(t)
		a.sizes[i] = size
		a.columns[i].size = size
		a.columns[i].type = t
	}

	a.lookup = make(map[typeid]int, count, allocator = a.allocator)
	for t, i in a.types {
		a.lookup[t] = i
	}

	a.edges = make(map[typeid]Archetype_Edge, 0, allocator = a.allocator)
}

arch_deinit :: proc(a: ^Archetype) {
	delete(a.types, a.allocator)
	delete(a.sizes, a.allocator)
	for col in a.columns {
		if col.ptr != nil do free(col.ptr, a.allocator)
	}
	delete(a.columns, a.allocator)
	delete(a.entities)
	delete(a.lookup)
	delete(a.edges)
}

arch_add_entity :: proc(a: ^Archetype, entity: Entity) -> int {
	sync.mutex_lock(&a.lock)
	defer sync.mutex_unlock(&a.lock)

	if a.len >= a.cap {
		a.cap = max(16, a.cap * 2)
		reserve(&a.entities, a.cap)
		for &col in a.columns {
			new_ptr, _ := mem.resize(
				col.ptr,
				a.len * col.size,
				a.cap * col.size,
				allocator = a.allocator,
			)
			col.ptr = new_ptr
		}
	}

	row := a.len
	a.len += 1
	append(&a.entities, entity)
	return row
}

arch_remove_row :: proc(a: ^Archetype, row: int) -> (moved_entity: Entity, was_moved: bool) {
	sync.mutex_lock(&a.lock)
	defer sync.mutex_unlock(&a.lock)

	a.len -= 1
	moved_entity = a.entities[a.len]
	was_moved = row != a.len

	if was_moved {
		for &col in a.columns {
			ptr := ([^]byte)(col.ptr)
			mem.copy(&ptr[row * col.size], &ptr[a.len * col.size], col.size)
		}
		a.entities[row] = moved_entity
	}
	pop(&a.entities)
	return
}

/*
    Returns a slice of all components of type T in the archetype.
    Used for high-performance vectorized iteration.
*/
arch_get_field :: proc(arch: ^Archetype, $T: typeid) -> []T {
	tid := typeid_of(T)
	if idx, ok := arch.lookup[tid]; ok {
		col := &arch.columns[idx]
		return slice.from_ptr((^T)(col.ptr), arch.len)
	}
	return nil
}

/*
    Returns a pointer to a component of type T at a specific row in the archetype.
*/
arch_get_component :: proc(arch: ^Archetype, row: int, $T: typeid) -> ^T {
	tid := typeid_of(T)
	if idx, ok := arch.lookup[tid]; ok && row >= 0 && row < arch.len {
		col := &arch.columns[idx]
		ptr := ([^]byte)(col.ptr)
		return (^T)(&ptr[row * col.size])
	}
	return nil
}

/*
    Returns a slice of all entities currently stored in this archetype.
*/
arch_get_entities :: proc(arch: ^Archetype) -> []Entity {
	// Returns the contiguous array of entity handles corresponding to the component rows.
	return arch.entities[:arch.len]
}

@(test)
test_archetype_lifecycle :: proc(t: ^testing.T) {
	a: Archetype
	// Mix types to test sorting and sizing
	types := []typeid{f32, i32}
	arch_init(&a, types)
	defer arch_deinit(&a)

	testing.expect_value(t, len(a.types), 2)
	testing.expect_value(t, a.len, 0)

	e1 := Entity {
		id  = 1,
		gen = 0,
	}
	row := arch_add_entity(&a, e1)
	testing.expect_value(t, row, 0)
	testing.expect_value(t, a.len, 1)

	_, was_moved := arch_remove_row(&a, 0)
	testing.expect_value(t, was_moved, false)
	testing.expect_value(t, a.len, 0)
}


@(test)
test_archetype_threaded :: proc(t: ^testing.T) {
	a: Archetype
	types := []typeid{f32, i32}
	arch_init(&a, types)
	defer arch_deinit(&a)

	e1 := Entity {
		id  = 1,
		gen = 0,
	}
	e2 := Entity {
		id  = 2,
		gen = 0,
	}
	e3 := Entity {
		id  = 3,
		gen = 0,
	}

	data :: struct {
		a: ^Archetype,
		e: Entity,
	}

	task :: proc(task: thread.Task) {
		d := cast(^data)task.data
		a := d.a
		e := d.e
		for i in 0 ..< 1000 {
			arch_add_entity(a, e)
		}
	}

	allocator := context.allocator
	// Spawn entities in parallel to test thread safety of archetype operations
	pool := thread.Pool{}
	thread.pool_init(&pool, allocator, 4, nil, rawptr(&data{&a, e1}))
	defer thread.pool_destroy(&pool)
	thread.pool_add_task(&pool, allocator, task, rawptr(&data{&a, e1}))
	thread.pool_add_task(&pool, allocator, task, rawptr(&data{&a, e2}))
	thread.pool_add_task(&pool, allocator, task, rawptr(&data{&a, e3}))
	thread.pool_start(&pool)
	time.sleep(100 * time.Millisecond) // Wait for tasks to add entities
	thread.pool_finish(&pool) // Wait for threads to finish

	testing.expect_value(t, a.len, 3000)
}
