package ecs

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:testing"

Serializer_Procs :: struct {
	serialize:     proc(ptr: rawptr, allocator: runtime.Allocator) -> ([]byte, json.Marshal_Error),
	deserialize:   proc(ptr: rawptr, data: []byte) -> json.Unmarshal_Error,
	add_to_entity: proc(w: ^World, entity: Entity, data: []byte) -> json.Unmarshal_Error,
}

Resource_Serializer_Procs :: struct {
	serialize:          proc(
		w: ^World,
		allocator: runtime.Allocator,
	) -> (
		[]byte,
		json.Marshal_Error,
	),
	deserialize_or_add: proc(w: ^World, data: []byte) -> json.Unmarshal_Error,
}

Serialization_Error :: enum {
	None,
	Entity_Not_Alive,
	Type_Not_Registered,
	JSON_Marshal_Error,
	JSON_Unmarshal_Error,
	Resource_Not_Found,
}

world_register_component :: proc(w: ^World, $T: typeid) {
	tid := typeid_of(T)

	s_proc := proc(ptr: rawptr, allocator: runtime.Allocator) -> ([]byte, json.Marshal_Error) {
		val := (^T)(ptr)
		return json.marshal(val^, allocator = allocator)
	}
	d_proc := proc(ptr: rawptr, data: []byte) -> json.Unmarshal_Error {
		val := (^T)(ptr)
		return json.unmarshal(data, val)
	}
	a_proc := proc(w: ^World, entity: Entity, data: []byte) -> json.Unmarshal_Error {
		comp := T{}
		err := json.unmarshal(data, &comp)
		if err != nil do return err
		world_add_component(w, entity, comp)
		return nil
	}

	w.serialization_procs[tid] = Serializer_Procs {
		serialize     = s_proc,
		deserialize   = d_proc,
		add_to_entity = a_proc,
	}

	name_clone := strings.clone(fmt.tprint(tid), w.allocator)
	w.serialization_names[name_clone] = tid
	w.serialization_types[tid] = name_clone
}

world_serialize_entity :: proc(
	w: ^World,
	entity: Entity,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: Serialization_Error,
) {
	if !world_is_alive(w, entity) do return nil, .Entity_Not_Alive

	// Get all components of this entity
	comps, ok := world_get_all_components(w, entity, context.temp_allocator)
	if !ok do return nil, .Entity_Not_Alive
	defer delete(comps, context.temp_allocator)

	json_map := make(map[string]json.Value, context.temp_allocator)
	defer delete(json_map)

	for comp in comps {
		tid := comp.id
		procs, registered := w.serialization_procs[tid]
		if !registered do continue // skip unregistered components

		name := w.serialization_types[tid]

		comp_bytes, m_err := procs.serialize(comp.data, context.temp_allocator)
		if m_err != nil do return nil, .JSON_Marshal_Error

		val, p_err := json.parse(comp_bytes, allocator = context.temp_allocator)
		if p_err != nil do return nil, .JSON_Unmarshal_Error

		json_map[name] = val
	}

	entity_map := make(map[string]json.Value, context.temp_allocator)
	defer delete(entity_map)

	entity_map["id"] = json.Integer(entity.id)
	entity_map["gen"] = json.Integer(entity.gen)
	entity_map["components"] = json.Object(json_map)

	res_bytes, m_err := json.marshal(json.Object(entity_map), allocator = allocator)
	if m_err != nil do return nil, .JSON_Marshal_Error

	return res_bytes, .None
}

