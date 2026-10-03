// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import "../editor"
import "../ui"
import editor_view "../view"

@(private = "file")
SYNCHRONIZED_OUTPUT_BEGIN :: string("\x1b[?2026h")
@(private = "file")
SYNCHRONIZED_OUTPUT_END :: string("\x1b[?2026l")

/* renderer_present_recovery replaces UI output with one global geometry diagnostic. */
renderer_present_recovery :: proc(
	renderer: ^Renderer,
	session: ^Session,
	message: string,
) -> (ok: bool, failure: Failure_Context) {
	state := renderer_state(renderer)
	if state == nil || !session_is_live(session) {
		return false, Failure_Context{code = .Invalid_Renderer}
	}
	if u32(len(message)) > MAX_RECOVERY_MESSAGE_BYTES {
		return false, Failure_Context {
			code = .Recovery_Message_Limit,
			limit = u64(MAX_RECOVERY_MESSAGE_BYTES),
			actual = u64(len(message)),
		}
	}
	output_estimate := u64(len(message)) + u64(state.constraints.width_cells) * 4 + 128
	if output_estimate > u64(state.max_output_bytes) {
		return false, Failure_Context {
			code = .Render_Output_Limit,
			limit = u64(state.max_output_bytes),
			actual = output_estimate,
		}
	}
	output, allocation_error := make([]u8, int(output_estimate), state.allocator)
	if allocation_error != nil {
		return false, renderer_memory_failure(output_estimate)
	}
	frame := Render_Frame{allocator = state.allocator, output = output}
	defer frame_close(&frame)
	frame_append_string(&frame, "\x1b[?25l\x1b[2J")
	frame_append_cursor(&frame, 1, 1)
	frame_append_string(&frame, "\x1b[7m")
	column := u32(0)
	offset: u64
	for offset < u64(len(message)) && column < state.constraints.width_cells {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(state.profile.unicode, message, offset)
		if !grapheme_ok {
			return false, Failure_Context{code = .Incompatible_Snapshot}
		}
		cluster := message[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(state.profile.unicode, cluster, column, 4)
		if !width_ok {
			return false, Failure_Context{code = .Incompatible_Snapshot}
		}
		if width.is_line_break || width.is_tab || width.used_replacement {
			cluster = "?"
			width.cells = 1
		}
		if column + u32(width.cells) > state.constraints.width_cells {
			break
		}
		frame_append_string(&frame, cluster)
		column += u32(width.cells)
		offset = grapheme.end
	}
	for column < state.constraints.width_cells {
		frame_append_byte(&frame, ' ')
		column += 1
	}
	frame_append_string(&frame, "\x1b[27m")
	written, write_failure := session_write_all(session, frame.output[:frame.used])
	if !written {
		return false, write_failure
	}
	flushed, flush_failure := session_flush(session)
	if !flushed {
		return false, flush_failure
	}
	return true, {}
}

/* renderer_ui_profile reports the exact logical capabilities of this renderer. */
renderer_ui_profile :: proc(renderer: ^Renderer) -> (profile: ui.Renderer_Profile, ok: bool) {
	state := renderer_state(renderer)
	if state == nil {
		return {}, false
	}
	return renderer_state_ui_profile(state), true
}

/* renderer_present_ui writes one complete logical UI root as a full frame. */
renderer_present_ui :: proc(
	renderer: ^Renderer,
	session: ^Session,
	presentation: UI_Presentation,
) -> (ok: bool, failure: Failure_Context) {
	state := renderer_state(renderer)
	if state == nil || !session_is_live(session) {
		return false, Failure_Context{code = .Invalid_Renderer}
	}
	frame, prepared, prepare_failure := renderer_prepare_ui(state, presentation)
	if !prepared {
		return false, prepare_failure
	}
	defer frame_close(&frame)
	synchronized, synchronize_failure := session_write_all(
		session, transmute([]u8)SYNCHRONIZED_OUTPUT_BEGIN)
	if !synchronized {
		return false, synchronize_failure
	}
	written, write_failure := session_write_all(session, frame.output[:frame.used])
	if !written {
		_, _ = session_write_all(session, transmute([]u8)SYNCHRONIZED_OUTPUT_END)
		_, _ = session_flush(session)
		return false, write_failure
	}
	ended, end_failure := session_write_all(session, transmute([]u8)SYNCHRONIZED_OUTPUT_END)
	if !ended {
		return false, end_failure
	}
	flushed, flush_failure := session_flush(session)
	if !flushed {
		return false, flush_failure
	}
	return true, {}
}

@(private)
renderer_prepare_ui :: proc(
	state: ^Renderer_State,
	presentation: UI_Presentation,
) -> (frame: Render_Frame, ok: bool, failure: Failure_Context) {
	root, viewed := ui.snapshot_view(presentation.root)
	if !viewed || !ui_presentation_is_valid(state, root, presentation.text_surfaces) {
		return {}, false, Failure_Context{code = .Invalid_UI_Presentation}
	}
	cell_count := u64(state.constraints.width_cells) * u64(state.constraints.height_rows)
	output_estimate := u64(128) + cell_count * 96 + u64(len(root.compact_content)) +
		u64(len(root.list_content)) + u64(len(root.input_content))
	for projection in presentation.text_surfaces {
		source, display_viewed, _ := display.snapshot_view(projection.snapshot)
		if !display_viewed {
			return {}, false, Failure_Context{code = .Incompatible_Snapshot}
		}
		output_estimate += u64(len(source.text))
	}
	if output_estimate > u64(state.max_output_bytes) || output_estimate > u64(max(int)) {
		return {}, false, Failure_Context {
			code = .Render_Output_Limit,
			limit = u64(state.max_output_bytes),
			actual = output_estimate,
		}
	}
	output, allocation_error := make([]u8, int(output_estimate), state.allocator)
	if allocation_error != nil {
		return {}, false, renderer_memory_failure(output_estimate)
	}
	frame = Render_Frame{allocator = state.allocator, output = output, color = state.color}
	frame_append_string(&frame, "\x1b[?25l")
	frame_append_style(&frame, ui_canvas_style(root.styles))
	frame_append_string(&frame, "\x1b[2J")
	active_cursor_row, active_cursor_column: u32
	active_cursor_visible := false
	active_cursor_terminal_style := ui.Terminal_Cursor_Style.Block
	active_cursor_blinking := false
	active_cursor_has_terminal_style := false
	audible_attention := false
	for node in root.composition {
		if node.kind == .Split && node.layout.present && node.layout.geometry_state != .Insufficient {
			separator := node.layout.separator
			if separator.width == 1 && separator.height > 0 {
				frame_append_separator(&frame, separator)
			}
		}
	}
	for status in root.status_regions {
		if status.placement != .Root_Edge do continue
		content, content_ok := ui.snapshot_status_content(root, status)
		if !content_ok || !frame_append_status(
			&frame,
			state.profile,
			status.geometry,
			content,
			ui_style_definition(root.styles, status.style_role),
			root,
			status.style_spans,
			status.style_span_count,
			status.active,
		) {
			frame_close(&frame)
			return {}, false, Failure_Context{code = .Incompatible_Snapshot}
		}
	}
	for surface in root.surfaces {
		if ui_surface_is_popup_content(root.popups, surface.handle) do continue
		view, found := ui_view_find(root.views, surface.view)
		assert(found)
		switch view.kind {
		case .Text_View:
			projection := ui_projection_for_surface(presentation.text_surfaces, surface.handle)
			source, _, _ := display.snapshot_view(projection.snapshot)
			if view.text.gutter.present {
				for viewport_row in 0 ..< u32(view.text.gutter.row_count) {
					gutter_row, left, right, gutter_row_ok := ui.snapshot_text_gutter_row(
						root,
						view.text,
						viewport_row,
					)
					if !gutter_row_ok ||
					   !frame_append_gutter_row(
						&frame,
						state.profile,
						surface.geometry,
						gutter_row,
						left,
						right,
						root,
					) {
						frame_close(&frame)
						return {}, false, Failure_Context{code = .Incompatible_Snapshot}
					}
				}
			}
			for row in source.rows {
				frame_append_cursor(
					&frame,
					u32(surface.geometry.row) + u32(row.viewport_row) + 1,
					u32(surface.geometry.column) + u32(view.text.gutter.left_cells) + 1,
				)
				if !frame_append_display_row(&frame, source, row, root, view, {}) {
					frame_close(&frame)
					return {}, false, Failure_Context{code = .Incompatible_Snapshot}
				}
			}
			if root.focus.target == surface.handle && source.cursor.visible {
				active_cursor_row = u32(surface.geometry.row) + u32(source.cursor.viewport_row) + 1
				active_cursor_column = u32(surface.geometry.column) +
					u32(view.text.gutter.left_cells) + u32(source.cursor.column) + 1
				active_cursor_visible = true
				switch view.text.cursor_shape {
				case .Block:
					active_cursor_terminal_style = .Block
					active_cursor_blinking = false
					active_cursor_has_terminal_style = true
				case .Bar:
					active_cursor_terminal_style = .Bar
					active_cursor_blinking = false
					active_cursor_has_terminal_style = true
				case .Underline:
					active_cursor_terminal_style = .Underline
					active_cursor_blinking = false
					active_cursor_has_terminal_style = true
				case .Default:
				}
			}
		case .Terminal_View:
			audible_attention = audible_attention || view.terminal.audible_attention
			if !frame_append_terminal_view(&frame, root, view, surface.geometry) {
				frame_close(&frame)
				return {}, false, Failure_Context{code = .Incompatible_Snapshot}
			}
			cursor := view.terminal.cursor
			if terminal_view_cursor_is_active(root, surface, view) {
				active_cursor_row = u32(surface.geometry.row) + u32(cursor.row) + 1
				active_cursor_column = u32(surface.geometry.column) + u32(cursor.column) + 1
				active_cursor_visible = true
				active_cursor_terminal_style = cursor.style
				active_cursor_blinking = cursor.blinking
				active_cursor_has_terminal_style = true
			}
		case .List_View:
			items, items_ok := ui.snapshot_list_visible_items(root, view)
			assert(items_ok)
			mark_lane := view.list.mark_lane
			for row in 0 ..< u32(surface.geometry.height) {
				text := ""
				prefix := ""
				style: ui.Style_Definition
				prefix_style: ui.Style_Definition
				mark := ui.List_Mark.None
				item: ui.List_Item_Descriptor
				if int(row) < len(items) {
					item = items[row]
					text, _ = ui.snapshot_list_item_text(root, item)
					mark = item.mark
					source_index := view.list.position.first_visible_item + row
					role := ui.Style_Role.List_Normal
					if i32(source_index) == view.list.position.current_item do role = .List_Current
					style = ui_style_definition(root.styles, role)
					prefix_style = style
					if item.icon_role != .Invalid {
						prefix = renderer_list_icon(item.icon_role, state.icons)
						semantic := ui_style_definition(root.styles, item.icon_style_role)
						semantic.background = {}
						prefix_style = ui_style_compose(style, semantic)
					}
				}
				emphasis_style: ui.Style_Definition
				emphasis_bytes := u32(0)
				if int(row) < len(items) && items[row].emphasis_style != .Invalid &&
				   i32(view.list.position.first_visible_item + row) != view.list.position.current_item {
					emphasis_style = ui_style_definition(root.styles, items[row].emphasis_style)
					emphasis_style.background = {}
					emphasis_bytes = items[row].emphasis_bytes
				}
				row_geometry := ui.Cell_Rect {
					row = surface.geometry.row + i32(row),
					column = surface.geometry.column,
					height = 1,
					width = surface.geometry.width,
				}
				if !frame_append_list_row(
					&frame, state.profile, row_geometry, prefix, text, style, prefix_style, mark, mark_lane, root,
					emphasis_style, emphasis_bytes, item.style_spans, item.style_span_count,
				) {
					frame_close(&frame)
					return {}, false, Failure_Context{code = .Incompatible_Snapshot}
				}
			}
		case .Tree_View:
			nodes, nodes_ok := ui.snapshot_tree_visible_nodes(root, view)
			assert(nodes_ok)
			for row in 0 ..< u32(surface.geometry.height) {
				text := ""
				prefix := ""
				style: ui.Style_Definition
				icon_style: ui.Style_Definition
				node: ui.Tree_Node_Descriptor
				if int(row) < len(nodes) {
					node = nodes[row]
					text, _ = ui.snapshot_tree_node_text(root, node)
					prefix_bytes: [ui.MAX_TREE_DEPTH * 2 + ui.MAX_TREE_ICON_BYTES + 1]u8
					prefix_count := int(node.indent_depth) * 2
					for index in 0 ..< prefix_count do prefix_bytes[index] = ' '
					icon, icon_ok := ui.snapshot_tree_node_icon(root, node)
					if !icon_ok || len(icon) == 0 {
						icon_role := node.icon_role
						if icon_role == .Invalid {
							icon_role = .Directory_Open if node.expandable && node.expanded else
								.Directory_Closed if node.expandable else .File
						}
						icon = renderer_tree_icon(icon_role, state.icons)
					}
					icon_bytes := transmute([]u8)icon
					copy(prefix_bytes[prefix_count:], icon_bytes)
					prefix_bytes[prefix_count + len(icon_bytes)] = ' '
					prefix = string(prefix_bytes[:prefix_count + len(icon_bytes) + 1])
					source_index := view.tree.position.first_visible_item + row
					role := ui.Style_Role.List_Normal
					if i32(source_index) == view.tree.position.current_item do role = .List_Current
					style = ui_style_definition(root.styles, role)
					icon_style = style
					if node.icon_style_role != .Invalid {
						icon_style = ui_style_compose(
							style,
							ui_style_definition(root.styles, node.icon_style_role),
						)
					}
				}
				row_geometry := ui.Cell_Rect {
					row = surface.geometry.row + i32(row),
					column = surface.geometry.column,
					height = 1,
					width = surface.geometry.width,
				}
				if !frame_append_list_row(
					&frame, state.profile, row_geometry, prefix, text, style, icon_style, .None, false, root,
					{}, 0, node.style_spans, node.style_span_count,
				) {
					frame_close(&frame)
					return {}, false, Failure_Context{code = .Incompatible_Snapshot}
				}
			}
		case .Input:
			value, value_ok := ui.snapshot_input_value(root, view)
			if !value_ok {
				frame_close(&frame)
				return {}, false, Failure_Context{code = .Incompatible_Snapshot}
			}
			start := int(view.input.first_visible_byte)
			if start > len(value) || !frame_append_list_row(
				&frame,
				state.profile,
				surface.geometry,
				"",
				value[start:],
				ui_style_definition(
					root.styles,
					.Diagnostic_Rejected if view.input.validation == .Rejected else .Status_Active,
				),
				ui_style_definition(
					root.styles,
					.Diagnostic_Rejected if view.input.validation == .Rejected else .Status_Active,
				),
				.None,
				false,
				root,
				{},
				0,
				{},
				0,
			) {
				frame_close(&frame)
				return {}, false, Failure_Context{code = .Incompatible_Snapshot}
			}
			if root.focus.target == surface.handle {
				cursor_cells, cursor_ok := ui_input_cursor_cells(
					state.profile,
					value[start:int(view.input.cursor_offset)],
				)
				if !cursor_ok || cursor_cells >= u32(surface.geometry.width) {
					frame_close(&frame)
					return {}, false, Failure_Context{code = .Incompatible_Snapshot}
				}
				active_cursor_row = u32(surface.geometry.row) + 1
				active_cursor_column = u32(surface.geometry.column) + cursor_cells + 1
				active_cursor_visible = true
			}
		case .Invalid:
			unreachable()
		}
	}
	for status in root.status_regions {
		if status.placement == .Root_Edge do continue
		content, content_ok := ui.snapshot_status_content(root, status)
		if !content_ok || !frame_append_status(
			&frame,
			state.profile,
			status.geometry,
			content,
			ui_style_definition(root.styles, status.style_role),
			root,
			status.style_spans,
			status.style_span_count,
			status.active,
		) {
			frame_close(&frame)
			return {}, false, Failure_Context{code = .Incompatible_Snapshot}
		}
	}
	for popup in root.popups {
		if popup.geometry.state != .Placed do continue
		content_surface, surface_found := ui_surface_find(root.surfaces, popup.content_surface)
		if !surface_found || !frame_append_popup(
			&frame,
			state,
			root,
			presentation.text_surfaces,
			popup,
			content_surface,
		) {
			frame_close(&frame)
			return {}, false, Failure_Context{code = .Incompatible_Snapshot}
		}
	}
	frame_reset_style(&frame)
	if audible_attention do frame_append_byte(&frame, '\x07')
	if active_cursor_visible {
		if active_cursor_has_terminal_style {
			frame_append_terminal_cursor_style(
				&frame,
				active_cursor_terminal_style,
				active_cursor_blinking,
			)
		} else if state.terminal_cursor_style_active {
			frame_append_terminal_cursor_style(&frame, .Block, false)
		}
		state.terminal_cursor_style_active = active_cursor_has_terminal_style
		frame_append_cursor(&frame, active_cursor_row, active_cursor_column)
		frame_append_string(&frame, "\x1b[?25h")
	}
	assert(frame.used <= u32(len(frame.output)))
	return frame, true, {}
}

@(private)
ui_presentation_is_valid :: proc(
	state: ^Renderer_State,
	root: ui.Snapshot_View,
	projections: []Text_Surface_Projection,
) -> bool {
	if state == nil || root.renderer != renderer_state_ui_profile(state) ||
	   len(root.surfaces) == 0 || len(root.composition) == 0 ||
	   root.focus.target.object_id == ui.Object_ID(0) {
		return false
	}
	seen: [ui.MAX_LIVE_SURFACES]ui.Object_Handle
	seen_count: int
	text_view_count: int
	focus_found := false
	for popup in root.popups {
		if popup.required_profile != root.renderer.id ||
		   !ui.presentation_profile_record_is_valid(popup.presentation_profile) ||
		   !ui_popup_profile_styles_are_present(root.styles, popup.presentation_profile) {
			return false
		}
		switch popup.geometry.state {
		case .Placed:
			if popup.geometry.z_order != 1 || !popup.geometry.obscures_underlay ||
			   !ui_rect_is_visible(popup.geometry.outer, state.constraints) ||
			   !ui_rect_is_visible(popup.geometry.content, state.constraints) ||
			   !ui_rect_contains(popup.geometry.outer, popup.geometry.content) {
				return false
			}
		case .Fallback:
			empty_rect: ui.Cell_Rect
			if popup.geometry.outer != empty_rect || popup.geometry.content != empty_rect {
				return false
			}
		case .Rejected, .Invalid:
			return false
		}
	}
	for surface in root.surfaces {
		popup, popup_content := ui_popup_for_content(root.popups, surface.handle)
		geometry := surface.geometry
		rendered := true
		if popup_content {
			rendered = popup.geometry.state == .Placed
			if rendered do geometry = popup.geometry.content
		}
		projection, found := ui_projection_find(projections, surface.handle)
		view, view_found := ui_view_find(root.views, surface.view)
		if !view_found || (rendered && !ui_rect_is_visible(geometry, state.constraints)) ||
		   (!rendered && found) {
			return false
		}
		if !rendered {
			for prior in seen[:seen_count] {
				if prior == surface.handle do return false
			}
			seen[seen_count] = surface.handle
			seen_count += 1
			continue
		}
		switch view.kind {
		case .Text_View:
			text_view_count += 1
			if !found || !view.text.present ||
			   !ui_style_present(root.styles, .Text_Normal) ||
			   projection.logical.view_id != editor_view.View_ID(view.text.source.view_id) ||
			   projection.logical.view_generation != view.text.source.view_generation ||
			   projection.logical.buffer_id != editor.Buffer_ID(view.text.buffer_id) ||
			   u64(projection.logical.revision) != view.text.revision {
				return false
			}
			text_width := u32(geometry.width)
			if view.text.gutter.present {
				if u64(view.text.gutter.left_cells) + u64(view.text.gutter.text_cells) +
				   u64(view.text.gutter.right_cells) != u64(geometry.width) ||
				   view.text.gutter.row_count != u8(geometry.height) ||
				   !ui_style_present(root.styles, .Gutter_Background) ||
				   !ui_style_present(root.styles, .Gutter_Line_Number) ||
				   !ui_style_present(root.styles, .Gutter_Line_Number_Current) ||
				   !ui_style_present(root.styles, .Gutter_Separator) {
					return false
				}
				text_width = view.text.gutter.text_cells
				for viewport_row in 0 ..< u32(view.text.gutter.row_count) {
					_, _, _, gutter_row_ok := ui.snapshot_text_gutter_row(
						root, view.text, viewport_row)
					if !gutter_row_ok do return false
				}
			}
			constraints := display.Viewport_Constraints {
				width_cells = text_width,
				height_rows = u32(geometry.height),
			}
			compatible, _ := display.snapshot_is_compatible(
				projection.snapshot,
				projection.logical,
				constraints,
				state.profile,
			)
			if !compatible {
				return false
			}
			display_source, display_viewed, _ := display.snapshot_view(projection.snapshot)
			if !display_viewed ||
			   !ui_text_presentation_matches_display(view.text, projection.logical, display_source) {
				return false
			}
			if view.text.region_active && !ui_style_present(root.styles, .Text_Region) {
				return false
			}
			if view.text.search.present && view.text.search.has_current &&
			   !ui_style_present(root.styles, .Text_Search_Current) {
				return false
			}
			if surface.pane.present && !popup_content {
				status, status_found := ui_status_find(root.status_regions, surface.handle)
				if !status_found || status.geometry != surface.pane.status ||
				   status.rows != u16(surface.pane.status.height) {
					return false
				}
			}
		case .Terminal_View:
			if found || !view.terminal.present || popup_content ||
			   u32(view.terminal.rows) < u32(geometry.height) ||
			   u32(view.terminal.columns) < u32(geometry.width) {
				return false
			}
			if _, rows_ok := ui.snapshot_terminal_rows(root, view); !rows_ok do return false
			if _, cells_ok := ui.snapshot_terminal_cells(root, view); !cells_ok do return false
			if _, title_ok := ui.snapshot_terminal_title(root, view); !title_ok do return false
		case .List_View:
			if found || !view.list.present ||
			   !ui_style_present(root.styles, .List_Normal) ||
			   !ui_style_present(root.styles, .List_Current) {
				return false
			}
			if _, items_ok := ui.snapshot_list_items(root, view); !items_ok do return false
		case .Tree_View:
			if found || !view.tree.present ||
			   !ui_style_present(root.styles, .List_Normal) ||
			   !ui_style_present(root.styles, .List_Current) {
				return false
			}
			if _, nodes_ok := ui.snapshot_tree_nodes(root, view); !nodes_ok do return false
		case .Input:
			if found || !view.input.present ||
			   !ui_style_present(root.styles, .Status_Active) ||
			   !ui_style_present(root.styles, .Diagnostic_Rejected) ||
			   (!popup_content && (!root.focus.captured || root.focus.target != surface.handle)) {
				return false
			}
			if _, input_ok := ui.snapshot_input_value(root, view); !input_ok do return false
			if _, choices_ok := ui.snapshot_input_choices(root, view); !choices_ok do return false
		case .Invalid:
			return false
		}
		for prior in seen[:seen_count] {
			if prior == surface.handle {
				return false
			}
		}
		seen[seen_count] = surface.handle
		seen_count += 1
		if root.focus.target == surface.handle do focus_found = true
	}
	for status in root.status_regions {
		if !ui_rect_is_visible(status.geometry, state.constraints) ||
		   !ui_style_present(root.styles, status.style_role) {
			return false
		}
		for span_index in 0 ..< int(status.style_span_count) {
			if !ui_style_present(root.styles, status.style_spans[span_index].style_role) {
				return false
			}
		}
		if (status.placement == .Attached && !ui_surface_present(root.surfaces, status.surface)) ||
		   (status.placement == .Root_Edge && status.surface.object_id != ui.Object_ID(0)) ||
		   status.placement == .Invalid {
			return false
		}
		if _, content_ok := ui.snapshot_status_content(root, status); !content_ok {
			return false
		}
	}
	return focus_found && seen_count == len(root.surfaces) && text_view_count == len(projections) &&
		ui_text_decorations_are_valid(root)
}

@(private)
ui_rect_is_visible :: proc(rect: ui.Cell_Rect, constraints: display.Viewport_Constraints) -> bool {
	return rect.row >= 0 && rect.column >= 0 && rect.height > 0 && rect.width > 0 &&
	       rect.row + rect.height <= i32(constraints.height_rows) &&
	       rect.column + rect.width <= i32(constraints.width_cells)
}

@(private)
ui_rect_contains :: proc(outer, inner: ui.Cell_Rect) -> bool {
	return outer.row <= inner.row && outer.column <= inner.column &&
		inner.row + inner.height <= outer.row + outer.height &&
		inner.column + inner.width <= outer.column + outer.width
}

@(private)
ui_projection_find :: proc(
	projections: []Text_Surface_Projection,
	surface: ui.Object_Handle,
) -> (projection: Text_Surface_Projection, found: bool) {
	for candidate in projections {
		if candidate.surface == surface {
			return candidate, true
		}
	}
	return {}, false
}

@(private)
ui_projection_for_surface :: proc(
	projections: []Text_Surface_Projection,
	surface: ui.Object_Handle,
) -> Text_Surface_Projection {
	projection, found := ui_projection_find(projections, surface)
	assert(found)
	return projection
}

@(private)
ui_surface_find :: proc(
	surfaces: []ui.Surface_Descriptor,
	handle: ui.Object_Handle,
) -> (surface: ui.Surface_Descriptor, found: bool) {
	for candidate in surfaces {
		if candidate.handle == handle do return candidate, true
	}
	return {}, false
}

@(private)
ui_popup_for_content :: proc(
	popups: []ui.Popup_Descriptor,
	surface: ui.Object_Handle,
) -> (popup: ui.Popup_Descriptor, found: bool) {
	for candidate in popups {
		if candidate.content_surface == surface do return candidate, true
	}
	return {}, false
}

@(private)
ui_surface_is_popup_content :: proc(
	popups: []ui.Popup_Descriptor,
	surface: ui.Object_Handle,
) -> bool {
	_, found := ui_popup_for_content(popups, surface)
	return found
}

@(private)
renderer_state_ui_profile :: proc(state: ^Renderer_State) -> ui.Renderer_Profile {
	return ui.Renderer_Profile {
		id = ui.Renderer_Profile_ID(state.profile.id),
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
			.Popup_Overlap,
		},
		unicode_profile = u64(state.profile.id),
		max_rows = state.constraints.height_rows,
		max_columns = state.constraints.width_cells,
		max_cells = u64(state.constraints.height_rows) * u64(state.constraints.width_cells),
		color = state.color,
		attributes = {
			.Bold, .Dim, .Italic, .Underline, .Blink, .Reverse, .Strikethrough, .Overline,
		},
	}
}

