package ecs

import "base:runtime"
import "core:hash"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:testing"
import "events"


Entity :: bit_field u64 {
	id:  u64 | 56,
	gen: u64 | 8,
}

Entity_Record :: struct {
	arch: ^Archetype,
	row:  int,
}

Entity_Meta :: struct {
	record: Entity_Record,
	gen:    u32,
}

Relation_Link :: struct {
	source:  Entity,
	pair_id: typeid,
}

Observer_Callback :: #type proc(w: ^World, e: Entity)

// System_Param_Builder defines how system parameters are dynamically injected and managed.
System_Param_Builder :: struct {
	// Evaluates whether this builder applies to a specific parameter type.
	match:     proc(info: ^runtime.Type_Info) -> bool,
	// Populates the parameter's memory block (ptr) before the system procedure runs.
	build:     proc(w: ^World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr),
	// Executes after the system procedure completes. Used for flushing buffers or deferred logic.
	after_run: proc(w: ^World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr),
	// Cleans up any resources or allocations associated with this parameter when the system is destroyed.
	destroy:   proc(sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr),
}

Resource_Destructor :: struct {
	destroy_proc: rawptr,
	wrapper:      proc(destroy_proc: rawptr, ptr: rawptr, allocator: runtime.Allocator),
}

World :: struct {
	entities:                     [dynamic]Entity_Meta,
	free_list:                    [dynamic]u32,
	archetypes:                   map[u64]^Archetype,
	root:                         ^Archetype,
	allocator:                    runtime.Allocator,
	resources:                    map[typeid]rawptr,
	resource_destructors:         map[typeid]Resource_Destructor,
	target_index:                 map[Entity][dynamic]Relation_Link,
	iteration_depth:              int,
	event_manager:                events.Event_Manager,
	systems_to_run:               [dynamic]rawptr,
	param_builders:               [dynamic]System_Param_Builder,
	filter_registry:              map[typeid]Filter_Info,
	filter_dedup:                 map[u64]typeid,
	virtual_id_counter:           uintptr,
	transition_buffer:            [dynamic]typeid,
	serialization_procs:          map[typeid]Serializer_Procs,
	serialization_names:          map[string]typeid,
	serialization_types:          map[typeid]string,
	resource_serialization_procs: map[typeid]Resource_Serializer_Procs,
	resource_serialization_names: map[string]typeid,
	resource_serialization_types: map[typeid]string,
	query_cache:                  map[u64]QueryIter,
	cache_mutex:                  sync.Mutex,
}

new_world :: proc(allocator := context.allocator) -> World {
	w: World
	w.allocator = allocator
	w.archetypes = make(map[u64]^Archetype, 16, w.allocator)
	w.entities = make([dynamic]Entity_Meta, w.allocator)
	w.free_list = make([dynamic]u32, w.allocator)
	w.root = new(Archetype, w.allocator)
	arch_init(w.root, nil, w.allocator)
	w.archetypes[0] = w.root
	w.resources = make(map[typeid]rawptr, 16, w.allocator)
	w.resource_destructors = make(map[typeid]Resource_Destructor, 16, w.allocator)
	w.target_index = make(map[Entity][dynamic]Relation_Link, 16, w.allocator)
	w.transition_buffer = make([dynamic]typeid, 0, 16, w.allocator)
	events.init(&w.event_manager, w.allocator)
	w.systems_to_run = make([dynamic]rawptr, w.allocator)
	w.param_builders = make([dynamic]System_Param_Builder, w.allocator)

	w.serialization_procs = make(map[typeid]Serializer_Procs, 16, w.allocator)
	w.serialization_names = make(map[string]typeid, 16, w.allocator)
	w.serialization_types = make(map[typeid]string, 16, w.allocator)

	w.resource_serialization_procs = make(map[typeid]Resource_Serializer_Procs, 16, w.allocator)
	w.resource_serialization_names = make(map[string]typeid, 16, w.allocator)
	w.resource_serialization_types = make(map[typeid]string, 16, w.allocator)

	w.query_cache = make(map[u64]QueryIter, 16, w.allocator)

	return w
}

