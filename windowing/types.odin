package windowing

import "../app"
import "vendor:sdl3"


Window_Descriptor :: struct {
	title:      string,
	width:      i32,
	height:     i32,
	fullscreen: bool,
	resizable:  bool,
}

Window_Context :: struct {
	window: ^sdl3.Window,
}

Window_Resized_Event :: struct {
	width:  i32,
	height: i32,
}

Window_Focus_Changed_Event :: enum {
	Gained,
	Lost,
}

Window_Orientation_Changed :: struct {}

Window_Closed_Event :: struct {}
