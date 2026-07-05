package ui

import "../ecs"
import "../ecs/params"
import graphics "../graphics"
import twoD "../graphics/2d"
import input "../input"
import "../windowing"
import "base:runtime"
import "core:c"
import "core:math/linalg"
import "vendor:sdl3"

// Helper function to get children pointing to parent via ChildOf relation
ui_get_children :: proc(
	w: ^ecs.World,
	parent: ecs.Entity,
	allocator := context.temp_allocator,
) -> []ecs.Entity {
	links, ok := w.target_index[parent]
	if !ok do return nil
	children := make([dynamic]ecs.Entity, allocator)
	for link in links {
		if info, found := w.filter_registry[link.pair_id]; found {
			if info.relation == typeid_of(ecs.ChildOf) {
				append(&children, link.source)
			}
		}
	}
	return children[:]
}

// Helper function to check if an entity has a parent ChildOf relationship
ui_has_parent :: proc(w: ^ecs.World, entity: ecs.Entity) -> bool {
	comps, ok := ecs.world_get_all_components(w, entity, context.temp_allocator)
	if !ok do return false
	defer delete(comps, context.temp_allocator)
	for c in comps {
		if ecs.is_pair(c.id) {
			if info, found := w.filter_registry[c.id]; found {
				if info.relation == typeid_of(ecs.ChildOf) {
					return true
				}
			}
		}
	}
	return false
}

ui_mark_dirty :: proc(w: ^ecs.World, e: ecs.Entity) {
	state := ecs.world_get_resource(w, UI_State)
	if state != nil {
		state.dirty = true
	}
}

ui_cascade_despawn :: proc(w: ^ecs.World, e: ecs.Entity) {
	state := ecs.world_get_resource(w, UI_State)
	if state != nil {
		append(&state.deferred_despawns, e)
	}
}

on_add :: proc(t: typeid, allocator := context.temp_allocator) -> ecs.Term {
	types := make([]typeid, 1, allocator)
	types[0] = t
	return ecs.Term{op = .OnAdd, types = types}
}

on_remove :: proc(t: typeid, allocator := context.temp_allocator) -> ecs.Term {
	types := make([]typeid, 1, allocator)
	types[0] = t
	return ecs.Term{op = .OnRemove, types = types}
}

ui_observer_init :: proc(w: ^ecs.World) {
	ecs.observe(w, on_add(UI_Node), ui_mark_dirty)
	ecs.observe(w, on_add(Layout_Flex), ui_mark_dirty)
	ecs.observe(w, on_add(Layout_Grid), ui_mark_dirty)
	ecs.observe(w, on_add(Layout_Anchor), ui_mark_dirty)
	ecs.observe(w, on_add(ecs.ChildOf), ui_mark_dirty)

	ecs.observe(w, on_remove(ecs.ChildOf), ui_cascade_despawn)
}

ui_solve_anchor :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	anchor: ^Layout_Anchor,
	parent_rect: UI_Rect,
) {
	anchor_left := parent_rect.x + anchor.anchor_min.x * parent_rect.w
	anchor_right := parent_rect.x + anchor.anchor_max.x * parent_rect.w
	anchor_top := parent_rect.y + anchor.anchor_min.y * parent_rect.h
	anchor_bottom := parent_rect.y + anchor.anchor_max.y * parent_rect.h

	cx, cy, cw, ch: f32

	if anchor.anchor_min.x != anchor.anchor_max.x {
		cx = anchor_left + anchor.offset_min.x
		cw = anchor_right + anchor.offset_max.x - cx
	} else {
		cw = node.width.unit == .Pixels ? node.width.val : 100.0
		cx = anchor_left + anchor.offset_min.x - cw * 0.5
	}

	if anchor.anchor_min.y != anchor.anchor_max.y {
		cy = anchor_top + anchor.offset_min.y
		ch = anchor_bottom + anchor.offset_max.y - cy
	} else {
		ch = node.height.unit == .Pixels ? node.height.val : 100.0
		cy = anchor_top + anchor.offset_min.y - ch * 0.5
	}

	// Apply node margin
	cx += node.margin[3]
	cy += node.margin[0]
	cw -= (node.margin[3] + node.margin[1])
	ch -= (node.margin[0] + node.margin[2])

	node.rect = {cx, cy, cw, ch}
}

