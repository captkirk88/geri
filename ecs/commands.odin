package ecs

import "core:mem"

// Command types
Command_Op :: enum {
	Spawn,
	Despawn,
	AddComponent,
	RemoveComponent,
	AddSystem,
	AddResource,
	AddRelation, // Deferred: relation type + target resolved at flush time
}

Command :: struct {
	op:         Command_Op,
	entity:     Entity,
	tid:        typeid,
	data:       rawptr,
	size:       int,
	adder:      proc(w: ^World, e: Entity, tid: typeid, data: rawptr),
	destructor: proc(data: rawptr, allocator: mem.Allocator),
}

// Commands holds a deferred queue of world mutations.
// It does not hold a pointer to the World; the world is only needed at
// flush time, which is handled automatically by the ECS system runner.
Commands :: struct {
	buffer:    [dynamic]Command,
	allocator: mem.Allocator,
	// Counter for placeholder entity IDs (gen=0 sentinel) created by commands_spawn.
	// Resolved to real entity IDs during commands_flush.
	_pending:  int,
}

commands_init :: proc(allocator := context.allocator) -> Commands {
	return Commands{buffer = make([dynamic]Command, allocator), allocator = allocator}
}

commands_destroy :: proc(c: ^Commands) {
	for cmd in c.buffer {
		if cmd.data != nil {
			if cmd.destructor != nil {
				cmd.destructor(cmd.data, c.allocator)
			}
			free(cmd.data, c.allocator)
		}
	}
	delete(c.buffer)
}

// commands_spawn queues a Spawn command and returns an EntityCommands handle.
// The returned entity uses a placeholder ID (gen = 0) that is resolved to a
// real world entity during commands_flush.  You can safely chain
// entity_commands_add_component etc. on the returned handle before flush.
commands_spawn :: proc(c: ^Commands) -> EntityCommands {
	e := Entity {
		id  = u64(c._pending),
		gen = 0,
	} // placeholder: gen=0 = deferred
	c._pending += 1
	append(&c.buffer, Command{op = .Spawn, entity = e})
	return EntityCommands{commands = c, entity = e}
}

commands_add_component :: proc(c: ^Commands, entity: Entity, component: $T) {
	data, _ := mem.alloc(size_of(T), mem.DEFAULT_ALIGNMENT, c.allocator)
	val_ptr := (^T)(data)
	val_ptr^ = component

	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		_world_transition_type(w, e, tid, data, size_of(T), false)
	}

	append(
		&c.buffer,
		Command {
			op = .AddComponent,
			entity = entity,
			tid = typeid_of(T),
			data = data,
			size = size_of(T),
			adder = adder,
		},
	)
}

commands_add_components :: proc(c: ^Commands, entity: Entity, components: ..any) {
	for comp in components {
		if comp.data == nil do continue
		ti := type_info_of(comp.id)

		data, _ := mem.alloc(ti.size, ti.align, c.allocator)
		mem.copy(data, comp.data, ti.size)

		adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
			ti := type_info_of(tid)
			_world_transition_type(w, e, tid, data, ti.size, false)
		}

		append(
			&c.buffer,
			Command {
				op = .AddComponent,
				entity = entity,
				tid = comp.id,
				data = data,
				size = ti.size,
				adder = adder,
			},
		)
	}
}

commands_remove_component :: proc(c: ^Commands, entity: Entity, $T: typeid) {
	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		world_remove_component(w, e, tid)
	}

	append(
		&c.buffer,
		Command{op = .RemoveComponent, entity = entity, tid = typeid_of(T), adder = adder},
	)
}

// commands_add_relation queues an AddRelation command.
// The relation term (pair) is resolved against the World at flush time,
// so no world pointer is needed at queue time.
commands_add_relation :: proc(c: ^Commands, entity: Entity, $Rel: typeid, target: Entity) {
	// Store the target entity in a heap allocation so it survives until flush.
	target_data, _ := mem.alloc(size_of(Entity), mem.DEFAULT_ALIGNMENT, c.allocator)
	(^Entity)(target_data)^ = target

	append(
		&c.buffer,
		Command {
			op     = .AddRelation,
			entity = entity,
			tid    = typeid_of(Rel), // unresolved relation type; resolved in flush
			data   = target_data,
			size   = size_of(Entity),
		},
	)
}

commands_add_system :: proc(
	c: ^Commands,
	sys: rawptr,
	sys_size: int,
	adder: proc(w: ^World, e: Entity, tid: typeid, data: rawptr),
) {
	data, err := mem.alloc(sys_size, mem.DEFAULT_ALIGNMENT, c.allocator)
	if err == nil {
		mem.copy(data, sys, sys_size)
		append(&c.buffer, Command{op = .AddSystem, data = data, size = sys_size, adder = adder})
	}
}

