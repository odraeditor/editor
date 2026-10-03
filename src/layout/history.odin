// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"

/* pane_buffer_state_from_view copies one checked redisplay state from a live view snapshot. */
pane_buffer_state_from_view :: proc(
	entry: editor_session.Entry_Handle,
	snapshot: view.Snapshot,
) -> Pane_Buffer_State {
	return Pane_Buffer_State {
		entry = entry,
		buffer_id = snapshot.buffer_id,
		stored_point = snapshot.point_position,
		viewport_start = snapshot.viewport_origin_position,
		horizontal_display_column = snapshot.horizontal_display_column,
		desired_display_column = snapshot.desired_display_column,
	}
}

/* registry_pane_history_record publishes one unique pane history and top-level recency update. */
registry_pane_history_record :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
	state: Pane_Buffer_State,
) -> (layout_handle: Layout_Handle, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Record_History)
	if resolved.code != .None {
		return {}, false, resolved
	}
	_, pane_ref, pane_failure := resolve_pane(data, pane, .Record_History)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	if !pane_buffer_state_is_valid(state) || !entry_session_matches(data, state.entry) {
		failure = data_failure(data, .Record_History, .Invalid_Buffer_State)
		failure.pane = pane
		return {}, false, failure
	}
	if data.generation == Layout_Generation(max(u64)) || data.next_history_sequence == max(u64) {
		return {}, false, data_failure(data, .Record_History, .Generation_Limit)
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Record_History)
	}
	proposed, prepared := prepared_state_copy(data, .Record_History)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	slot := resolve_node(proposed, pane_ref)
	assert(slot != nil && slot.kind == .Pane)
	pane_history_touch(proposed, slot, state)
	buffer_list_touch(proposed, state.entry, state.buffer_id)
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Record_History, .Invalid_Topology)
	}
	handle := current_layout_handle(proposed)
	registry_publish(registry, proposed)
	return handle, true, {}
}

/* registry_pane_history_snapshot copies one exact pane-local history generation. */
registry_pane_history_snapshot :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
) -> (snapshot: Pane_History_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Inspect)
	if resolved.code != .None {
		return {}, false, resolved
	}
	slot, _, pane_failure := resolve_pane(data, pane, .Inspect)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	snapshot.layout = current_layout_handle(data)
	snapshot.pane = pane_handle(data, Node_Ref{slot = pane.slot, generation = pane.slot_generation})
	snapshot.generation = slot.history_generation
	snapshot.count = slot.history_count
	copy(snapshot.entries[:], slot.history[:])
	return snapshot, true, {}
}

/* registry_pane_history_previous returns the most recent entry other than the excluded buffer. */
registry_pane_history_previous :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
	excluded: editor.Buffer_ID,
) -> (entry: Pane_History_Entry, found: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Inspect)
	if resolved.code != .None {
		return {}, false, resolved
	}
	slot, _, pane_failure := resolve_pane(data, pane, .Inspect)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	for candidate in slot.history[:slot.history_count] {
		if candidate.state.buffer_id != excluded {
			return candidate, true, {}
		}
	}
	return {}, false, {}
}

/* registry_buffer_list_snapshot copies the independent top-level buffer recency list. */
registry_buffer_list_snapshot :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
) -> (snapshot: Buffer_List_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Inspect)
	if resolved.code != .None {
		return {}, false, resolved
	}
	snapshot.layout = current_layout_handle(data)
	snapshot.generation = data.buffer_list_generation
	snapshot.count = data.buffer_list_count
	copy(snapshot.entries[:], data.buffer_list[:])
	return snapshot, true, {}
}

/* registry_pane_history_purge removes one undisplayed buffer from every pane and the top-level list. */
registry_pane_history_purge :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
) -> (layout_handle: Layout_Handle, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Purge_History)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if !editor_session.entry_handle_is_valid(entry) || buffer_id == editor.Buffer_ID(0) ||
	   !entry_session_matches(data, entry) {
		return {}, false, data_failure(data, .Purge_History, .Invalid_Buffer_State)
	}
	for &slot, index in data.nodes {
		if slot.live && slot.kind == .Pane && slot.buffer_id == buffer_id {
			failure = data_failure(data, .Purge_History, .Buffer_Displayed)
			failure.pane = pane_handle(data, Node_Ref{slot = u16(index), generation = slot.generation})
			return {}, false, failure
		}
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Purge_History, .Generation_Limit)
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Purge_History)
	}
	proposed, prepared := prepared_state_copy(data, .Purge_History)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	changed := false
	for &slot in proposed.nodes {
		if slot.live && slot.kind == .Pane {
			changed = pane_history_remove(&slot, entry, buffer_id) || changed
		}
	}
	changed = buffer_list_remove(proposed, entry, buffer_id) || changed
	if !changed {
		return current_layout_handle(data), true, {}
	}
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Purge_History, .Invalid_Topology)
	}
	handle := current_layout_handle(proposed)
	registry_publish(registry, proposed)
	return handle, true, {}
}

@(private)
pane_buffer_state_is_valid :: proc(state: Pane_Buffer_State) -> bool {
	return editor_session.entry_handle_is_valid(state.entry) &&
	       state.buffer_id != editor.Buffer_ID(0) &&
	       state.stored_point.buffer_id == state.buffer_id &&
	       state.viewport_start.buffer_id == state.buffer_id &&
	       state.stored_point.revision == state.viewport_start.revision
}

@(private)
entry_session_matches :: proc(data: ^Registry_Data, entry: editor_session.Entry_Handle) -> bool {
	if data == nil || !editor_session.entry_handle_is_valid(entry) {
		return false
	}
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane && editor_session.entry_handle_is_valid(slot.entry) {
			return slot.entry.registry.session == entry.registry.session
		}
	}
	for candidate in data.buffer_list[:data.buffer_list_count] {
		return candidate.entry.registry.session == entry.registry.session
	}
	return true
}

