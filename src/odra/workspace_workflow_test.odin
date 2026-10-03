// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../interaction"
import "core:testing"

/* workspace_candidate_actions_reject_stale_catalog_and_record_generations. */
@(test)
workspace_actions_reject_stale_generations :: proc(t: ^testing.T) {
	descriptors := []command.Workspace_Command_Descriptor {
		{id = "daily-work", generation = 3, name = "Daily Work", member_count = 2},
		{id = "research", generation = 7, name = "Research", member_count = 4},
	}
	action := interaction.Candidate_Action {
		kind = .Open_Workspace,
		owner_generation = 11,
		primary = 2,
		secondary = 7,
	}
	descriptor, valid := workspace_candidate_action_descriptor(action, 11, descriptors)
	testing.expect(t, valid)
	if valid do testing.expect_value(t, descriptor.id, "research")
	_, stale_catalog := workspace_candidate_action_descriptor(action, 12, descriptors)
	testing.expect(t, !stale_catalog)
	action.secondary = 8
	_, stale_record := workspace_candidate_action_descriptor(action, 11, descriptors)
	testing.expect(t, !stale_record)
	action.primary = 3
	_, invalid_index := workspace_candidate_action_descriptor(action, 11, descriptors)
	testing.expect(t, !invalid_index)
}