commands_add_resource_no_destroy :: proc(c: ^Commands, resource: $T) {
	commands_add_resource_with_destroy(c, resource, nil)
}

commands_add_resource_with_destroy :: proc(
	c: ^Commands,
	resource: $T,
	destroy: proc(_: ^T, _: mem.Allocator),
) {
	Payload :: struct {
		value:   T,
		destroy: proc(_: ^T, _: mem.Allocator),
	}

	data, _ := mem.alloc(size_of(Payload), mem.DEFAULT_ALIGNMENT, c.allocator)
	payload := (^Payload)(data)
	payload.value = resource
	payload.destroy = destroy

	adder := proc(w: ^World, e: Entity, tid: typeid, data: rawptr) {
		payload := (^Payload)(data)
		world_add_resource(w, payload.value, payload.destroy)
	}

	destructor := proc(data: rawptr, allocator: mem.Allocator) {
		payload := (^Payload)(data)
		if payload.destroy != nil {
			payload.destroy(&payload.value, allocator)
		}
	}

	append(
		&c.buffer,
		Command {
			op = .AddResource,
			tid = typeid_of(T),
			data = data,
			size = size_of(Payload),
			adder = adder,
			destructor = destructor,
		},
	)
}

commands_add_resource :: proc {
	commands_add_resource_no_destroy,
	commands_add_resource_with_destroy,
}

commands_despawn :: proc(c: ^Commands, entity: Entity) {
	append(&c.buffer, Command{op = .Despawn, entity = entity})
}

// commands_flush applies all queued commands to the world.
//
// Deferred spawns (entities with gen = 0) are allocated first and mapped to
// real entity IDs. Any subsequent commands that reference a placeholder entity
// are transparently resolved before being applied.
commands_flush :: proc(c: ^Commands, w: ^World) {
	if c == nil || len(c.buffer) == 0 do return

	// Build a spawn map: placeholder index -> real Entity.
	// Allocated on the temp allocator so no cleanup is required.
	spawn_map := make([]Entity, c._pending, context.temp_allocator)
	for cmd in c.buffer {
		if cmd.op == .Spawn && cmd.entity.gen == 0 {
			id: u32
			gen: u32
			if len(w.free_list) > 0 {
				id = pop(&w.free_list)
				gen = w.entities.gen[id]
			} else {
				id = u32(len(w.entities))
				append_soa(&w.entities, Entity_Meta{gen = 1})
				gen = 1
			}
			spawn_map[cmd.entity.id] = Entity {
				id  = u64(id),
				gen = u64(gen),
			}
		}
	}

	// Resolve a potentially-deferred entity to its real ID.
	resolve :: proc(e: Entity, spawn_map: []Entity) -> Entity {
		if e.gen == 0 && int(e.id) < len(spawn_map) {
			return spawn_map[e.id]
		}
		return e
	}

	for cmd in c.buffer {
		entity := resolve(cmd.entity, spawn_map)

		switch cmd.op {
		case .AddComponent, .AddSystem, .AddResource, .RemoveComponent:
			cmd.adder(w, entity, cmd.tid, cmd.data)
		case .Despawn:
			world_despawn(w, entity)
		case .Spawn:
			row := arch_add_entity(w.root, entity)
			w.entities.record[entity.id] = {w.root, row}
		case .AddRelation:
			target := resolve((^Entity)(cmd.data)^, spawn_map)
			term := Term {
				op       = .Pair,
				relation = cmd.tid,
				target   = target,
			}
			virtual_tid := world_resolve_term(w, term)

			if world_is_alive(w, entity) && world_is_alive(w, target) {
				if !world_has_component(w, entity, virtual_tid) {
					_world_transition_type(w, entity, virtual_tid, nil, 0, true)

					if target not_in w.target_index {
						w.target_index[target] = make([dynamic]Relation_Link, w.allocator)
					}
					append(&w.target_index[target], Relation_Link{entity, virtual_tid})
				}
			}
		}

		if cmd.data != nil {
			free(cmd.data, c.allocator)
		}
	}

	clear(&c.buffer)
	c._pending = 0
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

entity_commands_add_relation :: proc(
	ec: EntityCommands,
	$Rel: typeid,
	target: Entity,
) -> EntityCommands {
	commands_add_relation(ec.commands, ec.entity, Rel, target)
	return ec
}

entity_commands_despawn :: proc(ec: EntityCommands) {
	commands_despawn(ec.commands, ec.entity)
}
