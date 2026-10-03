// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

import "../language"

/* MAX_CAPTURE_VALUES bounds one template expansion context. */
MAX_CAPTURE_VALUES :: 256
/* MAX_FEED_ENTRY_TEXT_BYTES bounds one copied provider entry field. */
MAX_FEED_ENTRY_TEXT_BYTES :: 64 * 1_024

/* Capture_Value_Kind identifies one admitted substitution source. */
Capture_Value_Kind :: enum u8 {
	Invalid,
	Time,
	Clipboard,
	Selection,
	Link,
	Prompt,
	File,
	Extension,
}

/* Capture_Capabilities is the closed substitution authority set. */
Capture_Capabilities :: bit_set[Capture_Value_Kind; u16]

/* Capture_Position selects the insertion point retained after finalization. */
Capture_Position :: enum u8 {
	Invalid,
	Start,
	Cursor,
	End,
}

/* Capture_Template_Source identifies confirmed literal or provider-generated template text. */
Capture_Template_Source :: enum u8 {
	Invalid,
	Literal,
	Generator,
}

/* Capture_Template is one confirmed bounded structured-entry definition. */
Capture_Template :: struct {
	identity:              string,
	key:                   rune,
	label:                 string,
	entry_kind:            Capture_Entry_Kind,
	source_kind:           Capture_Template_Source,
	source:                string,
	generator_admitted:    bool,
	required_capabilities: Capture_Capabilities,
	immediate_finish:      bool,
	start_clock:           bool,
	empty_lines_before:    u8,
	empty_lines_after:     u8,
	position:              Capture_Position,
	applicable:            bool,
	input_limit:           u64,
	output_limit:          u64,
}

/* Capture_Value is one borrowed, explicitly admitted template value. */
Capture_Value :: struct {
	kind:      Capture_Value_Kind,
	key:       string,
	value:     string,
	admitted:  bool,
	sensitive: bool,
}