@(private)
ui_view_find :: proc(
	views: []ui.Visual_View_Descriptor,
	handle: ui.Object_Handle,
) -> (view: ui.Visual_View_Descriptor, found: bool) {
	for candidate in views {
		if candidate.handle == handle do return candidate, true
	}
	return {}, false
}

@(private)
ui_text_presentation_matches_display :: proc(
	text: ui.Text_View_State,
	logical: editor_view.Snapshot,
	source: display.Snapshot_View,
) -> bool {
	if logical.state_generation != text.source.state_generation ||
	   logical.selection_generation != text.source.selection_generation ||
	   u64(logical.point_position.byte_offset) != text.stored_point ||
	   u64(logical.effective_point_position.byte_offset) != text.effective_point ||
	   logical.mark.present != text.mark_present || logical.region_active != text.region_active ||
	   (logical.selection_shape == .Rectangle) != text.region_rectangular ||
	   u64(logical.viewport_origin_position.byte_offset) != text.viewport_origin ||
	   logical.horizontal_display_column != text.horizontal_display_column ||
	   logical.desired_display_column != text.desired_display_column ||
	   logical.tab_width != text.tab_width ||
	   u64(logical.display_profile_id) != text.display_profile_id ||
	   source.region.active != text.region_active {
		return false
	}
	if text.mark_present && u64(logical.mark.position.byte_offset) != text.mark {
		return false
	}
	if text.region_active {
		start := min(text.mark, text.effective_point)
		end := max(text.mark, text.effective_point)
		if u64(source.region.start) != start || u64(source.region.end) != end ||
		   source.region.rectangular != text.region_rectangular {
			return false
		}
	}
	current_count: int
	for match in source.search_matches {
		if !match.current do continue
		current_count += 1
		if !text.search.present || !text.search.has_current ||
		   u64(match.start) != text.search.current_start ||
		   u64(match.end) != text.search.current_end {
			return false
		}
	}
	return current_count == (1 if text.search.present && text.search.has_current else 0)
}

