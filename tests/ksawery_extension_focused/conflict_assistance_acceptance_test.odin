// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import "core:testing"

/* conflict_assistance_acceptance_observation builds one representative class payload. */
conflict_assistance_acceptance_observation :: proc(
	classes: ksawery.Conflict_Assistance_Classes,
) -> ksawery.Conflict_Assistance_Observation {
	target := conflict_assistance_test_target()
	target.classes = classes
	observation := ksawery.Conflict_Assistance_Observation {
		target = target,
		sides = {
			{kind = .Base, material = .Missing},
			{kind = .Current, material = .Missing},
			{kind = .Applied, material = .Missing},
			{kind = .Worktree, material = .Missing},
		},
	}
	if .Text in classes {
		observation.content = transmute([]u8)(string("conflicted text"))
		observation.sides[3] = {
			kind = .Worktree,
			material = .Text,
			mode = 0o100644,
			content = {0, u32(len(observation.content))},
		}
	}
	if .Binary in classes {
		observation.content = transmute([]u8)(string("\x00\x01binary"))
		observation.sides[3] = {
			kind = .Worktree,
			material = .Binary,
			mode = 0o100644,
			content = {0, u32(len(observation.content))},
		}
	}
	if .Submodule in classes {
		observation.sides[0] = {
			kind = .Base,
			material = .Submodule,
			mode = 0o160000,
			object = conflict_assistance_test_revision("1111111111111111111111111111111111111111"),
		}
	}
	if .Type_Change in classes {
		observation.sides[0] = {
			kind = .Base,
			material = .Omitted,
			mode = 0o100644,
			object = conflict_assistance_test_revision("1111111111111111111111111111111111111111"),
			truncated = true,
		}
		observation.sides[1] = {
			kind = .Current,
			material = .Omitted,
			mode = 0o100755,
			object = conflict_assistance_test_revision("2222222222222222222222222222222222222222"),
			truncated = true,
		}
		observation.truncated = true
	}
	if .Truncated in classes && !observation.truncated {
		observation.sides[0] = {
			kind = .Base,
			material = .Omitted,
			mode = 0o100644,
			object = conflict_assistance_test_revision("1111111111111111111111111111111111111111"),
			truncated = true,
		}
		observation.truncated = true
	}
	return observation
}

/* Verifies every planned Conflict class is copied or explicitly omitted within bounds. */
@(test)
conflict_assistance_accepts_complete_conflict_class_matrix :: proc(t: ^testing.T) {
	cases := [?]struct {
		name: string,
		classes: ksawery.Conflict_Assistance_Classes,
	} {
		{"text", {.Text}},
		{"binary", {.Binary}},
		{"rename", {.Rename}},
		{"delete", {.Delete}},
		{"type change", {.Type_Change, .Truncated}},
		{"submodule", {.Submodule}},
		{"missing stage", {.Missing_Stage}},
		{"truncated", {.Truncated}},
		{"unsupported", {.Unsupported}},
	}
	provider := ksawery.conflict_assistance_builtin_no_op_provider()
	for test_case in cases {
		observation := conflict_assistance_acceptance_observation(test_case.classes)
		_, failure := ksawery.conflict_assistance_observation_validate(observation)
		testing.expectf(
			t,
			failure.code == .None,
			"%s observation failed: %v",
			test_case.name,
			failure.code,
		)
		testing.expectf(
			t,
			ksawery.conflict_assistance_provider_supports(provider, observation.target),
			"fallback did not support %s",
			test_case.name,
		)
	}
}

/* Verifies stale targets and selection replacement revoke prior provider requests. */
@(test)
conflict_assistance_revokes_stale_target_and_selection :: proc(t: ^testing.T) {
	provider, _ := conflict_assistance_test_provider()
	selection := conflict_assistance_test_selection(provider)
	request := ksawery.Conflict_Assistance_Request {
		request = 53,
		selection_generation = selection.generation,
		provider = selection.provider,
		target = conflict_assistance_test_target(),
	}
	response := ksawery.Conflict_Assistance_Response {
		request = request.request,
		provider = request.provider,
		target = request.target,
		kind = .Declined,
	}
	response.target.observation_generation += 1
	_, failure := ksawery.conflict_assistance_response_validate(response, request, provider)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Stale_Target)
	selection.generation += 1
	failure = ksawery.conflict_assistance_request_validate(request, provider, selection)
	testing.expect_value(t, failure.code, ksawery.Conflict_Assistance_Failure_Code.Stale_Selection)
}
