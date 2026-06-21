package events

import "base:runtime"
import "core:sync"
import "core:mem"
import reflect "../../reflect"

Observer_ID :: distinct u32

// Generic callback signature: (context, entity_id, optional_data)
Observer_Callback :: #type proc(ctx: rawptr, entity: u64, data: rawptr, user_data: rawptr)

Observer_Entry :: struct {
	id:       Observer_ID,
	callback: Observer_Callback,
	user_data: rawptr,
}

@(private)
Event_Buffer :: struct {
	data:       [dynamic]byte,
	event_size: int,
}

Event_Manager :: struct {
	// Groups observers by type (Component/Event) and Kind for cache locality
	registry:  map[typeid][dynamic]Observer_Entry,
	history:   map[typeid]Event_Buffer,
	lock:      sync.RW_Mutex,
	next_id:   u32,
	allocator: runtime.Allocator,
}

init :: proc(m: ^Event_Manager, allocator := context.allocator) {
	m.allocator = allocator
	m.registry = make(map[typeid][dynamic]Observer_Entry, 16, allocator)
	m.history = make(map[typeid]Event_Buffer, 16, allocator)
}

destroy :: proc(m: ^Event_Manager) {
	for _, list in m.registry {
		delete(list)
	}
	delete(m.registry)
	for _, buf in m.history {
		delete(buf.data)
	}
	delete(m.history)
}

register :: proc(
	m: ^Event_Manager,
	tid: typeid,
	callback: Observer_Callback,
	user_data: rawptr = nil,
) -> Observer_ID {
	sync.rw_mutex_lock(&m.lock)
	defer sync.rw_mutex_unlock(&m.lock)

	m.next_id += 1
	id := Observer_ID(m.next_id)

	if m.registry[tid].allocator.procedure == nil {
		m.registry[tid] = make([dynamic]Observer_Entry, m.allocator)
	}

	append(&m.registry[tid], Observer_Entry{id, callback, user_data})
	return id
}

unregister :: proc(m: ^Event_Manager, id: Observer_ID) {
	sync.rw_mutex_lock(&m.lock)
	defer sync.rw_mutex_unlock(&m.lock)

	for _, &list in m.registry {
		for entry, i in list {
			if entry.id == id {
				unordered_remove(&list, i)
				return
			}
		}
	}
}

trigger :: proc(
	m: ^Event_Manager,
	ctx: rawptr,
	tid: typeid,
	entity: u64,
	data: rawptr = nil,
) {
	// 1. Handle Global Event Storage (History)
	sync.rw_mutex_lock(&m.lock)
	if data != nil {
		if tid not_in m.history {
			m.history[tid] = {
				data       = make([dynamic]byte, m.allocator),
				event_size = reflect.size_of_type(tid),
			}
		}
		buf := &m.history[tid]
		bytes := mem.slice_ptr(cast(^byte)data, buf.event_size)
		append(&buf.data, ..bytes)
	}
	sync.rw_mutex_unlock(&m.lock)

	// 2. Trigger Immediate Observers
	sync.rw_mutex_shared_lock(&m.lock)
	if list, ok := m.registry[tid]; ok {
		if len(list) > 0 {
			entries := make([]Observer_Entry, len(list), context.temp_allocator)
			copy(entries, list[:])
			sync.rw_mutex_shared_unlock(&m.lock)

			for entry in entries {
				entry.callback(ctx, entity, data, entry.user_data)
			}
			return
		}
	}
	sync.rw_mutex_shared_unlock(&m.lock)
}

clear_events :: proc(m: ^Event_Manager) {
	sync.rw_mutex_lock(&m.lock)
	defer sync.rw_mutex_unlock(&m.lock)
	for _, &buf in m.history {
		clear(&buf.data)
	}
}
