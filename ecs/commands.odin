package ecs

import "core:mem"

// Command types
Command_Op :: enum {
	Spawn,
	Despawn,
	AddComponent,
	RemoveComponent,
	AddSystem,
}

Command :: struct {
	op: Command_Op,
	entity: Entity,
	tid: typeid,
	data: rawptr,
	size: int,
	adder: proc(w: ^World, e: Entity, tid: typeid, data: rawptr),
}

Commands :: struct {
	world: ^World,
	buffer: [dynamic]Command,
}

commands_init :: proc(w: ^World, allocator := context.allocator) -> Commands {
	return Commands{world = w, buffer = make([dynamic]Command, allocator)}
}

commands_destroy :: proc(c: ^Commands) {
	for cmd in c.buffer {
		if cmd.data != nil {
			free(cmd.data, c.world.allocator)
		}
	}
	delete(c.buffer)
}

commands_spawn :: proc(c: ^Commands) -> Entity {
	return world_spawn(c.world)
}

commands_add_component :: proc(c: ^Commands, entity: Entity, component: $T) {
	data := mem.clone_ptr(&component, size_of(T), c.world.allocator)
	
	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		// This needs to call world_add_component but it's generic.
		// Since we have the typeid `tid` and the data, 
		// we can use a runtime-friendly way to add components, 
		// possibly by extending world_add_component to take rawptr and typeid.
		_world_transition_type(w, e, tid, data, size_of(T), false)
	}

	append(&c.buffer, Command{
		op = .AddComponent,
		entity = entity,
		tid = typeid_of(T),
		data = data,
		size = size_of(T),
		adder = adder,
	})
}

commands_add_system :: proc(c: ^Commands, sys: rawptr, sys_size: int, adder: proc(w: ^World, e: Entity, tid: typeid, data: rawptr)) {
	data, err := mem.alloc(sys_size, mem.DEFAULT_ALIGNMENT, c.world.allocator)
	if err == nil {
		mem.copy(data, sys, sys_size)
		append(&c.buffer, Command{
			op = .AddSystem,
			data = data,
			size = sys_size,
			adder = adder,
		})
	}
}

commands_flush :: proc(c: ^Commands) {
	if c == nil do return
	for cmd in c.buffer {
		switch cmd.op {
		case .AddComponent, .AddSystem:
			cmd.adder(c.world, cmd.entity, cmd.tid, cmd.data)
		case .Despawn:
			world_despawn(c.world, cmd.entity)
		case .Spawn, .RemoveComponent:
			// Handle other cases
		}
		if cmd.data != nil {
			free(cmd.data, c.world.allocator)
		}
	}
	clear(&c.buffer)
}
