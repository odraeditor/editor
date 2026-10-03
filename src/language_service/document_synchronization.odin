// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import document "../document"
import project_core "../project"
import "base:runtime"
import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"

/* Synchronizer_Request binds one session to an exact trusted Project membership. */
Synchronizer_Request :: struct {
	session:         Session_Handle,
	project:         project_core.Project_Handle,
	membership:      project_core.Membership_Handle,
	root_policy:     Root_Policy,
	resolved_root:   string,
	languages:       []string,
	capabilities:    Capabilities,
	position_encoding: Position_Encoding,
	synchronization_mode: Synchronization_Mode,
	limits:          Service_Limits,
}

/* Document_Open_Request describes one exact file-backed canonical revision. */
Document_Open_Request :: struct {
	document_identity:  u64,
	buffer_identity:    u64,
	canonical_revision: u64,
	path:               string,
	uri:                string,
	language:           string,
	text:               string,
}

/* Document_Change_Request describes one normalized committed canonical splice. */
Document_Change_Request :: struct {
	binding:         Document_Binding_Handle,
	base_revision:   u64,
	target_revision: u64,
	start:            u64,
	end:              u64,
	replacement:      string,
	target_text:      string,
}

/* Synchronization_Operation identifies one queued LSP document notification. */
Synchronization_Operation :: enum u8 {
	Invalid,
	Open,
	Change,
	Save,
	Close,
	Recover,
}

/* Synchronization_Message_View borrows one queued copied JSON-RPC notification. */
Synchronization_Message_View :: struct {
	record:    Synchronization_Record,
	operation: Synchronization_Operation,
	body:      []u8,
}

/* Document_Synchronizer_Inspection is one pointer-free scoped owner snapshot. */
Document_Synchronizer_Inspection :: struct {
	session:              Session_Handle,
	project:              project_core.Project_Handle,
	membership:           project_core.Membership_Handle,
	root_policy:          Root_Policy,
	position_encoding:    Position_Encoding,
	synchronization_mode: Synchronization_Mode,
	revoked:              bool,
	documents:            u32,
	queue_depth:          u32,
	queue_bytes:          u64,
	latest_failure:       Failure_Context,
}

/* Document_Synchronizer owns exact document versions and a bounded LSP queue. */
Document_Synchronizer :: struct {
	state: rawptr,
}

@(private)
Document_Binding_Owner :: struct {
	descriptor: Document_Binding_Descriptor,
	path:       string,
	uri:        string,
	language:   string,
	text:       string,
	live:       bool,
}

@(private)
Synchronization_Message_Owner :: struct {
	view: Synchronization_Message_View,
	live: bool,
}

@(private)
Document_Synchronizer_State :: struct {
	project_registry:     ^project_core.Registry,
	session:              Session_Handle,
	project:              project_core.Project_Handle,
	membership:           project_core.Membership_Handle,
	root_policy:          Root_Policy,
	root:                 string,
	languages:            []string,
	capabilities:         Capabilities,
	position_encoding:    Position_Encoding,
	synchronization_mode: Synchronization_Mode,
	bindings:             [dynamic]Document_Binding_Owner,
	queue:                [dynamic]Synchronization_Message_Owner,
	next_binding_id:      Document_Binding_ID,
	next_synchronization_generation: Synchronization_Generation,
	usage:                Resource_Usage,
	document_text_bytes:  u64,
	limits:               Service_Limits,
	latest_failure:       Failure_Context,
	revoked:              bool,
	allocator:            runtime.Allocator,
}