world_destroy :: proc(w: ^World) {
	for _, arch in w.archetypes {
		arch_deinit(arch)
		free(arch, w.allocator)
	}
	for tid, ptr in w.resources {
		if dest, ok := w.resource_destructors[tid]; ok {
			if dest.destroy_proc != nil && dest.wrapper != nil {
				dest.wrapper(dest.destroy_proc, ptr, w.allocator)
			}
		}
		free(ptr, w.allocator)
	}
	for _, links in w.target_index {
		delete(links)
	}
	delete(w.archetypes)

	delete(w.target_index)

	for _, v in w.filter_registry {
		if v.types != nil do delete(v.types, w.allocator)
	}
	delete(w.filter_registry)
	delete(w.filter_dedup)
	events.destroy(&w.event_manager)

	delete(w.transition_buffer)
	delete(w.entities)
	delete(w.free_list)
	delete(w.systems_to_run)
	delete(w.resources)
	delete(w.resource_destructors)
	delete(w.param_builders)

	delete(w.serialization_procs)
	for _, name in w.serialization_types {
		delete(name, w.allocator)
	}
	delete(w.serialization_names)
	delete(w.serialization_types)

	delete(w.resource_serialization_procs)
	for _, name in w.resource_serialization_types {
		delete(name, w.allocator)
	}
	delete(w.resource_serialization_names)
	delete(w.resource_serialization_types)

	for _, iter in w.query_cache {
		delete(cast([]^Archetype)iter, w.allocator)
	}
	delete(w.query_cache)
}

world_register_param_builder :: proc(w: ^World, builder: System_Param_Builder) {
	append(&w.param_builders, builder)
}

/*
    Clears all event history. Typically called at the end of a frame or tick loop
	so that events don't accumulate indefinitely.
*/
world_clear_events :: proc(w: ^World) {
	events.clear_events(&w.event_manager)
}

world_spawn :: proc(w: ^World) -> Entity {
	id: u32
	gen: u32
	if len(w.free_list) > 0 {
		id = pop(&w.free_list)
		gen = w.entities[id].gen
	} else {
		id = u32(len(w.entities))
		append(&w.entities, Entity_Meta{gen = 1})
		gen = 1
	}

	e := Entity {
		id  = u64(id),
		gen = u64(gen),
	}
	row := arch_add_entity(w.root, e)
	w.entities[id].record = {w.root, row}

	return e
}

world_despawn :: proc(w: ^World, entity: Entity) {
	id := u32(entity.id)
	if int(id) >= len(w.entities) || w.entities[id].gen != u32(entity.gen) do return

	record := w.entities[id].record
	arch := record.arch

	// 1. Cleanup where this entity is the TARGET
	if links, ok := w.target_index[entity]; ok {
		for link in links {
			if world_is_alive(w, link.source) {
				world_remove_component(w, link.source, link.pair_id)
			}
		}
		delete(links)
		delete_key(&w.target_index, entity)
	}

	// 2. Cleanup where this entity is the SOURCE
	// We check its components for any relationship pairs
	comps, ok := world_get_all_components(w, entity, context.temp_allocator)
	if ok {
		defer delete(comps, context.temp_allocator)
		for c in comps {
			trigger_lifecycle(w, .OnRemove, c.id, entity)
			if is_pair(c.id) {
				if info, found := w.filter_registry[c.id]; found {
					if links, ok2 := w.target_index[info.target]; ok2 {
						for link, i in links {
							if link.source == entity && link.pair_id == c.id {
								unordered_remove(&links, i)
								break
							}
						}
					}
				}
			}
		}
	}

	// Remove from the Archetype storage
	moved_entity, was_moved := arch_remove_row(arch, record.row)

	// If the swap-and-pop moved another entity, update its record in the world
	if was_moved {
		w.entities[moved_entity.id].record.row = record.row
	}

	// Invalidate handle and recycle ID
	w.entities[id].gen += 1
	append(&w.free_list, id)
	w.entities[id].record = {}
}

world_is_alive :: proc(w: ^World, entity: Entity) -> bool {
	id := u32(entity.id)
	return int(id) < len(w.entities) && w.entities[id].gen == u32(entity.gen)
}

world_add_system :: proc(w: ^World, sys: rawptr) {
	append(&w.systems_to_run, sys)
}

