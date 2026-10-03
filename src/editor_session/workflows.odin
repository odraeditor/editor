// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import editor_view "../view"
import "core:strings"

/*
session_create_buffer initializes and publishes one complete empty unassociated
buffer graph. Expected failure preserves every previously live entry and target.
*/
session_create_buffer :: proc(
	session: ^Session,
	request: Create_Buffer_Request,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Create_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	metadata_ok, metadata_failure := entry_metadata_validate(
		data,
		Entry_Prepare_Request {
			session = request.session,
			kind = .Text,
			selection_label = request.name,
			association = .Unassociated,
		},
	)
	if !metadata_ok {
		metadata_failure.operation = .Create_Buffer
		return {}, false, metadata_failure
	}

	buffer_id, store_id, identities_ok, identity_failure :=
		session_next_buffer_identities(data, .Create_Buffer)
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
		request.initial_contents,
		editor.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.configuration.buffer_limits,
	)
	if !buffer_ok {
		failure = session_failure(data, .Create_Buffer, .Editor_Failure)
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
		failure = session_failure(data, .Create_Buffer, .History_Failure)
		failure.history_failure = history_failure
		return {}, false, failure
	}

	result, ok, failure = session_publish_initialized_graph(
		session,
		Entry_Prepare_Request {
			session = request.session,
			kind = .Text,
			selection_label = request.name,
			association = .Unassociated,
			resources = resources,
			view_config = request.configuration.view_config,
		},
		.Create_Buffer,
	)
	return
}

/*
session_open_path reuses an admitted normalized target without I/O or privately
opens, initializes, and publishes one complete document-backed buffer graph.
*/
session_open_path :: proc(
	session: ^Session,
	request: Open_Path_Request,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, request.session, .Open_Path)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if request.encoding != .UTF8 {
		failure = session_failure(data, .Open_Path, .Document_Failure)
		failure.document_failure = document.Failure_Context {
			code = .Invalid_Encoding,
			operation = .Normalize_Path,
		}
		return {}, false, failure
	}
	normalized: document.Normalized_Path
	normalized_ok, normalized_failure := document.path_normalize(
		request.path,
		&normalized,
		data.temporary_allocator,
		request.configuration.document_limits,
	)
	if !normalized_ok {
		failure = session_failure(data, .Open_Path, .Document_Failure)
		failure.document_failure = normalized_failure
		return {}, false, failure
	}
	path := document.normalized_path_text(&normalized)
	encoded_path := data.path_index[path]
	if encoded_path != 0 {
		slot_index := encoded_path - 1
		slot := &data.slots[slot_index]
		if !slot.live {
			return {}, false, session_failure(data, .Open_Path, .Path_Collision)
		}
		entry := entry_handle(data, slot_index)
		activation, activated, activation_failure := session_activate(session, entry)
		if !activated {
			activation_failure.operation = .Open_Path
			return {}, false, activation_failure
		}
		return Admission_Result {
			outcome = .Reused,
			entry = entry,
			visible = activation.visible,
			usage = data.usage,
		}, true, {}
	}
	if data.label_index[path] != 0 {
		return {}, false, session_failure(data, .Open_Path, .Name_Collision)
	}

	buffer_id, store_id, document_id, identities_ok, identity_failure :=
		session_next_document_identities(data, .Open_Path)
	if !identities_ok {
		return {}, false, identity_failure
	}
	prepared_open: document.Prepared_Open
	opened, open_failure := document.open_prepare(
		&prepared_open,
		document.Open_Request {
			document_id = document_id,
			buffer_id = buffer_id,
			has_path = true,
			path = path,
			encoding = request.encoding,
		},
		document.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.configuration.document_limits,
	)
	if !opened {
		failure = session_failure(data, .Open_Path, .Document_Failure)
		failure.document_failure = open_failure
		return {}, false, failure
	}
	open_view, viewed, view_failure := document.prepared_open_view(&prepared_open)
	if !viewed {
		aborted, _ := document.prepared_open_abort(&prepared_open)
		assert(aborted)
		failure = session_failure(data, .Open_Path, .Document_Failure)
		failure.document_failure = view_failure
		return {}, false, failure
	}
	assert(open_view.path == path)

	buffer: editor.Buffer
	buffer_ok, buffer_failure := editor.buffer_init(
		&buffer,
		buffer_id,
		open_view.contents,
		editor.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.configuration.buffer_limits,
	)
	if !buffer_ok {
		aborted, _ := document.prepared_open_abort(&prepared_open)
		assert(aborted)
		failure = session_failure(data, .Open_Path, .Editor_Failure)
		failure.editor_failure = buffer_failure
		return {}, false, failure
	}
	history_store: history.Store
	history_ok, history_failure := history.store_init(
		&history_store,
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
		closed, _ := editor.buffer_close(&buffer)
		assert(closed)
		aborted, _ := document.prepared_open_abort(&prepared_open)
		assert(aborted)
		failure = session_failure(data, .Open_Path, .History_Failure)
		failure.history_failure = history_failure
		return {}, false, failure
	}
	document_owner: document.Document
	committed, commit_failure := document.prepared_open_commit(
		&prepared_open,
		&document_owner,
		editor.Revision(0),
	)
	if !committed {
		aborted, _ := document.prepared_open_abort(&prepared_open)
		assert(aborted)
		history_closed, _ := history.store_close(&history_store)
		buffer_closed, _ := editor.buffer_close(&buffer)
		assert(history_closed && buffer_closed)
		failure = session_failure(data, .Open_Path, .Document_Failure)
		failure.document_failure = commit_failure
		return {}, false, failure
	}

	result, ok, failure = session_publish_initialized_graph(
		session,
		Entry_Prepare_Request {
			session = request.session,
			kind = .Text,
			selection_label = path,
			normalized_path = path,
			association = .Document,
			resources = Entry_Resources {
				buffer = &buffer,
				history_store = &history_store,
				document = &document_owner,
				has_document = true,
			},
			view_config = request.configuration.view_config,
		},
		.Open_Path,
	)
	return
}