@(private)
pane_history_touch :: proc(data: ^Registry_Data, slot: ^Node_Slot, state: Pane_Buffer_State) {
	assert(data != nil && slot != nil && pane_buffer_state_is_valid(state))
	assert(data.next_history_sequence < max(u64))
	data.next_history_sequence += 1
	entry := Pane_History_Entry {
		state = state,
		insertion_sequence = data.next_history_sequence,
	}
	index := int(slot.history_count)
	for candidate, candidate_index in slot.history[:slot.history_count] {
		if candidate.state.buffer_id == state.buffer_id {
			index = candidate_index
			break
		}
	}
	if index == int(slot.history_count) && slot.history_count < data.policy.pane_history_entries {
		slot.history_count += 1
	}
	if index >= int(data.policy.pane_history_entries) {
		index = int(data.policy.pane_history_entries) - 1
	}
	for index > 0 {
		slot.history[index] = slot.history[index - 1]
		index -= 1
	}
	slot.history[0] = entry
	slot.history_generation += 1
}

@(private)
buffer_list_touch :: proc(
	data: ^Registry_Data,
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
) {
	assert(data != nil && editor_session.entry_handle_is_valid(entry) && buffer_id != editor.Buffer_ID(0))
	assert(data.next_history_sequence < max(u64))
	data.next_history_sequence += 1
	candidate := Buffer_List_Entry {
		entry = entry,
		buffer_id = buffer_id,
		insertion_sequence = data.next_history_sequence,
	}
	index := int(data.buffer_list_count)
	for existing, existing_index in data.buffer_list[:data.buffer_list_count] {
		if existing.buffer_id == buffer_id {
			index = existing_index
			break
		}
	}
	if index == int(data.buffer_list_count) && data.buffer_list_count < data.policy.top_level_buffers {
		data.buffer_list_count += 1
	}
	if index >= int(data.policy.top_level_buffers) {
		index = int(data.policy.top_level_buffers) - 1
	}
	for index > 0 {
		data.buffer_list[index] = data.buffer_list[index - 1]
		index -= 1
	}
	data.buffer_list[0] = candidate
	data.buffer_list_generation += 1
}

@(private)
pane_history_remove :: proc(
	slot: ^Node_Slot,
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
) -> bool {
	write: int
	removed := false
	for candidate in slot.history[:slot.history_count] {
		if candidate.state.entry == entry || candidate.state.buffer_id == buffer_id {
			removed = true
			continue
		}
		slot.history[write] = candidate
		write += 1
	}
	if !removed {
		return false
	}
	for index in write ..< int(slot.history_count) {
		slot.history[index] = {}
	}
	slot.history_count = u16(write)
	slot.history_generation += 1
	return true
}

@(private)
buffer_list_remove :: proc(
	data: ^Registry_Data,
	entry: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
) -> bool {
	write: int
	removed := false
	for candidate in data.buffer_list[:data.buffer_list_count] {
		if candidate.entry == entry || candidate.buffer_id == buffer_id {
			removed = true
			continue
		}
		data.buffer_list[write] = candidate
		write += 1
	}
	if !removed {
		return false
	}
	for index in write ..< int(data.buffer_list_count) {
		data.buffer_list[index] = {}
	}
	data.buffer_list_count = u16(write)
	data.buffer_list_generation += 1
	return true
}

@(private)
pane_history_is_valid :: proc(data: ^Registry_Data, slot: ^Node_Slot) -> bool {
	if data == nil || slot == nil || slot.history_count > data.policy.pane_history_entries ||
	   u64(slot.history_count) * u64(size_of(Pane_History_Entry)) > data.policy.pane_history_bytes {
		return false
	}
	if editor_session.entry_handle_is_valid(slot.entry) {
		if slot.buffer_id == editor.Buffer_ID(0) {
			return false
		}
	} else if slot.entry != (editor_session.Entry_Handle{}) || slot.history_count != 0 {
		return false
	}
	for candidate, index in slot.history[:slot.history_count] {
		if !pane_buffer_state_is_valid(candidate.state) || candidate.insertion_sequence == 0 ||
		   candidate.state.entry.registry.session != slot.entry.registry.session {
			return false
		}
		if index > 0 && candidate.insertion_sequence >= slot.history[index - 1].insertion_sequence {
			return false
		}
		for previous in slot.history[:index] {
			if previous.state.buffer_id == candidate.state.buffer_id {
				return false
			}
		}
	}
	return true
}

@(private)
buffer_list_is_valid :: proc(data: ^Registry_Data) -> bool {
	if data == nil || data.buffer_list_count > data.policy.top_level_buffers {
		return false
	}
	for candidate, index in data.buffer_list[:data.buffer_list_count] {
		if !editor_session.entry_handle_is_valid(candidate.entry) ||
		   candidate.buffer_id == editor.Buffer_ID(0) || candidate.insertion_sequence == 0 {
			return false
		}
		if index > 0 && candidate.insertion_sequence >= data.buffer_list[index - 1].insertion_sequence {
			return false
		}
		for previous in data.buffer_list[:index] {
			if previous.buffer_id == candidate.buffer_id {
				return false
			}
		}
	}
	return true
}

@(private)
registry_history_entry_count :: proc(data: ^Registry_Data) -> u32 {
	count: u32
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane {
			count += u32(slot.history_count)
		}
	}
	return count
}

@(private)
registry_history_bytes :: proc(data: ^Registry_Data) -> u64 {
	return u64(registry_history_entry_count(data)) * u64(size_of(Pane_History_Entry))
}
