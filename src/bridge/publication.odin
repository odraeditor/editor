// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import edit_transaction "../transaction"

/*
buffer_capability_splice validates and publishes one revision-bound replacement.
No callback or foreign execution occurs after validation enters editor publication.
*/
buffer_capability_splice :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	byte_range: Byte_Range,
	replacement: string,
	request: Publication_Request,
) -> (result: Publication_Result, ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	slot, resolve_failure := capability_resolve(registry, capability)
	if resolve_failure.code != .None {
		return {}, false, resolve_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(
			registry, capability, byte_range, stats_failure,
		)
	}
	if buffer_id != slot.buffer_id || buffer_id != stats.buffer_id {
		return {}, false, Failure_Context {
			code = .Wrong_Buffer,
			registry_id = registry.registry_id,
			capability = capability,
			buffer_id = buffer_id,
			revision = revision,
			range = byte_range,
			actual = u64(stats.buffer_id),
		}
	}
	if revision != stats.revision {
		return {}, false, Failure_Context {
			code = .Stale_Revision,
			registry_id = registry.registry_id,
			capability = capability,
			buffer_id = buffer_id,
			revision = revision,
			range = byte_range,
			actual = u64(stats.revision),
		}
	}

	start, start_ok, start_failure := editor.buffer_position(slot.buffer, byte_range.start)
	if !start_ok {
		return {}, false, editor_failure_context(
			registry, capability, byte_range, start_failure,
		)
	}
	end, end_ok, end_failure := editor.buffer_position(slot.buffer, byte_range.end)
	if !end_ok {
		return {}, false, editor_failure_context(
			registry, capability, byte_range, end_failure,
		)
	}

	transaction: edit_transaction.Transaction
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		request.transaction_id,
		request.undo_unit_id,
		slot.buffer,
		request.origin,
		request.command,
		edit_transaction.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		},
	)
	if !started {
		return {}, false, transaction_failure_context(
			registry, capability, buffer_id, revision, byte_range, begin_failure,
		)
	}
	defer {
		if edit_transaction.transaction_is_valid(&transaction) {
			edit_transaction.transaction_close(&transaction)
		}
	}
	if request.cancelled {
		edit_transaction.transaction_request_cancel(&transaction)
	}
	applied, apply_failure := edit_transaction.transaction_apply_batch(
		&transaction,
		[]edit_transaction.Base_Splice{{start = start, end = end, replacement = replacement}},
	)
	if !applied {
		return {}, false, transaction_failure_context(
			registry, capability, buffer_id, revision, byte_range, apply_failure,
		)
	}
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated {
		return {}, false, transaction_failure_context(
			registry, capability, buffer_id, revision, byte_range, validation_failure,
		)
	}
	commit, committed, commit_failure := edit_transaction.transaction_commit(&transaction)
	if !committed {
		return {}, false, transaction_failure_context(
			registry, capability, buffer_id, revision, byte_range, commit_failure,
		)
	}
	result = Publication_Result{transaction = transaction, commit = commit}
	transaction = {}
	return result, true, {}
}

/* publication_result_close releases retained checked transaction result storage. */
publication_result_close :: proc(result: ^Publication_Result) {
	if result == nil {
		return
	}
	if edit_transaction.transaction_is_valid(&result.transaction) {
		closed, close_failure := edit_transaction.transaction_close(&result.transaction)
		assert(closed && close_failure.code == .None)
	}
	result.commit = {}
}

@(private)
transaction_failure_context :: proc(
	registry: ^Buffer_Capability_Registry,
	capability: Buffer_Capability,
	buffer_id: editor.Buffer_ID,
	revision: editor.Revision,
	byte_range: Byte_Range,
	transaction_failure: edit_transaction.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Transaction_Failure,
		registry_id = registry.registry_id,
		capability = capability,
		buffer_id = buffer_id,
		revision = revision,
		range = byte_range,
		transaction_code = transaction_failure.code,
		editor_code = transaction_failure.editor_failure.code,
	}
}
