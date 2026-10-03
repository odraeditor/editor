// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../interaction"
import "../project"
import "core:testing"

/* project_selection_actions_reject_stale_catalog_and_record_generations. */
@(test)
project_actions_reject_stale_generations :: proc(t: ^testing.T) {
	candidates := []command.Project_Directory_Candidate {
		{
			project_generation = project.Project_Generation(3),
			durable_id = "odra",
			name = "Odra",
			path = "/tmp/odra",
		},
		{
			project_generation = project.Project_Generation(7),
			durable_id = "notes",
			name = "Notes",
			path = "/tmp/notes",
		},
	}
	action := interaction.Candidate_Action {
		kind = .Open_Project,
		owner_generation = 11,
		primary = 2,
		secondary = 7,
	}
	candidate, valid := project_selection_action_candidate(action, 11, candidates)
	testing.expect(t, valid)
	if valid do testing.expect_value(t, candidate.durable_id, "notes")
	_, stale_catalog := project_selection_action_candidate(action, 12, candidates)
	testing.expect(t, !stale_catalog)
	action.secondary = 8
	_, stale_record := project_selection_action_candidate(action, 11, candidates)
	testing.expect(t, !stale_record)
	action.primary = 3
	_, invalid_index := project_selection_action_candidate(action, 11, candidates)
	testing.expect(t, !invalid_index)
}
