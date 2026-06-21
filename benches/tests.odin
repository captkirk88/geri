#+feature using-stmt
package main

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:testing"
import "core:time"

import bench "../benchmark"
import "../ecs"
import "../ecs/params"
import systems "../ecs/systems"
import log "../logging"

benchmark_spawn :: proc(t: ^testing.T) {
	test_data :: struct {
		world: ecs.World,
	}

	data := test_data {
		world = ecs.new_world(),
	}
	defer ecs.world_destroy(&data.world)

	bench.run(
		"Spawn Entities",
		1_000_000,
		&data,
		proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_spawn(w)
			}
			return .Okay
		},
	)
}

benchmark_add_component :: proc(t: ^testing.T) {
	log.create()
	defer log.destroy()

	test_data :: struct {
		world: ecs.World,
		ent:   ecs.Entity,
	}

	data := test_data {
		world = ecs.new_world(),
	}
	data.ent = ecs.world_spawn(&data.world)
	defer {
		ecs.world_destroy(&data.world)
	}

	bench.run(
		"Add Component",
		1_000_000,
		&data,
		proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_add_component(w, data.ent, rand.int127_max(1000))
			}
			return .Okay
		},
	)
}

benchmark_add_bulk :: proc(t: ^testing.T) {
	log.create()
	defer log.destroy()

	test_data :: struct {
		world:    ecs.World,
		entities: []ecs.Entity,
		count:    int,
	}

	data := test_data {
		world    = ecs.new_world(),
		entities = make([]ecs.Entity, 1_000_000),
		count    = 1_000_000,
	}
	defer {
		delete(data.entities)
		ecs.world_destroy(&data.world)
	}

	for i in 1 ..= data.count {
		data.entities[i - 1] = ecs.world_spawn(&data.world)
	}

	
	bench_title := fmt.aprintf("Add Component Bulk (%d)", data.count)
	defer delete(bench_title)
	bench.run(
		bench_title,
		1_000,
		&data,
		proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_add_component_bulk(w, data.entities, rand.int127_max(1000))
			}
			return .Okay
		},
	)
}

benchmark_query :: proc(t: ^testing.T) {
	log.create()
	defer log.destroy()

	componentA :: struct {
		value: int,
	}
	componentB :: struct {
		value: int,
	}
	test_data :: struct {
		world:    ecs.World,
		entities: []ecs.Entity,
		count:    int,
	}

	data := test_data {
		world    = ecs.new_world(),
		entities = make([]ecs.Entity, 1_000_000),
		count    = 1_000_000,
	}
	defer {
		delete(data.entities)
		ecs.world_destroy(&data.world)
	}

	for i in 1 ..= data.count {
		e := ecs.world_spawn(&data.world)
		ecs.world_add_component(&data.world, e, i)
		data.entities[i - 1] = e
	}

	bench_title := fmt.aprintf("Query System (%d)", data.count)
	defer delete(bench_title)
	bench.run(
		bench_title,
		1000,
		&data,
		proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world

			for _ in 0 ..< opts.count {
				for arch in ecs.query(w, int, ecs.not(f32)) {
					values := ecs.arch_get_field(arch, int)
					for &v in values {
						v += 1
					}
				}
			}
			return .Okay
		},
	)
}

