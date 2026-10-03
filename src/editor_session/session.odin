// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import "../project"
import "../result_set"
import editor_view "../view"
import "core:strings"
import "core:unicode/utf8"

/* session_init creates one empty bounded session and its responsibility-owned view registry. */
session_init :: proc(
	session: ^Session,
	session_id: Session_ID,
	allocators: Allocator_Set,
	policy := DEFAULT_POLICY,
	project_policy := project.DEFAULT_POLICY,
) -> (handle: Session_Handle, ok: bool, failure: Failure_Context) {
	assert(session != nil)
	if session.state != nil || session.closed || session_id == Session_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Session, operation = .Initialize}
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		policy_failure.operation = .Initialize
		return {}, false, policy_failure
	}
	if allocators.persistent.procedure == nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	if allocators.temporary.procedure == nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, operation = .Initialize}
	}
	candidate_handle := Session_Handle {
		session_id = session_id,
		generation = Session_Generation(1),
	}

	data, data_error := new(Session_Data, allocators.persistent)
	if data_error != nil {
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	data.allocator = allocators.persistent
	data.temporary_allocator = allocators.temporary
	data.policy = policy
	data.handle = candidate_handle
	data.registry = Registry_Handle {
		session = candidate_handle,
		generation = Registry_Generation(1),
	}
	data.project_owner = project.Owner_Handle {
		id = project.Owner_ID(u64(session_id)),
		generation = project.Owner_Generation(u64(candidate_handle.generation)),
	}
	data.project_policy = project_policy
	data.mru_head = INVALID_SLOT
	data.mru_tail = INVALID_SLOT
	data.next_entry_id = Entry_ID(1)
	data.next_activation = Activation_Sequence(1)
	data.next_buffer_id = editor.Buffer_ID(1)
	data.next_store_id = history.Store_ID(1)
	data.next_document_id = document.Document_ID(1)
	data.root_generation = Root_Set_Generation(1)
	data.next_root_id = Root_ID(1)

	data.slots, data_error = make([]Entry_Slot, int(policy.live_buffers), allocators.persistent)
	if data_error != nil {
		free(data, allocators.persistent)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	for &slot in data.slots {
		slot.previous_mru = INVALID_SLOT
		slot.next_mru = INVALID_SLOT
	}

	index_capacity := int(policy.live_buffers) * 2
	data.label_index, data_error = make(map[string]int, index_capacity, allocators.persistent)
	if data_error != nil {
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	data.path_index, data_error = make(map[string]int, index_capacity, allocators.persistent)
	if data_error != nil {
		delete(data.label_index)
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}
	data.search_history_entries, data_error = make(
		[]Search_History_Entry,
		int(DEFAULT_SEARCH_HISTORY_ENTRIES),
		allocators.persistent,
	)
	if data_error != nil {
		delete(data.path_index)
		delete(data.label_index)
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context{code = .Persistent_Memory_Limit, operation = .Initialize}
	}

	registry_id := editor_view.Registry_ID(u32(session_id))
	if registry_id == editor_view.Registry_ID(0) {
		registry_id = editor_view.Registry_ID(1)
	}
	view_ok, view_failure := editor_view.registry_init(
		&data.view_registry,
		registry_id,
		allocators.persistent,
	)
	if !view_ok {
		delete(data.search_history_entries, allocators.persistent)
		delete(data.path_index)
		delete(data.label_index)
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context {
			code = .View_Failure,
			operation = .Initialize,
			view_failure = view_failure,
		}
	}
	project_ok, project_failure := project.registry_init(
		&data.project_registry,
		data.project_owner,
		project_policy,
		project.Allocator_Set {
			persistent = allocators.persistent,
			temporary = allocators.temporary,
		},
	)
	if !project_ok {
		view_closed, _ := editor_view.registry_close(&data.view_registry)
		assert(view_closed)
		delete(data.search_history_entries, allocators.persistent)
		delete(data.path_index)
		delete(data.label_index)
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context {
			code = .Project_Failure,
			operation = .Initialize,
			session = candidate_handle,
			project_failure = project_failure,
		}
	}
	result_ok, result_failure := result_set.registry_init(
		&data.result_registry,
		result_set.Config{limits = result_set.DEFAULT_LIMITS, allocator = allocators.persistent},
	)
	if !result_ok {
		project.registry_close(&data.project_registry)
		view_closed, _ := editor_view.registry_close(&data.view_registry)
		assert(view_closed)
		delete(data.search_history_entries, allocators.persistent)
		delete(data.path_index)
		delete(data.label_index)
		delete(data.slots, allocators.persistent)
		free(data, allocators.persistent)
		return {}, false, Failure_Context {
			code = .Persistent_Memory_Limit,
			operation = .Initialize,
			actual = result_failure.actual,
		}
	}

	handle = candidate_handle
	view_stats, view_stats_ok, view_stats_failure := editor_view.registry_stats(&data.view_registry)
	assert(view_stats_ok && view_stats_failure.code == .None)
	project_usage, project_usage_ok := project.registry_usage(&data.project_registry)
	assert(project_usage_ok)
	data.project_registry_bytes = project_usage.registry_bytes
	index_charge := u64(index_capacity * 2) * u64(size_of(string) + size_of(int))
	data.usage.registry_bytes = u64(size_of(Session_Data)) +
	                            u64(len(data.slots)) * u64(size_of(Entry_Slot)) +
	                            u64(len(data.search_history_entries)) * u64(size_of(Search_History_Entry)) +
	                            view_stats.storage_bytes + index_charge +
	                            data.project_registry_bytes
	session.state = data
	assert(session_validate(data))
	return handle, true, {}
}

/* session_close releases one empty session and invalidates its generation. */
session_close :: proc(session: ^Session) -> (ok: bool, failure: Failure_Context) {
	data := session_data(session)
	if data == nil {
		return false, Failure_Context{code = .Invalid_Session, operation = .Close}
	}
	if data.usage.live_buffers != 0 {
		failure = session_failure(data, .Close, .Retained_Entries)
		failure.actual = u64(data.usage.live_buffers)
		return false, failure
	}
	if data.usage.prepared_operations != 0 {
		failure = session_failure(data, .Close, .Retained_Preparations)
		failure.actual = u64(data.usage.prepared_operations)
		return false, failure
	}
	if data.detached_entries != 0 {
		failure = session_failure(data, .Close, .Retained_Cleanup)
		failure.actual = u64(data.detached_entries)
		return false, failure
	}
	view_closed, view_failure := editor_view.registry_close(&data.view_registry)
	if !view_closed {
		failure = session_failure(data, .Close, .View_Failure)
		failure.view_failure = view_failure
		return false, failure
	}
	project_progress := project.registry_close(&data.project_registry)
	assert(project_progress.complete && project_progress.first_failure.code == .None)
	result_closed, result_failure := result_set.registry_close(&data.result_registry)
	assert(result_closed && result_failure.code == .None)
	session_workspace_projects_clear(data)
	session_root_storage_clear(data)
	session_search_history_clear(data)
	delete(data.search_history_entries, data.allocator)
	delete(data.path_index)
	delete(data.label_index)
	delete(data.slots, data.allocator)
	allocator := data.allocator
	free(data, allocator)
	session.state = nil
	session.closed = true
	return true, {}
}

/* session_result_registry borrows the session-owned result registry after handle validation. */
session_result_registry :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (registry: ^result_set.Registry, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return nil, false, resolved_failure
	}
	return &data.result_registry, true, {}
}

/* session_usage returns one exact copied aggregate accounting snapshot. */
session_usage :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (usage: Resource_Usage, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return data.usage, true, {}
}

/* session_registry_handle returns the exact copied registry generation for a live session. */
session_registry_handle :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (registry: Registry_Handle, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return data.registry, true, {}
}

/* session_visible_target returns the one current checked presentation target. */
session_visible_target :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (target: Visible_Target, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	return data.visible, true, {}
}

/* session_present_ui selects one checked frontend-independent UI workflow without changing MRU order. */
session_present_ui :: proc(
	session: ^Session,
	handle: Session_Handle,
	ui: UI_Target,
) -> (previous, visible: Visible_Target, ok: bool, failure: Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Present_UI)
	if resolved_failure.code != .None {
		return {}, {}, false, resolved_failure
	}
	target := Visible_Target{kind = .UI_Root, ui = ui}
	if !visible_target_is_valid(target) {
		return {}, {}, false, session_failure(data, .Present_UI, .Invalid_Visible_Target)
	}
	previous = data.visible
	data.visible = target
	assert(session_validate(data))
	return previous, target, true, {}
}

