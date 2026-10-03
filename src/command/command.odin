// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package command owns admitted native and Racket command turns.
package command

import "../bridge"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../hosting"
import "../history"
import "../interaction"
import "../kill_ring"
import "../layout"
import "../language"
import "../project"
import "../search"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"

/* MAX_COMMAND_TEXT_BYTES bounds each copied proof-command input and replacement. */
MAX_COMMAND_TEXT_BYTES :: u64(4 * 1024)

/* Editor_Session_ID identifies one native editor coordinator; zero is invalid. */
Editor_Session_ID :: distinct u64

/* Failure_Code classifies command orchestration, runtime, bridge, and publication failures. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Inspection_Limit,
	Temporary_Memory_Limit,
	Racket_Exception,
	Command_Rejected,
	Runtime_Failure,
	Wrong_Result,
	Malformed_Text,
	Cancelled,
	Capability_Failure,
	Publication_Failure,
	Invalid_Command,
	Wrong_Implementation,
	Missing_Text,
	Text_Limit,
	Unknown_Native_Command,
	View_Failure,
	Display_Failure,
	History_Failure,
	Kill_Ring_Failure,
	Region_Unavailable,
	Search_Failure,
	Editor_Session_Failure,
	Project_Scope_Required,
	Project_Duplicate,
	Project_Durability_Failure,
	Project_Promotion_Rejected,
	Project_Promotion_Unresolved,
	Project_Suppression_Rejected,
	Project_Suppression_Unresolved,
	Workspace_Rejected,
	Workspace_Unavailable,
	Workspace_Dirty_Protection,
	Layout_Failure,
}

/*
Failure_Context reports one contained command failure.
The diagnostic view is runtime-owned and expires at the next runtime operation.
*/
Failure_Context :: struct {
	code:            Failure_Code,
	bridge_code:     bridge.Failure_Code,
	hosting_code:    hosting.Failure_Code,
	editor_code:     editor.Failure_Code,
	interaction_code: interaction.Failure_Code,
	view_code:       editor_view.Failure_Code,
	display_code:    display.Failure_Code,
	document_code:   document.Failure_Code,
	transaction_code: edit_transaction.Failure_Code,
	history_code:     history.Failure_Code,
	kill_ring_code:   kill_ring.Failure_Code,
	search_code:      search.Failure_Code,
	editor_session_code: editor_session.Failure_Code,
	project_code:    project.Failure_Code,
	layout_code:     layout.Failure_Code,
	layout_failure:  layout.Failure_Context,
	search_diagnostic: search.Regex_Diagnostic,
	kill_ring_generation: kill_ring.Generation,
	transfer_code:    Transfer_Failure_Code,
	search_capability_code: Search_Capability_Failure_Code,
	buffer_session_capability_code: Buffer_Session_Capability_Failure_Code,
	layout_capability_code: Layout_Capability_Failure_Code,
	structural_capability_code: Structural_Capability_Failure_Code,
	structural_code: Structural_Editor_Failure_Code,
	language_code:   language.Failure_Code,
	policy_field:     history.Policy_Field,
	policy_generation: history.Policy_Generation,
	publication:     document.Publication_State,
	profile_code:    display.Profile_Failure_Code,
	command:         interaction.Command_Handle,
	diagnostic:      string,
	capability:      bridge.Buffer_Capability,
	buffer_id:       editor.Buffer_ID,
	revision:        editor.Revision,
	range:           bridge.Byte_Range,
	minimum:         u64,
	limit:           u64,
	actual:          u64,
}

/* Command_Result retains one checked publication until command_result_close. */
Command_Result :: struct {
	publication:              bridge.Publication_Result,
	inspected_bytes:          u64,
	replacement_bytes:        u64,
}

/* command_result_close releases one retained bridge publication result. */
command_result_close :: proc(result: ^Command_Result) {
	if result == nil {
		return
	}
	bridge.publication_result_close(&result.publication)
}

