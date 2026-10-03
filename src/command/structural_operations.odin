// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import "../language"
import edit_transaction "../transaction"
import editor_view "../view"

/* Structural_Editor_Failure_Code classifies rejection before structural publication. */
Structural_Editor_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Invalid_Operation,
	Wrong_View,
	Stale_View_State,
	Wrong_Buffer,
	Stale_Revision,
	Stale_Selection,
	Stale_Analysis,
	Analysis_Rejected,
	View_Rejected,
	Transaction_Rejected,
}

/* Structural_Editor_Scope captures every identity required by one structural turn. */
Structural_Editor_Scope :: struct {
	view:                  editor_view.View_Handle,
	view_state_generation: u64,
	buffer_id:             editor.Buffer_ID,
	revision:              editor.Revision,
	selection_generation:  u64,
	analysis:              language.Structural_Scope,
	transaction_id:        edit_transaction.Transaction_ID,
	undo_unit_id:          edit_transaction.Undo_Unit_ID,
}

/* Structural_Editor_Context borrows native owners and one exact retained analysis tree. */
Structural_Editor_Context :: struct {
	native: Native_Context,
	owner:  ^language.Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	scope:  language.Structural_Scope,
}

/* Structural_Editor_Request invokes one semantic operation against an exact scope. */
Structural_Editor_Request :: struct {
	expected_scope: Structural_Editor_Scope,
	operation:      language.Structural_Operation,
}

/* Structural_Editor_Result retains any transaction and copied structural outcome. */
Structural_Editor_Result :: struct {
	operation:    language.Structural_Operation,
	before_scope: Structural_Editor_Scope,
	result_scope: Structural_Editor_Scope,
	target:       language.Structural_Target,
	usage:        language.Structural_Usage,
	native:       Native_Result,
}

/* structural_editor_result_close releases retained transaction result storage. */
structural_editor_result_close :: proc(result: ^Structural_Editor_Result) {
	if result == nil do return
	native_result_close(&result.native)
	result^ = {}
}

