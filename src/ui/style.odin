package ui

// Visual styles for a single UI interaction state.
UI_State_Style :: struct {
	bg_color:     [4]f32,
	border_color: [4]f32,
	border_width: f32, // negative values mean inherit/ignore
	text_color:   [4]f32,
}

// Styling component that decouples visual states from UI elements.
UI_Style :: struct {
	normal:   UI_State_Style,
	hover:    UI_State_Style,
	active:   UI_State_Style,
	disabled: UI_State_Style,
}
