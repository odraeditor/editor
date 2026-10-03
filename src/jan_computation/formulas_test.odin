// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

@(private)
FORMULA_TEST_COLUMN_NAMES := [3]string{"item", "price", "tax"}

@(private)
FORMULA_TEST_CELLS := [9]Cell_Value {
	{kind = .Number, number = 1}, {kind = .Number, number = 10}, {kind = .Number, number = 2},
	{kind = .Number, number = 2}, {kind = .Number, number = 20}, {kind = .Number, number = 4},
	{kind = .Number, number = 3}, {kind = .Number, number = 30}, {kind = .Number, number = 6},
}

@(private)
FORMULA_TEST_INSTRUCTIONS := [3]Formula_Instruction {
	{kind = .Push_Reference, reference = {kind = .Named_Column, table_id = 41, name = "price"}},
	{kind = .Push_Reference, reference = {kind = .Named_Column, table_id = 41, name = "tax"}},
	{kind = .Add},
}

@(private)
formula_test_snapshot :: proc() -> Table_Snapshot {
	scope := computation_test_scope()
	return {
		identity = 41,
		scope = scope,
		row_count = 3,
		column_count = 3,
		column_names = FORMULA_TEST_COLUMN_NAMES[:],
		cells = FORMULA_TEST_CELLS[:],
	}
}

@(private)
formula_test_program :: proc(snapshot: Table_Snapshot, identity: u64, row: u32) -> Formula_Program {
	return {
		identity = identity,
		source_range = {scope = snapshot.scope.analysis, start = 1, end = 8},
		current_row = row,
		current_column = 1,
		instructions = FORMULA_TEST_INSTRUCTIONS[:],
	}
}

/* Verifies relative, absolute, current, named, and range references remain exact. */
@(test)
	formula_references_resolve_exactly :: proc(t: ^testing.T) {
	snapshot := formula_test_snapshot()
	references := []Table_Reference {
		{kind = .Relative, row_delta = 1, column_delta = 1},
		{kind = .Absolute, row = 2, column = 2},
		{kind = .Current_Row, column = 2},
		{kind = .Current_Column, row = 2},
		{kind = .Named_Column, name = "tax"},
		{kind = .Range, row = 0, column = 1, row_end = 2, column_end = 2},
	}
	for reference in references {
		_, ok := resolve_table_reference(snapshot, reference, 1, 1)
		testing.expect(t, ok)
	}
	_, remote_ok := resolve_table_reference(snapshot, {kind = .Absolute, table_id = 99}, 1, 1)
	testing.expect(t, !remote_ok)
}

/* Verifies algebra, conditions, ranges, durations, formatting, and debug traces. */
@(test)
formula_evaluation_is_bounded_and_inspectable :: proc(t: ^testing.T) {
	snapshot := formula_test_snapshot()
	program := formula_test_program(snapshot, 51, 1)
	stack: [8]Cell_Value
	trace: [8]Debug_Step
	value, trace_count, ok, failure := evaluate_formula(snapshot, program, stack[:], trace[:])
	testing.expectf(t, ok, "formula failed with %v", failure.code)
	testing.expect_value(t, value.kind, Cell_Value_Kind.Number)
	testing.expect_value(t, value.number, f64(24))
	testing.expect_value(t, trace_count, u32(3))
	testing.expect(t, trace[0].resolved && trace[1].resolved)
	aggregate := Formula_Program {
		identity = 52,
		source_range = program.source_range,
		instructions = []Formula_Instruction{{
			kind = .Average_Range,
			reference = {kind = .Range, row = 0, column = 1, row_end = 2, column_end = 1},
		}},
	}
	value, _, ok, _ = evaluate_formula(snapshot, aggregate, stack[:])
	testing.expect(t, ok)
	testing.expect_value(t, value.number, f64(20))
	duration := Formula_Program {
		identity = 53,
		source_range = program.source_range,
		instructions = []Formula_Instruction {
			{kind = .Push_Literal, literal = {kind = .Duration, duration_seconds = 3_600}},
			{kind = .Push_Literal, literal = {kind = .Duration, duration_seconds = 1_800}},
			{kind = .Add},
		},
	}
	value, _, ok, _ = evaluate_formula(snapshot, duration, stack[:])
	testing.expect(t, ok)
	formatted: [32]u8
	text, formatted_ok := format_cell_value(value, {kind = .Duration_Hours_Minutes}, formatted[:])
	testing.expect(t, formatted_ok)
	testing.expect_value(t, text, "1:30")
}