/* document_synchronizer_init copies one exact trusted Project scope. */
document_synchronizer_init :: proc(
	synchronizer: ^Document_Synchronizer,
	project_registry: ^project_core.Registry,
	request: Synchronizer_Request,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if synchronizer == nil do return false, Failure_Context{code = .Invalid_Input}
	synchronizer^ = {}
	if project_registry == nil || allocator.procedure == nil ||
	   !session_handle_valid(request.session) || request.membership.project != request.project ||
	   !project_core.membership_handle_is_valid(request.membership) ||
	   !service_limits_valid(request.limits) || len(request.languages) == 0 ||
	   len(request.languages) > MAX_LANGUAGE_IDENTITIES ||
	   (request.position_encoding != .UTF_8 && request.position_encoding != .UTF_16) ||
	   (request.synchronization_mode != .Full && request.synchronization_mode != .Incremental) {
		return false, Failure_Context{code = .Invalid_Input}
	}
	if request.synchronization_mode == .Full && .Full_Synchronization not_in request.capabilities {
		return false, Failure_Context{code = .Unsupported_Capability}
	}
	if request.synchronization_mode == .Incremental && .Incremental_Synchronization not_in request.capabilities {
		return false, Failure_Context{code = .Unsupported_Capability}
	}
	for language in request.languages {
		if len(language) == 0 || len(language) > MAX_NAME_BYTES ||
		   !utf8.valid_string(language) || strings.index_byte(language, 0) >= 0 {
			return false, Failure_Context{code = .Invalid_Definition}
		}
	}
	for language, index in request.languages {
		for prior in 0 ..< index {
			if request.languages[prior] == language do return false, Failure_Context{code = .Invalid_Definition}
		}
	}
	descriptor, resolved, failure := synchronization_membership_descriptor(
		project_registry,
		request.project,
		request.membership,
	)
	if !resolved do return false, failure
	if !project_core.trust_allows_behavior(descriptor.trust, .Language_Service) {
		return false, Failure_Context{code = .Untrusted_Root, session = request.session}
	}
	membership_root := project_core.directory_path_text(&descriptor.path)
	root := membership_root
	if request.root_policy != .Project_Membership && request.root_policy != .Workspace_Folder {
		return false, Failure_Context{code = .Project_Scope, session = request.session}
	}
	if request.resolved_root != "" {
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(request.resolved_root, &normalized, context.temp_allocator)
		if !normalized_ok {
			return false, Failure_Context{code = .Outside_Root, session = request.session}
		}
		root = document.normalized_path_text(&normalized)
		if !service_root_contains(membership_root, root) {
			return false, Failure_Context{code = .Outside_Root, session = request.session}
		}
	}
	if u64(len(root)) > request.limits.root_bytes {
		return false, Failure_Context{code = .Resource_Limit, resource = .Root_Bytes, limit = request.limits.root_bytes, actual = u64(len(root))}
	}

	state, allocation_error := new(Document_Synchronizer_State, allocator)
	if allocation_error != nil do return false, Failure_Context{code = .Allocation}
	state.allocator = allocator
	state.root, allocation_error = strings.clone(root, allocator)
	if allocation_error != nil {
		free(state, allocator)
		return false, Failure_Context{code = .Allocation, resource = .Root_Bytes}
	}
	state.languages, allocation_error = synchronization_clone_strings(request.languages, allocator)
	if allocation_error != nil {
		delete(state.root, allocator)
		free(state, allocator)
		return false, Failure_Context{code = .Allocation, resource = .Definition}
	}
	state.bindings, allocation_error = make(
		[dynamic]Document_Binding_Owner,
		0,
		int(request.limits.documents_per_session),
		allocator,
	)
	if allocation_error == nil {
		state.queue, allocation_error = make(
			[dynamic]Synchronization_Message_Owner,
			0,
			int(request.limits.queue_depth),
			allocator,
		)
	}
	if allocation_error != nil {
		document_synchronizer_state_close(state)
		return false, Failure_Context{code = .Allocation}
	}
	state.project_registry = project_registry
	state.session = request.session
	state.project = request.project
	state.membership = request.membership
	state.root_policy = request.root_policy
	state.capabilities = request.capabilities
	state.position_encoding = request.position_encoding
	state.synchronization_mode = request.synchronization_mode
	state.next_binding_id = Document_Binding_ID(1)
	state.next_synchronization_generation = Synchronization_Generation(1)
	state.limits = request.limits
	synchronizer.state = state
	return true, {}
}

/* document_synchronizer_close releases all document and queued message storage. */
document_synchronizer_close :: proc(synchronizer: ^Document_Synchronizer) -> bool {
	state := document_synchronizer_state(synchronizer)
	if state == nil do return false
	document_synchronizer_state_close(state)
	synchronizer^ = {}
	return true
}

/* document_synchronizer_open binds one file and queues didOpen version one. */
document_synchronizer_open :: proc(
	synchronizer: ^Document_Synchronizer,
	request: Document_Open_Request,
) -> (Document_Binding_Handle, bool, Failure_Context) {
	state, failure := document_synchronizer_require_scope(synchronizer)
	if failure.code != .None do return {}, false, failure
	if request.document_identity == 0 || request.buffer_identity == 0 ||
	   !synchronization_document_values_valid(state, request) {
		return {}, false, synchronization_failure(state, .Invalid_Document)
	}
	if !document_synchronizer_path_admitted(state, request.path) {
		return {}, false, synchronization_failure(state, .Outside_Root)
	}
	if state.usage.documents >= u32(state.limits.documents_per_session) ||
	   state.usage.documents >= state.limits.documents_total {
		return {}, false, synchronization_resource_failure(state, .Document, u64(state.limits.documents_per_session), u64(state.usage.documents) + 1)
	}
	if u64(len(request.text)) > state.limits.synchronization_bytes -
	   min(state.document_text_bytes, state.limits.synchronization_bytes) {
		return {}, false, synchronization_resource_failure(
			state, .Synchronization_Bytes, state.limits.synchronization_bytes,
			state.document_text_bytes + u64(len(request.text)),
		)
	}
	for &existing in state.bindings {
		if existing.live && existing.descriptor.state != .Closed &&
		   (existing.descriptor.document_identity == request.document_identity || existing.uri == request.uri) {
			return {}, false, synchronization_failure(state, .Invalid_Document)
		}
	}
	if state.next_binding_id == Document_Binding_ID(0) {
		return {}, false, synchronization_failure(state, .Arithmetic_Overflow)
	}
	handle := Document_Binding_Handle{
		session = state.session,
		id = state.next_binding_id,
		generation = Document_Binding_Generation(1),
	}
	body, built := synchronization_open_body(request, state.allocator)
	if !built do return {}, false, synchronization_failure(state, .Allocation)
	queued, queue_failure := document_synchronizer_enqueue(
		state,
		handle,
		.Open,
		request.canonical_revision,
		request.canonical_revision,
		1,
		body,
	)
	if queue_failure.code != .None {
		delete(body, state.allocator)
		return {}, false, queue_failure
	}
	owner, copied := document_binding_owner_copy(state, handle, request)
	if !copied {
		document_synchronizer_remove_message(state, queued)
		return {}, false, synchronization_failure(state, .Allocation)
	}
	if !document_synchronizer_store_binding(state, owner) {
		document_binding_owner_close(&owner, state.allocator)
		document_synchronizer_remove_message(state, queued)
		return {}, false, synchronization_resource_failure(state, .Document, u64(state.limits.documents_per_session), u64(len(state.bindings)) + 1)
	}
	state.next_binding_id += Document_Binding_ID(1)
	state.usage.documents += 1
	state.document_text_bytes += u64(len(request.text))
	return handle, true, {}
}

