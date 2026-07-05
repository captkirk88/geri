package systems

import ecs ".."
import events "../events"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:slice"
import "ecs:params"

import "core:testing"

System_Runner :: #type proc(sys: ^System, data: rawptr)

System_Param_Resolve :: struct {
	builder:   ecs.System_Param_Builder,
	base_info: ^runtime.Type_Info,
	offset:    uintptr,
}

System :: struct {
	id:                u64,
	procedure:         rawptr,
	runner:            System_Runner,
	params_type:       typeid,
	params_data:       rawptr,
	commands:          ecs.Commands,
	resolved_params:   [dynamic]System_Param_Resolve,
	resolved:          bool,
	// Active world during execution (set by build_system before each run)
	world:             ^ecs.World,
	// Captures a return value into an out-pointer; nil for void-returning systems
	return_runner:     proc(sys: ^System, data: rawptr, out: rawptr),
	return_size:       int,
	return_typeid:     typeid,
	// Piped-in value injected by a preceding pipe() composite system
	pipe_in:           rawptr,
	pipe_in_typeid:    typeid,
	pipe_in_size:      int,
	// Composite system cleanup; owns and destroys inner system allocations
	composite_destroy: proc(data: rawptr, allocator: mem.Allocator),
}

Schedule :: struct {
	systems: [dynamic]^System,
}

// Registers a new system parameter builder into the World, which defines how to construct and manage a specific type of system parameter.
register_system_param_builder :: proc(w: ^ecs.World, builder: ecs.System_Param_Builder) {
	ecs.world_register_param_builder(w, builder)
}

import reflect "../../reflect"

