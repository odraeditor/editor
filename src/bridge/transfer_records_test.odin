// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies exact pointer-free record widths and checked ring occupancy arithmetic. */
@(test)
transfer_records_are_fixed_and_bounded :: proc(t: ^testing.T) {
	testing.expect(t, transfer_record_layout_is_valid())
	testing.expect_value(t, align_of(Transfer_Scope_Record), 8)
	testing.expect_value(t, align_of(Transfer_Region_Record), 8)
	testing.expect_value(t, align_of(Transfer_Ring_Header_Record), 8)
	testing.expect_value(t, align_of(Transfer_Ring_Entry_Record), 8)

	empty_bytes, empty_ok := transfer_ring_record_bytes(0)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty_bytes, TRANSFER_RING_HEADER_BYTES)

	maximum_bytes, maximum_ok := transfer_ring_record_bytes(MAX_TRANSFER_INSPECTION_ENTRIES)
	testing.expect(t, maximum_ok)
	testing.expect_value(
		t,
		maximum_bytes,
		TRANSFER_RING_HEADER_BYTES + MAX_TRANSFER_INSPECTION_ENTRIES * TRANSFER_RING_ENTRY_BYTES,
	)

	_, oversized_ok := transfer_ring_record_bytes(MAX_TRANSFER_INSPECTION_ENTRIES + 1)
	testing.expect(t, !oversized_ok)
}