benchmark_systems :: proc(t: ^testing.T) {
	using systems
	log.create()
	defer log.destroy()

	Config :: struct {
		value: int,
	}
	w := ecs.new_world()
	defer ecs.world_destroy(&w)
	systems.world_init_default_params(&w)

	conf := Config{10}
	ecs.world_add_resource(&w, conf)

	MyEvent :: distinct int

	sys_proc := proc(
		cmds: ecs.Commands,
		config: params.Res(Config),
		writer: params.EventWriter(MyEvent),
		reader: params.EventReader(MyEvent),
	) {
		config.ptr.value += 1
		params.write(writer, MyEvent(5))
	}

	sys := new_system(sys_proc)
	defer destroy_system(&w, sys)

	data :: struct {
		world:     ^ecs.World,
		systems:   []^systems.System,
		ent_count: int,
	}
	sys_data := data {
		world     = &w,
		systems   = {sys},
		ent_count = 1_000_000,
	}

	for i in 1 ..= sys_data.ent_count {
		e := ecs.world_spawn(&w)
		ecs.world_add_component(&w, e, i)
	}

	run_count := 1000
	bench.run(
		"Systems Runner",
		run_count,
		&sys_data,
		proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^data)opts.user_data
			sys_arr := data.systems
			for _ in 0 ..< opts.count {
				for sys in sys_arr {
					systems.run_system(data.world, sys)
				}
			}
			return .Okay
		},
	)

	expect_conf := ecs.world_get_resource(&w, Config)
	testing.expect_value(t, expect_conf.value, 10 + run_count)
}

benchmark_serialize_entities :: proc(t: ^testing.T) {
	Test_Comp_A :: struct {
		x: f32,
		y: i32,
	}
	Test_Comp_B :: struct {
		active: bool,
		factor: f64,
	}

	test_data :: struct {
		world:  ecs.World,
		entity: ecs.Entity,
		count:  int,
	}

	data := test_data {
		world = ecs.new_world(),
		count = 1000,
	}
	defer ecs.world_destroy(&data.world)

	ecs.world_register_component(&data.world, Test_Comp_A)
	ecs.world_register_component(&data.world, Test_Comp_B)

	data.entity = ecs.world_spawn(&data.world)
	ecs.world_add_component(&data.world, data.entity, Test_Comp_A{x = 12.34, y = 5678})
	ecs.world_add_component(&data.world, data.entity, Test_Comp_B{active = true, factor = 98.76})

	bench.run("Serialize/Patch Entity", data.count, &data, proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
		data := cast(^test_data)opts.user_data
		w := &data.world
		e := data.entity

		for _ in 0 ..< opts.count {
			bytes, err := ecs.world_serialize_entity(w, e, allocator)
			if err != .None do return .Allocation_Error

			patch_err := ecs.world_patch_entity(w, e, bytes)
			delete(bytes, allocator)
			free_all(context.temp_allocator)
			if patch_err != .None do return .Allocation_Error
		}
		return .Okay
	})
}

benchmark_serialize_resources :: proc(t: ^testing.T) {
	Test_Res_A :: struct {
		score: int,
		index: int,
	}
	Test_Res_B :: struct {
		factor: f64,
		active: bool,
	}

	test_data :: struct {
		world: ecs.World,
		count: int,
	}

	data := test_data {
		world = ecs.new_world(),
		count = 1000,
	}
	defer ecs.world_destroy(&data.world)

	ecs.world_register_resource_serialization(&data.world, Test_Res_A)
	ecs.world_register_resource_serialization(&data.world, Test_Res_B)

	ecs.world_add_resource(&data.world, Test_Res_A{score = 9999, index = 1})
	ecs.world_add_resource(&data.world, Test_Res_B{factor = 3.14159, active = true})

	bench.run("Serialize/Deserialize Resources", data.count, &data, proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
		data := cast(^test_data)opts.user_data
		w := &data.world

		for _ in 0 ..< opts.count {
			bytes, err := ecs.world_serialize_all_resources(w, allocator)
			if err != .None do return .Allocation_Error

			patch_err := ecs.world_deserialize_all_resources(w, bytes)
			delete(bytes, allocator)
			free_all(context.temp_allocator)
			if patch_err != .None do return .Allocation_Error
		}
		return .Okay
	})
}

benchmark_serialization :: proc(t: ^testing.T) {
	benchmark_serialize_entities(t)
	benchmark_serialize_resources(t)
}

@(test)
run_all_benchmarks :: proc(t: ^testing.T) {
	benchmark_spawn(t)
	benchmark_add_component(t)
	benchmark_add_bulk(t)
	benchmark_query(t)
	benchmark_systems(t)
	benchmark_serialization(t)
	bench.finish_export()
}