world_init_default_params :: proc(w: ^ecs.World) {
	// Res system param: Maps a global resource from the world directly into the system's parameter block.
	// No after_run hook is required because modifications are written directly to the resource memory.
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime.type_info_base(info)
			if !reflect.match_struct_field(base, "ptr", 1) do return false
			s := base.variant.(runtime.Type_Info_Struct)
			return reflect.get_pointer_elem_type(s, 0) != typeid_of(ecs.Commands)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)
			res_type := reflect.get_pointer_elem_type(s, 0)
			if res, ok := w.resources[res_type]; ok {
				reflect.assign_ptr_value(ptr, res)
			}
		},
	})

	// Event_Writer system param: Initializes a dynamically-allocated array inside the system's parameter block.
	// Systems simply append events to this array, which are then flushed to the World dynamically inside the after_run hook.
	register_system_param_builder(w, {
		match = proc(
			info: ^runtime.Type_Info,
		) -> bool {return reflect.match_struct_field(info, "_events", 2)},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			Dummy :: struct {
				_events: runtime.Raw_Dynamic_Array,
				events:  ^runtime.Raw_Dynamic_Array,
			}
			dummy := (^Dummy)(ptr)
			if dummy._events.allocator.procedure == nil {
				dummy._events.allocator = context.allocator
			}
			dummy.events = &dummy._events
		},
		after_run = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			dyn_array := (^runtime.Raw_Dynamic_Array)(ptr)
			if dyn_array.len > 0 {
				s := info.variant.(runtime.Type_Info_Struct)
				ev_type := reflect.get_dynamic_array_elem_type(s, 0)
				event_size := int(s.types[0].variant.(runtime.Type_Info_Dynamic_Array).elem.size)

				for i in 0 ..< dyn_array.len {
					data_ptr := rawptr(uintptr(dyn_array.data) + uintptr(i * event_size))
					events.trigger(&w.event_manager, w, ev_type, 0, data_ptr)
				}

				dyn_array.len = 0
			}
		},
		destroy = proc(sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			dyn_array := (^runtime.Raw_Dynamic_Array)(ptr)
			if dyn_array.data != nil {
				free(dyn_array.data, dyn_array.allocator)
				dyn_array.data = nil
				dyn_array.cap = 0
			}
		},
	})

	// Event_Reader system param: Connects a system to the World's event history.
	// The builder isolates events emitted since the last time this specific system ran, copying them into a temporary slice.
	// Since it only reads data into temp allocator, no after_run or destroy hook is necessary.
	register_system_param_builder(
		w,
		{
			match = proc(
				info: ^runtime.Type_Info,
			) -> bool {return reflect.match_struct_field(info, "events", 2)},
			build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
				s := info.variant.(runtime.Type_Info_Struct)
				ev_type := reflect.get_slice_elem_type(s, 0)

				cursor := (^int)(uintptr(ptr) + s.offsets[1])
				if buf, ok := w.event_manager.history[ev_type]; ok {
					total_events := buf.count

					// Handle case where events were cleared between runs
					if cursor^ > total_events {
						cursor^ = 0
					}

					count := total_events - cursor^

					if count > 0 {
						// Copy history to temp_allocator to provide a stable slice for the system
						if buf.event_size > 0 {
							data_size := int(count * buf.event_size)
							out_data := make([]u8, data_size, context.temp_allocator)
							mem.copy(&out_data[0], &buf.data[cursor^ * buf.event_size], data_size)

							slice := runtime.Raw_Slice {
								data = &out_data[0],
								len  = count,
							}
							reflect.assign_ptr_value(ptr, slice)
						} else {
							// For zero-sized events, just provide length
							slice := runtime.Raw_Slice {
								data = nil,
								len  = count,
							}
							reflect.assign_ptr_value(ptr, slice)
						}
						cursor^ = total_events
					} else {
						slice := runtime.Raw_Slice {
							data = nil,
							len  = 0,
						}
						reflect.assign_ptr_value(ptr, slice)
					}
				}
			},
		},
	)

	// Commands system param: Provides a deferred commands buffer to the system.
	// Changes made via the buffer are automatically flushed into the World inside the after_run hook.
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime.type_info_base(info)
			if !reflect.match_struct_field(base, "ptr", 1) do return false
			s := base.variant.(runtime.Type_Info_Struct)
			return reflect.get_pointer_elem_type(s, 0) == typeid_of(ecs.Commands)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			sys_ptr := (^System)(sys)

			if sys_ptr.commands._world == nil {
				sys_ptr.commands = ecs.commands_init(w)
			} else if sys_ptr.commands._world != w {
				sys_ptr.commands._world = w
			}

			cmds_struct := (^params.Commands)(ptr)
			cmds_struct.ptr = &sys_ptr.commands
		},
		after_run = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			sys_ptr := (^System)(sys)
			ecs.commands_flush(&sys_ptr.commands)
		},
	})

	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime.type_info_base(info)
			return base.id == typeid_of(^ecs.World)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			((^^ecs.World)(ptr))^ = w
		},
	})

	// In(T) system param: receives a value piped in from a preceding pipe() composite.
	// Matches any struct with exactly one field named "value".  When a pipe is active
	// the field is filled from sys.pipe_in; otherwise it remains zero-initialised.
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime.type_info_base(info)
			s, ok := base.variant.(runtime.Type_Info_Struct)
			if !ok || s.field_count != 1 do return false
			return s.names[0] == "value"
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			sys_ptr := (^System)(sys)
			if sys_ptr.pipe_in == nil || sys_ptr.pipe_in_size == 0 do return
			s := info.variant.(runtime.Type_Info_Struct)
			field_ptr := rawptr(uintptr(ptr) + s.offsets[0])
			mem.copy(field_ptr, sys_ptr.pipe_in, sys_ptr.pipe_in_size)
		},
	})

	// OnAdded system param
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			named, ok := info.variant.(runtime.Type_Info_Named)
			if !ok do return false
			return len(named.name) >= 8 && named.name[:8] == "OnAdded("
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)
			phantom_ti := s.types[2]
			ptr_info := phantom_ti.variant.(runtime.Type_Info_Pointer)
			t := ptr_info.elem.id

			term := ecs.Term {
				op    = .OnAdd,
				types = []typeid{t},
			}
			vid := ecs.world_resolve_term(w, term)

			cursor := (^int)(uintptr(ptr) + s.offsets[1])
			if buf, ok := w.event_manager.history[vid]; ok {
				total_events := buf.count
				if cursor^ > total_events {
					cursor^ = 0
				}
				count := total_events - cursor^
				if count > 0 {
					out_entities := make([]ecs.Entity, count, context.temp_allocator)
					for i in 0 ..< count {
						out_entities[i] = transmute(ecs.Entity)buf.entities[cursor^ + i]
					}
					slice := runtime.Raw_Slice {
						data = &out_entities[0],
						len  = count,
					}
					reflect.assign_ptr_value(ptr, slice)
					cursor^ = total_events
				} else {
					slice := runtime.Raw_Slice {
						data = nil,
						len  = 0,
					}
					reflect.assign_ptr_value(ptr, slice)
				}
			} else {
				slice := runtime.Raw_Slice {
					data = nil,
					len  = 0,
				}
				reflect.assign_ptr_value(ptr, slice)
			}
		},
	})

	// OnRemoved system param
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			named, ok := info.variant.(runtime.Type_Info_Named)
			if !ok do return false
			return len(named.name) >= 10 && named.name[:10] == "OnRemoved("
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)
			phantom_ti := s.types[2]
			ptr_info := phantom_ti.variant.(runtime.Type_Info_Pointer)
			t := ptr_info.elem.id

			term := ecs.Term {
				op    = .OnRemove,
				types = []typeid{t},
			}
			vid := ecs.world_resolve_term(w, term)

			cursor := (^int)(uintptr(ptr) + s.offsets[1])
			if buf, ok := w.event_manager.history[vid]; ok {
				total_events := buf.count
				if cursor^ > total_events {
					cursor^ = 0
				}
				count := total_events - cursor^
				if count > 0 {
					out_entities := make([]ecs.Entity, count, context.temp_allocator)
					for i in 0 ..< count {
						out_entities[i] = transmute(ecs.Entity)buf.entities[cursor^ + i]
					}
					slice := runtime.Raw_Slice {
						data = &out_entities[0],
						len  = count,
					}
					reflect.assign_ptr_value(ptr, slice)
					cursor^ = total_events
				} else {
					slice := runtime.Raw_Slice {
						data = nil,
						len  = 0,
					}
					reflect.assign_ptr_value(ptr, slice)
				}
			} else {
				slice := runtime.Raw_Slice {
					data = nil,
					len  = 0,
				}
				reflect.assign_ptr_value(ptr, slice)
			}
		},
	})

	// Single system param
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			named, ok := info.variant.(runtime.Type_Info_Named)
			if !ok do return false
			return len(named.name) >= 7 && named.name[:7] == "Single("
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)
			phantom_ti := s.types[2]
			ptr_info := phantom_ti.variant.(runtime.Type_Info_Pointer)
			t := ptr_info.elem.id

			found_entity: ecs.Entity
			found_ptr: rawptr = nil
			found_count := 0

			for _, arch in w.archetypes {
				if t in arch.lookup {
					col_idx := arch.lookup[t]
					col := &arch.columns[col_idx]
					for i in 0 ..< arch.len {
						found_entity = arch.entities[i]
						found_ptr = rawptr(uintptr(col.ptr) + uintptr(i * col.size))
						found_count += 1
					}
				}
			}

			if found_count != 1 {
				panic(fmt.tprintf("Single(%v) matched %d entities instead of exactly 1", t, found_count))
			}

			entity_ptr := (^ecs.Entity)(uintptr(ptr) + s.offsets[0])
			entity_ptr^ = found_entity

			val_ptr := (^rawptr)(uintptr(ptr) + s.offsets[1])
			val_ptr^ = found_ptr
		},
	})

	// Query system param builder
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			named, ok := info.variant.(runtime.Type_Info_Named)
			if !ok do return false
			return len(named.name) >= 6 && named.name[:6] == "Query("
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)

			((^^ecs.World)(ptr))^ = w
			w.iteration_depth += 1

			state_ptr := (^^ecs.Query_State)(uintptr(ptr) + s.offsets[1])
			if state_ptr^ != nil do return

			state_ptr^ = new(ecs.Query_State, w.allocator)
			state := state_ptr^
			state.world = w
			state.include = make([dynamic]typeid, w.allocator)
			state.exclude = make([dynamic]typeid, w.allocator)
			state.any_ = make([dynamic]typeid, w.allocator)

			phantom_ti := s.types[2]
			phantom_ptr_info := phantom_ti.variant.(runtime.Type_Info_Pointer)
			t_actual := phantom_ptr_info.elem

			parse_term :: proc(ti: ^runtime.Type_Info, state: ^ecs.Query_State) {
				named, ok := ti.variant.(runtime.Type_Info_Named)
				if ok {
					if len(named.name) >= 5 && named.name[:5] == "With(" {
						s_ti := named.base.variant.(runtime.Type_Info_Struct)
						ptr_ti := s_ti.types[0].variant.(runtime.Type_Info_Pointer)
						tid := ptr_ti.elem.id
						append(&state.include, tid)
					} else if len(named.name) >= 8 && named.name[:8] == "Without(" {
						s_ti := named.base.variant.(runtime.Type_Info_Struct)
						ptr_ti := s_ti.types[0].variant.(runtime.Type_Info_Pointer)
						tid := ptr_ti.elem.id
						append(&state.exclude, tid)
					} else if len(named.name) >= 3 && named.name[:3] == "Or(" {
						s_ti := named.base.variant.(runtime.Type_Info_Struct)
						ptr_ti := s_ti.types[0].variant.(runtime.Type_Info_Pointer)
						sub_struct := ptr_ti.elem.variant.(runtime.Type_Info_Struct)

						t1_ptr := sub_struct.types[0].variant.(runtime.Type_Info_Pointer)
						append(&state.any_, t1_ptr.elem.id)

						t2_ptr := sub_struct.types[1].variant.(runtime.Type_Info_Pointer)
						append(&state.any_, t2_ptr.elem.id)
					} else {
						append(&state.include, ti.id)
					}
				} else {
					append(&state.include, ti.id)
				}
			}

			named, ok := t_actual.variant.(runtime.Type_Info_Named)
			if ok {
				parse_term(t_actual, state)
			} else {
				s_ti, is_struct := t_actual.variant.(runtime.Type_Info_Struct)
				if is_struct {
					for i in 0 ..< s_ti.field_count {
						field_type := s_ti.types[i]
						parse_term(field_type, state)
					}
				} else {
					parse_term(t_actual, state)
				}
			}

			typeid_cmp :: proc(i, j: typeid) -> bool {
				return transmute(uintptr)i < transmute(uintptr)j
			}

			if len(state.include) > 1 do slice.sort_by(state.include[:], typeid_cmp)
			if len(state.exclude) > 1 do slice.sort_by(state.exclude[:], typeid_cmp)
			if len(state.any_) > 1 do slice.sort_by(state.any_[:], typeid_cmp)

			state.hash = hash.fnv64a(slice.to_bytes(state.include[:]))
			if len(state.exclude) > 0 do state.hash = hash.fnv64a(slice.to_bytes(state.exclude[:]), state.hash)
			if len(state.any_) > 0 do state.hash = hash.fnv64a(slice.to_bytes(state.any_[:]), state.hash)
		},
		after_run = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			w.iteration_depth -= 1
		},
		destroy = proc(sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			s := info.variant.(runtime.Type_Info_Struct)
			state_ptr := (^^ecs.Query_State)(uintptr(ptr) + s.offsets[1])
			if state_ptr^ != nil {
				state := state_ptr^
				delete(state.include)
				delete(state.exclude)
				delete(state.any_)
				free(state, state.world.allocator)
				state_ptr^ = nil
			}
		},
	})
}