/* structural_editor_scope captures one exact live editor and analysis identity. */
structural_editor_scope :: proc(
	ctx: Structural_Editor_Context,
) -> (scope: Structural_Editor_Scope, ok: bool, failure: Failure_Context) {
	if ctx.native.buffer == nil || ctx.native.view_registry == nil || ctx.owner == nil ||
	   ctx.source == nil || !language.structural_scope_is_valid(ctx.scope) ||
	   ctx.native.temporary_allocator.procedure == nil ||
	   ctx.native.persistent_allocator.procedure == nil ||
	   ctx.native.transaction_id == edit_transaction.Transaction_ID(0) ||
	   ctx.native.undo_unit_id == edit_transaction.Undo_Unit_ID(0) {
		return {}, false, structural_editor_failure(.Invalid_Context)
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
		failure.structural_code = .Wrong_View
		return {}, false, failure
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(ctx.native.buffer)
	if !buffer_ok {
		failure = native_editor_failure(ctx.native.command, buffer_failure)
		failure.structural_code = .Wrong_Buffer
		return {}, false, failure
	}
	source_stats, source_ok, source_failure := editor.buffer_snapshot_stats(ctx.source)
	if !source_ok {
		failure = native_editor_failure(ctx.native.command, source_failure)
		failure.structural_code = .Stale_Revision
		return {}, false, failure
	}
	if logical.buffer_id != buffer_stats.buffer_id || source_stats.buffer_id != buffer_stats.buffer_id ||
	   ctx.scope.buffer_id != buffer_stats.buffer_id {
		failure = structural_editor_failure(.Wrong_Buffer)
		failure.buffer_id = buffer_stats.buffer_id
		return {}, false, failure
	}
	if logical.revision != buffer_stats.revision || source_stats.revision != buffer_stats.revision ||
	   ctx.scope.source_revision != buffer_stats.revision {
		failure = structural_editor_failure(.Stale_Revision)
		failure.buffer_id = buffer_stats.buffer_id
		failure.revision = buffer_stats.revision
		return {}, false, failure
	}
	return Structural_Editor_Scope {
		view = ctx.native.view,
		view_state_generation = logical.state_generation,
		buffer_id = buffer_stats.buffer_id,
		revision = buffer_stats.revision,
		selection_generation = logical.selection_generation,
		analysis = ctx.scope,
		transaction_id = ctx.native.transaction_id,
		undo_unit_id = ctx.native.undo_unit_id,
	}, true, {}
}

/* structural_editor_run resolves and publishes one semantic structural operation. */
structural_editor_run :: proc(
	ctx: Structural_Editor_Context,
	request: Structural_Editor_Request,
) -> (result: Structural_Editor_Result, ok: bool, failure: Failure_Context) {
	before, scoped, scope_failure := structural_editor_scope(ctx)
	if !scoped do return {}, false, scope_failure
	if request.operation < .Forward || request.operation > .Definition {
		return {}, false, structural_editor_failure(.Invalid_Operation)
	}
	if request.expected_scope != before {
		return {}, false, structural_editor_scope_mismatch(request.expected_scope, before)
	}
	switch request.operation {
	case .Forward, .Backward, .Up, .Down:
		return structural_editor_navigate(ctx, before, request.operation)
	case .Select, .Definition:
		return structural_editor_select(ctx, before, request.operation)
	case .Indent:
		return structural_editor_indent(ctx, before)
	case .Invalid:
		unreachable()
	}
	unreachable()
}

@(private)
structural_editor_indent :: proc(
	ctx: Structural_Editor_Context,
	before: Structural_Editor_Scope,
) -> (Structural_Editor_Result, bool, Failure_Context) {
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure := native_view_failure(ctx.native.command, logical_failure)
		failure.structural_code = .Wrong_View
		return {}, false, failure
	}
	query := structural_language_request(ctx.scope, logical, .Indent)
	plan, planned, plan_failure := language.tree_sitter_owner_plan_indentation(
		ctx.owner,
		ctx.source,
		query,
		ctx.native.temporary_allocator,
	)
	if !planned do return {}, false, structural_editor_language_failure(plan_failure)
	defer language.structural_indentation_plan_close(&plan)
	current, current_ok, current_failure := structural_editor_scope(ctx)
	if !current_ok do return {}, false, current_failure
	if current != before {
		return {}, false, structural_editor_scope_mismatch(before, current)
	}
	if len(plan.edits) == 0 {
		return Structural_Editor_Result {
			operation = .Indent,
			before_scope = before,
			result_scope = before,
			usage = plan.usage,
			native = Native_Result{completion = .No_Op},
		}, true, {}
	}
	batch, batch_error := make(
		[]edit_transaction.Base_Splice,
		len(plan.edits),
		ctx.native.temporary_allocator,
	)
	if batch_error != nil {
		failure := structural_editor_failure(.Transaction_Rejected)
		failure.code = .Temporary_Memory_Limit
		failure.actual = u64(len(plan.edits)) * u64(size_of(edit_transaction.Base_Splice))
		return {}, false, failure
	}
	defer delete(batch, ctx.native.temporary_allocator)
	replacements, replacement_error := make(
		[]byte,
		int(plan.usage.prepared_bytes),
		ctx.native.temporary_allocator,
	)
	if replacement_error != nil {
		failure := structural_editor_failure(.Transaction_Rejected)
		failure.code = .Temporary_Memory_Limit
		failure.actual = plan.usage.prepared_bytes
		return {}, false, failure
	}
	defer delete(replacements, ctx.native.temporary_allocator)
	for &byte in replacements do byte = ' '
	replacement_offset := 0
	for edit, index in plan.edits {
		start, start_ok, start_failure := editor.buffer_position(ctx.native.buffer, edit.start)
		if !start_ok {
			failure := native_editor_failure(ctx.native.command, start_failure)
			failure.structural_code = .Transaction_Rejected
			return {}, false, failure
		}
		end, end_ok, end_failure := editor.buffer_position(ctx.native.buffer, edit.end)
		if !end_ok {
			failure := native_editor_failure(ctx.native.command, end_failure)
			failure.structural_code = .Transaction_Rejected
			return {}, false, failure
		}
		replacement_end := replacement_offset + int(edit.indent_bytes)
		batch[index] = edit_transaction.Base_Splice {
			start = start,
			end = end,
			replacement = string(replacements[replacement_offset:replacement_end]),
		}
		replacement_offset = replacement_end
	}
	assert(replacement_offset == len(replacements))
	transaction: edit_transaction.Transaction
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		ctx.native.transaction_id,
		ctx.native.undo_unit_id,
		ctx.native.buffer,
		edit_transaction.Origin{kind = .Language_Tool, descriptor = "structural-syntax"},
		"structural-indent",
		edit_transaction.Allocator_Set {
			persistent = ctx.native.persistent_allocator,
			temporary = ctx.native.temporary_allocator,
		},
	)
	if !started do return {}, false, structural_editor_transaction_failure(ctx, begin_failure)
	defer {
		if edit_transaction.transaction_is_valid(&transaction) {
			closed, _ := edit_transaction.transaction_close(&transaction)
			assert(closed)
		}
	}
	applied, apply_failure := edit_transaction.transaction_apply_batch(&transaction, batch)
	if !applied do return {}, false, structural_editor_transaction_failure(ctx, apply_failure)
	result_offset, mapped := replace_all_map_offset(logical.point_position.byte_offset, batch)
	if !mapped {
		failure := structural_editor_failure(.Transaction_Rejected)
		failure.code = .Text_Limit
		return {}, false, failure
	}
	target, target_ok, target_failure := edit_transaction.transaction_position(
		&transaction,
		result_offset,
	)
	if !target_ok do return {}, false, structural_editor_transaction_failure(ctx, target_failure)
	prepared, prepare_failure := edit_transaction.transaction_prepare_logical_view(
		&transaction,
		ctx.native.view_registry,
		ctx.native.view,
		target,
		logical.desired_display_column,
		.Preserve,
	)
	if !prepared do return {}, false, structural_editor_transaction_failure(ctx, prepare_failure)
	if ctx.native.history_store != nil {
		tracked, track_failure := edit_transaction.transaction_track_history(
			&transaction,
			ctx.native.history_store,
			ctx.native.history_grouping,
		)
		if !tracked do return {}, false, structural_editor_transaction_failure(ctx, track_failure)
	}
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated do return {}, false, structural_editor_transaction_failure(ctx, validation_failure)
	commit, committed, commit_failure := edit_transaction.transaction_commit(
		&transaction,
		ctx.native.commit_observer,
	)
	if !committed do return {}, false, structural_editor_transaction_failure(ctx, commit_failure)
	finish_committed_view(ctx.native, logical.desired_display_column)
	after, after_ok, after_failure := structural_editor_result_scope(ctx)
	if !after_ok do return {}, false, after_failure
	owned_transaction := transaction
	transaction = {}
	return Structural_Editor_Result {
		operation = .Indent,
		before_scope = before,
		result_scope = after,
		usage = plan.usage,
		native = Native_Result {
			completion = .Buffer_Committed,
			transaction = owned_transaction,
			commit = commit,
		},
	}, true, {}
}

