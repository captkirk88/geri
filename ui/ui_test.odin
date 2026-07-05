package ui

import "core:testing"
import "base:runtime"
import "../ecs"

@(test)
test_ui_cascading_despawn :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)

	// Initialize UI observers and state
	state: UI_State
	ui_state_init(&state)
	ecs.world_add_resource(&w, state, proc(s: ^UI_State, alloc: runtime.Allocator) {
		ui_state_destroy(s)
	})
	
	ui_observer_init(&w)

	parent := ecs.world_spawn(&w)
	ecs.world_add_component(&w, parent, UI_Node{})

	child := ecs.world_spawn(&w)
	ecs.world_add_component(&w, child, UI_Node{})

	ecs.world_add_relation(&w, child, ecs.ChildOf, parent)

	testing.expect(t, ecs.world_is_alive(&w, parent))
	testing.expect(t, ecs.world_is_alive(&w, child))

	// Despawning parent should cascadingly despawn child
	ecs.world_despawn(&w, parent)
	ui_process_deferred_despawns(&w)

	testing.expect(t, !ecs.world_is_alive(&w, parent))
	testing.expect(t, !ecs.world_is_alive(&w, child))
}
