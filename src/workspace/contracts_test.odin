// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package workspace

import "core:testing"

@(test)
/* Verifies the measured Workspace defaults remain within hard bounds. */
workspace_policy_accepts_measured_defaults :: proc(t: ^testing.T) {
	ok, failure := policy_validate(DEFAULT_POLICY)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)

	invalid := DEFAULT_POLICY
	invalid.projects = 0
	invalid_ok, invalid_failure := policy_validate(invalid)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.field, Policy_Field.Projects)
}

@(test)
/* Verifies persistent Workspaces require one or more distinct valid Project references. */
records_require_distinct_projects :: proc(t: ^testing.T) {
	projects := [?]Project_Reference_Proposal {
		{id = "first", expected_generation = 1, root = "/work/first"},
		{id = "second", expected_generation = 2, root = "/work/second"},
	}
	proposal := Record_Proposal {
		format_version = FORMAT_VERSION,
		id = "daily-work",
		generation = 1,
		name = "Daily Work",
		projects = projects[:],
	}
	ok, failure := record_proposal_validate(proposal)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)

	proposal.projects = projects[:0]
	cardinality_ok, cardinality_failure := record_proposal_validate(proposal)
	testing.expect(t, !cardinality_ok)
	testing.expect_value(t, cardinality_failure.code, Failure_Code.Invalid_Cardinality)

	proposal.projects = projects[:1]
	one_ok, one_failure := record_proposal_validate(proposal)
	testing.expect(t, one_ok)
	testing.expect_value(t, one_failure.code, Failure_Code.None)

	projects[1].id = "first"
	proposal.projects = projects[:]
	duplicate_ok, duplicate_failure := record_proposal_validate(proposal)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Project)
}
