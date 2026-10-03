// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:strings"
import "core:testing"

/* Verifies visible queries publish sorted non-overlapping exact-revision spans. */
@(test)
query_produces_sorted_revisioned_spans :: proc(t: ^testing.T) {
	contents := "package demo\n// note\nMAX_VALUE :: 42\nmain :: proc(input: int) -> int { value := input + 42; print(value); PRINT(value); return value }\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		401,
		contents,
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)

	owner: Tree_Sitter_Owner
	owner_ok, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, owner_ok)
	if !owner_ok do return
	defer tree_sitter_owner_close(&owner)
	query_ok, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ok)
	language := Language_Identity{id = 1, generation = 1}
	provider := Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	_, parsed, _ := tree_sitter_owner_parse_snapshot(&owner, &snapshot, language, provider, 1, 1)
	testing.expect(t, parsed)

	result, queried, query_failure := tree_sitter_owner_query_spans(
		&owner,
		&snapshot,
		0,
		u64(len(contents)),
		0,
		1,
	)
	testing.expectf(t, queried, "syntax query failed with %v", query_failure.code)
	if !queried do return
	defer syntax_query_result_close(&result)
	testing.expect(t, len(result.spans) > 0)
	testing.expect_value(t, result.snapshot.buffer_id, editor.Buffer_ID(401))
	testing.expect_value(t, result.snapshot.source_revision, editor.Revision(0))
	testing.expect_value(t, result.snapshot.span_count, u32(len(result.spans)))

	seen_keyword := false
	seen_function := false
	seen_number := false
	for span, index in result.spans {
		testing.expect(t, syntax_span_is_valid(span, u64(len(contents))))
		if index > 0 do testing.expect(t, result.spans[index - 1].end <= span.start)
		seen_keyword = seen_keyword || span.role == .Keyword
		seen_function = seen_function || span.role == .Function
		seen_number = seen_number || span.role == .Number
	}
	testing.expect(t, seen_keyword)
	testing.expect(t, seen_function)
	testing.expect(t, seen_number)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "package")), Syntax_Role.Keyword)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "// note") + 3), Syntax_Role.Comment)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "MAX_VALUE")), Syntax_Role.Constant)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "main ::")), Syntax_Role.Function)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "input:")), Syntax_Role.Variable_Parameter)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "int)")), Syntax_Role.Type)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "value :=")), Syntax_Role.Variable)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "print(value)")), Syntax_Role.Function)
	testing.expect_value(t, syntax_test_role_at(result.spans[:], strings.index(contents, "PRINT(value)")), Syntax_Role.Function_Builtin)
}

@(private)
syntax_test_role_at :: proc(spans: []Syntax_Span, offset: int) -> Syntax_Role {
	if offset < 0 do return .Invalid
	for span in spans {
		if u64(offset) >= u64(span.start) && u64(offset) < u64(span.end) do return span.role
	}
	return .Invalid
}

/* Verifies a medium dense source may exceed the visible span count in raw captures. */
@(test)
query_handles_dense_capture_work :: proc(t: ^testing.T) {
	contents, allocation_error := make([dynamic]byte, 0, 64 * int(KIBIBYTE), context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(contents)
	_, _ = append(&contents, ..transmute([]u8)(string("package demo\n")))
	declaration := "value :: proc(input: int) -> int { return input + 42 }\n"
	for len(contents) < 48 * int(KIBIBYTE) {
		_, append_error := append(&contents, ..transmute([]u8)(declaration))
		testing.expect(t, append_error == nil)
		if append_error != nil do return
	}
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		402,
		string(contents[:]),
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)

	owner: Tree_Sitter_Owner
	owner_ok, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, owner_ok)
	if !owner_ok do return
	defer tree_sitter_owner_close(&owner)
	query_ok, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ok)
	language := Language_Identity{id = 1, generation = 1}
	provider := Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	_, parsed, _ := tree_sitter_owner_parse_snapshot(&owner, &snapshot, language, provider, 1, 1)
	testing.expect(t, parsed)
	if !parsed do return

	result, queried, query_failure := tree_sitter_owner_query_spans(
		&owner,
		&snapshot,
		0,
		512,
		MAX_VISIBLE_HALO_BYTES,
		1,
	)
	testing.expectf(
		t,
		queried,
		"medium dense syntax query failed with %v limit=%v actual=%v",
		query_failure.code,
		query_failure.limit,
		query_failure.actual,
	)
	if !queried do return
	defer syntax_query_result_close(&result)
	testing.expect(t, result.snapshot.usage.captures > MAX_VISIBLE_QUERY_SPANS)
	testing.expect(t, len(result.spans) > 0)
}

/* Verifies capture normalization splits overlap by deterministic precedence. */
@(test)
capture_normalization_splits_by_precedence :: proc(t: ^testing.T) {
	provider := Provider_Handle{provider_id = 1, provider_generation = 1}
	captures := [3]Raw_Syntax_Capture {
		{start = 0, end = 10, role = .Variable, precedence = 10, serial = 0},
		{start = 2, end = 6, role = .Function, precedence = 20, serial = 1},
		{start = 4, end = 8, role = .Keyword, precedence = 30, serial = 2},
	}
	spans, failure := syntax_captures_normalize(captures[:], provider, 0, context.allocator)
	testing.expect_value(t, failure.code, Failure_Code.None)
	if spans == nil do return
	defer delete(spans)
	expected := [4]Syntax_Span {
		{start = 0, end = 2, role = .Variable, precedence = 10},
		{start = 2, end = 4, role = .Function, precedence = 20},
		{start = 4, end = 8, role = .Keyword, precedence = 30},
		{start = 8, end = 10, role = .Variable, precedence = 10},
	}
	testing.expect_value(t, len(spans), 4)
	for span, index in spans {
		testing.expect_value(t, span.start, expected[index].start)
		testing.expect_value(t, span.end, expected[index].end)
		testing.expect_value(t, span.role, expected[index].role)
		testing.expect_value(t, span.precedence, expected[index].precedence)
	}
}