world_remove_system :: proc(w: ^World, sys: rawptr) {
	for i := 0; i < len(w.systems_to_run); i += 1 {
		s := w.systems_to_run[i]
		if s == sys {
			unordered_remove_dynamic_array(&w.systems_to_run, i)
			break
		}
	}
}

world_clear_query_cache :: proc(w: ^World) {
	sync.mutex_lock(&w.cache_mutex)
	defer sync.mutex_unlock(&w.cache_mutex)
	for _, iter in w.query_cache {
		delete(cast([]^Archetype)iter, w.allocator)
	}
	clear(&w.query_cache)
}

@(private)
_get_arch_hash :: proc(types: []typeid) -> u64 {
	if len(types) == 0 do return 0
	return hash.fnv64a(slice.to_bytes(types))
}

@(private)
world_get_next_archetype :: proc(w: ^World, current: ^Archetype, add_type: typeid) -> ^Archetype {
	clear(&w.transition_buffer)
	for t in current.types do append(&w.transition_buffer, t)
	append(&w.transition_buffer, add_type)
	slice.sort_by(w.transition_buffer[:], proc(i, j: typeid) -> bool {
		return transmute(uintptr)i < transmute(uintptr)j
	})

	h := _get_arch_hash(w.transition_buffer[:])

	next: ^Archetype
	if val, ok := w.archetypes[h]; ok {
		next = val
	} else {
		next = new(Archetype, w.allocator)
		arch_init(next, w.transition_buffer[:], w.allocator)
		w.archetypes[h] = next
		world_clear_query_cache(w)
	}

	add_idx: i32 = -1
	for t, i in next.types {
		if t == add_type {
			add_idx = i32(i)
			break
		}
	}

	current.edges[add_type] = {
		add       = next,
		add_index = add_idx,
	}

	return next
}

@(private)
_world_transition_type :: proc(
	w: ^World,
	entity: Entity,
	tid: typeid,
	data: rawptr,
	size: int,
	is_tag: bool,
) {
	id := u32(entity.id)
	meta := &w.entities[id]
	if meta.gen != u32(entity.gen) do return

	current := meta.record.arch

	// Fast Presence Check
	for t, i in current.types {
		if t == tid {
			if !is_tag && data != nil && size > 0 {
				col := &current.columns[i]
				mem.copy(&(([^]byte)(col.ptr))[meta.record.row * col.size], data, col.size)
			}
			return
		}
	}

	edge, has_edge := current.edges[tid]
	if !has_edge {
		world_get_next_archetype(w, current, tid)
		edge = current.edges[tid]
	}
	next := edge.add

	new_row := arch_add_entity(next, entity)

	// Migrate existing components and add the new one
	if len(current.columns) > 0 {
		curr_col := 0
		for next_col, i in next.columns {
			if i == int(edge.add_index) {
				if !is_tag && data != nil && size > 0 {
					mem.copy(
						&(([^]byte)(next_col.ptr))[new_row * next_col.size],
						data,
						next_col.size,
					)
				}
				continue
			}
			src_col := current.columns[curr_col]
			mem.copy(
				&(([^]byte)(next_col.ptr))[new_row * next_col.size],
				&(([^]byte)(src_col.ptr))[meta.record.row * src_col.size],
				src_col.size,
			)
			curr_col += 1
		}
	} else {
		// Moving from root: copy the new component if any
		if !is_tag && data != nil && size > 0 {
			next_col := &next.columns[edge.add_index]
			mem.copy(&(([^]byte)(next_col.ptr))[new_row * next_col.size], data, next_col.size)
		}
	}

	moved_entity, was_moved := arch_remove_row(current, meta.record.row)
	if was_moved {
		w.entities[u32(moved_entity.id)].record.row = meta.record.row
	}
	meta.record.arch = next
	meta.record.row = new_row
	trigger_lifecycle(w, .OnAdd, tid, entity)
}

