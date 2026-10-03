// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../interaction"
import "../kill_ring"
import editor_view "../view"
import "base:runtime"

/* Transfer_Access identifies one independently granted programmable operation. */
Transfer_Access :: enum u8 {
	Region_Inspection,
	Ring_Inspection,
	Entry_Text,
	Semantic_Invocation,
}

/* Transfer_Access_Set is the immutable authority granted to one native capability. */
Transfer_Access_Set :: bit_set[Transfer_Access; u8]

/* Transfer_Failure_Code classifies native capability rejection before any effect. */
Transfer_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Permission_Denied,
	Wrong_Authority,
	Wrong_Editor,
	Wrong_View,
	Stale_View_State,
	Wrong_Buffer,
	Stale_Revision,
	Wrong_Ring,
	Stale_Ring_Generation,
	Stale_Command_Registry,
	Command_Not_Allowed,
}

/*
Transfer_Capability_Scope is the complete pointer-free identity snapshot for one
programmable transfer turn. Every operation must present this exact scope.
*/
Transfer_Capability_Scope :: struct {
	editor_session_id:          Editor_Session_ID,
	access:                     Transfer_Access_Set,
	view:                       editor_view.View_Handle,
	view_state_generation:      u64,
	buffer_id:                   editor.Buffer_ID,
	revision:                    editor.Revision,
	ring_id:                     kill_ring.Ring_ID,
	ring_generation:             kill_ring.Generation,
	command_registry_generation: interaction.Registry_Generation,
}

/*
Transfer_Capability_Context borrows native owners for one bounded programmable turn.
The caller keeps every referenced owner alive and stable for the complete call.
*/
Transfer_Capability_Context :: struct {
	editor_session_id: Editor_Session_ID,
	access:            Transfer_Access_Set,
	native:            Native_Context,
}

/* Transfer_Region_Summary is a copied logical point, mark, activation, and range value. */
Transfer_Region_Summary :: struct {
	scope:          Transfer_Capability_Scope,
	point:          editor.Position,
	mark_present:   bool,
	mark:           editor.Position,
	region_active:  bool,
	region_present: bool,
	region_start:   editor.Byte_Offset,
	region_end:     editor.Byte_Offset,
}

/* Transfer_Ring_Summary owns bounded copied newest-to-oldest entry metadata. */
Transfer_Ring_Summary :: struct {
	scope:      Transfer_Capability_Scope,
	inspection: kill_ring.Inspection,
}

/* Transfer_Entry_Text owns one authorized copied retained entry. */
Transfer_Entry_Text :: struct {
	scope: Transfer_Capability_Scope,
	entry: kill_ring.Entry_Copy,
}

/* Transfer_Command_Request invokes one admitted stable semantic command name. */
Transfer_Command_Request :: struct {
	expected_scope: Transfer_Capability_Scope,
	name:           string,
}

/* Transfer_Command_Result owns the native result and reports the post-command scope. */
Transfer_Command_Result :: struct {
	native:       Native_Result,
	result_scope: Transfer_Capability_Scope,
}