@(private)
ui_surface_present :: proc(surfaces: []ui.Surface_Descriptor, handle: ui.Object_Handle) -> bool {
	for surface in surfaces {
		if surface.handle == handle do return true
	}
	return false
}

@(private)
ui_status_find :: proc(
	statuses: []ui.Status_Region_Descriptor,
	surface: ui.Object_Handle,
) -> (status: ui.Status_Region_Descriptor, found: bool) {
	for candidate in statuses {
		if candidate.placement != .Attached || candidate.surface != surface do continue
		if found do return {}, false
		status = candidate
		found = true
	}
	return status, found
}

@(private)
ui_style_present :: proc(styles: []ui.Style_Descriptor, role: ui.Style_Role) -> bool {
	for style in styles {
		if style.role == role do return true
	}
	return false
}

@(private)
ui_style_definition :: proc(
	styles: []ui.Style_Descriptor,
	role: ui.Style_Role,
) -> ui.Style_Definition {
	for style in styles {
		if style.role == role {
			return ui.Style_Definition {
				role = style.role,
				foreground = style.foreground,
				background = style.background,
				attributes = style.attributes,
			}
		}
	}
	return {}
}

@(private)
ui_canvas_style :: proc(styles: []ui.Style_Descriptor) -> ui.Style_Definition {
	roles := [?]ui.Style_Role {
		ui.Style_Role.Text_Normal,
		ui.Style_Role.List_Normal,
		ui.Style_Role.Status_Normal,
		ui.Style_Role.Status_Active,
		ui.Style_Role.Diagnostic_Normal,
	}
	for role in roles {
		if ui_style_present(styles, role) do return ui_style_definition(styles, role)
	}
	return {}
}

