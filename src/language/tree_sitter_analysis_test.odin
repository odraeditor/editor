// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../transaction"
import "base:runtime"
import "core:testing"

/* Verifies full and incremental parsing produce equivalent semantic spans. */
@(test)
full_and_incremental_syntax_match :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		501,
		"package demo\nvalue :: 1\n",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	base_snapshot: editor.Buffer_Snapshot
	base_open, _ := editor.buffer_snapshot_open(&buffer, &base_snapshot)
	testing.expect(t, base_open)
	if !base_open do return
	defer editor.buffer_snapshot_close(&base_snapshot)

	language, provider := tree_sitter_test_identity()
	incremental_owner: Tree_Sitter_Owner
	incremental_ready, _ := tree_sitter_owner_init(&incremental_owner, 1)
	testing.expect(t, incremental_ready)
	if !incremental_ready do return
	defer tree_sitter_owner_close(&incremental_owner)
	query_ready, _ := tree_sitter_owner_compile_odin_query(&incremental_owner, 1)
	testing.expect(t, query_ready)
	_, initial_ready, _ := tree_sitter_owner_parse_snapshot(
		&incremental_owner,
		&base_snapshot,
		language,
		provider,
		1,
		1,
	)
	testing.expect(t, initial_ready)

	start, _, _ := editor.buffer_position(&buffer, 22)
	end, _, _ := editor.buffer_position(&buffer, 23)
	change, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "42"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	result_snapshot: editor.Buffer_Snapshot
	result_open, _ := editor.buffer_snapshot_open(&buffer, &result_snapshot)
	testing.expect(t, result_open)
	if !result_open do return
	defer editor.buffer_snapshot_close(&result_snapshot)
	splices := [1]transaction.Normalized_Splice {{
		start = change.start,
		end = editor.Byte_Offset(u64(change.start) + change.removed_bytes),
		replacement_text = change.replacement_text,
		removed_text = "1",
	}}
	event := transaction.Commit_Event {
		buffer_id = change.buffer_id,
		base_revision = change.base_revision,
		result_revision = change.result_revision,
		splices = splices[:],
	}
	_, incremental_parsed, _ := tree_sitter_owner_parse_incremental(
		&incremental_owner,
		&base_snapshot,
		&result_snapshot,
		event,
		2,
	)
	testing.expect(t, incremental_parsed)
	result_stats, result_stats_ok, _ := editor.buffer_snapshot_stats(&result_snapshot)
	testing.expect(t, result_stats_ok)
	incremental_syntax, incremental_queried, _ := tree_sitter_owner_query_spans(
		&incremental_owner,
		&result_snapshot,
		0,
		result_stats.text_bytes,
		0,
		1,
	)
	testing.expect(t, incremental_queried)
	if !incremental_queried do return
	defer syntax_query_result_close(&incremental_syntax)

	full_owner: Tree_Sitter_Owner
	full_ready, _ := tree_sitter_owner_init(&full_owner, 2)
	testing.expect(t, full_ready)
	if !full_ready do return
	defer tree_sitter_owner_close(&full_owner)
	full_query_ready, _ := tree_sitter_owner_compile_odin_query(&full_owner, 1)
	testing.expect(t, full_query_ready)
	_, full_parsed, _ := tree_sitter_owner_parse_snapshot(
		&full_owner,
		&result_snapshot,
		language,
		provider,
		1,
		1,
	)
	testing.expect(t, full_parsed)
	full_syntax, full_queried, _ := tree_sitter_owner_query_spans(
		&full_owner,
		&result_snapshot,
		0,
		result_stats.text_bytes,
		0,
		1,
	)
	testing.expect(t, full_queried)
	if !full_queried do return
	defer syntax_query_result_close(&full_syntax)

	testing.expect_value(t, len(incremental_syntax.spans), len(full_syntax.spans))
	for span, index in incremental_syntax.spans {
		other := full_syntax.spans[index]
		testing.expect_value(t, span.start, other.start)
		testing.expect_value(t, span.end, other.end)
		testing.expect_value(t, span.role, other.role)
		testing.expect_value(t, span.precedence, other.precedence)
	}
}

