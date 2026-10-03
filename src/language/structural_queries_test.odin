// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:strings"
import "core:testing"

@(private)
Structural_Test_Fixture :: struct {
	buffer:   editor.Buffer,
	snapshot: editor.Buffer_Snapshot,
	owner:    Tree_Sitter_Owner,
	scope:    Structural_Scope,
	ready:    bool,
}

@(private)
structural_test_fixture_open :: proc(
	fixture: ^Structural_Test_Fixture,
	buffer_id: editor.Buffer_ID,
	contents: string,
) -> bool {
	fixture^ = {}
	initialized, _ := editor.buffer_init(
		&fixture.buffer,
		buffer_id,
		contents,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !initialized do return false
	opened, _ := editor.buffer_snapshot_open(&fixture.buffer, &fixture.snapshot)
	if !opened {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	owner_ready, _ := tree_sitter_owner_init(&fixture.owner, 3)
	if !owner_ready {
		editor.buffer_snapshot_close(&fixture.snapshot)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	query_ready, _ := tree_sitter_owner_compile_odin_query(&fixture.owner, 5)
	language, provider := tree_sitter_test_identity()
	parsed, parse_ok, _ := tree_sitter_owner_parse_snapshot(
		&fixture.owner,
		&fixture.snapshot,
		language,
		provider,
		7,
		11,
	)
	if !query_ready || !parse_ok {
		tree_sitter_owner_close(&fixture.owner)
		editor.buffer_snapshot_close(&fixture.snapshot)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	fixture.scope = Structural_Scope {
		buffer_id = parsed.buffer_id,
		source_revision = parsed.source_revision,
		language = parsed.language,
		provider = parsed.provider,
		selection_generation = parsed.selection_generation,
		parser_generation = parsed.parser_generation,
		tree_generation = parsed.tree_generation,
	}
	fixture.ready = true
	return true
}

@(private)
structural_test_fixture_close :: proc(fixture: ^Structural_Test_Fixture) {
	if fixture == nil || !fixture.ready do return
	tree_sitter_owner_close(&fixture.owner)
	editor.buffer_snapshot_close(&fixture.snapshot)
	editor.buffer_close(&fixture.buffer)
	fixture^ = {}
}

@(private)
structural_test_request :: proc(
	fixture: ^Structural_Test_Fixture,
	operation: Structural_Operation,
	point: int,
) -> Structural_Request {
	return Structural_Request {
		operation = operation,
		scope = fixture.scope,
		point = editor.Byte_Offset(point),
		start = editor.Byte_Offset(point),
		end = editor.Byte_Offset(point),
	}
}

@(private)
structural_test_kind :: proc(target: Structural_Target) -> string {
	kind := target.kind
	return string(kind.bytes[:int(kind.length)])
}

/* Verifies production traversal resolves named containment and strict ancestry. */
@(test)
structural_queries_resolve_ancestry :: proc(t: ^testing.T) {
	contents := "package demo\n\nmain :: proc() {\n    value := 1\n    if value > 0 {\n        value += 1\n    }\n}\n"
	fixture: Structural_Test_Fixture
	ready := structural_test_fixture_open(&fixture, 601, contents)
	testing.expect(t, ready)
	if !ready do return
	defer structural_test_fixture_close(&fixture)
	value_offset := strings.index(contents, "value := 1")
	request := structural_test_request(&fixture, .Select, value_offset)
	target, usage, selected, failure := tree_sitter_owner_query_structure(
		&fixture.owner,
		&fixture.snapshot,
		request,
	)
	testing.expectf(t, selected, "selection failed with %v", failure.code)
	if !selected do return
	testing.expect_value(t, structural_test_kind(target), "identifier")
	testing.expect_value(t, target.start, editor.Byte_Offset(value_offset))
	testing.expect(t, structural_target_is_valid(target, u64(len(contents))))
	testing.expect(t, usage.visited_nodes > 0)

	request.operation = .Up
	parent, _, parent_ok, parent_failure := tree_sitter_owner_query_structure(
		&fixture.owner,
		&fixture.snapshot,
		request,
	)
	testing.expectf(t, parent_ok, "parent failed with %v", parent_failure.code)
	if !parent_ok do return
	testing.expect(t, parent.start <= target.start && parent.end >= target.end)
	testing.expect(t, parent.start != target.start || parent.end != target.end)

	request.operation = .Down
	request.has_region = true
	request.start = parent.start
	request.end = parent.end
	child, _, child_ok, child_failure := tree_sitter_owner_query_structure(
		&fixture.owner,
		&fixture.snapshot,
		request,
	)
	testing.expectf(t, child_ok, "child failed with %v", child_failure.code)
	if child_ok do testing.expect(t, child.start >= parent.start && child.end <= parent.end)
}

/* Verifies selection expansion, siblings, and checked boundary no-target results. */
@(test)
structural_queries_traverse_one_level :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\n    alpha := 1\n    beta := 2\n}\n"
	fixture: Structural_Test_Fixture
	ready := structural_test_fixture_open(&fixture, 602, contents)
	testing.expect(t, ready)
	if !ready do return
	defer structural_test_fixture_close(&fixture)
	alpha_offset := strings.index(contents, "alpha")
	request := structural_test_request(&fixture, .Select, alpha_offset)
	selected, _, selected_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, selected_ok)
	if !selected_ok do return
	request.has_region = true
	request.start = selected.start
	request.end = selected.end
	expanded, _, expanded_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, expanded_ok)
	if !expanded_ok do return
	testing.expect(t, expanded.start <= selected.start && expanded.end >= selected.end)

	for structural_test_kind(expanded) != "block" {
		request.start = expanded.start
		request.end = expanded.end
		next, _, next_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
		if !next_ok do break
		expanded = next
	}
	testing.expect_value(t, structural_test_kind(expanded), "block")
	request.operation = .Down
	request.start = expanded.start
	request.end = expanded.end
	first, _, first_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, first_ok)
	if !first_ok do return
	request.operation = .Forward
	request.start = first.start
	request.end = first.end
	next, _, next_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, next_ok)
	if !next_ok do return
	testing.expect(t, next.start > first.start)
	request.operation = .Backward
	request.start = next.start
	request.end = next.end
	previous, _, previous_ok, _ := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, previous_ok)
	if previous_ok do testing.expect_value(t, previous.start, first.start)
}

