package app

import ecs "../ecs"
import sys "../ecs/systems"
import "base:intrinsics"
import "core:strings"
import "core:sync"

Plugin :: struct {
	build:   proc(plugin: Plugin, app: ^App),
	destroy: proc(plugin: Plugin, app: ^App),
	data:    rawptr,
}

App :: struct {
	world:        ecs.World,
	schedules:    map[Schedule_Label]^Schedule,
	should_exit:  bool,
	mutex:        sync.Mutex,
	thread_count: int,
}

Schedule_Label :: distinct string

App_Exit_Event :: struct {}

Startup: Schedule_Label : "Startup"
First: Schedule_Label : "First"
PreUpdate: Schedule_Label : "PreUpdate"
Update: Schedule_Label : "Update"
PostUpdate: Schedule_Label : "PostUpdate"
Last: Schedule_Label : "Last"
PreRender: Schedule_Label : "PreRender"
Render: Schedule_Label : "Render"
PostRender: Schedule_Label : "PostRender"

// Initializes a new App instance, setting up its ECS world, default schedules, default thread count (4), and running any provided plugins.
app_init :: proc(plugins: []Plugin = nil, allocator := context.allocator) -> App {
	app: App
	app.world = ecs.new_world(allocator)
	sys.world_init_default_params(&app.world)
	app.thread_count = 4
	app.schedules = make(map[Schedule_Label]^Schedule, 16, allocator)

	app.schedules[Startup] = schedule_new(app.thread_count, allocator)
	app.schedules[First] = schedule_new(app.thread_count, allocator)
	app.schedules[PreUpdate] = schedule_new(app.thread_count, allocator)
	app.schedules[Update] = schedule_new(app.thread_count, allocator)
	app.schedules[PostUpdate] = schedule_new(app.thread_count, allocator)
	app.schedules[Last] = schedule_new(app.thread_count, allocator)
	app.schedules[PreRender] = schedule_new(1, allocator)
	app.schedules[Render] = schedule_new(1, allocator)
	app.schedules[PostRender] = schedule_new(1, allocator)

	for p in plugins {
		if p.build != nil {
			p->build(&app)
		}
	}

	for p in plugins {
		if p.destroy != nil {
			p->destroy(&app)
		}
	}

	return app
}

// Destroys the App instance, freeing all schedules and the ECS world.
app_destroy :: proc(app: ^App) {
	sync.mutex_lock(&app.mutex)
	defer sync.mutex_unlock(&app.mutex)

	for _, sched in app.schedules {
		schedule_destroy(&app.world, sched)
	}
	delete(app.schedules)

	ecs.world_destroy(&app.world)
}

// Adds a resource to the application's ECS world.
app_add_resource :: proc(app: ^App, resource: $T) {
	ecs.world_add_resource(&app.world, resource)
}

// Registers a system procedure into the specified schedule, dynamically creating the schedule if it does not exist.
// If not specified, the system name defaults to the compile-time expression passed into the procedure argument.
app_add_system :: proc(
	app: ^App,
	schedule_label: Schedule_Label,
	procedure: $T,
	name := #caller_expression(procedure),
	before: []rawptr = nil,
	after: []rawptr = nil,
) where intrinsics.type_is_proc(T) {
	sync.mutex_lock(&app.mutex)
	if schedule_label not_in app.schedules {
		app.schedules[schedule_label] = schedule_new(app.thread_count, app.world.allocator)
	}
	sched := app.schedules[schedule_label]
	sync.mutex_unlock(&app.mutex)

	schedule_add_system(sched, &app.world, procedure, name, before, after)
}

// Returns true if the schedule label requires the main thread (e.g. rendering, event pumping).
is_main_thread_schedule :: proc(label: Schedule_Label) -> bool {
	if label == First do return true
	label_str := string(label)
	return strings.contains(strings.to_lower(label_str, context.temp_allocator), "render")
}

// Compiles and runs all systems registered in the specified schedule, executing independent systems concurrently.
app_run_schedule :: proc(app: ^App, schedule_label: Schedule_Label) {
	sync.mutex_lock(&app.mutex)
	sched, ok := app.schedules[schedule_label]
	thread_count := app.thread_count
	sync.mutex_unlock(&app.mutex)

	if ok && sched != nil {
		if is_main_thread_schedule(schedule_label) {
			thread_count = 1
		}
		schedule_run(&app.world, sched, thread_count)
	}
}

// Runs a single frame update iteration, executing the update schedules (First, PreUpdate, Update, PostUpdate, Last, Render).
app_update :: proc(app: ^App) {
	app_run_schedule(app, First)
	app_run_schedule(app, PreUpdate)
	app_run_schedule(app, Update)
	app_run_schedule(app, PostUpdate)
	app_run_schedule(app, Last)
	app_run_schedule(app, PreRender)
	app_run_schedule(app, Render)
	app_run_schedule(app, PostRender)

	if App_Exit_Event in app.world.event_manager.history {
		buf := app.world.event_manager.history[App_Exit_Event]
		if buf.count > 0 {
			app.should_exit = true
		}
	}

	ecs.world_clear_events(&app.world)
}

// Runs the main application loop, executing Startup schedule and continuously updating the app until should_exit is set to true.
app_run :: proc(app: ^App) {
	app_run_schedule(app, Startup)

	for !app.should_exit {
		app_update(app)
	}
}
