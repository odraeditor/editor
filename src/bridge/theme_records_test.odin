// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../theme"
import "core:testing"

/* Verifies theme ABI records remain fixed, pointer-free, and quota checked. */
@(test)
theme_record_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, theme_record_layout_is_valid())

	snapshot_bytes, snapshot_ok := theme_snapshot_record_bytes(
		5,
		5,
		5 * theme.CURRENT_STYLE_ROLE_COUNT,
		1,
		512,
		64,
	)
	testing.expect(t, snapshot_ok)
	testing.expect_value(
		t,
		snapshot_bytes,
		THEME_SNAPSHOT_HEADER_BYTES + 5 * THEME_PROVIDER_RECORD_BYTES +
			5 * THEME_DEFINITION_RECORD_BYTES +
			5 * theme.CURRENT_STYLE_ROLE_COUNT * THEME_STYLE_RECORD_BYTES +
			THEME_DIAGNOSTIC_RECORD_BYTES + 512 + 64,
	)

	_, snapshot_ok = theme_snapshot_record_bytes(
		u64(theme.MAX_PROVIDERS) + 1, 0, 0, 0, 0, 0,
	)
	testing.expect(t, !snapshot_ok)
	_, snapshot_ok = theme_snapshot_record_bytes(
		1, 1, u64(theme.MAX_STYLES) + 1, 0, 0, 0,
	)
	testing.expect(t, !snapshot_ok)
	_, snapshot_ok = theme_snapshot_record_bytes(
		0, 0, 0, MAX_THEME_INSPECTION_DIAGNOSTICS + 1, 0, 0,
	)
	testing.expect(t, !snapshot_ok)

	proposal_bytes, proposal_ok := theme_proposal_record_bytes(
		theme.CURRENT_STYLE_ROLE_COUNT,
		MAX_THEME_PROPOSAL_TEXT_BYTES,
	)
	testing.expect(t, proposal_ok)
	testing.expect_value(
		t,
		proposal_bytes,
		THEME_PROPOSAL_HEADER_BYTES +
			theme.CURRENT_STYLE_ROLE_COUNT * THEME_STYLE_RECORD_BYTES +
			MAX_THEME_PROPOSAL_TEXT_BYTES,
	)
	_, proposal_ok = theme_proposal_record_bytes(u64(theme.MAX_STYLES) + 1, 0)
	testing.expect(t, !proposal_ok)
	_, proposal_ok = theme_proposal_record_bytes(0, MAX_THEME_PROPOSAL_TEXT_BYTES + 1)
	testing.expect(t, !proposal_ok)
}