/* document_synchronizer_change validates one splice and queues negotiated didChange. */
document_synchronizer_change :: proc(
	synchronizer: ^Document_Synchronizer,
	request: Document_Change_Request,
) -> (bool, Failure_Context) {
	state, failure := document_synchronizer_require_scope(synchronizer)
	if failure.code != .None do return false, failure
	owner, binding_failure := document_synchronizer_resolve_binding(state, request.binding)
	if binding_failure.code != .None do return false, binding_failure
	if owner.descriptor.state != .Open || request.base_revision != owner.descriptor.canonical_revision ||
	   request.base_revision == max(u64) || request.target_revision != request.base_revision + 1 ||
	   owner.descriptor.document_version == max(i64) ||
	   u64(len(request.target_text)) > state.limits.synchronization_bytes ||
	   !synchronization_splice_matches(owner.text, request) {
		return false, synchronization_failure(state, .Stale_Generation, request.binding)
	}
	projected_text_bytes := state.document_text_bytes - u64(len(owner.text)) + u64(len(request.target_text))
	if projected_text_bytes > state.limits.synchronization_bytes {
		return false, synchronization_resource_failure(
			state, .Synchronization_Bytes, state.limits.synchronization_bytes, projected_text_bytes,
		)
	}
	next_text, allocation_error := strings.clone(request.target_text, state.allocator)
	if allocation_error != nil do return false, synchronization_failure(state, .Allocation, request.binding)
	next_version := owner.descriptor.document_version + 1
	body, built := synchronization_change_body(
		owner,
		request,
		next_version,
		state.synchronization_mode,
		state.position_encoding,
		state.allocator,
	)
	if !built {
		delete(next_text, state.allocator)
		return false, synchronization_failure(state, .Allocation, request.binding)
	}
	_, queue_failure := document_synchronizer_enqueue(
		state,
		request.binding,
		.Change,
		request.base_revision,
		request.target_revision,
		next_version,
		body,
	)
	if queue_failure.code != .None {
		delete(body, state.allocator)
		delete(next_text, state.allocator)
		return false, queue_failure
	}
	delete(owner.text, state.allocator)
	owner.text = next_text
	state.document_text_bytes = projected_text_bytes
	owner.descriptor.canonical_revision = request.target_revision
	owner.descriptor.document_version = next_version
	owner.descriptor.synchronization_generation = state.next_synchronization_generation - Synchronization_Generation(1)
	owner.descriptor.state = .Open
	return true, {}
}

/* document_synchronizer_save queues didSave for one exact current revision. */
document_synchronizer_save :: proc(
	synchronizer: ^Document_Synchronizer,
	binding: Document_Binding_Handle,
	canonical_revision: u64,
) -> (bool, Failure_Context) {
	state, failure := document_synchronizer_require_scope(synchronizer)
	if failure.code != .None do return false, failure
	owner, binding_failure := document_synchronizer_resolve_binding(state, binding)
	if binding_failure.code != .None do return false, binding_failure
	if .Save_Notification not_in state.capabilities {
		return false, synchronization_failure(state, .Unsupported_Capability, binding)
	}
	if owner.descriptor.state != .Open || owner.descriptor.canonical_revision != canonical_revision {
		return false, synchronization_failure(state, .Stale_Generation, binding)
	}
	body, built := synchronization_save_body(owner.uri, state.allocator)
	if !built do return false, synchronization_failure(state, .Allocation, binding)
	_, queue_failure := document_synchronizer_enqueue(
		state, binding, .Save, canonical_revision, canonical_revision,
		owner.descriptor.document_version, body,
	)
	if queue_failure.code != .None do delete(body, state.allocator)
	return queue_failure.code == .None, queue_failure
}