// Generic helper to register simple system params of a specific type
register_system_param :: proc(
	w: ^ecs.World,
	$T: typeid,
	provider: proc(w: ^ecs.World, sys: ^System) -> T,
) {
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			base := runtime.type_info_base(info)
			return base.id == typeid_of(T)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			((^T)(ptr))^ = provider(w, (^System)(sys))
		},
	})
}

new_system :: proc(
	procedure: $T,
	allocator := context.allocator,
) -> ^System where intrinsics.type_is_proc(T) {
	s := new(System, allocator)
	s.procedure = rawptr(procedure)

	s.runner = proc(sys: ^System, data_ptr: rawptr) {
		base_ti := reflect.base_info_of(typeid_of(T))
		params_info, ok := reflect.get_procedure_params(base_ti)
		if !ok do return

		fn_ptr := sys.procedure
		// 2. We cast the raw function pointer to its actual type T
		fn := cast(T)(fn_ptr)

		// 3. The Secret Sauce:
		// Since we know T at compile-time, we can construct an inline
		// type-assertion switch or use direct inline unpacking if we know the signature.
		// If this runner is entirely generic, we cast the packed `data_ptr` memory
		// block as an argument tuple structure using a specialized proxy.

		// For an arbitrary compile-time $T, you can unpack arguments by telling
		// Odin to treat the packed data_ptr as a direct reference to the argument list.
		// We can do this cleanly by casting the function pointer to take a raw byte pointer
		// or passing the dereferenced values.

		// The absolute easiest way to call a compile-time known $T with a raw pointer
		// to its arguments is to cast the function pointer to a version that takes a pointer to a struct.
		// However, Odin allows a simpler approach: if you built the buffer via alignment,
		// you can just manually unpack up to your supported maximum arguments, like this:

		param_count := len(params_info.types)
		args: [8]rawptr
		offset: uintptr = 0
		for i in 0 ..< min(param_count, len(args)) {
			ti := params_info.types[i]
			offset = mem.align_forward_uintptr(offset, uintptr(ti.align))
			args[i] = rawptr(uintptr(data_ptr) + offset)
			offset += uintptr(ti.size)
		}

		// Internal helper to dereference 8-byte arguments (passed by value in ABI)
		// while leaving larger ones (like slices/Event_Reader) as pointers (passed by ref in ABI).
		val := proc(p: rawptr, ti: ^runtime.Type_Info) -> rawptr {
			if ti.size <= 8 do return (^rawptr)(p)^
			return p
		}

		switch param_count {
		case 0:
			(cast(proc())(fn_ptr))()
		case 1:
			(cast(proc(_: rawptr))(fn_ptr))(val(args[0], params_info.types[0]))
		case 2:
			(cast(proc(_: rawptr, _: rawptr))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
			)
		case 3:
			(cast(proc(_: rawptr, _: rawptr, _: rawptr))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
			)
		case 4:
			(cast(proc(_: rawptr, _: rawptr, _: rawptr, _: rawptr))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
				val(args[3], params_info.types[3]),
			)
		case 5:
			(cast(proc(_: rawptr, _: rawptr, _: rawptr, _: rawptr, _: rawptr))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
				val(args[3], params_info.types[3]),
				val(args[4], params_info.types[4]),
			)
		case 6:
			(cast(proc(_: rawptr, _: rawptr, _: rawptr, _: rawptr, _: rawptr, _: rawptr))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
				val(args[3], params_info.types[3]),
				val(args[4], params_info.types[4]),
				val(args[5], params_info.types[5]),
			)
		case 7:
			(cast(proc(
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
				))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
				val(args[3], params_info.types[3]),
				val(args[4], params_info.types[4]),
				val(args[5], params_info.types[5]),
				val(args[6], params_info.types[6]),
			)
		case 8:
			(cast(proc(
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
					_: rawptr,
				))(fn_ptr))(
				val(args[0], params_info.types[0]),
				val(args[1], params_info.types[1]),
				val(args[2], params_info.types[2]),
				val(args[3], params_info.types[3]),
				val(args[4], params_info.types[4]),
				val(args[5], params_info.types[5]),
				val(args[6], params_info.types[6]),
				val(args[7], params_info.types[7]),
			)
		}
	}

	// Build a return_runner when T has exactly one return value.
	// The runner captures that return value into an out-pointer supplied by
	// the caller (pipe/run_if composites).  Uses the same arg-unpacking pattern
	// as the main runner so params are injected identically.
	when intrinsics.type_proc_return_count(T) == 1 {
		Return_Type :: intrinsics.type_proc_return_type(T, 0)
		s.return_typeid = typeid_of(Return_Type)
		s.return_size = size_of(Return_Type)

		s.return_runner = proc(sys: ^System, data_ptr: rawptr, out: rawptr) {
			base_ti := reflect.base_info_of(typeid_of(T))
			params_info, _ := reflect.get_procedure_params(base_ti)
			fn_ptr := sys.procedure
			param_count := len(params_info.types) // 0 for procs with no params
			args: [8]rawptr
			offset: uintptr = 0
			for i in 0 ..< min(param_count, len(args)) {
				ti := params_info.types[i]
				offset = mem.align_forward_uintptr(offset, uintptr(ti.align))
				args[i] = rawptr(uintptr(data_ptr) + offset)
				offset += uintptr(ti.size)
			}
			val :: proc(p: rawptr, ti: ^runtime.Type_Info) -> rawptr {
				if ti.size <= 8 do return (^rawptr)(p)^
				return p
			}
			switch param_count {
			case 0:
				((^Return_Type)(out))^ = (cast(proc() -> Return_Type)(fn_ptr))()
			case 1:
				((^Return_Type)(out))^ = (cast(proc(_: rawptr) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
				)
			case 2:
				((^Return_Type)(out))^ = (cast(proc(_: rawptr, _: rawptr) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
				)
			case 3:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
				)
			case 4:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
					val(args[3], params_info.types[3]),
				)
			case 5:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
					val(args[3], params_info.types[3]),
					val(args[4], params_info.types[4]),
				)
			case 6:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
					val(args[3], params_info.types[3]),
					val(args[4], params_info.types[4]),
					val(args[5], params_info.types[5]),
				)
			case 7:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
					val(args[3], params_info.types[3]),
					val(args[4], params_info.types[4]),
					val(args[5], params_info.types[5]),
					val(args[6], params_info.types[6]),
				)
			case 8:
				((^Return_Type)(out))^ = (cast(proc(
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
						_: rawptr,
					) -> Return_Type)(fn_ptr))(
					val(args[0], params_info.types[0]),
					val(args[1], params_info.types[1]),
					val(args[2], params_info.types[2]),
					val(args[3], params_info.types[3]),
					val(args[4], params_info.types[4]),
					val(args[5], params_info.types[5]),
					val(args[6], params_info.types[6]),
					val(args[7], params_info.types[7]),
				)
			}
		}
	}

	ti := reflect.base_info_of(T)
	if proc_info, ok := ti.variant.(runtime.Type_Info_Procedure); ok {
		if proc_info.params != nil {
			s.params_type = proc_info.params.id
		}
	}

	if s.params_type != nil {
		ti := reflect.base_info_of(s.params_type)
		s.params_data, _ = mem.alloc(ti.size, ti.align, allocator)
		mem.zero(s.params_data, ti.size)
	}

	return s
}

