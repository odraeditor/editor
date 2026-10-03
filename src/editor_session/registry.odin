// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import "../project"
import editor_view "../view"
import "core:strings"
import "core:unicode/utf8"

/* prepared_entry_publish atomically publishes and activates one complete reserved graph. */
prepared_entry_publish :: proc(
	prepared: ^Prepared_Entry,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	state := prepared_entry_state(prepared)
	if state == nil || state.session == nil || state.owner == nil {
		return {}, false, Failure_Context{code = .Invalid_Reservation, operation = .Publish_Entry}
	}
	data := state.session
	if state.slot < 0 || state.slot >= len(data.slots) {
		return {}, false, session_failure(data, .Publish_Entry, .Invalid_Reservation)
	}
	slot := &data.slots[state.slot]
	if !slot.reserved || slot.live || slot.owner != state.owner ||
	   entry_handle(data, state.slot) != state.handle {
		return {}, false, session_failure(data, .Publish_Entry, .Invalid_Reservation)
	}

	slot.owner = state.owner
	slot.reserved = false
	slot.live = true
	data.usage.prepared_operations -= 1
	data.usage.live_buffers += 1
	data.usage.live_primary_views += 1
	data.usage.activation_entries += 1
	if state.owner.document_live {
		assert(data.reserved_documents > 0)
		data.reserved_documents -= 1
		data.usage.live_documents += 1
	}
	mru_link_front(data, state.slot)
	data.visible = visible_from_slot(data, state.slot)
	session_project_focus_path(data, state.owner.normalized_path)
	result = Admission_Result {
		outcome = .Published,
		entry = state.handle,
		visible = data.visible,
		usage = data.usage,
	}
	prepared.state = nil
	free(state, data.allocator)
	assert(session_validate(data))
	return result, true, {}
}

/* prepared_entry_abort releases one unpublished graph and every reserved identity. */
prepared_entry_abort :: proc(
	prepared: ^Prepared_Entry,
) -> (ok: bool, failure: Failure_Context) {
	state := prepared_entry_state(prepared)
	if state == nil || state.session == nil || state.owner == nil {
		return false, Failure_Context{code = .Invalid_Reservation, operation = .Abort_Entry}
	}
	data := state.session
	cleaned, cleanup_failure := owner_cleanup(data, state.owner, .Abort_Entry)
	if !cleaned {
		return false, cleanup_failure
	}
	entry_identity_unreserve(data, state.slot, state.owner)
	if state.owner.document_live || state.owner.reservation.documents > 0 {
		assert(data.reserved_documents > 0)
		data.reserved_documents -= 1
	}
	usage_release_retained(data, state.owner.reservation)
	assert(data.usage.prepared_operations > 0)
	data.usage.prepared_operations -= 1
	owner_release_storage(data, state.owner)
	prepared.state = nil
	free(state, data.allocator)
	assert(session_validate(data))
	return true, {}
}

/* session_find_label resolves one complete selection label to a checked live entry handle. */
session_find_label :: proc(
	session: ^Session,
	handle: Session_Handle,
	selection_label: string,
) -> (entry: Entry_Handle, found: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Find_Label)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	encoded := data.label_index[selection_label]
	if encoded == 0 {
		return {}, false, {}
	}
	slot_index := encoded - 1
	slot := &data.slots[slot_index]
	if !slot.live {
		return {}, false, {}
	}
	return entry_handle(data, slot_index), true, {}
}

/* session_find_path resolves one normalized associated path to a checked live entry handle. */
session_find_path :: proc(
	session: ^Session,
	handle: Session_Handle,
	normalized_path: string,
) -> (entry: Entry_Handle, found: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Find_Path)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	encoded := data.path_index[normalized_path]
	if encoded == 0 {
		return {}, false, {}
	}
	slot_index := encoded - 1
	slot := &data.slots[slot_index]
	if !slot.live {
		return {}, false, {}
	}
	return entry_handle(data, slot_index), true, {}
}

