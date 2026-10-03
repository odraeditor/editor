// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies buffer-session ABI records and copied batch quotas remain exact. */
@(test)
session_record_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, buffer_session_record_layout_is_valid())
	descriptor_bytes, descriptor_ok := buffer_session_descriptor_record_bytes(2, 32)
	testing.expect(t, descriptor_ok)
	testing.expect_value(
		t,
		descriptor_bytes,
		BUFFER_SESSION_DESCRIPTOR_HEADER_BYTES + 2 * BUFFER_SESSION_DESCRIPTOR_RECORD_BYTES + 32,
	)
	_, descriptor_ok = buffer_session_descriptor_record_bytes(MAX_BUFFER_SESSION_DESCRIPTORS + 1, 0)
	testing.expect(t, !descriptor_ok)
	_, descriptor_ok = buffer_session_descriptor_record_bytes(1, MAX_BUFFER_SESSION_LABEL_BYTES + 1)
	testing.expect(t, !descriptor_ok)

	request_bytes, request_ok := buffer_session_request_record_bytes(64, 2, 2, 32)
	testing.expect(t, request_ok)
	testing.expect_value(
		t,
		request_bytes,
		BUFFER_SESSION_REQUEST_HEADER_BYTES + 64 + 2 * BUFFER_SESSION_MARK_RECORD_BYTES +
			2 * BUFFER_SESSION_DECISION_RECORD_BYTES + 32,
	)
	_, request_ok = buffer_session_request_record_bytes(MAX_BUFFER_SESSION_REQUEST_TEXT_BYTES + 1, 0, 0, 0)
	testing.expect(t, !request_ok)
	_, request_ok = buffer_session_request_record_bytes(0, MAX_BUFFER_SESSION_MARKS + 1, 0, 0)
	testing.expect(t, !request_ok)
	_, request_ok = buffer_session_request_record_bytes(0, 0, MAX_BUFFER_SESSION_DECISIONS + 1, 0)
	testing.expect(t, !request_ok)
}