@(private)
ui_style_compose :: proc(base, overlay: ui.Style_Definition) -> ui.Style_Definition {
	result := base
	result.role = overlay.role
	result.attributes |= overlay.attributes
	if overlay.foreground.present do result.foreground = overlay.foreground
	if overlay.background.present do result.background = overlay.background
	return result
}

@(private)
ui_popup_style_compose :: proc(base, overlay: ui.Style_Definition) -> ui.Style_Definition {
	if base.role != .Popup_Content do return ui_style_compose(base, overlay)
	semantic := overlay
	semantic.background = {}
	return ui_style_compose(base, semantic)
}

@(private)
ui_text_decorations_are_valid :: proc(root: ui.Snapshot_View) -> bool {
	for decoration in root.decorations {
		if !ui_style_present(root.styles, decoration.style_role) do return false
		if decoration.kind != .Text_Range && decoration.kind != .Diagnostic do continue
		view, found := ui_text_view_for_projection(root.views, decoration.projection)
		if !found || decoration.source_revision != view.text.revision ||
		   decoration.end < decoration.start || decoration.end > view.text.source_text_bytes ||
		   decoration.kind == .Text_Range && decoration.start == decoration.end {
			return false
		}
	}
	return true
}

@(private)
ui_text_view_for_projection :: proc(
	views: []ui.Visual_View_Descriptor,
	projection: ui.Object_Handle,
) -> (view: ui.Visual_View_Descriptor, found: bool) {
	for candidate in views {
		if candidate.kind == .Text_View && candidate.text.present &&
		   candidate.projection == projection {
			if found do return {}, false
			view = candidate
			found = true
		}
	}
	return view, found
}

@(private)
ui_input_cursor_cells :: proc(
	profile: display.Display_Profile,
	text: string,
) -> (cells: u32, ok: bool) {
	offset: u64
	for offset < u64(len(text)) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile.unicode, text, offset)
		if !grapheme_ok do return 0, false
		cluster := text[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(
			profile.unicode,
			cluster,
			cells,
			4,
		)
		if !width_ok do return 0, false
		if width.is_line_break || width.is_tab || width.used_replacement {
			cells += 1
		} else {
			cells += u32(width.cells)
		}
		offset = grapheme.end
	}
	return cells, true
}