/* session_entry_label returns one bounded copy of an exact live entry selection label. */
session_entry_label :: proc(
	session: ^Session,
	handle: Entry_Handle,
) -> (label: Closure_Label, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	slot, _, resolved_failure := resolve_entry(data, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return closure_label_copy(slot.owner.selection_label), true, {}
}

/* session_mru_entries copies every live entry handle in deterministic activation order. */
session_mru_entries :: proc(
	session: ^Session,
	handle: Session_Handle,
	destination: []Entry_Handle,
) -> (count: u32, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return 0, false, resolved_failure
	}
	if len(destination) < int(data.usage.live_buffers) {
		failure = session_failure(data, .Inspect, .Descriptor_Limit)
		failure.maximum = u64(len(destination))
		failure.actual = u64(data.usage.live_buffers)
		return 0, false, failure
	}
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		destination[count] = entry_handle(data, slot_index)
		count += 1
	}
	return count, true, {}
}

/* session_ordered_entries copies live entries in stable session-slot order. */
session_ordered_entries :: proc(
	session: ^Session,
	handle: Session_Handle,
	destination: []Entry_Handle,
) -> (count: u32, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return 0, false, resolved_failure
	}
	if len(destination) < int(data.usage.live_buffers) {
		failure = session_failure(data, .Inspect, .Descriptor_Limit)
		failure.maximum = u64(len(destination))
		failure.actual = u64(data.usage.live_buffers)
		return 0, false, failure
	}
	for slot_index in 0 ..< len(data.slots) {
		if !data.slots[slot_index].live do continue
		destination[count] = entry_handle(data, slot_index)
		count += 1
	}
	return count, true, {}
}