ui_solve_flex :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	flex: ^Layout_Flex,
	content_rect: UI_Rect,
	children: []ecs.Entity,
) {
	if len(children) == 0 do return

	child_nodes := make([]^UI_Node, len(children), context.temp_allocator)
	child_items := make([]^Flex_Item, len(children), context.temp_allocator)
	base_sizes := make([]f32, len(children), context.temp_allocator)
	total_fixed_size: f32 = 0.0
	total_grow: f32 = 0.0

	valid_children_count := 0

	for child, i in children {
		cn := ecs.world_get_component(w, child, UI_Node)
		if cn == nil do continue
		child_nodes[i] = cn
		child_items[i] = ecs.world_get_component(w, child, Flex_Item)

		valid_children_count += 1

		if flex.direction == .Row {
			sz :=
				cn.width.unit == .Pixels ? cn.width.val : (cn.width.unit == .Percent ? cn.width.val * 0.01 * content_rect.w : 50.0)
			base_sizes[i] = sz
			total_fixed_size += sz
		} else {
			sz :=
				cn.height.unit == .Pixels ? cn.height.val : (cn.height.unit == .Percent ? cn.height.val * 0.01 * content_rect.h : 50.0)
			base_sizes[i] = sz
			total_fixed_size += sz
		}

		if child_items[i] != nil {
			total_grow += child_items[i].grow
		}
	}

	if valid_children_count == 0 do return

	total_gap := flex.gap * f32(valid_children_count - 1)
	total_content_size := total_fixed_size + total_gap

	remaining_space: f32 = 0.0
	if flex.direction == .Row {
		remaining_space = content_rect.w - total_content_size
	} else {
		remaining_space = content_rect.h - total_content_size
	}

	allocated_sizes := make([]f32, len(children), context.temp_allocator)
	for i in 0 ..< len(children) {
		if child_nodes[i] == nil do continue
		allocated_sizes[i] = base_sizes[i]
		if remaining_space > 0.0 && total_grow > 0.0 && child_items[i] != nil {
			allocated_sizes[i] += remaining_space * (child_items[i].grow / total_grow)
		}
	}

	current_pos: f32 = 0.0
	spacing: f32 = flex.gap

	sum_allocated: f32 = 0.0
	for sz in allocated_sizes do sum_allocated += sz
	sum_allocated += flex.gap * f32(valid_children_count - 1)

	#partial switch flex.justify_content {
	case .Start:
		current_pos = 0.0
	case .End:
		if flex.direction == .Row {
			current_pos = content_rect.w - sum_allocated
		} else {
			current_pos = content_rect.h - sum_allocated
		}
	case .Center:
		if flex.direction == .Row {
			current_pos = (content_rect.w - sum_allocated) * 0.5
		} else {
			current_pos = (content_rect.h - sum_allocated) * 0.5
		}
	case .Space_Between:
		current_pos = 0.0
		if valid_children_count > 1 {
			space_left := flex.direction == .Row ? content_rect.w : content_rect.h
			sum_nodes_size: f32 = 0.0
			for sz in allocated_sizes do sum_nodes_size += sz
			spacing = (space_left - sum_nodes_size) / f32(valid_children_count - 1)
		}
	case .Space_Around:
		sum_nodes_size: f32 = 0.0
		for sz in allocated_sizes do sum_nodes_size += sz
		space_left := flex.direction == .Row ? content_rect.w : content_rect.h
		spacing = (space_left - sum_nodes_size) / f32(valid_children_count)
		current_pos = spacing * 0.5
	case .Space_Evenly:
		sum_nodes_size: f32 = 0.0
		for sz in allocated_sizes do sum_nodes_size += sz
		space_left := flex.direction == .Row ? content_rect.w : content_rect.h
		spacing = (space_left - sum_nodes_size) / f32(valid_children_count + 1)
		current_pos = spacing
	}

	for child, i in children {
		cn := child_nodes[i]
		if cn == nil do continue

		sz := allocated_sizes[i]

		cx, cy, cw, ch: f32
		if flex.direction == .Row {
			cx = content_rect.x + current_pos
			cw = sz

			ch =
				cn.height.unit == .Pixels ? cn.height.val : (cn.height.unit == .Percent ? cn.height.val * 0.01 * content_rect.h : content_rect.h)
			#partial switch flex.align_items {
			case .Start:
				cy = content_rect.y
			case .End:
				cy = content_rect.y + content_rect.h - ch
			case .Center:
				cy = content_rect.y + (content_rect.h - ch) * 0.5
			case .Stretch:
				cy = content_rect.y
				ch = content_rect.h
			}

			current_pos += cw + spacing
		} else {
			cy = content_rect.y + current_pos
			ch = sz

			cw =
				cn.width.unit == .Pixels ? cn.width.val : (cn.width.unit == .Percent ? cn.width.val * 0.01 * content_rect.w : content_rect.w)
			#partial switch flex.align_items {
			case .Start:
				cx = content_rect.x
			case .End:
				cx = content_rect.x + content_rect.w - cw
			case .Center:
				cx = content_rect.x + (content_rect.w - cw) * 0.5
			case .Stretch:
				cx = content_rect.x
				cw = content_rect.w
			}

			current_pos += ch + spacing
		}

		cx += cn.margin[3]
		cy += cn.margin[0]
		cw -= (cn.margin[3] + cn.margin[1])
		ch -= (cn.margin[0] + cn.margin[2])

		cn.rect = {cx, cy, cw, ch}

		ui_compute_children_layout(w, child, cn)
	}
}

