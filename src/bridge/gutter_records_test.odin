// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import endian "core:encoding/endian"
import "core:testing"

@(test)
/* Verifies programmable Gutter records retain one stable bounded layout. */
gutter_record_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, gutter_record_layout_is_valid())
	maximum, maximum_ok := gutter_provider_record_bytes(
		MAX_GUTTER_PROGRAMMABLE_LANES,
		MAX_GUTTER_PROGRAMMABLE_MARKERS,
		MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES,
	)
	testing.expect(t, maximum_ok)
	testing.expect_value(t, maximum, MAX_GUTTER_PROVIDER_PROPOSAL_BYTES)
	_, lanes_oversized := gutter_provider_record_bytes(MAX_GUTTER_PROGRAMMABLE_LANES + 1, 0, 0)
	_, markers_oversized := gutter_provider_record_bytes(1, MAX_GUTTER_PROGRAMMABLE_MARKERS + 1, 0)
	_, text_oversized := gutter_provider_record_bytes(1, 0, MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES + 1)
	testing.expect(t, !lanes_oversized)
	testing.expect(t, !markers_oversized)
	testing.expect(t, !text_oversized)
}

@(test)
/* Verifies provider decoding rejects malformed schemas, generations, and widths. */
gutter_provider_record_decoding_is_exact :: proc(t: ^testing.T) {
	bytes: [GUTTER_PROVIDER_HEADER_BYTES]u8
	values := [?]u64 {
		GUTTER_PROVIDER_SCHEMA_VERSION, 7, 11, 1, 0, 1,
		GUTTER_PROVIDER_HEADER_BYTES + GUTTER_LANE_RECORD_BYTES,
		5,
		GUTTER_PROVIDER_HEADER_BYTES + GUTTER_LANE_RECORD_BYTES + 5,
		7,
		12,
		GUTTER_PROVIDER_HEADER_BYTES + GUTTER_LANE_RECORD_BYTES + 12,
	}
	for value, index in values do testing.expect(t, endian.put_u64(bytes[index * 8:], .Little, value))
	record, decoded := gutter_provider_record_decode(bytes[:])
	testing.expect(t, decoded)
	testing.expect_value(t, record.marker_generation, u64(11))

	endian.put_u64(bytes[:], .Little, GUTTER_PROVIDER_SCHEMA_VERSION + 1)
	_, decoded = gutter_provider_record_decode(bytes[:])
	testing.expect(t, !decoded)
	endian.put_u64(bytes[:], .Little, GUTTER_PROVIDER_SCHEMA_VERSION)
	endian.put_u64(bytes[8:], .Little, 0)
	_, decoded = gutter_provider_record_decode(bytes[:])
	testing.expect(t, !decoded)
	_, decoded = gutter_provider_record_decode(bytes[:len(bytes) - 1])
	testing.expect(t, !decoded)
}

@(test)
/* Verifies copied text ranges are sequential, bounded, valid UTF-8, and display-safe. */
gutter_text_rejects_unsafe_ranges :: proc(t: ^testing.T) {
	unsafe := "notesunsafe\x1b"
	value := transmute([]u8)unsafe
	text, ok := gutter_record_text(value, 0, 5, 0, 8)
	testing.expect(t, ok)
	testing.expect_value(t, text, "notes")
	_, ok = gutter_record_text(value, 1, 5, 0, 8)
	testing.expect(t, !ok)
	_, ok = gutter_record_text(value, 5, 7, 5, 4)
	testing.expect(t, !ok)
	_, ok = gutter_record_text(value, 5, 7, 5, 8)
	testing.expect(t, !ok)
	invalid_utf8 := []u8{0xff}
	_, ok = gutter_record_text(invalid_utf8, 0, 1, 0, 8)
	testing.expect(t, !ok)
}

@(test)
/* Verifies marker decoding retains every action range without pointer state. */
gutter_marker_record_decoding_preserves_actions :: proc(t: ^testing.T) {
	bytes: [GUTTER_MARKER_RECORD_BYTES]u8
	for index in 0 ..< 28 do testing.expect(
		t,
		endian.put_u64(bytes[index * 8:], .Little, u64(index + 1)),
	)
	record, decoded := gutter_marker_record_decode(bytes[:])
	testing.expect(t, decoded)
	testing.expect_value(t, record.logical_line, u64(5))
	testing.expect_value(t, record.action_count, u64(20))
	testing.expect_value(t, record.action_offsets[3], u64(27))
	testing.expect_value(t, record.action_bytes[3], u64(28))
	_, decoded = gutter_marker_record_decode(bytes[:len(bytes) - 8])
	testing.expect(t, !decoded)
}
