// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../language"
import "core:fmt"
import "core:math"

/* MAX_FORMULA_INSTRUCTIONS bounds one copied formula program. */
MAX_FORMULA_INSTRUCTIONS :: u32(65_536)
/* MAX_DEBUG_STEPS bounds one non-mutating formula trace. */
MAX_DEBUG_STEPS :: u32(65_536)

/* Cell_Value_Kind identifies one formula value family. */
Cell_Value_Kind :: enum u8 {
	Invalid,
	Empty,
	Number,
	Duration,
	Boolean,
	Error,
}

/* Cell_Value is one copied scalar table value. */
Cell_Value :: struct {
	kind:             Cell_Value_Kind,
	number:           f64,
	duration_seconds: i64,
	boolean:          bool,
}

/* Table_Snapshot is one revision-bound copied table value. */
Table_Snapshot :: struct {
	identity:     u64,
	scope:        Scope,
	row_count:    u32,
	column_count: u32,
	column_names: []string,
	cells:        []Cell_Value,
}

/* Reference_Kind identifies compatible relative, absolute, named, and range references. */
Reference_Kind :: enum u8 {
	Invalid,
	Relative,
	Absolute,
	Current_Row,
	Current_Column,
	Named_Column,
	Range,
}

/* Table_Reference identifies one cell or inclusive rectangular range. */
Table_Reference :: struct {
	kind:       Reference_Kind,
	table_id:   u64,
	row:        i32,
	column:     i32,
	row_end:    i32,
	column_end: i32,
	row_delta:  i32,
	column_delta: i32,
	name:       string,
}

/* Resolved_Range is one inclusive copied table rectangle. */
Resolved_Range :: struct {
	row_start:    u32,
	column_start: u32,
	row_end:      u32,
	column_end:   u32,
}

/* Instruction_Kind identifies one bounded algebraic formula operation. */
Instruction_Kind :: enum u8 {
	Invalid,
	Push_Literal,
	Push_Reference,
	Add,
	Subtract,
	Multiply,
	Divide,
	Negate,
	Equal,
	Less,
	Greater,
	Select,
	Sum_Range,
	Average_Range,
	Minimum_Range,
	Maximum_Range,
}

/* Formula_Instruction is one copied stack-machine operation. */
Formula_Instruction :: struct {
	kind:      Instruction_Kind,
	literal:   Cell_Value,
	reference: Table_Reference,
}

/* Formula_Program is one source-preserved parsed formula candidate. */
Formula_Program :: struct {
	identity:     u64,
	source_range: language.Jan_Source_Range,
	current_row:  u32,
	current_column: u32,
	instructions: []Formula_Instruction,
}

/* Debug_Step records one non-mutating formula evaluation step. */
Debug_Step :: struct {
	step:        u32,
	instruction: Instruction_Kind,
	stack_depth: u32,
	value:       Cell_Value,
	row:         u32,
	column:      u32,
	resolved:    bool,
}

/* Formula_Target identifies one cell replacement owned by a program. */
Formula_Target :: struct {
	program_id: u64,
	row:        u32,
	column:     u32,
}

/* Cell_Replacement is one candidate cell update with its prior and next values. */
Cell_Replacement :: struct {
	program_id: u64,
	row:        u32,
	column:     u32,
	prior:      Cell_Value,
	next:       Cell_Value,
}

/* Formula_Dependency_Node identifies one deterministic dependency-graph node. */
Formula_Dependency_Node :: struct {
	identity:     u64,
	dependencies: []u64,
}

/* Iteration_Policy bounds explicitly admitted iterative calculations. */
Iteration_Policy :: struct {
	enabled:    bool,
	max_steps:  u32,
	epsilon:    f64,
}

/* Lookup_Kind identifies exact, relational, associative, and range lookup. */
Lookup_Kind :: enum u8 {
	Invalid,
	Exact,
	Relational,
	Associative,
	Range,
}

/* Lookup_Request identifies columns and one copied lookup key. */
Lookup_Request :: struct {
	kind:         Lookup_Kind,
	key:          Cell_Value,
	key_column:   u32,
	upper_column: u32,
	value_column: u32,
}

/* Format_Kind identifies general, fixed-decimal, and duration presentation. */
Format_Kind :: enum u8 {
	Invalid,
	General,
	Fixed,
	Duration_Hours_Minutes,
}

/* Format_Directive is one copied formula output format. */
Format_Directive :: struct {
	kind:      Format_Kind,
	precision: u8,
}