/* Verifies one multi-splice commit has full and incremental syntax parity. */
@(test)
multisplice_syntax_matches_full_parse :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		502,
		"package demo\nalpha :: 1\nbeta :: 2\n",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	base_snapshot: editor.Buffer_Snapshot
	base_open, _ := editor.buffer_snapshot_open(&buffer, &base_snapshot)
	testing.expect(t, base_open)
	if !base_open do return
	defer editor.buffer_snapshot_close(&base_snapshot)

	analysis_language, provider := tree_sitter_test_identity()
	incremental_owner: Tree_Sitter_Owner
	incremental_ready, _ := tree_sitter_owner_init(&incremental_owner, 1)
	testing.expect(t, incremental_ready)
	if !incremental_ready do return
	defer tree_sitter_owner_close(&incremental_owner)
	query_ready, _ := tree_sitter_owner_compile_odin_query(&incremental_owner, 1)
	testing.expect(t, query_ready)
	_, initial_ready, _ := tree_sitter_owner_parse_snapshot(
		&incremental_owner,
		&base_snapshot,
		analysis_language,
		provider,
		1,
		1,
	)
	testing.expect(t, initial_ready)

	first_start, _, _ := editor.buffer_position(&buffer, 22)
	first_end, _, _ := editor.buffer_position(&buffer, 23)
	second_start, _, _ := editor.buffer_position(&buffer, 32)
	second_end, _, _ := editor.buffer_position(&buffer, 33)
	root: transaction.Transaction
	transaction_ready, _ := transaction.transaction_begin(
		&root,
		1,
		1,
		&buffer,
		transaction.Origin{kind = .Language_Tool, descriptor = "syntax parity test"},
		"replace two literals",
		transaction.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, transaction_ready)
	if !transaction_ready do return
	defer transaction.transaction_close(&root)
	applied, _ := transaction.transaction_apply_batch(
		&root,
		[]transaction.Base_Splice {
			{start = first_start, end = first_end, replacement = "10"},
			{start = second_start, end = second_end, replacement = "20"},
		},
	)
	testing.expect(t, applied)
	validated, _ := transaction.transaction_validate(&root)
	testing.expect(t, validated)
	commit_result, committed, _ := transaction.transaction_commit(&root)
	testing.expect(t, committed)
	testing.expect_value(t, len(commit_result.splices), 2)

	result_snapshot: editor.Buffer_Snapshot
	result_open, _ := editor.buffer_snapshot_open(&buffer, &result_snapshot)
	testing.expect(t, result_open)
	if !result_open do return
	defer editor.buffer_snapshot_close(&result_snapshot)
	_, incremental_parsed, _ := tree_sitter_owner_parse_incremental(
		&incremental_owner,
		&base_snapshot,
		&result_snapshot,
		commit_result.event,
		2,
	)
	testing.expect(t, incremental_parsed)
	result_stats, result_stats_ok, _ := editor.buffer_snapshot_stats(&result_snapshot)
	testing.expect(t, result_stats_ok)
	incremental_syntax, incremental_queried, _ := tree_sitter_owner_query_spans(
		&incremental_owner,
		&result_snapshot,
		0,
		result_stats.text_bytes,
		0,
		1,
	)
	testing.expect(t, incremental_queried)
	if !incremental_queried do return
	defer syntax_query_result_close(&incremental_syntax)

	full_owner: Tree_Sitter_Owner
	full_ready, _ := tree_sitter_owner_init(&full_owner, 2)
	testing.expect(t, full_ready)
	if !full_ready do return
	defer tree_sitter_owner_close(&full_owner)
	full_query_ready, _ := tree_sitter_owner_compile_odin_query(&full_owner, 1)
	testing.expect(t, full_query_ready)
	_, full_parsed, _ := tree_sitter_owner_parse_snapshot(
		&full_owner,
		&result_snapshot,
		analysis_language,
		provider,
		1,
		1,
	)
	testing.expect(t, full_parsed)
	full_syntax, full_queried, _ := tree_sitter_owner_query_spans(
		&full_owner,
		&result_snapshot,
		0,
		result_stats.text_bytes,
		0,
		1,
	)
	testing.expect(t, full_queried)
	if !full_queried do return
	defer syntax_query_result_close(&full_syntax)

	testing.expect_value(t, len(incremental_syntax.spans), len(full_syntax.spans))
	for span, index in incremental_syntax.spans {
		other := full_syntax.spans[index]
		testing.expect_value(t, span.start, other.start)
		testing.expect_value(t, span.end, other.end)
		testing.expect_value(t, span.role, other.role)
		testing.expect_value(t, span.precedence, other.precedence)
	}
}

/* Verifies incomplete source and repeated visible queries remain bounded. */
@(test)
bad_source_queries_remain_bounded :: proc(t: ^testing.T) {
	contents := "package demo\nmain :: proc( {\nvalue := 42\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		503,
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
	language, provider := tree_sitter_test_identity()
	owner: Tree_Sitter_Owner
	ready, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, ready)
	if !ready do return
	defer tree_sitter_owner_close(&owner)
	query_ready, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ready)
	_, parsed, _ := tree_sitter_owner_parse_snapshot(&owner, &snapshot, language, provider, 1, 1)
	testing.expect(t, parsed)

	first, first_ok, first_failure := tree_sitter_owner_query_spans(
		&owner,
		&snapshot,
		0,
		20,
		8,
		1,
	)
	testing.expectf(t, first_ok, "first visible query failed with %v limit=%v actual=%v", first_failure.code, first_failure.limit, first_failure.actual)
	if first_ok do defer syntax_query_result_close(&first)
	second, second_ok, second_failure := tree_sitter_owner_query_spans(
		&owner,
		&snapshot,
		20,
		u64(len(contents)),
		8,
		2,
	)
	testing.expectf(t, second_ok, "second visible query failed with %v limit=%v actual=%v", second_failure.code, second_failure.limit, second_failure.actual)
	if second_ok do defer syntax_query_result_close(&second)
	if first_ok && second_ok {
		testing.expect_value(t, first.snapshot.source_revision, second.snapshot.source_revision)
		testing.expect_value(t, first.snapshot.parser_generation, second.snapshot.parser_generation)
		for span in first.spans do testing.expect(t, syntax_span_is_valid(span, u64(len(contents))))
		for span in second.spans do testing.expect(t, syntax_span_is_valid(span, u64(len(contents))))
	}
}