/* document_synchronizer_recover replaces queued work with one full current update. */
document_synchronizer_recover :: proc(
	synchronizer: ^Document_Synchronizer,
	binding: Document_Binding_Handle,
	canonical_revision: u64,
	text: string,
) -> (bool, Failure_Context) {
	state, failure := document_synchronizer_require_scope(synchronizer)
	if failure.code != .None do return false, failure
	owner, binding_failure := document_synchronizer_resolve_binding(state, binding)
	if binding_failure.code != .None do return false, binding_failure
	if owner.descriptor.state != .Open || owner.descriptor.canonical_revision != canonical_revision ||
	   owner.text != text || owner.descriptor.document_version == max(i64) {
		return false, synchronization_failure(state, .Stale_Generation, binding)
	}
	next_version := owner.descriptor.document_version + 1
	body, built := synchronization_full_change_body(owner.uri, next_version, text, state.allocator)
	if !built do return false, synchronization_failure(state, .Allocation, binding)
	if len(body) == 0 || u64(len(body)) > state.limits.message_bytes ||
	   u64(len(body)) > state.limits.queue_bytes ||
	   u64(len(body)) > state.limits.synchronization_bytes {
		actual := u64(len(body))
		delete(body, state.allocator)
		return false, synchronization_resource_failure(state, .Synchronization_Bytes, state.limits.synchronization_bytes, actual)
	}
	document_synchronizer_remove_binding_messages(state, binding)
	_, queue_failure := document_synchronizer_enqueue(
		state, binding, .Recover, canonical_revision, canonical_revision, next_version, body,
	)
	if queue_failure.code != .None {
		delete(body, state.allocator)
		return false, queue_failure
	}
	owner.descriptor.document_version = next_version
	owner.descriptor.synchronization_generation = state.next_synchronization_generation - Synchronization_Generation(1)
	return true, {}
}

/* document_synchronizer_close_document queues didClose and closes local ownership. */
document_synchronizer_close_document :: proc(
	synchronizer: ^Document_Synchronizer,
	binding: Document_Binding_Handle,
	canonical_revision: u64,
) -> (bool, Failure_Context) {
	state, failure := document_synchronizer_require_scope(synchronizer)
	if failure.code != .None do return false, failure
	owner, binding_failure := document_synchronizer_resolve_binding(state, binding)
	if binding_failure.code != .None do return false, binding_failure
	if owner.descriptor.state != .Open || owner.descriptor.canonical_revision != canonical_revision {
		return false, synchronization_failure(state, .Stale_Generation, binding)
	}
	body, built := synchronization_close_body(owner.uri, state.allocator)
	if !built do return false, synchronization_failure(state, .Allocation, binding)
	_, queue_failure := document_synchronizer_enqueue(
		state, binding, .Close, canonical_revision, canonical_revision,
		owner.descriptor.document_version, body,
	)
	if queue_failure.code != .None {
		delete(body, state.allocator)
		return false, queue_failure
	}
	owner.descriptor.state = .Closed
	state.document_text_bytes -= u64(len(owner.text))
	delete(owner.text, state.allocator)
	owner.text = ""
	state.usage.documents -= 1
	return true, {}
}

/* document_synchronizer_peek borrows the oldest queued notification. */
document_synchronizer_peek :: proc(
	synchronizer: ^Document_Synchronizer,
) -> (Synchronization_Message_View, bool) {
	state := document_synchronizer_state(synchronizer)
	if state == nil do return {}, false
	oldest: ^Synchronization_Message_Owner
	for &message in state.queue {
		if message.live && (oldest == nil || message.view.record.generation < oldest.view.record.generation) {
			oldest = &message
		}
	}
	if oldest == nil do return {}, false
	return oldest.view, true
}

/* document_synchronizer_ack releases one exact queued notification. */
document_synchronizer_ack :: proc(
	synchronizer: ^Document_Synchronizer,
	generation: Synchronization_Generation,
) -> bool {
	state := document_synchronizer_state(synchronizer)
	if state == nil do return false
	for &message in state.queue {
		if !message.live || message.view.record.generation != generation {
			continue
		}
		if message.view.operation == .Open || message.view.operation == .Change ||
		   message.view.operation == .Recover {
			owner, failure := document_synchronizer_resolve_binding(state, message.view.record.binding)
			if failure.code != .None do return false
			owner.descriptor.transmitted_revision = message.view.record.target_revision
		}
		break
	}
	return document_synchronizer_remove_message(state, generation)
}