@(private)
frame_append_gutter_row :: proc(
	frame: ^Render_Frame,
	profile: display.Display_Profile,
	rect: ui.Cell_Rect,
	row: ui.Text_Gutter_Row_Descriptor,
	left, right: string,
	root: ui.Snapshot_View,
) -> bool {
	if row.viewport_row >= u32(rect.height) do return false
	base := ui_style_definition(root.styles, .Gutter_Background)
	if row.left_cells > 0 {
		frame_append_cursor(
			frame,
			u32(rect.row) + row.viewport_row + 1,
			u32(rect.column) + 1,
		)
		if !frame_append_gutter_side(
			frame,
			profile,
			left,
			u32(row.left_cells),
			row.left_separator_bytes,
			false,
			ui_style_compose(base, ui_style_definition(root.styles, row.left_style_role)),
			ui_style_compose(base, ui_style_definition(root.styles, .Gutter_Separator)),
		) {
			return false
		}
	}
	if row.right_cells > 0 {
		frame_append_cursor(
			frame,
			u32(rect.row) + row.viewport_row + 1,
			u32(rect.column + rect.width) - u32(row.right_cells) + 1,
		)
		if !frame_append_gutter_side(
			frame,
			profile,
			right,
			u32(row.right_cells),
			row.right_separator_bytes,
			true,
			ui_style_compose(base, ui_style_definition(root.styles, row.right_style_role)),
			ui_style_compose(base, ui_style_definition(root.styles, .Gutter_Separator)),
		) {
			return false
		}
	}
	frame_reset_style(frame)
	return true
}

@(private)
frame_append_gutter_side :: proc(
	frame: ^Render_Frame,
	profile: display.Display_Profile,
	content: string,
	expected_cells: u32,
	separator_bytes: u8,
	separator_first: bool,
	content_style, separator_style: ui.Style_Definition,
) -> bool {
	cells, cells_ok := ui_input_cursor_cells(profile, content)
	if !cells_ok || cells != expected_cells || int(separator_bytes) > len(content) do return false
	separator_count := int(separator_bytes)
	separator_start := len(content) - separator_count
	if separator_first do separator_start = 0
	separator_end := separator_start + separator_count
	if separator_start > 0 {
		frame_append_style(frame, content_style)
		frame_append_string(frame, content[:separator_start])
	}
	if separator_count > 0 {
		frame_append_style(frame, separator_style)
		frame_append_string(frame, content[separator_start:separator_end])
	}
	if separator_end < len(content) {
		frame_append_style(frame, content_style)
		frame_append_string(frame, content[separator_end:])
	}
	return true
}

@(private)
frame_append_popup :: proc(
	frame: ^Render_Frame,
	state: ^Renderer_State,
	root: ui.Snapshot_View,
	projections: []Text_Surface_Projection,
	popup: ui.Popup_Descriptor,
	surface: ui.Surface_Descriptor,
) -> bool {
	if frame == nil || state == nil || popup.geometry.state != .Placed ||
	   surface.handle != popup.content_surface ||
	   !frame_append_popup_extent(frame, state, root, popup) {
		return false
	}
	view, found := ui_view_find(root.views, surface.view)
	if !found do return false
	geometry := popup.geometry.content
	base_style, base_style_ok := ui_popup_profile_style(
		root.styles,
		popup.presentation_profile,
		.Content,
	)
	if !base_style_ok do return false
	switch view.kind {
	case .Text_View:
		projection, projection_found := ui_projection_find(projections, surface.handle)
		if !projection_found do return false
		source, viewed, _ := display.snapshot_view(projection.snapshot)
		if !viewed do return false
		if view.text.gutter.present {
			for viewport_row in 0 ..< u32(view.text.gutter.row_count) {
				gutter_row, left, right, gutter_row_ok := ui.snapshot_text_gutter_row(
					root,
					view.text,
					viewport_row,
				)
				if !gutter_row_ok || !frame_append_gutter_row(
					frame,
					state.profile,
					geometry,
					gutter_row,
					left,
					right,
					root,
				) {
					return false
				}
			}
		}
		for row in source.rows {
			frame_append_cursor(
				frame,
				u32(geometry.row) + u32(row.viewport_row) + 1,
				u32(geometry.column) + u32(view.text.gutter.left_cells) + 1,
			)
			if !frame_append_display_row(frame, source, row, root, view, base_style) {
				return false
			}
		}
	case .Terminal_View:
		return false
	case .List_View:
		items, items_ok := ui.snapshot_list_visible_items(root, view)
		if !items_ok do return false
		for row in 0 ..< u32(geometry.height) {
			text := ""
			prefix := ""
			style := base_style
			prefix_style := base_style
			mark := ui.List_Mark.None
			item: ui.List_Item_Descriptor
			if int(row) < len(items) {
				item = items[row]
				text, _ = ui.snapshot_list_item_text(root, item)
				mark = item.mark
				source_index := view.list.position.first_visible_item + row
				if i32(source_index) == view.list.position.current_item {
					selection, selection_ok := ui_popup_profile_style(
						root.styles,
						popup.presentation_profile,
						.Selection,
					)
					if !selection_ok do return false
					style = ui_popup_style_compose(base_style, selection)
				}
				prefix_style = style
				if item.icon_role != .Invalid {
					prefix = renderer_list_icon(item.icon_role, state.icons)
					semantic := ui_style_definition(root.styles, item.icon_style_role)
					semantic.background = {}
					prefix_style = ui_style_compose(style, semantic)
				}
			}
			emphasis_style: ui.Style_Definition
			emphasis_bytes := u32(0)
			if int(row) < len(items) && items[row].emphasis_style != .Invalid &&
			   i32(view.list.position.first_visible_item + row) != view.list.position.current_item {
				emphasis_style = ui_style_definition(root.styles, items[row].emphasis_style)
				emphasis_style.background = {}
				emphasis_bytes = items[row].emphasis_bytes
			}
			row_geometry := ui.Cell_Rect {
				row = geometry.row + i32(row),
				column = geometry.column,
				height = 1,
				width = geometry.width,
			}
			if !frame_append_list_row(
				frame, state.profile, row_geometry, prefix, text, style, prefix_style, mark,
				view.list.mark_lane, root, emphasis_style, emphasis_bytes,
				item.style_spans, item.style_span_count,
			) {
				return false
			}
		}
	case .Tree_View:
		nodes, nodes_ok := ui.snapshot_tree_visible_nodes(root, view)
		if !nodes_ok do return false
		for row in 0 ..< u32(geometry.height) {
			text := ""
			prefix := ""
			style := base_style
			icon_style := base_style
			node: ui.Tree_Node_Descriptor
			if int(row) < len(nodes) {
				node = nodes[row]
				text, _ = ui.snapshot_tree_node_text(root, node)
				prefix_bytes: [ui.MAX_TREE_DEPTH * 2 + ui.MAX_TREE_ICON_BYTES + 1]u8
				prefix_count := int(node.indent_depth) * 2
				for index in 0 ..< prefix_count do prefix_bytes[index] = ' '
				icon, icon_ok := ui.snapshot_tree_node_icon(root, node)
				if !icon_ok || len(icon) == 0 {
					icon_role := node.icon_role
					if icon_role == .Invalid {
						icon_role = .Directory_Open if node.expandable && node.expanded else
							.Directory_Closed if node.expandable else .File
					}
					icon = renderer_tree_icon(icon_role, state.icons)
				}
				icon_bytes := transmute([]u8)icon
				copy(prefix_bytes[prefix_count:], icon_bytes)
				prefix_bytes[prefix_count + len(icon_bytes)] = ' '
				prefix = string(prefix_bytes[:prefix_count + len(icon_bytes) + 1])
				source_index := view.tree.position.first_visible_item + row
				if i32(source_index) == view.tree.position.current_item {
					selection, selection_ok := ui_popup_profile_style(
						root.styles,
						popup.presentation_profile,
						.Selection,
					)
					if !selection_ok do return false
					style = ui_popup_style_compose(base_style, selection)
				}
				icon_style = style
				if node.icon_style_role != .Invalid {
					icon_style = ui_style_compose(
						style,
						ui_style_definition(root.styles, node.icon_style_role),
					)
				}
			}
			row_geometry := ui.Cell_Rect {
				row = geometry.row + i32(row),
				column = geometry.column,
				height = 1,
				width = geometry.width,
			}
			if !frame_append_list_row(
				frame, state.profile, row_geometry, prefix, text, style, icon_style,
				.None, false, root, {}, 0, node.style_spans, node.style_span_count,
			) {
				return false
			}
		}
	case .Input:
		value, value_ok := ui.snapshot_input_value(root, view)
		start := int(view.input.first_visible_byte)
		if !value_ok || start > len(value) do return false
		slot := ui.Presentation_Chrome_Slot.Content
		if view.input.validation == .Rejected do slot = .Unavailable
		input_style, input_style_ok := ui_popup_profile_style(
			root.styles,
			popup.presentation_profile,
			slot,
		)
		if !input_style_ok do return false
		style := ui_popup_style_compose(base_style, input_style)
		return frame_append_list_row(
			frame, state.profile, geometry, "", value[start:], style, style, .None,
			false, root, {}, 0, {}, 0,
		)
	case .Invalid:
		return false
	}
	return true
}

