// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"

/* History_Command_Context contains the checked native owners for one history command turn. */
History_Command_Context :: struct {
	store:                ^history.Store,
	buffer:               ^editor.Buffer,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
	transaction_id:       edit_transaction.Transaction_ID,
	undo_unit_id:         edit_transaction.Undo_Unit_ID,
	cancelled:            bool,
	view_registry:        ^editor_view.Registry,
	view:                 editor_view.View_Handle,
}

/* History_Anchor_Range optionally narrows selective undo with two live stable anchors. */
History_Anchor_Range :: struct {
	present: bool,
	start:   editor.Anchor,
	end:     editor.Anchor,
}

/* history_command_inspect returns one copied bounded native history projection. */
history_command_inspect :: proc(
	ctx: History_Command_Context,
	request: history.Inspection_Request,
) -> (inspection: history.Inspection, ok: bool, failure: Failure_Context) {
	if ctx.store == nil || ctx.buffer == nil || ctx.cancelled {
		code := Failure_Code.Invalid_Request
		if ctx.cancelled {
			code = .Cancelled
		}
		return {}, false, Failure_Context{code = code}
	}
	history_failure: history.Failure_Context
	inspection, ok, history_failure = history.store_inspect(
		ctx.store,
		request,
		ctx.temporary_allocator,
	)
	if !ok {
		return {}, false, history_command_failure(history_failure)
	}
	return inspection, true, {}
}

/* history_command_inspection_close releases a copied native inspection result. */
history_command_inspection_close :: proc(
	inspection: ^history.Inspection,
	temporary_allocator: runtime.Allocator,
) {
	history.inspection_release(inspection, temporary_allocator)
}

/* history_command_select_branch publishes one checked retained branch transition. */
history_command_select_branch :: proc(
	ctx: History_Command_Context,
	active_node, target_node: history.Node_ID,
	policy_generation: history.Policy_Generation,
	analysis_operations: u64,
) -> (result: history.Navigation_Result, ok: bool, failure: Failure_Context) {
	if invalid := history_command_context_validate(ctx); invalid.code != .None {
		return {}, false, invalid
	}
	transaction_failure: edit_transaction.Failure_Context
	result, ok, transaction_failure = edit_transaction.transaction_history_navigate(
		ctx.store,
		ctx.buffer,
		.Select_Branch,
		ctx.transaction_id,
		ctx.undo_unit_id,
		edit_transaction.Allocator_Set {
			persistent = ctx.persistent_allocator,
			temporary = ctx.temporary_allocator,
		},
		active_node = active_node,
		target_node = target_node,
		policy_generation = policy_generation,
		analysis_operations = analysis_operations,
	)
	if !ok {
		return {}, false, history_command_transaction_failure(transaction_failure)
	}
	return result, true, {}
}

/* history_command_selective_undo publishes one checked compensating transaction. */
history_command_selective_undo :: proc(
	ctx: History_Command_Context,
	active_node: history.Node_ID,
	target_unit: history.Unit_ID,
	policy_generation: history.Policy_Generation,
	analysis_operations: u64,
	anchor_range := History_Anchor_Range{},
	origin := edit_transaction.Origin{kind = .Built_In, descriptor = "history"},
) -> (result: history.Navigation_Result, ok: bool, failure: Failure_Context) {
	if invalid := history_command_context_validate(ctx); invalid.code != .None {
		return {}, false, invalid
	}
	buffer_stats, buffer_ok, editor_failure := editor.buffer_stats(ctx.buffer)
	if !buffer_ok {
		return {}, false, Failure_Context {
			code = .History_Failure,
			editor_code = editor_failure.code,
		}
	}
	selected_range, range_ok, range_failure := history_command_selected_range(
		ctx,
		buffer_stats,
		anchor_range,
	)
	if !range_ok {
		return {}, false, range_failure
	}
	transaction_failure: edit_transaction.Failure_Context
	result, ok, transaction_failure = edit_transaction.transaction_history_selective_undo(
		ctx.store,
		ctx.buffer,
		history.Selective_Request {
			buffer_id = buffer_stats.buffer_id,
			current_revision = buffer_stats.revision,
			active_node = active_node,
			target_unit = target_unit,
			policy_generation = policy_generation,
			analysis_operations = analysis_operations,
			range = selected_range,
			cancelled = ctx.cancelled,
		},
		ctx.transaction_id,
		ctx.undo_unit_id,
		edit_transaction.Allocator_Set {
			persistent = ctx.persistent_allocator,
			temporary = ctx.temporary_allocator,
		},
		origin,
	)
	if !ok {
		return {}, false, history_command_transaction_failure(transaction_failure)
	}
	return result, true, {}
}

