package ecs

import "core:container/intrusive/list"
import "core:hash"
import "core:slice"
import "core:sync"
import "base:runtime"

/*
    Terms - These encode complex query logic into typeids.
    The Registry stores the actual meaning of these virtual IDs.
*/
Term :: struct {
	op:       Filter_Op,
	types:    []typeid,
	target:   Entity, // Used for pairs
	relation: typeid, // Used for hierarchy/pairs
}

Filter_Op :: enum {
	And,
	Or,
	Not,
	Pair,
	Hierarchy,
	OnAdd,
	OnRemove,
}

Query_Result :: struct {
	archetypes: []^Archetype,
}

QueryProc :: #type proc() -> Query_Result

Filter_Info :: struct {
	op:       Filter_Op,
	types:    []typeid,
	target:   Entity, // Used for pairs
	relation: typeid, // Used for hierarchy/pairs
}

// Internal registry to map virtual typeids to their filter definitions

@(private)
hash_filter_info :: proc(op: Filter_Op, types: []typeid, target: Entity, relation: typeid) -> u64 {
	h := hash.fnv64a(slice.to_bytes([]Filter_Op{op}))
	if len(types) > 0 {
		h = hash.fnv64a(slice.to_bytes(types), h)
	}
	h = hash.fnv64a(slice.to_bytes([]Entity{target}), h)
	h = hash.fnv64a(slice.to_bytes([]typeid{relation}), h)
	return h
}

world_resolve_term :: proc(w: ^World, term: Term) -> typeid {
	sync.mutex_lock(&w.cache_mutex)
	defer sync.mutex_unlock(&w.cache_mutex)
	
	types := term.types
	if w.filter_registry == nil {
		w.filter_registry = make(map[typeid]Filter_Info, 16, w.allocator)
		w.filter_dedup = make(map[u64]typeid, 16, w.allocator)
	}

	// Sort types to ensure consistent hashing for commutative operations (and/or)
	if len(types) > 1 {
		slice.sort_by(types, proc(i, j: typeid) -> bool {
			return transmute(uintptr)i < transmute(uintptr)j
		})
	}

	h := hash_filter_info(term.op, types, term.target, term.relation)
	if id, ok := w.filter_dedup[h]; ok do return id

	if w.virtual_id_counter == 0 do w.virtual_id_counter = 1
	id_val := w.virtual_id_counter | VIRTUAL_BIT
	w.virtual_id_counter += 1

	id := transmute(typeid)id_val
	w.filter_registry[id] = {
		op = term.op,
		types = slice.clone(types, w.allocator),
		target = term.target,
		relation = term.relation,
	}
	w.filter_dedup[h] = id
	return id
}

@(private)
// lifecycle events
on_add :: proc(t: typeid) -> Term {
	return { op = .OnAdd, types = slice.clone([]typeid{t}, context.temp_allocator) }
}

on_rm :: proc(t: typeid) -> Term {
	return { op = .OnRemove, types = slice.clone([]typeid{t}, context.temp_allocator) }
}
on_remove :: on_rm

// require ALL of these types
and :: proc(types: ..typeid) -> Term {
	return { op = .And, types = slice.clone(types, context.temp_allocator) }
}

all :: proc(types: ..typeid) -> Term {return and(..types)}

// require SOME (at least one) of these types
some :: proc(types: ..typeid) -> Term {
	return { op = .Or, types = slice.clone(types, context.temp_allocator) }
}
or :: some

// require NONE of these types
not :: proc(types: ..typeid) -> Term {
	return { op = .Not, types = slice.clone(types, context.temp_allocator) }
}
none :: not

// creates a relationship term (Relation, Target)
pair :: proc($Rel: typeid, target: Target) -> Term {
	return { op = .Pair, target = target, relation = typeid_of(Rel) }
}

// creates a depth-ordered iteration filter based on a relation
hierarchy :: proc($R: typeid) -> Term {
	return { op = .Hierarchy, relation = typeid_of(R) }
}

/*
    Query Structure
*/
Query :: struct {
	world:   ^World,
	include: [dynamic]typeid,
	exclude: [dynamic]typeid,
	any_:     [dynamic]typeid,
}

query_init :: proc(w: ^World, terms: []any) -> Query {
	q := Query {
		world = w,
	}
	for t_val in terms {
		tid: typeid
		if val, ok := t_val.(typeid); ok do tid = val
		else if val, ok := t_val.(Term); ok do tid = world_resolve_term(w, val)
		else do continue

		if !is_pair(tid) {
			append(&q.include, tid)
			continue
		}

		info, ok := w.filter_registry[tid]
		if !ok do continue

		#partial switch info.op {
		case .And:
			for sub in info.types do append(&q.include, sub)
		case .Or:
			for sub in info.types do append(&q.any_, sub)
		case .Not:
			for sub in info.types do append(&q.exclude, sub)
		case .Pair, .Hierarchy:
			// Archetype matching logic for relations would go here
			append(&q.include, tid)
		}
	}
	return q
}

query_destroy :: proc(q: ^Query) {
	delete(q.include)
	delete(q.exclude)
	delete(q.any_)
}