@(private)
resolve_system_params :: proc(w: ^ecs.World, system: ^System) {
	if system.resolved do return

	system.resolved_params = make([dynamic]System_Param_Resolve, w.allocator)

	if system.params_type == nil {
		system.resolved = true
		return
	}

	info := reflect.base_info_of(system.params_type)
	params_info, ok := info.variant.(runtime.Type_Info_Parameters)
	if !ok {
		system.resolved = true
		return
	}

	offset: uintptr = 0
	for i in 0 ..< len(params_info.types) {
		field_info := params_info.types[i]
		offset = mem.align_forward_uintptr(offset, uintptr(field_info.align))

		base_info := runtime.type_info_base(field_info)

		for builder in w.param_builders {
			if builder.match(field_info) {
				append(
					&system.resolved_params,
					System_Param_Resolve {
						builder = builder,
						base_info = base_info,
						offset = offset,
					},
				)
				break
			}
		}
		offset += uintptr(field_info.size)
	}

	system.resolved = true
}

destroy_system :: proc(w: ^ecs.World, sys: ^System, allocator := context.allocator) {
	if sys == nil do return
	// Composite systems manage their own inner allocations
	if sys.composite_destroy != nil {
		sys.composite_destroy(sys.params_data, allocator)
		sys.params_data = nil
	}
	if sys.params_data != nil {
		if sys.resolved {
			for p in sys.resolved_params {
				field_ptr := rawptr(uintptr(sys.params_data) + p.offset)
				if p.builder.destroy != nil {
					p.builder.destroy(rawptr(sys), p.base_info, field_ptr)
				}
			}
			delete(sys.resolved_params)
		} else {
			info := reflect.base_info_of(sys.params_type)
			if params_info, ok := info.variant.(runtime.Type_Info_Parameters); ok {
				offset: uintptr = 0
				for i in 0 ..< len(params_info.types) {
					field_info := params_info.types[i]
					offset = mem.align_forward_uintptr(offset, uintptr(field_info.align))
					field_ptr := rawptr(uintptr(sys.params_data) + offset)
					offset += uintptr(field_info.size)

					base_info := runtime.type_info_base(field_info)

					for builder in w.param_builders {
						if builder.match(field_info) {
							if builder.destroy != nil {
								builder.destroy(rawptr(sys), base_info, field_ptr)
							}
							break
						}
					}
				}
			}
		}
		free(sys.params_data, allocator)
	}
	if sys.commands._world != nil {
		ecs.commands_destroy(&sys.commands)
	}
	free(sys, allocator)
}

