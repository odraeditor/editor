// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "../language"
import editor_view "../view"

/* Structural_Access identifies one independently granted structural operation. */
Structural_Access :: enum u8 {
	Invalid,
	Inspect,
	Forward,
	Backward,
	Up,
	Down,
	Select,
	Indent,
	Definition,
}

/* Structural_Access_Set is immutable authority for one programmable turn. */
Structural_Access_Set :: bit_set[Structural_Access; u16]

/* Structural_Capability_Failure_Code classifies rejection before semantic execution. */
Structural_Capability_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Permission_Denied,
	Wrong_Authority,
	Wrong_Editor_Session,
	Wrong_View,
	Stale_View_State,
	Wrong_Buffer,
	Stale_Revision,
	Stale_Selection,
	Stale_Analysis,
	Stale_Command_Registry,
	Stale_Capability,
}

/* Structural_Capability_Scope is complete pointer-free programmable authority. */
Structural_Capability_Scope :: struct {
	editor_session_id:           Editor_Session_ID,
	access:                      Structural_Access_Set,
	editor:                      Structural_Editor_Scope,
	command_registry_generation: interaction.Registry_Generation,
	capability_generation:       u64,
}

/* Structural_Capability_State retains copied inspection state without foreign objects. */
Structural_Capability_State :: struct {
	last_target:      language.Structural_Target,
	plan_start:       u64,
	plan_end:         u64,
	plan_edit_count:  u64,
	last_operation:   language.Structural_Operation,
	last_completion:  Native_Completion,
	last_changed:     bool,
	usage:            language.Structural_Usage,
	latest_failure:   Failure_Context,
	diagnostic:       [language.MAX_DIAGNOSTIC_BYTES]u8,
	diagnostic_length: u16,
}

/* Structural_Capability_Context borrows native owners behind one exact scope. */
Structural_Capability_Context :: struct {
	editor_session_id:     Editor_Session_ID,
	access:                Structural_Access_Set,
	capability_generation: u64,
	editor:                Structural_Editor_Context,
	state:                 ^Structural_Capability_State,
}

/* Structural_Capability_Outcome is one copied refreshed semantic result. */
Structural_Capability_Outcome :: struct {
	scope:          Structural_Capability_Scope,
	operation:      language.Structural_Operation,
	completion:     Native_Completion,
	changed:        bool,
	point:          u64,
	mark:           u64,
	region_active:  bool,
	transaction_id: u64,
	undo_unit_id:   u64,
	usage:          language.Structural_Usage,
}

/* Structural_Capability_Result owns any retained native structural result. */
Structural_Capability_Result :: struct {
	outcome: Structural_Capability_Outcome,
	editor:  Structural_Editor_Result,
}

/* Structural_Capability_Inspection is copied current and last-operation state. */
Structural_Capability_Inspection :: struct {
	scope:           Structural_Capability_Scope,
	target:          language.Structural_Target,
	plan_start:      u64,
	plan_end:        u64,
	plan_edit_count: u64,
	outcome:         Structural_Capability_Outcome,
	usage:           language.Structural_Usage,
	failure:         Failure_Context,
	diagnostic:      string,
}

/* structural_capability_result_close releases retained native result storage. */
structural_capability_result_close :: proc(result: ^Structural_Capability_Result) {
	if result == nil do return
	structural_editor_result_close(&result.editor)
	result^ = {}
}

/* structural_capability_scope captures exact editor, analysis, registry, and authority state. */
structural_capability_scope :: proc(
	ctx: Structural_Capability_Context,
) -> (scope: Structural_Capability_Scope, ok: bool, failure: Failure_Context) {
	if ctx.editor_session_id == Editor_Session_ID(0) || ctx.access == {} ||
	   ctx.capability_generation == 0 || ctx.state == nil || ctx.editor.native.registry == nil {
		return {}, false, structural_capability_failure(.Invalid_Context)
	}
	editor_scope, scoped, editor_failure := structural_editor_scope(ctx.editor)
	if !scoped do return {}, false, editor_failure
	registry, registry_ok, registry_failure := interaction.command_registry_stats(
		ctx.editor.native.registry,
	)
	if !registry_ok {
		failure = structural_capability_failure(.Stale_Command_Registry)
		failure.interaction_code = registry_failure.code
		return {}, false, failure
	}
	return Structural_Capability_Scope {
		editor_session_id = ctx.editor_session_id,
		access = ctx.access,
		editor = editor_scope,
		command_registry_generation = registry.generation,
		capability_generation = ctx.capability_generation,
	}, true, {}
}