/*
session_close_buffer checks transient ownership and dirty-state authority before
detaching, cleaning, and releasing one complete entry graph.
*/
session_close_buffer :: proc(
	session: ^Session,
	request: Close_Buffer_Request,
) -> (result: Closure_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Close_Buffer}
	}
	metadata, assessed, assess_failure := session_assess_buffer_close(session, request.entry)
	if !assessed {
		return {}, false, assess_failure
	}
	if metadata.modified && request.authority != .Discard_Modified {
		return metadata, true, {}
	}

	detached: Detached_Entry
	detachment, detached_ok, detach_failure := session_entry_detach(
		session,
		request.entry,
		&detached,
	)
	if !detached_ok {
		detach_failure.operation = .Close_Buffer
		return {}, false, detach_failure
	}
	cleanup, cleaned, cleanup_failure := detached_entry_cleanup(&detached)
	if !cleaned {
		cleanup_failure.operation = .Close_Buffer
		return {}, false, cleanup_failure
	}
	released, release_failure := detached_entry_release(&detached)
	if !released {
		release_failure.operation = .Close_Buffer
		return {}, false, release_failure
	}
	metadata.outcome = .Closed
	metadata.was_visible = detachment.was_visible
	metadata.successor = detachment.successor
	metadata.last_buffer = detachment.successor.kind == .None
	metadata.usage = data.usage
	metadata.cleanup = cleanup
	return metadata, true, {}
}