/* Verifies factory Odin indentation plans only leading horizontal whitespace. */
@(test)
indentation_plans_nested_odin :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\nvalue := 1\nif value > 0 {\nvalue += 1\n}\n}\n"
	fixture: Structural_Test_Fixture
	ready := structural_test_fixture_open(&fixture, 603, contents)
	testing.expect(t, ready)
	if !ready do return
	defer structural_test_fixture_close(&fixture)
	request := structural_test_request(&fixture, .Indent, 0)
	request.has_region = true
	request.start = 0
	request.end = editor.Byte_Offset(len(contents))
	plan, planned, failure := tree_sitter_owner_plan_indentation(
		&fixture.owner,
		&fixture.snapshot,
		request,
	)
	testing.expectf(t, planned, "indentation failed with %v", failure.code)
	if !planned do return
	defer structural_indentation_plan_close(&plan)
	testing.expect(t, len(plan.edits) >= 3)
	testing.expect(t, plan.usage.indent_lines >= 7)
	seen_one := false
	seen_two := false
	for edit in plan.edits {
		testing.expect_value(t, edit.start, edit.end)
		seen_one = seen_one || edit.indent_level == 1 && edit.indent_bytes == 4
		seen_two = seen_two || edit.indent_level == 2 && edit.indent_bytes == 8
	}
	testing.expect(t, seen_one && seen_two)
}

/* Verifies stale scopes, invalid UTF-8 boundaries, cancellation, and faults. */
@(test)
queries_contain_stale_and_alloc_faults :: proc(t: ^testing.T) {
	contents := "package demo\nname :: \"żółw\"\n"
	fixture: Structural_Test_Fixture
	ready := structural_test_fixture_open(&fixture, 604, contents)
	testing.expect(t, ready)
	if !ready do return
	defer structural_test_fixture_close(&fixture)
	name_offset := strings.index(contents, "name")
	request := structural_test_request(&fixture, .Select, name_offset)
	request.scope.tree_generation += 1
	_, _, stale_ok, stale_failure := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Selection)

	request = structural_test_request(&fixture, .Select, strings.index(contents, "ż") + 1)
	_, _, boundary_ok, boundary_failure := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, !boundary_ok)
	testing.expect_value(t, boundary_failure.code, Failure_Code.Invalid_UTF8_Boundary)

	request = structural_test_request(&fixture, .Select, name_offset)
	cancelled, _ := tree_sitter_owner_request_cancel(&fixture.owner)
	_, _, cancellation_ok, cancellation_failure := tree_sitter_owner_query_structure(&fixture.owner, &fixture.snapshot, request)
	testing.expect(t, cancelled && !cancellation_ok)
	testing.expect_value(t, cancellation_failure.code, Failure_Code.Cancelled)
	tree_sitter_owner_clear_cancel(&fixture.owner)

	request = structural_test_request(&fixture, .Indent, 0)
	failing := Tree_Sitter_Test_Failing_Allocator{backing = context.allocator, fail_after = 0}
	_, planned, allocation_failure := tree_sitter_owner_plan_indentation(
		&fixture.owner,
		&fixture.snapshot,
		request,
		tree_sitter_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Allocation)
}

