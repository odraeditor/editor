// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* proposal_project_list_view copies one complete bounded list presentation generation. */
proposal_project_list_view :: proc(
	proposal: ^Proposal,
	request: List_Projection_Request,
	items: []List_Item_Definition,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || request.model.owner_id == Owner_ID(0) ||
	   request.model.model_id == Model_ID(0) ||
	   request.model.generation == Model_Generation(0) || len(items) > int(max(u32)) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_List_View)
	}
	item_count := u32(len(items))
	list_state := List_View_State {
		present = true,
		mark_lane = request.mark_lane,
		item_offset = u32(state.list_item_count),
		item_count = item_count,
		position = request.position,
	}
	if !list_view_state_is_valid(list_state) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_List_View)
	}
	if state.projection_count >= len(state.projections) || state.view_count >= len(state.views) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	if len(items) > len(state.list_items) - state.list_item_count {
		failure = generation_failure(state, .Prepare, .List_Item_Limit)
		failure.limit = u64(state.registry.limits.list_items)
		failure.actual = u64(state.list_item_count) + u64(len(items))
		return {}, false, failure
	}
	if !resolve_style_role(state, .List_Normal) || !resolve_style_role(state, .List_Current) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
	}
	text_bytes: u64
	needs_save_style, needs_kill_style: bool
	for item, index in items {
		if item.id == List_Item_ID(0) {
			failure = generation_failure(state, .Prepare, .Invalid_List_Item)
			failure.actual = u64(index)
			return {}, false, failure
		}
		for previous in 0 ..< index {
			if items[previous].id == item.id {
				failure = generation_failure(state, .Prepare, .Duplicate_List_Item)
				failure.actual = u64(index)
				return {}, false, failure
			}
		}
		if !utf8.valid_string(item.text) || len(item.text) > int(max(u32)) {
			failure = generation_failure(state, .Prepare, .Malformed_List_Text)
			failure.actual = u64(index)
			return {}, false, failure
		}
		icon_present := item.icon_role != .Invalid || item.icon_style_role != .Invalid
		if icon_present &&
		   (item.icon_role <= .Invalid || item.icon_role > .Keyword ||
		    !style_role_is_valid(item.icon_style_role) ||
		    !resolve_style_role(state, item.icon_style_role)) {
			failure = generation_failure(state, .Prepare, .Invalid_Style)
			failure.actual = u64(index)
			return {}, false, failure
		}
		emphasis_present := item.emphasis_bytes > 0 || item.emphasis_style != .Invalid
		if emphasis_present &&
		   (item.emphasis_bytes == 0 || item.emphasis_bytes > u32(len(item.text)) ||
		    !style_role_is_valid(item.emphasis_style) ||
		    !utf8.valid_string(item.text[:int(item.emphasis_bytes)]) ||
		    !resolve_style_role(state, item.emphasis_style)) {
			failure = generation_failure(state, .Prepare, .Invalid_Style)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if item.style_span_count > MAX_LIST_ITEM_STYLE_SPANS {
			failure = generation_failure(state, .Prepare, .Invalid_Style)
			failure.actual = u64(index)
			return {}, false, failure
		}
		previous_end := u32(0)
		for span_index in 0 ..< int(item.style_span_count) {
			span := item.style_spans[span_index]
			if span.start_byte < previous_end || span.start_byte >= span.end_byte ||
			   span.end_byte > u32(len(item.text)) || !style_role_is_valid(span.style_role) ||
			   !utf8.valid_string(item.text[:int(span.start_byte)]) ||
			   !utf8.valid_string(item.text[:int(span.end_byte)]) ||
			   !resolve_style_role(state, span.style_role) {
				failure = generation_failure(state, .Prepare, .Invalid_Style)
				failure.actual = u64(index) * MAX_LIST_ITEM_STYLE_SPANS + u64(span_index)
				return {}, false, failure
			}
			previous_end = span.end_byte
		}
		if (item.passive && item.action != List_Action_Reference{}) ||
		   (!item.passive && !list_action_reference_is_valid(item.action)) {
			failure = generation_failure(state, .Prepare, .Invalid_List_Action)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if item.passive && item.mark != .None {
			failure = generation_failure(state, .Prepare, .Invalid_List_Mark)
			failure.actual = u64(index)
			return {}, false, failure
		}
		switch item.mark {
		case .None:
		case .Save:
			needs_save_style = true
		case .Kill:
			needs_kill_style = true
		case:
			failure = generation_failure(state, .Prepare, .Invalid_List_Mark)
			failure.actual = u64(index)
			return {}, false, failure
		}
		if u64(len(item.text)) > max(u64) - text_bytes {
			return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
		}
		text_bytes += u64(len(item.text))
	}
	if item_count > 0 && items[int(request.position.current_item)].passive {
		failure = generation_failure(state, .Prepare, .Invalid_List_Action)
		failure.actual = u64(request.position.current_item)
		return {}, false, failure
	}
	if !request.mark_lane && (needs_save_style || needs_kill_style) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_List_Mark)
	}
	if needs_save_style && !resolve_style_role(state, .List_Mark_Save) ||
	   needs_kill_style && !resolve_style_role(state, .List_Mark_Kill) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_Style)
	}
	descriptor_bytes := u64(len(items)) * u64(size_of(List_Item_Descriptor))
	if text_bytes > max(u64) - descriptor_bytes {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	projection_bytes := descriptor_bytes + text_bytes
	if projection_bytes > state.registry.limits.projection_bytes - state.accounting.projection_bytes {
		failure = generation_failure(state, .Prepare, .Projection_Limit)
		failure.limit = state.registry.limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + projection_bytes
		return {}, false, failure
	}
	if text_bytes > u64(max(int)) - u64(len(state.list_content)) {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	temporary_bytes := u64(len(state.list_content)) * 2 + text_bytes
	if temporary_bytes > state.registry.limits.temporary_bytes {
		failure = generation_failure(state, .Prepare, .Temporary_Memory_Limit)
		failure.limit = state.registry.limits.temporary_bytes
		failure.actual = temporary_bytes
		return {}, false, failure
	}
	if u64(state.next_object_id) > max(u64) - 2 {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	content_size := len(state.list_content) + int(text_bytes)
	content, allocation_error := make([]u8, content_size, state.allocator)
	if allocation_error != nil {
		failure = generation_failure(state, .Prepare, .Allocation)
		failure.actual = u64(content_size)
		return {}, false, failure
	}
	copy(content, state.list_content)
	projection, projection_ok := next_handle(state, state.projection_count)
	view, view_ok := next_handle(state, state.view_count)
	assert(projection_ok && view_ok)
	content_offset := len(state.list_content)
	for item, index in items {
		length := len(item.text)
		copy(content[content_offset:], transmute([]u8)item.text)
		state.list_items[state.list_item_count + index] = List_Item_Descriptor {
			projection = projection,
			id = item.id,
			text_offset = u64(content_offset),
			text_bytes = u32(length),
			icon_role = item.icon_role,
			icon_style_role = item.icon_style_role,
			action = item.action,
			mark = item.mark,
			passive = item.passive,
			emphasis_bytes = item.emphasis_bytes,
			emphasis_style = item.emphasis_style,
			style_spans = item.style_spans,
			style_span_count = item.style_span_count,
		}
		content_offset += length
	}
	if state.list_content != nil do delete(state.list_content, state.allocator)
	state.list_content = content
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = projection,
		model = request.model,
		byte_count = projection_bytes,
		item_count = item_count,
		read_only = request.read_only,
	}
	state.projection_count += 1
	state.views[state.view_count] = Visual_View_Descriptor {
		handle = view,
		kind = .List_View,
		projection = projection,
		read_only = request.read_only,
		list = list_state,
	}
	state.view_count += 1
	state.list_item_count += len(items)
	state.accounting.projection_bytes += projection_bytes
	state.accounting.list_items = u32(state.list_item_count)
	state.accounting.temporary_peak_bytes = max(
		state.accounting.temporary_peak_bytes, temporary_bytes,
	)
	return view, true, {}
}

/* list_view_move_current moves only view-owned selection and keeps it visible. */
list_view_move_current :: proc(
	state: List_View_State,
	delta: i32,
) -> (next: List_View_State, changed, ok: bool, failure: Failure) {
	if !list_view_state_is_valid(state) {
		return {}, false, false, Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	if state.position.selection_owner != .View {
		return {}, false, false, Failure{operation = .Navigate, code = .Wrong_Owner}
	}
	if state.item_count == 0 || delta == 0 {
		return state, false, true, {}
	}
	target := i64(state.position.current_item) + i64(delta)
	target = max(i64(0), min(target, i64(state.item_count) - 1))
	if i32(target) == state.position.current_item {
		return state, false, true, {}
	}
	next = state
	next.position.current_item = i32(target)
	list_view_keep_current_visible(&next)
	return list_view_advance(next, .Navigate)
}

/* list_view_follow_model copies one model-owned current item without taking ownership. */
list_view_follow_model :: proc(
	state: List_View_State,
	current_item: i32,
) -> (next: List_View_State, changed, ok: bool, failure: Failure) {
	if !list_view_state_is_valid(state) {
		return {}, false, false, Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	if state.position.selection_owner != .Model {
		return {}, false, false, Failure{operation = .Navigate, code = .Wrong_Owner}
	}
	if state.item_count == 0 || current_item < 0 || u32(current_item) >= state.item_count {
		return {}, false, false, Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	if current_item == state.position.current_item {
		return state, false, true, {}
	}
	next = state
	next.position.current_item = current_item
	list_view_keep_current_visible(&next)
	return list_view_advance(next, .Navigate)
}

/* list_view_resize changes the bounded viewport and retains a visible current item. */
list_view_resize :: proc(
	state: List_View_State,
	viewport_items: u32,
) -> (next: List_View_State, changed, ok: bool, failure: Failure) {
	if !list_view_state_is_valid(state) || viewport_items == 0 ||
	   viewport_items > MAX_LIST_ITEMS {
		return {}, false, false, Failure{operation = .Resize, code = .Invalid_List_View}
	}
	if viewport_items == state.position.viewport_items {
		return state, false, true, {}
	}
	next = state
	next.position.viewport_items = viewport_items
	list_view_keep_current_visible(&next)
	return list_view_advance(next, .Resize)
}

/* snapshot_list_items borrows every checked item owned by one list view. */
snapshot_list_items :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (items: []List_Item_Descriptor, ok: bool) {
	if view.kind != .List_View || !list_view_state_is_valid(view.list) ||
	   int(view.handle.slot) >= len(snapshot.views) || snapshot.views[view.handle.slot] != view {
		return nil, false
	}
	start := int(view.list.item_offset)
	count := int(view.list.item_count)
	if start > len(snapshot.list_items) || count > len(snapshot.list_items) - start {
		return nil, false
	}
	items = snapshot.list_items[start:start + count]
	for item in items {
		if item.projection != view.projection ||
		   item.text_offset > u64(len(snapshot.list_content)) ||
		   u64(item.text_bytes) > u64(len(snapshot.list_content)) - item.text_offset {
			return nil, false
		}
	}
	return items, true
}

/* snapshot_list_visible_items borrows the clipped viewport for one list view. */
snapshot_list_visible_items :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (items: []List_Item_Descriptor, ok: bool) {
	all, all_ok := snapshot_list_items(snapshot, view)
	if !all_ok {
		return nil, false
	}
	first := int(view.list.position.first_visible_item)
	visible := min(int(view.list.position.viewport_items), len(all) - first)
	return all[first:first + visible], true
}

/* snapshot_list_item_text borrows one checked UTF-8 item value. */
snapshot_list_item_text :: proc(
	snapshot: Snapshot_View,
	item: List_Item_Descriptor,
) -> (text: string, ok: bool) {
	if item.id == List_Item_ID(0) || item.text_offset > u64(len(snapshot.list_content)) ||
	   u64(item.text_bytes) > u64(len(snapshot.list_content)) - item.text_offset {
		return "", false
	}
	start := int(item.text_offset)
	return string(snapshot.list_content[start:start + int(item.text_bytes)]), true
}

@(private)
list_view_matches_projection :: proc(
	generation: ^Generation_State,
	list: List_View_State,
	projection: ^Projection_Descriptor,
) -> bool {
	if generation == nil || projection == nil || !list_view_state_is_valid(list) ||
	   projection.item_count != list.item_count ||
	   !resolve_style_role(generation, .List_Normal) ||
	   !resolve_style_role(generation, .List_Current) {
		return false
	}
	start := int(list.item_offset)
	count := int(list.item_count)
	if start > generation.list_item_count || count > generation.list_item_count - start {
		return false
	}
	text_bytes: u64
	items := generation.list_items[start:start + count]
	for item, index in items {
		if item.projection != projection.handle || item.id == List_Item_ID(0) ||
		   (item.icon_role == .Invalid) != (item.icon_style_role == .Invalid) ||
		   item.icon_role > .Keyword ||
		   (item.icon_style_role != .Invalid &&
		    !resolve_style_role(generation, item.icon_style_role)) ||
		   (item.passive && (item.action != List_Action_Reference{} || item.mark != .None)) ||
		   (!item.passive && !list_action_reference_is_valid(item.action)) ||
		   (item.mark != .None && item.mark != .Save && item.mark != .Kill) ||
		   (item.mark == .Save && !resolve_style_role(generation, .List_Mark_Save)) ||
		   (item.mark == .Kill && !resolve_style_role(generation, .List_Mark_Kill)) ||
		   (item.emphasis_bytes == 0) != (item.emphasis_style == .Invalid) ||
		   item.emphasis_bytes > item.text_bytes ||
		   (item.emphasis_style != .Invalid && !resolve_style_role(generation, item.emphasis_style)) ||
		   item.style_span_count > MAX_LIST_ITEM_STYLE_SPANS ||
		   item.text_offset > u64(len(generation.list_content)) ||
		   u64(item.text_bytes) > u64(len(generation.list_content)) - item.text_offset {
			return false
		}
		if item.emphasis_bytes > 0 {
			text_start := int(item.text_offset)
			prefix := string(generation.list_content[
				text_start:text_start + int(item.emphasis_bytes)
			])
			if !utf8.valid_string(prefix) {
				return false
			}
		}
		previous_end := u32(0)
		for span_index in 0 ..< int(item.style_span_count) {
			span := item.style_spans[span_index]
			if span.start_byte < previous_end || span.start_byte >= span.end_byte ||
			   span.end_byte > item.text_bytes ||
			   !resolve_style_role(generation, span.style_role) {
				return false
			}
			text_start := int(item.text_offset)
			if !utf8.valid_string(string(generation.list_content[
				text_start:text_start + int(span.start_byte)
			])) || !utf8.valid_string(string(generation.list_content[
				text_start:text_start + int(span.end_byte)
			])) {
				return false
			}
			previous_end = span.end_byte
		}
		for previous in 0 ..< index {
			if items[previous].id == item.id do return false
		}
		text_bytes += u64(item.text_bytes)
	}
	if count > 0 && items[int(list.position.current_item)].passive do return false
	return projection.byte_count ==
		u64(count) * u64(size_of(List_Item_Descriptor)) + text_bytes
}

@(private)
list_action_reference_is_valid :: proc(action: List_Action_Reference) -> bool {
	return action.owner_id != Owner_ID(0) && action.action_id != List_Action_ID(0) &&
		action.generation != 0
}

@(private)
list_view_keep_current_visible :: proc(state: ^List_View_State) {
	if state.item_count == 0 {
		state.position.current_item = -1
		state.position.first_visible_item = 0
		return
	}
	current := u32(state.position.current_item)
	if current < state.position.first_visible_item {
		state.position.first_visible_item = current
	}
	end := u64(state.position.first_visible_item) + u64(state.position.viewport_items)
	if u64(current) >= end {
		state.position.first_visible_item = current - state.position.viewport_items + 1
	}
}

@(private)
list_view_advance :: proc(
	state: List_View_State,
	operation: Operation,
) -> (next: List_View_State, changed, ok: bool, failure: Failure) {
	if state.position.presentation_generation == max(u64) {
		return {}, false, false, Failure{operation = operation, code = .Generation_Limit}
	}
	next = state
	next.position.presentation_generation += 1
	assert(list_view_state_is_valid(next))
	return next, true, true, {}
}
