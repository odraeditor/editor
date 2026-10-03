// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies workspace records keep their published widths and bounds. */
@(test)
test_workspace_record_widths_and_bounds :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Workspace_Request_Header_Record), int(WORKSPACE_REQUEST_HEADER_BYTES))
	testing.expect_value(t, size_of(Workspace_Result_Header_Record), int(WORKSPACE_RESULT_HEADER_BYTES))
	testing.expect_value(t, size_of(Workspace_Descriptor_Record), int(WORKSPACE_DESCRIPTOR_RECORD_BYTES))
	testing.expect_value(t, size_of(Workspace_Member_Record), int(WORKSPACE_MEMBER_RECORD_BYTES))
	bytes, admitted := workspace_result_bytes(2, 4, 512)
	testing.expect(t, admitted)
	testing.expect_value(
		t,
		bytes,
		WORKSPACE_RESULT_HEADER_BYTES + 2 * WORKSPACE_DESCRIPTOR_RECORD_BYTES +
		4 * WORKSPACE_MEMBER_RECORD_BYTES + 512,
	)
	_, rejected := workspace_result_bytes(MAX_WORKSPACE_RESULT_RECORDS + 1, 0, 0)
	testing.expect(t, !rejected)
}
