package windowing

import "../app"
import "../ecs/params"
import "vendor:sdl3"

event_pump_system :: proc(
	exit_writer: params.EventWriter(app.App_Exit_Event),
	resize_writer: params.EventWriter(Window_Resized_Event),
	close_writer: params.EventWriter(Window_Closed_Event),
	sdl_event_writer: params.EventWriter(sdl3.Event),
) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		params.write(sdl_event_writer, event)

		#partial switch event.type {
		case .QUIT:
			params.write(exit_writer, app.App_Exit_Event{})
		case .WINDOW_RESIZED:
			params.write(
				resize_writer,
				Window_Resized_Event{width = event.window.data1, height = event.window.data2},
			)
		case .WINDOW_CLOSE_REQUESTED:
			params.write(close_writer, Window_Closed_Event{})
			params.write(exit_writer, app.App_Exit_Event{})
		}
	}
}