world_add_component :: proc(w: ^World, entity: Entity, component: $T) {
	id := u32(entity.id)
	meta := &w.entities[id]
	if meta.gen != u32(entity.gen) do return

	current := meta.record.arch
	tid := typeid_of(T)

	// Fast Presence Check: Linear search on small sorted types is faster than map hash
	for t, i in current.types {
		if t == tid {
			col := &current.columns[i]
			((^T)(&(([^]byte)(col.ptr))[meta.record.row * col.size]))^ = component
			return
		}
	}

	edge, has_edge := current.edges[tid]
	if !has_edge {
		world_get_next_archetype(w, current, tid)
		edge = current.edges[tid]
	}
	next := edge.add

	new_row := arch_add_entity(next, entity)

	// Optimized Transition: Skip migration loop if moving from root (0 components)
	if len(current.columns) > 0 {
		curr_col := 0
		for next_col, i in next.columns {
			if i == int(edge.add_index) {
				((^T)(&(([^]byte)(next_col.ptr))[new_row * next_col.size]))^ = component
				continue
			}
			src_col := current.columns[curr_col]
			mem.copy(
				&(([^]byte)(next_col.ptr))[new_row * next_col.size],
				&(([^]byte)(src_col.ptr))[meta.record.row * src_col.size],
				src_col.size,
			)
			curr_col += 1
		}
	} else {
		// Moving from root: only copy the new component
		next_col := &next.columns[edge.add_index]
		((^T)(&(([^]byte)(next_col.ptr))[new_row * next_col.size]))^ = component
	}

	moved_entity, was_moved := arch_remove_row(current, meta.record.row)
	if was_moved {
		w.entities[u32(moved_entity.id)].record.row = meta.record.row
	}
	meta.record.arch = next
	meta.record.row = new_row
	trigger_lifecycle(w, .OnAdd, tid, entity)
}

/*
    Adds a relationship between two entities.
*/
world_add_relation :: proc(w: ^World, entity: Entity, $Rel: typeid, target: Entity) {
	if !world_is_alive(w, entity) || !world_is_alive(w, target) do return

	term := pair(Rel, target)
	tid := world_resolve_term(w, term)

	// Check if relationship already exists to avoid duplicates in the index
	if world_has_component(w, entity, tid) do return

	// Transition the entity to include the Pair tag
	// Note: Relational Pairs are tags, so we pass nil/0 for data
	_world_transition_type(w, entity, tid, nil, 0, true)

	// Track the relationship for cleanup when target is despawned
	if target not_in w.target_index {
		w.target_index[target] = make([dynamic]Relation_Link, w.allocator)
	}
	append(&w.target_index[target], Relation_Link{entity, tid})
}

/*
    Adds a component to multiple entities.
    Efficiently migrates all entities from the current archetype to the next archetype.
*/
world_add_component_bulk :: proc(w: ^World, entities: []Entity, component: $T) {
	if len(entities) == 0 do return

	tid := typeid_of(T)

	// Fast path: if only one entity, just use standard add
	if len(entities) == 1 {
		world_add_component(w, entities[0], component)
		return
	}

	// Try to avoid full map grouping if all entities are already in the same archetype
	// Just do a quick check on the first entity
	first_arch := w.entities[u32(entities[0].id)].record.arch
	all_same := true
	for i := 1; i < len(entities); i += 1 {
		if w.entities[u32(entities[i].id)].record.arch != first_arch {
			all_same = false
			break
		}
	}

	if all_same {
		_migrate_entities_bulk(w, entities, first_arch, tid, component)
		return
	}

	// Fallback to grouping if entities are in different archetypes
	archetype_groups := make(map[^Archetype][dynamic]Entity, 16, context.temp_allocator)
	defer delete(archetype_groups)

	for e in entities {
		id := u32(e.id)
		if id >= u32(len(w.entities)) || w.entities[id].gen != u32(e.gen) do continue

		arch := w.entities[id].record.arch
		if arch not_in archetype_groups {
			archetype_groups[arch] = make([dynamic]Entity, 0, 1024, context.temp_allocator)
		}
		append(&archetype_groups[arch], e)
	}

	for current, group in archetype_groups {
		_migrate_entities_bulk(w, group[:], current, tid, component)
	}
}