/* session_descriptors copies the complete live inventory in active-then-MRU order. */
session_descriptors :: proc(
	session: ^Session,
	handle: Session_Handle,
	allocator := context.allocator,
) -> (batch: Descriptor_Batch, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if allocator.procedure == nil {
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	if data.usage.live_buffers > data.policy.descriptor_batch {
		failure = session_failure(data, .Inspect, .Descriptor_Limit)
		failure.maximum = u64(data.policy.descriptor_batch)
		failure.actual = u64(data.usage.live_buffers)
		return {}, false, failure
	}
	label_bytes: u64
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		owner := data.slots[slot_index].owner
		label_bytes += u64(len(owner.selection_label) + len(owner.terminal_context))
	}
	state, state_error := new(Descriptor_Batch_State, allocator)
	if state_error != nil {
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	state.allocator = allocator
	descriptors, descriptors_error := make(
		[]Entry_Descriptor,
		int(data.usage.live_buffers),
		allocator,
	)
	if descriptors_error != nil {
		free(state, allocator)
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	state.descriptors = descriptors
	labels, labels_error := make([]u8, int(label_bytes), allocator)
	if labels_error != nil {
		delete(descriptors, allocator)
		free(state, allocator)
		return {}, false, session_failure(data, .Inspect, .Persistent_Memory_Limit)
	}
	state.labels = labels
	label_offset := 0
	descriptor_index := 0
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		slot := &data.slots[slot_index]
		owner := slot.owner
		buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(&owner.buffer)
		if !buffer_ok {
			descriptor_batch_state_destroy(state)
			failure = session_failure(data, .Inspect, .Editor_Failure)
			failure.editor_failure = buffer_failure
			return {}, false, failure
		}
		persistence := document.Persistence_State.Unassociated
		modified := buffer_stats.revision != editor.Revision(0)
		if owner.kind == .Terminal do modified = false
		if owner.document_live {
			status, status_ok, status_failure := document.document_status(&owner.document)
			if !status_ok {
				descriptor_batch_state_destroy(state)
				failure = session_failure(data, .Inspect, .Document_Failure)
				failure.document_failure = status_failure
				return {}, false, failure
			}
			persistence = status.persistence
			modified = !status.has_saved_revision || status.saved_revision != buffer_stats.revision
		}
		label_length := len(owner.selection_label)
		copy(state.labels[label_offset:], transmute([]u8)owner.selection_label)
		label := string(state.labels[label_offset:label_offset + label_length])
		label_offset += label_length
		terminal_context_length := len(owner.terminal_context)
		copy(state.labels[label_offset:], transmute([]u8)owner.terminal_context)
		terminal_context := string(state.labels[label_offset:label_offset + terminal_context_length])
		handle := entry_handle(data, slot_index)
		state.descriptors[descriptor_index] = Entry_Descriptor {
			graph = owner_graph(owner, handle),
			kind = owner.kind,
			selection_label = label,
			association = owner.association,
			persistence = persistence,
			operation = .Idle,
			active = slot_index == data.mru_head,
			modified = modified,
			activation_sequence = slot.activation_sequence,
			terminal = Terminal_Buffer_Source {
				ref = owner.terminal_ref,
				lifecycle = owner.terminal_lifecycle,
				working_context = terminal_context,
			},
		}
		label_offset += terminal_context_length
		descriptor_index += 1
	}
	batch.state = state
	batch.descriptors = state.descriptors
	return batch, true, {}
}

/* descriptor_batch_close releases copied descriptors and their retained labels. */
descriptor_batch_close :: proc(batch: ^Descriptor_Batch) -> bool {
	if batch == nil || batch.state == nil {
		return false
	}
	state := (^Descriptor_Batch_State)(batch.state)
	descriptor_batch_state_destroy(state)
	batch.state = nil
	batch.descriptors = nil
	return true
}

@(private)
descriptor_batch_state_destroy :: proc(state: ^Descriptor_Batch_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	delete(state.descriptors, allocator)
	delete(state.labels, allocator)
	free(state, allocator)
}

/* session_entry_ownership returns one copied complete-graph identity and reservation. */
session_entry_ownership :: proc(
	session: ^Session,
	handle: Entry_Handle,
) -> (snapshot: Ownership_Snapshot, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	slot, _, resolved_failure := resolve_entry(data, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return Ownership_Snapshot {
		graph = owner_graph(slot.owner, handle),
		state = .Published_Session,
		reservation = slot.owner.reservation,
	}, true, {}
}

/* session_active_entry_access creates a checked native capability for the visible primary view. */
session_active_entry_access :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (access: Entry_Access, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if data.visible.kind != .Primary_View {
		return {}, false, session_failure(data, .Inspect, .Invalid_Visible_Target)
	}
	return Entry_Access {
		state = data,
		entry = data.visible.entry,
	}, true, {}
}

/* session_entry_access creates a checked native capability for one exact live entry. */
session_entry_access :: proc(
	session: ^Session,
	handle: Entry_Handle,
) -> (access: Entry_Access, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	_, _, resolved_failure := resolve_entry(data, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return Entry_Access {state = data, entry = handle}, true, {}
}

/* entry_access_borrow revalidates one access and borrows its owned objects for one native call. */
entry_access_borrow :: proc(
	access: Entry_Access,
) -> (borrow: Entry_Borrow, ok: bool, failure: Failure_Context) {
	if access.state == nil {
		return {}, false, Failure_Context{code = .Invalid_Entry, operation = .Inspect}
	}
	data := (^Session_Data)(access.state)
	slot, _, resolved_failure := resolve_entry(data, access.entry, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return Entry_Borrow {
		kind = slot.owner.kind,
		buffer = &slot.owner.buffer,
		history_store = &slot.owner.history_store,
		document = &slot.owner.document if slot.owner.document_live else nil,
		has_document = slot.owner.document_live,
		view_registry = &data.view_registry,
		primary_view = slot.owner.primary_view,
		terminal = Terminal_Buffer_Source {
			ref = slot.owner.terminal_ref,
			lifecycle = slot.owner.terminal_lifecycle,
			working_context = slot.owner.terminal_context,
		},
	}, true, {}
}

/* entry_access_reconcile refreshes mutable text and history charges after one native command. */
entry_access_reconcile :: proc(
	access: Entry_Access,
) -> (usage: Resource_Usage, ok: bool, failure: Failure_Context) {
	if access.state == nil {
		return {}, false, Failure_Context{code = .Invalid_Entry, operation = .Inspect}
	}
	data := (^Session_Data)(access.state)
	slot, _, resolved_failure := resolve_entry(data, access.entry, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(&slot.owner.buffer)
	if !buffer_ok {
		failure = session_failure(data, .Inspect, .Editor_Failure)
		failure.editor_failure = buffer_failure
		return {}, false, failure
	}
	history_stats, history_ok, history_failure := history.store_stats(&slot.owner.history_store)
	if !history_ok {
		failure = session_failure(data, .Inspect, .History_Failure)
		failure.history_failure = history_failure
		return {}, false, failure
	}
	projected_text := data.usage.canonical_text_bytes -
	                  slot.owner.reservation.canonical_text_bytes + buffer_stats.text_bytes
	if projected_text > data.policy.aggregate_text_bytes {
		failure = session_failure(data, .Inspect, .Aggregate_Text_Limit)
		failure.maximum = data.policy.aggregate_text_bytes
		failure.actual = projected_text
		return {}, false, failure
	}
	data.usage.canonical_text_bytes = projected_text
	data.usage.history_bytes = data.usage.history_bytes -
	                           slot.owner.reservation.history_bytes +
	                           history_stats.usage.retained_bytes
	slot.owner.reservation.canonical_text_bytes = buffer_stats.text_bytes
	slot.owner.reservation.history_bytes = history_stats.usage.retained_bytes
	return data.usage, true, {}
}

/* session_activation_validate checks one activation without changing visible or MRU state. */
session_activation_validate :: proc(
	session: ^Session,
	handle: Entry_Handle,
) -> (ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return false, Failure_Context{code = .Invalid_Session, operation = .Activate}
	}
	_, _, resolved_failure := resolve_entry(data, handle, .Activate)
	if resolved_failure.code != .None do return false, resolved_failure
	previous := data.visible
	if previous.kind == .Primary_View && previous.entry == handle do return true, {}
	if previous.kind == .Primary_View {
		outgoing_slot, _, outgoing_failure := resolve_entry(data, previous.entry, .Activate)
		if outgoing_failure.code != .None do return false, outgoing_failure
		transient, transient_ok, transient_failure := editor_view.transient_state(
			&data.view_registry,
			outgoing_slot.owner.primary_view,
		)
		if !transient_ok {
			failure = session_failure(data, .Activate, .View_Failure)
			failure.view_failure = transient_failure
			return false, failure
		}
		if transient.active_preparation || transient.search || transient.query_replacement {
			failure = session_failure(data, .Activate, .Busy)
			failure.entry = previous.entry
			return false, failure
		}
	}
	if data.next_activation == Activation_Sequence(0) {
		return false, session_failure(data, .Activate, .Activation_Limit)
	}
	return true, {}
}

/* session_activate atomically selects one primary view and moves its entry to MRU head. */
session_activate :: proc(
	session: ^Session,
	handle: Entry_Handle,
) -> (result: Activation_Result, ok: bool, failure: Failure_Context) {
	validated, validation_failure := session_activation_validate(session, handle)
	if !validated do return {}, false, validation_failure
	data := session_data(session)
	slot, slot_index, _ := resolve_entry(data, handle, .Activate)
	previous := data.visible
	if previous.kind == .Primary_View && previous.entry == handle {
		session_project_focus_path(data, slot.owner.normalized_path)
		return Activation_Result {
			entry = handle,
			previous = previous,
			visible = previous,
			sequence = slot.activation_sequence,
			changed = false,
		}, true, {}
	}
	mru_unlink(data, slot_index)
	mru_link_front(data, slot_index)
	slot.activation_sequence = data.next_activation
	data.next_activation = Activation_Sequence(u64(data.next_activation) + 1)
	data.visible = visible_from_slot(data, slot_index)
	session_project_focus_path(data, slot.owner.normalized_path)
	assert(session_validate(data))
	return Activation_Result {
		entry = handle,
		previous = previous,
		visible = data.visible,
		sequence = slot.activation_sequence,
		changed = true,
	}, true, {}
}

@(private)
session_project_focus_path :: proc(data: ^Session_Data, path: string) {
	if data == nil || data.active_workspace.generation == 0 || len(path) == 0 {
		return
	}
	best_length := -1
	best_project: project.Project_Handle
	for root in data.roots {
		if root.kind != .Project || len(root.path) == 0 || !strings.has_prefix(path, root.path) {
			continue
		}
		if (len(path) == len(root.path) || root.path == "/" || path[len(root.path)] == '/') &&
		   len(root.path) > best_length {
			best_length = len(root.path)
			best_project = root.project
		}
	}
	if best_length >= 0 do data.active_project = best_project
}

/*
session_entry_detach removes one complete graph from every live index and MRU link.
All allocation occurs before the no-fail registry mutation; cleanup remains explicit.
*/
session_entry_detach :: proc(
	session: ^Session,
	handle: Entry_Handle,
	detached: ^Detached_Entry,
) -> (result: Detachment_Result, ok: bool, failure: Failure_Context) {
	assert(detached != nil)
	if detached.state != nil {
		return {}, false, Failure_Context{code = .Invalid_Reservation, operation = .Detach}
	}
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Detach}
	}
	_, _, resolved_failure := resolve_entry(data, handle, .Detach)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	state, state_error := new(Detached_Entry_State, data.allocator)
	if state_error != nil {
		return {}, false, session_failure(data, .Prepare_Detach, .Persistent_Memory_Limit)
	}
	result, ok, failure = session_entry_detach_with_state(data, handle, state, detached)
	if !ok {
		free(state, data.allocator)
	}
	return
}

@(private)
session_entry_detach_with_state :: proc(
	data: ^Session_Data,
	handle: Entry_Handle,
	state: ^Detached_Entry_State,
	detached: ^Detached_Entry,
) -> (result: Detachment_Result, ok: bool, failure: Failure_Context) {
	assert(data != nil && state != nil && detached != nil && detached.state == nil)
	slot, slot_index, resolved_failure := resolve_entry(data, handle, .Detach)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	owner := slot.owner
	was_visible := data.visible.kind == .Primary_View && data.visible.entry == handle
	result = Detachment_Result {
		entry = handle,
		selection_label = string(owner.selection_label),
		was_visible = was_visible,
		detached_graphs = 1,
		detached_bytes = retained_reservation_bytes(owner.reservation),
	}

	delete_key(&data.label_index, string(owner.selection_label))
	if len(owner.normalized_path) > 0 {
		delete_key(&data.path_index, string(owner.normalized_path))
	}
	mru_unlink(data, slot_index)
	if was_visible {
		if data.mru_head != INVALID_SLOT {
			data.visible = visible_from_slot(data, data.mru_head)
		} else {
			data.visible = {}
		}
	}
	result.successor = data.visible
	slot.owner = nil
	slot.entry_id = Entry_ID(0)
	slot.activation_sequence = Activation_Sequence(0)
	slot.previous_mru = INVALID_SLOT
	slot.next_mru = INVALID_SLOT
	slot.live = false
	data.usage.live_buffers -= 1
	data.usage.live_primary_views -= 1
	data.usage.activation_entries -= 1
	if owner.document_live {
		data.usage.live_documents -= 1
	}
	data.usage.detached_cleanup_entries += 1
	data.detached_entries += 1
	data.usage.registry_bytes += u64(size_of(Detached_Entry_State))
	state.session = data
	state.owner = owner
	state.result = result
	detached.state = state
	assert(session_validate(data))
	return result, true, {}
}

/* detached_entry_cleanup performs bounded reverse-order graph release without freeing copied metadata. */
detached_entry_cleanup :: proc(
	detached: ^Detached_Entry,
) -> (progress: Cleanup_Progress, ok: bool, failure: Failure_Context) {
	state := detached_entry_state(detached)
	if state == nil || state.session == nil || state.owner == nil {
		return {}, false, Failure_Context{code = .Invalid_Reservation, operation = .Cleanup}
	}
	cleaned, cleanup_failure := owner_cleanup(state.session, state.owner, .Cleanup)
	if !cleaned {
		return Cleanup_Progress {
			remaining_entries = 1,
			first_failure = cleanup_failure,
		}, false, cleanup_failure
	}
	return Cleanup_Progress {
		processed_entries = 1,
		remaining_entries = 0,
		released_bytes = state.result.detached_bytes,
		complete = true,
	}, true, {}
}

/* detached_entry_release frees retained copied metadata after cleanup completed. */
detached_entry_release :: proc(
	detached: ^Detached_Entry,
) -> (ok: bool, failure: Failure_Context) {
	state := detached_entry_state(detached)
	if state == nil || state.session == nil || state.owner == nil {
		return false, Failure_Context{code = .Invalid_Reservation, operation = .Cleanup}
	}
	owner := state.owner
	if owner.primary_view_live || owner.document_live || owner.history_live || owner.buffer_live {
		return false, session_failure(state.session, .Cleanup, .Retained_Cleanup)
	}
	data := state.session
	usage_release_retained(data, owner.reservation)
	assert(data.usage.detached_cleanup_entries > 0 && data.detached_entries > 0)
	data.usage.detached_cleanup_entries -= 1
	data.detached_entries -= 1
	assert(data.usage.registry_bytes >= u64(size_of(Detached_Entry_State)))
	data.usage.registry_bytes -= u64(size_of(Detached_Entry_State))
	owner_release_storage(data, owner)
	detached.state = nil
	free(state, data.allocator)
	assert(session_validate(data))
	return true, {}
}

@(private)
mru_link_front :: proc(data: ^Session_Data, slot_index: int) {
	slot := &data.slots[slot_index]
	slot.previous_mru = INVALID_SLOT
	slot.next_mru = data.mru_head
	if data.mru_head != INVALID_SLOT {
		data.slots[data.mru_head].previous_mru = slot_index
	} else {
		data.mru_tail = slot_index
	}
	data.mru_head = slot_index
}

@(private)
mru_unlink :: proc(data: ^Session_Data, slot_index: int) {
	slot := &data.slots[slot_index]
	if slot.previous_mru != INVALID_SLOT {
		data.slots[slot.previous_mru].next_mru = slot.next_mru
	} else {
		data.mru_head = slot.next_mru
	}
	if slot.next_mru != INVALID_SLOT {
		data.slots[slot.next_mru].previous_mru = slot.previous_mru
	} else {
		data.mru_tail = slot.previous_mru
	}
	slot.previous_mru = INVALID_SLOT
	slot.next_mru = INVALID_SLOT
}

@(private)
owner_cleanup :: proc(
	data: ^Session_Data,
	owner: ^Entry_Owner,
	operation: Operation,
) -> (ok: bool, failure: Failure_Context) {
	if owner.primary_view_live {
		closed, view_failure := editor_view.close(&data.view_registry, &owner.primary_view)
		if !closed {
			failure = session_failure(data, operation, .View_Failure)
			failure.view_failure = view_failure
			return false, failure
		}
		owner.primary_view_live = false
	}
	if owner.document_live {
		closed, document_failure := document.document_close(&owner.document)
		if !closed {
			failure = session_failure(data, operation, .Document_Failure)
			failure.document_failure = document_failure
			return false, failure
		}
		owner.document_live = false
	}
	if owner.history_live {
		closed, history_failure := history.store_close(&owner.history_store)
		if !closed {
			failure = session_failure(data, operation, .History_Failure)
			failure.history_failure = history_failure
			return false, failure
		}
		owner.history_live = false
	}
	if owner.buffer_live {
		closed, editor_failure := editor.buffer_close(&owner.buffer)
		if !closed {
			failure = session_failure(data, operation, .Editor_Failure)
			failure.editor_failure = editor_failure
			return false, failure
		}
		owner.buffer_live = false
	}
	return true, {}
}

@(private)
usage_release_retained :: proc(data: ^Session_Data, reservation: Graph_Reservation) {
	assert(data.usage.canonical_text_bytes >= reservation.canonical_text_bytes)
	assert(data.usage.retained_label_bytes >= reservation.label_bytes)
	assert(data.usage.view_anchors >= reservation.view_anchors)
	assert(data.usage.view_context_bytes >= reservation.view_context_bytes)
	assert(data.usage.history_bytes >= reservation.history_bytes)
	assert(data.usage.registry_bytes >= reservation.registry_bytes)
	data.usage.canonical_text_bytes -= reservation.canonical_text_bytes
	data.usage.retained_label_bytes -= reservation.label_bytes
	data.usage.view_anchors -= reservation.view_anchors
	data.usage.view_context_bytes -= reservation.view_context_bytes
	data.usage.history_bytes -= reservation.history_bytes
	data.usage.registry_bytes -= reservation.registry_bytes
}

@(private)
retained_reservation_bytes :: proc(reservation: Graph_Reservation) -> u64 {
	return reservation.canonical_text_bytes + reservation.label_bytes +
	       reservation.view_context_bytes + reservation.history_bytes +
	       reservation.registry_bytes
}

@(private)
session_validate :: proc(data: ^Session_Data) -> bool {
	if data == nil || !session_handle_is_valid(data.handle) ||
	   !registry_handle_is_valid(data.registry) || data.registry.session != data.handle ||
	   data.usage.live_buffers > data.policy.live_buffers ||
	   data.usage.live_documents > data.policy.live_documents ||
	   data.usage.prepared_operations > data.policy.prepared_operations ||
	   data.usage.detached_cleanup_entries != data.detached_entries {
		return false
	}
	if !session_search_history_validate(data) {
		return false
	}
	if !project.registry_validate(&data.project_registry) {
		return false
	}
	project_usage, project_usage_ok := project.registry_usage(&data.project_registry)
	if !project_usage_ok || project_usage.registry_bytes != data.project_registry_bytes ||
	   data.usage.registry_bytes < data.project_registry_bytes + data.workspace_project_registry_bytes {
		return false
	}
	if project_usage.projects == 0 {
		if data.primary_project != (project.Project_Handle{}) {
			return false
		}
	} else {
		if !project.project_handle_is_valid(data.primary_project) ||
		   data.primary_project.owner != data.project_owner {
			return false
		}
		descriptor, described, _ := project.registry_project_descriptor(
			&data.project_registry,
			data.primary_project,
		)
		if !described || descriptor.handle != data.primary_project {
			return false
		}
	}
	workspace_registry_bytes: u64
	for &owner, index in data.workspace_projects {
		if owner.handle == (project.Project_Handle{}) || !project.registry_validate(&owner.registry) {
			return false
		}
		usage, usage_ok := project.registry_usage(&owner.registry)
		if !usage_ok || usage.projects != 1 || usage.registry_bytes != owner.registry_bytes {
			return false
		}
		descriptor, described, _ := project.registry_project_descriptor(&owner.registry, owner.handle)
		if !described || descriptor.handle != owner.handle {
			return false
		}
		for previous in data.workspace_projects[:index] {
			if previous.handle == owner.handle {
				return false
			}
		}
		workspace_registry_bytes += owner.registry_bytes
	}
	if workspace_registry_bytes != data.workspace_project_registry_bytes {
		return false
	}
	if data.active_project != (project.Project_Handle{}) &&
	   session_project_registry(data, data.active_project) == nil {
		return false
	}
	if !session_roots_validate(data) {
		return false
	}
	if data.active_workspace.generation != 0 {
		if data.active_workspace.root_set != data.root_generation ||
		   data.active_workspace.project_count < 1 ||
		   data.active_workspace.project_count != u32(len(data.roots)) ||
		   len(workspace_id_text(&data.active_workspace.id)) == 0 ||
		   len(workspace_name_text(&data.active_workspace.name)) == 0 {
			return false
		}
		for root in data.roots {
			if root.kind != .Project {
				return false
			}
		}
	}
	live_count: u32
	reserved_count: u32
	live_documents: u32
	reserved_documents: u32
	indexed_labels: u32
	indexed_paths: u32
	for &slot, slot_index in data.slots {
		if slot.live {
			if slot.reserved || slot.owner == nil || slot.entry_id == Entry_ID(0) ||
			   slot.generation == 0 ||
			   data.label_index[string(slot.owner.selection_label)] != slot_index + 1 ||
			   !entry_owner_kind_validate(slot.owner) {
				return false
			}
			live_count += 1
			indexed_labels += 1
			if slot.owner.document_live {
				live_documents += 1
			}
			if len(slot.owner.normalized_path) > 0 {
				if data.path_index[string(slot.owner.normalized_path)] != slot_index + 1 {
					return false
				}
				indexed_paths += 1
			}
		} else if slot.reserved {
			if slot.owner == nil || slot.entry_id == Entry_ID(0) || slot.generation == 0 ||
			   data.label_index[string(slot.owner.selection_label)] != slot_index + 1 ||
			   !entry_owner_kind_validate(slot.owner) {
				return false
			}
			reserved_count += 1
			indexed_labels += 1
			if slot.owner.document_live {
				reserved_documents += 1
			}
			if len(slot.owner.normalized_path) > 0 {
				if data.path_index[string(slot.owner.normalized_path)] != slot_index + 1 {
					return false
				}
				indexed_paths += 1
			}
		} else if slot.owner != nil || slot.entry_id != Entry_ID(0) ||
		          slot.previous_mru != INVALID_SLOT || slot.next_mru != INVALID_SLOT {
			return false
		}
	}
	if live_count != data.usage.live_buffers ||
	   live_documents != data.usage.live_documents ||
	   reserved_count != data.usage.prepared_operations ||
	   reserved_documents != data.reserved_documents ||
	   indexed_labels != u32(len(data.label_index)) ||
	   indexed_paths != u32(len(data.path_index)) {
		return false
	}

	seen: [MAX_LIVE_BUFFERS]bool
	mru_count: u32
	previous := INVALID_SLOT
	for slot_index := data.mru_head; slot_index != INVALID_SLOT; slot_index = data.slots[slot_index].next_mru {
		if slot_index < 0 || slot_index >= len(data.slots) || seen[slot_index] {
			return false
		}
		slot := &data.slots[slot_index]
		if !slot.live || slot.previous_mru != previous {
			return false
		}
		seen[slot_index] = true
		previous = slot_index
		mru_count += 1
	}
	if mru_count != live_count || previous != data.mru_tail {
		return false
	}
	if live_count == 0 {
		return data.mru_head == INVALID_SLOT && data.mru_tail == INVALID_SLOT &&
		       (data.visible.kind == .None || data.visible.kind == .UI_Root) &&
		       visible_target_is_valid(data.visible)
	}
	if data.mru_head == INVALID_SLOT || data.mru_tail == INVALID_SLOT ||
	   !visible_target_is_valid(data.visible) {
		return false
	}
	return data.visible.kind == .UI_Root ||
	       (data.visible.kind == .Primary_View &&
	        data.visible.entry == entry_handle(data, data.mru_head))
}

@(private)
entry_owner_kind_validate :: proc(owner: ^Entry_Owner) -> bool {
	if owner == nil {
		return false
	}
	buffer_stats, buffer_ok, _ := editor.buffer_stats(&owner.buffer)
	_, history_ok, _ := history.store_stats(&owner.history_store)
	if !buffer_ok || !history_ok {
		return false
	}
	switch owner.kind {
	case .Text:
		return buffer_stats.kind == .Text &&
		       owner.terminal_ref == (Terminal_Session_Ref{}) &&
		       owner.terminal_lifecycle == .Invalid &&
		       len(owner.terminal_context) == 0
	case .Terminal:
		return buffer_stats.kind == .Terminal_Projection &&
		       terminal_session_ref_is_valid(owner.terminal_ref) &&
		       (owner.terminal_lifecycle == .Running || owner.terminal_lifecycle == .Exited ||
		        owner.terminal_lifecycle == .Failed) &&
		       owner.association == .Unassociated && !owner.document_live &&
		       len(owner.normalized_path) == 0 && len(owner.terminal_context) > 0 &&
		       u64(len(owner.terminal_context)) <= MAX_TERMINAL_WORKING_CONTEXT_BYTES &&
		       utf8.valid_string(owner.terminal_context) &&
		       strings.index_byte(owner.terminal_context, 0) < 0
	case .Invalid:
		return false
	}
	return false
}
