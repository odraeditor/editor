// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:unicode/utf8"

/* proposal_project_input copies one complete bounded transient-input presentation. */
proposal_project_input :: proc(
	proposal: ^Proposal,
	request: Input_Projection_Request,
	value: string,
	choices: []Input_Choice_Definition = nil,
) -> (handle: Object_Handle, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	if state == nil || request.model.owner_id == Owner_ID(0) ||
	   request.model.model_id == Model_ID(0) ||
	   request.model.generation == Model_Generation(0) ||
	   request.presentation_generation == 0 || request.backing_generation == 0 ||
	   request.viewport_bytes == 0 ||
	   (request.validation != .Valid && request.validation != .Rejected) ||
	   len(value) > int(max(u32)) || len(choices) > int(max(u16)) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_View)
	}
	if !utf8.valid_string(value) || request.cursor_offset > u32(len(value)) ||
	   request.first_visible_byte > request.cursor_offset ||
	   !input_offset_is_boundary(value, request.cursor_offset) ||
	   !input_offset_is_boundary(value, request.first_visible_byte) {
		return {}, false, generation_failure(state, .Prepare, .Invalid_View)
	}
	visible_end := u64(request.first_visible_byte) + u64(request.viewport_bytes)
	if u64(request.cursor_offset) >= visible_end {
		return {}, false, generation_failure(state, .Prepare, .Invalid_View)
	}
	if state.projection_count >= len(state.projections) || state.view_count >= len(state.views) {
		return {}, false, generation_failure(state, .Prepare, .View_Limit)
	}
	if len(choices) > len(state.input_choices) - state.input_choice_count {
		failure = generation_failure(state, .Prepare, .Fixed_Choice_Limit)
		failure.limit = u64(state.registry.limits.fixed_choices)
		failure.actual = u64(state.input_choice_count) + u64(len(choices))
		return {}, false, failure
	}
	content_bytes := u64(len(value))
	for choice, index in choices {
		if choice.id == Input_Choice_ID(0) || len(choice.name) == 0 ||
		   !utf8.valid_string(choice.name) || len(choice.name) > int(max(u32)) ||
		   !list_action_reference_is_valid(choice.action) {
			failure = generation_failure(state, .Prepare, .Invalid_View)
			failure.actual = u64(index)
			return {}, false, failure
		}
		for previous in 0 ..< index {
			if choices[previous].id == choice.id {
				failure = generation_failure(state, .Prepare, .Invalid_View)
				failure.actual = u64(index)
				return {}, false, failure
			}
		}
		if u64(len(choice.name)) > max(u64) - content_bytes {
			return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
		}
		content_bytes += u64(len(choice.name))
	}
	if content_bytes > u64(state.registry.limits.input_bytes) - u64(state.accounting.input_bytes) {
		failure = generation_failure(state, .Prepare, .Input_Limit)
		failure.limit = u64(state.registry.limits.input_bytes)
		failure.actual = u64(state.accounting.input_bytes) + content_bytes
		return {}, false, failure
	}
	descriptor_bytes := u64(len(choices)) * u64(size_of(Input_Choice_Descriptor))
	if content_bytes > max(u64) - descriptor_bytes {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	projection_bytes := descriptor_bytes + content_bytes
	if projection_bytes > state.registry.limits.projection_bytes - state.accounting.projection_bytes {
		failure = generation_failure(state, .Prepare, .Projection_Limit)
		failure.limit = state.registry.limits.projection_bytes
		failure.actual = state.accounting.projection_bytes + projection_bytes
		return {}, false, failure
	}
	if content_bytes > u64(max(int)) - u64(len(state.input_content)) {
		return {}, false, generation_failure(state, .Prepare, .Checked_Integer_Overflow)
	}
	temporary_bytes := u64(len(state.input_content)) * 2 + content_bytes
	if temporary_bytes > state.registry.limits.temporary_bytes {
		failure = generation_failure(state, .Prepare, .Temporary_Memory_Limit)
		failure.limit = state.registry.limits.temporary_bytes
		failure.actual = temporary_bytes
		return {}, false, failure
	}
	if u64(state.next_object_id) > max(u64) - 2 {
		return {}, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	content_size := len(state.input_content) + int(content_bytes)
	content, allocation_error := make([]u8, content_size, state.allocator)
	if allocation_error != nil {
		failure = generation_failure(state, .Prepare, .Allocation)
		failure.actual = u64(content_size)
		return {}, false, failure
	}
	copy(content, state.input_content)
	projection, projection_ok := next_handle(state, state.projection_count)
	view, view_ok := next_handle(state, state.view_count)
	assert(projection_ok && view_ok)
	value_offset := len(state.input_content)
	copy(content[value_offset:], transmute([]u8)value)
	content_offset := value_offset + len(value)
	for choice, index in choices {
		length := len(choice.name)
		copy(content[content_offset:], transmute([]u8)choice.name)
		state.input_choices[state.input_choice_count + index] = Input_Choice_Descriptor {
			projection = projection,
			id = choice.id,
			name_offset = u64(content_offset),
			name_bytes = u32(length),
			action = choice.action,
		}
		content_offset += length
	}
	if state.input_content != nil do delete(state.input_content, state.allocator)
	state.input_content = content
	input := Input_View_State {
		present = true,
		presentation_generation = request.presentation_generation,
		backing_generation = request.backing_generation,
		value_offset = u64(value_offset),
		value_bytes = u32(len(value)),
		cursor_offset = request.cursor_offset,
		first_visible_byte = request.first_visible_byte,
		viewport_bytes = request.viewport_bytes,
		validation = request.validation,
		choice_offset = u16(state.input_choice_count),
		choice_count = u16(len(choices)),
	}
	state.projections[state.projection_count] = Projection_Descriptor {
		handle = projection,
		model = request.model,
		byte_count = projection_bytes,
		item_count = u32(len(choices)),
		read_only = request.read_only,
	}
	state.projection_count += 1
	state.views[state.view_count] = Visual_View_Descriptor {
		handle = view,
		kind = .Input,
		projection = projection,
		read_only = request.read_only,
		input = input,
	}
	state.view_count += 1
	state.input_choice_count += len(choices)
	state.accounting.projection_bytes += projection_bytes
	state.accounting.input_bytes += u32(content_bytes)
	state.accounting.fixed_choices = u16(state.input_choice_count)
	state.accounting.temporary_peak_bytes = max(
		state.accounting.temporary_peak_bytes, temporary_bytes,
	)
	return view, true, {}
}

/* snapshot_input_value borrows one checked copied input value. */
snapshot_input_value :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (value: string, ok: bool) {
	if view.kind != .Input || !input_view_state_is_valid(view.input) ||
	   int(view.handle.slot) >= len(snapshot.views) || snapshot.views[view.handle.slot] != view ||
	   view.input.value_offset > u64(len(snapshot.input_content)) ||
	   u64(view.input.value_bytes) > u64(len(snapshot.input_content)) - view.input.value_offset {
		return "", false
	}
	start := int(view.input.value_offset)
	return string(snapshot.input_content[start:start + int(view.input.value_bytes)]), true
}

/* snapshot_input_choices borrows every checked fixed choice for one input view. */
snapshot_input_choices :: proc(
	snapshot: Snapshot_View,
	view: Visual_View_Descriptor,
) -> (choices: []Input_Choice_Descriptor, ok: bool) {
	if view.kind != .Input || !input_view_state_is_valid(view.input) ||
	   int(view.handle.slot) >= len(snapshot.views) || snapshot.views[view.handle.slot] != view {
		return nil, false
	}
	start := int(view.input.choice_offset)
	count := int(view.input.choice_count)
	if start > len(snapshot.input_choices) || count > len(snapshot.input_choices) - start {
		return nil, false
	}
	choices = snapshot.input_choices[start:start + count]
	for choice in choices {
		if choice.projection != view.projection || choice.id == Input_Choice_ID(0) ||
		   choice.name_offset > u64(len(snapshot.input_content)) ||
		   u64(choice.name_bytes) > u64(len(snapshot.input_content)) - choice.name_offset ||
		   !list_action_reference_is_valid(choice.action) {
			return nil, false
		}
	}
	return choices, true
}

/* snapshot_input_choice_name borrows one checked copied choice name. */
snapshot_input_choice_name :: proc(
	snapshot: Snapshot_View,
	choice: Input_Choice_Descriptor,
) -> (name: string, ok: bool) {
	if choice.id == Input_Choice_ID(0) || choice.name_offset > u64(len(snapshot.input_content)) ||
	   u64(choice.name_bytes) > u64(len(snapshot.input_content)) - choice.name_offset {
		return "", false
	}
	start := int(choice.name_offset)
	return string(snapshot.input_content[start:start + int(choice.name_bytes)]), true
}

@(private)
input_view_matches_projection :: proc(
	generation: ^Generation_State,
	input: Input_View_State,
	projection: ^Projection_Descriptor,
) -> bool {
	if generation == nil || projection == nil || !input_view_state_is_valid(input) ||
	   projection.item_count != u32(input.choice_count) ||
	   input.value_offset > u64(len(generation.input_content)) ||
	   u64(input.value_bytes) > u64(len(generation.input_content)) - input.value_offset {
		return false
	}
	start := int(input.choice_offset)
	count := int(input.choice_count)
	if start > generation.input_choice_count || count > generation.input_choice_count - start {
		return false
	}
	content_bytes := u64(input.value_bytes)
	for choice, index in generation.input_choices[start:start + count] {
		if choice.projection != projection.handle || choice.id == Input_Choice_ID(0) ||
		   !list_action_reference_is_valid(choice.action) ||
		   choice.name_offset > u64(len(generation.input_content)) ||
		   u64(choice.name_bytes) > u64(len(generation.input_content)) - choice.name_offset {
			return false
		}
		for previous in 0 ..< index {
			if generation.input_choices[start + previous].id == choice.id do return false
		}
		content_bytes += u64(choice.name_bytes)
	}
	return projection.byte_count ==
		u64(count) * u64(size_of(Input_Choice_Descriptor)) + content_bytes
}

@(private)
input_offset_is_boundary :: proc(value: string, offset: u32) -> bool {
	if offset > u32(len(value)) {
		return false
	}
	return utf8.valid_string(value[:int(offset)])
}