/* table_snapshot_is_valid checks exact scope, shape, and copied cell values. */
table_snapshot_is_valid :: proc(snapshot: Table_Snapshot) -> bool {
	if snapshot.identity == 0 || !scope_is_valid(snapshot.scope) ||
	   snapshot.row_count == 0 || snapshot.column_count == 0 ||
	   snapshot.row_count > MAX_TABLE_CELLS || snapshot.column_count > MAX_TABLE_CELLS ||
	   u64(snapshot.row_count) * u64(snapshot.column_count) > u64(MAX_TABLE_CELLS) ||
	   len(snapshot.cells) != int(snapshot.row_count * snapshot.column_count) ||
	   (len(snapshot.column_names) != 0 && len(snapshot.column_names) != int(snapshot.column_count)) {
		return false
	}
	for value in snapshot.cells do if value.kind == .Invalid do return false
	return true
}

/* resolve_table_reference resolves one reference against copied table data. */
resolve_table_reference :: proc(
	snapshot: Table_Snapshot,
	reference: Table_Reference,
	current_row, current_column: u32,
) -> (Resolved_Range, bool) {
	if !table_snapshot_is_valid(snapshot) || reference.kind == .Invalid ||
	   (reference.table_id != 0 && reference.table_id != snapshot.identity) ||
	   current_row >= snapshot.row_count || current_column >= snapshot.column_count {
		return {}, false
	}
	row, column, row_end, column_end: i64
	switch reference.kind {
	case .Relative:
		row = i64(current_row) + i64(reference.row_delta)
		column = i64(current_column) + i64(reference.column_delta)
		row_end, column_end = row, column
	case .Absolute:
		row, column = i64(reference.row), i64(reference.column)
		row_end, column_end = row, column
	case .Current_Row:
		row, column = i64(current_row), i64(reference.column)
		row_end, column_end = row, column
	case .Current_Column:
		row, column = i64(reference.row), i64(current_column)
		row_end, column_end = row, column
	case .Named_Column:
		if len(reference.name) == 0 || len(snapshot.column_names) == 0 do return {}, false
		found := -1
		for name, index in snapshot.column_names do if name == reference.name {
			if found >= 0 do return {}, false
			found = index
		}
		if found < 0 do return {}, false
		row, column = i64(current_row), i64(found)
		row_end, column_end = row, column
	case .Range:
		row, column = i64(reference.row), i64(reference.column)
		row_end, column_end = i64(reference.row_end), i64(reference.column_end)
	case .Invalid:
		return {}, false
	}
	if row < 0 || column < 0 || row_end < row || column_end < column ||
	   row_end >= i64(snapshot.row_count) || column_end >= i64(snapshot.column_count) {
		return {}, false
	}
	return {
		row_start = u32(row),
		column_start = u32(column),
		row_end = u32(row_end),
		column_end = u32(column_end),
	}, true
}

/* table_cell returns one copied table value. */
table_cell :: proc(snapshot: Table_Snapshot, row, column: u32) -> (Cell_Value, bool) {
	if !table_snapshot_is_valid(snapshot) || row >= snapshot.row_count || column >= snapshot.column_count {
		return {}, false
	}
	return snapshot.cells[int(row * snapshot.column_count + column)], true
}

