// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import ui "../../src/ui"
import "core:strings"
import "core:testing"

/* Builds two valid contributor generations in deliberately noncanonical order. */
extension_status_projection_generations :: proc(
	first_items, second_items: ^[2]ksawery.Extension_Status_Item,
	first_metadata, second_metadata: ^[2]ksawery.Extension_Status_Metadata,
	first_sections, second_sections: ^[1]ksawery.Extension_Status_Section,
	generations: ^[2]ksawery.Extension_Status_Generation,
) -> ksawery.Observation_Descriptor {
	first := extension_status_test_section(first_items, first_metadata)
	second := extension_status_test_section(second_items, second_metadata)
	second.contributor = {contributor = 2, generation = 5}
	_ = ksawery.contributor_identity_assign(&second.contributor_identity, "personal.alpha")
	_ = ksawery.extension_identity_assign(&second.identity, "status.alpha")
	_ = ksawery.extension_label_assign(&second.label, "Alpha insight")
	for &item in second_items {
		if item.command.present do item.command.contributor = second.contributor
	}
	second.items = second_items[:]
	first_sections^ = [1]ksawery.Extension_Status_Section{first}
	second_sections^ = [1]ksawery.Extension_Status_Section{second}
	generations^ = [2]ksawery.Extension_Status_Generation {
		{
			contributor = first.contributor,
			contributor_identity = first.contributor_identity,
			generation = first.generation,
			repository = first.repository,
			observation_generation = first.observation_generation,
			sections = first_sections[:],
		},
		{
			contributor = second.contributor,
			contributor_identity = second.contributor_identity,
			generation = second.generation,
			repository = second.repository,
			observation_generation = second.observation_generation,
			sections = second_sections[:],
		},
	}
	return {
		repository = first.repository,
		generation = first.observation_generation,
	}
}

/* Verifies multi-contributor order, semantic selection, commands, and style roles. */
@(test)
extension_status_projection_is_deterministic_and_semantic :: proc(t: ^testing.T) {
	first_items, second_items: [2]ksawery.Extension_Status_Item
	first_metadata, second_metadata: [2]ksawery.Extension_Status_Metadata
	first_sections, second_sections: [1]ksawery.Extension_Status_Section
	generations: [2]ksawery.Extension_Status_Generation
	descriptor := extension_status_projection_generations(
		&first_items, &second_items, &first_metadata, &second_metadata,
		&first_sections, &second_sections, &generations,
	)
	count := odra.ksawery_extension_status_visible_row_count(generations[:], descriptor)
	testing.expect_value(t, count, 7)
	rows: [7]ui.List_Item_Definition
	storage: [7 * odra.KSAWERY_LIST_ROW_BYTES]u8
	write := 0
	current, appended := odra.ksawery_extension_status_append(
		rows[:], storage[:], &write, generations[:], descriptor, {},
	)
	testing.expect(t, appended)
	testing.expect_value(t, write, 7)
	testing.expect_value(t, current, i32(-1))
	testing.expect_value(t, rows[0].text, "Extensions")
	testing.expect_value(t, rows[1].text, "Alpha insight")
	testing.expect_value(t, rows[4].text, "Repository insight")
	testing.expect_value(t, rows[2].emphasis_style, ui.Style_Role.Diagnostic_Warning)
	testing.expect_value(t, rows[3].emphasis_style, ui.Style_Role.Diagnostic_Information)

	selection: odra.Ksawery_Extension_Status_Selection
	testing.expect(t, odra.ksawery_extension_status_select_ui_item(
		generations[:], descriptor, rows[2].id, &selection,
	))
	command, available := odra.ksawery_extension_status_selected_command(
		generations[:], descriptor, selection,
	)
	testing.expect(t, available)
	testing.expect_value(t, command, "command.open-history")
	write = 0
	current, appended = odra.ksawery_extension_status_append(
		rows[:], storage[:], &write, generations[:], descriptor, selection,
	)
	testing.expect(t, appended)
	testing.expect_value(t, current, i32(2))

	swapped := [2]ksawery.Extension_Status_Generation{generations[1], generations[0]}
	write = 0
	_, appended = odra.ksawery_extension_status_append(
		rows[:], storage[:], &write, swapped[:], descriptor, {},
	)
	testing.expect(t, appended)
	testing.expect_value(t, rows[1].text, "Alpha insight")
}

/* Verifies stale and empty generations disappear while truncation has a text cue. */
@(test)
extension_status_projection_omits_stale_and_empty_sections :: proc(t: ^testing.T) {
	first_items, second_items: [2]ksawery.Extension_Status_Item
	first_metadata, second_metadata: [2]ksawery.Extension_Status_Metadata
	first_sections, second_sections: [1]ksawery.Extension_Status_Section
	generations: [2]ksawery.Extension_Status_Generation
	descriptor := extension_status_projection_generations(
		&first_items, &second_items, &first_metadata, &second_metadata,
		&first_sections, &second_sections, &generations,
	)
	second_sections[0].truncation = .Provider_Limit
	rows: [7]ui.List_Item_Definition
	storage: [7 * odra.KSAWERY_LIST_ROW_BYTES]u8
	write := 0
	_, appended := odra.ksawery_extension_status_append(
		rows[:], storage[:], &write, generations[:], descriptor, {},
	)
	testing.expect(t, appended)
	testing.expect(t, strings.contains(rows[1].text, "[truncated: provider limit]"))

	stale := descriptor
	stale.generation += 1
	testing.expect_value(t,
		odra.ksawery_extension_status_visible_row_count(generations[:], stale), 0)
	_, selected := odra.ksawery_extension_status_selected_command(generations[:], stale, {})
	testing.expect(t, !selected)

	first_sections[0].items = nil
	one := [1]ksawery.Extension_Status_Generation{generations[0]}
	testing.expect_value(t,
		odra.ksawery_extension_status_visible_row_count(one[:], descriptor), 0)
}
