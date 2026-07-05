package app

import ecs "../ecs"
import params "../ecs/params"
import sys "../ecs/systems"
import "core:sync"
import "core:testing"
import "core:time"

Config_A :: struct {
	value: int,
}

Config_B :: struct {
	value: int,
}

Test_Context :: struct {
	order: [dynamic]string,
	mutex: sync.Mutex,
}

@(test)
test_schedule_conflicts_and_ordering :: proc(t: ^testing.T) {
	app := app_init()
	defer app_destroy(&app)

	ecs.world_add_resource(&app.world, Config_A{10})
	ecs.world_add_resource(&app.world, Config_B{20})

	ctx := Test_Context{}
	ctx.order = make([dynamic]string, app.world.allocator)
	defer delete(ctx.order)
	ecs.world_add_resource(&app.world, ctx)

	sys_a :: proc(a: params.Res(Config_A), ctx: params.Res(Test_Context)) {
		time.sleep(10 * time.Millisecond)
		sync.mutex_lock(&ctx.ptr.mutex)
		append(&ctx.ptr.order, "sys_a")
		sync.mutex_unlock(&ctx.ptr.mutex)
	}

	sys_b :: proc(a: params.Res(Config_A), ctx: params.Res(Test_Context)) {
		sync.mutex_lock(&ctx.ptr.mutex)
		append(&ctx.ptr.order, "sys_b")
		sync.mutex_unlock(&ctx.ptr.mutex)
	}

	sys_c :: proc(b: params.Res(Config_B), ctx: params.Res(Test_Context)) {
		time.sleep(5 * time.Millisecond)
		sync.mutex_lock(&ctx.ptr.mutex)
		append(&ctx.ptr.order, "sys_c")
		sync.mutex_unlock(&ctx.ptr.mutex)
	}

	app_add_system(&app, Update, sys_a)
	app_add_system(&app, Update, sys_b)
	app_add_system(&app, Update, sys_c)

	app_run_schedule(&app, Update)

	sched := app.schedules[Update]
	testing.expect(t, len(sched.levels) >= 2)

	// Clean up resources to prevent memory leaks
	retrieved_ctx := ecs.world_get_resource(&app.world, Test_Context)
	if retrieved_ctx != nil {
		delete(retrieved_ctx.order)
	}
}

@(test)
test_explicit_ordering :: proc(t: ^testing.T) {
	app := app_init()
	defer app_destroy(&app)

	ctx := Test_Context{}
	ctx.order = make([dynamic]string, app.world.allocator)
	defer delete(ctx.order)
	ecs.world_add_resource(&app.world, ctx)

	sys_first :: proc(ctx: params.Res(Test_Context)) {
		if sync.mutex_guard(&ctx.ptr.mutex) {
			append(&ctx.ptr.order, "first")
		}
	}

	sys_second :: proc(ctx: params.Res(Test_Context)) {
		if sync.mutex_guard(&ctx.ptr.mutex) {
			append(&ctx.ptr.order, "second")
		}
	}

	app_add_system(&app, Update, sys_second, after = []rawptr{rawptr(sys_first)})
	app_add_system(&app, Update, sys_first)

	app_run_schedule(&app, Update)

	retrieved_ctx := ecs.world_get_resource(&app.world, Test_Context)
	testing.expect(t, retrieved_ctx != nil)
	if retrieved_ctx != nil {
		testing.expect_value(t, len(retrieved_ctx.order), 2)
		if len(retrieved_ctx.order) == 2 {
			testing.expect_value(t, retrieved_ctx.order[0], "first")
			testing.expect_value(t, retrieved_ctx.order[1], "second")
		}
		delete(retrieved_ctx.order)
	}
}

@(test)
test_custom_schedules :: proc(t: ^testing.T) {
	app := app_init()
	defer app_destroy(&app)

	Custom_Label: Schedule_Label : "MyCustomSchedule"

	ctx := Test_Context{}
	ctx.order = make([dynamic]string, app.world.allocator)
	defer delete(ctx.order)
	ecs.world_add_resource(&app.world, ctx)

	sys_custom :: proc(ctx: params.Res(Test_Context)) {
		if sync.mutex_guard(&ctx.ptr.mutex) {
			append(&ctx.ptr.order, "custom_run")
		}
	}

	app_add_system(&app, Custom_Label, sys_custom)

	// Verify that the schedule was dynamically created in the schedules map
	testing.expect(t, Custom_Label in app.schedules)

	app_run_schedule(&app, Custom_Label)

	retrieved_ctx := ecs.world_get_resource(&app.world, Test_Context)
	testing.expect(t, retrieved_ctx != nil)
	if retrieved_ctx != nil {
		testing.expect_value(t, len(retrieved_ctx.order), 1)
		if len(retrieved_ctx.order) == 1 {
			testing.expect_value(t, retrieved_ctx.order[0], "custom_run")
		}
		delete(retrieved_ctx.order)
	}
}

@(test)
test_render_schedule_main_thread :: proc(t: ^testing.T) {
	app := app_init()
	defer app_destroy(&app)

	Render_Label : Schedule_Label : "MyCustomRenderSchedule"

	My_Res_A :: struct { value: int }
	My_Res_B :: struct { value: int }

	ecs.world_add_resource(&app.world, My_Res_A{10})
	ecs.world_add_resource(&app.world, My_Res_B{20})

	sys_render_a :: proc(a: params.Res(My_Res_A)) {
		a.ptr.value += 1
	}

	sys_render_b :: proc(b: params.Res(My_Res_B)) {
		b.ptr.value += 2
	}

	app_add_system(&app, Render_Label, sys_render_a)
	app_add_system(&app, Render_Label, sys_render_b)

	app_run_schedule(&app, Render_Label)

	res_a := ecs.world_get_resource(&app.world, My_Res_A)
	res_b := ecs.world_get_resource(&app.world, My_Res_B)
	testing.expect(t, res_a != nil && res_a.value == 11)
	testing.expect(t, res_b != nil && res_b.value == 22)
}

@(test)
test_modify_system :: proc(t: ^testing.T) {
	app := app_init()
	defer app_destroy(&app)

	ctx := Test_Context{}
	ctx.order = make([dynamic]string, app.world.allocator)
	defer delete(ctx.order)
	ecs.world_add_resource(&app.world, ctx)

	sys_first :: proc(ctx: params.Res(Test_Context)) {
		if sync.mutex_guard(&ctx.ptr.mutex) {
			append(&ctx.ptr.order, "first")
		}
	}

	sys_second :: proc(ctx: params.Res(Test_Context)) {
		if sync.mutex_guard(&ctx.ptr.mutex) {
			append(&ctx.ptr.order, "second")
		}
	}

	// Register systems without constraints
	app_add_system(&app, Update, sys_second)
	app_add_system(&app, Update, sys_first)

	// Modify sys_second to run after sys_first
	ok := app_modify_system(&app, Update, rawptr(sys_second), after = []rawptr{rawptr(sys_first)})
	testing.expect(t, ok, "app_modify_system should return true for registered system")

	app_run_schedule(&app, Update)

	retrieved_ctx := ecs.world_get_resource(&app.world, Test_Context)
	testing.expect(t, retrieved_ctx != nil)
	if retrieved_ctx != nil {
		testing.expect_value(t, len(retrieved_ctx.order), 2)
		if len(retrieved_ctx.order) == 2 {
			testing.expect_value(t, retrieved_ctx.order[0], "first")
			testing.expect_value(t, retrieved_ctx.order[1], "second")
		}
		delete(retrieved_ctx.order)
	}
}


