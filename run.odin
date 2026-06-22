package main

import "ecs"
import log "logging"
import logrl "logging/raylib"
import rl "vendor:raylib"

main :: proc() {
	logrl.init_raylib_logging()
	defer logrl.deinit_raylib_logging()
	console_output := log.create_console_output(
		.Debug,
		{
			enable_color = true,
			time_format  = .Short_UTC,
			options      = {.Time, .Level, .Short_File_Path, .Thread_Id, .Terminal_Color},
			template     = "[c=green][time][/c] [c=yellow][[location]][/c] [b][level][/b]: [if level==debug: [c=yellow][message][/c] ? [c=gray][message][/c]]",
		},
	)
	log.clear_outputs()
	log.add_output(console_output)
    
    
	world := ecs.new_world()
	defer ecs.world_destroy(&world)

	for i in 0 ..< 5 {
        e := ecs.world_spawn(&world)
        ecs.world_add_component(&world, e, 100)
    }

    log.debug("Spawned %d entities", len(world.entities))

    rl.InitWindow(800, 600, "Raylib Logging Test")
    defer rl.CloseWindow()
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        rl.EndDrawing()
    }
}