/*
session_entry_prepare validates, reserves, and privately adopts one complete live object graph.
Success transfers the supplied resource wrappers into Prepared_Entry.
*/
session_entry_prepare :: proc(
	session: ^Session,
	request: Entry_Prepare_Request,
	prepared: ^Prepared_Entry,
) -> (result: Admission_Result, ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	if prepared.state != nil {
		return {}, false, Failure_Context{code = .Invalid_Reservation, operation = .Prepare_Entry}
	}
	data, resolved_failure := resolve_session(session, request.session, .Prepare_Entry)
	if resolved_failure.code != .None {
		return {}, false, resolved_failure
	}
	if data.usage.prepared_operations >= data.policy.prepared_operations {
		failure = session_failure(data, .Prepare_Entry, .Operation_Limit)
		failure.maximum = u64(data.policy.prepared_operations)
		failure.actual = u64(data.usage.prepared_operations) + 1
		return {}, false, failure
	}
	metadata_ok, metadata_failure := entry_metadata_validate(data, request)
	if !metadata_ok {
		return {}, false, metadata_failure
	}
	resource_ok, buffer_stats, history_stats, document_status, resource_failure :=
		entry_resources_validate(data, request)
	if !resource_ok {
		return {}, false, resource_failure
	}
	if identities_ok, identity_failure := entry_object_identities_validate(
		data,
		buffer_stats,
		history_stats,
		document_status,
		request.resources.has_document,
	); !identities_ok {
		return {}, false, identity_failure
	}
	slot_index := entry_reservable_slot(data)
	if slot_index == INVALID_SLOT {
		failure = session_failure(data, .Prepare_Entry, .Buffer_Limit)
		failure.maximum = u64(data.policy.live_buffers)
		failure.actual = u64(data.usage.live_buffers) + u64(data.usage.prepared_operations) + 1
		return {}, false, failure
	}
	if request.resources.has_document &&
	   data.usage.live_documents + data.reserved_documents >= data.policy.live_documents {
		failure = session_failure(data, .Prepare_Entry, .Document_Limit)
		failure.maximum = u64(data.policy.live_documents)
		failure.actual = u64(data.usage.live_documents + data.reserved_documents) + 1
		return {}, false, failure
	}

	reservation := Graph_Reservation {
		buffers = 1,
		documents = 1 if request.resources.has_document else 0,
		primary_views = 1,
		activation_entries = 1,
		canonical_text_bytes = buffer_stats.text_bytes,
		label_bytes = u64(len(request.selection_label) + len(request.normalized_path) +
		                  len(request.terminal.working_context)),
		view_anchors = 3,
		view_context_bytes = u64(size_of(editor_view.View_Handle)),
		history_bytes = history_stats.usage.retained_bytes,
		registry_bytes = u64(size_of(Entry_Owner)) +
		                 u64(len(request.selection_label) + len(request.normalized_path) +
		                     len(request.terminal.working_context)),
		prepared_operations = 1,
	}
	if data.usage.canonical_text_bytes + reservation.canonical_text_bytes > data.policy.aggregate_text_bytes {
		failure = session_failure(data, .Prepare_Entry, .Aggregate_Text_Limit)
		failure.maximum = data.policy.aggregate_text_bytes
		failure.actual = data.usage.canonical_text_bytes + reservation.canonical_text_bytes
		return {}, false, failure
	}
	if data.usage.retained_label_bytes + reservation.label_bytes > data.policy.retained_label_bytes {
		failure = session_failure(data, .Prepare_Entry, .Retained_Label_Limit)
		failure.maximum = data.policy.retained_label_bytes
		failure.actual = data.usage.retained_label_bytes + reservation.label_bytes
		return {}, false, failure
	}

	owner, owner_error := new(Entry_Owner, data.allocator)
	if owner_error != nil {
		return {}, false, session_failure(data, .Prepare_Entry, .Persistent_Memory_Limit)
	}
	label, label_error := strings.clone(request.selection_label, data.allocator)
	if label_error != nil {
		free(owner, data.allocator)
		return {}, false, session_failure(data, .Prepare_Entry, .Persistent_Memory_Limit)
	}
	path: string
	if len(request.normalized_path) > 0 {
		path, label_error = strings.clone(request.normalized_path, data.allocator)
		if label_error != nil {
			delete(label, data.allocator)
			free(owner, data.allocator)
			return {}, false, session_failure(data, .Prepare_Entry, .Persistent_Memory_Limit)
		}
	}
	terminal_context: string
	if len(request.terminal.working_context) > 0 {
		terminal_context, label_error = strings.clone(request.terminal.working_context, data.allocator)
		if label_error != nil {
			if len(path) > 0 {
				delete(path, data.allocator)
			}
			delete(label, data.allocator)
			free(owner, data.allocator)
			return {}, false, session_failure(data, .Prepare_Entry, .Persistent_Memory_Limit)
		}
	}
	prepared_state, state_error := new(Prepared_Entry_State, data.allocator)
	if state_error != nil {
		if len(terminal_context) > 0 {
			delete(terminal_context, data.allocator)
		}
		if len(path) > 0 {
			delete(path, data.allocator)
		}
		delete(label, data.allocator)
		free(owner, data.allocator)
		return {}, false, session_failure(data, .Prepare_Entry, .Persistent_Memory_Limit)
	}

	owner.kind = request.kind
	owner.buffer = request.resources.buffer^
	owner.history_store = request.resources.history_store^
	if request.resources.has_document {
		owner.document = request.resources.document^
		owner.document_live = true
	}
	owner.selection_label = label
	owner.normalized_path = path
	owner.terminal_context = terminal_context
	owner.association = request.association
	owner.terminal_ref = request.terminal.ref
	owner.terminal_lifecycle = request.terminal.lifecycle
	owner.reservation = reservation
	owner.buffer_live = true
	owner.history_live = true
	handle, reserved_failure := entry_identity_reserve(data, slot_index)
	if reserved_failure.code != .None {
		owner.buffer = {}
		owner.history_store = {}
		owner.document = {}
		owner_release_storage(data, owner)
		free(prepared_state, data.allocator)
		return {}, false, reserved_failure
	}
	view_handle, view_ok, view_failure := editor_view.create(
		&data.view_registry,
		&owner.buffer,
		request.view_config,
	)
	if !view_ok {
		entry_identity_unreserve(data, slot_index, owner)
		owner.buffer = {}
		owner.history_store = {}
		owner.document = {}
		owner_release_storage(data, owner)
		free(prepared_state, data.allocator)
		failure = session_failure(data, .Prepare_Entry, .View_Failure)
		failure.view_failure = view_failure
		return {}, false, failure
	}
	owner.primary_view = view_handle
	owner.primary_view_live = true
	data.slots[slot_index].owner = owner
	request.resources.buffer^ = {}
	request.resources.history_store^ = {}
	if request.resources.has_document {
		request.resources.document^ = {}
	}

	data.label_index[string(owner.selection_label)] = slot_index + 1
	if len(owner.normalized_path) > 0 {
		data.path_index[string(owner.normalized_path)] = slot_index + 1
	}
	if request.resources.has_document {
		data.reserved_documents += 1
	}
	data.usage.canonical_text_bytes += reservation.canonical_text_bytes
	data.usage.retained_label_bytes += reservation.label_bytes
	data.usage.view_anchors += reservation.view_anchors
	data.usage.view_context_bytes += reservation.view_context_bytes
	data.usage.history_bytes += reservation.history_bytes
	data.usage.registry_bytes += reservation.registry_bytes
	data.usage.prepared_operations += 1
	entry_object_identities_observe(data, buffer_stats, history_stats, document_status)
	prepared_state.session = data
	prepared_state.owner = owner
	prepared_state.handle = handle
	prepared_state.slot = slot_index
	prepared.state = prepared_state
	assert(session_validate(data))
	return Admission_Result {
		outcome = .Prepared,
		entry = handle,
		visible = data.visible,
		usage = data.usage,
	}, true, {}
}

