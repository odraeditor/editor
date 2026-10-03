// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import ksawery "../../src/ksawery"
import "core:testing"

/* Verifies external-operation command submissions keep one fixed bounded ABI. */
@(test)
extension_command_submission_records_are_fixed_and_bounded :: proc(t: ^testing.T) {
	testing.expect(t, bridge.ksawery_extension_command_submission_record_layout_is_valid())
	command_context: [184]u8
	payload := transmute([]u8)string("refs/heads/main")
	values := [1]bridge.Ksawery_Extension_Command_Value_Record {{
		argument_id = 9,
		kind = u64(ksawery.Extension_Command_Argument_Kind.Ref),
		target_family = u64(ksawery.Extension_Annotation_Target_Family.Ref),
		target_generation = 19,
		target_bytes = u64(len(payload)),
	}}
	record_bytes, size_failure := bridge.ksawery_extension_command_submission_record_bytes(
		1, u64(len(command_context)), u64(len(payload)),
	)
	testing.expect_value(t, size_failure.code, bridge.Ksawery_Extension_Command_Submission_Failure_Code.None)
	header := bridge.Ksawery_Extension_Command_Submission_Header_Record {
		schema_version = bridge.KSAWERY_EXTENSION_COMMAND_SUBMISSION_SCHEMA_VERSION,
		record_bytes = record_bytes,
		request_id = 71,
		family_id = 11,
		family_generation = 17,
		action_id = 1,
		confirmation_id = 41,
		argument_count = 1,
		context_bytes = u64(len(command_context)),
		payload_bytes = u64(len(payload)),
	}
	failure := bridge.ksawery_extension_command_submission_records_validate(
		header, values[:], command_context[:], payload,
	)
	testing.expect_value(t, failure.code, bridge.Ksawery_Extension_Command_Submission_Failure_Code.None)
	values[0].target_generation = 0
	failure = bridge.ksawery_extension_command_submission_records_validate(
		header, values[:], command_context[:], payload,
	)
	testing.expect_value(t, failure.code, bridge.Ksawery_Extension_Command_Submission_Failure_Code.Invalid_Value)
}
