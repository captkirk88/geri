package ecs

import reflect "../reflect"
import "base:runtime"
import "core:log"
import "core:testing"

/*
    Adds or updates a global resource in the world.
*/
world_add_resource_no_destroy :: proc(w: ^World, resource: $T) {
	world_add_resource_with_destroy(w, resource, nil)
}

world_add_resource_with_destroy :: proc(
	w: ^World,
	resource: $T,
	destroy: proc(_: ^T, _: runtime.Allocator),
) {
	tid := typeid_of(T)

	if reflect.is_pointer_type(runtime.type_info_base(type_info_of(T))) {
		log.panic(
			"Pointer types cannot be used as resources. Use a struct containing the pointer instead.",
		)
	}

	if ptr, ok := w.resources[tid]; ok {
		if dest, ok_dest := w.resource_destructors[tid]; ok_dest {
			if dest.destroy_proc != nil && dest.wrapper != nil {
				dest.wrapper(dest.destroy_proc, ptr, w.allocator)
			}
		}
		((^T)(ptr))^ = resource
		w.resource_destructors[tid] = Resource_Destructor {
			destroy_proc = rawptr(destroy),
			wrapper = proc(destroy_proc: rawptr, ptr: rawptr, allocator: runtime.Allocator) {
				typed_destroy := (proc(_: ^T, _: runtime.Allocator))(destroy_proc)
				if typed_destroy != nil {
					typed_destroy((^T)(ptr), allocator)
				}
			},
		}
		return
	}

	ptr := new(T, w.allocator)
	ptr^ = resource
	w.resources[tid] = rawptr(ptr)

	w.resource_destructors[tid] = Resource_Destructor {
		destroy_proc = rawptr(destroy),
		wrapper = proc(destroy_proc: rawptr, ptr: rawptr, allocator: runtime.Allocator) {
			typed_destroy := (proc(_: ^T, _: runtime.Allocator))(destroy_proc)
			if typed_destroy != nil {
				typed_destroy((^T)(ptr), allocator)
			}
		},
	}
}

world_add_resource :: proc {
	world_add_resource_no_destroy,
	world_add_resource_with_destroy,
}

/*
    Retrieves a pointer to a global resource.
*/
world_get_resource :: proc(w: ^World, $T: typeid) -> ^T {
	tid := typeid_of(T)
	if ptr, ok := w.resources[tid]; ok {
		return (^T)(ptr)
	}
	return nil
}

/*
    Removes a resource and frees its memory.
*/
world_remove_resource :: proc(w: ^World, $T: typeid) {
	tid := typeid_of(T)
	if ptr, ok := w.resources[tid]; ok {
		if dest, ok_dest := w.resource_destructors[tid]; ok_dest {
			if dest.destroy_proc != nil && dest.wrapper != nil {
				dest.wrapper(dest.destroy_proc, ptr, w.allocator)
			}
			delete_key(&w.resource_destructors, tid)
		}
		free(ptr, w.allocator)
		delete_key(&w.resources, tid)
	}
}

@(test)
test_world_resources :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	world_add_resource(&w, i32(42))
	res := world_get_resource(&w, i32)
	testing.expect(t, res != nil)
	testing.expect_value(t, res^, 42)

	world_remove_resource(&w, i32)
	res_after := world_get_resource(&w, i32)
	testing.expect(t, res_after == nil)
}

Test_Destructor_Resource :: struct {
	destroyed:        ^bool,
	allocator_passed: ^runtime.Allocator,
}

@(test)
test_resource_destructor :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	// Test 1: Destructor called on world_remove_resource
	destroyed_1 := false
	alloc_passed_1: runtime.Allocator
	world_add_resource(
		&w,
		Test_Destructor_Resource{&destroyed_1, &alloc_passed_1},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)
	testing.expect(t, !destroyed_1, "Should not be destroyed yet")
	world_remove_resource(&w, Test_Destructor_Resource)
	testing.expect(t, destroyed_1, "Should be destroyed")
	testing.expect(t, alloc_passed_1 == w.allocator, "Should pass world allocator")

	// Test 2: Destructor called when overwriting resource
	destroyed_2a := false
	alloc_passed_2a: runtime.Allocator
	world_add_resource(
		&w,
		Test_Destructor_Resource{&destroyed_2a, &alloc_passed_2a},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)

	destroyed_2b := false
	alloc_passed_2b: runtime.Allocator
	// Overwrite resource
	world_add_resource(
		&w,
		Test_Destructor_Resource{&destroyed_2b, &alloc_passed_2b},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)
	testing.expect(t, destroyed_2a, "Old resource should be destroyed")
	testing.expect(t, !destroyed_2b, "New resource should not be destroyed yet")
	world_remove_resource(&w, Test_Destructor_Resource)
	testing.expect(t, destroyed_2b, "New resource should be destroyed")

	// Test 3: Destructor called on world_destroy
	destroyed_3 := false
	alloc_passed_3: runtime.Allocator
	w_temp := new_world()
	world_add_resource(
		&w_temp,
		Test_Destructor_Resource{&destroyed_3, &alloc_passed_3},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)
	world_destroy(&w_temp)
	testing.expect(t, destroyed_3, "Resource should be destroyed on world_destroy")

	// Test 4: Destructor called with commands_add_resource and flush
	w2 := new_world()
	cmds := commands_init(w2.allocator)
	destroyed_4 := false
	alloc_passed_4: runtime.Allocator
	commands_add_resource(
		&cmds,
		Test_Destructor_Resource{&destroyed_4, &alloc_passed_4},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)
	testing.expect(t, !destroyed_4, "Not destroyed during command buffering")
	commands_flush(&cmds, &w2)
	testing.expect(t, !destroyed_4, "Not destroyed after flush (ownership moved to world)")
	world_destroy(&w2)
	testing.expect(t, destroyed_4, "Destroyed when world is destroyed")
	commands_destroy(&cmds)

	// Test 5: Destructor called if command buffer is destroyed without flush
	w3 := new_world()
	cmds2 := commands_init(w3.allocator)
	destroyed_5 := false
	alloc_passed_5: runtime.Allocator
	commands_add_resource(
		&cmds2,
		Test_Destructor_Resource{&destroyed_5, &alloc_passed_5},
		proc(res: ^Test_Destructor_Resource, alloc: runtime.Allocator) {
			res.destroyed^ = true
			res.allocator_passed^ = alloc
		},
	)
	commands_destroy(&cmds2)
	testing.expect(t, destroyed_5, "Destroyed when command queue is destroyed")
	testing.expect(t, alloc_passed_5 == w3.allocator, "Should pass world allocator")
	world_destroy(&w3)
}