/* document_synchronizer_binding returns one pointer-free current descriptor. */
document_synchronizer_binding :: proc(
	synchronizer: ^Document_Synchronizer,
	handle: Document_Binding_Handle,
) -> (Document_Binding_Descriptor, bool, Failure_Context) {
	state := document_synchronizer_state(synchronizer)
	owner, failure := document_synchronizer_resolve_binding(state, handle)
	if failure.code != .None do return {}, false, failure
	return owner.descriptor, true, {}
}

/* document_synchronizer_text borrows the current canonical text of one open binding. */
document_synchronizer_text :: proc(
	synchronizer: ^Document_Synchronizer,
	handle: Document_Binding_Handle,
) -> (string, bool, Failure_Context) {
	state := document_synchronizer_state(synchronizer)
	owner, failure := document_synchronizer_resolve_binding(state, handle)
	if failure.code != .None do return "", false, failure
	if owner.descriptor.state != .Open {
		return "", false, synchronization_failure(state, .Invalid_Document, handle)
	}
	return owner.text, true, {}
}

/* document_synchronizer_uri borrows the exact URI of one open binding. */
document_synchronizer_uri :: proc(
	synchronizer: ^Document_Synchronizer,
	handle: Document_Binding_Handle,
) -> (string, bool, Failure_Context) {
	state := document_synchronizer_state(synchronizer)
	owner, failure := document_synchronizer_resolve_binding(state, handle)
	if failure.code != .None do return "", false, failure
	if owner.descriptor.state != .Open {
		return "", false, synchronization_failure(state, .Invalid_Document, handle)
	}
	return owner.uri, true, {}
}

/* document_synchronizer_inspect copies current scoped synchronization state. */
document_synchronizer_inspect :: proc(
	synchronizer: ^Document_Synchronizer,
) -> (Document_Synchronizer_Inspection, bool) {
	state := document_synchronizer_state(synchronizer)
	if state == nil do return {}, false
	return Document_Synchronizer_Inspection{
		session = state.session,
		project = state.project,
		membership = state.membership,
		root_policy = state.root_policy,
		position_encoding = state.position_encoding,
		synchronization_mode = state.synchronization_mode,
		revoked = state.revoked,
		documents = state.usage.documents,
		queue_depth = state.usage.queue_depth,
		queue_bytes = state.usage.queue_bytes,
		latest_failure = state.latest_failure,
	}, true
}

@(private = "file")
document_synchronizer_state :: proc(synchronizer: ^Document_Synchronizer) -> ^Document_Synchronizer_State {
	if synchronizer == nil || synchronizer.state == nil do return nil
	return (^Document_Synchronizer_State)(synchronizer.state)
}

@(private = "file")
document_synchronizer_require_scope :: proc(
	synchronizer: ^Document_Synchronizer,
) -> (^Document_Synchronizer_State, Failure_Context) {
	state := document_synchronizer_state(synchronizer)
	if state == nil do return nil, Failure_Context{code = .Closed}
	if state.revoked do return state, synchronization_failure(state, .Revoked)
	descriptor, resolved, failure := synchronization_membership_descriptor(
		state.project_registry,
		state.project,
		state.membership,
	)
	if !resolved || !project_core.trust_allows_behavior(descriptor.trust, .Language_Service) ||
	   !service_root_contains(project_core.directory_path_text(&descriptor.path), state.root) {
		document_synchronizer_revoke_state(state)
		if failure.code == .None do failure = synchronization_failure(state, .Revoked)
		return state, failure
	}
	return state, {}
}

@(private = "file")
synchronization_membership_descriptor :: proc(
	registry: ^project_core.Registry,
	project_handle: project_core.Project_Handle,
	membership: project_core.Membership_Handle,
) -> (project_core.Membership_Descriptor, bool, Failure_Context) {
	batch, copied, _ := project_core.registry_membership_descriptors(registry, project_handle)
	if !copied do return {}, false, Failure_Context{code = .Revoked}
	defer project_core.descriptor_batch_close(&batch)
	for descriptor in batch.descriptors {
		if descriptor.handle == membership do return descriptor, true, {}
	}
	return {}, false, Failure_Context{code = .Revoked}
}

@(private = "file")
document_synchronizer_path_admitted :: proc(state: ^Document_Synchronizer_State, path: string) -> bool {
	matches: [project_core.MAX_DIRECTORIES]project_core.Membership_Handle
	count, classified, _ := project_core.registry_classify_path(state.project_registry, state.project, path, matches[:])
	if !classified do return false
	contained := false
	for index in 0 ..< int(count) {
		if matches[index] == state.membership {
			contained = true
			break
		}
	}
	if !contained do return false
	normalized: document.Normalized_Path
	normalized_ok, _ := document.path_normalize(path, &normalized, context.temp_allocator)
	return normalized_ok && service_root_contains(state.root, document.normalized_path_text(&normalized))
}