/* evaluate_formula evaluates one bounded copied program and optionally records a trace. */
evaluate_formula :: proc(
	snapshot: Table_Snapshot,
	program: Formula_Program,
	stack: []Cell_Value,
	trace: []Debug_Step = nil,
) -> (Cell_Value, u32, bool, Failure) {
	if !table_snapshot_is_valid(snapshot) || program.identity == 0 ||
	   program.source_range.scope != snapshot.scope.analysis ||
	   !language.jan_source_range_is_valid(program.source_range, snapshot.scope.source_bytes) ||
	   program.current_row >= snapshot.row_count || program.current_column >= snapshot.column_count ||
	   len(program.instructions) == 0 || len(program.instructions) > int(MAX_FORMULA_INSTRUCTIONS) ||
	   len(stack) < len(program.instructions) || len(trace) > int(MAX_DEBUG_STEPS) {
		return {}, 0, false, formula_failure(.Invalid_Request, .Formula)
	}
	depth, trace_count := 0, 0
	for instruction, index in program.instructions {
		resolved_row, resolved_column, resolved := u32(0), u32(0), false
		switch instruction.kind {
		case .Push_Literal:
			if !cell_value_is_usable(instruction.literal) do return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
			stack[depth] = instruction.literal
			depth += 1
		case .Push_Reference:
			range, ok := resolve_table_reference(snapshot, instruction.reference, program.current_row, program.current_column)
			if !ok || range.row_start != range.row_end || range.column_start != range.column_end {
				return {}, u32(trace_count), false, formula_failure(.Stale, .Dependency)
			}
			value, value_ok := table_cell(snapshot, range.row_start, range.column_start)
			if !value_ok || !cell_value_is_usable(value) do return {}, u32(trace_count), false, formula_failure(.Evaluation, .Dependency)
			stack[depth] = value
			depth += 1
			resolved_row, resolved_column, resolved = range.row_start, range.column_start, true
		case .Negate:
			if depth < 1 do return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
			value, ok := formula_negate(stack[depth - 1])
			if !ok do return {}, u32(trace_count), false, formula_failure(.Evaluation, .Formula)
			stack[depth - 1] = value
		case .Add, .Subtract, .Multiply, .Divide, .Equal, .Less, .Greater:
			if depth < 2 do return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
			value, ok := formula_binary(instruction.kind, stack[depth - 2], stack[depth - 1])
			if !ok do return {}, u32(trace_count), false, formula_failure(.Evaluation, .Formula)
			depth -= 1
			stack[depth - 1] = value
		case .Select:
			if depth < 3 || stack[depth - 3].kind != .Boolean {
				return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
			}
			stack[depth - 3] = stack[depth - 2] if stack[depth - 3].boolean else stack[depth - 1]
			depth -= 2
		case .Sum_Range, .Average_Range, .Minimum_Range, .Maximum_Range:
			range, ok := resolve_table_reference(snapshot, instruction.reference, program.current_row, program.current_column)
			if !ok do return {}, u32(trace_count), false, formula_failure(.Stale, .Dependency)
			value, aggregate_ok := aggregate_range(snapshot, range, instruction.kind)
			if !aggregate_ok do return {}, u32(trace_count), false, formula_failure(.Evaluation, .Formula)
			stack[depth] = value
			depth += 1
			resolved_row, resolved_column, resolved = range.row_start, range.column_start, true
		case .Invalid:
			return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
		}
		if len(trace) > 0 {
			if trace_count >= len(trace) do return {}, u32(trace_count), false, formula_failure(.Limited, .Limit)
			trace[trace_count] = {
				step = u32(index),
				instruction = instruction.kind,
				stack_depth = u32(depth),
				value = stack[depth - 1],
				row = resolved_row,
				column = resolved_column,
				resolved = resolved,
			}
			trace_count += 1
		}
	}
	if depth != 1 do return {}, u32(trace_count), false, formula_failure(.Malformed, .Formula)
	return stack[0], u32(trace_count), true, {}
}

/* prepare_recalculation evaluates all programs before publishing any replacement. */
prepare_recalculation :: proc(
	snapshot: Table_Snapshot,
	programs: []Formula_Program,
	targets: []Formula_Target,
	stack: []Cell_Value,
	scratch, output: []Cell_Replacement,
) -> (u32, bool, Failure) {
	if !table_snapshot_is_valid(snapshot) || len(programs) == 0 || len(programs) != len(targets) ||
	   len(programs) > int(DEFAULT_LIMITS.executable_targets) ||
	   len(scratch) < len(programs) || len(output) < len(programs) {
		return 0, false, formula_failure(.Invalid_Request, .Target)
	}
	for target, index in targets {
		if target.program_id == 0 || target.program_id != programs[index].identity ||
		   target.row >= snapshot.row_count || target.column >= snapshot.column_count {
			return 0, false, formula_failure(.Invalid_Request, .Target)
		}
		for prior in targets[:index] do if prior.row == target.row && prior.column == target.column {
			return 0, false, formula_failure(.Conflict, .Target)
		}
		prior, prior_ok := table_cell(snapshot, target.row, target.column)
		if !prior_ok do return 0, false, formula_failure(.Stale, .Target)
		next, _, evaluated, failure := evaluate_formula(snapshot, programs[index], stack)
		if !evaluated do return 0, false, failure
		scratch[index] = {program_id = target.program_id, row = target.row, column = target.column, prior = prior, next = next}
	}
	copy(output[:len(programs)], scratch[:len(programs)])
	return u32(len(programs)), true, {}
}