/*
buffer_command_run executes one Racket request and publishes at most one Odin splice.
All Racket execution ends before the canonical publication call begins.
*/
buffer_command_run :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Buffer_Capability_Registry,
	capability: bridge.Buffer_Capability,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	persistent_allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id: edit_transaction.Undo_Unit_ID,
	cancelled := false,
) -> (result: Command_Result, ok: bool, failure: Failure_Context) {
	assert(racket_runtime != nil)
	assert(registry != nil)
	base_failure := Failure_Context {
		capability = capability,
		buffer_id = buffer_id,
		revision = revision,
	}
	if cancelled {
		base_failure.code = .Cancelled
		return {}, false, base_failure
	}
	if temporary_allocator.procedure == nil {
		base_failure.code = .Temporary_Memory_Limit
		base_failure.limit = MAX_COMMAND_TEXT_BYTES * 2
		return {}, false, base_failure
	}

	request, requested, request_failure := hosting.runtime_command_inspection_request(
		racket_runtime,
		u64(capability),
		u64(buffer_id),
		u64(revision),
	)
	if !requested {
		return {}, false, hosting_failure_context(base_failure, request_failure)
	}
	base_failure.range = bridge.Byte_Range {
		start = editor.Byte_Offset(request.start),
		end = editor.Byte_Offset(request.end),
	}
	if request.start > request.end {
		base_failure.code = .Invalid_Request
		return {}, false, base_failure
	}
	inspection_bytes := request.end - request.start
	if inspection_bytes > MAX_COMMAND_TEXT_BYTES {
		base_failure.code = .Inspection_Limit
		base_failure.limit = MAX_COMMAND_TEXT_BYTES
		base_failure.actual = inspection_bytes
		return {}, false, base_failure
	}

	input, input_error := make([]byte, int(inspection_bytes), temporary_allocator)
	if input_error != nil {
		base_failure.code = .Temporary_Memory_Limit
		base_failure.limit = MAX_COMMAND_TEXT_BYTES * 2
		base_failure.actual = inspection_bytes
		return {}, false, base_failure
	}
	defer delete(input, temporary_allocator)
	_, inspected, inspect_failure := bridge.buffer_capability_inspect(
		registry,
		capability,
		buffer_id,
		revision,
		base_failure.range,
		input,
	)
	if !inspected {
		return {}, false, bridge_failure_context(base_failure, inspect_failure)
	}

	replacement, replacement_error := make(
		[]byte,
		int(MAX_COMMAND_TEXT_BYTES),
		temporary_allocator,
	)
	if replacement_error != nil {
		base_failure.code = .Temporary_Memory_Limit
		base_failure.limit = MAX_COMMAND_TEXT_BYTES * 2
		base_failure.actual = inspection_bytes + MAX_COMMAND_TEXT_BYTES
		return {}, false, base_failure
	}
	defer delete(replacement, temporary_allocator)
	replacement_request, transformed, transform_failure := hosting.runtime_command_transform(
			racket_runtime,
			u64(capability),
			u64(buffer_id),
			u64(revision),
			request,
			input,
			replacement,
		)
	if !transformed {
		return {}, false, hosting_failure_context(base_failure, transform_failure)
	}
	if replacement_request.replacement_bytes > u64(len(replacement)) {
		base_failure.code = .Wrong_Result
		return {}, false, base_failure
	}
	replacement_range := bridge.Byte_Range {
		start = editor.Byte_Offset(replacement_request.start),
		end = editor.Byte_Offset(replacement_request.end),
	}
	base_failure.range = replacement_range
	if cancelled {
		base_failure.code = .Cancelled
		return {}, false, base_failure
	}

	publication, published, publish_failure := bridge.buffer_capability_splice(
		registry,
		capability,
		buffer_id,
		revision,
		replacement_range,
		string(replacement[:replacement_request.replacement_bytes]),
		bridge.Publication_Request {
			transaction_id = transaction_id,
			undo_unit_id = undo_unit_id,
			origin = edit_transaction.Origin{kind = .Racket, descriptor = "checked-bridge"},
			command = "buffer-command",
			persistent_allocator = persistent_allocator,
			temporary_allocator = temporary_allocator,
			cancelled = cancelled,
		},
	)
	if !published {
		return {}, false, bridge_failure_context(base_failure, publish_failure)
	}
	return Command_Result {
		publication = publication,
		inspected_bytes = inspection_bytes,
		replacement_bytes = replacement_request.replacement_bytes,
	}, true, {}
}

