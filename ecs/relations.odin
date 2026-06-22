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