/* plan_formula_order returns stable dependency order or rejects missing and cyclic nodes. */
plan_formula_order :: proc(
	nodes: []Formula_Dependency_Node,
	indegrees: []u16,
	output: []u64,
) -> (u32, bool, Failure) {
	if len(nodes) == 0 || len(nodes) > int(MAX_FORMULA_DEPENDENCIES) ||
	   len(indegrees) < len(nodes) || len(output) < len(nodes) {
		return 0, false, formula_failure(.Limited, .Dependency)
	}
	for _, index in nodes do output[index] = 0
	for node, index in nodes {
		if node.identity == 0 || len(node.dependencies) > int(MAX_FORMULA_DEPENDENCIES) {
			return 0, false, formula_failure(.Malformed, .Dependency)
		}
		for prior in nodes[:index] do if prior.identity == node.identity {
			return 0, false, formula_failure(.Conflict, .Dependency)
		}
		indegrees[index] = u16(len(node.dependencies))
		for dependency in node.dependencies {
			found := false
			for candidate in nodes do if candidate.identity == dependency {found = true; break}
			if !found do return 0, false, formula_failure(.Stale, .Dependency)
		}
	}
	count := 0
	for count < len(nodes) {
		selected := -1
		for degree, index in indegrees[:len(nodes)] do if degree == 0 {
			already_output := false
			for identity in output[:count] do if identity == nodes[index].identity {already_output = true; break}
			if !already_output {selected = index; break}
		}
		if selected < 0 do return 0, false, formula_failure(.Cycle, .Dependency)
		identity := nodes[selected].identity
		output[count] = identity
		count += 1
		for node, index in nodes {
			for dependency in node.dependencies do if dependency == identity && indegrees[index] > 0 {
				indegrees[index] -= 1
			}
		}
	}
	return u32(count), true, {}
}

/* iteration_converged checks one explicitly bounded iterative calculation step. */
iteration_converged :: proc(previous, current: f64, step: u32, policy: Iteration_Policy) -> (bool, bool) {
	if !policy.enabled || policy.max_steps == 0 || policy.epsilon <= 0 ||
	   math.is_nan(policy.epsilon) || math.is_inf(policy.epsilon) ||
	   math.is_nan(previous) || math.is_inf(previous) || math.is_nan(current) || math.is_inf(current) ||
	   step == 0 || step > policy.max_steps {
		return false, false
	}
	return abs(current - previous) <= policy.epsilon, true
}

/* lookup_table resolves exact, relational, associative, or range values from copied cells. */
lookup_table :: proc(snapshot: Table_Snapshot, request: Lookup_Request) -> (Cell_Value, bool) {
	if !table_snapshot_is_valid(snapshot) || request.kind == .Invalid ||
	   request.key_column >= snapshot.column_count || request.value_column >= snapshot.column_count ||
	   request.upper_column >= snapshot.column_count || !cell_value_is_usable(request.key) {
		return {}, false
	}
	best: Cell_Value
	best_key: Cell_Value
	found := false
	for row in 0 ..< snapshot.row_count {
		key, _ := table_cell(snapshot, row, request.key_column)
		value, _ := table_cell(snapshot, row, request.value_column)
		switch request.kind {
		case .Exact, .Associative:
			if cell_value_equal(key, request.key) do return value, true
		case .Relational:
			comparison, comparable := cell_value_compare(key, request.key)
			if comparable && comparison <= 0 {
				if !found {
					best, best_key, found = value, key, true
				} else {
					better, _ := cell_value_compare(key, best_key)
					if better > 0 do best, best_key = value, key
				}
			}
		case .Range:
			upper, _ := table_cell(snapshot, row, request.upper_column)
			lower_comparison, lower_ok := cell_value_compare(request.key, key)
			upper_comparison, upper_ok := cell_value_compare(request.key, upper)
			if lower_ok && upper_ok && lower_comparison >= 0 && upper_comparison <= 0 do return value, true
		case .Invalid:
			return {}, false
		}
	}
	return best, found
}

/* format_cell_value writes one bounded compatible display value. */
format_cell_value :: proc(value: Cell_Value, directive: Format_Directive, output: []u8) -> (string, bool) {
	if len(output) == 0 || directive.kind == .Invalid || directive.precision > 12 do return "", false
	text := ""
	switch value.kind {
	case .Empty:
		text = ""
	case .Number:
		if directive.kind == .Fixed {
			text = fmt.bprintf(output, "%.*f", int(directive.precision), value.number)
		} else {
			text = fmt.bprintf(output, "%g", value.number)
		}
	case .Duration:
		if directive.kind != .Duration_Hours_Minutes && directive.kind != .General do return "", false
		seconds := value.duration_seconds
		sign := "-" if seconds < 0 else ""
		if seconds < 0 do seconds = -seconds
		text = fmt.bprintf(output, "%s%d:%02d", sign, seconds / 3_600, (seconds % 3_600) / 60)
	case .Boolean:
		text = fmt.bprintf(output, "%s", "true" if value.boolean else "false")
	case .Error:
		text = fmt.bprintf(output, "#ERROR")
	case .Invalid:
		return "", false
	}
	return text, len(text) < len(output)
}

