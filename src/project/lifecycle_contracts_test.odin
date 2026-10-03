// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:testing"

@(test)
/* Verifies the measured target Project lifecycle defaults remain within hard bounds. */
lifecycle_policy_accepts_defaults :: proc(t: ^testing.T) {
	ok, failure := lifecycle_policy_validate(DEFAULT_LIFECYCLE_POLICY)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Lifecycle_Failure_Code.None)

	invalid := DEFAULT_LIFECYCLE_POLICY
	invalid.promotion_suppressions = MAX_PROMOTION_SUPPRESSIONS + 1
	invalid_ok, invalid_failure := lifecycle_policy_validate(invalid)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Lifecycle_Failure_Code.Policy_Range)
	testing.expect_value(t, invalid_failure.field, Lifecycle_Policy_Field.Promotion_Suppressions)
}

@(test)
/* Verifies a target Project record owns exactly one valid root and explicit trust. */
project_records_require_root_and_trust :: proc(t: ^testing.T) {
	proposal := Local_Project_Proposal {
		format_version = TARGET_PROJECT_FORMAT_VERSION,
		id = "odra",
		generation = 1,
		name = "Odra",
		root = "/work/odra",
		trust = .Untrusted,
	}
	ok, failure := local_project_proposal_validate(proposal)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Lifecycle_Failure_Code.None)

	proposal.root = "relative"
	path_ok, path_failure := local_project_proposal_validate(proposal)
	testing.expect(t, !path_ok)
	testing.expect_value(t, path_failure.code, Lifecycle_Failure_Code.Invalid_Path)
}

@(test)
/* Verifies discovery, prompt preference, and migration records remain distinct. */
global_contracts_remain_separate :: proc(t: ^testing.T) {
	discovery_ok, _ := project_discovery_proposal_validate(Project_Discovery_Proposal {
		format_version = TARGET_REFERENCE_FORMAT_VERSION,
		id = "odra",
		expected_project_generation = 3,
		root = "/work/odra",
	})
	suppression_ok, _ := promotion_suppression_proposal_validate(Promotion_Suppression_Proposal {
		format_version = PROMOTION_SUPPRESSION_FORMAT_VERSION,
		generation = 2,
		root = "/work/scratch",
	})
	migration_ok, _ := migration_proposal_validate(Migration_Proposal {
		format_version = MIGRATION_FORMAT_VERSION,
		generation = 1,
		source_id = "legacy-odra",
		source_path = "/legacy/odra.rkt",
		target_id = "odra",
		state = .Planned,
	})
	testing.expect(t, discovery_ok)
	testing.expect(t, suppression_ok)
	testing.expect(t, migration_ok)
}
