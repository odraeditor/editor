// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor

import "core:testing"

/* Verifies that the production editor limits form a coherent bound set. */
@(test)
default_limits_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	testing.expect_value(t, DEFAULT_LIMITS.buffer_bytes, u64(1_073_741_824))
	testing.expect_value(t, DEFAULT_LIMITS.replacement_bytes, u64(268_435_456))
	testing.expect_value(t, DEFAULT_LIMITS.inspection_bytes, u64(16_777_216))
}

/* Verifies rejection of inconsistent size, storage, and reclamation limits. */
@(test)
invalid_limits_are_rejected :: proc(t: ^testing.T) {
	oversized_replacement := DEFAULT_LIMITS
	oversized_replacement.replacement_bytes = oversized_replacement.buffer_bytes + 1

	undersized_persistent_budget := DEFAULT_LIMITS
	undersized_persistent_budget.persistent_bytes = undersized_persistent_budget.buffer_bytes - 1

	invalid_reclaim_budget := DEFAULT_LIMITS
	invalid_reclaim_budget.reclaim_step_nodes = invalid_reclaim_budget.reclaim_queue_nodes + 1

	testing.expect(t, !limits_are_valid(oversized_replacement))
	testing.expect(t, !limits_are_valid(undersized_persistent_budget))
	testing.expect(t, !limits_are_valid(invalid_reclaim_budget))
}

/* Verifies that zero cannot be used as a live buffer identity in a position. */
@(test)
positions_require_live_identity :: proc(t: ^testing.T) {
	position, ok := position_make(Buffer_ID(7), Revision(0), Byte_Offset(3))
	testing.expect(t, ok)
	testing.expect_value(t, position.buffer_id, Buffer_ID(7))
	testing.expect_value(t, position.revision, Revision(0))
	testing.expect_value(t, position.byte_offset, Byte_Offset(3))

	_, zero_ok := position_make(Buffer_ID(0), Revision(0), Byte_Offset(0))
	testing.expect(t, !zero_ok)
}
