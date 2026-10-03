// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies fixed search-record layouts and bounded occupancy arithmetic. */
@(test)
search_records_are_fixed_and_bounded :: proc(t: ^testing.T) {
	testing.expect(t, search_record_layout_is_valid())
	empty, empty_ok := search_session_record_bytes(0, 0, 0)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty, SEARCH_SESSION_HEADER_BYTES)
	maximum, maximum_ok := search_session_record_bytes(
		MAX_SEARCH_INSPECTION_OCCURRENCES,
		MAX_SEARCH_INSPECTION_CAPTURES,
		MAX_SEARCH_INSPECTION_TEXT_BYTES,
	)
	testing.expect(t, maximum_ok)
	testing.expect(t, maximum > SEARCH_SESSION_HEADER_BYTES)
	_, oversized := search_session_record_bytes(MAX_SEARCH_INSPECTION_OCCURRENCES + 1, 0, 0)
	testing.expect(t, !oversized)

	request, request_ok := search_command_request_bytes(16, 32, 64)
	testing.expect(t, request_ok)
	testing.expect_value(t, request, SEARCH_COMMAND_REQUEST_HEADER_BYTES + 112)
	_, invalid_request := search_command_request_bytes(MAX_SEARCH_COMMAND_NAME_BYTES + 1, 0, 0)
	testing.expect(t, !invalid_request)
}
