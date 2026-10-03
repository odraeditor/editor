// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"

@(private)
validate_base_batch :: proc(state: ^Transaction_State, batch: []Base_Splice) -> Failure_Context {
	previous_start := u64(0)
	previous_end := u64(0)
	has_previous := false
	for splice, index in batch {
		if splice.start.buffer_id != state.buffer_id || splice.end.buffer_id != state.buffer_id {
			failure := transaction_failure(state, .Wrong_Buffer)
			failure.splice_index = u64(index)
			return failure
		}
		if splice.start.revision != splice.end.revision {
			failure := transaction_failure(state, .Mismatched_Revision)
			failure.splice_index = u64(index)
			return failure
		}
		if splice.start.revision != state.base_revision {
			failure := transaction_failure(state, .Stale_Revision)
			failure.splice_index = u64(index)
			return failure
		}
		start := u64(splice.start.byte_offset)
		end := u64(splice.end.byte_offset)
		if start > end {
			failure := transaction_failure(state, .Reversed_Range)
			failure.splice_index = u64(index)
			return failure
		}
		if has_previous {
			if start < previous_start {
				failure := transaction_failure(state, .Ambiguous_Order)
				failure.splice_index = u64(index)
				return failure
			}
			if start < previous_end {
				failure := transaction_failure(state, .Overlapping_Batch)
				failure.splice_index = u64(index)
				return failure
			}
			if start == previous_start && (start != end || previous_start != previous_end) {
				failure := transaction_failure(state, .Ambiguous_Order)
				failure.splice_index = u64(index)
				return failure
			}
		}
		position, position_ok, position_failure := editor.buffer_position(
			state.buffer,
			splice.start.byte_offset,
		)
		if !position_ok || position != splice.start {
			if position_failure.code == .None {
				position_failure = editor.Failure_Context {
					code = .Stale_Revision,
					buffer_id = state.buffer_id,
					revision = state.base_revision,
					start = splice.start.byte_offset,
				}
			}
			return transaction_editor_failure(state.transaction_id, u64(index), position_failure)
		}
		position, position_ok, position_failure = editor.buffer_position(
			state.buffer,
			splice.end.byte_offset,
		)
		if !position_ok || position != splice.end {
			if position_failure.code == .None {
				position_failure = editor.Failure_Context {
					code = .Stale_Revision,
					buffer_id = state.buffer_id,
					revision = state.base_revision,
					start = splice.end.byte_offset,
				}
			}
			return transaction_editor_failure(state.transaction_id, u64(index), position_failure)
		}
		previous_start = start
		previous_end = end
		has_previous = true
	}
	return {}
}
