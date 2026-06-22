package ecs

import "base:runtime"
import "core:testing"
import reflect "../reflect"

/*
    Adds or updates a global resource in the world.
*/
world_add_resource :: proc(w: ^World, resource: $T) {
	tid := typeid_of(T)
	
	if reflect.is_pointer_type(runtime.type_info_base(type_info_of(T))) {
		panic("Pointer types cannot be used as resources. Use a struct containing the pointer instead.")
	}
	
	if ptr, ok := w.resources[tid]; ok {
		((^T)(ptr))^ = resource
		return
	}

	ptr := new(T, w.allocator)
	ptr^ = resource
	w.resources[tid] = rawptr(ptr)
	
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