ui_solve_grid :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	node: ^UI_Node,
	grid: ^Layout_Grid,
	content_rect: UI_Rect,
	children: []ecs.Entity,
) {
	if len(children) == 0 do return

	cols := max(1, grid.columns)
	rows := max(1, grid.rows)

	col_w := (content_rect.w - grid.column_gap * f32(cols - 1)) / f32(cols)
	row_h := (content_rect.h - grid.row_gap * f32(rows - 1)) / f32(rows)

	grid_idx := 0

	for child in children {
		cn := ecs.world_get_component(w, child, UI_Node)
		if cn == nil do continue

		gi := ecs.world_get_component(w, child, Grid_Item)
		col, row, col_span, row_span: int

		if gi != nil {
			col = gi.column_start
			row = gi.row_start
			col_span = max(1, gi.column_span)
			row_span = max(1, gi.row_span)
		} else {
			col = grid_idx % cols
			row = grid_idx / cols
			col_span = 1
			row_span = 1
			grid_idx += 1
		}

		cx := content_rect.x + f32(col) * (col_w + grid.column_gap)
		cy := content_rect.y + f32(row) * (row_h + grid.row_gap)
		cw := f32(col_span) * col_w + f32(col_span - 1) * grid.column_gap
		ch := f32(row_span) * row_h + f32(row_span - 1) * grid.row_gap

		cx += cn.margin[3]
		cy += cn.margin[0]
		cw -= (cn.margin[3] + cn.margin[1])
		ch -= (cn.margin[0] + cn.margin[2])

		cn.rect = {cx, cy, cw, ch}

		ui_compute_children_layout(w, child, cn)
	}
}

ui_compute_children_layout :: proc(w: ^ecs.World, entity: ecs.Entity, node: ^UI_Node) {
	cx := node.rect.x + node.padding[3]
	cy := node.rect.y + node.padding[0]
	cw := node.rect.w - node.padding[3] - node.padding[1]
	ch := node.rect.h - node.padding[0] - node.padding[2]
	if cw < 0 do cw = 0
	if ch < 0 do ch = 0
	content_rect := UI_Rect{cx, cy, cw, ch}

	children := ui_get_children(w, entity)

	flex := ecs.world_get_component(w, entity, Layout_Flex)
	grid := ecs.world_get_component(w, entity, Layout_Grid)

	if flex != nil {
		ui_solve_flex(w, entity, node, flex, content_rect, children)
	} else if grid != nil {
		ui_solve_grid(w, entity, node, grid, content_rect, children)
	} else {
		for child in children {
			ui_compute_node_layout(w, child, content_rect)
		}
	}
}

