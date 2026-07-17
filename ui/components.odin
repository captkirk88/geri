package ui

import "../ecs"
import graphics "../graphics"
import input "../input"

// UI-specific parent-child relationship tag to avoid tracking global ecs.ChildOf
UI_ChildOf :: struct {}

// The unit of measurement for a UI_Size value (pixels, percent, or auto).
UI_Size_Unit :: enum {
	// Pixels means the size is specified in absolute pixels.
	Pixels,
	// Percent means the size is a percentage of the parent container's size.
	Percent,
	// Auto means the size is determined by the content or layout rules.
	Auto,
}

// A size value with a unit (pixels, percent, or auto).
UI_Size :: struct {
	val:  f32,
	unit: UI_Size_Unit,
}

// Rectangle of the UI element in screen space coordinates (pixels)
UI_Rect :: struct {
	x, y, w, h: f32,
}

// UI Node represents a single element in the UI hierarchy. It contains layout and styling information.
UI_Node :: struct {
	width:        UI_Size,
	height:       UI_Size,
	padding:      [4]f32, // top, right, bottom, left
	margin:       [4]f32, // top, right, bottom, left
	bg_color:      [4]f32,
	border_color:  [4]f32,
	border_width:  f32,
	rect:          UI_Rect,
	clip_children: bool,
}

Layout_Flex_Direction :: enum {
	Row,
	Column,
}

Layout_Justify_Content :: enum {
	// Start means items are packed toward the start of the flex-direction.
	Start,
	// End means items are packed toward the end of the flex-direction.
	End,
	// Center means items are centered along the flex-direction.
	Center,
	// Space_Between means items are evenly distributed in the line; first item is on the start line, last item on the end line.
	Space_Between,
	// Space_Around means items are evenly distributed in the line with equal space around them.
	Space_Around,
	// Space_Evenly means items are distributed so that the spacing between any two items (and the space to the edges) is equal.
	Space_Evenly,
}

Layout_Align_Items :: enum {
	// Start means items are aligned to the start of the cross-axis.
	Start,
	// End means items are aligned to the end of the cross-axis.
	End,
	// Center means items are centered along the cross-axis.
	Center,
	// Stretch means items are stretched to fill the container along the cross-axis.
	Stretch,
}

// The flex layout properties for a UI element in a flex layout.
Layout_Flex :: struct {
	direction:       Layout_Flex_Direction,
	justify_content: Layout_Justify_Content,
	align_items:     Layout_Align_Items,
	gap:             f32,
}

// The flex grow and shrink factors for a UI element in a flex layout.
Flex_Item :: struct {
	grow:   f32,
	shrink: f32,
}

// The grid layout properties for a UI element in a grid layout.
Layout_Grid :: struct {
	columns:    int,
	rows:       int,
	column_gap: f32,
	row_gap:    f32,
}

// The grid item properties for a UI element in a grid layout.
Grid_Item :: struct {
	column_start: int,
	column_span:  int,
	row_start:    int,
	row_span:     int,
}

grid_item_all :: proc() -> Grid_Item {
	return Grid_Item{column_start = 0, column_span = 1, row_start = 0, row_span = 1}
}

grid_item_col_span :: proc(col_span: int) -> Grid_Item {
	return Grid_Item{column_start = 0, column_span = col_span, row_start = 0, row_span = 1}
}

grid_item_row_span :: proc(row_span: int) -> Grid_Item {
	return Grid_Item{column_start = 0, column_span = 1, row_start = 0, row_span = row_span}
}

grid_item_col_start :: proc(col_start: int) -> Grid_Item {
	return Grid_Item{column_start = col_start, column_span = 1, row_start = 0, row_span = 1}
}

grid_item_row_start :: proc(row_start: int) -> Grid_Item {
	return Grid_Item{column_start = 0, column_span = 1, row_start = row_start, row_span = 1}
}

// The anchor properties for a UI element, defining how it is positioned relative to its parent.
Layout_Anchor :: struct {
	// {left, top} relative to parent content bounds [0.0 - 1.0]
	anchor_min: [2]f32,
	// {right, bottom} relative to parent content bounds [0.0 - 1.0]
	anchor_max: [2]f32,
	// {left, top} in pixels from anchor_min
	offset_min: [2]f32,
	// {right, bottom} in pixels from anchor_max
	offset_max: [2]f32,
}

anchor_topleft :: proc() -> Layout_Anchor {
	return Layout_Anchor {
		anchor_min = {0, 0},
		anchor_max = {0, 0},
		offset_min = {0, 0},
		offset_max = {0, 0},
	}
}

anchor_topright :: proc() -> Layout_Anchor {
	return Layout_Anchor {
		anchor_min = {1, 0},
		anchor_max = {1, 0},
		offset_min = {0, 0},
		offset_max = {0, 0},
	}
}

anchor_bottomleft :: proc() -> Layout_Anchor {
	return Layout_Anchor {
		anchor_min = {0, 1},
		anchor_max = {0, 1},
		offset_min = {0, 0},
		offset_max = {0, 0},
	}
}

anchor_bottomright :: proc() -> Layout_Anchor {
	return Layout_Anchor {
		anchor_min = {1, 1},
		anchor_max = {1, 1},
		offset_min = {0, 0},
		offset_max = {0, 0},
	}
}

// The state of the UI system, including whether it is dirty and any deferred despawns.
UI_State :: struct {
	dirty:             bool,
	deferred_despawns: [dynamic]ecs.Entity,
}

// The render mode of the UI canvas, either screen space or world space.
UI_Canvas_Render_Mode :: enum {
	Screen_Space,
	World_Space,
}

// The UI canvas component, which defines the render mode, camera, reference size, and world size for the UI system.
UI_Canvas :: struct {
	render_mode:    UI_Canvas_Render_Mode,
	camera:         ecs.Entity,
	reference_size: [2]f32,
	world_size:     [2]f32,
}

// The UI canvas target, which contains the render target and batch for rendering the UI.
UI_Canvas_Target :: struct {
	target: graphics.Render_Target,
	batch:  graphics.Batch2D,
}

// Configurable key/button bindings for UI interactions.
UI_Input_Config :: struct {
	mouse_click:    input.MouseButtonCode,
	gamepad_submit: input.GamepadButton,
}