// Instantiates and maps system parameters (resource pointers, command buffers, event readers/writers) from the world.
build_system :: proc(w: ^ecs.World, system: ^System) {
	system.world = w // always expose world for composite runners
	if system.params_data == nil do return

	if !system.resolved {
		resolve_system_params(w, system)
	}

	for p in system.resolved_params {
		field_ptr := rawptr(uintptr(system.params_data) + p.offset)
		p.builder.build(w, rawptr(system), p.base_info, field_ptr)
	}
}

// Invokes the system procedure, passing the unpacked parameter structure.
execute_system :: proc(system: ^System) {
	system.runner(system, system.params_data)
}

// Flushes and clears any temporary system state (e.g. deferred command buffers and written event histories) back to the world.
flush_system :: proc(w: ^ecs.World, system: ^System) {
	if system.params_data == nil do return

	if !system.resolved {
		resolve_system_params(w, system)
	}

	for p in system.resolved_params {
		if p.builder.after_run != nil {
			field_ptr := rawptr(uintptr(system.params_data) + p.offset)
			p.builder.after_run(w, rawptr(system), p.base_info, field_ptr)
		}
	}
}

// Runs a system completely: builds its parameters, executes it, and flushes its state.
run_system :: proc(w: ^ecs.World, sys: ^System) {
	build_system(w, sys)
	execute_system(sys)
	flush_system(w, sys)
}

