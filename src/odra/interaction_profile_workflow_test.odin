// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "core:testing"

/* Verifies profile candidates retain exact catalog and snapshot identities. */
@(test)
interaction_profile_actions_reject_stale_identity :: proc(t: ^testing.T) {
	profiles := [1]interaction.Profile_Definition {{
		identity = {id = 2, revision = 3},
		name = "modal",
	}}
	catalog := interaction.Profile_Catalog_Definition {
		generation = 7,
		profiles = profiles[:],
	}
	action := interaction.Candidate_Action {
		kind = .Select_Interaction_Profile,
		owner_generation = 7,
		primary = 11,
		graph_identity = {2, 3, 0, 0, 0, 0},
	}
	target, decoded := interaction_profile_candidate_action(action, catalog, 11)
	testing.expect(t, decoded)
	testing.expect_value(t, target, interaction.Profile_Identity{id = 2, revision = 3})

	stale := action
	stale.primary = 12
	_, stale_decoded := interaction_profile_candidate_action(stale, catalog, 11)
	testing.expect(t, !stale_decoded)

	malformed := action
	malformed.graph_identity[1] = 0
	_, malformed_decoded := interaction_profile_candidate_action(malformed, catalog, 11)
	testing.expect(t, !malformed_decoded)
}