@(private)
_migrate_entities_bulk :: proc(
	w: ^World,
	entities: []Entity,
	current: ^Archetype,
	tid: typeid,
	component: $T,
) {
	if tid in current.lookup do return

	edge, has_edge := current.edges[tid]
	if !has_edge {
		world_get_next_archetype(w, current, tid)
		edge = current.edges[tid]
	}
	next := edge.add

	for e in entities {
		meta := &w.entities[e.id]

		new_row := arch_add_entity(next, e)

		// Copy components
		if len(current.columns) > 0 {
			curr_col := 0
			for next_col, i in next.columns {
				if i == int(edge.add_index) {
					((^T)(&(([^]byte)(next_col.ptr))[new_row * next_col.size]))^ = component
					continue
				}
				src_col := current.columns[curr_col]
				mem.copy(
					&(([^]byte)(next_col.ptr))[new_row * next_col.size],
					&(([^]byte)(src_col.ptr))[meta.record.row * src_col.size],
					src_col.size,
				)
				curr_col += 1
			}
		} else {
			next_col := &next.columns[edge.add_index]
			((^T)(&(([^]byte)(next_col.ptr))[new_row * next_col.size]))^ = component
		}

		// Remove from old archetype
		moved_entity, was_moved := arch_remove_row(current, meta.record.row)
		if was_moved {
			w.entities[u32(moved_entity.id)].record.row = meta.record.row
		}

		meta.record.arch = next
		meta.record.row = new_row
		trigger_lifecycle(w, .OnAdd, tid, e)
	}
}

/*
    Removes a component (or relationship pair) from an entity.
*/
world_remove_component :: proc(w: ^World, entity: Entity, tid: typeid) {
	id := u32(entity.id)
	meta := &w.entities[id]
	if meta.gen != u32(entity.gen) do return

	current := meta.record.arch
	if tid not_in current.lookup do return

	trigger_lifecycle(w, .OnRemove, tid, entity)

	// Calculate new Archetype (current - tid)
	new_types := make([dynamic]typeid, context.temp_allocator)
	for t in current.types {
		if t != tid do append(&new_types, t)
	}
	defer delete(new_types)

	h := _get_arch_hash(new_types[:])
	next, ok := w.archetypes[h]
	if !ok {
		next = new(Archetype, w.allocator)
		arch_init(next, new_types[:], w.allocator)
		w.archetypes[h] = next
		world_clear_query_cache(w)
	}

	new_row := arch_add_entity(next, entity)

	// Migrate components
	for t, next_idx in next.types {
		curr_idx := current.lookup[t]
		src_col := current.columns[curr_idx]
		dst_col := next.columns[next_idx]

		mem.copy(
			&(([^]byte)(dst_col.ptr))[new_row * dst_col.size],
			&(([^]byte)(src_col.ptr))[meta.record.row * src_col.size],
			src_col.size,
		)
	}

	moved_entity, was_moved := arch_remove_row(current, meta.record.row)
	if was_moved {
		w.entities[u32(moved_entity.id)].record.row = meta.record.row
	}

	meta.record.arch = next
	meta.record.row = new_row
}

/*
    Helper to check if an entity has a specific type ID.
*/
world_has_component :: proc(w: ^World, entity: Entity, tid: typeid) -> bool #no_bounds_check {
	id := u32(entity.id)
	if int(id) >= len(w.entities) || w.entities[id].gen != u32(entity.gen) do return false

	for col in w.entities[id].record.arch.columns {
		if col.type == tid do return true
	}
	return false
}

/*
	Retrieves a pointer to a component of type T for a given entity.
	Returns nil if the entity doesn't have that component or is not alive.
*/
world_get_component :: proc(w: ^World, entity: Entity, $T: typeid) -> ^T #no_bounds_check {
	id := u32(entity.id)
	if int(id) >= len(w.entities) || w.entities[id].gen != u32(entity.gen) do return nil

	record := w.entities[id].record
	tid := typeid_of(T)

	for &col in record.arch.columns {
		if col.type == tid {
			ptr := ([^]byte)(col.ptr)
			return (^T)(&ptr[record.row * col.size])
		}
	}

	return nil
}

world_get_component_by_id :: proc(
	w: ^World,
	entity: Entity,
	tid: typeid,
) -> rawptr #no_bounds_check {
	id := u32(entity.id)
	if int(id) >= len(w.entities) || w.entities[id].gen != u32(entity.gen) do return nil

	record := w.entities[id].record

	for &col in record.arch.columns {
		if col.type == tid {
			ptr := ([^]byte)(col.ptr)
			return rawptr(&ptr[record.row * col.size])
		}
	}

	return nil
}