@(test)
test_systems_params :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	world_init_default_params(&w)

	Config :: struct {
		value: int,
	}
	ecs.world_add_resource(&w, Config{10})

	MyEvent :: struct {
		msg: int,
	}

	// sys_proc now takes original unpacked params
	sys_proc := proc(
		config: params.Res(Config),
		writer: params.EventWriter(MyEvent),
		reader: params.EventReader(MyEvent),
	) {
		config.ptr.value += 1
		if len(reader.events) > 0 {
			config.ptr.value += reader.events[0].msg
		}
		params.write(writer, MyEvent{5})
	}

	sys := new_system(sys_proc)
	defer destroy_system(&w, sys)

	run_system(&w, sys)
	conf := ecs.world_get_resource(&w, Config)
	testing.expect_value(t, conf.value, 11) // Value + 1

	run_system(&w, sys)
	testing.expect_value(t, conf.value, 17) // Value + 1 + event(5)
}

// ─── Composite system data ────────────────────────────────────────────────────

@(private)
Run_If_Data :: struct {
	condition: ^System,
	target:    ^System,
}

@(private)
Pipe_Data :: struct {
	source:     ^System,
	target:     ^System,
	return_buf: [128]byte, // return value from source, up to 128 bytes
}

// ─── run_if ──────────────────────────────────────────────────────────────────

