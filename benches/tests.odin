#+feature using-stmt
package main

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:testing"
import "core:time"

import app "../app"
import bench "../benchmark"
import "../ecs"
import "../ecs/params"
import systems "../ecs/systems"
import log "../logging"

benchmark_spawn :: proc(t: ^testing.T) {
	test_data :: struct {
		world: ecs.World,
	}

	opts := time.Benchmark_Options {
		count = 1_000_000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_spawn(w)
			}
			return .Okay
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Spawn Entities", &opts)
}

benchmark_add_component :: proc(t: ^testing.T) {
	test_data :: struct {
		world: ecs.World,
		ent:   ecs.Entity,
	}

	opts := time.Benchmark_Options {
		count = 1_000_000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			data.ent = ecs.world_spawn(&data.world)
			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_add_component(w, data.ent, rand.int127_max(1000))
			}
			return .Okay
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Add Component", &opts)
}

benchmark_add_bulk :: proc(t: ^testing.T) {
	test_data :: struct {
		world:    ecs.World,
		entities: []ecs.Entity,
		count:    int,
	}

	opts := time.Benchmark_Options {
		count = 1_000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			data.count = 1_000_000
			data.entities = make([]ecs.Entity, data.count, allocator)
			for i in 1 ..= data.count {
				data.entities[i - 1] = ecs.world_spawn(&data.world)
			}
			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			w := &data.world
			for i in 0 ..< opts.count {
				ecs.world_add_component_bulk(w, data.entities, rand.int127_max(1000))
			}
			return .Okay
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			delete(data.entities, allocator)
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench_title := fmt.aprintf("Add Component Bulk (%d)", 1_000_000)
	defer delete(bench_title)
	bench.run(bench_title, &opts)
}

benchmark_query :: proc(t: ^testing.T) {
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

	opts := time.Benchmark_Options {
		count = 1000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			data.count = 1_000_000
			data.entities = make([]ecs.Entity, data.count, allocator)

			for i in 1 ..= data.count {
				e := ecs.world_spawn(&data.world)
				ecs.world_add_component(&data.world, e, i)
				data.entities[i - 1] = e
			}

			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
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
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			delete(data.entities, allocator)
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench_title := fmt.aprintf("Query System (%d)", 1_000_000)
	defer delete(bench_title)
	bench.run(bench_title, &opts)
}

benchmark_systems :: proc(t: ^testing.T) {
	using systems

	Config :: struct {
		value: int,
	}

	MyEvent :: distinct int

	sys_proc :: proc(
		cmds: ecs.Commands,
		config: params.Res(Config),
		writer: params.EventWriter(MyEvent),
		reader: params.EventReader(MyEvent),
	) {
		config.ptr.value += 1
		params.write(writer, MyEvent(5))
	}

	test_data :: struct {
		world:     ecs.World,
		system:    ^systems.System,
		systems:   []^systems.System,
		ent_count: int,
	}

	run_count := 1000

	opts := time.Benchmark_Options {
		count = run_count,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			systems.world_init_default_params(&data.world)

			conf := Config{10}
			ecs.world_add_resource(&data.world, conf)

			data.system = new_system(sys_proc, allocator = allocator)
			data.systems = make([]^systems.System, 1, allocator)
			data.systems[0] = data.system
			data.ent_count = 1_000_000

			for i in 1 ..= data.ent_count {
				e := ecs.world_spawn(&data.world)
				ecs.world_add_component(&data.world, e, i)
			}

			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			sys_arr := data.systems
			for _ in 0 ..< opts.count {
				for sys in sys_arr {
					systems.run_system(&data.world, sys)
				}
			}
			return .Okay
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			destroy_system(&data.world, data.system, allocator = allocator)
			delete(data.systems, allocator)
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Systems Runner", &opts)
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

	opts := time.Benchmark_Options {
		count = 1000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			data.count = 1000

			ecs.world_register_component(&data.world, Test_Comp_A)
			ecs.world_register_component(&data.world, Test_Comp_B)

			data.entity = ecs.world_spawn(&data.world)
			ecs.world_add_component(&data.world, data.entity, Test_Comp_A{x = 12.34, y = 5678})
			ecs.world_add_component(&data.world, data.entity, Test_Comp_B{active = true, factor = 98.76})

			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
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
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Serialize/Patch Entity", &opts)
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

	opts := time.Benchmark_Options {
		count = 1000,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(test_data, allocator)
			data.world = ecs.new_world(allocator)
			data.count = 1000

			ecs.world_register_resource_serialization(&data.world, Test_Res_A)
			ecs.world_register_resource_serialization(&data.world, Test_Res_B)

			ecs.world_add_resource(&data.world, Test_Res_A{score = 9999, index = 1})
			ecs.world_add_resource(&data.world, Test_Res_B{factor = 3.14159, active = true})

			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
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
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^test_data)opts.user_data
			ecs.world_destroy(&data.world)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Serialize/Deserialize Resources", &opts)
}

benchmark_serialization :: proc(t: ^testing.T) {
	benchmark_serialize_entities(t)
	benchmark_serialize_resources(t)
}

Position :: struct {
	x: f32,
	y: f32,
	z: f32,
}

Velocity :: struct {
	x: f32,
	y: f32,
	z: f32,
}

Health :: struct {
	hp:     f32,
	max_hp: f32,
}

Enemy :: struct {
	target: ecs.Entity,
}

Transform :: struct {
	m: [16]f32,
}

Sound :: struct {
	volume: f32,
}

World_Ref :: struct {
	world: ^ecs.World,
}

benchmark_app_schedules :: proc(t: ^testing.T) {
	using app

	// Define 7 systems
	sys_physics :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Position, Velocity) {
			pos := ecs.arch_get_field(arch, Position)
			vel := ecs.arch_get_field(arch, Velocity)
			for i in 0 ..< len(pos) {
				pos[i].x += vel[i].x * 0.016
				pos[i].y += vel[i].y * 0.016
				pos[i].z += vel[i].z * 0.016
			}
		}
	}

	sys_ai :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Enemy, Position) {
			enemy := ecs.arch_get_field(arch, Enemy)
			pos := ecs.arch_get_field(arch, Position)
			for i in 0 ..< len(pos) {
				target_pos := ecs.world_get_component(w, enemy[i].target, Position)
				if target_pos != nil {
					pos[i].x += (target_pos.x - pos[i].x) * 0.1
					pos[i].y += (target_pos.y - pos[i].y) * 0.1
					pos[i].z += (target_pos.z - pos[i].z) * 0.1
				}
			}
		}
	}

	sys_collision :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Position, Health) {
			pos := ecs.arch_get_field(arch, Position)
			health := ecs.arch_get_field(arch, Health)
			for i in 0 ..< len(pos) {
				if pos[i].z < -10.0 {
					health[i].hp -= 10.0
				}
			}
		}
	}

	sys_gameplay :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Health) {
			health := ecs.arch_get_field(arch, Health)
			for i in 0 ..< len(health) {
				if health[i].hp > 0.0 && health[i].hp < health[i].max_hp {
					health[i].hp = min(health[i].max_hp, health[i].hp + 0.1)
				}
			}
		}
	}

	sys_animation :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Transform, Position) {
			transform := ecs.arch_get_field(arch, Transform)
			pos := ecs.arch_get_field(arch, Position)
			for i in 0 ..< len(transform) {
				transform[i].m[12] = pos[i].x
				transform[i].m[13] = pos[i].y
				transform[i].m[14] = pos[i].z
			}
		}
	}

	sys_audio :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		for arch in ecs.query(w, Sound, Position, ecs.not(Transform)) {
			sound := ecs.arch_get_field(arch, Sound)
			pos := ecs.arch_get_field(arch, Position)
			for i in 0 ..< len(sound) {
				dist := pos[i].x * pos[i].x + pos[i].y * pos[i].y + pos[i].z * pos[i].z
				sound[i].volume = 1.0 / (1.0 + dist * 0.01)
			}
		}
	}

	sys_render :: proc(world_ref: params.Res(World_Ref)) {
		w := world_ref.ptr.world
		draw_count := 0
		for arch in ecs.query(w, Transform) {
			transform := ecs.arch_get_field(arch, Transform)
			draw_count += len(transform)
		}
	}

	bench_data :: struct {
		application:                                                app.App,
		physics, ai, collision, gameplay, animation, audio, render: app.Schedule_Label,
	}

	opts := time.Benchmark_Options {
		count = 100,
		setup = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := new(bench_data, allocator)
			data.application = app_init(allocator = allocator)

			// Add World_Ref resource
			world_ref := World_Ref {
				world = &data.application.world,
			}
			ecs.world_add_resource(&data.application.world, world_ref)

			// Create entities
			entities := make([]ecs.Entity, 100_000, allocator)
			defer delete(entities, allocator)

			for i in 0 ..< len(entities) {
				e := ecs.world_spawn(&data.application.world)
				ecs.world_add_component(&data.application.world, e, Position{0, 0, 0})
				ecs.world_add_component(&data.application.world, e, Velocity{1, 2, 3})
				ecs.world_add_component(&data.application.world, e, Health{100, 100})
				ecs.world_add_component(&data.application.world, e, Transform{})
				ecs.world_add_component(&data.application.world, e, Sound{1.0})
				entities[i] = e
			}

			// Add Enemy component targeting the next entity
			for i in 0 ..< len(entities) {
				target_idx := (i + 1) % 1000
				ecs.world_add_component(&data.application.world, entities[i], Enemy{target = entities[target_idx]})
			}

			// Define 7 different labels using app.Schedule_Label
			data.physics = "Physics"
			data.ai = "AI"
			data.collision = "Collision"
			data.gameplay = "Gameplay"
			data.animation = "Animation"
			data.audio = "Audio"
			data.render = "Render"

			labels := [7]app.Schedule_Label {
				data.physics,
				data.ai,
				data.collision,
				data.gameplay,
				data.animation,
				data.audio,
				data.render,
			}

			for i in 0 ..< 100 {
				label := labels[i % 7]
				switch i % 7 {
				case 0:
					app_add_system(&data.application, label, sys_physics)
				case 1:
					app_add_system(&data.application, label, sys_ai)
				case 2:
					app_add_system(&data.application, label, sys_collision)
				case 3:
					app_add_system(&data.application, label, sys_gameplay)
				case 4:
					app_add_system(&data.application, label, sys_animation)
				case 5:
					app_add_system(&data.application, label, sys_audio)
				case 6:
					app_add_system(&data.application, label, sys_render)
				}
			}

			opts.user_data = data
			return .Okay
		},
		bench = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^bench_data)opts.user_data
			for _ in 0 ..< opts.count {
				app_run_schedule(&data.application, data.physics)
				app_run_schedule(&data.application, data.ai)
				app_run_schedule(&data.application, data.collision)
				app_run_schedule(&data.application, data.gameplay)
				app_run_schedule(&data.application, data.animation)
				app_run_schedule(&data.application, data.audio)
				app_run_schedule(&data.application, data.render)
			}
			return .Okay
		},
		teardown = proc(opts: ^time.Benchmark_Options, allocator: mem.Allocator) -> time.Benchmark_Error {
			data := cast(^bench_data)opts.user_data
			app_destroy(&data.application)
			free(data, allocator)
			return .Okay
		},
	}

	bench.run("Scheduler 7 labels, 100 systems, 100k entities", &opts)
}

@(test)
run_all_benchmarks :: proc(t: ^testing.T) {
	benchmark_spawn(t)
	benchmark_add_component(t)
	benchmark_add_bulk(t)
	benchmark_query(t)
	benchmark_systems(t)
	benchmark_app_schedules(t)
	benchmark_serialization(t)
	bench.finish_export()
}