/* Verifies work exhaustion and explicit cancellation preserve owner state. */
@(test)
work_limit_cancel_preserves_owner :: proc(t: ^testing.T) {
	contents, allocation_error := make([dynamic]byte, 0, 8 * int(MEBIBYTE), context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(contents)
	_, _ = append(&contents, ..transmute([]u8)(string("package demo\n")))
	for len(contents) < 8 * int(MEBIBYTE) {
		_, _ = append(&contents, 'a', '\n')
	}
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		505,
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
	language, provider := tree_sitter_test_identity()
	owner: Tree_Sitter_Owner
	ready, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, ready)
	if !ready do return
	defer tree_sitter_owner_close(&owner)
	query_ready, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ready)

	_, limited, limit_failure := tree_sitter_owner_parse_snapshot(
		&owner,
		&snapshot,
		language,
		provider,
		1,
		1,
		1,
	)
	testing.expect(t, !limited)
	testing.expect_value(t, limit_failure.code, Failure_Code.Work_Limit)
	cancel_requested, _ := tree_sitter_owner_request_cancel(&owner)
	testing.expect(t, cancel_requested)
	_, cancelled, cancel_failure := tree_sitter_owner_parse_snapshot(
		&owner,
		&snapshot,
		language,
		provider,
		1,
		1,
		INITIAL_WORK_BYTES,
	)
	testing.expect(t, !cancelled)
	testing.expect_value(t, cancel_failure.code, Failure_Code.Cancelled)
	clear_ok, _ := tree_sitter_owner_clear_cancel(&owner)
	testing.expect(t, clear_ok)
	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, !stats.has_tree)
}

/* Verifies query limits, foreign accounting, and allocation failure containment. */
@(test)
foreign_alloc_failure_is_contained :: proc(t: ^testing.T) {
	owner: Tree_Sitter_Owner
	ready, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, ready)
	if !ready do return
	defer tree_sitter_owner_close(&owner)
	query_ok, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ok)
	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.foreign_live_bytes > 0)
	testing.expect(t, stats.foreign_peak_bytes >= stats.foreign_live_bytes)
	testing.expect(t, stats.foreign_allocations > 0)

	oversized, oversized_error := make([]u8, int(MAX_QUERY_BYTES + 1), context.temp_allocator)
	testing.expect(t, oversized_error == nil)
	if oversized_error == nil {
		_, oversized_failure := tree_sitter_owner_compile_query(&owner, oversized, 2)
		testing.expect_value(t, oversized_failure.code, Failure_Code.Query_Limit)
		delete(oversized, context.temp_allocator)
	}
	failing := Tree_Sitter_Test_Failing_Allocator {
		backing = context.allocator,
		fail_after = 0,
	}
	captures := [1]Raw_Syntax_Capture {{start = 0, end = 1, role = .Variable}}
	_, allocation_failure := syntax_captures_normalize(
		captures[:],
		Provider_Handle{provider_id = 1, provider_generation = 1},
		0,
		tree_sitter_test_failing_allocator(&failing),
	)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Allocation)
}

/* Verifies repeated owner teardown releases every foreign allocation. */
@(test)
teardown_releases_foreign_owners :: proc(t: ^testing.T) {
	for generation in 1 ..= 16 {
		owner: Tree_Sitter_Owner
		ready, _ := tree_sitter_owner_init(&owner, Parser_Generation(generation))
		testing.expect(t, ready)
		if !ready do continue
		query_ready, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
		testing.expect(t, query_ready)
		stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
		testing.expect(t, stats_ok)
		testing.expect(t, stats.foreign_live_bytes > 0)
		closed, _ := tree_sitter_owner_close(&owner)
		testing.expect(t, closed)
	}
}

@(private)
tree_sitter_test_identity :: proc() -> (Language_Identity, Provider_Handle) {
	language := Language_Identity{id = 1, generation = 1}
	return language, Provider_Handle {
		registry_id = 1,
		language_id = language.id,
		provider_id = 1,
		provider_generation = 1,
	}
}

@(private)
Tree_Sitter_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
tree_sitter_test_failing_allocator :: proc(data: ^Tree_Sitter_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = tree_sitter_test_failing_allocator_proc,
		data = data,
	}
}

@(private)
tree_sitter_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Tree_Sitter_Test_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
