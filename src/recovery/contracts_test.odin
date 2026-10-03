// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:testing"

test_digest :: proc(seed: u8) -> Digest {
	digest: Digest
	digest[0] = seed
	return digest
}

/* Verifies the factory policy is complete and satisfies every immutable range. */
@(test)
factory_policy_is_admitted :: proc(t: ^testing.T) {
	ok, failure := policy_validate(DEFAULT_POLICY)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect(t, DEFAULT_POLICY.enabled)
	testing.expect_value(t, DEFAULT_POLICY.strategy, Strategy.Hybrid)
	testing.expect_value(t, DEFAULT_POLICY.source_autosave, Source_Autosave_Policy.Disabled)
}

/* Verifies policy validation rejects range and cross-field violations precisely. */
@(test)
policy_rejection_identifies_the_field :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.debounce_milliseconds = policy.maximum_interval_milliseconds + 1
	ok, failure := policy_validate(policy)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Policy)
	testing.expect_value(t, failure.field, Policy_Field.Debounce_Interval)

	policy = DEFAULT_POLICY
	policy.storage.record_payload_bytes = policy.storage.buffer_storage_bytes + 1
	ok, failure = policy_validate(policy)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.field, Policy_Field.Record_Payload_Bytes)
}

/* Verifies platform roots require Unix privacy modes without imposing them on Windows. */
@(test)
recovery_root_contract_is_platform_specific :: proc(t: ^testing.T) {
	linux := Root {
		platform = .Linux,
		state_root = "/state/odra",
		recovery_root = "/state/odra/recovery/v1",
		private_directory_mode = PRIVATE_DIRECTORY_MODE,
		private_file_mode = PRIVATE_FILE_MODE,
	}
	ok, _ := root_validate(linux)
	testing.expect(t, ok)
	linux.private_directory_mode = 0o755
	failure: Failure_Context
	ok, failure = root_validate(linux)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Root)

	windows := Root {
		platform = .Windows,
		state_root = "C:\\State\\Odra",
		recovery_root = "C:\\State\\Odra\\recovery\\v1",
	}
	ok, _ = root_validate(windows)
	testing.expect(t, ok)
}

/* Verifies records bind revisions, fingerprints, payloads, and policy generation. */
@(test)
recovery_record_requires_complete_metadata :: proc(t: ^testing.T) {
	record := Record {
		record_id = Record_ID(1),
		buffer_id = Buffer_ID(2),
		source_present = true,
		source_identity = "/project/note.txt",
		source_fingerprint = test_digest(1),
		saved_revision = 4,
		recovered_revision = 5,
		encoding = .UTF_8,
		line_ending = .LF,
		payload_digest = test_digest(2),
		payload_bytes = 4_096,
		created_at_seconds = 1,
		policy_generation = DEFAULT_POLICY.generation,
		format_version = RECOVERY_FORMAT_VERSION,
	}
	ok, _ := record_validate(record, DEFAULT_POLICY)
	testing.expect(t, ok)
	record.recovered_revision = record.saved_revision
	failure: Failure_Context
	ok, failure = record_validate(record, DEFAULT_POLICY)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Record)
}

/* Verifies conflict candidates expose comparison while quarantine cannot restore. */
@(test)
candidate_actions_follow_candidate_state :: proc(t: ^testing.T) {
	conflict := Candidate {
		record_id = Record_ID(1),
		buffer_id = Buffer_ID(2),
		state = .Conflict,
		conflict = .Source_Changed,
		actions = {.Inspect, .Compare, .Restore, .Discard},
		action_count = 4,
		recovered_revision = 5,
	}
	ok, _ := candidate_validate(conflict)
	testing.expect(t, ok)

	quarantined := Candidate {
		record_id = Record_ID(1),
		buffer_id = Buffer_ID(2),
		state = .Quarantined,
		quarantine = .Digest_Mismatch,
		actions = {.Inspect, .Discard, .Invalid, .Invalid},
		action_count = 2,
		recovered_revision = 5,
	}
	ok, _ = candidate_validate(quarantined)
	testing.expect(t, ok)
	quarantined.actions[2] = .Restore
	quarantined.action_count = 3
	failure: Failure_Context
	ok, failure = candidate_validate(quarantined)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Candidate)
}
