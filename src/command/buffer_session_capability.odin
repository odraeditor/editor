// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../document"
import "../editor_session"
import "base:runtime"

/* Buffer_Session_Access identifies one independently granted session operation. */
Buffer_Session_Access :: enum u8 {
	Usage_Inspection,
	Descriptor_Inspection,
	Create,
	Open,
	Activate,
	Save,
	Kill,
	Marked_Execution,
}

/* Buffer_Session_Access_Set is the immutable authority granted to one capability. */
Buffer_Session_Access_Set :: bit_set[Buffer_Session_Access; u8]

/* Buffer_Session_Capability_Failure_Code classifies rejection before publication. */
Buffer_Session_Capability_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Permission_Denied,
	Wrong_Authority,
	Wrong_Editor,
	Wrong_Session,
	Stale_Registry,
	Stale_Visible_Target,
	Wrong_Entry,
	Stale_Component,
	Descriptor_Not_Found,
	Temporary_Memory_Limit,
}

/*
Buffer_Session_Capability_Scope is the complete pointer-free session identity
snapshot required by every programmable buffer operation.
*/
Buffer_Session_Capability_Scope :: struct {
	editor_session_id: Editor_Session_ID,
	access:             Buffer_Session_Access_Set,
	session:            editor_session.Session_Handle,
	registry:           editor_session.Registry_Handle,
	visible:            editor_session.Visible_Target,
}

/* Buffer_Session_Capability_Context borrows exact native owners for one turn. */
Buffer_Session_Capability_Context :: struct {
	editor_session_id: Editor_Session_ID,
	access:            Buffer_Session_Access_Set,
	buffer_session:    Buffer_Session_Context,
	temporary_allocator: runtime.Allocator,
	cancelled:         bool,
}

/* Buffer_Session_Usage_Summary is one copied session accounting result. */
Buffer_Session_Usage_Summary :: struct {
	scope: Buffer_Session_Capability_Scope,
	usage: editor_session.Resource_Usage,
}

/* Buffer_Descriptor_Copy owns one copied descriptor and its selection label. */
Buffer_Descriptor_Copy :: struct {
	descriptor: editor_session.Entry_Descriptor,
	label:      []byte,
	allocator:  runtime.Allocator,
}

/* Buffer_Session_Mutation_Result reports a copied outcome and refreshed scope. */
Buffer_Session_Mutation_Result :: struct {
	operation: Buffer_Session_Result,
	scope:     Buffer_Session_Capability_Scope,
}

/* Buffer_Session_Save_Result reports a copied save outcome and refreshed scope. */
Buffer_Session_Save_Result :: struct {
	save:  document.Save_Result,
	scope: Buffer_Session_Capability_Scope,
}

/* Buffer_Session_Kill_Result reports a copied close outcome and refreshed scope. */
Buffer_Session_Kill_Result :: struct {
	kill:  Buffer_Kill_Result,
	scope: Buffer_Session_Capability_Scope,
}

/* Buffer_Session_Marked_Result reports one checked marked batch and refreshed scope. */
Buffer_Session_Marked_Result :: struct {
	execution: Marked_Execution_Result,
	scope:     Buffer_Session_Capability_Scope,
}

/* buffer_session_capability_scope captures the exact live coordinator identity. */
buffer_session_capability_scope :: proc(
	ctx: Buffer_Session_Capability_Context,
) -> (scope: Buffer_Session_Capability_Scope, ok: bool, failure: Failure_Context) {
	if ctx.editor_session_id == Editor_Session_ID(0) || ctx.access == {} ||
	   ctx.buffer_session.session == nil ||
	   !editor_session.session_handle_is_valid(ctx.buffer_session.handle) ||
	   ctx.temporary_allocator.procedure == nil {
		return {}, false, buffer_session_capability_failure(.Invalid_Context)
	}
	if ctx.cancelled {
		return {}, false, Failure_Context{code = .Cancelled}
	}
	registry, registry_ok, session_failure := editor_session.session_registry_handle(
		ctx.buffer_session.session,
		ctx.buffer_session.handle,
	)
	if !registry_ok {
		failure = buffer_session_failure(ctx.buffer_session.command, session_failure)
		failure.buffer_session_capability_code = .Wrong_Session
		return {}, false, failure
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		ctx.buffer_session.session,
		ctx.buffer_session.handle,
	)
	if !visible_ok {
		failure = buffer_session_failure(ctx.buffer_session.command, visible_failure)
		failure.buffer_session_capability_code = .Wrong_Session
		return {}, false, failure
	}
	return Buffer_Session_Capability_Scope {
		editor_session_id = ctx.editor_session_id,
		access = ctx.access,
		session = ctx.buffer_session.handle,
		registry = registry,
		visible = visible,
	}, true, {}
}

