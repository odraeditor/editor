// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* TEST_RACKET_COMMAND_COUNT fixes the admitted Racket fixture width. */
TEST_RACKET_COMMAND_COUNT :: 7

/* test_racket_command_definitions mirrors an admitted catalog for command unit tests. */
test_racket_command_definitions :: proc() -> [TEST_RACKET_COMMAND_COUNT]interaction.Command_Definition {
	inspection_provenance := interaction.Definition_Provenance {
		provider = "odra-racket",
		source = "src/command/keymap-inspection.rkt",
	}
	catalog_provenance := interaction.Definition_Provenance {
		provider = "odra-racket",
		source = "src/command/catalog.rkt",
	}
	return {
		{
			name = "describe-key",
			route = racket_route(.Keymap_Inspection, 1),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Describe the active command and alternatives for a key sequence.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "where-is",
			route = racket_route(.Keymap_Inspection, 2),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "List active key sequences associated with a command.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "describe-bindings",
			route = racket_route(.Keymap_Inspection, 3),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "List active keymaps in resolution order.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "describe-keymap",
			route = racket_route(.Keymap_Inspection, 4),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Describe one keymap and its bindings and remaps.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "describe-keymap-conflicts",
			route = racket_route(.Keymap_Inspection, 5),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Describe the most recent rejected keymap candidate.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "describe-keymap-state",
			route = racket_route(.Keymap_Inspection, 6),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Describe the catalog, profiles, states, surfaces, pending input, and generations.",
			interactive = true,
			provenance = inspection_provenance,
		},
		{
			name = "uppercase-current-line",
			route = racket_route(.Transaction, 7),
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Uppercase the current logical line.",
			interactive = true,
			requirements = {.Active_Buffer},
			provenance = catalog_provenance,
		},
	}
}

/* test_built_in_command_definitions composes native and admitted test commands. */
test_built_in_command_definitions :: proc() -> [BUILT_IN_BASE_COMMAND_COUNT + TEST_RACKET_COMMAND_COUNT]interaction.Command_Definition {
	result: [BUILT_IN_BASE_COMMAND_COUNT + TEST_RACKET_COMMAND_COUNT]interaction.Command_Definition
	base := built_in_base_command_definitions()
	for definition, index in base {
		result[index] = definition
	}
	racket := test_racket_command_definitions()
	for definition, index in racket {
		result[BUILT_IN_BASE_COMMAND_COUNT + index] = definition
	}
	return result
}