/* structural_capability_inspect returns copied state without triggering analysis. */
structural_capability_inspect :: proc(
	ctx: Structural_Capability_Context,
	expected: Structural_Capability_Scope,
) -> (inspection: Structural_Capability_Inspection, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := structural_capability_validate(ctx, expected, .Inspect)
	if !valid do return {}, false, validation_failure
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.editor.native.view_registry,
		ctx.editor.native.view,
	)
	if !logical_ok do return {}, false, native_view_failure(ctx.editor.native.command, logical_failure)
	outcome := structural_capability_current_outcome(actual, logical, ctx.state)
	diagnostic := string(ctx.state.diagnostic[:ctx.state.diagnostic_length])
	return Structural_Capability_Inspection {
		scope = actual,
		target = ctx.state.last_target,
		plan_start = ctx.state.plan_start,
		plan_end = ctx.state.plan_end,
		plan_edit_count = ctx.state.plan_edit_count,
		outcome = outcome,
		usage = ctx.state.usage,
		failure = ctx.state.latest_failure,
		diagnostic = diagnostic,
	}, true, {}
}

/* structural_capability_invoke validates authority and runs one semantic operation. */
structural_capability_invoke :: proc(
	ctx: Structural_Capability_Context,
	expected: Structural_Capability_Scope,
	operation: language.Structural_Operation,
) -> (result: Structural_Capability_Result, ok: bool, failure: Failure_Context) {
	access, access_ok := structural_operation_access(operation)
	if !access_ok do return {}, false, structural_capability_failure(.Permission_Denied)
	actual, valid, validation_failure := structural_capability_validate(ctx, expected, access)
	if !valid do return {}, false, validation_failure
	before, before_ok, before_failure := editor_view.snapshot(
		ctx.editor.native.view_registry,
		ctx.editor.native.view,
	)
	if !before_ok do return {}, false, native_view_failure(ctx.editor.native.command, before_failure)
	editor_result, executed, editor_failure := structural_editor_run(
		ctx.editor,
		Structural_Editor_Request{expected_scope = actual.editor, operation = operation},
	)
	if !executed do return {}, false, editor_failure
	after, after_ok, after_failure := editor_view.snapshot(
		ctx.editor.native.view_registry,
		ctx.editor.native.view,
	)
	if !after_ok {
		structural_editor_result_close(&editor_result)
		return {}, false, native_view_failure(ctx.editor.native.command, after_failure)
	}
	refreshed := actual
	refreshed.editor = editor_result.result_scope
	outcome := structural_capability_outcome(refreshed, after, editor_result)
	ctx.state.last_operation = operation
	ctx.state.last_completion = editor_result.native.completion
	ctx.state.last_changed = editor_result.native.completion != .No_Op
	ctx.state.usage = editor_result.usage
	ctx.state.latest_failure = {}
	ctx.state.diagnostic_length = 0
	if operation == .Indent {
		ctx.state.last_target = {}
		ctx.state.plan_start = u64(min(before.point_position.byte_offset, before.mark.position.byte_offset))
		ctx.state.plan_end = u64(max(before.point_position.byte_offset, before.mark.position.byte_offset))
		if !before.region_active || !before.mark.present {
			ctx.state.plan_start = u64(before.point_position.byte_offset)
			ctx.state.plan_end = u64(before.point_position.byte_offset)
		}
		ctx.state.plan_edit_count = u64(editor_result.usage.indent_lines)
	} else {
		ctx.state.last_target = editor_result.target
		ctx.state.plan_start = 0
		ctx.state.plan_end = 0
		ctx.state.plan_edit_count = 0
	}
	return Structural_Capability_Result{outcome = outcome, editor = editor_result}, true, {}
}

/* structural_capability_record_failure retains bounded copied rejection context. */
structural_capability_record_failure :: proc(
	state: ^Structural_Capability_State,
	operation: language.Structural_Operation,
	failure: Failure_Context,
) {
	if state == nil do return
	state.latest_failure = failure
	state.latest_failure.diagnostic = ""
	state.last_operation = operation
	message := structural_capability_failure_message(failure)
	length := min(len(message), len(state.diagnostic))
	copy(state.diagnostic[:length], transmute([]u8)message)
	state.diagnostic_length = u16(length)
}