@(private)
structural_editor_select :: proc(
	ctx: Structural_Editor_Context,
	before: Structural_Editor_Scope,
	operation: language.Structural_Operation,
) -> (Structural_Editor_Result, bool, Failure_Context) {
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure := native_view_failure(ctx.native.command, logical_failure)
		failure.structural_code = .Wrong_View
		return {}, false, failure
	}
	query := structural_language_request(ctx.scope, logical, operation)
	target, usage, queried, query_failure := language.tree_sitter_owner_query_structure(
		ctx.owner,
		ctx.source,
		query,
	)
	if !queried {
		if query_failure.code == .No_Structural_Target {
			return Structural_Editor_Result {
				operation = operation,
				before_scope = before,
				result_scope = before,
				usage = usage,
				native = Native_Result{completion = .No_Op},
			}, true, {}
		}
		return {}, false, structural_editor_language_failure(query_failure)
	}
	current, current_ok, current_failure := structural_editor_scope(ctx)
	if !current_ok do return {}, false, current_failure
	if current != before {
		return {}, false, structural_editor_scope_mismatch(before, current)
	}
	start, start_ok, start_failure := editor.buffer_position(ctx.native.buffer, target.start)
	if !start_ok {
		failure := native_editor_failure(ctx.native.command, start_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	end, end_ok, end_failure := editor.buffer_position(ctx.native.buffer, target.end)
	if !end_ok {
		failure := native_editor_failure(ctx.native.command, end_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	column, column_ok, column_failure := display.position_display_column(
		ctx.native.buffer,
		end,
		ctx.native.profile,
		logical.tab_width,
	)
	if !column_ok {
		failure := native_display_failure(ctx.native.command, column_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	reveal, revealed, reveal_failure := cursor_reveal_plan(
		ctx.native.buffer,
		logical,
		end,
		column,
		ctx.native.constraints,
	)
	if !revealed {
		reveal_failure.command = ctx.native.command
		reveal_failure.structural_code = .View_Rejected
		return {}, false, reveal_failure
	}
	selected, select_failure := editor_view.select_range(
		ctx.native.view_registry,
		ctx.native.view,
		start,
		end,
		column,
	)
	if !selected {
		failure := native_view_failure(ctx.native.command, select_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	if reveal.update {
		updated, update_failure := editor_view.set_viewport(
			ctx.native.view_registry,
			ctx.native.view,
			reveal.origin,
			reveal.horizontal,
		)
		if !updated {
			failure := native_view_failure(ctx.native.command, update_failure)
			failure.structural_code = .View_Rejected
			return {}, false, failure
		}
	}
	after, after_ok, after_failure := structural_editor_scope(ctx)
	if !after_ok do return {}, false, after_failure
	return Structural_Editor_Result {
		operation = operation,
		before_scope = before,
		result_scope = after,
		target = target,
		usage = usage,
		native = Native_Result{completion = .View_Changed},
	}, true, {}
}

@(private)
structural_editor_navigate :: proc(
	ctx: Structural_Editor_Context,
	before: Structural_Editor_Scope,
	operation: language.Structural_Operation,
) -> (Structural_Editor_Result, bool, Failure_Context) {
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure := native_view_failure(ctx.native.command, logical_failure)
		failure.structural_code = .Wrong_View
		return {}, false, failure
	}
	query := structural_language_request(ctx.scope, logical, operation)
	target, usage, queried, query_failure := language.tree_sitter_owner_query_structure(
		ctx.owner,
		ctx.source,
		query,
	)
	if !queried {
		if query_failure.code == .No_Structural_Target {
			return Structural_Editor_Result {
				operation = operation,
				before_scope = before,
				result_scope = before,
				usage = usage,
				native = Native_Result{completion = .No_Op},
			}, true, {}
		}
		return {}, false, structural_editor_language_failure(query_failure)
	}
	current, current_ok, current_failure := structural_editor_scope(ctx)
	if !current_ok do return {}, false, current_failure
	if current != before {
		return {}, false, structural_editor_scope_mismatch(before, current)
	}
	target_offset := target.start
	if operation == .Forward do target_offset = target.end
	position, positioned, position_failure := editor.buffer_position(ctx.native.buffer, target_offset)
	if !positioned {
		failure := native_editor_failure(ctx.native.command, position_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	column, column_ok, column_failure := display.position_display_column(
		ctx.native.buffer,
		position,
		ctx.native.profile,
		logical.tab_width,
	)
	if !column_ok {
		failure := native_display_failure(ctx.native.command, column_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	reveal, revealed, reveal_failure := cursor_reveal_plan(
		ctx.native.buffer,
		logical,
		position,
		column,
		ctx.native.constraints,
	)
	if !revealed {
		reveal_failure.command = ctx.native.command
		reveal_failure.structural_code = .View_Rejected
		return {}, false, reveal_failure
	}
	moved, move_failure := editor_view.move_point(
		ctx.native.view_registry,
		ctx.native.view,
		position,
		column,
		.Preserve,
	)
	if !moved {
		failure := native_view_failure(ctx.native.command, move_failure)
		failure.structural_code = .View_Rejected
		return {}, false, failure
	}
	if reveal.update {
		updated, update_failure := editor_view.set_viewport(
			ctx.native.view_registry,
			ctx.native.view,
			reveal.origin,
			reveal.horizontal,
		)
		if !updated {
			failure := native_view_failure(ctx.native.command, update_failure)
			failure.structural_code = .View_Rejected
			return {}, false, failure
		}
	}
	after, after_ok, after_failure := structural_editor_scope(ctx)
	if !after_ok do return {}, false, after_failure
	return Structural_Editor_Result {
		operation = operation,
		before_scope = before,
		result_scope = after,
		target = target,
		usage = usage,
		native = Native_Result{completion = .View_Changed},
	}, true, {}
}

@(private)
structural_language_request :: proc(
	scope: language.Structural_Scope,
	logical: editor_view.Snapshot,
	operation: language.Structural_Operation,
) -> language.Structural_Request {
	point := logical.point_position.byte_offset
	request := language.Structural_Request {
		operation = operation,
		scope = scope,
		point = point,
		start = point,
		end = point,
	}
	if logical.region_active && logical.mark.present {
		request.has_region = true
		request.start = min(point, logical.mark.position.byte_offset)
		request.end = max(point, logical.mark.position.byte_offset)
	}
	return request
}

@(private)
structural_editor_scope_mismatch :: proc(
	expected, actual: Structural_Editor_Scope,
) -> Failure_Context {
	code := Structural_Editor_Failure_Code.Stale_View_State
	if expected.view != actual.view do code = .Wrong_View
	if expected.buffer_id != actual.buffer_id do code = .Wrong_Buffer
	if expected.revision != actual.revision do code = .Stale_Revision
	if expected.selection_generation != actual.selection_generation do code = .Stale_Selection
	if expected.analysis != actual.analysis do code = .Stale_Analysis
	failure := structural_editor_failure(code)
	failure.buffer_id = actual.buffer_id
	failure.revision = actual.revision
	return failure
}

@(private)
structural_editor_failure :: proc(code: Structural_Editor_Failure_Code) -> Failure_Context {
	return Failure_Context{code = .Capability_Failure, structural_code = code}
}

@(private)
structural_editor_language_failure :: proc(source: language.Failure) -> Failure_Context {
	return Failure_Context {
		code = .Capability_Failure,
		structural_code = .Analysis_Rejected,
		language_code = source.code,
		revision = source.source_revision,
		limit = source.limit,
		actual = source.actual,
	}
}

@(private)
structural_editor_transaction_failure :: proc(
	ctx: Structural_Editor_Context,
	source: edit_transaction.Failure_Context,
) -> Failure_Context {
	failure := native_transaction_failure(ctx.native.command, source)
	failure.structural_code = .Transaction_Rejected
	return failure
}

@(private)
structural_editor_result_scope :: proc(
	ctx: Structural_Editor_Context,
) -> (scope: Structural_Editor_Scope, ok: bool, failure: Failure_Context) {
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure = native_view_failure(ctx.native.command, logical_failure)
		failure.structural_code = .Wrong_View
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(ctx.native.buffer)
	if !stats_ok {
		failure = native_editor_failure(ctx.native.command, stats_failure)
		failure.structural_code = .Wrong_Buffer
		return {}, false, failure
	}
	if logical.buffer_id != stats.buffer_id || logical.revision != stats.revision {
		return {}, false, structural_editor_failure(.Stale_Revision)
	}
	return Structural_Editor_Scope {
		view = ctx.native.view,
		view_state_generation = logical.state_generation,
		buffer_id = stats.buffer_id,
		revision = stats.revision,
		selection_generation = logical.selection_generation,
		analysis = ctx.scope,
		transaction_id = ctx.native.transaction_id,
		undo_unit_id = ctx.native.undo_unit_id,
	}, true, {}
}