@(private)
cell_value_is_usable :: proc(value: Cell_Value) -> bool {
	return value.kind >= .Empty && value.kind <= .Boolean &&
	       (value.kind != .Number || (!math.is_nan(value.number) && !math.is_inf(value.number)))
}

@(private)
formula_binary :: proc(kind: Instruction_Kind, left, right: Cell_Value) -> (Cell_Value, bool) {
	if kind == .Equal do return {kind = .Boolean, boolean = cell_value_equal(left, right)}, true
	comparison, comparable := cell_value_compare(left, right)
	if kind == .Less do return {kind = .Boolean, boolean = comparison < 0}, comparable
	if kind == .Greater do return {kind = .Boolean, boolean = comparison > 0}, comparable
	if left.kind == .Number && right.kind == .Number {
		#partial switch kind {
		case .Add:      return {kind = .Number, number = left.number + right.number}, true
		case .Subtract: return {kind = .Number, number = left.number - right.number}, true
		case .Multiply: return {kind = .Number, number = left.number * right.number}, true
		case .Divide:
			if right.number == 0 do return {}, false
			return {kind = .Number, number = left.number / right.number}, true
		}
	}
	if left.kind == .Duration && right.kind == .Duration {
		#partial switch kind {
		case .Add:      return {kind = .Duration, duration_seconds = left.duration_seconds + right.duration_seconds}, true
		case .Subtract: return {kind = .Duration, duration_seconds = left.duration_seconds - right.duration_seconds}, true
		}
	}
	return {}, false
}

@(private)
formula_negate :: proc(value: Cell_Value) -> (Cell_Value, bool) {
	if value.kind == .Number do return {kind = .Number, number = -value.number}, true
	if value.kind == .Duration do return {kind = .Duration, duration_seconds = -value.duration_seconds}, true
	return {}, false
}

@(private)
aggregate_range :: proc(snapshot: Table_Snapshot, rectangle: Resolved_Range, kind: Instruction_Kind) -> (Cell_Value, bool) {
	result: Cell_Value
	count := u32(0)
	for row in rectangle.row_start ..= rectangle.row_end {
		for column in rectangle.column_start ..= rectangle.column_end {
			value, _ := table_cell(snapshot, row, column)
			if value.kind == .Empty do continue
			if value.kind != .Number && value.kind != .Duration do return {}, false
			if count == 0 {
				result = value
			} else {
				if result.kind != value.kind do return {}, false
				#partial switch kind {
				case .Sum_Range, .Average_Range:
					result, _ = formula_binary(.Add, result, value)
				case .Minimum_Range:
					comparison, _ := cell_value_compare(value, result)
					if comparison < 0 do result = value
				case .Maximum_Range:
					comparison, _ := cell_value_compare(value, result)
					if comparison > 0 do result = value
				}
			}
			count += 1
		}
	}
	if count == 0 do return {kind = .Empty}, true
	if kind == .Average_Range {
		if result.kind == .Number do result.number /= f64(count)
		if result.kind == .Duration do result.duration_seconds /= i64(count)
	}
	return result, true
}

@(private)
cell_value_equal :: proc(left, right: Cell_Value) -> bool {
	if left.kind != right.kind do return false
	#partial switch left.kind {
	case .Empty:    return true
	case .Number:   return left.number == right.number
	case .Duration: return left.duration_seconds == right.duration_seconds
	case .Boolean:  return left.boolean == right.boolean
	}
	return false
}

@(private)
cell_value_compare :: proc(left, right: Cell_Value) -> (int, bool) {
	if left.kind != right.kind do return 0, false
	#partial switch left.kind {
	case .Number:
		if left.number < right.number do return -1, true
		if left.number > right.number do return 1, true
		return 0, true
	case .Duration:
		if left.duration_seconds < right.duration_seconds do return -1, true
		if left.duration_seconds > right.duration_seconds do return 1, true
		return 0, true
	}
	return 0, false
}

@(private)
formula_failure :: proc(code: Failure_Code, field: Failure_Field) -> Failure {
	return {kind = .Formula, code = code, field = field}
}