ui_compute_node_layout :: proc(w: ^ecs.World, entity: ecs.Entity, parent_rect: UI_Rect) {
	node := ecs.world_get_component(w, entity, UI_Node)
	if node == nil do return

	anchor := ecs.world_get_component(w, entity, Layout_Anchor)
	if anchor != nil {
		ui_solve_anchor(w, entity, node, anchor, parent_rect)
	} else {
		w_val := parent_rect.w
		if node.width.unit == .Pixels do w_val = node.width.val
		else if node.width.unit == .Percent do w_val = node.width.val * 0.01 * parent_rect.w

		h_val := parent_rect.h
		if node.height.unit == .Pixels do h_val = node.height.val
		else if node.height.unit == .Percent do h_val = node.height.val * 0.01 * parent_rect.h

		x := parent_rect.x + node.margin[3]
		y := parent_rect.y + node.margin[0]
		w_val -= (node.margin[3] + node.margin[1])
		h_val -= (node.margin[0] + node.margin[2])

		node.rect = {x, y, w_val, h_val}
	}

	ui_compute_children_layout(w, entity, node)
}

ui_process_deferred_despawns :: proc(w: ^ecs.World) {
	state := ecs.world_get_resource(w, UI_State)
	if state == nil do return

	for len(state.deferred_despawns) > 0 {
		despawns := make([]ecs.Entity, len(state.deferred_despawns), context.temp_allocator)
		copy(despawns, state.deferred_despawns[:])
		clear(&state.deferred_despawns)

		for e in despawns {
			if ecs.world_is_alive(w, e) {
				ecs.world_despawn(w, e)
			}
		}
	}
}

ui_layout_system :: proc(
	world: ^ecs.World,
	window_res: params.Res(windowing.Window_Context),
	ui_state: params.Res(UI_State),
) {
	if world == nil || window_res.ptr == nil || ui_state.ptr == nil do return

	ui_process_deferred_despawns(world)

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	parent_rect := UI_Rect{0, 0, f32(win_w), f32(win_h)}

	for arch in ecs.query(world, UI_Node) {
		entities := ecs.arch_get_entities(arch)
		for e in entities {
			if !ui_has_parent(world, e) {
				ui_compute_node_layout(world, e, parent_rect)
			}
		}
	}

	ui_state.ptr.dirty = false
}

ui_projection_matrix :: proc(w, h: f32) -> linalg.Matrix4f32 {
	return linalg.Matrix4f32 {
		2.0 / w,
		0.0,
		0.0,
		-1.0,
		0.0,
		-2.0 / h,
		0.0,
		1.0,
		0.0,
		0.0,
		1.0,
		0.0,
		0.0,
		0.0,
		0.0,
		1.0,
	}
}