/*
	Retrieves raw pointers to all components of an entity and their type IDs
*/
world_get_all_components :: proc(
	w: ^World,
	entity: Entity,
	allocator := context.allocator,
) -> (
	components: []any,
	ok: bool,
) {
	id := u32(entity.id)
	if int(id) >= len(w.entities) || w.entities[id].gen != u32(entity.gen) do return nil, false

	record := w.entities[id].record
	arch := record.arch

	components = make([]any, len(arch.columns), allocator)
	for col, i in arch.columns {
		ptr := ([^]byte)(col.ptr)
		data := &ptr[record.row * col.size]
		components[i] = any {
			data = rawptr(data),
			id   = col.type,
		}
	}

	ok = true
	return
}

/* Wrapper API for the Generic Event System */

/*
	Observes events related to a specific term (component or relationship). The callback is triggered whenever an entity gains or loses that term.
	Returns an Observer_ID that can be used to unobserve later.
*/
observe :: proc(w: ^World, term: any, callback: Observer_Callback) -> events.Observer_ID {
	tid: typeid
	if val, ok := term.(typeid); ok do tid = val
	else if val, ok := term.(Term); ok do tid = world_resolve_term(w, val)

	// Adapter to convert the generic rawptr/u64 callback to World/Entity
	adapter := proc(ctx: rawptr, entity_id: u64, data: rawptr, user_data: rawptr) {
		w := (^World)(ctx)
		cb := cast(Observer_Callback)user_data
		cb(w, transmute(Entity)entity_id)
	}
	return events.register(&w.event_manager, tid, adapter, rawptr(callback))
}

/*
	Subscribes to global events of a specific type T. The callback is triggered whenever an event of that type is emitted.
	Returns an Observer_ID that can be used to unobserve later.
*/
subscribe :: proc(w: ^World, $T: typeid, callback: proc(_: ^World, _: ^T)) -> events.Observer_ID {
	tid := typeid_of(T)
	adapter := proc(ctx: rawptr, entity_id: u64, data: rawptr, user_data: rawptr) {
		w := (^World)(ctx)
		cb := (proc(_: ^World, _: ^T))(user_data)
		cb(w, (^T)(data))
	}
	return events.register(&w.event_manager, tid, adapter, rawptr(callback))
}

/*
	Unregisters an observer or subscriber using its Observer_ID, stopping future callbacks.
*/
unobserve :: proc(w: ^World, id: events.Observer_ID) {
	events.unregister(&w.event_manager, id)
}

@(private)
trigger_lifecycle :: proc(w: ^World, op: Filter_Op, tid: typeid, e: Entity) {
	types := [1]typeid{tid}
	term := Term {
		op    = op,
		types = types[:],
	}
	vid := world_resolve_term(w, term)
	events.trigger(&w.event_manager, w, vid, transmute(u64)e)
}

/* Global Generic Events */
/*
	Emits a global event of type T. All subscribers to that event type will receive the event data.
*/
emit :: proc(w: ^World, event: $T) {
	tid := typeid_of(T)
	val := event
	events.trigger(&w.event_manager, w, tid, 0, &val)
}

@(private)
_query_auto_cleanup :: proc(w: ^World, terms: ..any) {
	w.iteration_depth -= 1
}

@(private)
_query_cleanup_1 :: proc(w: ^World, t1: typeid, terms: ..any) {w.iteration_depth -= 1}
@(private)
_query_cleanup_2 :: proc(w: ^World, t1, t2: typeid, terms: ..any) {w.iteration_depth -= 1}
@(private)
_query_cleanup_3 :: proc(w: ^World, t1, t2, t3: typeid, terms: ..any) {w.iteration_depth -= 1}
@(private)
_query_cleanup_4 :: proc(w: ^World, t1, t2, t3, t4: typeid, terms: ..any) {w.iteration_depth -= 1}
@(private)
_query_cleanup_5 :: proc(
	w: ^World,
	t1, t2, t3, t4, t5: typeid,
	terms: ..any,
) {w.iteration_depth -= 1}
@(private)
_query_cleanup_6 :: proc(
	w: ^World,
	t1, t2, t3, t4, t5, t6: typeid,
	terms: ..any,
) {w.iteration_depth -= 1}
@(private)
_query_cleanup_7 :: proc(
	w: ^World,
	t1, t2, t3, t4, t5, t6, t7: typeid,
	terms: ..any,
) {w.iteration_depth -= 1}
@(private)
_query_cleanup_8 :: proc(
	w: ^World,
	t1, t2, t3, t4, t5, t6, t7, t8: typeid,
	terms: ..any,
) {w.iteration_depth -= 1}

