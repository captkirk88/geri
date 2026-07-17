package ui

import "../ecs"
import "base:runtime"
import "core:testing"

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

	ecs.world_add_relation(&w, child, UI_ChildOf, parent)

	testing.expect(t, ecs.world_is_alive(&w, parent))
	testing.expect(t, ecs.world_is_alive(&w, child))

	// Despawning parent should cascadingly despawn child
	ecs.world_despawn(&w, parent)
	ui_process_deferred_despawns(&w)

	testing.expect(t, !ecs.world_is_alive(&w, parent))
	testing.expect(t, !ecs.world_is_alive(&w, child))
}

@(test)
test_ui_canvas_components_lifecycle :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)

	state: UI_State
	ui_state_init(&state)
	ecs.world_add_resource(&w, state, proc(s: ^UI_State, alloc: runtime.Allocator) {
		ui_state_destroy(s)
	})

	ui_observer_init(&w)

	canvas_entity := ecs.world_spawn(&w)
	ecs.world_add_component(
		&w,
		canvas_entity,
		UI_Canvas {
			render_mode = .World_Space,
			reference_size = {800, 600},
			world_size = {2.0, 1.5},
		},
	)

	canvas := ecs.world_get_component(&w, canvas_entity, UI_Canvas)
	testing.expect(t, canvas != nil)
	testing.expect_value(t, canvas.render_mode, UI_Canvas_Render_Mode.World_Space)
	testing.expect_value(t, canvas.reference_size, [2]f32{800, 600})

	// Add UI_Canvas_Target (with nil device/context this won't allocate WGPU but won't crash)
	ecs.world_add_component(&w, canvas_entity, UI_Canvas_Target{})
	target := ecs.world_get_component(&w, canvas_entity, UI_Canvas_Target)
	testing.expect(t, target != nil)

	ecs.world_remove_component(&w, canvas_entity, UI_Canvas_Target)
}