/* Capture_Request binds expansion and finalization to one exact target. */
Capture_Request :: struct {
	operation_id:       Operation_ID,
	resource:           Resource_Identity,
	scope:              Scope,
	target:             Semantic_Target,
	template:           Capture_Template,
	values:             []Capture_Value,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* Capture_Lifecycle identifies preview, editing, finalization, and abort boundaries. */
Capture_Lifecycle :: enum u8 {
	Invalid,
	Prepared,
	Previewing,
	Editing,
	Finalized,
	Aborted,
}

/* Capture_Session_Descriptor reports copied draft state without exposing text. */
Capture_Session_Descriptor :: struct {
	operation_id:     Operation_ID,
	lifecycle:        Capture_Lifecycle,
	entry_kind:       Capture_Entry_Kind,
	text_bytes:       u64,
	cursor_byte:      u64,
	start_clock:      bool,
	immediate_finish: bool,
	sensitive_values: u16,
}

/* Capture_Session owns one copied expanded draft until finalize, abort, or close. */
Capture_Session :: struct {
	state: rawptr,
}

@(private)
Capture_Session_State :: struct {
	descriptor:        Capture_Session_Descriptor,
	scope:             Scope,
	target:            Semantic_Target,
	rewrite_generation: language.Jan_Rewrite_Generation,
	text:              []u8,
	output_limit:      u64,
	allocator:         runtime.Allocator,
}

/* Attachment_Action identifies public resource and navigation workflows. */
Attachment_Action :: enum u8 {
	Invalid,
	Copy,
	Move,
	Hard_Link,
	Symbolic_Link,
	Download,
	Create_Directory,
	Open,
	Reveal,
	List,
	Rename,
	Delete,
	Synchronize,
}

/* Attachment_Directory_Source identifies the visible attachment-owner policy. */
Attachment_Directory_Source :: enum u8 {
	Invalid,
	Stable_Identifier,
	Inherited,
	Explicit,
	Provider,
}

/* Attachment_Request binds one workflow to exact owner and resource identities. */
Attachment_Request :: struct {
	operation_id:          Operation_ID,
	action:                Attachment_Action,
	directory_source:      Attachment_Directory_Source,
	scope:                 Scope,
	owner:                 Semantic_Target,
	source:                Resource_Identity,
	destination:           Resource_Identity,
	provider_admitted:     bool,
	symlink_supported:     bool,
	maksym_admitted:       bool,
	repository_recording:  bool,
	repository_admitted:   bool,
	expected_bytes:        u64,
	attachment_limit:      u32,
}

/* Attachment_Effect_Plan exposes required public owners without executing them. */
Attachment_Effect_Plan :: struct {
	operation_id:         Operation_ID,
	action:               Attachment_Action,
	source:               Resource_Identity,
	destination:          Resource_Identity,
	resource_effect:      bool,
	resource_mutation:    bool,
	document_link_change: bool,
	reveal_with_maksym:   bool,
	repository_recording: bool,
	reversible_resource:  bool,
}

/* Attachment_Workflow_State identifies exact resource/document recovery boundaries. */
Attachment_Workflow_State :: enum u8 {
	Invalid,
	Prepared,
	Resource_Committed,
	Repository_Pending,
	Completed,
	Cancelled,
	Failed,
	Recovery_Required,
	Rolled_Back,
}

/* Attachment_Workflow_Event is one public-owner observation. */
Attachment_Workflow_Event :: enum u8 {
	Invalid,
	Cancel,
	Resource_Commit,
	Resource_Fail,
	Document_Commit,
	Document_Fail,
	Repository_Commit,
	Repository_Fail,
	Rollback_Resource,
}

/* Attachment_Workflow_Record retains exact committed state without private paths or contents. */
Attachment_Workflow_Record :: struct {
	operation_id:        Operation_ID,
	action:              Attachment_Action,
	state:               Attachment_Workflow_State,
	resource_committed:  bool,
	document_committed:  bool,
	repository_recorded: bool,
	repository_requested: bool,
	reversible_resource: bool,
}

/* Feed_Format identifies supported configured syndication formats. */
Feed_Format :: enum u8 {
	Invalid,
	RSS,
	Atom,
}

/* Feed_Refresh_Reason prevents network work from document-open observation. */
Feed_Refresh_Reason :: enum u8 {
	Invalid,
	Explicit,
	Scheduled,
	Document_Open,
}

/* Feed_Source_Definition is one bounded configured provider request. */
Feed_Source_Definition :: struct {
	identity:             string,
	endpoint:             string,
	format:               Feed_Format,
	credential_reference: string,
	retention_limit:      u32,
}

/* Feed_Entry_Candidate is one borrowed provider result. */
Feed_Entry_Candidate :: struct {
	identity:  string,
	title:     string,
	link:      string,
	summary:   string,
	published: u64,
}

/* Feed_Refresh_Request admits one explicit or scheduled bounded provider result. */
Feed_Refresh_Request :: struct {
	operation_id:      Operation_ID,
	source:            Feed_Source_Definition,
	reason:            Feed_Refresh_Reason,
	provider_admitted: bool,
	entry_limit:       u32,
	copied_text_limit: u64,
	cancel_requested:  bool,
}

/* Feed_Entry_Record borrows copied snapshot text until close. */
Feed_Entry_Record :: struct {
	identity:  string,
	title:     string,
	link:      string,
	summary:   string,
	published: u64,
}

/* Feed_Refresh_Descriptor reports bounded deduplication and retention accounting. */
Feed_Refresh_Descriptor :: struct {
	operation_id:   Operation_ID,
	entry_count:    u32,
	duplicate_count: u32,
	retained_count: u32,
	copied_bytes:   u64,
	truncated:      bool,
}

/* Feed_Refresh_Snapshot owns copied unseen entries and next retention identities. */
Feed_Refresh_Snapshot :: struct {
	state: rawptr,
}

@(private)
Feed_Refresh_State :: struct {
	descriptor: Feed_Refresh_Descriptor,
	entries:    []Feed_Entry_Record,
	retained:   []string,
	arena:      []u8,
	allocator:  runtime.Allocator,
}

/* capture_session_prepare expands one bounded template without executing effects. */
capture_session_prepare :: proc(
	session: ^Capture_Session,
	request: Capture_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Capture_Session_Descriptor, bool, Failure) {
	if session == nil || session.state != nil || !capture_request_is_valid(request) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, intake_failure(request.operation_id, .Capture, .Invalid_Request, .Capture)
	}
	input_bytes: u64
	sensitive_values: u16
	for value, index in request.values {
		if !capture_value_is_valid(value) || value.kind not_in request.template.required_capabilities {
			return {}, false, intake_failure(request.operation_id, .Capture, .Unavailable, .Capture)
		}
		for prior in request.values[:index] do if prior.key == value.key {
			return {}, false, intake_failure(request.operation_id, .Capture, .Conflict, .Capture)
		}
		if u64(len(value.value)) > max(u64) - input_bytes {
			return {}, false, intake_failure(request.operation_id, .Capture, .Limited, .Limit)
		}
		input_bytes += u64(len(value.value))
		if value.sensitive do sensitive_values += 1
	}
	if input_bytes > request.template.input_limit {
		failure := intake_failure(request.operation_id, .Capture, .Limited, .Limit)
		failure.limit = request.template.input_limit
		failure.actual = input_bytes
		return {}, false, failure
	}
	expanded, cursor, expanded_ok, expansion_failure := capture_expand(
		request.template,
		request.values,
		temporary_allocator,
	)
	if !expanded_ok do return {}, false, intake_failure(request.operation_id, .Capture, expansion_failure, .Capture)
	defer delete(expanded, temporary_allocator)
	state, state_error := new(Capture_Session_State, allocator)
	if state_error != nil do return {}, false, intake_failure(request.operation_id, .Capture, .Allocation_Failed, .Capture)
	state^ = Capture_Session_State{allocator = allocator}
	state.text, state_error = make([]u8, len(expanded), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, intake_failure(request.operation_id, .Capture, .Allocation_Failed, .Capture)
	}
	copy(state.text, expanded)
	state.scope = request.scope
	state.target = request.target
	state.rewrite_generation = request.rewrite_generation
	state.output_limit = request.template.output_limit
	lifecycle := Capture_Lifecycle.Previewing
	if request.template.immediate_finish do lifecycle = .Prepared
	state.descriptor = {
		operation_id = request.operation_id,
		lifecycle = lifecycle,
		entry_kind = request.template.entry_kind,
		text_bytes = u64(len(expanded)),
		cursor_byte = cursor,
		start_clock = request.template.start_clock,
		immediate_finish = request.template.immediate_finish,
		sensitive_values = sensitive_values,
	}
	session.state = state
	return state.descriptor, true, {}
}