/* transfer_capability_scope captures the exact live identity of every native owner. */
transfer_capability_scope :: proc(
	ctx: Transfer_Capability_Context,
) -> (scope: Transfer_Capability_Scope, ok: bool, failure: Failure_Context) {
	if ctx.editor_session_id == Editor_Session_ID(0) || ctx.access == {} ||
	   ctx.native.registry == nil || ctx.native.buffer == nil ||
	   ctx.native.view_registry == nil || ctx.native.kill_ring == nil ||
	   ctx.native.temporary_allocator.procedure == nil {
		return {}, false, transfer_failure(.Invalid_Context)
	}
	if ctx.native.cancelled {
		return {}, false, Failure_Context{code = .Cancelled}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure = native_view_failure(ctx.native.command, logical_failure)
		failure.transfer_code = .Wrong_View
		return {}, false, failure
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(ctx.native.buffer)
	if !buffer_ok {
		failure = native_editor_failure(ctx.native.command, buffer_failure)
		failure.transfer_code = .Wrong_Buffer
		return {}, false, failure
	}
	if logical.buffer_id != buffer_stats.buffer_id {
		failure = transfer_failure(.Wrong_Buffer)
		failure.buffer_id = buffer_stats.buffer_id
		return {}, false, failure
	}
	if logical.revision != buffer_stats.revision {
		failure = transfer_failure(.Stale_Revision)
		failure.buffer_id = buffer_stats.buffer_id
		failure.revision = logical.revision
		failure.actual = u64(buffer_stats.revision)
		return {}, false, failure
	}
	ring_stats, ring_ok, ring_failure := kill_ring.ring_stats(ctx.native.kill_ring)
	if !ring_ok {
		failure = native_kill_ring_failure(ctx.native.command, ring_failure)
		failure.transfer_code = .Wrong_Ring
		return {}, false, failure
	}
	registry_stats, registry_ok, registry_failure := interaction.command_registry_stats(
		ctx.native.registry,
	)
	if !registry_ok {
		return {}, false, Failure_Context {
			code = .Capability_Failure,
			transfer_code = .Stale_Command_Registry,
			interaction_code = registry_failure.code,
		}
	}
	return Transfer_Capability_Scope {
		editor_session_id = ctx.editor_session_id,
		access = ctx.access,
		view = ctx.native.view,
		view_state_generation = logical.state_generation,
		buffer_id = buffer_stats.buffer_id,
		revision = buffer_stats.revision,
		ring_id = ring_stats.ring_id,
		ring_generation = ring_stats.generation,
		command_registry_generation = registry_stats.generation,
	}, true, {}
}

/* transfer_region_inspect returns one copied logical region summary after exact validation. */
transfer_region_inspect :: proc(
	ctx: Transfer_Capability_Context,
	expected_scope: Transfer_Capability_Scope,
) -> (summary: Transfer_Region_Summary, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := transfer_capability_validate(
		ctx,
		expected_scope,
		.Region_Inspection,
	)
	if !valid {
		return {}, false, validation_failure
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	assert(logical_ok, "validated transfer view became unavailable")
	if !logical_ok {
		return {}, false, native_view_failure(ctx.native.command, logical_failure)
	}
	summary = Transfer_Region_Summary {
		scope = actual,
		point = logical.point_position,
		mark_present = logical.mark.present,
		region_active = logical.region_active,
		region_present = logical.mark.present,
	}
	if logical.mark.present {
		summary.mark = logical.mark.position
		summary.region_start = logical.point_position.byte_offset
		summary.region_end = logical.mark.position.byte_offset
		if summary.region_start > summary.region_end {
			summary.region_start, summary.region_end = summary.region_end, summary.region_start
		}
	}
	return summary, true, {}
}

/* transfer_ring_inspect returns bounded copied metadata without exposing ring storage. */
transfer_ring_inspect :: proc(
	ctx: Transfer_Capability_Context,
	expected_scope: Transfer_Capability_Scope,
	entry_limit: u64,
) -> (summary: Transfer_Ring_Summary, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := transfer_capability_validate(
		ctx,
		expected_scope,
		.Ring_Inspection,
	)
	if !valid {
		return {}, false, validation_failure
	}
	inspection, inspected, ring_failure := kill_ring.ring_inspect(
		ctx.native.kill_ring,
		kill_ring.Inspection_Request {
			expected_generation = actual.ring_generation,
			entry_limit = entry_limit,
		},
		ctx.native.temporary_allocator,
	)
	if !inspected {
		return {}, false, native_kill_ring_failure(ctx.native.command, ring_failure)
	}
	return Transfer_Ring_Summary{scope = actual, inspection = inspection}, true, {}
}

/* transfer_ring_summary_close releases one copied metadata summary. */
transfer_ring_summary_close :: proc(
	summary: ^Transfer_Ring_Summary,
	temporary_allocator: runtime.Allocator,
) {
	if summary == nil {
		return
	}
	kill_ring.inspection_release(&summary.inspection, temporary_allocator)
	summary^ = {}
}

/* transfer_entry_text copies one authorized retained entry under the requested byte limit. */
transfer_entry_text :: proc(
	ctx: Transfer_Capability_Context,
	expected_scope: Transfer_Capability_Scope,
	entry_id: kill_ring.Entry_ID,
	byte_limit: u64,
) -> (copied: Transfer_Entry_Text, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := transfer_capability_validate(
		ctx,
		expected_scope,
		.Entry_Text,
	)
	if !valid {
		return {}, false, validation_failure
	}
	entry, entry_ok, ring_failure := kill_ring.entry_copy(
		ctx.native.kill_ring,
		kill_ring.Entry_Copy_Request {
			expected_generation = actual.ring_generation,
			entry_id = entry_id,
			byte_limit = byte_limit,
		},
		ctx.native.temporary_allocator,
	)
	if !entry_ok {
		return {}, false, native_kill_ring_failure(ctx.native.command, ring_failure)
	}
	return Transfer_Entry_Text{scope = actual, entry = entry}, true, {}
}

/* transfer_entry_text_close releases one authorized copied entry. */
transfer_entry_text_close :: proc(
	copied: ^Transfer_Entry_Text,
	temporary_allocator: runtime.Allocator,
) {
	if copied == nil {
		return
	}
	kill_ring.entry_copy_release(&copied.entry, temporary_allocator)
	copied^ = {}
}

/*
transfer_command_invoke resolves and executes one admitted region or transfer command.
The expected scope is checked before lookup or mutation and the returned scope reflects
the complete successful command result.
*/
transfer_command_invoke :: proc(
	ctx: Transfer_Capability_Context,
	request: Transfer_Command_Request,
) -> (result: Transfer_Command_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := transfer_capability_validate(
		ctx,
		request.expected_scope,
		.Semantic_Invocation,
	)
	if !valid {
		return {}, false, validation_failure
	}
	handle, found, lookup_failure := interaction.command_lookup(
		ctx.native.registry,
		request.name,
	)
	if !found {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			transfer_code = .Command_Not_Allowed,
			interaction_code = lookup_failure.code,
		}
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(ctx.native.registry, handle)
	route, route_ok := native_route_decode(metadata.route)
	if !metadata_ok || !route_ok || !transfer_command_is_admitted(route) {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			transfer_code = .Command_Not_Allowed,
			interaction_code = metadata_failure.code,
		}
	}
	native_request := ctx.native
	native_request.command = handle
	native_request.text = ""
	native_result, executed, execute_failure := native_command_execute(native_request)
	if !executed {
		return {}, false, execute_failure
	}
	result_scope, refreshed, refresh_failure := transfer_capability_scope(ctx)
	assert(refreshed, "successful transfer command invalidated its native owners")
	if !refreshed {
		native_result_close(&native_result)
		return {}, false, refresh_failure
	}
	return Transfer_Command_Result {
		native = native_result,
		result_scope = result_scope,
	}, true, {}
}

/* transfer_command_result_close releases retained native transaction result storage. */
transfer_command_result_close :: proc(result: ^Transfer_Command_Result) {
	if result == nil {
		return
	}
	native_result_close(&result.native)
	result.result_scope = {}
}

@(private)
transfer_capability_validate :: proc(
	ctx: Transfer_Capability_Context,
	expected: Transfer_Capability_Scope,
	required: Transfer_Access,
) -> (actual: Transfer_Capability_Scope, ok: bool, failure: Failure_Context) {
	actual, ok, failure = transfer_capability_scope(ctx)
	if !ok {
		return {}, false, failure
	}
	if required not_in actual.access {
		return {}, false, transfer_failure(.Permission_Denied)
	}
	if expected.access != actual.access {
		return {}, false, transfer_failure(.Wrong_Authority)
	}
	if expected.editor_session_id != actual.editor_session_id {
		failure = transfer_failure(.Wrong_Editor)
		failure.limit = u64(expected.editor_session_id)
		failure.actual = u64(actual.editor_session_id)
		return {}, false, failure
	}
	if expected.view != actual.view {
		return {}, false, transfer_failure(.Wrong_View)
	}
	if expected.view_state_generation != actual.view_state_generation {
		failure = transfer_failure(.Stale_View_State)
		failure.limit = expected.view_state_generation
		failure.actual = actual.view_state_generation
		return {}, false, failure
	}
	if expected.buffer_id != actual.buffer_id {
		failure = transfer_failure(.Wrong_Buffer)
		failure.buffer_id = expected.buffer_id
		failure.actual = u64(actual.buffer_id)
		return {}, false, failure
	}
	if expected.revision != actual.revision {
		failure = transfer_failure(.Stale_Revision)
		failure.buffer_id = actual.buffer_id
		failure.revision = expected.revision
		failure.actual = u64(actual.revision)
		return {}, false, failure
	}
	if expected.ring_id != actual.ring_id {
		return {}, false, transfer_failure(.Wrong_Ring)
	}
	if expected.ring_generation != actual.ring_generation {
		failure = transfer_failure(.Stale_Ring_Generation)
		failure.kill_ring_generation = actual.ring_generation
		failure.limit = u64(expected.ring_generation)
		failure.actual = u64(actual.ring_generation)
		return {}, false, failure
	}
	if expected.command_registry_generation != actual.command_registry_generation {
		failure = transfer_failure(.Stale_Command_Registry)
		failure.limit = u64(expected.command_registry_generation)
		failure.actual = u64(actual.command_registry_generation)
		return {}, false, failure
	}
	return actual, true, {}
}

@(private)
transfer_command_is_admitted :: proc(route: Native_Route) -> bool {
	#partial switch route {
	case .Set_Mark,
	     .Deactivate_Mark,
	     .Exchange_Point_And_Mark,
	     .Copy_Region,
	     .Kill_Region,
	     .Delete_Region,
	     .Yank,
	     .Yank_Pop:
		return true
	}
	return false
}

@(private)
transfer_failure :: proc(code: Transfer_Failure_Code) -> Failure_Context {
	return Failure_Context{code = .Capability_Failure, transfer_code = code}
}