@(private)
frame_append_popup_extent :: proc(
	frame: ^Render_Frame,
	state: ^Renderer_State,
	root: ui.Snapshot_View,
	popup: ui.Popup_Descriptor,
) -> bool {
	outer := popup.geometry.outer
	if outer.height <= 0 || outer.width <= 0 do return false
	background, background_ok := ui_popup_profile_style(
		root.styles,
		popup.presentation_profile,
		.Background,
	)
	if !background_ok do return false
	for row in 0 ..< outer.height {
		frame_append_cursor(frame, u32(outer.row + row) + 1, u32(outer.column) + 1)
		frame_append_style(frame, background)
		for _ in 0 ..< outer.width do frame_append_byte(frame, ' ')
	}
	if !popup.border do return true
	border_rect := outer
	border_rect.row += i32(popup.margin_rows)
	border_rect.column += i32(popup.margin_columns)
	border_rect.height -= i32(popup.margin_rows) * 2
	border_rect.width -= i32(popup.margin_columns) * 2
	if border_rect.height < 2 || border_rect.width < 2 do return false
	border_style, border_ok := ui_popup_profile_style(
		root.styles,
		popup.presentation_profile,
		.Border,
	)
	if !border_ok do return false
	border := ui_style_compose(background, border_style)
	top_left, horizontal, top_right := "┌", "─", "┐"
	bottom_left, bottom_right, vertical := "└", "┘", "│"
	if state.icons == .Portable {
		if popup.presentation_profile.definition.degradation == .Reject do return false
		top_left, horizontal, top_right = "+", "-", "+"
		bottom_left, bottom_right, vertical = "+", "+", "|"
	}
	frame_append_cursor(frame, u32(border_rect.row) + 1, u32(border_rect.column) + 1)
	frame_append_style(frame, border)
	frame_append_string(frame, top_left)
	for _ in 0 ..< border_rect.width - 2 do frame_append_string(frame, horizontal)
	frame_append_string(frame, top_right)
	for row in 1 ..< border_rect.height - 1 {
		frame_append_cursor(frame, u32(border_rect.row + row) + 1, u32(border_rect.column) + 1)
		frame_append_string(frame, vertical)
		frame_append_cursor(frame, u32(border_rect.row + row) + 1, u32(border_rect.column + border_rect.width))
		frame_append_string(frame, vertical)
	}
	frame_append_cursor(frame, u32(border_rect.row + border_rect.height - 1) + 1, u32(border_rect.column) + 1)
	frame_append_string(frame, bottom_left)
	for _ in 0 ..< border_rect.width - 2 do frame_append_string(frame, horizontal)
	frame_append_string(frame, bottom_right)
	return true
}

@(private)
ui_popup_profile_style :: proc(
	styles: []ui.Style_Descriptor,
	record: ui.Presentation_Profile_Record,
	slot: ui.Presentation_Chrome_Slot,
) -> (style: ui.Style_Definition, ok: bool) {
	definition := record.definition
	role, mapped := ui.presentation_profile_definition_style(&definition, slot)
	if !mapped || !ui_style_present(styles, role) {
		return {}, false
	}
	return ui_style_definition(styles, role), true
}

@(private)
ui_popup_profile_styles_are_present :: proc(
	styles: []ui.Style_Descriptor,
	record: ui.Presentation_Profile_Record,
) -> bool {
	if !ui.presentation_profile_record_is_valid(record) {
		return false
	}
	definition := record.definition
	for mapping in definition.mappings[:definition.mapping_count] {
		if !ui_style_present(styles, mapping.style_role) {
			return false
		}
	}
	return true
}

@(private)
frame_append_display_row :: proc(
	frame: ^Render_Frame,
	source: display.Snapshot_View,
	row: display.Display_Row,
	root: ui.Snapshot_View,
	view: ui.Visual_View_Descriptor,
	base_style: ui.Style_Definition,
) -> bool {
	cached := Cached_Row{has_content = row.has_content}
	if row.run_count > 0 {
		first := source.runs[row.first_run]
		last := source.runs[row.first_run + row.run_count - 1]
		cached.text_offset = first.text_offset
		cached.text_bytes = last.text_offset + last.text_bytes - first.text_offset
	}
	frame_capture_region(&cached, source, row)
	frame_capture_search(&cached, source, row)
	if cached.text_bytes == 0 {
		return true
	}
	boundaries := source.boundaries[
		row.first_boundary:row.first_boundary + row.boundary_count
	]
	syntax_index := 0
	syntax_range, syntax_visible, syntax_ok := frame_next_syntax_range(
		root.decorations,
		boundaries,
		view.projection,
		view.text.revision,
		&syntax_index,
	)
	if !syntax_ok do return false
	start := int(cached.text_offset)
	offset := u32(0)
	for offset < cached.text_bytes {
		for syntax_visible && offset >= syntax_range.end_text_offset {
			syntax_range, syntax_visible, syntax_ok = frame_next_syntax_range(
				root.decorations,
				boundaries,
				view.projection,
				view.text.revision,
				&syntax_index,
			)
			if !syntax_ok do return false
		}
		next := cached.text_bytes
		style := ui_popup_style_compose(base_style, ui_style_definition(root.styles, .Text_Normal))
		search_visible, _, search_next, search_ok := frame_search_style_at_offset(
			source.search_matches,
			boundaries,
			offset,
			cached.text_bytes,
		)
		if !search_ok do return false
		diagnostic_role, diagnostic_visible, diagnostic_next, diagnostic_ok :=
			frame_diagnostic_style_at_offset(
				root.decorations, boundaries, view.projection, view.text.revision, offset,
			)
		if !diagnostic_ok do return false
		if search_visible {
			style = ui_popup_style_compose(
				base_style,
				ui_style_definition(root.styles, .Text_Search_Current),
			)
			next = search_next
		} else if cached.region_visible && offset >= cached.region_start_text_offset &&
		          offset < cached.region_end_text_offset {
			style = ui_popup_style_compose(base_style, ui_style_definition(root.styles, .Text_Region))
			next = cached.region_end_text_offset
			if search_next > offset do next = min(next, search_next)
		} else if syntax_visible && offset >= syntax_range.start_text_offset &&
		          offset < syntax_range.end_text_offset {
			style = ui_popup_style_compose(
				base_style,
				ui_style_definition(root.styles, syntax_range.style_role),
			)
			next = syntax_range.end_text_offset
		} else {
			if cached.region_visible && cached.region_start_text_offset > offset {
				next = min(next, cached.region_start_text_offset)
			}
			if search_next > offset do next = min(next, search_next)
			if syntax_visible && syntax_range.start_text_offset > offset {
				next = min(next, syntax_range.start_text_offset)
			}
		}
		if diagnostic_visible && !search_visible &&
		   !(cached.region_visible && offset >= cached.region_start_text_offset &&
		     offset < cached.region_end_text_offset) {
			style = ui_style_compose(style, ui_style_definition(root.styles, diagnostic_role))
		}
		if diagnostic_next > offset do next = min(next, diagnostic_next)
		if syntax_visible && syntax_range.start_text_offset > offset {
			next = min(next, syntax_range.start_text_offset)
		}
		if cached.region_visible && cached.region_start_text_offset > offset {
			next = min(next, cached.region_start_text_offset)
		}
		if search_next > offset do next = min(next, search_next)
		if next <= offset do return false
		frame_append_style(frame, style)
		frame_append_bytes(frame, transmute([]u8)source.text[start + int(offset):start + int(next)])
		offset = next
	}
	frame_reset_style(frame)
	return true
}

