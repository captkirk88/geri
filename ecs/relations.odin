package ecs

/*
    Relations allow entities to have relationships with other entities or types.
    A relationship is a 'Pair' of (Relation, Target).
*/

/* 
    Relation is simply a typeid representing the component type of the relationship.
    Target is the Entity the relationship points to.
*/
Target :: Entity

// Represents a concrete relationship instance for internal registry storage
Pair :: struct {
	relation: typeid,
	target:   Target,
}

/* 
    Utility to check if a typeid represents a relationship pair.
    Virtual/pair IDs are small counter values (less than 1MB) rather than valid pointers.
*/
is_pair :: #force_inline proc(id: typeid) -> bool {
	val := transmute(uintptr)id
	return val > 0 && val < 0x100000
}

// Internal constant for bit-tagging virtual typeids (not used when using small counter values)
VIRTUAL_BIT :: uintptr(0)

/*
    Example Relations:
    - IsChildOf (Relation) -> Parent (Target)
    - Likes (Relation) -> Food (Target)
*/

// Pre-defined relations
ChildOf :: struct {}
DependsOn :: struct {}
InstanceOf :: struct {}

relations_get_children :: proc(
	w: ^World,
	parent: Entity,
	relation_type: typeid,
	allocator := context.temp_allocator,
) -> []Entity {
	links, ok := w.target_index[parent]
	if !ok do return nil
	children := make([dynamic]Entity, allocator)
	for link in links {
		if info, found := w.filter_registry[link.pair_id]; found {
			if info.relation == relation_type {
				append(&children, link.source)
			}
		}
	}
	return children[:]
}

relations_has_parent :: proc(w: ^World, entity: Entity, relation_type: typeid) -> bool {
	comps, ok := world_get_all_components(w, entity, context.temp_allocator)
	if !ok do return false
	defer delete(comps, context.temp_allocator)
	for c in comps {
		if is_pair(c.id) {
			if info, found := w.filter_registry[c.id]; found {
				if info.relation == relation_type {
					return true
				}
			}
		}
	}
	return false
}

relations_get_parent :: proc(w: ^World, entity: Entity, relation_type: typeid) -> Entity {
	comps, ok := world_get_all_components(w, entity, context.temp_allocator)
	if !ok do return {}
	defer delete(comps, context.temp_allocator)
	for c in comps {
		if is_pair(c.id) {
			if info, found := w.filter_registry[c.id]; found {
				if info.relation == relation_type {
					return info.target
				}
			}
		}
	}
	return {}
}

relations_get_root :: proc(w: ^World, e: Entity, relation_type: typeid) -> Entity {
	curr := e
	for {
		parent := relations_get_parent(w, curr, relation_type)
		if parent == {} do break
		curr = parent
	}
	return curr
}
