// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/ksawery_bridge"
import ksawery "../../src/ksawery"
import "core:testing"

/* Verifies conflict-assistance bridge records retain their fixed ABI widths. */
@(test)
conflict_assistance_record_layout_is_fixed :: proc(t: ^testing.T) {
	testing.expect(t, bridge.ksawery_conflict_assistance_record_layout_is_valid())
}

/* Verifies provider, selection, and response records reject malformed fields. */
@(test)
conflict_assistance_control_records_are_bounded :: proc(t: ^testing.T) {
	contributor := "personal.conflict-tools"
	identity := "conflict.helper"
	label := "Conflict helper"
	payload_text := "personal.conflict-toolsconflict.helperConflict helper"
	payload := transmute([]u8)payload_text
	provider := bridge.Ksawery_Conflict_Assistance_Provider_Record {
		schema_version = bridge.KSAWERY_CONFLICT_ASSISTANCE_SCHEMA_VERSION,
		record_bytes = bridge.KSAWERY_CONFLICT_ASSISTANCE_PROVIDER_BYTES + u64(len(payload)),
		origin = u64(ksawery.Conflict_Assistance_Provider_Origin.Extension),
		contributor_generation = 5,
		contribution_id = 7,
		provider_id = 11,
		provider_generation = 13,
		supported_classes = 0b10010010,
		capabilities = 0b111,
		lifecycle = u64(ksawery.Conflict_Assistance_Provider_Lifecycle.Active),
		contributor_identity_bytes = u64(len(contributor)),
		identity_offset = u64(len(contributor)),
		identity_bytes = u64(len(identity)),
		label_offset = u64(len(contributor) + len(identity)),
		label_bytes = u64(len(label)),
		payload_bytes = u64(len(payload)),
	}
	failure := bridge.ksawery_conflict_assistance_provider_record_validate(provider, payload)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.None)
	provider.capabilities = 0
	failure = bridge.ksawery_conflict_assistance_provider_record_validate(provider, payload)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.Invalid_Provider)

	selection_payload_text := "personal.conflict-tools/tmp/odra-conflict-assistance"
	selection_payload := transmute([]u8)selection_payload_text
	repository_offset := u64(len("personal.conflict-tools"))
	selection := bridge.Ksawery_Conflict_Assistance_Selection_Record {
		schema_version = 1,
		record_bytes = bridge.KSAWERY_CONFLICT_ASSISTANCE_SELECTION_BYTES + u64(len(selection_payload)),
		action = 1,
		selection_id = 17,
		next_generation = 19,
		scope = u64(ksawery.Conflict_Assistance_Selection_Scope.Repository),
		provider_origin = u64(ksawery.Conflict_Assistance_Provider_Origin.Extension),
		contributor_generation = 5,
		provider_id = 11,
		provider_generation = 13,
		repository_offset = repository_offset,
		repository_bytes = u64(len("/tmp/odra-conflict-assistance")),
		confirmed = 1,
		payload_bytes = u64(len(selection_payload)),
		contributor_identity_bytes = repository_offset,
	}
	failure = bridge.ksawery_conflict_assistance_selection_record_validate(selection, selection_payload)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.None)
	selection.confirmed = 0
	failure = bridge.ksawery_conflict_assistance_selection_record_validate(selection, selection_payload)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.Invalid_Selection)

	guidance := transmute([]u8)(string("Compare Base and Current."))
	response := bridge.Ksawery_Conflict_Assistance_Response_Record {
		schema_version = 1,
		record_bytes = bridge.KSAWERY_CONFLICT_ASSISTANCE_RESPONSE_BYTES + u64(len(guidance)),
		request_id = 23,
		provider_id = 11,
		provider_generation = 13,
		kind = u64(ksawery.Conflict_Assistance_Response_Kind.Guidance),
		guidance_bytes = u64(len(guidance)),
		payload_bytes = u64(len(guidance)),
		contributor_generation = 5,
	}
	failure = bridge.ksawery_conflict_assistance_response_record_validate(response, guidance)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.None)
	response.tool_access = u64(ksawery.Conflict_Assistance_Tool_Access.Read_Only)
	failure = bridge.ksawery_conflict_assistance_response_record_validate(response, guidance)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.Invalid_Response)
}

/* Verifies one copied observation keeps four ordered sides and exact ranges. */
@(test)
conflict_assistance_observation_record_is_exact :: proc(t: ^testing.T) {
	repository := "/tmp/odra-conflict-assistance"
	path := "src/example.odin"
	base := "1111111111111111111111111111111111111111"
	current := "2222222222222222222222222222222222222222"
	payload_text := "/tmp/odra-conflict-assistancesrc/example.odin" +
		"1111111111111111111111111111111111111111" +
		"2222222222222222222222222222222222222222" +
		"basecurrentworktree"
	payload := transmute([]u8)payload_text
	path_offset := u64(len(repository))
	base_offset := path_offset + u64(len(path))
	current_offset := base_offset + u64(len(base))
	content_offset := current_offset + u64(len(current))
	sides := [4]bridge.Ksawery_Conflict_Assistance_Side_Record {
		{1, 2, 0o100644, base_offset, u64(len(base)), content_offset, 4, 0},
		{2, 2, 0o100644, current_offset, u64(len(current)), content_offset + 4, 7, 0},
		{3, 1, 0, 0, 0, 0, 0, 0},
		{4, 2, 0o100644, 0, 0, content_offset + 11, 8, 0},
	}
	record := bridge.Ksawery_Conflict_Assistance_Observation_Record {
		schema_version = 1,
		record_bytes = bridge.KSAWERY_CONFLICT_ASSISTANCE_OBSERVATION_BYTES +
			4 * bridge.KSAWERY_CONFLICT_ASSISTANCE_SIDE_BYTES + u64(len(payload)),
		repository_generation = 17,
		worktree_generation = 19,
		observation_generation = 23,
		sequence_generation = 29,
		sequence_fingerprint = 31,
		conflict_id = 37,
		conflict_kind = u64(ksawery.Conflict_Kind.Deleted_By_Them),
		classes = 0b10010010,
		side_count = 4,
		payload_bytes = u64(len(payload)),
		repository_bytes = u64(len(repository)),
		path_offset = path_offset,
		path_bytes = u64(len(path)),
	}
	failure := bridge.ksawery_conflict_assistance_observation_record_validate(
		record, sides[:], payload,
	)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.None)
	sides[2].kind = 4
	failure = bridge.ksawery_conflict_assistance_observation_record_validate(
		record, sides[:], payload,
	)
	testing.expect_value(t, failure.code, bridge.Ksawery_Conflict_Assistance_Record_Failure_Code.Invalid_Side)
}
