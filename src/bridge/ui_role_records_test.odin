// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../ui"
import "core:testing"

/* Verifies programmable UI role ABI records and copied quotas remain exact. */
@(test)
ui_role_records_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, ui_role_record_layout_is_valid())

	snapshot_bytes, snapshot_ok := ui_role_snapshot_record_bytes(
		2, 2, 3, 2, 2, 3, 2, 2, 2, 7, 8, 64,
	)
	testing.expect(t, snapshot_ok)
	testing.expect_value(
		t,
		snapshot_bytes,
		UI_ROLE_SNAPSHOT_HEADER_BYTES + 2 * UI_ROLE_PROJECTION_RECORD_BYTES +
			2 * UI_ROLE_VIEW_RECORD_BYTES + 3 * UI_ROLE_LIST_ITEM_RECORD_BYTES +
			2 * UI_ROLE_INPUT_CHOICE_RECORD_BYTES + 2 * UI_ROLE_SURFACE_RECORD_BYTES +
			3 * UI_ROLE_COMPOSITION_RECORD_BYTES + 2 * UI_ROLE_STYLE_RECORD_BYTES +
			2 * UI_ROLE_STATUS_RECORD_BYTES + 2 * UI_ROLE_DECORATION_RECORD_BYTES +
			7 * UI_ROLE_PROVIDER_RECORD_BYTES +
			8 * UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES + 64,
	)
	_, snapshot_ok = ui_role_snapshot_record_bytes(
		0, 0, 0, 0, 0, 0, 0, 0, 0, MAX_UI_ROLE_PROVIDERS + 1, 0, 0,
	)
	testing.expect(t, !snapshot_ok)

	request_bytes, request_ok := ui_role_request_record_bytes(
		1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 8, 8, 64, 16,
	)
	testing.expect(t, request_ok)
	testing.expect_value(
		t,
		request_bytes,
		UI_ROLE_REQUEST_HEADER_BYTES + UI_ROLE_PROJECTION_RECORD_BYTES +
			UI_ROLE_VIEW_RECORD_BYTES + UI_ROLE_LIST_ITEM_RECORD_BYTES +
			UI_ROLE_INPUT_CHOICE_RECORD_BYTES + UI_ROLE_SURFACE_RECORD_BYTES +
			UI_ROLE_COMPOSITION_RECORD_BYTES + UI_ROLE_STATUS_RECORD_BYTES +
			UI_ROLE_STYLE_RECORD_BYTES + UI_ROLE_DECORATION_RECORD_BYTES +
			2 * UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES + 8 + 8 + 64 + 16,
	)
	_, request_ok = ui_role_request_record_bytes(
		u64(ui.MAX_LIVE_VIEWS) + 1,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
	)
	testing.expect(t, !request_ok)
	_, request_ok = ui_role_request_record_bytes(
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		MAX_UI_ROLE_CAPABILITY_REQUIREMENTS + 1,
		0,
		0,
		0,
		0,
	)
	testing.expect(t, !request_ok)
}