@(private = "file")
document_synchronizer_resolve_binding :: proc(
	state: ^Document_Synchronizer_State,
	handle: Document_Binding_Handle,
) -> (^Document_Binding_Owner, Failure_Context) {
	if state == nil do return nil, Failure_Context{code = .Closed}
	if handle.session != state.session || handle.id == Document_Binding_ID(0) ||
	   handle.generation == Document_Binding_Generation(0) {
		return nil, synchronization_failure(state, .Invalid_Document, handle)
	}
	for &owner in state.bindings {
		if owner.live && owner.descriptor.handle == handle do return &owner, {}
	}
	return nil, synchronization_failure(state, .Stale_Generation, handle)
}

@(private = "file")
document_synchronizer_enqueue :: proc(
	state: ^Document_Synchronizer_State,
	binding: Document_Binding_Handle,
	operation: Synchronization_Operation,
	base_revision, target_revision: u64,
	document_version: i64,
	body: []u8,
) -> (Synchronization_Generation, Failure_Context) {
	if len(body) == 0 || u64(len(body)) > state.limits.message_bytes {
		return 0, synchronization_resource_failure(state, .Message_Bytes, state.limits.message_bytes, u64(len(body)))
	}
	if state.usage.queue_depth >= state.limits.queue_depth {
		return 0, synchronization_resource_failure(state, .Queue, u64(state.limits.queue_depth), u64(state.usage.queue_depth) + 1)
	}
	if state.usage.notifications >= state.limits.notifications {
		return 0, synchronization_resource_failure(state, .Notification, u64(state.limits.notifications), u64(state.usage.notifications) + 1)
	}
	is_change := operation == .Change || operation == .Recover
	if is_change && state.usage.synchronization_changes >= state.limits.synchronization_changes {
		return 0, synchronization_resource_failure(state, .Synchronization_Change, u64(state.limits.synchronization_changes), u64(state.usage.synchronization_changes) + 1)
	}
	if is_change && u64(len(body)) > state.limits.synchronization_bytes -
	   min(state.usage.synchronization_bytes, state.limits.synchronization_bytes) {
		return 0, synchronization_resource_failure(state, .Synchronization_Bytes, state.limits.synchronization_bytes, state.usage.synchronization_bytes + u64(len(body)))
	}
	if u64(len(body)) > state.limits.queue_bytes - min(state.usage.queue_bytes, state.limits.queue_bytes) {
		return 0, synchronization_resource_failure(state, .Queue_Bytes, state.limits.queue_bytes, state.usage.queue_bytes + u64(len(body)))
	}
	generation := state.next_synchronization_generation
	if generation == Synchronization_Generation(0) {
		return 0, synchronization_failure(state, .Arithmetic_Overflow, binding)
	}
	message := Synchronization_Message_Owner{
		view = {
			record = {
				binding = binding,
				generation = generation,
				state = .Queued,
				base_revision = base_revision,
				target_revision = target_revision,
				document_version = document_version,
				payload = {storage_generation = u64(generation), length = u64(len(body))},
			},
			operation = operation,
			body = body,
		},
		live = true,
	}
	stored := false
	for &slot in state.queue {
		if !slot.live {
			slot = message
			stored = true
			break
		}
	}
	if !stored {
		if len(state.queue) >= cap(state.queue) {
			return 0, synchronization_resource_failure(state, .Queue, u64(state.limits.queue_depth), u64(len(state.queue)) + 1)
		}
		if _, append_error := append(&state.queue, message); append_error != nil {
			return 0, synchronization_failure(state, .Allocation, binding)
		}
	}
	state.next_synchronization_generation += Synchronization_Generation(1)
	state.usage.queue_depth += 1
	state.usage.queue_bytes += u64(len(body))
	state.usage.notifications += 1
	if is_change {
		state.usage.synchronization_changes += 1
		state.usage.synchronization_bytes += u64(len(body))
	}
	return generation, {}
}

@(private = "file")
document_synchronizer_remove_message :: proc(
	state: ^Document_Synchronizer_State,
	generation: Synchronization_Generation,
) -> bool {
	for &message in state.queue {
		if message.live && message.view.record.generation == generation {
			state.usage.queue_depth -= 1
			state.usage.queue_bytes -= u64(len(message.view.body))
			state.usage.notifications -= 1
			if message.view.operation == .Change || message.view.operation == .Recover {
				state.usage.synchronization_changes -= 1
				state.usage.synchronization_bytes -= u64(len(message.view.body))
			}
			delete(message.view.body, state.allocator)
			message = {}
			return true
		}
	}
	return false
}

@(private = "file")
document_synchronizer_remove_binding_messages :: proc(
	state: ^Document_Synchronizer_State,
	binding: Document_Binding_Handle,
) {
	for &message in state.queue {
		if message.live && message.view.record.binding == binding {
			document_synchronizer_remove_message(state, message.view.record.generation)
		}
	}
}

