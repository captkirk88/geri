package reflect_utils

import "base:runtime"

// Generic helper for match procs: checks if a type is a struct with a specific field.
match_struct_field :: proc(
	info: ^runtime.Type_Info,
	field_name: string,
	field_count: int = -1,
) -> bool {
	s, ok := info.variant.(runtime.Type_Info_Struct)
	if !ok {return false}

	if field_count != -1 && int(s.field_count) != field_count {return false}

	for i in 0 ..< s.field_count {
		if s.names[i] == field_name {return true}
	}
	return false
}

// Generic helper for build procs: casts a rawptr to a pointer of type T and assigns a value.
assign_ptr_value :: proc(ptr: rawptr, value: $T) {
	((^T)(ptr))^ = value
}

// Generic helper for build procs: gets the element type of a pointer field within a struct.
get_pointer_elem_type :: proc(
	struct_info: runtime.Type_Info_Struct,
	field_index: int,
) -> typeid {
	ptr_info := struct_info.types[field_index].variant.(runtime.Type_Info_Pointer)
	return ptr_info.elem.id
}

// Generic helper for build procs: gets the element type of a slice field within a struct.
get_slice_elem_type :: proc(
	struct_info: runtime.Type_Info_Struct,
	field_index: int,
) -> typeid {
	slice_info := struct_info.types[field_index].variant.(runtime.Type_Info_Slice)
	return slice_info.elem.id
}

// Generic helper for build procs: gets the element type of a dynamic array field within a struct.
get_dynamic_array_elem_type :: proc(
	struct_info: runtime.Type_Info_Struct,
	field_index: int,
) -> typeid {
	dyn_info := struct_info.types[field_index].variant.(runtime.Type_Info_Dynamic_Array)
	return dyn_info.elem.id
}

// Helper to determine if a type info represents any kind of pointer.
is_pointer_type :: proc(ti: ^runtime.Type_Info) -> bool {
	#partial switch _ in ti.variant {
	case runtime.Type_Info_Pointer, runtime.Type_Info_Multi_Pointer, runtime.Type_Info_Soa_Pointer:
		return true
	case:
		return false
	}
}

// Get the size of a typeid
size_of_type :: proc(tid: typeid) -> int {
	return runtime.type_info_base(type_info_of(tid)).size
}

// Get procedure parameters type info
get_procedure_params :: proc(info: ^runtime.Type_Info) -> (runtime.Type_Info_Parameters, bool) {
	if fn_ti, is_proc := info.variant.(runtime.Type_Info_Procedure); is_proc {
		if fn_ti.params != nil {
			if params_info, ok := fn_ti.params.variant.(runtime.Type_Info_Parameters); ok {
				return params_info, true
			}
		}
	}
	return {}, false
}

// Get base type info from a typeid
base_info_of :: proc(tid: typeid) -> ^runtime.Type_Info {
	return runtime.type_info_base(type_info_of(tid))
}