ui_render_node :: proc(
	w: ^ecs.World,
	entity: ecs.Entity,
	batch: ^graphics.Batch2D,
	vp: linalg.Matrix4f32,
) {
	node := ecs.world_get_component(w, entity, UI_Node)
	if node != nil {
		bg_color := node.bg_color
		border_color := node.border_color
		border_width := node.border_width
		text_color_override: [4]f32
		has_text_color_override := false

		// Apply UI_Style if present
		style := ecs.world_get_component(w, entity, UI_Style)
		if style != nil {
			state_style := style.normal
			// TODO: have a system for each element that applies the style
			btn := ecs.world_get_component(w, entity, Button)
			if btn != nil {
				if btn.is_pressed {
					state_style = style.active
				} else if btn.is_hovered {
					state_style = style.hover
				}
			}

			bg_color = state_style.bg_color
			border_color = state_style.border_color
			if state_style.border_width >= 0.0 {
				border_width = state_style.border_width
			}
			if state_style.text_color.a > 0.0 {
				text_color_override = state_style.text_color
				has_text_color_override = true
			}
		}

		// Draw background
		if bg_color.a > 0.0 {
			twoD.draw_rect(
				batch,
				{node.rect.x, node.rect.y},
				{node.rect.w, node.rect.h},
				bg_color,
				vp,
			)
		}
		// Draw border
		if border_width > 0.0 && border_color.a > 0.0 {
			t := border_width
			// top border
			twoD.draw_rect(batch, {node.rect.x, node.rect.y}, {node.rect.w, t}, border_color, vp)
			// bottom border
			twoD.draw_rect(
				batch,
				{node.rect.x, node.rect.y + node.rect.h - t},
				{node.rect.w, t},
				border_color,
				vp,
			)
			// left border
			twoD.draw_rect(
				batch,
				{node.rect.x, node.rect.y + t},
				{t, node.rect.h - 2 * t},
				border_color,
				vp,
			)
			// right border
			twoD.draw_rect(
				batch,
				{node.rect.x + node.rect.w - t, node.rect.y + t},
				{t, node.rect.h - 2 * t},
				border_color,
				vp,
			)
		}

		// Draw basic elements: Label
		label := ecs.world_get_component(w, entity, Label)
		if label != nil {
			font := ecs.world_get_resource(w, graphics.Font)
			if font != nil {
				font_size := label.font_size > 0.0 ? label.font_size : font.pixel_height
				x := node.rect.x + node.padding[3]
				y := node.rect.y + node.padding[0]
				color := has_text_color_override ? text_color_override : label.color
				graphics.draw_text(batch, label.text, x, y, font, 1.0, color, vp)
			}
		}

		// Draw basic elements: Checkbox
		checkbox := ecs.world_get_component(w, entity, Checkbox)
		if checkbox != nil && checkbox.checked {
			pad: f32 = 4.0
			rect_x := node.rect.x + pad
			rect_y := node.rect.y + pad
			rect_w := max(f32(0.0), node.rect.w - pad * 2.0)
			rect_h := max(f32(0.0), node.rect.h - pad * 2.0)
			twoD.draw_rect(batch, {rect_x, rect_y}, {rect_w, rect_h}, checkbox.active_color, vp)
		}

		// Draw basic elements: Slider
		slider := ecs.world_get_component(w, entity, Slider)
		if slider != nil {
			fill_w := node.rect.w * clamp(slider.value, 0.0, 1.0)
			if fill_w > 0.0 {
				twoD.draw_rect(
					batch,
					{node.rect.x, node.rect.y},
					{fill_w, node.rect.h},
					slider.active_color,
					vp,
				)
			}
			knob_w := node.rect.h
			knob_x := node.rect.x + fill_w - knob_w / 2.0
			knob_x = clamp(knob_x, node.rect.x, node.rect.x + node.rect.w - knob_w)
			twoD.draw_rect(
				batch,
				{knob_x, node.rect.y},
				{knob_w, node.rect.h},
				slider.knob_color,
				vp,
			)
		}
	}

	children := ui_get_children(w, entity)

	for child in children {
		ui_render_node(w, child, batch, vp)
	}
}

ui_render_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(graphics.Batch2D),
	render_ctx: params.Res(graphics.Render_Context),
	window_res: params.Res(windowing.Window_Context),
) {
	if render_ctx.ptr == nil || render_ctx.ptr.device == nil || batch2d.ptr == nil || window_res.ptr == nil do return

	win_w, win_h: c.int
	sdl3.GetWindowSize(window_res.ptr.window, &win_w, &win_h)
	vp := ui_projection_matrix(f32(win_w), f32(win_h))

	// Find root nodes and render recursively
	for arch in ecs.query(world, UI_Node) {
		entities := ecs.arch_get_entities(arch)
		for e in entities {
			if !ui_has_parent(world, e) {
				ui_render_node(world, e, batch2d.ptr, vp)
			}
		}
	}
}

ui_button_interaction_system :: proc(world: ^ecs.World, mouse_inp: input.Input(input.ButtonCode)) {
	mpos := input.mouse_position(mouse_inp)
	is_left_down := input.is_down(mouse_inp, input.ButtonCode.Left)
	is_left_pressed := input.is_pressed(mouse_inp, input.ButtonCode.Left)

	for arch in ecs.query(world, UI_Node, Button) {
		nodes := ecs.arch_get_field(arch, UI_Node)
		buttons := ecs.arch_get_field(arch, Button)

		for i in 0 ..< len(nodes) {
			node := &nodes[i]
			btn := &buttons[i]

			in_bounds :=
				mpos.x >= node.rect.x &&
				mpos.x <= node.rect.x + node.rect.w &&
				mpos.y >= node.rect.y &&
				mpos.y <= node.rect.y + node.rect.h

			btn.is_hovered = in_bounds
			btn.is_clicked = false

			if in_bounds {
				if is_left_pressed {
					btn.is_pressed = true
				}
				if btn.is_pressed {
					if !is_left_down {
						btn.is_pressed = false
						btn.is_clicked = true
					}
				}
			} else {
				btn.is_pressed = false
			}
		}
	}
}
