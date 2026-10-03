// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../editor"
import "../history"
import "core:strings"
import "core:unicode/utf8"

/*
session_create_terminal_buffer publishes one editor identity over a copied terminal
projection. It does not acquire the terminal registry, PTY, or emulator owner.
*/
session_create_terminal_buffer :: proc(
	session: ^Session,
	request: Create_Terminal_Buffer_Request,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Create_Terminal_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	prepare_request := Entry_Prepare_Request {
		session = request.session,
		kind = .Terminal,
		selection_label = request.name,
		association = .Unassociated,
		terminal = request.terminal,
	}
	metadata_ok, metadata_failure := entry_metadata_validate(data, prepare_request)
	if !metadata_ok {
		metadata_failure.operation = .Create_Terminal_Buffer
		return {}, false, metadata_failure
	}

	buffer_id, store_id, identities_ok, identity_failure :=
		session_next_buffer_identities(data, .Create_Terminal_Buffer)
	if !identities_ok {
		return {}, false, identity_failure
	}
	buffer: editor.Buffer
	history_store: history.Store
	resources := Entry_Resources {
		buffer = &buffer,
		history_store = &history_store,
	}
	buffer_ok, buffer_failure := editor.buffer_init(
		resources.buffer,
		buffer_id,
		request.copied_projection,
		editor.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.configuration.buffer_limits,
		.Terminal_Projection,
	)
	if !buffer_ok {
		failure = session_failure(data, .Create_Terminal_Buffer, .Editor_Failure)
		failure.editor_failure = buffer_failure
		return {}, false, failure
	}
	history_ok, history_failure := history.store_init(
		resources.history_store,
		store_id,
		buffer_id,
		editor.Revision(0),
		history.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.configuration.history_policy,
	)
	if !history_ok {
		closed, _ := editor.buffer_close(resources.buffer)
		assert(closed)
		failure = session_failure(data, .Create_Terminal_Buffer, .History_Failure)
		failure.history_failure = history_failure
		return {}, false, failure
	}

	prepare_request.resources = resources
	prepare_request.view_config = request.configuration.view_config
	result, ok, failure = session_publish_initialized_graph(
		session,
		prepare_request,
		.Create_Terminal_Buffer,
	)
	return
}

/* session_terminal_buffer_state copies one exact terminal-backed entry state. */
session_terminal_buffer_state :: proc(
	session: ^Session,
	entry: Entry_Handle,
) -> (state: Terminal_Buffer_State, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	slot, _, resolved_failure := resolve_entry(data, entry, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if slot.owner.kind != .Terminal {
		failure = session_failure(data, .Inspect, .Invalid_Terminal)
		failure.entry = entry
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(&slot.owner.buffer)
	if !stats_ok {
		failure = session_failure(data, .Inspect, .Editor_Failure)
		failure.entry = entry
		failure.editor_failure = stats_failure
		return {}, false, failure
	}
	return terminal_buffer_state_copy(slot.owner, entry, stats.revision), true, {}
}

/*
session_refresh_terminal_buffer atomically advances copied projection and lifecycle.
The terminal source remains externally owned and is matched by exact generation.
*/
session_refresh_terminal_buffer :: proc(
	session: ^Session,
	request: Terminal_Buffer_Update_Request,
) -> (state: Terminal_Buffer_State, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Refresh_Terminal_Buffer}
	}
	slot, _, resolved_failure := resolve_entry(data, request.entry, .Refresh_Terminal_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	owner := slot.owner
	if owner.kind != .Terminal || !terminal_session_ref_is_valid(request.terminal) {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Invalid_Terminal)
		failure.entry = request.entry
		failure.terminal = request.terminal
		return {}, false, failure
	}
	if owner.terminal_ref != request.terminal {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Stale_Terminal)
		failure.entry = request.entry
		failure.terminal = request.terminal
		return {}, false, failure
	}
	if !terminal_lifecycle_transition_valid(owner.terminal_lifecycle, request.lifecycle) {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Invalid_Terminal_Transition)
		failure.entry = request.entry
		failure.terminal = request.terminal
		return {}, false, failure
	}
	before, before_ok, before_failure := editor.buffer_stats(&owner.buffer)
	if !before_ok {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Editor_Failure)
		failure.entry = request.entry
		failure.editor_failure = before_failure
		return {}, false, failure
	}
	projected_text := data.usage.canonical_text_bytes - before.text_bytes +
	                  u64(len(request.copied_projection))
	if projected_text > data.policy.aggregate_text_bytes {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Aggregate_Text_Limit)
		failure.entry = request.entry
		failure.maximum = data.policy.aggregate_text_bytes
		failure.actual = projected_text
		return {}, false, failure
	}
	if before.revision == editor.Revision(max(u64)) {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Editor_Failure)
		failure.entry = request.entry
		failure.editor_failure = editor.Failure_Context {
			code = .Work_Limit,
			buffer_id = before.buffer_id,
			revision = before.revision,
		}
		return {}, false, failure
	}
	next_revision := editor.Revision(u64(before.revision) + 1)
	reservation: history.Reservation
	reserved, reserve_failure := history.revision_reserve(
		&owner.history_store,
		&reservation,
		before.revision,
		next_revision,
	)
	if !reserved {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .History_Failure)
		failure.entry = request.entry
		failure.history_failure = reserve_failure
		return {}, false, failure
	}
	defer if history.reservation_is_valid(&reservation) {
		aborted, _ := history.reservation_abort(&reservation)
		assert(aborted)
	}
	published_revision, published, publish_failure := editor.buffer_projection_replace(
		&owner.buffer,
		request.copied_projection,
		data.temporary_allocator,
	)
	if !published {
		failure = session_failure(data, .Refresh_Terminal_Buffer, .Editor_Failure)
		failure.entry = request.entry
		failure.editor_failure = publish_failure
		return {}, false, failure
	}
	assert(published_revision == next_revision)
	history.reservation_commit_reserved(&reservation, published_revision)
	owner.terminal_lifecycle = request.lifecycle
	owner.reservation.canonical_text_bytes = u64(len(request.copied_projection))
	data.usage.canonical_text_bytes = projected_text
	return terminal_buffer_state_copy(owner, request.entry, published_revision), true, {}
}

