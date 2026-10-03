// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../status_bar"
import endian "core:encoding/endian"
import "core:testing"

/* Verifies programmable Status Bar ABI records and copied quotas remain exact. */
@(test)
status_bar_record_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, status_bar_record_layout_is_valid())
	maximum, maximum_ok := status_bar_proposal_record_bytes(
		MAX_STATUS_BAR_EXTENSION_SEGMENTS,
		MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES,
	)
	testing.expect(t, maximum_ok)
	testing.expect_value(t, maximum, MAX_STATUS_BAR_PROPOSAL_BYTES)
	_, oversized := status_bar_proposal_record_bytes(MAX_STATUS_BAR_EXTENSION_SEGMENTS + 1, 0)
	testing.expect(t, !oversized)

	inspection, inspection_ok := status_bar_snapshot_record_bytes(
		MAX_STATUS_BAR_PROVIDERS,
		u64(status_bar.MAX_SEGMENTS),
		MAX_STATUS_BAR_PROPOSAL_TEXT_BYTES,
		MAX_STATUS_BAR_DIAGNOSTIC_BYTES,
	)
	testing.expect(t, inspection_ok)
	testing.expect_value(t, inspection, MAX_STATUS_BAR_INSPECTION_BYTES)
}

/* Verifies operation authority is closed and cannot be widened by numeric overlap. */
@(test)
status_bar_operations_require_exact_authority :: proc(t: ^testing.T) {
	testing.expect(t, status_bar_operation_is_authorized(.Scope, .Inspect))
	testing.expect(t, status_bar_operation_is_authorized(.Inspect, .Inspect))
	testing.expect(t, status_bar_operation_is_authorized(.Register, .Register))
	testing.expect(t, status_bar_operation_is_authorized(.Replace, .Replace))
	testing.expect(t, status_bar_operation_is_authorized(.Remove, .Remove))
	testing.expect(t, status_bar_operation_is_authorized(.Teardown, .Teardown))
	testing.expect(t, !status_bar_operation_is_authorized(.Replace, .Register))
	testing.expect(t, !status_bar_operation_is_authorized(.Remove, .Inspect))
}

/* Verifies exact little-endian scope decoding rejects stale or truncated identity. */
@(test)
status_bar_scope_checks_generation :: proc(t: ^testing.T) {
	words := [12]u64 {1, 3, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41}
	bytes: [STATUS_BAR_SCOPE_RECORD_BYTES]u8
	for value, index in words do testing.expect(t, endian.put_u64(bytes[index * 8:], .Little, value))
	record, decoded := status_bar_scope_record_decode(bytes[:])
	testing.expect(t, decoded)
	testing.expect_value(t, record.provider_id, u64(23))
	testing.expect_value(t, record.capability_generation, u64(41))
	_, decoded = status_bar_scope_record_decode(bytes[:len(bytes) - 1])
	testing.expect(t, !decoded)
	endian.put_u64(bytes[:], .Little, STATUS_BAR_CAPABILITY_SCHEMA_VERSION + 1)
	_, decoded = status_bar_scope_record_decode(bytes[:])
	testing.expect(t, !decoded)
}

/* Verifies segment decoding preserves every copied text and command range. */
@(test)
status_bar_segment_decoding_preserves_all_fields :: proc(t: ^testing.T) {
	bytes: [STATUS_BAR_SEGMENT_RECORD_BYTES]u8
	for index in 0 ..< 24 do testing.expect(
		t,
		endian.put_u64(bytes[index * 8:], .Little, u64(index + 1)),
	)
	record, decoded := status_bar_segment_record_decode(bytes[:])
	testing.expect(t, decoded)
	testing.expect_value(t, record.provider_id, u64(1))
	testing.expect_value(t, record.style_role, u64(12))
	testing.expect_value(t, record.secondary_command_bytes, u64(24))
	_, decoded = status_bar_segment_record_decode(bytes[:len(bytes) - 8])
	testing.expect(t, !decoded)
}
