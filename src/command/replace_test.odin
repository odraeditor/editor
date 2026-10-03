// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import "../interaction"
import "../search"
import "core:testing"

/* Verifies literal replace-all publishes one changeset and one reversible unit. */
@(test)
replace_all_publishes_one_atomic_literal_unit :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one fish one fish", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	result, replaced, failure := run_replace_all(t, &fixture, .Literal, "one", "two")
	testing.expectf(t, replaced, "literal replace-all failed with %v", failure)
	if !replaced {
		return
	}
	testing.expect_value(t, result.native.completion, Native_Completion.Buffer_Committed)
	testing.expect_value(t, result.usage.matches, u64(2))
	testing.expect_value(t, len(result.native.commit.splices), 2)
	testing.expect_value(t, result.native.commit.base_revision, editor.Revision(0))
	testing.expect_value(t, result.native.commit.result_revision, editor.Revision(1))
	replace_all_result_close(&result)
	expect_native_state(t, &fixture, 0, 0, 1, "two fish two fish")
	stats, stats_ok, _ := history.store_stats(&fixture.history)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.current_revision, editor.Revision(1))
	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "replace-all undo failed with %v", undo_failure)
	if undone {
		native_result_close(&undo)
	}
	expect_native_state(t, &fixture, 0, 0, 2, "one fish one fish")
}

/* Verifies regexp batches expand participating and absent optional captures exactly. */
@(test)
replace_expands_regexp_captures :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one one fish", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	result, replaced, failure := run_replace_all(
		t,
		&fixture,
		.Regular_Expression,
		"(one)( fish)?",
		"\\1-\\2",
	)
	testing.expectf(t, replaced, "regexp replace-all failed with %v", failure)
	if !replaced {
		return
	}
	testing.expect_value(t, result.usage.matches, u64(2))
	testing.expect_value(t, result.usage.captures, u64(5))
	replace_all_result_close(&result)
	expect_native_state(t, &fixture, 0, 0, 1, "one- one- fish")
}

/* Verifies no-match and pre-cancelled commands publish no revision or history. */
@(test)
no_match_and_cancel_preserve_state :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "stable", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	result, replaced, failure := run_replace_all(t, &fixture, .Literal, "missing", "x")
	testing.expectf(t, replaced, "no-match replace-all failed with %v", failure)
	testing.expect_value(t, result.native.completion, Native_Completion.No_Op)
	testing.expect_value(t, result.usage.matches, u64(0))
	replace_all_result_close(&result)
	expect_native_state(t, &fixture, 0, 0, 0, "stable")

	handle, found, _ := interaction.command_lookup(&fixture.command_registry, "replace-string")
	testing.expect(t, found)
	native := native_request(&fixture, handle)
	native.history_store = &fixture.history
	cancellation := search.Cancellation{generation = 91, requested = true}
	_, replaced, failure = replace_all(
		Replace_All_Request {
			native = native,
			pattern = "stable",
			replacement = "changed",
			pattern_kind = .Literal,
			search_policy = search.DEFAULT_POLICY,
			replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
			query_id = 91,
			search_generation = 91,
			cancellation = &cancellation,
			limits = DEFAULT_REPLACE_ALL_LIMITS,
			replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
		},
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
	expect_native_state(t, &fixture, 0, 0, 0, "stable")
}

@(private)
run_replace_all :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	kind: search.Pattern_Kind,
	pattern, replacement: string,
) -> (Replace_All_Result, bool, Failure_Context) {
	name := "replace-string"
	if kind == .Regular_Expression {
		name = "replace-regexp"
	}
	handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	testing.expectf(t, found, "replace command lookup failed with %v", lookup_failure)
	if !found {
		return {}, false, Failure_Context{code = .Invalid_Command}
	}
	native := native_request(fixture, handle)
	native.history_store = &fixture.history
	native.history_grouping = history.Grouping_Context{kind = .Independent}
	identity := u64(native.transaction_id)
	return replace_all(
		Replace_All_Request {
			native = native,
			pattern = pattern,
			replacement = replacement,
			pattern_kind = kind,
			search_policy = search.DEFAULT_POLICY,
			replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
			query_id = search.Query_ID(identity),
			search_generation = search.Search_Generation(identity),
			limits = DEFAULT_REPLACE_ALL_LIMITS,
			replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
		},
	)
}
