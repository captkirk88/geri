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

commands_spawn :: proc(c: ^Commands) -> EntityCommands {
	id: u32
	gen: u32
	w := c.world
	if len(w.free_list) > 0 {
		id = pop(&w.free_list)
		gen = w.entities[id].gen
	} else {
		id = u32(len(w.entities))
		append(&w.entities, Entity_Meta{gen = 1})
		gen = 1
	}

	e := Entity {
		id  = u64(id),
		gen = u64(gen),
	}

	append(&c.buffer, Command{
		op = .Spawn,
		entity = e,
	})

	return EntityCommands{commands = c, entity = e}
}

commands_add_component :: proc(c: ^Commands, entity: Entity, component: $T) {
	data, _ := mem.alloc(size_of(T), mem.DEFAULT_ALIGNMENT, c.world.allocator)
	val_ptr := (^T)(data)
	val_ptr^ = component
	
	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
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

commands_add_components :: proc(c: ^Commands, entity: Entity, components: ..any) {
	for comp in components {
		if comp.data == nil do continue
		ti := type_info_of(comp.id)

		data, _ := mem.alloc(ti.size, ti.align, c.world.allocator)
		mem.copy(data, comp.data, ti.size)

		adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
			ti := type_info_of(tid)
			_world_transition_type(w, e, tid, data, ti.size, false)
		}

		append(&c.buffer, Command{
			op = .AddComponent,
			entity = entity,
			tid = comp.id,
			data = data,
			size = ti.size,
			adder = adder,
		})
	}
}

commands_remove_component :: proc(c: ^Commands, entity: Entity, $T: typeid) {
	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		world_remove_component(w, e, tid)
	}

	append(&c.buffer, Command{
		op = .RemoveComponent,
		entity = entity,
		tid = typeid_of(T),
		adder = adder,
	})
}

commands_add_relation :: proc(c: ^Commands, entity: Entity, $Rel: typeid, target: Entity) {
	term := pair(Rel, target)
	tid := world_resolve_term(c.world, term)

	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		target_ptr := (^Entity)(data)
		target := target_ptr^
		if !world_is_alive(w, e) || !world_is_alive(w, target) do return

		if world_has_component(w, e, tid) do return

		_world_transition_type(w, e, tid, nil, 0, true)

		if target not_in w.target_index {
			w.target_index[target] = make([dynamic]Relation_Link, w.allocator)
		}
		append(&w.target_index[target], Relation_Link{e, tid})
	}

	target_data, _ := mem.alloc(size_of(Entity), mem.DEFAULT_ALIGNMENT, c.world.allocator)
	val_ptr := (^Entity)(target_data)
	val_ptr^ = target

	append(&c.buffer, Command{
		op = .AddComponent,
		entity = entity,
		tid = tid,
		data = target_data,
		size = size_of(Entity),
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

commands_despawn :: proc(c: ^Commands, entity: Entity) {
	append(&c.buffer, Command{
		op = .Despawn,
		entity = entity,
	})
}

commands_flush :: proc(c: ^Commands) {
	if c == nil do return
	for cmd in c.buffer {
		switch cmd.op {
		case .AddComponent, .AddSystem:
			cmd.adder(c.world, cmd.entity, cmd.tid, cmd.data)
		case .Despawn:
			world_despawn(c.world, cmd.entity)
		case .Spawn:
			row := arch_add_entity(c.world.root, cmd.entity)
			c.world.entities[cmd.entity.id].record = {c.world.root, row}
		case .RemoveComponent:
			cmd.adder(c.world, cmd.entity, cmd.tid, cmd.data)
		}
		if cmd.data != nil {
			free(cmd.data, c.world.allocator)
		}
	}
	clear(&c.buffer)
}

EntityCommands :: struct {
	commands: ^Commands,
	entity:   Entity,
}

entity_commands_add_component :: proc(ec: EntityCommands, component: $T) -> EntityCommands {
	commands_add_component(ec.commands, ec.entity, component)
	return ec
}

entity_commands_add_components :: proc(ec: EntityCommands, components: ..any) -> EntityCommands {
	commands_add_components(ec.commands, ec.entity, ..components)
	return ec
}

entity_commands_remove_component :: proc(ec: EntityCommands, $T: typeid) -> EntityCommands {
	commands_remove_component(ec.commands, ec.entity, T)
	return ec
}

entity_commands_add_relation :: proc(ec: EntityCommands, $Rel: typeid, target: Entity) -> EntityCommands {
	commands_add_relation(ec.commands, ec.entity, Rel, target)
	return ec
}

entity_commands_despawn :: proc(ec: EntityCommands) {
	commands_despawn(ec.commands, ec.entity)
}
