// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies programmable layout ABI records and copied snapshot quotas remain exact. */
@(test)
layout_records_are_bounded_and_pointer_free :: proc(t: ^testing.T) {
	testing.expect(t, layout_record_layout_is_valid())
	bytes, ok := layout_snapshot_record_bytes(3)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, LAYOUT_SNAPSHOT_HEADER_BYTES + 3 * LAYOUT_NODE_RECORD_BYTES)
	_, ok = layout_snapshot_record_bytes(MAX_LAYOUT_SNAPSHOT_NODES + 1)
	testing.expect(t, !ok)
}