/*
session_close_buffer_set validates every dirty authority and allocates every
detachment record before one no-fail set mutation and deterministic cleanup.
*/
session_close_buffer_set :: proc(
	session: ^Session,
	requests: []Close_Buffer_Request,
) -> (result: Close_Buffer_Set_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Close_Buffer}
	}
	if len(requests) == 0 || len(requests) > int(data.policy.detach_participants) {
		failure = session_failure(data, .Close_Buffer, .Detach_Limit)
		failure.maximum = u64(data.policy.detach_participants)
		failure.actual = u64(len(requests))
		return {}, false, failure
	}
	for request, index in requests {
		for previous in 0 ..< index {
			if requests[previous].entry == request.entry {
				failure = session_failure(data, .Close_Buffer, .Invalid_Entry)
				failure.entry = request.entry
				return {}, false, failure
			}
		}
		assessment, assessed, assess_failure := session_assess_buffer_close(session, request.entry)
		if !assessed {
			return {}, false, assess_failure
		}
		if assessment.modified && request.authority != .Discard_Modified {
			failure = session_failure(data, .Close_Buffer, .Cancelled)
			failure.entry = request.entry
			return {}, false, failure
		}
	}
	states, states_error := make([]^Detached_Entry_State, len(requests), data.temporary_allocator)
	if states_error != nil {
		return {}, false, session_failure(data, .Prepare_Detach, .Temporary_Memory_Limit)
	}
	defer delete(states, data.temporary_allocator)
	detached, detached_error := make([]Detached_Entry, len(requests), data.temporary_allocator)
	if detached_error != nil {
		return {}, false, session_failure(data, .Prepare_Detach, .Temporary_Memory_Limit)
	}
	defer delete(detached, data.temporary_allocator)
	for _, index in requests {
		state, state_error := new(Detached_Entry_State, data.allocator)
		if state_error != nil {
			for previous in 0 ..< index {
				free(states[previous], data.allocator)
			}
			return {}, false, session_failure(data, .Prepare_Detach, .Persistent_Memory_Limit)
		}
		states[index] = state
	}
	for request, index in requests {
		_, detached_ok, detach_failure := session_entry_detach_with_state(
			data,
			request.entry,
			states[index],
			&detached[index],
		)
		assert(detached_ok && detach_failure.code == .None, "admitted set detachment must not fail")
	}
	for _, index in requests {
		_, cleaned, cleanup_failure := detached_entry_cleanup(&detached[index])
		if !cleaned {
			cleanup_failure.operation = .Close_Buffer
			return {}, false, cleanup_failure
		}
		released, release_failure := detached_entry_release(&detached[index])
		if !released {
			release_failure.operation = .Close_Buffer
			return {}, false, release_failure
		}
	}
	return Close_Buffer_Set_Result {
		closed_entries = u32(len(requests)),
		usage = data.usage,
	}, true, {}
}

/* session_assess_buffer_close checks one entry without mutating registry or owner state. */
session_assess_buffer_close :: proc(
	session: ^Session,
	entry: Entry_Handle,
) -> (result: Closure_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Close_Buffer}
	}
	slot, _, resolved_failure := resolve_entry(data, entry, .Close_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if slot.owner.kind == .Terminal {
		failure = session_failure(data, .Close_Buffer, .Terminal_Coordination_Required)
		failure.entry = entry
		failure.terminal = slot.owner.terminal_ref
		return {}, false, failure
	}
	return session_assess_buffer_close_resolved(data, slot, entry)
}

/* session_assess_terminal_buffer_close admits an exact externally coordinated terminal close. */
session_assess_terminal_buffer_close :: proc(
	session: ^Session,
	entry: Entry_Handle,
	terminal: Terminal_Session_Ref,
) -> (result: Closure_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Close_Buffer}
	}
	slot, _, resolved_failure := resolve_entry(data, entry, .Close_Buffer)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if slot.owner.kind != .Terminal || !terminal_session_ref_is_valid(terminal) {
		failure = session_failure(data, .Close_Buffer, .Invalid_Terminal)
		failure.entry = entry
		failure.terminal = terminal
		return {}, false, failure
	}
	if slot.owner.terminal_ref != terminal {
		failure = session_failure(data, .Close_Buffer, .Stale_Terminal)
		failure.entry = entry
		failure.terminal = terminal
		return {}, false, failure
	}
	return session_assess_buffer_close_resolved(data, slot, entry)
}

