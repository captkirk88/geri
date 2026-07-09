#+feature dynamic-literals using-stmt
package params

import ecs ".."

// Deferred commands buffer. Flushed automatically to the World after the system runs.
Commands :: struct {
	ptr: ^ecs.Commands,
}

// Access a global resource of type T. Modifications are applied instantly.
Res :: struct($T: typeid) {
	ptr: ^T,
}

// Local buffer for emitting events of type T. Flushed automatically to the World after the system runs.
EventWriter :: struct($T: typeid) {
	_events: [dynamic]T,
	events:  ^[dynamic]T,
}

// Idiomatic Odin helper to write events to an Event_Writer.
// Usage: params.write(writer, MyEvent(5))
write :: #force_inline proc(writer: EventWriter($T), event: T) {
	append(writer.events, event)
}

// Read events of type T emitted since the last system run. Backed by temporary memory valid for the current frame.
EventReader :: struct($T: typeid) {
	events:      []T,
	_cursor:     int,
	_generation: int,
}

// Receive a value piped in from a preceding pipe() composite system.
// Zero-initialized when no pipe is active.
In :: struct($T: typeid) {
	value: T,
}

// Local is unique to the system that uses it
// TODO
Local :: struct($T: typeid) {
	value: ^T,
	_hash: u64,
}

// Trigger when a component is added to any entity
OnAdded :: struct($T: typeid) {
	entities:    []ecs.Entity,
	_cursor:     int,
	_phantom:    ^T,
	_generation: int,
}

// Trigger when a component is removed from any entity
OnRemoved :: struct($T: typeid) {
	entities:    []ecs.Entity,
	_cursor:     int,
	_phantom:    ^T,
	_generation: int,
}

// Query but only expects 1 result
Single :: struct($T: typeid) {
	entity:   ecs.Entity,
	value:    ^T,
	_phantom: ^T,
}

@(private)
None :: struct {}

With :: struct($T: typeid) {
	_phantom: ^T,
}

Without :: struct($T: typeid) {
	_phantom: ^T,
}

Or :: struct($T1: typeid, $T2: typeid) {
	_phantom: ^struct {
		t1: ^T1,
		t2: ^T2,
	},
}


Query :: struct($T: typeid) {
	_world:   ^ecs.World,
	state:    ^ecs.Query_State,
	_phantom: ^T,
}

query :: proc(q: Query($T)) -> ecs.QueryIter {
	if q.state.epoch == q.state.world.query_cache_epoch {
		return q.state.cached_res
	}
	q.state.cached_res = ecs.query_by_lists_and_hash(
		q.state.world,
		q.state.hash,
		q.state.include[:],
		q.state.exclude[:],
		q.state.any_[:],
	)
	q.state.epoch = q.state.world.query_cache_epoch
	return q.state.cached_res
}