/* Verifies graph ordering, cycles, bounded iteration, and lookup families. */
@(test)
formula_dependencies_and_lookup_are_deterministic :: proc(t: ^testing.T) {
	nodes := []Formula_Dependency_Node {
		{identity = 3, dependencies = []u64{1, 2}},
		{identity = 1},
		{identity = 2, dependencies = []u64{1}},
	}
	indegrees: [3]u16
	order: [3]u64
	count, ok, failure := plan_formula_order(nodes, indegrees[:], order[:])
	testing.expectf(t, ok, "dependency order failed with %v", failure.code)
	testing.expect_value(t, count, u32(3))
	testing.expect_value(t, order, [3]u64{1, 2, 3})
	cyclic := []Formula_Dependency_Node{{identity = 1, dependencies = []u64{2}}, {identity = 2, dependencies = []u64{1}}}
	_, ok, failure = plan_formula_order(cyclic, indegrees[:2], order[:2])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Cycle)
	converged, admitted := iteration_converged(1.0, 1.0001, 3, {enabled = true, max_steps = 8, epsilon = 0.001})
	testing.expect(t, admitted && converged)
	snapshot := formula_test_snapshot()
	value, found := lookup_table(snapshot, {
		kind = .Exact,
		key = {kind = .Number, number = 2},
		key_column = 0,
		value_column = 1,
	})
	testing.expect(t, found)
	testing.expect_value(t, value.number, f64(20))
	value, found = lookup_table(snapshot, {
		kind = .Relational,
		key = {kind = .Number, number = 2.5},
		key_column = 0,
		value_column = 1,
	})
	testing.expect(t, found)
	testing.expect_value(t, value.number, f64(20))
}

/* Verifies failed multi-cell recalculation preserves every prior output candidate. */
@(test)
formula_recalculation_publishes_only_complete_sets :: proc(t: ^testing.T) {
	snapshot := formula_test_snapshot()
	valid := formula_test_program(snapshot, 61, 0)
	invalid := Formula_Program {
		identity = 62,
		source_range = valid.source_range,
		instructions = []Formula_Instruction {
			{kind = .Push_Literal, literal = {kind = .Number, number = 1}},
			{kind = .Push_Literal, literal = {kind = .Number, number = 0}},
			{kind = .Divide},
		},
	}
	programs := []Formula_Program{valid, invalid}
	targets := []Formula_Target{{program_id = 61, row = 0, column = 2}, {program_id = 62, row = 1, column = 2}}
	stack: [8]Cell_Value
	scratch: [2]Cell_Replacement
	sentinel := Cell_Replacement{program_id = 999}
	output := [2]Cell_Replacement{sentinel, sentinel}
	count, ok, failure := prepare_recalculation(snapshot, programs, targets, stack[:], scratch[:], output[:])
	testing.expect(t, !ok)
	testing.expect_value(t, count, u32(0))
	testing.expect_value(t, failure.code, Failure_Code.Evaluation)
	testing.expect_value(t, output[0].program_id, u64(999))
	testing.expect_value(t, output[1].program_id, u64(999))
	programs = programs[:1]
	count, ok, _ = prepare_recalculation(snapshot, programs[:1], targets[:1], stack[:], scratch[:1], output[:1])
	testing.expect(t, ok)
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, output[0].prior.number, f64(2))
	testing.expect_value(t, output[0].next.number, f64(12))
}
