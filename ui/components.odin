package ui

import "../ecs"
import graphics "../graphics"

UI_Size_Unit :: enum {
	Pixels,
	Percent,
	Auto,
}

UI_Size :: struct {
	val:  f32,
	unit: UI_Size_Unit,
}

UI_Rect :: struct {
	x, y, w, h: f32,
}

UI_Node :: struct {
	width:        UI_Size,
	height:       UI_Size,
	padding:      [4]f32, // top, right, bottom, left
	margin:       [4]f32, // top, right, bottom, left
	bg_color:     [4]f32,
	border_color: [4]f32,
	border_width: f32,
	rect:         UI_Rect,
}

Layout_Flex_Direction :: enum {
	Row,
	Column,
}

Layout_Justify_Content :: enum {
	Start,
	End,
	Center,
	Space_Between,
	Space_Around,
	Space_Evenly,
}

Layout_Align_Items :: enum {
	Start,
	End,
	Center,
	Stretch,
}

Layout_Flex :: struct {
	direction:       Layout_Flex_Direction,
	justify_content: Layout_Justify_Content,
	align_items:     Layout_Align_Items,
	gap:             f32,
}

Flex_Item :: struct {
	grow:   f32,
	shrink: f32,
}

Layout_Grid :: struct {
	columns:    int,
	rows:       int,
	column_gap: f32,
	row_gap:    f32,
}

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


Layout_Anchor :: struct {
	anchor_min: [2]f32, // {left, top} relative to parent content bounds [0.0 - 1.0]
	anchor_max: [2]f32, // {right, bottom} relative to parent content bounds [0.0 - 1.0]
	offset_min: [2]f32, // {left, top} in pixels from anchor_min
	offset_max: [2]f32, // {right, bottom} in pixels from anchor_max
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

UI_State :: struct {
	dirty:             bool,
	deferred_despawns: [dynamic]ecs.Entity,
}

UI_Canvas_Render_Mode :: enum {
	Screen_Space,
	World_Space,
}

UI_Canvas :: struct {
	render_mode:     UI_Canvas_Render_Mode,
	camera:          ecs.Entity,
	reference_size:  [2]f32,
	world_size:      [2]f32,
}

UI_Canvas_Target :: struct {
	target:          graphics.Render_Target,
	batch:           graphics.Batch2D,
}
