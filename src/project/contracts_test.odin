// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:testing"

/* Verifies untrusted memberships retain file access but deny executable behavior. */
@(test)
executable_capabilities_require_trust :: proc(t: ^testing.T) {
	file_behaviors := [?]Restricted_Behavior {
		Restricted_Behavior.Read,
		Restricted_Behavior.Edit,
		Restricted_Behavior.Save,
		Restricted_Behavior.Search,
	}
	for behavior in file_behaviors {
		testing.expect(t, trust_allows_behavior(.Untrusted, behavior))
		testing.expect(t, trust_allows_behavior(.Trusted, behavior))
	}
	executable_behaviors := [?]Restricted_Behavior {
		Restricted_Behavior.Configuration,
		Restricted_Behavior.Tool,
		Restricted_Behavior.Process,
		Restricted_Behavior.Language_Service,
		Restricted_Behavior.Extension,
		Restricted_Behavior.Command_Definition,
		Restricted_Behavior.Keymap_Definition,
	}
	for behavior in executable_behaviors {
		testing.expect(t, !trust_allows_behavior(.Untrusted, behavior))
		testing.expect(t, trust_allows_behavior(.Trusted, behavior))
	}
	testing.expect(t, !trust_allows_behavior(.Invalid, .Read))
	testing.expect(t, !trust_allows_behavior(.Trusted, .Invalid))
}

/* Verifies the measured default and complete validated Project policy envelope. */
@(test)
policy_admits_valid_extremes :: proc(t: ^testing.T) {
	default_ok, default_failure := policy_validate(DEFAULT_POLICY)
	testing.expect(t, default_ok)
	testing.expect_value(t, default_failure.code, Failure_Code.None)

	minimum := Policy{
		catalog_projects = MIN_CATALOG_PROJECTS,
		directories = MIN_DIRECTORIES,
		name_bytes = MIN_NAME_BYTES,
		retained_path_bytes = MIN_RETAINED_PATH_BYTES,
		descriptor_batch = MIN_DESCRIPTOR_BATCH,
		file_candidates = MIN_FILE_CANDIDATES,
		examined_entries = MIN_EXAMINED_ENTRIES,
		entries_per_turn = MIN_ENTRIES_PER_TURN,
		dirty_markers = MIN_DIRTY_MARKERS,
		diagnostics = MIN_DIAGNOSTICS,
		diagnostic_bytes = MIN_DIAGNOSTIC_BYTES,
	}
	minimum_ok, _ := policy_validate(minimum)
	testing.expect(t, minimum_ok)

	maximum := Policy{
		catalog_projects = MAX_CATALOG_PROJECTS,
		directories = MAX_DIRECTORIES,
		name_bytes = MAX_NAME_BYTES,
		retained_path_bytes = MAX_RETAINED_PATH_BYTES,
		descriptor_batch = MAX_DESCRIPTOR_BATCH,
		file_candidates = MAX_FILE_CANDIDATES,
		examined_entries = MAX_EXAMINED_ENTRIES,
		entries_per_turn = MAX_ENTRIES_PER_TURN,
		dirty_markers = MAX_DIRECTORIES,
		diagnostics = MAX_DIAGNOSTICS,
		diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
	}
	maximum_ok, _ := policy_validate(maximum)
	testing.expect(t, maximum_ok)
}

/* Verifies policy validation distinguishes range and cross-field failures. */
@(test)
policy_rejects_range_and_relationship_failures :: proc(t: ^testing.T) {
	range_policy := DEFAULT_POLICY
	range_policy.directories = 0
	range_ok, range_failure := policy_validate(range_policy)
	testing.expect(t, !range_ok)
	testing.expect_value(t, range_failure.code, Failure_Code.Policy_Range)
	testing.expect_value(t, range_failure.field, Policy_Field.Directories)

	relationship_policy := DEFAULT_POLICY
	relationship_policy.examined_entries = MIN_EXAMINED_ENTRIES
	relationship_policy.entries_per_turn = MIN_EXAMINED_ENTRIES + 1
	relationship_ok, relationship_failure := policy_validate(relationship_policy)
	testing.expect(t, !relationship_ok)
	testing.expect_value(t, relationship_failure.code, Failure_Code.Policy_Relationship)
	testing.expect_value(t, relationship_failure.field, Policy_Field.Entries_Per_Turn)
}

/* Verifies checked Project identity shapes reject zero generations. */
@(test)
checked_handles_require_full_nonzero_identity :: proc(t: ^testing.T) {
	owner := Owner_Handle{id = Owner_ID(1), generation = Owner_Generation(2)}
	project := Project_Handle{owner = owner, id = Project_ID(3), generation = Project_Generation(4)}
	membership := Membership_Handle{
		project = project,
		id = Membership_ID(5),
		slot = 0,
		generation = Membership_Generation(6),
	}
	testing.expect(t, owner_handle_is_valid(owner))
	testing.expect(t, project_handle_is_valid(project))
	testing.expect(t, membership_handle_is_valid(membership))

	membership.generation = Membership_Generation(0)
	testing.expect(t, !membership_handle_is_valid(membership))
	project.generation = Project_Generation(0)
	testing.expect(t, !project_handle_is_valid(project))
	owner.generation = Owner_Generation(0)
	testing.expect(t, !owner_handle_is_valid(owner))
}