@(private)
history_command_selected_range :: proc(
	ctx: History_Command_Context,
	buffer_stats: editor.Buffer_Stats,
	anchor_range: History_Anchor_Range,
) -> (selected_range: history.Selective_Range, ok: bool, failure: Failure_Context) {
	if anchor_range.present {
		start, start_ok, start_failure := editor.buffer_anchor_resolve(ctx.buffer, anchor_range.start)
		if !start_ok {
			return {}, false, Failure_Context{code = .History_Failure, editor_code = start_failure.code}
		}
		end, end_ok, end_failure := editor.buffer_anchor_resolve(ctx.buffer, anchor_range.end)
		if !end_ok {
			return {}, false, Failure_Context{code = .History_Failure, editor_code = end_failure.code}
		}
		if start.revision != buffer_stats.revision || end.revision != buffer_stats.revision ||
		   start.byte_offset > end.byte_offset {
			return {}, false, Failure_Context{code = .Invalid_Request}
		}
		return history.Selective_Range {
			present = true,
			revision = buffer_stats.revision,
			start = start.byte_offset,
			end = end.byte_offset,
		}, true, {}
	} else if ctx.view_registry != nil {
		logical, logical_ok, view_failure := editor_view.snapshot(ctx.view_registry, ctx.view)
		if !logical_ok {
			return {}, false, native_view_failure({}, view_failure)
		}
		if logical.region_active {
			if !logical.mark.present || logical.buffer_id != buffer_stats.buffer_id ||
				logical.revision != buffer_stats.revision {
				return {}, false, Failure_Context{code = .Invalid_Request}
			}
			start := logical.point_position.byte_offset
			end := logical.mark.position.byte_offset
			if start > end {
				start, end = end, start
			}
			return history.Selective_Range {
				present = true,
				revision = buffer_stats.revision,
				start = start,
				end = end,
			}, true, {}
		}
	}
	return {}, true, {}
}

@(private)
history_command_context_validate :: proc(ctx: History_Command_Context) -> Failure_Context {
	if ctx.cancelled {
		return Failure_Context{code = .Cancelled}
	}
	if ctx.store == nil || ctx.buffer == nil ||
	   ctx.persistent_allocator.procedure == nil ||
	   ctx.temporary_allocator.procedure == nil ||
	   ctx.transaction_id == edit_transaction.Transaction_ID(0) ||
	   ctx.undo_unit_id == edit_transaction.Undo_Unit_ID(0) {
		return Failure_Context{code = .Invalid_Request}
	}
	return {}
}

@(private)
history_command_failure :: proc(history_failure: history.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .History_Failure,
		history_code = history_failure.code,
		buffer_id = history_failure.buffer_id,
		revision = history_failure.revision,
		policy_generation = history_failure.policy_generation,
		minimum = history_failure.minimum,
		limit = history_failure.maximum,
		actual = history_failure.actual,
	}
}

@(private)
history_command_transaction_failure :: proc(
	failure: edit_transaction.Failure_Context,
) -> Failure_Context {
	result := Failure_Context {
		code = .Publication_Failure,
		transaction_code = failure.code,
		buffer_id = failure.buffer_id,
		revision = failure.base_revision,
		limit = failure.limit,
		actual = failure.actual,
	}
	if failure.code == .History_Failure {
		result.code = .History_Failure
		result.history_code = failure.history_failure.code
		result.policy_generation = failure.history_failure.policy_generation
	}
	return result
}
