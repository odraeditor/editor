// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies candidate history ABI records and copied quotas remain exact. */
@(test)
candidate_history_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, candidate_history_record_layout_is_valid())
	load_bytes, load_ok := candidate_history_load_record_bytes(2, 96, 24)
	testing.expect(t, load_ok)
	testing.expect_value(
		t,
		load_bytes,
		CANDIDATE_HISTORY_LOAD_HEADER_BYTES +
			2 * CANDIDATE_HISTORY_ENTRY_RECORD_BYTES + 96 + 24,
	)
	_, load_ok = candidate_history_load_record_bytes(MAX_CANDIDATE_HISTORY_ENTRIES + 1, 0, 0)
	testing.expect(t, !load_ok)
	_, load_ok = candidate_history_load_record_bytes(0, 0, MAX_CANDIDATE_HISTORY_DIAGNOSTIC_BYTES + 1)
	testing.expect(t, !load_ok)

	publish_bytes, publish_ok := candidate_history_publish_record_bytes(3, 128)
	testing.expect(t, publish_ok)
	testing.expect_value(
		t,
		publish_bytes,
		CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES +
			3 * CANDIDATE_HISTORY_ENTRY_RECORD_BYTES + 128,
	)
	_, publish_ok = candidate_history_publish_record_bytes(0, MAX_CANDIDATE_HISTORY_KEY_BYTES + 1)
	testing.expect(t, !publish_ok)
}