@(private)
session_assess_buffer_close_resolved :: proc(
	data: ^Session_Data,
	slot: ^Entry_Slot,
	entry: Entry_Handle,
) -> (result: Closure_Result, ok: bool, failure: Failure_Context) {
	transient, transient_ok, transient_failure := editor_view.transient_state(
		&data.view_registry,
		slot.owner.primary_view,
	)
	if !transient_ok {
		failure = session_failure(data, .Close_Buffer, .View_Failure)
		failure.entry = entry
		failure.view_failure = transient_failure
		return {}, false, failure
	}
	if transient.active_preparation || transient.search || transient.query_replacement {
		failure = session_failure(data, .Close_Buffer, .Busy)
		failure.entry = entry
		return {}, false, failure
	}
	if history_ready, history_failure := history.store_close_ready(&slot.owner.history_store); !history_ready {
		failure = session_failure(data, .Close_Buffer, .Busy)
		failure.entry = entry
		failure.history_failure = history_failure
		return {}, false, failure
	}

	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(&slot.owner.buffer)
	if !buffer_ok {
		failure = session_failure(data, .Close_Buffer, .Editor_Failure)
		failure.entry = entry
		failure.editor_failure = buffer_failure
		return {}, false, failure
	}
	modified := buffer_stats.revision != editor.Revision(0)
	if slot.owner.association == .Document {
		status, status_ok, status_failure := document.document_status(&slot.owner.document)
		if !status_ok {
			failure = session_failure(data, .Close_Buffer, .Document_Failure)
			failure.entry = entry
			failure.document_failure = status_failure
			return {}, false, failure
		}
		if status.persistence == .Saving {
			failure = session_failure(data, .Close_Buffer, .Busy)
			failure.entry = entry
			return {}, false, failure
		}
		modified = !status.has_saved_revision || status.saved_revision != buffer_stats.revision
	}

	result = closure_result_prepare(data, slot.owner, entry, modified)
	result.outcome = .Discard_Required if modified else .Ready
	return result, true, {}
}

/*
session_associate_and_save reserves registry identity before the first external
save, then publishes the document association and full-path indexes truthfully.
*/
session_associate_and_save :: proc(
	session: ^Session,
	request: Associate_Save_Request,
) -> (result: Associate_Save_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Associate_Path}
	}
	slot, slot_index, resolved_failure := resolve_entry(data, request.entry, .Associate_Path)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	owner := slot.owner
	if owner.kind == .Terminal {
		failure = session_failure(data, .Associate_Path, .Invalid_Terminal)
		failure.entry = request.entry
		failure.terminal = owner.terminal_ref
		return {}, false, failure
	}
	if owner.association != .Unassociated || len(owner.normalized_path) != 0 {
		return {}, false, session_failure(data, .Associate_Path, .Invalid_Path)
	}
	normalized: document.Normalized_Path
	normalized_ok, normalized_failure := document.path_normalize(
		request.path,
		&normalized,
		data.temporary_allocator,
		request.limits,
	)
	if !normalized_ok {
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = normalized_failure
		return {}, false, failure
	}
	path := document.normalized_path_text(&normalized)
	if data.path_index[path] != 0 {
		return {}, false, session_failure(data, .Associate_Path, .Path_Collision)
	}
	if data.label_index[path] != 0 {
		return {}, false, session_failure(data, .Associate_Path, .Name_Collision)
	}
	old_label_bytes := owner.reservation.label_bytes
	new_label_bytes := u64(len(path) * 2)
	projected_labels := data.usage.retained_label_bytes - old_label_bytes +
	                    new_label_bytes
	if projected_labels > data.policy.retained_label_bytes {
		failure = session_failure(data, .Associate_Path, .Retained_Label_Limit)
		failure.maximum = data.policy.retained_label_bytes
		failure.actual = projected_labels
		return {}, false, failure
	}
	needs_document := !owner.document_live
	if needs_document && data.usage.live_documents >= data.policy.live_documents {
		failure = session_failure(data, .Associate_Path, .Document_Limit)
		failure.maximum = u64(data.policy.live_documents)
		failure.actual = u64(data.usage.live_documents) + 1
		return {}, false, failure
	}

	label, label_error := strings.clone(path, data.allocator)
	if label_error != nil {
		return {}, false, session_failure(data, .Associate_Path, .Persistent_Memory_Limit)
	}
	normalized_path, path_error := strings.clone(path, data.allocator)
	if path_error != nil {
		delete(label, data.allocator)
		return {}, false, session_failure(data, .Associate_Path, .Persistent_Memory_Limit)
	}
	committed_document: document.Document
	document_owner := &owner.document
	if needs_document {
		created, create_failure := session_unassociated_document_init(
			data,
			owner,
			request.limits,
			&committed_document,
		)
		if !created {
			delete(normalized_path, data.allocator)
			delete(label, data.allocator)
			return {}, false, create_failure
		}
		document_owner = &committed_document
	}

	prepared: document.Prepared_Association
	prepared_ok, prepare_failure := document.document_association_prepare(
		document_owner,
		path,
		&prepared,
		document.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		request.limits,
	)
	if !prepared_ok {
		if needs_document {
			closed, _ := document.document_close(&committed_document)
			assert(closed)
		}
		delete(normalized_path, data.allocator)
		delete(label, data.allocator)
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = prepare_failure
		return {}, false, failure
	}
	save, saved, save_failure := document.prepared_association_publish(
		&prepared,
		&owner.buffer,
	)
	if save.publication == .Not_Published {
		if needs_document {
			closed, _ := document.document_close(&committed_document)
			assert(closed)
		}
		delete(normalized_path, data.allocator)
		delete(label, data.allocator)
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = save_failure
		return Associate_Save_Result{entry = request.entry, save = save}, false, failure
	}

	delete_key(&data.label_index, string(owner.selection_label))
	delete(owner.selection_label, data.allocator)
	owner.selection_label = label
	owner.normalized_path = normalized_path
	owner.association = .Document
	data.label_index[string(owner.selection_label)] = slot_index + 1
	data.path_index[string(owner.normalized_path)] = slot_index + 1
	data.usage.retained_label_bytes = projected_labels
	data.usage.registry_bytes = data.usage.registry_bytes - old_label_bytes +
	                            new_label_bytes
	owner.reservation.registry_bytes = owner.reservation.registry_bytes -
	                                   old_label_bytes + new_label_bytes
	owner.reservation.label_bytes = new_label_bytes
	if needs_document {
		owner.document = committed_document
		owner.document_live = true
		owner.reservation.documents = 1
		data.usage.live_documents += 1
		data.next_document_id = document.Document_ID(u64(data.next_document_id) + 1)
	}
	label_copy := closure_label_copy(owner.selection_label)
	result = Associate_Save_Result {
		entry = request.entry,
		selection_label = label_copy,
		save = save,
		usage = data.usage,
	}
	assert(session_validate(data))
	if !saved {
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = save_failure
		return result, false, failure
	}
	return result, true, {}
}

