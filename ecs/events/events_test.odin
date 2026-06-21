package events

import "core:testing"
import "core:mem"

My_Event :: struct {
	val: int,
}

Another_Event :: struct {
	msg: string,
}

Test_State :: struct {
	count:  int,
	entity: u64,
	val:    int,
}

my_event_callback :: proc(ctx: rawptr, entity: u64, data: rawptr, user_data: rawptr) {
	state := cast(^Test_State)user_data
	state.count += 1
	state.entity = entity
	if data != nil {
		event := cast(^My_Event)data
		state.val = event.val
	}
}

@(test)
test_event_observability :: proc(t: ^testing.T) {
	m: Event_Manager
	init(&m, context.allocator)
	defer destroy(&m)

	state := Test_State{}

	id := register(&m, My_Event, my_event_callback, &state)
	testing.expect(t, id != 0, "Observer ID should be non-zero")

	ev := My_Event{val = 42}
	trigger(&m, nil, My_Event, 100, &ev)

	testing.expect_value(t, state.count, 1)
	testing.expect_value(t, state.entity, 100)
	testing.expect_value(t, state.val, 42)
}

@(test)
test_event_dependability_unregister :: proc(t: ^testing.T) {
	m: Event_Manager
	init(&m, context.allocator)
	defer destroy(&m)

	state1 := Test_State{}
	state2 := Test_State{}

	id1 := register(&m, My_Event, my_event_callback, &state1)
	id2 := register(&m, My_Event, my_event_callback, &state2)

	ev := My_Event{val = 10}
	trigger(&m, nil, My_Event, 101, &ev)

	testing.expect_value(t, state1.count, 1)
	testing.expect_value(t, state2.count, 1)

	unregister(&m, id1)

	state1.count = 0
	state2.count = 0
	trigger(&m, nil, My_Event, 102, &ev)

	testing.expect_value(t, state1.count, 0)
	testing.expect_value(t, state2.count, 1)
}

@(test)
test_event_history :: proc(t: ^testing.T) {
	m: Event_Manager
	init(&m, context.allocator)
	defer destroy(&m)

	ev1 := My_Event{val = 1}
	ev2 := My_Event{val = 2}

	trigger(&m, nil, My_Event, 104, &ev1)
	trigger(&m, nil, My_Event, 105, &ev2)

	// Check history
	testing.expect(t, My_Event in m.history, "My_Event should exist in history")
	buf := m.history[My_Event]
	testing.expect_value(t, buf.event_size, size_of(My_Event))
	testing.expect_value(t, len(buf.data), size_of(My_Event) * 2)

	// Verify history data contents
	events_slice := mem.slice_data_cast([]My_Event, buf.data[:])
	testing.expect_value(t, events_slice[0].val, 1)
	testing.expect_value(t, events_slice[1].val, 2)

	// Clear history
	clear_events(&m)
	testing.expect_value(t, len(m.history[My_Event].data), 0)
}