@(private)
frame_search_style_at_offset :: proc(
	matches: []display.Search_Match_Map,
	boundaries: []display.Boundary_Map,
	offset, row_text_bytes: u32,
) -> (active: bool, current: bool, next: u32, ok: bool) {
	next = row_text_bytes
	if len(boundaries) == 0 do return false, false, next, true
	visible_start := boundaries[0].source_byte_offset
	visible_end := boundaries[len(boundaries) - 1].source_byte_offset
	for match in matches {
		if !match.intersects_visible do continue
		match_start := max(match.start, visible_start)
		match_end := min(match.end, visible_end)
		if match_start >= match_end do continue
		start_text_offset, start_found := region_boundary_text_offset(boundaries, match_start)
		end_text_offset, end_found := region_boundary_text_offset(boundaries, match_end)
		if !start_found || !end_found || start_text_offset >= end_text_offset {
			return false, false, 0, false
		}
		if offset >= start_text_offset && offset < end_text_offset {
			if !active || match.current {
				active = true
				current = match.current
				next = min(next, end_text_offset)
			}
		} else if start_text_offset > offset {
			next = min(next, start_text_offset)
		}
	}
	return active, current, next, true
}

@(private)
frame_diagnostic_style_at_offset :: proc(
	decorations: []ui.Decoration_Descriptor,
	boundaries: []display.Boundary_Map,
	projection: ui.Object_Handle,
	source_revision: u64,
	text_offset: u32,
) -> (role: ui.Style_Role, visible: bool, next: u32, ok: bool) {
	if len(boundaries) < 2 do return {}, false, 0, false
	source_start: u64
	source_end: u64
	boundary_found := false
	for boundary, index in boundaries[:len(boundaries) - 1] {
		if boundary.row_text_offset == text_offset {
			source_start = u64(boundary.source_byte_offset)
			source_end = u64(boundaries[index + 1].source_byte_offset)
			next = boundaries[index + 1].row_text_offset
			boundary_found = true
			break
		}
	}
	if !boundary_found || source_end <= source_start do return {}, false, 0, false
	selected_precedence := u16(0)
	for decoration in decorations {
		if decoration.kind != .Diagnostic || decoration.projection != projection do continue
		if decoration.source_revision != source_revision do return {}, false, 0, false
		point_here := decoration.start == decoration.end && decoration.start == source_start
		range_here := decoration.start < source_end && decoration.end > source_start
		if (point_here || range_here) && (!visible || decoration.precedence > selected_precedence ||
		   decoration.precedence == selected_precedence && decoration.style_role < role) {
			role = decoration.style_role
			selected_precedence = decoration.precedence
			visible = true
		}
	}
	return role, visible, next, true
}

@(private)
Text_Style_Range :: struct {
	start_text_offset: u32,
	end_text_offset:   u32,
	style_role:        ui.Style_Role,
}

@(private)
frame_next_syntax_range :: proc(
	decorations: []ui.Decoration_Descriptor,
	boundaries: []display.Boundary_Map,
	projection: ui.Object_Handle,
	source_revision: u64,
	index: ^int,
) -> (result: Text_Style_Range, visible: bool, ok: bool) {
	if index == nil || len(boundaries) < 2 do return {}, false, false
	visible_start := u64(boundaries[0].source_byte_offset)
	visible_end := u64(boundaries[len(boundaries) - 1].source_byte_offset)
	for index^ < len(decorations) {
		decoration := decorations[index^]
		index^ += 1
		if decoration.kind != .Text_Range || decoration.projection != projection do continue
		if decoration.source_revision != source_revision do return {}, false, false
		if decoration.end <= visible_start do continue
		if decoration.start >= visible_end do return {}, false, true
		start := max(decoration.start, visible_start)
		end := min(decoration.end, visible_end)
		start_offset, start_found := region_boundary_text_offset(
			boundaries,
			editor.Byte_Offset(start),
		)
		end_offset, end_found := region_boundary_text_offset(
			boundaries,
			editor.Byte_Offset(end),
		)
		if !start_found || !end_found || start_offset >= end_offset do return {}, false, false
		return Text_Style_Range {
			start_text_offset = start_offset,
			end_text_offset = end_offset,
			style_role = decoration.style_role,
		}, true, true
	}
	return {}, false, true
}

@(private)
frame_append_separator :: proc(frame: ^Render_Frame, rect: ui.Cell_Rect) {
	if rect.width != 1 || rect.height <= 0 {
		return
	}
	for row in 0 ..< rect.height {
		frame_append_cursor(frame, u32(rect.row + row) + 1, u32(rect.column) + 1)
		frame_append_string(frame, "│")
	}
}

