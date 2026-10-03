// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies Jan command records remain fixed, pointer-free, and quota checked. */
@(test)
jan_language_records_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, jan_language_record_layout_is_valid())
	bytes, ok := jan_language_inspection_bytes(4, 8, 2, 2, 5, 512)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		bytes,
		JAN_LANGUAGE_INSPECTION_HEADER_BYTES + JAN_LANGUAGE_LIMITS_RECORD_BYTES +
			JAN_LANGUAGE_PROVIDER_RECORD_BYTES + JAN_LANGUAGE_BASELINE_RECORD_BYTES +
			JAN_LANGUAGE_FAILURE_RECORD_BYTES + 4 * JAN_LANGUAGE_NODE_RECORD_BYTES +
			8 * JAN_LANGUAGE_ATTRIBUTE_RECORD_BYTES + 2 * JAN_LANGUAGE_RECOVERY_RECORD_BYTES +
			2 * JAN_LANGUAGE_LINT_RECORD_BYTES + 5 * JAN_LANGUAGE_AVAILABILITY_RECORD_BYTES + 512,
	)
	_, ok = jan_language_inspection_bytes(0, 0, 0, MAX_JAN_LANGUAGE_LINT_RECORDS + 1, 0, 0)
	testing.expect(t, !ok)
	_, ok = jan_language_inspection_bytes(0, 0, 0, 0, 0, MAX_JAN_LANGUAGE_COPY_BYTES + 1)
	testing.expect(t, !ok)
}

/* Verifies the complete public Jan command operation family remains stable. */
@(test)
jan_language_operations_are_complete :: proc(t: ^testing.T) {
	operations := [?]Jan_Language_Operation {
		.Inspect_Syntax,
		.Lint,
		.Lint_Refresh,
		.Language_Status,
	}
	for operation, index in operations do testing.expect_value(t, u64(operation), u64(index + 1))
}
