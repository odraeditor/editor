// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

/* Verifies the complete final inventory and explicit optional unavailability. */
@(test)
jan_future_stage_capabilities_are_complete_and_read_only :: proc(t: ^testing.T) {
	source := "* TODO Preserved\n#+begin_src odin\nmain :: proc() {}\n#+end_src\n"
	before := source
	records := jan_capability_availability()
	testing.expect_value(t, len(records), JAN_CAPABILITY_COUNT)
	seen_stages: bit_set[Jan_Stage]
	for record, index in records {
		testing.expect(t, jan_availability_record_is_valid(record))
		if index < 5 {
			testing.expect_value(t, record.class, Jan_Availability_Class.Factory_Native)
			testing.expect(t, record.available)
			testing.expect_value(t, record.owner, Jan_Stage.Structured_Editing)
		} else if index < 11 {
			testing.expect_value(t, record.class, Jan_Availability_Class.Factory_Native)
			testing.expect(t, record.available)
			testing.expect_value(t, record.owner, Jan_Stage.Planning_And_Agenda)
		} else if index == 11 || index == 14 {
			testing.expect_value(t, record.class, Jan_Availability_Class.Factory_Native)
			testing.expect(t, record.available)
		} else {
			testing.expect(t, record.class == .Factory_Adapter || record.class == .Configured_Provider)
			testing.expect(t, !record.available)
		}
		testing.expect(t, record.owner >= .Structured_Editing)
		seen_stages += {record.owner}
		for prior in records[:index] {
			left := record.capability
			right := prior.capability
			testing.expect(t, !jan_bounded_text_equal(
				left.bytes[:], left.length,
				right.bytes[:], right.length,
			))
		}
	}
	testing.expect(t, .Structured_Editing in seen_stages)
	testing.expect(t, .Planning_And_Agenda in seen_stages)
	testing.expect(t, .Computable_Documents in seen_stages)
	testing.expect(t, .Export_Publishing_And_Integration in seen_stages)
	future := jan_future_stage_availability()
	testing.expect_value(t, len(future), JAN_FUTURE_CAPABILITY_COUNT)
	for record in future {
		testing.expect(t, record.class != .Future_Stage)
	}
	testing.expect_value(t, source, before)
}

@(private)
jan_bounded_text_equal :: proc(left: []u8, left_length: u16, right: []u8, right_length: u16) -> bool {
	if left_length != right_length do return false
	for value, index in left[:left_length] do if value != right[index] do return false
	return true
}