QueryIter :: distinct []^Archetype

/*
    Executes a query against the world, returning a slice of matching archetypes.
    Uses @(deferred_in) to track iteration depth and prevent concurrent structural changes.
*/
query :: proc {
	query_any,
	query_type_1,
	query_type_2,
	query_type_3,
	query_type_4,
	query_type_5,
	query_type_6,
	query_type_7,
	query_type_8,
}

@(deferred_in = _query_auto_cleanup)
query_any :: proc(w: ^World, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	return _query_internal(w, terms)
}

@(deferred_in = _query_cleanup_1)
query_type_1 :: proc(w: ^World, t1: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 1, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	copy(all_terms[1:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_2)
query_type_2 :: proc(w: ^World, t1, t2: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 2, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	copy(all_terms[2:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_3)
query_type_3 :: proc(w: ^World, t1, t2, t3: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 3, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	copy(all_terms[3:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_4)
query_type_4 :: proc(w: ^World, t1, t2, t3, t4: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 4, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	all_terms[3] = t4
	copy(all_terms[4:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_5)
query_type_5 :: proc(w: ^World, t1, t2, t3, t4, t5: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 5, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	all_terms[3] = t4
	all_terms[4] = t5
	copy(all_terms[5:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_6)
query_type_6 :: proc(w: ^World, t1, t2, t3, t4, t5, t6: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 6, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	all_terms[3] = t4
	all_terms[4] = t5
	all_terms[5] = t6
	copy(all_terms[6:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_7)
query_type_7 :: proc(w: ^World, t1, t2, t3, t4, t5, t6, t7: typeid, terms: ..any) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 7, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	all_terms[3] = t4
	all_terms[4] = t5
	all_terms[5] = t6
	all_terms[6] = t7
	copy(all_terms[7:], terms)
	return _query_internal(w, all_terms)
}

@(deferred_in = _query_cleanup_8)
query_type_8 :: proc(
	w: ^World,
	t1, t2, t3, t4, t5, t6, t7, t8: typeid,
	terms: ..any,
) -> QueryIter {
	w.iteration_depth += 1
	all_terms := make([]any, len(terms) + 8, context.temp_allocator)
	defer delete(all_terms, context.temp_allocator)
	all_terms[0] = t1
	all_terms[1] = t2
	all_terms[2] = t3
	all_terms[3] = t4
	all_terms[4] = t5
	all_terms[5] = t6
	all_terms[6] = t7
	all_terms[7] = t8
	copy(all_terms[8:], terms)
	return _query_internal(w, all_terms)
}

@(private)
_query_internal :: proc(w: ^World, terms: []any) -> QueryIter {
	if len(terms) == 0 do return nil

	// 1. Resolve terms to typeids
	tids := make([]typeid, len(terms), context.temp_allocator)
	for t_val, idx in terms {
		if val, ok := t_val.(typeid); ok do tids[idx] = val
		else if val, ok := t_val.(Term); ok do tids[idx] = world_resolve_term(w, val)
	}

	// 2. Sort the typeids to make cache keys order-independent
	if len(tids) > 1 {
		slice.sort_by(tids, proc(i, j: typeid) -> bool {
			return transmute(uintptr)i < transmute(uintptr)j
		})
	}

	// 3. Hash the typeids
	h := hash.fnv64a(slice.to_bytes(tids))

	// 4. Check cache
	sync.mutex_lock(&w.cache_mutex)
	if cached, ok := w.query_cache[h]; ok {
		sync.mutex_unlock(&w.cache_mutex)
		return cached
	}
	sync.mutex_unlock(&w.cache_mutex)

	// 5. Cache miss: evaluate query
	q := query_init(w, terms)
	defer query_destroy(&q)

	results := make([dynamic]^Archetype, context.temp_allocator)

	for _, arch in w.archetypes {
		if query_matches(&q, arch) {
			append(&results, arch)
		}
	}

	sync.mutex_lock(&w.cache_mutex)
	if cached, ok := w.query_cache[h]; ok {
		sync.mutex_unlock(&w.cache_mutex)
		return cached
	}

	// Store in cache (allocated using world allocator)
	cached_iter := make([]^Archetype, len(results), w.allocator)
	copy(cached_iter, results[:])
	iter := cast(QueryIter)cached_iter
	w.query_cache[h] = iter
	sync.mutex_unlock(&w.cache_mutex)

	return iter
}

@(private)
query_matches :: proc(q: ^Query, arch: ^Archetype) -> bool {
	// Must have all "include" components (and concrete Pairs)
	for t in q.include {
		if t not_in arch.lookup do return false
	}

	// Must have none of the "exclude" components
	for t in q.exclude {
		if t in arch.lookup do return false
	}

	// Must have at least one of the "any" components if the list isn't empty
	if len(q.any_) > 0 {
		any_match := false
		for t in q.any_ {
			if t in arch.lookup {
				any_match = true
				break
			}
		}
		if !any_match do return false
	}

	return true
}

@(test)
test_world_basic_operations :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	// Test Spawn
	e1 := world_spawn(&w)
	e2 := world_spawn(&w)
	id1 := e1.id
	id2 := e2.id
	testing.expect_value(t, id1, 0)
	testing.expect_value(t, id2, 1)

	// Test Component Addition
	world_add_component(&w, e1, i32(100))
	world_add_component(&w, e1, f32(200.5))

	// Test Retrieval
	val_i := world_get_component(&w, e1, i32)
	val_f := world_get_component(&w, e1, f32)

	testing.expect(t, val_i != nil)
	testing.expect(t, val_f != nil)

	if val_i != nil do testing.expect_value(t, val_i^, 100)
	if val_f != nil do testing.expect_value(t, val_f^, 200.5)

	// e2 should not have components
	val_none := world_get_component(&w, e2, i32)
	testing.expect(t, val_none == nil)

	testing.expect(t, world_is_alive(&w, e1))
	testing.expect(t, world_is_alive(&w, e2))
	world_despawn(&w, e1)
	testing.expect(t, !world_is_alive(&w, e1))
}

@(test)
test_world_get_all_components :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	e := world_spawn(&w)
	world_add_component(&w, e, i32(42))
	world_add_component(&w, e, f32(3.14))

	comps, ok := world_get_all_components(&w, e)
	defer delete(comps)

	testing.expect(t, ok)
	testing.expect_value(t, len(comps), 2)

	found_i32, found_f32 := false, false
	for c in comps {
		switch c.id {
		case i32:
			testing.expect_value(t, (^i32)(c.data)^, 42)
			found_i32 = true
		case f32:
			testing.expect_value(t, (^f32)(c.data)^, 3.14)
			found_f32 = true
		}
	}
	testing.expect(t, found_i32 && found_f32)
}

@(test)
test_world_despawn :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	e := world_spawn(&w)
	world_add_component(&w, e, i32(100))

	// Ensure it exists
	testing.expect(t, world_get_component(&w, e, i32) != nil)

	// Despawn
	testing.expect(t, world_is_alive(&w, e))
	world_despawn(&w, e)
	testing.expect(t, !world_is_alive(&w, e))

	// Ensure it is gone
	testing.expect(t, world_get_component(&w, e, i32) == nil)
	testing.expect_value(t, len(w.free_list), 1)

	// Test ID reuse with new generation
	e_new := world_spawn(&w)
	id_old, gen_old := e.id, e.gen
	id_new, gen_new := e_new.id, e_new.gen

	testing.expect_value(t, id_new, id_old)
	testing.expect(t, gen_new > gen_old)

	// Old handle should still fail
	testing.expect(t, world_get_component(&w, e, i32) == nil)

	world_add_component(&w, e_new, i32(200))
	testing.expect_value(t, world_get_component(&w, e_new, i32)^, 200)
}

@(test)
test_world_relations :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	e1 := world_spawn(&w)
	e2 := world_spawn(&w)

	world_add_relation(&w, e1, ChildOf, e2)
}
