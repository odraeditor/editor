// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "../language"
import "core:testing"

/* Verifies document agenda rows retain task state, planning text, and exact source scope. */
@(test)
document_agenda_projects_scheduled_tasks :: proc(t: ^testing.T) {
	source := transmute([]u8)(string(
		"* TODO Ship release\n" +
		"SCHEDULED: <2026-09-17>\n" +
		"* NEXT Review release\n",
	))
	scope := planning_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, failure := language.jan_structural_owner_analyze(
		&owner, source, scope.analysis,
	)
	testing.expectf(t, analyzed, "analysis failed with %v", failure.code)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	nodes := language.jan_structural_analysis_nodes(&analysis)
	attributes := language.jan_structural_analysis_attributes(&analysis)
	testing.expect_value(t, agenda_document_row_count(nodes, attributes), 2)
	first, found := agenda_document_row(nodes, attributes, source, 0)
	testing.expect(t, found)
	if !found do return
	testing.expect_value(t, first.task_state, "TODO")
	testing.expect_value(t, first.heading, "* TODO Ship release")
	testing.expect_value(t, first.planning, "SCHEDULED: <2026-09-17>")
	testing.expect(t, first.has_planning)
	testing.expect_value(t, first.target.range.scope, scope.analysis)
	second, second_found := agenda_document_row(nodes, attributes, source, 1)
	testing.expect(t, second_found)
	if !second_found do return
	testing.expect_value(t, second.task_state, "NEXT")
	testing.expect(t, !second.has_planning)
}
