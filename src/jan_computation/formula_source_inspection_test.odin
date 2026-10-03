// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../language"
import "core:testing"

/* Verifies source-backed formula inspection recognizes and evaluates an attached formula. */
@(test)
formula_source_inspection_evaluates_attached_sum :: proc(t: ^testing.T) {
	source := transmute([]u8)(string(
		"* Totals\n" +
		"| Day | Samples |\n" +
		"|-----+---------|\n" +
		"| Mon |       3 |\n" +
		"| Tue |       4 |\n" +
		"| Wed |       5 |\n" +
		"|-----+---------|\n" +
		"| Total |      12 |\n" +
		"#+TBLFM: @>$2=vsum(@2..@4)\n",
	))
	scope := computation_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, analysis_failure := language.jan_structural_owner_analyze(
		&owner, source, scope.analysis,
	)
	testing.expectf(t, analyzed, "analysis failed with %v", analysis_failure.code)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	inspection: Formula_Source_Inspection
	inspected, failure := inspect_formula_source(
		&inspection, &analysis, source, 0,
	)
	testing.expectf(t, inspected, "inspection failed with %v", failure.code)
	if !inspected do return
	defer formula_source_inspection_close(&inspection)
	view, viewed := formula_source_inspection_view(&inspection)
	testing.expect(t, viewed)
	testing.expect_value(t, view.target, "@>$2")
	testing.expect_value(t, view.expression, "vsum(@2..@4)")
	testing.expect_value(t, view.row_count, u32(5))
	testing.expect_value(t, view.column_count, u32(2))
	testing.expect_value(t, view.target_row, u32(4))
	testing.expect_value(t, view.target_column, u32(1))
	testing.expect_value(t, view.value.kind, Cell_Value_Kind.Number)
	testing.expect_value(t, view.value.number, f64(12))
	testing.expect_value(t, len(view.trace), 1)
	testing.expect_value(t, view.trace[0].instruction, Instruction_Kind.Sum_Range)
	testing.expect(t, view.trace[0].resolved)
}