/*
Patches an entity with the provided JSON data. If a component exists on the entity, it will be deserialized and updated. If it doesn't exist, it will be added to the entity.

Notable usage of this function is for network synchronization or applying saved patches to existing entities without needing to fully deserialize/respawn them.  Implementing your own hotpatching is also possible with this function, but users should be careful to ensure that the JSON data being patched is compatible with the current component definitions to avoid deserialization errors.
*/
world_patch_entity :: proc(w: ^World, entity: Entity, data: []byte) -> Serialization_Error {
	if !world_is_alive(w, entity) do return .Entity_Not_Alive

	root_val, p_err := json.parse(data, allocator = context.temp_allocator)
	if p_err != nil do return .JSON_Unmarshal_Error

	root_obj, is_obj := root_val.(json.Object)
	if !is_obj do return .JSON_Unmarshal_Error

	comps_val, has_comps := root_obj["components"]
	if !has_comps do return .None // Nothing to patch

	comps_obj, comps_is_obj := comps_val.(json.Object)
	if !comps_is_obj do return .JSON_Unmarshal_Error

	for name, comp_val in comps_obj {
		tid, registered := w.serialization_names[name]
		if !registered do return .Type_Not_Registered

		procs := w.serialization_procs[tid]

		comp_bytes, m_err := json.marshal(comp_val, allocator = context.temp_allocator)
		if m_err != nil do return .JSON_Marshal_Error

		if world_has_component(w, entity, tid) {
			ptr := world_get_component_by_id(w, entity, tid)
			if ptr == nil do return .Entity_Not_Alive
			d_err := procs.deserialize(ptr, comp_bytes)
			if d_err != nil do return .JSON_Unmarshal_Error
		} else {
			d_err := procs.add_to_entity(w, entity, comp_bytes)
			if d_err != nil do return .JSON_Unmarshal_Error
		}
	}

	return .None
}

world_serialize_resource :: proc(
	w: ^World,
	$T: typeid,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: Serialization_Error,
) {
	ptr := world_get_resource(w, T)
	if ptr == nil do return nil, .Resource_Not_Found
	bytes, m_err := json.marshal(ptr^, allocator = allocator)
	if m_err != nil do return nil, .JSON_Marshal_Error
	return bytes, .None
}

world_deserialize_resource :: proc(w: ^World, $T: typeid, data: []byte) -> Serialization_Error {
	ptr := world_get_resource(w, T)
	if ptr == nil {
		res := T{}
		u_err := json.unmarshal(data, &res)
		if u_err != nil do return .JSON_Unmarshal_Error
		world_add_resource(w, res)
		return .None
	}

	u_err := json.unmarshal(data, ptr)
	if u_err != nil do return .JSON_Unmarshal_Error
	return .None
}

world_register_resource_serialization :: proc(w: ^World, $T: typeid) {
	tid := typeid_of(T)

	s_proc := proc(w: ^World, allocator: runtime.Allocator) -> ([]byte, json.Marshal_Error) {
		ptr := world_get_resource(w, T)
		if ptr == nil do return nil, .Unsupported_Type
		return json.marshal(ptr^, allocator = allocator)
	}

	d_proc := proc(w: ^World, data: []byte) -> json.Unmarshal_Error {
		ptr := world_get_resource(w, T)
		if ptr == nil {
			res := T{}
			err := json.unmarshal(data, &res)
			if err != nil do return err
			world_add_resource(w, res)
			return nil
		}
		return json.unmarshal(data, ptr)
	}

	w.resource_serialization_procs[tid] = Resource_Serializer_Procs {
		serialize          = s_proc,
		deserialize_or_add = d_proc,
	}

	name_clone := strings.clone(fmt.tprint(tid), w.allocator)
	w.resource_serialization_names[name_clone] = tid
	w.resource_serialization_types[tid] = name_clone
}

world_serialize_all_resources :: proc(
	w: ^World,
	allocator := context.allocator,
) -> (
	data: []byte,
	err: Serialization_Error,
) {
	json_map := make(map[string]json.Value, context.temp_allocator)
	defer delete(json_map)

	for tid, procs in w.resource_serialization_procs {
		name := w.resource_serialization_types[tid]
		bytes, m_err := procs.serialize(w, context.temp_allocator)
		if m_err != nil do continue // skip if resource doesn't exist

		val, p_err := json.parse(bytes, allocator = context.temp_allocator)
		if p_err != nil do return nil, .JSON_Unmarshal_Error

		json_map[name] = val
	}

	res_bytes, m_err := json.marshal(json.Object(json_map), allocator = allocator)
	if m_err != nil do return nil, .JSON_Marshal_Error

	return res_bytes, .None
}