/* capture_session_descriptor reports copied state without draft contents. */
capture_session_descriptor :: proc(session: ^Capture_Session) -> (Capture_Session_Descriptor, bool) {
	state := capture_session_state(session)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* capture_session_text borrows expanded or edited text until the next mutation. */
capture_session_text :: proc(session: ^Capture_Session) -> (string, bool) {
	state := capture_session_state(session)
	if state == nil || state.text == nil do return "", false
	return string(state.text), true
}

/* capture_session_begin_edit enters the explicit editable preview state. */
capture_session_begin_edit :: proc(session: ^Capture_Session) -> (bool, Failure) {
	state := capture_session_state(session)
	if state == nil || state.descriptor.lifecycle != .Previewing {
		return false, intake_failure(0, .Capture, .Conflict, .Capture)
	}
	state.descriptor.lifecycle = .Editing
	return true, {}
}

/* capture_session_replace_text copies one bounded edited draft atomically. */
capture_session_replace_text :: proc(
	session: ^Capture_Session,
	replacement: string,
) -> (Capture_Session_Descriptor, bool, Failure) {
	state := capture_session_state(session)
	if state == nil || state.descriptor.lifecycle != .Editing || len(replacement) == 0 ||
	   u64(len(replacement)) > state.output_limit || !utf8.valid_string(replacement) {
		return {}, false, intake_failure(0, .Capture, .Invalid_Request, .Capture)
	}
	copy_text, allocation_error := make([]u8, len(replacement), state.allocator)
	if allocation_error != nil {
		return state.descriptor, false, intake_failure(state.descriptor.operation_id, .Capture, .Allocation_Failed, .Capture)
	}
	copy(copy_text, replacement)
	delete(state.text, state.allocator)
	state.text = copy_text
	state.descriptor.text_bytes = u64(len(copy_text))
	state.descriptor.cursor_byte = min(state.descriptor.cursor_byte, u64(len(copy_text)))
	return state.descriptor, true, {}
}

/* capture_session_finalize_prepare creates one checked target rewrite and consumes no effects. */
capture_session_finalize_prepare :: proc(
	session: ^Capture_Session,
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Capture_Session_Descriptor, bool, Failure) {
	state := capture_session_state(session)
	if state == nil || plan == nil || analysis == nil ||
	   !capture_lifecycle_can_finalize(state.descriptor.lifecycle) ||
	   u64(len(source)) != state.scope.source_bytes || state.text == nil ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, intake_failure(0, .Capture, .Invalid_Request, .Capture)
	}
	start, end := int(state.target.range.start), int(state.target.range.end)
	if end > len(source) do return state.descriptor, false, intake_failure(state.descriptor.operation_id, .Capture, .Stale, .Target)
	current := string(source[start:end])
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil do return state.descriptor, false, intake_failure(state.descriptor.operation_id, .Capture, .Allocation_Failed, .Capture)
	defer strings.builder_destroy(&builder)
	if strings.write_string(&builder, current) != len(current) ||
	   len(current) > 0 && current[len(current) - 1] != '\n' && strings.write_byte(&builder, '\n') != 1 ||
	   strings.write_string(&builder, string(state.text)) != len(state.text) {
		return state.descriptor, false, intake_failure(state.descriptor.operation_id, .Capture, .Allocation_Failed, .Capture)
	}
	if state.text[len(state.text) - 1] != '\n' && strings.write_byte(&builder, '\n') != 1 {
		return state.descriptor, false, intake_failure(state.descriptor.operation_id, .Capture, .Allocation_Failed, .Capture)
	}
	rewrites := [1]language.Jan_Rewrite_Request{{
		node_id = state.target.node_id,
		range = state.target.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		state.rewrite_generation,
		rewrites[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned do return state.descriptor, false, intake_failure_from_language(state.descriptor.operation_id, .Capture, jan_failure)
	state.descriptor.lifecycle = .Finalized
	return state.descriptor, true, {}
}

/* capture_session_abort clears draft text and records explicit cancellation. */
capture_session_abort :: proc(session: ^Capture_Session) -> (Capture_Session_Descriptor, bool) {
	state := capture_session_state(session)
	if state == nil || state.descriptor.lifecycle == .Finalized || state.descriptor.lifecycle == .Aborted do return {}, false
	if state.text != nil do delete(state.text, state.allocator)
	state.text = nil
	state.descriptor.text_bytes = 0
	state.descriptor.cursor_byte = 0
	state.descriptor.lifecycle = .Aborted
	return state.descriptor, true
}

/* capture_session_close releases copied draft state exactly once. */
capture_session_close :: proc(session: ^Capture_Session) {
	state := capture_session_state(session)
	if state == nil do return
	allocator := state.allocator
	if state.text != nil do delete(state.text, allocator)
	state^ = {}
	free(state, allocator)
	session.state = nil
}

/* attachment_effect_plan_prepare validates one workflow without performing resource effects. */
attachment_effect_plan_prepare :: proc(request: Attachment_Request) -> (Attachment_Effect_Plan, bool, Failure) {
	if !attachment_request_is_valid(request) {
		return {}, false, intake_failure(request.operation_id, .Attachment, .Invalid_Request, .Attachment)
	}
	if request.action == .Symbolic_Link && !request.symlink_supported ||
	   request.action == .Reveal && !request.maksym_admitted ||
	   request.repository_recording && !attachment_action_mutates_resource(request.action) ||
	   request.repository_recording && !request.repository_admitted ||
	   attachment_action_uses_provider(request.action) && !request.provider_admitted {
		return {}, false, intake_failure(request.operation_id, .Attachment, .Unavailable, .Attachment)
	}
	resource_mutation := attachment_action_mutates_resource(request.action)
	document_change := attachment_action_changes_document(request.action)
	return {
		operation_id = request.operation_id,
		action = request.action,
		source = request.source,
		destination = request.destination,
		resource_effect = true,
		resource_mutation = resource_mutation,
		document_link_change = document_change,
		reveal_with_maksym = request.action == .Reveal,
		repository_recording = request.repository_recording,
		reversible_resource = resource_mutation && request.action != .Delete && request.action != .Synchronize,
	}, true, {}
}

/* attachment_workflow_prepare creates one explicit recoverable outcome record. */
attachment_workflow_prepare :: proc(plan: Attachment_Effect_Plan) -> (Attachment_Workflow_Record, bool) {
	if plan.operation_id == Operation_ID(0) || plan.action == .Invalid do return {}, false
	return {
		operation_id = plan.operation_id,
		action = plan.action,
		state = .Prepared,
		repository_requested = plan.repository_recording,
		reversible_resource = plan.reversible_resource,
	}, true
}

/* attachment_workflow_advance retains exact resource, document, and repository outcomes. */
attachment_workflow_advance :: proc(
	record: Attachment_Workflow_Record,
	plan: Attachment_Effect_Plan,
	event: Attachment_Workflow_Event,
) -> (Attachment_Workflow_Record, bool, Failure) {
	if record.operation_id != plan.operation_id || record.state == .Invalid || event == .Invalid {
		return record, false, intake_failure(record.operation_id, .Attachment, .Malformed, .Attachment)
	}
	next := record
	switch record.state {
	case .Prepared:
		#partial switch event {
		case .Cancel:
			next.state = .Cancelled
		case .Resource_Fail:
			next.state = .Failed
		case .Resource_Commit:
			next.resource_committed = true
			if plan.document_link_change do next.state = .Resource_Committed
			else if plan.repository_recording do next.state = .Repository_Pending
			else do next.state = .Completed
		}
	case .Resource_Committed:
		#partial switch event {
		case .Document_Commit:
			next.document_committed = true
			if plan.repository_recording do next.state = .Repository_Pending
			else do next.state = .Completed
		case .Document_Fail, .Cancel:
			next.state = .Recovery_Required
		}
	case .Recovery_Required:
		#partial switch event {
		case .Document_Commit:
			next.document_committed = true
			if plan.repository_recording do next.state = .Repository_Pending
			else do next.state = .Completed
		case .Rollback_Resource:
			if !record.reversible_resource do return record, false, intake_failure(record.operation_id, .Attachment, .Recovery_Required, .Attachment)
			next.resource_committed = false
			next.state = .Rolled_Back
		}
	case .Repository_Pending:
		#partial switch event {
		case .Repository_Commit:
			next.repository_recorded = true
			next.state = .Completed
		case .Repository_Fail:
			next.state = .Completed
			failure := intake_failure(record.operation_id, .Attachment, .Partial, .Attachment)
			failure.committed = 2 if next.document_committed else 1
			return next, true, failure
		}
	case .Completed, .Cancelled, .Failed, .Rolled_Back, .Invalid:
		return record, false, intake_failure(record.operation_id, .Attachment, .Conflict, .Attachment)
	}
	if next.state == record.state && next.resource_committed == record.resource_committed &&
	   next.document_committed == record.document_committed {
		return record, false, intake_failure(record.operation_id, .Attachment, .Conflict, .Attachment)
	}
	failure: Failure
	if next.state == .Recovery_Required {
		failure = intake_failure(record.operation_id, .Attachment, .Recovery_Required, .Attachment)
		failure.committed = 1
	}
	return next, true, failure
}

