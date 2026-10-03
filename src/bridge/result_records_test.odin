// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../result_set"
import "core:testing"

@(test)
/* Verifies copied widths and quotas. */
result_records_are_fixed_and_bounded :: proc(t: ^testing.T) {
	testing.expect(t, result_record_layout_is_valid())
	empty, empty_ok := result_publication_record_bytes(0, 0, 0)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty, RESULT_PUBLICATION_HEADER_BYTES)
	maximum, maximum_ok := result_view_record_bytes(
		u64(result_set.MAX_RESULT_LOCATIONS),
		u64(result_set.MAX_RESULT_GROUPS),
		result_set.MAX_RESULT_TEXT_BYTES,
	)
	testing.expect(t, maximum_ok)
	testing.expect_value(t, maximum, MAX_RESULT_INSPECTION_BYTES)
	_, oversized := result_publication_record_bytes(
		u64(result_set.MAX_RESULT_LOCATIONS) + 1,
		0,
		0,
	)
	testing.expect(t, !oversized)
}
