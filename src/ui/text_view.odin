// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../editor"
import editor_view "../view"

/* proposal_project_editor_text_view copies one exact delivered editor-view generation. */
proposal_project_editor_text_view :: proc(
	proposal: ^Proposal,
	source_registry: ^editor_view.Registry,
	source_handle: editor_view.View_Handle,
	buffer: ^editor.Buffer,
	owner_id: Owner_ID,
	read_only := false,
	search_override: ^editor_view.Search_Snapshot = nil,
	cursor_shape := Text_Cursor_Shape.Default,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || owner_id == Owner_ID(0) || cursor_shape > .Underline {
		return {}, false, source_view_failure(state, source_handle, .Invalid_Text_View)
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(source_registry, source_handle)
	if !logical_ok {
		return {}, false, map_source_view_failure(state, source_handle, logical_failure)
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.buffer_id != logical.buffer_id || stats.revision != logical.revision {
		return {}, false, source_view_failure(state, source_handle, .Incompatible_Text_View)
	}
	search, search_ok, search_failure := editor_view.search_session_view(
		source_registry,
		source_handle,
	)
	if !search_ok {
		return {}, false, map_source_view_failure(state, source_handle, search_failure)
	}
	if search_override != nil do search = search_override^
	text, text_ok := text_view_state_from_source(source_handle, logical, search, stats.text_bytes)
	if !text_ok {
		return {}, false, source_view_failure(state, source_handle, .Invalid_Text_View)
	}
	text.cursor_shape = cursor_shape
	if state.projection_count >= len(state.projections) || state.view_count >= len(state.views) {
		return {}, false, source_view_failure(state, source_handle, .View_Limit)
	}
	projection_bytes := u64(size_of(Text_View_State))
	if projection_bytes > state.registry.limits.projection_bytes - state.accounting.projection_bytes {
		failure = source_view_failure(state, source_handle, .Projection_Limit)
		failure.limit = state.registry.limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + projection_bytes
		return {}, false, failure
	}
	if state.next_object_id == Object_ID(max(u64)) ||
	   u64(state.next_object_id) == u64(max(u64)) - 1 {
		return {}, false, source_view_failure(state, source_handle, .Generation_Limit)
	}
	model_generation := u64(logical.revision)
	if model_generation == max(u64) {
		return {}, false, source_view_failure(state, source_handle, .Generation_Limit)
	}
	projection_handle, projection_handle_ok := next_handle(state, state.projection_count)
	view_handle, view_handle_ok := next_handle(state, state.view_count)
	if !projection_handle_ok || !view_handle_ok {
		return {}, false, source_view_failure(state, source_handle, .Generation_Limit)
	}
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = projection_handle,
		model = Model_Reference {
			owner_id = owner_id,
			model_id = Model_ID(logical.buffer_id),
			generation = Model_Generation(model_generation + 1),
		},
		byte_count = projection_bytes,
		read_only = read_only,
	}
	state.projection_count += 1
	state.accounting.projection_bytes += projection_bytes
	state.views[state.view_count] = Visual_View_Descriptor {
		handle = view_handle,
		kind = .Text_View,
		projection = projection_handle,
		read_only = read_only,
		text = text,
	}
	state.view_count += 1
	return view_handle, true, {}
}

@(private)
text_view_state_from_source :: proc(
	handle: editor_view.View_Handle,
	logical: editor_view.Snapshot,
	search: editor_view.Search_Snapshot,
	source_text_bytes: u64,
) -> (state: Text_View_State, ok: bool) {
	if handle.registry_id == editor_view.Registry_ID(0) || handle.view_id == editor_view.View_ID(0) ||
	   logical.view_id != handle.view_id || logical.view_generation != handle.generation ||
	   logical.buffer_id == editor.Buffer_ID(0) ||
	   u64(logical.point_position.byte_offset) > source_text_bytes ||
	   u64(logical.effective_point_position.byte_offset) > source_text_bytes ||
	   u64(logical.viewport_origin_position.byte_offset) > source_text_bytes ||
	   logical.mark.present && u64(logical.mark.position.byte_offset) > source_text_bytes {
		return {}, false
	}
	state = Text_View_State {
		present = true,
		source = Text_View_Source {
			registry_id = u32(handle.registry_id),
			view_id = u64(handle.view_id),
			view_generation = handle.generation,
			state_generation = logical.state_generation,
			selection_generation = logical.selection_generation,
		},
		buffer_id = u64(logical.buffer_id),
		revision = u64(logical.revision),
		source_text_bytes = source_text_bytes,
		stored_point = u64(logical.point_position.byte_offset),
		effective_point = u64(logical.effective_point_position.byte_offset),
		mark_present = logical.mark.present,
		region_active = logical.region_active,
		region_rectangular = logical.selection_shape == .Rectangle,
		viewport_origin = u64(logical.viewport_origin_position.byte_offset),
		horizontal_display_column = logical.horizontal_display_column,
		desired_display_column = logical.desired_display_column,
		tab_width = logical.tab_width,
		display_profile_id = u64(logical.display_profile_id),
		presentation_ownership = map_text_ownership(logical.presentation_ownership),
	}
	if logical.mark.present {
		state.mark = u64(logical.mark.position.byte_offset)
	}
	if search.present {
		if search.source_revision != logical.revision ||
		   search.status == .Inactive || search.interaction_generation == 0 ||
		   len(search.occurrences) > int(max(u32)) {
			return {}, false
		}
		state.search = Text_Search_Descriptor {
			present = true,
			interaction_generation = search.interaction_generation,
			source_revision = u64(search.source_revision),
			status = map_text_search_status(search.status),
			match_count = u32(len(search.occurrences)),
			has_current = search.has_current,
		}
		if search.has_current {
			if search.current_index >= u32(len(search.occurrences)) {
				return {}, false
			}
			current := search.occurrences[search.current_index]
			if current.buffer_id != logical.buffer_id || current.revision != logical.revision ||
			   current.start > current.end || u64(current.end) > source_text_bytes {
				return {}, false
			}
			state.search.current_start = u64(current.start)
			state.search.current_end = u64(current.end)
		}
	}
	return state, text_view_state_is_valid(state)
}

@(private)
map_text_ownership :: proc(value: editor_view.Presentation_Ownership) -> Text_Presentation_Ownership {
	switch value {
	case .Retained_Primary:
		return .Retained_Primary
	case .Additional:
		return .Additional
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
map_text_search_status :: proc(value: editor_view.Search_Status) -> Text_Search_Status {
	switch value {
	case .Inactive:
		return .Inactive
	case .Active:
		return .Active
	case .Failing:
		return .Failing
	case .Pending:
		return .Pending
	case .Wrapped:
		return .Wrapped
	}
	return .Inactive
}

@(private)
map_source_view_failure :: proc(
	state: ^Generation_State,
	handle: editor_view.View_Handle,
	source: editor_view.Failure_Context,
) -> Failure {
	code := Failure_Code.Invalid_Text_View
	#partial switch source.code {
	case .Wrong_Registry:
		code = .Wrong_Registry
	case .Stale_View:
		code = .Stale_Text_View
	case .Invalid_View:
		code = .Invalid_Text_View
	}
	return source_view_failure(state, handle, code)
}

@(private)
source_view_failure :: proc(
	state: ^Generation_State,
	handle: editor_view.View_Handle,
	code: Failure_Code,
) -> Failure {
	failure := generation_failure(state, .Prepare, code)
	failure.source_view_id = u64(handle.view_id)
	failure.source_view_generation = handle.generation
	return failure
}