/* attachment_link_plan_prepare mutates source only after a confirmed resource outcome. */
attachment_link_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Attachment_Request,
	resource_committed: bool,
	rewrite_generation: language.Jan_Rewrite_Generation,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	effect, valid, failure := attachment_effect_plan_prepare(request)
	if !valid do return false, failure
	if !effect.document_link_change || !resource_committed || plan == nil || analysis == nil ||
	   u64(len(source)) != request.scope.source_bytes || rewrite_generation == language.Jan_Rewrite_Generation(0) {
		return false, intake_failure(request.operation_id, .Attachment, .Confirmation_Required, .Attachment)
	}
	start, end := int(request.owner.range.start), int(request.owner.range.end)
	if end > len(source) do return false, intake_failure(request.operation_id, .Attachment, .Stale, .Target)
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil do return false, intake_failure(request.operation_id, .Attachment, .Allocation_Failed, .Attachment)
	defer strings.builder_destroy(&builder)
	current := string(source[start:end])
	replaced, rewrite_failure := attachment_document_rewrite(&builder, current, request, temporary_allocator)
	if !replaced {
		return false, intake_failure(request.operation_id, .Attachment, rewrite_failure, .Attachment)
	}
	rewrites := [1]language.Jan_Rewrite_Request{{
		node_id = request.owner.node_id,
		range = request.owner.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		rewrite_generation,
		rewrites[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned do return false, intake_failure_from_language(request.operation_id, .Attachment, jan_failure)
	return true, {}
}

/* feed_source_definition_is_valid validates configuration without contacting the network. */
feed_source_definition_is_valid :: proc(source: Feed_Source_Definition) -> bool {
	return configuration_text_is_valid(source.identity, MAX_IDENTITY_BYTES) &&
	       configuration_text_is_valid(source.endpoint, MAX_RESOURCE_BYTES) &&
	       source.format != .Invalid && source.retention_limit > 0 &&
	       source.retention_limit <= MAX_FEED_ENTRIES &&
	       len(source.credential_reference) <= MAX_IDENTITY_BYTES &&
	       utf8.valid_string(source.credential_reference)
}

/* feed_refresh_snapshot_prepare copies unseen entries and deterministic retention state. */
feed_refresh_snapshot_prepare :: proc(
	snapshot: ^Feed_Refresh_Snapshot,
	request: Feed_Refresh_Request,
	entries: []Feed_Entry_Candidate,
	retained: []string,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Feed_Refresh_Descriptor, bool, Failure) {
	if snapshot == nil || snapshot.state != nil || request.operation_id == Operation_ID(0) ||
	   !feed_source_definition_is_valid(request.source) || !request.provider_admitted ||
	   (request.reason != .Explicit && request.reason != .Scheduled) || request.entry_limit == 0 ||
	   request.entry_limit > MAX_FEED_ENTRIES || request.copied_text_limit == 0 ||
	   request.copied_text_limit > MAX_COPIED_TEXT_BYTES || len(entries) > int(MAX_FEED_ENTRIES) ||
	   len(retained) > int(MAX_FEED_ENTRIES) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil {
		return {}, false, intake_failure(request.operation_id, .Feed, .Invalid_Request, .Feed)
	}
	if request.cancel_requested do return {}, false, intake_failure(request.operation_id, .Feed, .Cancelled, .Feed)
	seen, seen_error := make(map[string]bool, len(entries) + len(retained), temporary_allocator)
	if seen_error != nil do return {}, false, intake_failure(request.operation_id, .Feed, .Allocation_Failed, .Feed)
	defer delete(seen)
	for identity in retained {
		if !capture_text_is_valid(identity, MAX_IDENTITY_BYTES) {
			return {}, false, intake_failure(request.operation_id, .Feed, .Malformed, .Feed)
		}
		if seen[identity] {
			return {}, false, intake_failure(request.operation_id, .Feed, .Conflict, .Feed)
		}
		seen[identity] = true
	}
	selected_indexes, indexes_error := make([]int, min(len(entries), int(request.entry_limit)), temporary_allocator)
	if indexes_error != nil do return {}, false, intake_failure(request.operation_id, .Feed, .Allocation_Failed, .Feed)
	defer delete(selected_indexes, temporary_allocator)
	selected_count := 0
	duplicate_count: u32
	truncated := false
	arena_bytes: u64
	for entry, index in entries {
		if !feed_entry_candidate_is_valid(entry) do return {}, false, intake_failure(request.operation_id, .Feed, .Malformed, .Feed)
		if seen[entry.identity] {
			duplicate_count += 1
			continue
		}
		seen[entry.identity] = true
		if selected_count >= len(selected_indexes) {
			truncated = true
			continue
		}
		entry_bytes := u64(len(entry.identity) + len(entry.title) + len(entry.link) + len(entry.summary))
		if entry_bytes > request.copied_text_limit - min(request.copied_text_limit, arena_bytes) {
			truncated = true
			continue
		}
		selected_indexes[selected_count] = index
		selected_count += 1
		arena_bytes += entry_bytes
	}
	retention_count := min(int(request.source.retention_limit), selected_count + len(retained))
	for index in 0 ..< min(selected_count, retention_count) {
		identity := entries[selected_indexes[index]].identity
		arena_bytes += u64(len(identity))
	}
	remaining_retention := retention_count - min(selected_count, retention_count)
	for index in 0 ..< remaining_retention do arena_bytes += u64(len(retained[index]))
	if arena_bytes > request.copied_text_limit {
		failure := intake_failure(request.operation_id, .Feed, .Limited, .Limit)
		failure.limit = request.copied_text_limit
		failure.actual = arena_bytes
		return {}, false, failure
	}
	state, state_error := new(Feed_Refresh_State, allocator)
	if state_error != nil do return {}, false, intake_failure(request.operation_id, .Feed, .Allocation_Failed, .Feed)
	state^ = Feed_Refresh_State{allocator = allocator}
	state.entries, state_error = make([]Feed_Entry_Record, selected_count, allocator)
	if state_error == nil do state.retained, state_error = make([]string, retention_count, allocator)
	if state_error == nil && arena_bytes > 0 do state.arena, state_error = make([]u8, int(arena_bytes), allocator)
	if state_error != nil {
		feed_refresh_state_close(state)
		return {}, false, intake_failure(request.operation_id, .Feed, .Allocation_Failed, .Feed)
	}
	cursor := 0
	for output_index in 0 ..< selected_count {
		entry := entries[selected_indexes[output_index]]
		state.entries[output_index] = {
			identity = intake_arena_copy(state.arena, &cursor, entry.identity),
			title = intake_arena_copy(state.arena, &cursor, entry.title),
			link = intake_arena_copy(state.arena, &cursor, entry.link),
			summary = intake_arena_copy(state.arena, &cursor, entry.summary),
			published = entry.published,
		}
	}
	retention_index := 0
	for index in 0 ..< min(selected_count, retention_count) {
		state.retained[retention_index] = intake_arena_copy(state.arena, &cursor, entries[selected_indexes[index]].identity)
		retention_index += 1
	}
	for index in 0 ..< remaining_retention {
		state.retained[retention_index] = intake_arena_copy(state.arena, &cursor, retained[index])
		retention_index += 1
	}
	state.descriptor = {
		operation_id = request.operation_id,
		entry_count = u32(selected_count),
		duplicate_count = duplicate_count,
		retained_count = u32(retention_count),
		copied_bytes = arena_bytes,
		truncated = truncated,
	}
	snapshot.state = state
	return state.descriptor, true, {}
}

/* feed_refresh_entry borrows one copied unseen entry until snapshot close. */
feed_refresh_entry :: proc(snapshot: ^Feed_Refresh_Snapshot, index: int) -> (Feed_Entry_Record, bool) {
	state := feed_refresh_state(snapshot)
	if state == nil || index < 0 || index >= len(state.entries) do return {}, false
	return state.entries[index], true
}

/* feed_refresh_retained_identity borrows one next-generation deduplication identity. */
feed_refresh_retained_identity :: proc(snapshot: ^Feed_Refresh_Snapshot, index: int) -> (string, bool) {
	state := feed_refresh_state(snapshot)
	if state == nil || index < 0 || index >= len(state.retained) do return "", false
	return state.retained[index], true
}

/* feed_entry_capture_values projects copied feed data through ordinary capture substitutions. */
feed_entry_capture_values :: proc(entry: Feed_Entry_Record, output: []Capture_Value) -> (int, bool) {
	if len(output) < 3 || !feed_entry_record_is_valid(entry) do return 0, false
	output[0] = {kind = .Extension, key = "feed-title", value = entry.title, admitted = true}
	output[1] = {kind = .Link, key = "feed-link", value = entry.link, admitted = true}
	output[2] = {kind = .Extension, key = "feed-summary", value = entry.summary, admitted = true}
	return 3, true
}

/* feed_refresh_snapshot_close releases copied provider results exactly once. */
feed_refresh_snapshot_close :: proc(snapshot: ^Feed_Refresh_Snapshot) {
	state := feed_refresh_state(snapshot)
	if state == nil do return
	feed_refresh_state_close(state)
	snapshot.state = nil
}

@(private)
capture_lifecycle_can_finalize :: proc(lifecycle: Capture_Lifecycle) -> bool {
	return lifecycle == .Prepared || lifecycle == .Previewing || lifecycle == .Editing
}

@(private)
attachment_action_uses_provider :: proc(action: Attachment_Action) -> bool {
	return action == .Download || action == .Synchronize
}

@(private)
attachment_action_mutates_resource :: proc(action: Attachment_Action) -> bool {
	return action == .Copy || action == .Move || action == .Hard_Link ||
	       action == .Symbolic_Link || action == .Download || action == .Create_Directory ||
	       action == .Rename || action == .Delete || action == .Synchronize
}

@(private)
attachment_action_changes_document :: proc(action: Attachment_Action) -> bool {
	return action == .Copy || action == .Move || action == .Hard_Link ||
	       action == .Symbolic_Link || action == .Download || action == .Rename ||
	       action == .Delete
}

@(private)
attachment_action_requires_source :: proc(action: Attachment_Action) -> bool {
	return action == .Copy || action == .Move || action == .Hard_Link ||
	       action == .Symbolic_Link || action == .Download || action == .Open ||
	       action == .Reveal || action == .Rename || action == .Delete ||
	       action == .Synchronize
}

@(private)
attachment_action_requires_destination :: proc(action: Attachment_Action) -> bool {
	return action == .Copy || action == .Move || action == .Hard_Link ||
	       action == .Symbolic_Link || action == .Download ||
	       action == .Create_Directory || action == .Rename ||
	       action == .Synchronize
}

@(private)
capture_request_is_valid :: proc(request: Capture_Request) -> bool {
	template := request.template
	return request.operation_id != Operation_ID(0) && resource_identity_is_valid(request.resource) &&
	       scope_is_valid(request.scope) &&
	       semantic_target_is_valid(request.target, request.scope) && request.target.kind == .Heading &&
	       request.rewrite_generation != language.Jan_Rewrite_Generation(0) &&
	       len(request.values) <= MAX_CAPTURE_VALUES && template.applicable &&
	       configuration_text_is_valid(template.identity, MAX_IDENTITY_BYTES) &&
	       template.key != rune(0) && configuration_text_is_valid(template.label, MAX_LABEL_BYTES) &&
	       template.entry_kind != .Invalid && template.source_kind != .Invalid &&
	       (template.source_kind != .Generator || template.generator_admitted) &&
	       capture_text_is_valid(template.source, MAX_TEMPLATE_BYTES) &&
	       template.position != .Invalid && template.empty_lines_before <= 16 &&
	       template.empty_lines_after <= 16 && template.input_limit > 0 &&
	       template.input_limit <= MAX_COPIED_TEXT_BYTES && template.output_limit > 0 &&
	       template.output_limit <= MAX_COPIED_TEXT_BYTES
}

@(private)
capture_value_is_valid :: proc(value: Capture_Value) -> bool {
	return value.kind != .Invalid && value.admitted &&
	       capture_text_is_valid(value.key, MAX_IDENTITY_BYTES) &&
	       len(value.value) <= MAX_FEED_ENTRY_TEXT_BYTES && utf8.valid_string(value.value)
}

@(private)
capture_expand :: proc(
	template: Capture_Template,
	values: []Capture_Value,
	allocator: runtime.Allocator,
) -> (string, u64, bool, Failure_Code) {
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", 0, false, .Allocation_Failed
	defer strings.builder_destroy(&builder)
	for _ in 0 ..< int(template.empty_lines_before) do if strings.write_byte(&builder, '\n') != 1 {
		return "", 0, false, .Allocation_Failed
	}
	cursor_byte := u64(0)
	cursor_found := false
	cursor := 0
	for cursor < len(template.source) {
		if cursor + 2 <= len(template.source) && template.source[cursor:cursor + 2] == "%?" {
			if cursor_found do return "", 0, false, .Conflict
			cursor_byte = u64(strings.builder_len(builder))
			cursor_found = true
			cursor += 2
			continue
		}
		if cursor + 2 <= len(template.source) && template.source[cursor:cursor + 2] == "%{" {
			closing_relative := strings.index_byte(template.source[cursor + 2:], '}')
			if closing_relative < 0 do return "", 0, false, .Malformed
			closing := cursor + 2 + closing_relative
			key := template.source[cursor + 2:closing]
			value, found := capture_value_find(values, key)
			if !found do return "", 0, false, .Unavailable
			if strings.write_string(&builder, value.value) != len(value.value) do return "", 0, false, .Allocation_Failed
			cursor = closing + 1
			continue
		}
		if strings.write_byte(&builder, template.source[cursor]) != 1 do return "", 0, false, .Allocation_Failed
		cursor += 1
	}
	for _ in 0 ..< int(template.empty_lines_after) do if strings.write_byte(&builder, '\n') != 1 {
		return "", 0, false, .Allocation_Failed
	}
	text := strings.to_string(builder)
	if len(text) == 0 || u64(len(text)) > template.output_limit do return "", 0, false, .Limited
	if template.position == .Start do cursor_byte = 0
	if template.position == .End do cursor_byte = u64(len(text))
	if template.position == .Cursor && !cursor_found do return "", 0, false, .Malformed
	owned, allocation_error := strings.clone(text, allocator)
	if allocation_error != nil do return "", 0, false, .Allocation_Failed
	return owned, cursor_byte, true, .None
}

@(private)
capture_value_find :: proc(values: []Capture_Value, key: string) -> (Capture_Value, bool) {
	for value in values do if value.key == key do return value, true
	return {}, false
}

@(private)
capture_session_state :: proc(session: ^Capture_Session) -> ^Capture_Session_State {
	if session == nil || session.state == nil do return nil
	return cast(^Capture_Session_State)session.state
}

@(private)
attachment_request_is_valid :: proc(request: Attachment_Request) -> bool {
	source_required := attachment_action_requires_source(request.action)
	destination_required := attachment_action_requires_destination(request.action)
	return request.operation_id != Operation_ID(0) && request.action != .Invalid &&
	       request.directory_source != .Invalid && scope_is_valid(request.scope) &&
	       semantic_target_is_valid(request.owner, request.scope) && request.owner.kind == .Heading &&
	       (!source_required || resource_identity_is_valid(request.source)) &&
	       (!destination_required || resource_identity_is_valid(request.destination)) &&
	       request.expected_bytes <= MAX_COPIED_TEXT_BYTES && request.attachment_limit > 0 &&
	       request.attachment_limit <= MAX_ATTACHMENT_OUTCOMES
}

@(private)
attachment_link_key_is_valid :: proc(key: string) -> bool {
	return len(key) > 0 && len(key) <= MAX_RESOURCE_BYTES && utf8.valid_string(key) &&
	       !strings.contains_any(key, "\r\n[]")
}

@(private)
attachment_document_rewrite :: proc(
	builder: ^strings.Builder,
	current: string,
	request: Attachment_Request,
	temporary_allocator: runtime.Allocator,
) -> (bool, Failure_Code) {
	source := request.source
	destination := request.destination
	source_key := resource_identity_text(&source)
	destination_key := resource_identity_text(&destination)
	if request.action == .Rename || request.action == .Delete {
		if !attachment_link_key_is_valid(source_key) do return false, .Malformed
		old_builder, old_error := strings.builder_make(temporary_allocator)
		if old_error != nil do return false, .Allocation_Failed
		defer strings.builder_destroy(&old_builder)
		if !attachment_reference_write(&old_builder, source_key) do return false, .Allocation_Failed
		old_reference := strings.to_string(old_builder)
		position := strings.index(current, old_reference)
		if position < 0 do return false, .Unavailable
		if strings.index(current[position + len(old_reference):], old_reference) >= 0 do return false, .Conflict
		replacement_end := position + len(old_reference)
		if strings.write_string(builder, current[:position]) != position do return false, .Allocation_Failed
		if request.action == .Rename {
			if !attachment_link_key_is_valid(destination_key) do return false, .Malformed
			if !attachment_reference_write(builder, destination_key) do return false, .Allocation_Failed
		} else if replacement_end < len(current) && current[replacement_end] == '\n' {
			replacement_end += 1
		}
		if strings.write_string(builder, current[replacement_end:]) != len(current) - replacement_end {
			return false, .Allocation_Failed
		}
		return true, .None
	}
	if !attachment_link_key_is_valid(destination_key) do return false, .Malformed
	reference_builder, reference_error := strings.builder_make(temporary_allocator)
	if reference_error != nil do return false, .Allocation_Failed
	defer strings.builder_destroy(&reference_builder)
	if !attachment_reference_write(&reference_builder, destination_key) do return false, .Allocation_Failed
	reference := strings.to_string(reference_builder)
	if strings.index(current, reference) >= 0 do return false, .Conflict
	if strings.write_string(builder, current) != len(current) ||
	   len(current) > 0 && current[len(current) - 1] != '\n' && strings.write_byte(builder, '\n') != 1 ||
	   strings.write_string(builder, reference) != len(reference) ||
	   strings.write_byte(builder, '\n') != 1 {
		return false, .Allocation_Failed
	}
	return true, .None
}

@(private)
attachment_reference_write :: proc(builder: ^strings.Builder, key: string) -> bool {
	return strings.write_string(builder, "[[attachment:") == len("[[attachment:") &&
	       strings.write_string(builder, key) == len(key) &&
	       strings.write_string(builder, "]]") == len("]]")
}

@(private)
feed_entry_candidate_is_valid :: proc(entry: Feed_Entry_Candidate) -> bool {
	return capture_text_is_valid(entry.identity, MAX_IDENTITY_BYTES) &&
	       capture_text_is_valid(entry.title, MAX_FEED_ENTRY_TEXT_BYTES) &&
	       capture_text_is_valid(entry.link, MAX_RESOURCE_BYTES) &&
	       len(entry.summary) <= MAX_FEED_ENTRY_TEXT_BYTES && utf8.valid_string(entry.summary)
}

@(private)
feed_entry_record_is_valid :: proc(entry: Feed_Entry_Record) -> bool {
	return len(entry.identity) > 0 && len(entry.title) > 0 && len(entry.link) > 0
}

@(private)
capture_text_is_valid :: proc(text: string, limit: int) -> bool {
	return len(text) > 0 && len(text) <= limit && utf8.valid_string(text)
}

@(private)
intake_arena_copy :: proc(arena: []u8, cursor: ^int, text: string) -> string {
	start := cursor^
	copy(arena[start:start + len(text)], text)
	cursor^ += len(text)
	return string(arena[start:cursor^])
}

@(private)
feed_refresh_state :: proc(snapshot: ^Feed_Refresh_Snapshot) -> ^Feed_Refresh_State {
	if snapshot == nil || snapshot.state == nil do return nil
	return cast(^Feed_Refresh_State)snapshot.state
}

@(private)
feed_refresh_state_close :: proc(state: ^Feed_Refresh_State) {
	if state == nil do return
	allocator := state.allocator
	if state.entries != nil do delete(state.entries, allocator)
	if state.retained != nil do delete(state.retained, allocator)
	if state.arena != nil do delete(state.arena, allocator)
	state^ = {}
	free(state, allocator)
}

@(private)
intake_failure :: proc(
	operation_id: Operation_ID,
	kind: Operation_Kind,
	code: Failure_Code,
	field: Failure_Field,
) -> Failure {
	return {operation_id = operation_id, kind = kind, code = code, field = field}
}

@(private)
intake_failure_from_language :: proc(
	operation_id: Operation_ID,
	kind: Operation_Kind,
	failure: language.Jan_Failure,
) -> Failure {
	result := intake_failure(operation_id, kind, .Invalid_Target, .Target)
	#partial switch failure.code {
	case .Stale:             result.code = .Stale
	case .Malformed:         result.code = .Malformed
	case .Limited:           result.code = .Limited
	case .Allocation_Failed: result.code = .Allocation_Failed
	case .Cancelled:         result.code = .Cancelled
	}
	result.limit = failure.limit
	result.actual = failure.actual
	return result
}