@(private)
entry_object_identities_observe :: proc(
	data: ^Session_Data,
	buffer_stats: editor.Buffer_Stats,
	history_stats: history.Store_Stats,
	document_status: document.Document_Status,
) {
	if u64(buffer_stats.buffer_id) >= u64(data.next_buffer_id) {
		data.next_buffer_id = editor.Buffer_ID(u64(buffer_stats.buffer_id) + 1)
	}
	if u64(history_stats.store_id) >= u64(data.next_store_id) {
		data.next_store_id = history.Store_ID(u64(history_stats.store_id) + 1)
	}
	if document_status.document_id != document.Document_ID(0) &&
	   u64(document_status.document_id) >= u64(data.next_document_id) {
		data.next_document_id = document.Document_ID(u64(document_status.document_id) + 1)
	}
}

@(private)
entry_object_identities_validate :: proc(
	data: ^Session_Data,
	buffer_stats: editor.Buffer_Stats,
	history_stats: history.Store_Stats,
	document_status: document.Document_Status,
	has_document: bool,
) -> (ok: bool, failure: Failure_Context) {
	if data.next_buffer_id == editor.Buffer_ID(0) ||
	   data.next_store_id == history.Store_ID(0) ||
	   (has_document && data.next_document_id == document.Document_ID(0)) {
		return false, session_failure(data, .Prepare_Entry, .Identity_Limit)
	}
	if u64(buffer_stats.buffer_id) < u64(data.next_buffer_id) ||
	   u64(history_stats.store_id) < u64(data.next_store_id) ||
	   (has_document && u64(document_status.document_id) < u64(data.next_document_id)) {
		return false, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	return true, {}
}

@(private)
entry_metadata_validate :: proc(
	data: ^Session_Data,
	request: Entry_Prepare_Request,
) -> (ok: bool, failure: Failure_Context) {
	if request.kind != .Text && request.kind != .Terminal {
		return false, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	if len(request.selection_label) == 0 {
		return false, session_failure(data, .Prepare_Entry, .Invalid_Name)
	}
	if !utf8.valid_string(request.selection_label) || strings.index_byte(request.selection_label, 0) >= 0 {
		return false, session_failure(data, .Prepare_Entry, .Malformed_Label)
	}
	if u64(len(request.selection_label)) > data.policy.name_bytes && request.association == .Unassociated {
		failure = session_failure(data, .Prepare_Entry, .Label_Limit)
		failure.maximum = data.policy.name_bytes
		failure.actual = u64(len(request.selection_label))
		return false, failure
	}
	if data.label_index[request.selection_label] != 0 {
		return false, session_failure(data, .Prepare_Entry, .Name_Collision)
	}
	switch request.association {
	case .Invalid:
		return false, session_failure(data, .Prepare_Entry, .Invalid_Name)
	case .Unassociated:
		if len(request.normalized_path) != 0 {
			return false, session_failure(data, .Prepare_Entry, .Invalid_Path)
		}
	case .Document:
		if len(request.normalized_path) == 0 || request.selection_label != request.normalized_path ||
		   !utf8.valid_string(request.normalized_path) || strings.index_byte(request.normalized_path, 0) >= 0 {
			return false, session_failure(data, .Prepare_Entry, .Invalid_Path)
		}
		if data.path_index[request.normalized_path] != 0 {
			return false, session_failure(data, .Prepare_Entry, .Path_Collision)
		}
	}
	if request.kind == .Text {
		if request.terminal != (Terminal_Buffer_Source{}) {
			return false, session_failure(data, .Prepare_Entry, .Invalid_Terminal)
		}
	} else {
		if request.association != .Unassociated ||
		   !terminal_session_ref_is_valid(request.terminal.ref) ||
		   (request.terminal.lifecycle != .Running && request.terminal.lifecycle != .Exited &&
		    request.terminal.lifecycle != .Failed) {
			failure = session_failure(data, .Prepare_Entry, .Invalid_Terminal)
			failure.terminal = request.terminal.ref
			return false, failure
		}
		working_ctx := request.terminal.working_context
		if len(working_ctx) == 0 || u64(len(working_ctx)) > MAX_TERMINAL_WORKING_CONTEXT_BYTES ||
		   !utf8.valid_string(working_ctx) || strings.index_byte(working_ctx, 0) >= 0 {
			failure = session_failure(data, .Prepare_Entry, .Invalid_Terminal)
			failure.terminal = request.terminal.ref
			failure.maximum = MAX_TERMINAL_WORKING_CONTEXT_BYTES
			failure.actual = u64(len(working_ctx))
			return false, failure
		}
	}
	return true, {}
}

@(private)
entry_resources_validate :: proc(
	data: ^Session_Data,
	request: Entry_Prepare_Request,
) -> (
	ok: bool,
	buffer_stats: editor.Buffer_Stats,
	history_stats: history.Store_Stats,
	document_status: document.Document_Status,
	failure: Failure_Context,
) {
	resources := request.resources
	if resources.buffer == nil || resources.history_store == nil ||
	   (resources.has_document && resources.document == nil) {
		return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	buffer_ok: bool
	buffer_failure: editor.Failure_Context
	buffer_stats, buffer_ok, buffer_failure = editor.buffer_stats(resources.buffer)
	if !buffer_ok {
		failure = session_failure(data, .Prepare_Entry, .Editor_Failure)
		failure.editor_failure = buffer_failure
		return false, {}, {}, {}, failure
	}
	expected_buffer_kind := editor.Buffer_Kind.Text
	if request.kind == .Terminal do expected_buffer_kind = .Terminal_Projection
	if buffer_stats.kind != expected_buffer_kind {
		return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	history_ok: bool
	history_failure: history.Failure_Context
	history_stats, history_ok, history_failure = history.store_stats(resources.history_store)
	if !history_ok {
		failure = session_failure(data, .Prepare_Entry, .History_Failure)
		failure.history_failure = history_failure
		return false, {}, {}, {}, failure
	}
	if history_stats.buffer_id != buffer_stats.buffer_id ||
	   history_stats.current_revision != buffer_stats.revision {
		return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	if resources.has_document {
		document_ok: bool
		document_failure: document.Failure_Context
		document_status, document_ok, document_failure = document.document_status(resources.document)
		if !document_ok {
			failure = session_failure(data, .Prepare_Entry, .Document_Failure)
			failure.document_failure = document_failure
			return false, {}, {}, {}, failure
		}
		if document_status.buffer_id != buffer_stats.buffer_id {
			return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
		}
		if request.association == .Document {
			if !document_status.has_target || document_status.target_path != request.normalized_path {
				return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
			}
		} else if document_status.has_target {
			return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
		}
	} else if request.association == .Document {
		return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	if request.kind == .Terminal && resources.has_document {
		return false, {}, {}, {}, session_failure(data, .Prepare_Entry, .Invalid_Object_Graph)
	}
	return true, buffer_stats, history_stats, document_status, {}
}

@(private)
entry_reservable_slot :: proc(data: ^Session_Data) -> int {
	for &slot, slot_index in data.slots {
		if !slot.live && !slot.reserved && slot.generation != max(u32) {
			return slot_index
		}
	}
	return INVALID_SLOT
}

@(private)
entry_identity_reserve :: proc(
	data: ^Session_Data,
	slot_index: int,
) -> (handle: Entry_Handle, failure: Failure_Context) {
	if data.next_entry_id == Entry_ID(0) {
		return {}, session_failure(data, .Prepare_Entry, .Invalid_Entry)
	}
	if data.next_activation == Activation_Sequence(0) {
		return {}, session_failure(data, .Prepare_Entry, .Activation_Limit)
	}
	slot := &data.slots[slot_index]
	if slot.live || slot.reserved || slot.generation == max(u32) {
		return {}, session_failure(data, .Prepare_Entry, .Invalid_Reservation)
	}
	slot.generation += 1
	slot.entry_id = data.next_entry_id
	slot.activation_sequence = data.next_activation
	slot.reserved = true
	slot.previous_mru = INVALID_SLOT
	slot.next_mru = INVALID_SLOT
	handle = entry_handle(data, slot_index)
	data.next_entry_id = Entry_ID(u64(data.next_entry_id) + 1)
	data.next_activation = Activation_Sequence(u64(data.next_activation) + 1)
	return handle, {}
}

@(private)
entry_identity_unreserve :: proc(data: ^Session_Data, slot_index: int, owner: ^Entry_Owner) {
	slot := &data.slots[slot_index]
	if owner != nil {
		if len(owner.selection_label) > 0 && data.label_index[string(owner.selection_label)] == slot_index + 1 {
			delete_key(&data.label_index, string(owner.selection_label))
		}
		if len(owner.normalized_path) > 0 && data.path_index[string(owner.normalized_path)] == slot_index + 1 {
			delete_key(&data.path_index, string(owner.normalized_path))
		}
	}
	slot.entry_id = Entry_ID(0)
	slot.owner = nil
	slot.activation_sequence = Activation_Sequence(0)
	slot.reserved = false
	slot.previous_mru = INVALID_SLOT
	slot.next_mru = INVALID_SLOT
}

@(private)
owner_release_storage :: proc(data: ^Session_Data, owner: ^Entry_Owner) {
	if len(owner.terminal_context) > 0 {
		delete(owner.terminal_context, data.allocator)
	}
	if len(owner.normalized_path) > 0 {
		delete(owner.normalized_path, data.allocator)
	}
	if len(owner.selection_label) > 0 {
		delete(owner.selection_label, data.allocator)
	}
	free(owner, data.allocator)
}
