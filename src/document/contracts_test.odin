// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "core:testing"

/* Verifies the production document bounds remain explicit and internally valid. */
@(test)
default_document_limits_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	testing.expect_value(t, DEFAULT_LIMITS.file_bytes, u64(268_435_456))
	testing.expect_value(t, DEFAULT_LIMITS.path_bytes, u64(4_096))
	testing.expect_value(t, DEFAULT_LIMITS.io_chunk_bytes, u64(65_536))
	testing.expect_value(t, DEFAULT_LIMITS.active_operations, u32(1))
	testing.expect_value(t, DEFAULT_LIMITS.save_snapshots, u32(1))
}

/* Verifies invalid or expanded resource contracts are rejected. */
@(test)
invalid_document_limits_are_rejected :: proc(t: ^testing.T) {
	zero_file := DEFAULT_LIMITS
	zero_file.file_bytes = 0
	testing.expect(t, !limits_are_valid(zero_file))

	expanded_path := DEFAULT_LIMITS
	expanded_path.path_bytes = MAX_PATH_BYTES + 1
	testing.expect(t, !limits_are_valid(expanded_path))

	unbounded_operations := DEFAULT_LIMITS
	unbounded_operations.active_operations = 2
	testing.expect(t, !limits_are_valid(unbounded_operations))

	zero_retries := DEFAULT_LIMITS
	zero_retries.interrupted_io_retries = 0
	testing.expect(t, !limits_are_valid(zero_retries))
}

/* Verifies opaque lifecycle handles have useful empty states. */
@(test)
document_handles_have_inert_zero_values :: proc(t: ^testing.T) {
	document: Document
	prepared: Prepared_Open
	testing.expect(t, document.state == nil)
	testing.expect(t, prepared.state == nil)
}