/* Verifies incomplete syntax remains queryable and error lines are unchanged. */
@(test)
indentation_contains_incomplete_syntax :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc() {\nvalue := (\n}\n"
	fixture: Structural_Test_Fixture
	ready := structural_test_fixture_open(&fixture, 605, contents)
	testing.expect(t, ready)
	if !ready do return
	defer structural_test_fixture_close(&fixture)
	request := structural_test_request(&fixture, .Indent, 0)
	request.has_region = true
	request.start = 0
	request.end = editor.Byte_Offset(len(contents))
	plan, planned, failure := tree_sitter_owner_plan_indentation(&fixture.owner, &fixture.snapshot, request)
	testing.expectf(t, planned, "incomplete plan failed with %v", failure.code)
	if !planned do return
	defer structural_indentation_plan_close(&plan)
	error_start := editor.Byte_Offset(strings.index(contents, "value := ("))
	for edit in plan.edits do testing.expect(t, edit.start != error_start)
}

/* Verifies production traversal and indentation reject work beyond selected limits. */
@(test)
structural_queries_enforce_limits :: proc(t: ^testing.T) {
	dense, dense_error := make([dynamic]u8, 0, int(MAX_STRUCTURAL_NODES) * 8)
	testing.expect(t, dense_error == nil)
	if dense_error != nil do return
	defer delete(dense)
	for _ in 0 ..< MAX_STRUCTURAL_NODES + 1 {
		_, append_error := append(&dense, ..transmute([]u8)(string("v :: 1\n")))
		testing.expect(t, append_error == nil)
		if append_error != nil do return
	}
	dense_fixture: Structural_Test_Fixture
	dense_ready := structural_test_fixture_open(&dense_fixture, 606, string(dense[:]))
	testing.expect(t, dense_ready)
	if dense_ready {
		request := structural_test_request(&dense_fixture, .Select, 0)
		_, usage, queried, failure := tree_sitter_owner_query_structure(
			&dense_fixture.owner,
			&dense_fixture.snapshot,
			request,
		)
		testing.expect(t, !queried)
		testing.expect_value(t, failure.code, Failure_Code.Node_Limit)
		testing.expect(t, usage.visited_nodes > MAX_STRUCTURAL_NODES)
		structural_test_fixture_close(&dense_fixture)
	}

	lines, line_error := make([dynamic]u8, 0, int(MAX_STRUCTURAL_INDENT_LINES) + 1)
	testing.expect(t, line_error == nil)
	if line_error != nil do return
	defer delete(lines)
	for _ in 0 ..< MAX_STRUCTURAL_INDENT_LINES + 1 {
		_, append_error := append(&lines, '\n')
		testing.expect(t, append_error == nil)
		if append_error != nil do return
	}
	line_fixture: Structural_Test_Fixture
	line_ready := structural_test_fixture_open(&line_fixture, 607, string(lines[:]))
	testing.expect(t, line_ready)
	if line_ready {
		request := structural_test_request(&line_fixture, .Indent, 0)
		request.has_region = true
		request.start = 0
		request.end = editor.Byte_Offset(len(lines))
		plan, planned, failure := tree_sitter_owner_plan_indentation(
			&line_fixture.owner,
			&line_fixture.snapshot,
			request,
		)
		testing.expect(t, !planned)
		testing.expect_value(t, failure.code, Failure_Code.Line_Limit)
		if planned do structural_indentation_plan_close(&plan)
		structural_test_fixture_close(&line_fixture)
	}
}