world_deserialize_all_resources :: proc(w: ^World, data: []byte) -> Serialization_Error {
	root_val, p_err := json.parse(data, allocator = context.temp_allocator)
	if p_err != nil do return .JSON_Unmarshal_Error

	root_obj, is_obj := root_val.(json.Object)
	if !is_obj do return .JSON_Unmarshal_Error

	for name, res_val in root_obj {
		tid, registered := w.resource_serialization_names[name]
		if !registered do return .Type_Not_Registered

		procs := w.resource_serialization_procs[tid]

		bytes, m_err := json.marshal(res_val, allocator = context.temp_allocator)
		if m_err != nil do return .JSON_Marshal_Error

		d_err := procs.deserialize_or_add(w, bytes)
		if d_err != nil do return .JSON_Unmarshal_Error
	}

	return .None
}

@(test)
test_serialization :: proc(t: ^testing.T) {
	w := new_world()
	defer world_destroy(&w)

	Test_Comp_A :: struct {
		x: f32,
		y: i32,
	}

	Test_Comp_B :: struct {
		name:   string,
		active: bool,
	}

	Test_Res :: struct {
		score: int,
	}

	world_register_component(&w, Test_Comp_A)
	world_register_component(&w, Test_Comp_B)
	world_register_resource_serialization(&w, Test_Res)

	// Test Entity Serialization/Patching
	e := world_spawn(&w)
	world_add_component(&w, e, Test_Comp_A{x = 1.23, y = 42})
	world_add_component(&w, e, Test_Comp_B{name = "Geri", active = true})

	data, err := world_serialize_entity(&w, e)
	testing.expect_value(t, err, Serialization_Error.None)
	defer delete(data)

	// Despawn/modify or create new entity to patch
	e2 := world_spawn(&w)
	// Add only component A with different values
	world_add_component(&w, e2, Test_Comp_A{x = 0, y = 0})

	err_patch := world_patch_entity(&w, e2, data)
	testing.expect_value(t, err_patch, Serialization_Error.None)

	comp_a := world_get_component(&w, e2, Test_Comp_A)
	comp_b := world_get_component(&w, e2, Test_Comp_B)

	testing.expect(t, comp_a != nil)
	testing.expect_value(t, comp_a.x, f32(1.23))
	testing.expect_value(t, comp_a.y, i32(42))

	testing.expect(t, comp_b != nil)
	testing.expect_value(t, comp_b.name, "Geri")
	testing.expect_value(t, comp_b.active, true)
	if comp_b != nil do delete(comp_b.name)

	// Test Resource Serialization/Deserialization
	world_add_resource(&w, Test_Res{score = 9001})

	// Dynamic/registered resource serialization
	res_data, res_err := world_serialize_all_resources(&w)
	testing.expect_value(t, res_err, Serialization_Error.None)
	defer delete(res_data)

	// Modify resource
	res_ptr := world_get_resource(&w, Test_Res)
	testing.expect(t, res_ptr != nil)
	res_ptr.score = 0

	// Patch resource
	res_patch_err := world_deserialize_all_resources(&w, res_data)
	testing.expect_value(t, res_patch_err, Serialization_Error.None)
	testing.expect_value(t, res_ptr.score, 9001)

	// Compile-time/generic resource serialization/deserialization
	res_data_generic, res_err_generic := world_serialize_resource(&w, Test_Res)
	testing.expect_value(t, res_err_generic, Serialization_Error.None)
	defer delete(res_data_generic)

	res_ptr.score = 123
	res_patch_generic_err := world_deserialize_resource(&w, Test_Res, res_data_generic)
	testing.expect_value(t, res_patch_generic_err, Serialization_Error.None)
	testing.expect_value(t, res_ptr.score, 9001)
}