/*
	Creates a composite system that runs `target` only when `condition` returns true.
	`condition` must be a system procedure returning exactly one `bool`.

	Example:
		app_add_system(&app, app.Update, sys.run_if(is_alive, process))
*/
run_if :: proc(
	condition: $C,
	target: $T,
	allocator := context.allocator,
) -> ^System where intrinsics.type_is_proc(C),
	intrinsics.type_is_proc(T),
	intrinsics.type_proc_return_count(C) ==
	1,
	intrinsics.type_proc_return_type(C, 0) ==
	bool {

	cond_sys := new_system(condition, allocator)
	target_sys := new_system(target, allocator)

	data := new(Run_If_Data, allocator)
	data.condition = cond_sys
	data.target = target_sys

	wrapper := new(System, allocator)
	wrapper.params_data = data
	wrapper.resolved = true // suppress default param resolution
	wrapper.resolved_params = make([dynamic]System_Param_Resolve, allocator)

	wrapper.composite_destroy = proc(data: rawptr, allocator: mem.Allocator) {
		d := (^Run_If_Data)(data)
		destroy_system(d.condition.world, d.condition, allocator)
		destroy_system(d.target.world, d.target, allocator)
		free(d, allocator)
	}

	wrapper.runner = proc(sys: ^System, data_ptr: rawptr) {
		comp := (^Run_If_Data)(data_ptr)
		w := sys.world
		if w == nil do return

		// Execute condition and capture bool result
		build_system(w, comp.condition)
		cond_result := false
		if comp.condition.return_runner != nil {
			ret: bool
			comp.condition.return_runner(comp.condition, comp.condition.params_data, &ret)
			cond_result = ret
		}
		flush_system(w, comp.condition)

		if cond_result {
			build_system(w, comp.target)
			execute_system(comp.target)
			flush_system(w, comp.target)
		}
	}

	return wrapper
}

// ─── pipe ────────────────────────────────────────────────────────────────────