/*
session_write_entry_to_path saves one text entry to a selected path and makes
that path the entry's authoritative document identity.
*/
session_write_entry_to_path :: proc(
	session: ^Session,
	request: Associate_Save_Request,
) -> (result: Associate_Save_Result, ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Associate_Path}
	}
	slot, slot_index, resolved_failure := resolve_entry(data, request.entry, .Associate_Path)
	if resolved_failure.code != .None do return {}, false, resolved_failure
	owner := slot.owner
	if owner.kind == .Terminal {
		failure = session_failure(data, .Associate_Path, .Invalid_Terminal)
		failure.entry = request.entry
		return {}, false, failure
	}
	if owner.association == .Unassociated {
		return session_associate_and_save(session, request)
	}

	normalized: document.Normalized_Path
	normalized_ok, normalized_failure := document.path_normalize(
		request.path,
		&normalized,
		data.temporary_allocator,
		request.limits,
	)
	if !normalized_ok {
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = normalized_failure
		return {}, false, failure
	}
	path := document.normalized_path_text(&normalized)
	if path == owner.normalized_path {
		prepared: document.Prepared_Save
		prepared_ok, prepare_failure := document.save_prepare(&owner.document, &owner.buffer, &prepared)
		if !prepared_ok {
			failure = session_failure(data, .Associate_Path, .Document_Failure)
			failure.entry = request.entry
			failure.document_failure = prepare_failure
			return {}, false, failure
		}
		save, saved, save_failure := document.prepared_save_publish(&prepared)
		result = {entry = request.entry, selection_label = closure_label_copy(owner.selection_label), save = save, usage = data.usage}
		if !saved {
			failure = session_failure(data, .Associate_Path, .Document_Failure)
			failure.entry = request.entry
			failure.document_failure = save_failure
			return result, false, failure
		}
		return result, true, {}
	}
	if encoded := data.path_index[path]; encoded != 0 && encoded != slot_index + 1 {
		return {}, false, session_failure(data, .Associate_Path, .Path_Collision)
	}
	if encoded := data.label_index[path]; encoded != 0 && encoded != slot_index + 1 {
		return {}, false, session_failure(data, .Associate_Path, .Name_Collision)
	}
	old_label_bytes := owner.reservation.label_bytes
	new_label_bytes := u64(len(path) * 2)
	projected_labels := data.usage.retained_label_bytes - old_label_bytes + new_label_bytes
	if projected_labels > data.policy.retained_label_bytes {
		failure = session_failure(data, .Associate_Path, .Retained_Label_Limit)
		failure.maximum = data.policy.retained_label_bytes
		failure.actual = projected_labels
		return {}, false, failure
	}
	label, label_error := strings.clone(path, data.allocator)
	if label_error != nil do return {}, false, session_failure(data, .Associate_Path, .Persistent_Memory_Limit)
	normalized_path, path_error := strings.clone(path, data.allocator)
	if path_error != nil {
		delete(label, data.allocator)
		return {}, false, session_failure(data, .Associate_Path, .Persistent_Memory_Limit)
	}

	replacement: document.Document
	created, create_failure := session_unassociated_document_init(data, owner, request.limits, &replacement)
	if !created {
		delete(normalized_path, data.allocator)
		delete(label, data.allocator)
		return {}, false, create_failure
	}
	prepared: document.Prepared_Association
	prepared_ok, prepare_failure := document.document_association_prepare(
		&replacement,
		path,
		&prepared,
		document.Allocator_Set{persistent = data.allocator, temporary = data.temporary_allocator},
		request.limits,
	)
	if !prepared_ok {
		_, _ = document.document_close(&replacement)
		delete(normalized_path, data.allocator)
		delete(label, data.allocator)
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = prepare_failure
		return {}, false, failure
	}
	save, saved, save_failure := document.prepared_association_publish(&prepared, &owner.buffer)
	if save.publication == .Not_Published {
		_, _ = document.document_close(&replacement)
		delete(normalized_path, data.allocator)
		delete(label, data.allocator)
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = save_failure
		return {entry = request.entry, save = save}, false, failure
	}
	closed, close_failure := document.document_close(&owner.document)
	assert(closed && close_failure.code == .None)
	delete_key(&data.label_index, string(owner.selection_label))
	delete_key(&data.path_index, string(owner.normalized_path))
	delete(owner.selection_label, data.allocator)
	delete(owner.normalized_path, data.allocator)
	owner.selection_label = label
	owner.normalized_path = normalized_path
	owner.document = replacement
	data.label_index[string(owner.selection_label)] = slot_index + 1
	data.path_index[string(owner.normalized_path)] = slot_index + 1
	data.usage.retained_label_bytes = projected_labels
	data.usage.registry_bytes = data.usage.registry_bytes - old_label_bytes + new_label_bytes
	owner.reservation.registry_bytes = owner.reservation.registry_bytes - old_label_bytes + new_label_bytes
	owner.reservation.label_bytes = new_label_bytes
	data.next_document_id = document.Document_ID(u64(data.next_document_id) + 1)
	result = {
		entry = request.entry,
		selection_label = closure_label_copy(owner.selection_label),
		save = save,
		usage = data.usage,
	}
	assert(session_validate(data))
	if !saved {
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.entry = request.entry
		failure.document_failure = save_failure
		return result, false, failure
	}
	return result, true, {}
}