/* buffer_session_usage_inspect returns exact copied aggregate accounting. */
buffer_session_usage_inspect :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
) -> (summary: Buffer_Session_Usage_Summary, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Usage_Inspection)
	if !valid {
		return {}, false, validation_failure
	}
	usage, inspected, session_failure := editor_session.session_usage(
		ctx.buffer_session.session,
		actual.session,
	)
	if !inspected {
		return {}, false, buffer_session_failure(ctx.buffer_session.command, session_failure)
	}
	return Buffer_Session_Usage_Summary{scope = actual, usage = usage}, true, {}
}

/* buffer_session_descriptors_inspect returns one bounded owned inventory batch. */
buffer_session_descriptors_inspect :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
) -> (batch: editor_session.Descriptor_Batch, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Descriptor_Inspection)
	if !valid {
		return {}, false, validation_failure
	}
	session_failure: editor_session.Failure_Context
	batch, ok, session_failure = editor_session.session_descriptors(
		ctx.buffer_session.session,
		ctx.buffer_session.handle,
		ctx.temporary_allocator,
	)
	if !ok {
		return {}, false, buffer_session_failure(ctx.buffer_session.command, session_failure)
	}
	return batch, true, {}
}

/* buffer_session_descriptor_inspect copies one exact-generation descriptor. */
buffer_session_descriptor_inspect :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	entry: editor_session.Entry_Handle,
) -> (copied: Buffer_Descriptor_Copy, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Descriptor_Inspection)
	if !valid {
		return {}, false, validation_failure
	}
	if !editor_session.entry_handle_is_valid(entry) || entry.registry != expected.registry {
		return {}, false, buffer_session_capability_failure(.Wrong_Entry)
	}
	batch, inspected, inspect_failure := buffer_session_descriptors_inspect(ctx, expected)
	if !inspected {
		return {}, false, inspect_failure
	}
	defer editor_session.descriptor_batch_close(&batch)
	for descriptor in batch.descriptors {
		if descriptor.graph.entry != entry {
			continue
		}
		label, allocation_error := make([]byte, len(descriptor.selection_label), ctx.temporary_allocator)
		if allocation_error != nil {
			return {}, false, buffer_session_capability_failure(.Temporary_Memory_Limit)
		}
		copy(label, transmute([]u8)descriptor.selection_label)
		copied = Buffer_Descriptor_Copy {
			descriptor = descriptor,
			label = label,
			allocator = ctx.temporary_allocator,
		}
		copied.descriptor.selection_label = string(copied.label)
		return copied, true, {}
	}
	return {}, false, buffer_session_capability_failure(.Descriptor_Not_Found)
}

/* buffer_descriptor_copy_close releases one copied descriptor label. */
buffer_descriptor_copy_close :: proc(copied: ^Buffer_Descriptor_Copy) {
	if copied == nil {
		return
	}
	if copied.allocator.procedure != nil {
		delete(copied.label, copied.allocator)
	}
	copied^ = {}
}

/* buffer_session_capability_create admits one named unassociated buffer. */
buffer_session_capability_create :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	name: string,
) -> (result: Buffer_Session_Mutation_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Create)
	if !valid {
		return {}, false, validation_failure
	}
	operation, changed, operation_failure := buffer_session_switch_to_buffer(ctx.buffer_session, name)
	if !changed {
		return {}, false, operation_failure
	}
	return buffer_session_mutation_result(ctx, operation)
}

/* buffer_session_capability_open prepares and admits one local path or reuses it. */
buffer_session_capability_open :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	path: string,
) -> (result: Buffer_Session_Mutation_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Open)
	if !valid {
		return {}, false, validation_failure
	}
	operation, changed, operation_failure := buffer_session_find_file(ctx.buffer_session, path)
	if !changed {
		return {}, false, operation_failure
	}
	return buffer_session_mutation_result(ctx, operation)
}

/* buffer_session_capability_activate selects one exact live entry generation. */
buffer_session_capability_activate :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	entry: editor_session.Entry_Handle,
) -> (result: Buffer_Session_Mutation_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Activate)
	if !valid {
		return {}, false, validation_failure
	}
	if !editor_session.entry_handle_is_valid(entry) || entry.registry != expected.registry {
		return {}, false, buffer_session_capability_failure(.Wrong_Entry)
	}
	activation, activated, session_failure := editor_session.session_activate(
		ctx.buffer_session.session,
		entry,
	)
	if !activated {
		failure = buffer_session_failure(ctx.buffer_session.command, session_failure)
		failure.buffer_session_capability_code = .Wrong_Entry
		return {}, false, failure
	}
	completion := Buffer_Session_Completion.Activated
	if !activation.changed {
		completion = .Already_Active
	}
	return buffer_session_mutation_result(
		ctx,
		Buffer_Session_Result {
			completion = completion,
			entry = activation.entry,
			visible = activation.visible,
		},
	)
}