@(private = "file")
document_synchronizer_store_binding :: proc(
	state: ^Document_Synchronizer_State,
	owner: Document_Binding_Owner,
) -> bool {
	for &slot in state.bindings {
		if !slot.live || slot.descriptor.state == .Closed {
			if slot.live do document_binding_owner_close(&slot, state.allocator)
			slot = owner
			return true
		}
	}
	if len(state.bindings) >= cap(state.bindings) do return false
	_, append_error := append(&state.bindings, owner)
	return append_error == nil
}

@(private = "file")
document_binding_owner_copy :: proc(
	state: ^Document_Synchronizer_State,
	handle: Document_Binding_Handle,
	request: Document_Open_Request,
) -> (Document_Binding_Owner, bool) {
	owner := Document_Binding_Owner{live = true}
	allocation_error: runtime.Allocator_Error
	owner.path, allocation_error = strings.clone(request.path, state.allocator)
	if allocation_error == nil do owner.uri, allocation_error = strings.clone(request.uri, state.allocator)
	if allocation_error == nil do owner.language, allocation_error = strings.clone(request.language, state.allocator)
	if allocation_error == nil do owner.text, allocation_error = strings.clone(request.text, state.allocator)
	if allocation_error != nil {
		document_binding_owner_close(&owner, state.allocator)
		return {}, false
	}
	owner.descriptor = Document_Binding_Descriptor{
		handle = handle,
		state = .Open,
		document_identity = request.document_identity,
		buffer_identity = request.buffer_identity,
		canonical_revision = request.canonical_revision,
		document_version = 1,
		position_encoding = state.position_encoding,
		synchronization_mode = state.synchronization_mode,
		synchronization_generation = state.next_synchronization_generation - Synchronization_Generation(1),
	}
	return owner, true
}

@(private = "file")
document_binding_owner_close :: proc(owner: ^Document_Binding_Owner, allocator: runtime.Allocator) {
	if owner == nil || !owner.live do return
	delete(owner.path, allocator)
	delete(owner.uri, allocator)
	delete(owner.language, allocator)
	if len(owner.text) > 0 do delete(owner.text, allocator)
	owner^ = {}
}

@(private = "file")
document_synchronizer_revoke_state :: proc(state: ^Document_Synchronizer_State) {
	if state.revoked do return
	state.revoked = true
	state.latest_failure = synchronization_failure(state, .Revoked)
	for &message in state.queue {
		if message.live do document_synchronizer_remove_message(state, message.view.record.generation)
	}
	for &owner in state.bindings {
		if owner.live && owner.descriptor.state != .Closed {
			owner.descriptor.state = .Failed
			if len(owner.text) > 0 {
				delete(owner.text, state.allocator)
				owner.text = ""
			}
		}
	}
	state.usage.documents = 0
	state.document_text_bytes = 0
}

@(private = "file")
document_synchronizer_state_close :: proc(state: ^Document_Synchronizer_State) {
	if state == nil do return
	for &message in state.queue {
		if message.live do delete(message.view.body, state.allocator)
	}
	if state.queue != nil do delete(state.queue)
	for &owner in state.bindings do document_binding_owner_close(&owner, state.allocator)
	if state.bindings != nil do delete(state.bindings)
	for language in state.languages do delete(language, state.allocator)
	if state.languages != nil do delete(state.languages, state.allocator)
	if len(state.root) > 0 do delete(state.root, state.allocator)
	free(state, state.allocator)
}

@(private = "file")
synchronization_document_values_valid :: proc(
	state: ^Document_Synchronizer_State,
	request: Document_Open_Request,
) -> bool {
	if !utf8.valid_string(request.path) || !utf8.valid_string(request.uri) ||
	   !utf8.valid_string(request.language) || !utf8.valid_string(request.text) ||
	   !strings.has_prefix(request.uri, "file://") ||
	   u64(len(request.uri)) > state.limits.uri_bytes ||
	   u64(len(request.text)) > state.limits.synchronization_bytes {
		return false
	}
	for language in state.languages {
		if language == request.language do return true
	}
	return false
}

@(private = "file")
synchronization_splice_matches :: proc(base: string, request: Document_Change_Request) -> bool {
	if request.start > request.end || request.end > u64(len(base)) ||
	   !utf8.valid_string(request.replacement) || !utf8.valid_string(request.target_text) ||
	   !utf8.valid_string(base[:int(request.start)]) || !utf8.valid_string(base[:int(request.end)]) {
		return false
	}
	expected_bytes := u64(len(base)) - (request.end - request.start) + u64(len(request.replacement))
	if expected_bytes != u64(len(request.target_text)) do return false
	prefix_end := int(request.start)
	replacement_end := prefix_end + len(request.replacement)
	return request.target_text[:prefix_end] == base[:prefix_end] &&
		request.target_text[prefix_end:replacement_end] == request.replacement &&
		request.target_text[replacement_end:] == base[int(request.end):]
}

