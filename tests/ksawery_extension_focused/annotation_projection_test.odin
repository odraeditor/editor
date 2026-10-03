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

/* Verifies target-local text, semantic style, selection, and command resolution. */
@(test)
extension_annotation_projection_is_semantic_and_target_local :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	testing.expect_value(t, odra.ksawery_extension_annotation_visible_row_count(
		&generation, generation.observation,
	), 2)
	rows: [2]ui.List_Item_Definition
	storage: [2 * odra.KSAWERY_LIST_ROW_BYTES]u8
	write := 0
	current, appended := odra.ksawery_extension_annotation_append_target(
		rows[:], storage[:], &write, &generation, generation.observation,
		annotations[0].target, {},
	)
	testing.expect(t, appended)
	testing.expect_value(t, write, 1)
	testing.expect_value(t, current, i32(-1))
	testing.expect_value(t, rows[0].text, "  [Protected: Requires a reviewed update]")
	testing.expect_value(t, rows[0].emphasis_style, ui.Style_Role.Diagnostic_Warning)
	testing.expect(t, !rows[0].passive)
	testing.expect(t, strings.has_prefix(rows[0].text, "  ["))

	selection: odra.Ksawery_Extension_Annotation_Selection
	testing.expect(t, odra.ksawery_extension_annotation_select_ui_item(
		&generation, generation.observation, rows[0].id, &selection,
	))
	command, available := odra.ksawery_extension_annotation_selected_command(
		&generation, selection,
	)
	testing.expect(t, available)
	testing.expect_value(t, command, "command.open-history")
	write = 0
	current, appended = odra.ksawery_extension_annotation_append_target(
		rows[:], storage[:], &write, &generation, generation.observation,
		annotations[0].target, selection,
	)
	testing.expect(t, appended)
	testing.expect_value(t, current, i32(0))

	write = 0
	_, appended = odra.ksawery_extension_annotation_append_target(
		rows[:], storage[:], &write, &generation, generation.observation,
		annotations[1].target, {},
	)
	testing.expect(t, appended)
	testing.expect_value(t, write, 1)
	testing.expect_value(t, rows[0].text, "  [annotation.review]")
	testing.expect_value(t, rows[0].emphasis_style, ui.Style_Role.Diagnostic_Information)
	testing.expect(t, rows[0].passive)
}

/* Verifies stale observations disappear and cannot preserve semantic selection. */
@(test)
extension_annotation_projection_rejects_stale_selection :: proc(t: ^testing.T) {
	annotations: [2]ksawery.Extension_Annotation
	generation := annotation_contract_test_generation(&annotations)
	rows: [2]ui.List_Item_Definition
	storage: [2 * odra.KSAWERY_LIST_ROW_BYTES]u8
	write := 0
	_, appended := odra.ksawery_extension_annotation_append_target(
		rows[:], storage[:], &write, &generation, generation.observation,
		annotations[0].target, {},
	)
	testing.expect(t, appended)
	selection: odra.Ksawery_Extension_Annotation_Selection
	testing.expect(t, odra.ksawery_extension_annotation_select_ui_item(
		&generation, generation.observation, rows[0].id, &selection,
	))
	stale := generation.observation
	stale.generation += 1
	testing.expect_value(t,
		odra.ksawery_extension_annotation_visible_row_count(&generation, stale), 0)
	testing.expect(t, !odra.ksawery_extension_annotation_select_ui_item(
		&generation, stale, rows[0].id, &selection,
	))
	command, available := odra.ksawery_extension_annotation_selected_command(
		&generation, selection,
	)
	testing.expect(t, available)
	testing.expect_value(t, command, "command.open-history")
	selection.observation_generation = stale.generation
	_, available = odra.ksawery_extension_annotation_selected_command(&generation, selection)
	testing.expect(t, !available)
}