/* buffer_session_capability_save admits one associated or first-save operation. */
buffer_session_capability_save :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	entry: editor_session.Entry_Handle,
	first_save_path := "",
) -> (result: Buffer_Session_Save_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Save)
	if !valid {
		return {}, false, validation_failure
	}
	if !editor_session.entry_handle_is_valid(entry) || entry.registry != expected.registry {
		return {}, false, buffer_session_capability_failure(.Wrong_Entry)
	}
	save, saved, save_failure := buffer_session_save_entry(ctx.buffer_session, entry, first_save_path)
	if !saved {
		return {}, false, save_failure
	}
	refreshed, refreshed_ok, refresh_failure := buffer_session_capability_scope(ctx)
	if !refreshed_ok {
		return {}, false, refresh_failure
	}
	return Buffer_Session_Save_Result{save = save, scope = refreshed}, true, {}
}

/* buffer_session_capability_kill admits one exact entry close with explicit authority. */
buffer_session_capability_kill :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	entry: editor_session.Entry_Handle,
	authority := editor_session.Close_Authority.Preserve_Modified,
) -> (result: Buffer_Session_Kill_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Kill)
	if !valid {
		return {}, false, validation_failure
	}
	if !editor_session.entry_handle_is_valid(entry) || entry.registry != expected.registry {
		return {}, false, buffer_session_capability_failure(.Wrong_Entry)
	}
	closure, closed, session_failure := editor_session.session_close_buffer(
		ctx.buffer_session.session,
		editor_session.Close_Buffer_Request{entry = entry, authority = authority},
	)
	if !closed {
		return {}, false, buffer_session_failure(ctx.buffer_session.command, session_failure)
	}
	completion := Buffer_Kill_Completion.Closed
	if closure.outcome == .Discard_Required {
		completion = .Discard_Required
	}
	refreshed, refreshed_ok, refresh_failure := buffer_session_capability_scope(ctx)
	if !refreshed_ok {
		return {}, false, refresh_failure
	}
	return Buffer_Session_Kill_Result {
		kill = Buffer_Kill_Result{completion = completion, closure = closure},
		scope = refreshed,
	}, true, {}
}

/* buffer_session_capability_execute_marks executes one copied semantic mark set. */
buffer_session_capability_execute_marks :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	marks: []Buffer_Marked_Entry,
	decisions: []Marked_Entry_Decision,
) -> (result: Buffer_Session_Marked_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := buffer_session_capability_validate(ctx, expected, .Marked_Execution)
	if !valid {
		return {}, false, validation_failure
	}
	execution, executed, execute_failure := buffer_session_execute_buffer_marks(
		Buffer_Marked_Execution_Context {
			buffer_session = ctx.buffer_session,
			decisions = decisions,
		},
		marks,
	)
	if !executed {
		return {}, false, execute_failure
	}
	refreshed, refreshed_ok, refresh_failure := buffer_session_capability_scope(ctx)
	if !refreshed_ok {
		return {}, false, refresh_failure
	}
	return Buffer_Session_Marked_Result{execution = execution, scope = refreshed}, true, {}
}

@(private)
buffer_session_capability_validate :: proc(
	ctx: Buffer_Session_Capability_Context,
	expected: Buffer_Session_Capability_Scope,
	required: Buffer_Session_Access,
) -> (actual: Buffer_Session_Capability_Scope, ok: bool, failure: Failure_Context) {
	actual, ok, failure = buffer_session_capability_scope(ctx)
	if !ok {
		return {}, false, failure
	}
	if required not_in actual.access {
		return {}, false, buffer_session_capability_failure(.Permission_Denied)
	}
	if expected.access != actual.access {
		return {}, false, buffer_session_capability_failure(.Wrong_Authority)
	}
	if expected.editor_session_id != actual.editor_session_id {
		return {}, false, buffer_session_capability_failure(.Wrong_Editor)
	}
	if expected.session != actual.session {
		return {}, false, buffer_session_capability_failure(.Wrong_Session)
	}
	if expected.registry != actual.registry {
		return {}, false, buffer_session_capability_failure(.Stale_Registry)
	}
	if expected.visible != actual.visible {
		return {}, false, buffer_session_capability_failure(.Stale_Visible_Target)
	}
	return actual, true, {}
}

@(private)
buffer_session_mutation_result :: proc(
	ctx: Buffer_Session_Capability_Context,
	operation: Buffer_Session_Result,
) -> (result: Buffer_Session_Mutation_Result, ok: bool, failure: Failure_Context) {
	refreshed, refreshed_ok, refresh_failure := buffer_session_capability_scope(ctx)
	if !refreshed_ok {
		return {}, false, refresh_failure
	}
	return Buffer_Session_Mutation_Result{operation = operation, scope = refreshed}, true, {}
}

@(private)
buffer_session_capability_failure :: proc(
	code: Buffer_Session_Capability_Failure_Code,
) -> Failure_Context {
	return Failure_Context{code = .Capability_Failure, buffer_session_capability_code = code}
}
