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
    We reserve the high bit of the ID for virtual/pair IDs.
*/
is_pair :: #force_inline proc(id: typeid) -> bool {
	return (transmute(uintptr)id & VIRTUAL_BIT) != 0
}

// Internal constant for bit-tagging virtual typeids
VIRTUAL_BIT :: uintptr(1) << 63

/*
    Example Relations:
    - IsChildOf (Relation) -> Parent (Target)
    - Likes (Relation) -> Food (Target)
*/

// Pre-defined relations
ChildOf :: struct {}
DependsOn :: struct {}
InstanceOf :: struct {}
