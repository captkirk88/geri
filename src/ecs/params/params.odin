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
	events: ^[dynamic]T,
}

// Idiomatic Odin helper to write events to an Event_Writer.
// Usage: params.write(writer, MyEvent(5))
write :: #force_inline proc(writer: EventWriter($T), event: T) {
	append(writer.events, event)
}

// Read events of type T emitted since the last system run. Backed by temporary memory valid for the current frame.
EventReader :: struct($T: typeid) {
	events: []T,
	_cursor: int,
}

// Receive a value piped in from a preceding pipe() composite system.
// Zero-initialized when no pipe is active.
In :: struct($T: typeid) {
	value: T,
}

