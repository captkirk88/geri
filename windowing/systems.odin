package windowing

import "../app"
import "../ecs/params"
import "vendor:sdl3"

event_pump_system :: proc(
	exit_writer: params.EventWriter(app.App_Exit_Event),
	resize_writer: params.EventWriter(Window_Resized_Event),
	focus_writer: params.EventWriter(Window_Focus_Changed_Event),
	close_writer: params.EventWriter(Window_Closed_Event),
	sdl_event_writer: params.EventWriter(sdl3.Event),
) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		params.write(sdl_event_writer, event)

		#partial switch event.type {
		case .WINDOW_RESIZED:
			params.write(
				resize_writer,
				Window_Resized_Event{width = event.window.data1, height = event.window.data2},
			)

		// FOCUS EVENTS
		case .WINDOW_EXPOSED:
			params.write(focus_writer, Window_Focus_Changed_Event.Gained)
		case .WINDOW_HIDDEN, .WINDOW_FOCUS_LOST:
			params.write(focus_writer, Window_Focus_Changed_Event.Lost)

		// CLOSE/QUIT EVENTS
		case .WINDOW_CLOSE_REQUESTED, .QUIT:
			params.write(close_writer, Window_Closed_Event{})
			params.write(exit_writer, app.App_Exit_Event{})
		}
	}
}
