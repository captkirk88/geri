package ui

// Hoverable/Clickable button state tracker.
Button :: struct {
	is_hovered:  bool,
	is_pressed:  bool,
	is_clicked:  bool,
}

// Text rendering element that automatically displays font textures.
Label :: struct {
	text:      string,
	color:     [4]f32,
	font_size: f32, // 0 = derive from font's default size
}

// Checkbox selection control component.
Checkbox :: struct {
	checked:      bool,
	active_color: [4]f32,
}

// Horizontal slider control component.
Slider :: struct {
	value:        f32, // normalized range [0.0, 1.0]
	active_color: [4]f32,
	knob_color:   [4]f32,
}