@(private)
session_unassociated_document_init :: proc(
	data: ^Session_Data,
	owner: ^Entry_Owner,
	limits: document.Limits,
	destination: ^document.Document,
) -> (ok: bool, failure: Failure_Context) {
	if data.next_document_id == document.Document_ID(0) {
		return false, session_failure(data, .Associate_Path, .Identity_Limit)
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(&owner.buffer)
	if !buffer_ok {
		failure = session_failure(data, .Associate_Path, .Editor_Failure)
		failure.editor_failure = buffer_failure
		return false, failure
	}
	prepared: document.Prepared_Open
	prepared_ok, prepare_failure := document.open_prepare(
		&prepared,
		document.Open_Request {
			document_id = data.next_document_id,
			buffer_id = buffer_stats.buffer_id,
			encoding = .UTF8,
		},
		document.Allocator_Set {
			persistent = data.allocator,
			temporary = data.temporary_allocator,
		},
		limits,
	)
	if !prepared_ok {
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.document_failure = prepare_failure
		return false, failure
	}
	committed, commit_failure := document.prepared_open_commit(
		&prepared,
		destination,
		buffer_stats.revision,
	)
	if !committed {
		aborted, _ := document.prepared_open_abort(&prepared)
		assert(aborted)
		failure = session_failure(data, .Associate_Path, .Document_Failure)
		failure.document_failure = commit_failure
		return false, failure
	}
	return true, {}
}

@(private)
closure_result_prepare :: proc(
	data: ^Session_Data,
	owner: ^Entry_Owner,
	entry: Entry_Handle,
	modified: bool,
) -> Closure_Result {
	return Closure_Result {
		graph = owner_graph(owner, entry),
		selection_label = closure_label_copy(owner.selection_label),
		association = owner.association,
		modified = modified,
		was_visible = data.visible.kind == .Primary_View && data.visible.entry == entry,
		successor = data.visible,
		last_buffer = data.usage.live_buffers == 1,
		usage = data.usage,
	}
}

@(private)
closure_label_copy :: proc(source: string) -> Closure_Label {
	label: Closure_Label
	assert(len(source) <= len(label.bytes))
	copy(label.bytes[:], transmute([]u8)source)
	label.length = u32(len(source))
	return label
}

@(private)
session_publish_initialized_graph :: proc(
	session: ^Session,
	request: Entry_Prepare_Request,
	operation: Operation,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	prepared: Prepared_Entry
	_, prepared_ok, prepare_failure := session_entry_prepare(session, request, &prepared)
	if !prepared_ok {
		workflow_resources_close(request.resources)
		prepare_failure.operation = operation
		return {}, false, prepare_failure
	}
	published: bool
	publish_failure: Failure_Context
	result, published, publish_failure = prepared_entry_publish(&prepared)
	if !published {
		aborted, _ := prepared_entry_abort(&prepared)
		assert(aborted)
		publish_failure.operation = operation
		return {}, false, publish_failure
	}
	return result, true, {}
}

@(private)
workflow_resources_close :: proc(resources: Entry_Resources) {
	if resources.has_document && resources.document != nil {
		closed, _ := document.document_close(resources.document)
		assert(closed)
	}
	if resources.history_store != nil && history.store_is_valid(resources.history_store) {
		closed, _ := history.store_close(resources.history_store)
		assert(closed)
	}
	if resources.buffer != nil && editor.buffer_is_live(resources.buffer) {
		closed, _ := editor.buffer_close(resources.buffer)
		assert(closed)
	}
}

@(private)
session_next_buffer_identities :: proc(
	data: ^Session_Data,
	operation: Operation,
) -> (buffer_id: editor.Buffer_ID, store_id: history.Store_ID, ok: bool, failure: Failure_Context) {
	if data.next_buffer_id == editor.Buffer_ID(0) || data.next_store_id == history.Store_ID(0) {
		return {}, {}, false, session_failure(data, operation, .Identity_Limit)
	}
	buffer_id = data.next_buffer_id
	store_id = data.next_store_id
	return buffer_id, store_id, true, {}
}

@(private)
session_next_document_identities :: proc(
	data: ^Session_Data,
	operation: Operation,
) -> (
	buffer_id: editor.Buffer_ID,
	store_id: history.Store_ID,
	document_id: document.Document_ID,
	ok: bool,
	failure: Failure_Context,
) {
	if data.next_document_id == document.Document_ID(0) {
		return {}, {}, {}, false, session_failure(data, operation, .Identity_Limit)
	}
	buffer_id, store_id, ok, failure = session_next_buffer_identities(data, operation)
	if !ok {
		return
	}
	document_id = data.next_document_id
	return buffer_id, store_id, document_id, true, {}
}
