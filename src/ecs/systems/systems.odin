package systems

import ecs ".."
import events "../events"
import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "ecs:params"

import "core:testing"

System_Runner :: #type proc(sys: ^System, data: rawptr)

System_Param_Resolve :: struct {
	builder:   ecs.System_Param_Builder,
	base_info: ^runtime.Type_Info,
	offset:    uintptr,
}

System :: struct {
	id:              u64,
	procedure:       rawptr,
	runner:          System_Runner,
	params_type:     typeid,
	params_data:     rawptr,
	commands:        ecs.Commands,
	resolved_params: [dynamic]System_Param_Resolve,
	resolved:        bool,
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
			if !reflect.match_struct_field(info, "ptr", 1) do return false
			s := info.variant.(runtime.Type_Info_Struct)
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
				events: ^runtime.Raw_Dynamic_Array,
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
	register_system_param_builder(w, {
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
	})

	// Commands system param: Provides a deferred commands buffer to the system.
	// Changes made via the buffer are automatically flushed into the World inside the after_run hook.
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {
			if !reflect.match_struct_field(info, "ptr", 1) do return false
			s := info.variant.(runtime.Type_Info_Struct)
			return reflect.get_pointer_elem_type(s, 0) == typeid_of(ecs.Commands)
		},
		build = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			sys_ptr := (^System)(sys)

			if sys_ptr.commands.world == nil {
				sys_ptr.commands = ecs.commands_init(w)
			} else if sys_ptr.commands.world != w {
				sys_ptr.commands.world = w
			}

			cmds_struct := (^params.Commands)(ptr)
			cmds_struct.ptr = &sys_ptr.commands
		},
		after_run = proc(w: ^ecs.World, sys: rawptr, info: ^runtime.Type_Info, ptr: rawptr) {
			sys_ptr := (^System)(sys)
			ecs.commands_flush(&sys_ptr.commands)
		},
	})
}

// Generic helper to register simple system params of a specific type
register_system_param :: proc(w: ^ecs.World, $T: typeid, provider: proc(w: ^ecs.World, sys: ^System) -> T) {
	register_system_param_builder(w, {
		match = proc(info: ^runtime.Type_Info) -> bool {return info.id == typeid_of(T)},
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
			if builder.match(base_info) {
				append(&system.resolved_params, System_Param_Resolve{
					builder = builder,
					base_info = base_info,
					offset = offset,
				})
				break
			}
		}
		offset += uintptr(field_info.size)
	}
	
	system.resolved = true
}

destroy_system :: proc(w: ^ecs.World, sys: ^System, allocator := context.allocator) {
	if sys == nil do return
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
						if builder.match(base_info) {
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
	if sys.commands.world != nil {
		ecs.commands_destroy(&sys.commands)
	}
	free(sys, allocator)
}

// Instantiates and maps system parameters (resource pointers, command buffers, event readers/writers) from the world.
build_system :: proc(w: ^ecs.World, system: ^System) {
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