@(private)
frame_append_list_row :: proc(
	frame: ^Render_Frame,
	profile: display.Display_Profile,
	rect: ui.Cell_Rect,
	prefix: string,
	text: string,
	style: ui.Style_Definition,
	prefix_style: ui.Style_Definition,
	mark: ui.List_Mark,
	mark_lane: bool,
	root: ui.Snapshot_View,
	emphasis_style: ui.Style_Definition,
	emphasis_bytes: u32,
	style_spans: [ui.MAX_LIST_ITEM_STYLE_SPANS]ui.List_Item_Style_Span,
	style_span_count: u8,
) -> bool {
	frame_append_cursor(frame, u32(rect.row) + 1, u32(rect.column) + 1)
	frame_append_style(frame, prefix_style)
	column := u32(0)
	prefix_offset: u64
	for prefix_offset < u64(len(prefix)) && column < u32(rect.width) {
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(
			profile.unicode,
			prefix,
			prefix_offset,
		)
		if !grapheme_ok do return false
		cluster := prefix[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(profile.unicode, cluster, column, 4)
		if !width_ok do return false
		if width.is_line_break || width.is_tab || width.used_replacement {
			cluster = "?"
			width.cells = 1
		}
		if column + u32(width.cells) > u32(rect.width) do break
		frame_append_string(frame, cluster)
		column += u32(width.cells)
		prefix_offset = grapheme.end
	}
	frame_append_style(frame, style)
	if len(text) > 0 && mark_lane {
		mark_style := style
		mark_prefix := "  "
		if mark == .Save {
			mark_prefix = "S "
			mark_style = ui_style_compose(style, ui_style_definition(root.styles, .List_Mark_Save))
		} else if mark == .Kill {
			mark_prefix = "D "
			mark_style = ui_style_compose(style, ui_style_definition(root.styles, .List_Mark_Kill))
		}
		frame_append_style(frame, mark_style)
		prefix_cells := min(u32(rect.width), u32(2))
		frame_append_string(frame, mark_prefix[:prefix_cells])
		frame_append_style(frame, style)
		column = prefix_cells
	}
	offset: u64
	emphasis_active := emphasis_bytes > 0
	active_role := ui.Style_Role.Invalid
	span_index := 0
	for offset < u64(len(text)) && column < u32(rect.width) {
		for span_index < int(style_span_count) &&
		    offset >= u64(style_spans[span_index].end_byte) {
			span_index += 1
		}
		next_role := ui.Style_Role.Invalid
		if span_index < int(style_span_count) &&
		   offset >= u64(style_spans[span_index].start_byte) {
			next_role = style_spans[span_index].style_role
		}
		if next_role != active_role {
			if next_role == .Invalid {
				frame_append_style(frame, style)
			} else {
				semantic_style := ui_style_definition(root.styles, next_role)
				if next_role != .Text_Search_Current do semantic_style.background = {}
				frame_append_style(frame, ui_style_compose(style, semantic_style))
			}
			active_role = next_role
		}
		if emphasis_active && offset >= u64(emphasis_bytes) {
			emphasis_active = false
			if active_role == .Invalid do frame_append_style(frame, style)
		} else if emphasis_active && active_role == .Invalid && offset == 0 {
			frame_append_style(frame, ui_style_compose(style, emphasis_style))
		}
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile.unicode, text, offset)
		if !grapheme_ok do return false
		cluster := text[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(profile.unicode, cluster, column, 4)
		if !width_ok do return false
		if width.is_line_break || width.is_tab || width.used_replacement {
			cluster = "?"
			width.cells = 1
		}
		if column + u32(width.cells) > u32(rect.width) do break
		frame_append_string(frame, cluster)
		column += u32(width.cells)
		offset = grapheme.end
	}
	if emphasis_bytes > 0 || style_span_count > 0 do frame_append_style(frame, style)
	for column < u32(rect.width) {
		frame_append_byte(frame, ' ')
		column += 1
	}
	frame_reset_style(frame)
	return true
}

@(private)
frame_append_status :: proc(
	frame: ^Render_Frame,
	profile: display.Display_Profile,
	rect: ui.Cell_Rect,
	status: string,
	style: ui.Style_Definition,
	root: ui.Snapshot_View,
	style_spans: [ui.MAX_STATUS_STYLE_SPANS]ui.Status_Style_Span,
	style_span_count: u8,
	active: bool,
) -> bool {
	if rect.height != 1 && rect.height != 2 do return false
	content_rect := rect
	if rect.height == 2 {
		frame_append_status_separator(frame, rect, style)
		content_rect.row += 1
		content_rect.height = 1
	}
	frame_append_cursor(frame, u32(content_rect.row) + 1, u32(content_rect.column) + 1)
	frame_append_style(frame, style)
	column := u32(0)
	offset: u64
	active_role := ui.Style_Role.Invalid
	span_index := 0
	for offset < u64(len(status)) && column < u32(content_rect.width) {
		if active {
			for span_index < int(style_span_count) &&
			    offset >= u64(style_spans[span_index].end_byte) {
				span_index += 1
			}
			next_role := ui.Style_Role.Invalid
			if span_index < int(style_span_count) &&
			   offset >= u64(style_spans[span_index].start_byte) {
				next_role = style_spans[span_index].style_role
			}
			if next_role != active_role {
				if next_role == .Invalid {
					frame_append_style(frame, style)
				} else {
					semantic_style := ui_style_definition(root.styles, next_role)
					semantic_style.background = {}
					frame_append_style(frame, ui_style_compose(style, semantic_style))
				}
				active_role = next_role
			}
		}
		grapheme, grapheme_ok, _ := display.profile_next_grapheme(profile.unicode, status, offset)
		if !grapheme_ok {
			return false
		}
		cluster := status[grapheme.start:grapheme.end]
		width, width_ok, _ := display.profile_cluster_width(profile.unicode, cluster, column, 4)
		if !width_ok {
			return false
		}
		if width.is_line_break || width.is_tab || width.used_replacement {
			cluster = "?"
			width.cells = 1
		}
		if column + u32(width.cells) > u32(content_rect.width) {
			break
		}
		frame_append_string(frame, cluster)
		column += u32(width.cells)
		offset = grapheme.end
	}
	if active_role != .Invalid do frame_append_style(frame, style)
	for column < u32(content_rect.width) {
		frame_append_byte(frame, ' ')
		column += 1
	}
	frame_reset_style(frame)
	return true
}

@(private)
frame_append_status_separator :: proc(
	frame: ^Render_Frame,
	rect: ui.Cell_Rect,
	style: ui.Style_Definition,
) {
	frame_append_cursor(frame, u32(rect.row) + 1, u32(rect.column) + 1)
	frame_append_style(frame, style)
	for _ in 0 ..< rect.width do frame_append_string(frame, "─")
}

@(private)
terminal_view_cursor_is_active :: proc(
	root: ui.Snapshot_View,
	surface: ui.Surface_Descriptor,
	view: ui.Visual_View_Descriptor,
) -> bool {
	if view.kind != .Terminal_View || root.focus.target != surface.handle do return false
	cursor := view.terminal.cursor
	return cursor.visible && cursor.in_viewport && cursor.row < u16(surface.geometry.height) &&
		cursor.column < u16(surface.geometry.width)
}

@(private)
frame_append_terminal_view :: proc(
	frame: ^Render_Frame,
	root: ui.Snapshot_View,
	view: ui.Visual_View_Descriptor,
	rect: ui.Cell_Rect,
) -> bool {
	rows, rows_ok := ui.snapshot_terminal_rows(root, view)
	cells, cells_ok := ui.snapshot_terminal_cells(root, view)
	if !rows_ok || !cells_ok || len(rows) < int(rect.height) do return false
	base := ui.Style_Definition {
		foreground = {present = true, color = view.terminal.foreground},
		background = {present = true, color = view.terminal.background},
	}
	if view.terminal.visual_attention do base.attributes += {.Reverse}
	for row in 0 ..< rect.height {
		frame_append_cursor(frame, u32(rect.row + row) + 1, u32(rect.column) + 1)
		frame_append_style(frame, base)
		for _ in 0 ..< rect.width do frame_append_byte(frame, ' ')
	}
	for cell in cells {
		if cell.row >= u16(rect.height) || cell.column >= u16(rect.width) ||
		   cell.width == 2 || cell.width == 3 {
			continue
		}
		if cell.width == 1 && u32(cell.column) + 1 >= u32(rect.width) do continue
		frame_append_cursor(
			frame,
			u32(rect.row) + u32(cell.row) + 1,
			u32(rect.column) + u32(cell.column) + 1,
		)
		frame_transition_style(frame, terminal_cell_style_lower(view.terminal, cell, frame.color))
		if cell.text_length == 0 || cell.style.invisible {
			frame_append_byte(frame, ' ')
		} else {
			copy_cell := cell
			frame_append_bytes(frame, copy_cell.text[:int(copy_cell.text_length)])
		}
	}
	return true
}

@(private)
terminal_cell_style_lower :: proc(
	view: ui.Terminal_View_State,
	cell: ui.Terminal_Cell,
	capability: ui.Renderer_Color_Capability,
) -> Terminal_Style {
	style := terminal_style_lower(terminal_cell_style(view, cell), capability)
	if cell.style.underline_color.kind != .Default {
		color := terminal_cell_color(cell.style.underline_color, view.foreground, view.palette)
		style.underline_color = terminal_color_lower({present = true, color = color}, capability)
	}
	return style
}

@(private)
terminal_cell_style :: proc(
	view: ui.Terminal_View_State,
	cell: ui.Terminal_Cell,
) -> ui.Style_Definition {
	foreground := terminal_cell_color(cell.style.foreground, view.foreground, view.palette)
	background := terminal_cell_color(cell.style.background, view.background, view.palette)
	attributes := cell.style.attributes
	if view.visual_attention {
		if .Reverse in attributes {
			attributes -= {.Reverse}
		} else {
			attributes += {.Reverse}
		}
	}
	if cell.selected {
		if .Reverse in attributes {
			attributes -= {.Reverse}
		} else {
			attributes += {.Reverse}
		}
	}
	if cell.style.invisible do foreground = background
	return ui.Style_Definition {
		foreground = {present = true, color = foreground},
		background = {present = true, color = background},
		attributes = attributes,
	}
}

@(private)
terminal_cell_color :: proc(
	color: ui.Terminal_Color,
	default_color: ui.SRGB_Color,
	palette: [256]ui.SRGB_Color,
) -> ui.SRGB_Color {
	switch color.kind {
	case .Default: return default_color
	case .Palette: return palette[color.palette]
	case .RGB: return color.rgb
	}
	return default_color
}

@(private)
frame_append_terminal_cursor_style :: proc(
	frame: ^Render_Frame,
	style: ui.Terminal_Cursor_Style,
	blinking: bool,
) {
	frame_append_string(frame, "\x1b[")
	code := u32(1)
	switch style {
	case .Block, .Hollow_Block: code = 1 if blinking else 2
	case .Underline: code = 3 if blinking else 4
	case .Bar: code = 5 if blinking else 6
	}
	frame_append_decimal(frame, code)
	frame_append_string(frame, " q")
}

@(private)
frame_append_style :: proc(frame: ^Render_Frame, style: ui.Style_Definition) {
	frame_transition_style(frame, terminal_style_lower(style, frame.color))
}

@(private)
frame_reset_style :: proc(frame: ^Render_Frame) {
	frame_transition_style(frame, {})
}
