// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import ksawery "../../src/ksawery"
import "core:testing"

/* operation_record_fixture builds one complete configured-executable envelope. */
operation_record_fixture :: proc() -> (
	bridge.Ksawery_Extension_Operation_Header_Record,
	bridge.Ksawery_Extension_Operation_Limits_Record,
	bridge.Ksawery_Extension_Operation_Verifier_Record,
	[2]bridge.Ksawery_Extension_Operation_Argument_Record,
	[]u8,
) {
	contributor_identity :: "personal.repository-tools"
	plan_identity :: "operations.inspect-ref"
	purpose :: "Inspect one ref"
	executable_identity :: "tools.inspector"
	executable_path :: "/opt/odra/bin/inspect"
	target :: "refs/heads/main"
	first_argument :: "--ref"
	second_argument :: "refs/heads/main"
	text_value :: contributor_identity + plan_identity + purpose + executable_identity +
		executable_path + target + first_argument + second_argument
	text := transmute([]u8)(string(text_value))
	contributor_offset :: 0
	plan_offset :: contributor_offset + len(contributor_identity)
	purpose_offset :: plan_offset + len(plan_identity)
	executable_identity_offset :: purpose_offset + len(purpose)
	executable_path_offset :: executable_identity_offset + len(executable_identity)
	target_offset :: executable_path_offset + len(executable_path)
	first_argument_offset :: target_offset + len(target)
	second_argument_offset :: first_argument_offset + len(first_argument)
	arguments := [2]bridge.Ksawery_Extension_Operation_Argument_Record {
		{offset = u64(first_argument_offset), bytes = u64(len(first_argument))},
		{offset = u64(second_argument_offset), bytes = u64(len(second_argument))},
	}
	header := bridge.Ksawery_Extension_Operation_Header_Record {
		schema_version = bridge.KSAWERY_EXTENSION_OPERATION_SCHEMA_VERSION,
		contributor_generation = 5,
		contribution_id = 7,
		plan_id = 11,
		plan_generation = 17,
		effect = u64(ksawery.Extension_Operation_Effect.Read_Only),
		refresh_observations = (u64(1) << u64(ksawery.Extension_Observation_Family.Status)) |
			(u64(1) << u64(ksawery.Extension_Observation_Family.Refs)),
		environment_profile = u64(ksawery.Extension_Operation_Environment_Profile.Core_Repository),
		diagnostic_policy = u64(ksawery.Extension_Operation_Diagnostic_Policy.Bounded_Public),
		executable_kind = u64(ksawery.Extension_Operation_Executable_Kind.Configured_Absolute_Path),
		argument_count = u64(len(arguments)),
		contributor_identity_offset = u64(contributor_offset),
		contributor_identity_bytes = u64(len(contributor_identity)),
		identity_offset = u64(plan_offset),
		identity_bytes = u64(len(plan_identity)),
		purpose_offset = u64(purpose_offset),
		purpose_bytes = u64(len(purpose)),
		executable_identity_offset = u64(executable_identity_offset),
		executable_identity_bytes = u64(len(executable_identity)),
		executable_path_offset = u64(executable_path_offset),
		executable_path_bytes = u64(len(executable_path)),
		text_bytes = u64(len(text)),
	}
	header.record_bytes, _ = bridge.ksawery_extension_operation_record_bytes(
		header.argument_count, header.text_bytes,
	)
	limits := bridge.Ksawery_Extension_Operation_Limits_Record {
		output_bytes = ksawery.DEFAULT_EXTENSION_OPERATION_OUTPUT_BYTES,
		diagnostic_bytes = ksawery.DEFAULT_EXTENSION_OPERATION_DIAGNOSTIC_BYTES,
		deadline_nanoseconds = u64(ksawery.DEFAULT_EXTENSION_OPERATION_DEADLINE_NS),
		cancellation_grace_ns = u64(ksawery.DEFAULT_EXTENSION_OPERATION_CANCELLATION_GRACE_NS),
	}
	verifier := bridge.Ksawery_Extension_Operation_Verifier_Record {
		kind = u64(ksawery.Extension_Operation_Verifier_Kind.Target_Present),
		observation = u64(ksawery.Extension_Observation_Family.Refs),
		target_family = u64(ksawery.Extension_Annotation_Target_Family.Ref),
		target_generation = 19,
		target_offset = u64(target_offset),
		target_bytes = u64(len(target)),
	}
	return header, limits, verifier, arguments, text
}

/* Verifies exact ABI widths and a complete configured executable declaration. */
@(test)
operation_records_accept_declared_plan :: proc(t: ^testing.T) {
	header, limits, verifier, arguments, text := operation_record_fixture()
	testing.expect(t, bridge.ksawery_extension_operation_record_layout_is_valid())
	failure := bridge.ksawery_extension_operation_records_validate(
		header, limits, verifier, arguments[:], text,
	)
	testing.expect_value(
		t, failure.code, bridge.Ksawery_Extension_Operation_Record_Failure_Code.None,
	)
}

/* Verifies malformed paths, counts, limits, and typed verifiers fail closed. */
@(test)
operation_records_reject_malformed_plan :: proc(t: ^testing.T) {
	header, limits, verifier, arguments, text := operation_record_fixture()

	invalid_header := header
	invalid_header.executable_path_offset += 1
	failure := bridge.ksawery_extension_operation_records_validate(
		invalid_header, limits, verifier, arguments[:], text,
	)
	testing.expect_value(
		t, failure.code, bridge.Ksawery_Extension_Operation_Record_Failure_Code.Invalid_Executable,
	)

	invalid_header = header
	invalid_header.argument_count += 1
	failure = bridge.ksawery_extension_operation_records_validate(
		invalid_header, limits, verifier, arguments[:], text,
	)
	testing.expect_value(
		t, failure.code, bridge.Ksawery_Extension_Operation_Record_Failure_Code.Size_Mismatch,
	)

	invalid_limits := limits
	invalid_limits.deadline_nanoseconds = u64(ksawery.MAX_EXTENSION_OPERATION_DEADLINE_NS) + 1
	failure = bridge.ksawery_extension_operation_records_validate(
		header, invalid_limits, verifier, arguments[:], text,
	)
	testing.expect_value(
		t, failure.code, bridge.Ksawery_Extension_Operation_Record_Failure_Code.Invalid_Limits,
	)

	invalid_verifier := verifier
	invalid_verifier.observation = u64(ksawery.Extension_Observation_Family.History)
	failure = bridge.ksawery_extension_operation_records_validate(
		header, limits, invalid_verifier, arguments[:], text,
	)
	testing.expect_value(
		t, failure.code, bridge.Ksawery_Extension_Operation_Record_Failure_Code.Invalid_Verifier,
	)
}