/*
buffer_command_shutdown closes an empty capability registry before stopping Racket.
It rejects shutdown while any bridge-owned capability remains live.
*/
buffer_command_shutdown :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^bridge.Buffer_Capability_Registry,
) -> (ok: bool, failure: Failure_Context) {
	assert(racket_runtime != nil)
	assert(registry != nil)
	registry_closed, registry_failure := bridge.buffer_capability_registry_close(registry)
	if !registry_closed {
		return false, bridge_failure_context({}, registry_failure)
	}
	runtime_stopped, runtime_failure := hosting.runtime_shutdown(racket_runtime)
	if !runtime_stopped {
		return false, hosting_failure_context({}, runtime_failure)
	}
	return true, {}
}

@(private)
hosting_failure_context :: proc(
	base: Failure_Context,
	hosting_failure: hosting.Failure_Context,
) -> Failure_Context {
	result := base
	result.hosting_code = hosting_failure.code
	result.diagnostic = hosting_failure.diagnostic
	switch hosting_failure.code {
	case .Racket_Exception:
		result.code = .Racket_Exception
	case .Command_Rejection:
		result.code = .Command_Rejected
	case .Wrong_Result:
		result.code = .Wrong_Result
	case .None:
		result.code = .None
	case .Invalid_State, .Wrong_Thread, .Reentrant_Call, .Runtime_Unavailable:
		result.code = .Runtime_Failure
	}
	return result
}

@(private)
bridge_failure_context :: proc(
	base: Failure_Context,
	bridge_failure: bridge.Failure_Context,
) -> Failure_Context {
	result := base
	result.bridge_code = bridge_failure.code
	result.editor_code = bridge_failure.editor_code
	result.transaction_code = bridge_failure.transaction_code
	result.history_code = bridge_failure.history_code
	result.layout_code = bridge_failure.layout_code
	result.layout_failure = bridge_failure.layout_failure
	result.policy_field = bridge_failure.policy_field
	result.policy_generation = bridge_failure.policy_generation
	result.minimum = bridge_failure.minimum
	result.limit = bridge_failure.limit
	result.actual = bridge_failure.actual
	switch bridge_failure.code {
	case .Malformed_Text:
		result.code = .Malformed_Text
	case .Temporary_Memory_Limit:
		result.code = .Temporary_Memory_Limit
	case .Cancelled:
		result.code = .Cancelled
	case .None:
		result.code = .None
	case .Invalid_Registry,
	     .Wrong_Registry,
	     .Invalid_Capability,
	     .Stale_Capability,
	     .Capacity_Limit,
	     .Retained_Capabilities,
	     .Closed_Buffer,
	     .Wrong_Buffer,
	     .Stale_Revision,
	     .Stale_Generation,
	     .Reversed_Range,
	     .Out_Of_Range,
	     .Inspection_Limit,
	     .Wrong_Thread,
	     .Reentrant_Call,
	     .Wrong_Command,
	     .Wrong_Transaction,
	     .Malformed_Record,
	     .History_Failure,
	     .Layout_Failure,
	     .Policy_Range,
	     .Policy_Relationship,
	     .Retention_Blocked:
		result.code = .Capability_Failure
	case .Editor_Failure:
		result.code = .Publication_Failure
	case .Transaction_Failure:
		#partial switch bridge_failure.transaction_code {
		case .Malformed_UTF8: result.code = .Malformed_Text
		case .Temporary_Memory_Limit: result.code = .Temporary_Memory_Limit
		case .Cancelled: result.code = .Cancelled
		case: result.code = .Publication_Failure
		}
	}
	return result
}