@(private)
structural_capability_validate :: proc(
	ctx: Structural_Capability_Context,
	expected: Structural_Capability_Scope,
	required: Structural_Access,
) -> (actual: Structural_Capability_Scope, ok: bool, failure: Failure_Context) {
	current, scoped, scope_failure := structural_capability_scope(ctx)
	if !scoped do return {}, false, scope_failure
	actual = current
	if required not_in ctx.access do return {}, false, structural_capability_failure(.Permission_Denied)
	if expected.access != actual.access {
		failure = structural_capability_failure(.Wrong_Authority)
		failure.limit = u64(transmute(u16)expected.access)
		failure.actual = u64(transmute(u16)actual.access)
		return {}, false, failure
	}
	if expected.editor_session_id != actual.editor_session_id {
		failure = structural_capability_failure(.Wrong_Editor_Session)
		failure.limit = u64(expected.editor_session_id)
		failure.actual = u64(actual.editor_session_id)
		return {}, false, failure
	}
	if expected.capability_generation != actual.capability_generation {
		failure = structural_capability_failure(.Stale_Capability)
		failure.limit = expected.capability_generation
		failure.actual = actual.capability_generation
		return {}, false, failure
	}
	if expected.command_registry_generation != actual.command_registry_generation {
		failure = structural_capability_failure(.Stale_Command_Registry)
		failure.limit = u64(expected.command_registry_generation)
		failure.actual = u64(actual.command_registry_generation)
		return {}, false, failure
	}
	if expected.editor != actual.editor {
		failure = structural_editor_scope_mismatch(expected.editor, actual.editor)
		#partial switch failure.structural_code {
		case .Wrong_View: failure.structural_capability_code = .Wrong_View
		case .Stale_View_State: failure.structural_capability_code = .Stale_View_State
		case .Wrong_Buffer: failure.structural_capability_code = .Wrong_Buffer
		case .Stale_Revision: failure.structural_capability_code = .Stale_Revision
		case .Stale_Selection: failure.structural_capability_code = .Stale_Selection
		case .Stale_Analysis: failure.structural_capability_code = .Stale_Analysis
		}
		failure.limit = u64(expected.editor.revision)
		failure.actual = u64(actual.editor.revision)
		return {}, false, failure
	}
	return actual, true, {}
}

@(private)
structural_operation_access :: proc(
	operation: language.Structural_Operation,
) -> (Structural_Access, bool) {
	switch operation {
	case .Forward: return .Forward, true
	case .Backward: return .Backward, true
	case .Up: return .Up, true
	case .Down: return .Down, true
	case .Select: return .Select, true
	case .Indent: return .Indent, true
	case .Definition: return .Definition, true
	case .Invalid: return .Invalid, false
	}
	unreachable()
}

@(private)
structural_capability_outcome :: proc(
	scope: Structural_Capability_Scope,
	logical: editor_view.Snapshot,
	result: Structural_Editor_Result,
) -> Structural_Capability_Outcome {
	mark := logical.point_position.byte_offset
	if logical.mark.present do mark = logical.mark.position.byte_offset
	return Structural_Capability_Outcome {
		scope = scope,
		operation = result.operation,
		completion = result.native.completion,
		changed = result.native.completion != .No_Op,
		point = u64(logical.point_position.byte_offset),
		mark = u64(mark),
		region_active = logical.region_active,
		transaction_id = u64(result.result_scope.transaction_id),
		undo_unit_id = u64(result.result_scope.undo_unit_id),
		usage = result.usage,
	}
}

@(private)
structural_capability_current_outcome :: proc(
	scope: Structural_Capability_Scope,
	logical: editor_view.Snapshot,
	state: ^Structural_Capability_State,
) -> Structural_Capability_Outcome {
	mark := logical.point_position.byte_offset
	if logical.mark.present do mark = logical.mark.position.byte_offset
	return Structural_Capability_Outcome {
		scope = scope,
		operation = state.last_operation,
		completion = state.last_completion,
		changed = state.last_changed,
		point = u64(logical.point_position.byte_offset),
		mark = u64(mark),
		region_active = logical.region_active,
		transaction_id = u64(scope.editor.transaction_id),
		undo_unit_id = u64(scope.editor.undo_unit_id),
		usage = state.usage,
	}
}

@(private)
structural_capability_failure :: proc(
	code: Structural_Capability_Failure_Code,
) -> Failure_Context {
	return Failure_Context {
		code = .Capability_Failure,
		structural_capability_code = code,
	}
}

@(private)
structural_capability_failure_message :: proc(failure: Failure_Context) -> string {
	if len(failure.diagnostic) != 0 do return failure.diagnostic
	if failure.language_code != .None do return "structural language analysis rejected the request"
	switch failure.structural_capability_code {
	case .Permission_Denied: return "structural capability permission denied"
	case .Wrong_Authority: return "structural capability authority changed"
	case .Wrong_Editor_Session: return "structural editor session changed"
	case .Stale_Command_Registry: return "structural command registry generation changed"
	case .Stale_Capability: return "structural capability generation changed"
	case .Invalid_Context: return "structural capability context is invalid"
	case .None, .Wrong_View, .Stale_View_State, .Wrong_Buffer, .Stale_Revision,
	     .Stale_Selection, .Stale_Analysis:
	}
	if failure.structural_code != .None do return "structural editor state rejected the request"
	return "structural command rejected the request"
}