/* session_rename_terminal_buffer changes one checked editor-visible terminal label. */
session_rename_terminal_buffer :: proc(
	session: ^Session,
	request: Rename_Terminal_Buffer_Request,
) -> (label: Closure_Label, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Rename_Terminal_Buffer}
	}
	slot, slot_index, resolved_failure := resolve_entry(data, request.entry, .Rename_Terminal_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	owner := slot.owner
	if owner.kind != .Terminal || owner.terminal_ref != request.terminal {
		code := Failure_Code.Invalid_Terminal
		if owner.kind == .Terminal && terminal_session_ref_is_valid(request.terminal) {
			code = .Stale_Terminal
		}
		failure = session_failure(data, .Rename_Terminal_Buffer, code)
		failure.entry = request.entry
		failure.terminal = request.terminal
		return {}, false, failure
	}
	if len(request.name) == 0 {
		return {}, false, session_failure(data, .Rename_Terminal_Buffer, .Invalid_Name)
	}
	if !utf8.valid_string(request.name) || strings.index_byte(request.name, 0) >= 0 {
		return {}, false, session_failure(data, .Rename_Terminal_Buffer, .Malformed_Label)
	}
	if u64(len(request.name)) > data.policy.name_bytes {
		failure = session_failure(data, .Rename_Terminal_Buffer, .Label_Limit)
		failure.maximum = data.policy.name_bytes
		failure.actual = u64(len(request.name))
		return {}, false, failure
	}
	if request.name == owner.selection_label {
		return closure_label_copy(owner.selection_label), true, {}
	}
	if encoded := data.label_index[request.name]; encoded != 0 && encoded != slot_index + 1 {
		return {}, false, session_failure(data, .Rename_Terminal_Buffer, .Name_Collision)
	}
	old_bytes := u64(len(owner.selection_label))
	new_bytes := u64(len(request.name))
	projected_labels := data.usage.retained_label_bytes - old_bytes + new_bytes
	if projected_labels > data.policy.retained_label_bytes {
		failure = session_failure(data, .Rename_Terminal_Buffer, .Retained_Label_Limit)
		failure.maximum = data.policy.retained_label_bytes
		failure.actual = projected_labels
		return {}, false, failure
	}
	name, allocation_error := strings.clone(request.name, data.allocator)
	if allocation_error != nil {
		return {}, false, session_failure(data, .Rename_Terminal_Buffer, .Persistent_Memory_Limit)
	}
	delete_key(&data.label_index, string(owner.selection_label))
	delete(owner.selection_label, data.allocator)
	owner.selection_label = name
	data.label_index[string(owner.selection_label)] = slot_index + 1
	owner.reservation.label_bytes = owner.reservation.label_bytes - old_bytes + new_bytes
	owner.reservation.registry_bytes = owner.reservation.registry_bytes - old_bytes + new_bytes
	data.usage.retained_label_bytes = projected_labels
	data.usage.registry_bytes = data.usage.registry_bytes - old_bytes + new_bytes
	return closure_label_copy(owner.selection_label), true, {}
}

@(private)
terminal_lifecycle_transition_valid :: proc(from, to: Terminal_Lifecycle) -> bool {
	switch from {
	case .Running:
		return to == .Running || to == .Exited || to == .Failed
	case .Exited:
		return to == .Exited
	case .Failed:
		return to == .Failed
	case .Invalid:
		return false
	}
	return false
}

@(private)
terminal_buffer_state_copy :: proc(
	owner: ^Entry_Owner,
	entry: Entry_Handle,
	revision: editor.Revision,
) -> Terminal_Buffer_State {
	working_ctx: Terminal_Working_Context
	assert(len(owner.terminal_context) <= len(working_ctx.bytes))
	copy(working_ctx.bytes[:], transmute([]u8)owner.terminal_context)
	working_ctx.length = u16(len(owner.terminal_context))
	return Terminal_Buffer_State {
		entry = entry,
		terminal = owner.terminal_ref,
		lifecycle = owner.terminal_lifecycle,
		projection_revision = revision,
		working_context = working_ctx,
	}
}