@(private)
session_handle_valid :: proc(handle: Session_Handle) -> bool {
	return handle.id != Session_ID(0) && handle.generation != Session_Generation(0) &&
		handle.provider.id != Provider_ID(0) && handle.provider.generation != Provider_Generation(0) &&
		handle.provider.definition.id != Definition_ID(0) &&
		handle.provider.definition.generation != Definition_Generation(0) &&
		handle.provider.definition.registry.id != Registry_ID(0) &&
		handle.provider.definition.registry.generation != Registry_Generation(0)
}

@(private = "file")
synchronization_failure :: proc(
	state: ^Document_Synchronizer_State,
	code: Failure_Code,
	binding := Document_Binding_Handle{},
) -> Failure_Context {
	failure := Failure_Context{code = code, binding = binding}
	if state != nil {
		failure.session = state.session
		state.latest_failure = failure
	}
	return failure
}

@(private = "file")
synchronization_resource_failure :: proc(
	state: ^Document_Synchronizer_State,
	resource: Resource_Kind,
	limit, actual: u64,
) -> Failure_Context {
	failure := synchronization_failure(state, .Resource_Limit)
	failure.resource = resource
	failure.limit = limit
	failure.actual = actual
	state.latest_failure = failure
	return failure
}

@(private = "file")
synchronization_clone_strings :: proc(
	values: []string,
	allocator: runtime.Allocator,
) -> ([]string, runtime.Allocator_Error) {
	owned, allocation_error := make([]string, len(values), allocator)
	if allocation_error != nil do return nil, allocation_error
	for value, index in values {
		owned[index], allocation_error = strings.clone(value, allocator)
		if allocation_error != nil {
			for previous in 0 ..< index do delete(owned[previous], allocator)
			delete(owned, allocator)
			return nil, allocation_error
		}
	}
	return owned, nil
}

@(private = "file")
synchronization_open_body :: proc(request: Document_Open_Request, allocator: runtime.Allocator) -> ([]u8, bool) {
	Text_Document_Item :: struct {
		uri: string,
		language_id: string `json:"languageId"`,
		version: i64,
		text: string,
	}
	Params :: struct {text_document: Text_Document_Item `json:"textDocument"`}
	Message :: struct {jsonrpc, method: string, params: Params}
	message := Message{
		jsonrpc = "2.0",
		method = "textDocument/didOpen",
		params = {text_document = {
			uri = request.uri,
			language_id = request.language,
			version = 1,
			text = request.text,
		}},
	}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private = "file")
synchronization_change_body :: proc(
	owner: ^Document_Binding_Owner,
	request: Document_Change_Request,
	version: i64,
	mode: Synchronization_Mode,
	encoding: Position_Encoding,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	if mode == .Full do return synchronization_full_change_body(owner.uri, version, request.target_text, allocator)
	start, start_ok, _ := byte_offset_to_position(owner.text, request.start, encoding)
	finish, finish_ok, _ := byte_offset_to_position(owner.text, request.end, encoding)
	if !start_ok || !finish_ok do return nil, false
	Text_Document :: struct {uri: string, version: i64}
	Range :: struct {start, end: LSP_Position}
	Change :: struct {range: Range, text: string}
	Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		content_changes: []Change `json:"contentChanges"`,
	}
	Message :: struct {jsonrpc, method: string, params: Params}
	changes := [1]Change{{range = {start = start, end = finish}, text = request.replacement}}
	message := Message{
		jsonrpc = "2.0",
		method = "textDocument/didChange",
		params = {
			text_document = {uri = owner.uri, version = version},
			content_changes = changes[:],
		},
	}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private = "file")
synchronization_full_change_body :: proc(uri: string, version: i64, text: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	Text_Document :: struct {uri: string, version: i64}
	Change :: struct {text: string}
	Params :: struct {
		text_document: Text_Document `json:"textDocument"`,
		content_changes: []Change `json:"contentChanges"`,
	}
	Message :: struct {jsonrpc, method: string, params: Params}
	changes := [1]Change{{text = text}}
	message := Message{
		jsonrpc = "2.0",
		method = "textDocument/didChange",
		params = {
			text_document = {uri = uri, version = version},
			content_changes = changes[:],
		},
	}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private = "file")
synchronization_save_body :: proc(uri: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	Text_Document :: struct {uri: string}
	Params :: struct {text_document: Text_Document `json:"textDocument"`}
	Message :: struct {jsonrpc, method: string, params: Params}
	message := Message{jsonrpc = "2.0", method = "textDocument/didSave", params = {text_document = {uri = uri}}}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}

@(private = "file")
synchronization_close_body :: proc(uri: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	Text_Document :: struct {uri: string}
	Params :: struct {text_document: Text_Document `json:"textDocument"`}
	Message :: struct {jsonrpc, method: string, params: Params}
	message := Message{jsonrpc = "2.0", method = "textDocument/didClose", params = {text_document = {uri = uri}}}
	body, marshal_error := json.marshal(message, {}, allocator)
	return body, marshal_error == nil
}