/*
	Creates a composite system that runs `source`, captures its single return value,
	then runs `target` with that value injected via params.In(T).

	`source` must return exactly one value.  `target` may declare a `params.In(T)`
	parameter whose T matches the source return type to receive the piped value.

	Example:
		app_add_system(&app, app.Update, sys.pipe(compute_count, consume_count))
*/
pipe :: proc(
	source: $S,
	target: $T,
	allocator := context.allocator,
) -> ^System where intrinsics.type_is_proc(S),
	intrinsics.type_is_proc(T),
	intrinsics.type_proc_return_count(S) ==
	1 {

	source_sys := new_system(source, allocator)
	target_sys := new_system(target, allocator)

	data := new(Pipe_Data, allocator)
	data.source = source_sys
	data.target = target_sys

	wrapper := new(System, allocator)
	wrapper.params_data = data
	wrapper.resolved = true
	wrapper.resolved_params = make([dynamic]System_Param_Resolve, allocator)

	wrapper.composite_destroy = proc(data: rawptr, allocator: mem.Allocator) {
		d := (^Pipe_Data)(data)
		destroy_system(d.source.world, d.source, allocator)
		destroy_system(d.target.world, d.target, allocator)
		free(d, allocator)
	}

	wrapper.runner = proc(sys: ^System, data_ptr: rawptr) {
		comp := (^Pipe_Data)(data_ptr)
		w := sys.world
		if w == nil do return

		// Execute source and capture its return value into the embedded buffer
		build_system(w, comp.source)
		if comp.source.return_runner != nil {
			mem.zero(&comp.return_buf[0], len(comp.return_buf))
			comp.source.return_runner(comp.source, comp.source.params_data, &comp.return_buf[0])
		} else {
			execute_system(comp.source)
		}
		flush_system(w, comp.source)

		// Inject return value as pipe input to target
		comp.target.pipe_in = &comp.return_buf[0]
		comp.target.pipe_in_typeid = comp.source.return_typeid
		comp.target.pipe_in_size = comp.source.return_size

		build_system(w, comp.target)
		execute_system(comp.target)
		flush_system(w, comp.target)

		comp.target.pipe_in = nil // clear after use to avoid dangling reference
	}

	return wrapper
}

// ─── Tests ───────────────────────────────────────────────────────────────────

@(test)
test_run_if :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	world_init_default_params(&w)

	Flag :: struct {
		enabled: bool,
	}
	Counter :: struct {
		n: int,
	}
	ecs.world_add_resource(&w, Flag{true})
	ecs.world_add_resource(&w, Counter{0})

	cond_proc := proc(flag: params.Res(Flag)) -> bool {
		return flag.ptr.enabled
	}
	body_proc := proc(counter: params.Res(Counter)) {
		counter.ptr.n += 1
	}

	sys := run_if(cond_proc, body_proc)
	defer destroy_system(&w, sys)

	run_system(&w, sys)
	testing.expect_value(t, ecs.world_get_resource(&w, Counter).n, 1)

	ecs.world_get_resource(&w, Flag).enabled = false
	run_system(&w, sys)
	testing.expect_value(t, ecs.world_get_resource(&w, Counter).n, 1) // should NOT increment
}

@(test)
test_pipe :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	world_init_default_params(&w)

	Result :: struct {
		value: int,
	}
	ecs.world_add_resource(&w, Result{0})

	source_proc := proc() -> int {return 42}
	target_proc := proc(in_val: params.In(int), res: params.Res(Result)) {
		res.ptr.value = in_val.value
	}

	sys := pipe(source_proc, target_proc)
	defer destroy_system(&w, sys)

	run_system(&w, sys)
	testing.expect_value(t, ecs.world_get_resource(&w, Result).value, 42)
}

@(test)
test_new_params_added_removed_single :: proc(t: ^testing.T) {
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	world_init_default_params(&w)

	TestComponent :: struct {
		x: int,
	}
	Config :: struct {
		added_count:   int,
		removed_count: int,
		single_val:    int,
	}
	ecs.world_add_resource(&w, Config{})

	sys_proc := proc(
		added: params.OnAdded(TestComponent),
		removed: params.OnRemoved(TestComponent),
		single_comp: params.Single(TestComponent),
		config: params.Res(Config),
	) {
		config.ptr.added_count = len(added.entities)
		config.ptr.removed_count = len(removed.entities)
		config.ptr.single_val = single_comp.value.x
	}

	sys := new_system(sys_proc)
	defer destroy_system(&w, sys)

	// 1. Spawn a single entity with TestComponent
	e1 := ecs.world_spawn(&w)
	ecs.world_add_component(&w, e1, TestComponent{x = 42})

	// Run system
	run_system(&w, sys)

	conf := ecs.world_get_resource(&w, Config)
	testing.expect_value(t, conf.added_count, 1)
	testing.expect_value(t, conf.removed_count, 0)
	testing.expect_value(t, conf.single_val, 42)

	// 2. Remove the component from e1
	ecs.world_remove_component(&w, e1, TestComponent)

	// Spawn a new single entity with TestComponent so Single(TestComponent) doesn't panic
	e2 := ecs.world_spawn(&w)
	ecs.world_add_component(&w, e2, TestComponent{x = 100})

	run_system(&w, sys)

	testing.expect_value(t, conf.added_count, 1) // e2 was added
	testing.expect_value(t, conf.removed_count, 1) // e1 was removed
	testing.expect_value(t, conf.single_val, 100)
}
