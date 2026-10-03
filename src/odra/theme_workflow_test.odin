// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../theme"
import "core:testing"

/* Verifies theme candidates retain the exact selection and immutable definition identity. */
@(test)
theme_actions_reject_bad_selection :: proc(t: ^testing.T) {
	selection := theme.Selection {
		registry_id = 11,
		registry_generation = 12,
		selection_generation = 13,
	}
	action := interaction.Candidate_Action {
		kind = .Select_Theme,
		owner_generation = 12,
		primary = 11,
		secondary = 13,
		graph_identity = {21, 22, 23, 24, 0, 0},
	}
	definition, decoded := theme_candidate_action_definition(action, selection)
	testing.expect(t, decoded)
	testing.expect_value(t, definition.registry_id, theme.Registry_ID(11))
	testing.expect_value(t, definition.provider_id, theme.Provider_ID(21))
	testing.expect_value(t, definition.provider_generation, theme.Provider_Generation(22))
	testing.expect_value(t, definition.definition_id, theme.Definition_ID(23))
	testing.expect_value(t, definition.definition_generation, theme.Definition_Generation(24))

	stale := selection
	stale.selection_generation += 1
	_, stale_decoded := theme_candidate_action_definition(action, stale)
	testing.expect(t, !stale_decoded)

	malformed := action
	malformed.graph_identity[2] = 0
	_, malformed_decoded := theme_candidate_action_definition(malformed, selection)
	testing.expect(t, !malformed_decoded)
}
