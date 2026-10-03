// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../history"
import "../interaction"
import editor_view "../view"
import "core:testing"

/* Verifies familiar word killing is Unicode-safe and remains one undo unit. */
@(test)
familiar_kill_word_is_unicode_safe_and_reversible :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "Żółć alpha", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, killed, failure := execute_named(&fixture, "kill-word")
	testing.expectf(t, killed, "Unicode word kill failed with %v", failure.code)
	if !killed do return
	native_result_close(&result)
	familiar_expect_text(t, &fixture, " alpha")
	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "Unicode word kill undo failed with %v", undo_failure.code)
	if undone do native_result_close(&undo)
	familiar_expect_text(t, &fixture, "Żółć alpha")
}

/* Verifies prefix repetition extends one case command across adjacent words. */
@(test)
familiar_case_command_honors_repeat_count :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two THREE", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, changed, failure := familiar_execute_repeat(&fixture, "upcase-word", 2)
	testing.expectf(t, changed, "repeated case command failed with %v", failure.code)
	if changed do native_result_close(&result)
	familiar_expect_text(t, &fixture, "ONE TWO THREE")
}

/* Verifies blank-line deletion distinguishes nonblank, isolated, and grouped targets. */
@(test)
familiar_blank_line_deletion_matches_context :: proc(t: ^testing.T) {
	nonblank: Native_Fixture
	if native_fixture_init(t, &nonblank, "alpha\n\n\nbeta", context.allocator) {
		result, changed, failure := execute_named(&nonblank, "delete-blank-lines")
		testing.expectf(t, changed, "following blank-line deletion failed with %v", failure.code)
		if changed do native_result_close(&result)
		familiar_expect_text(t, &nonblank, "alpha\nbeta")
		native_fixture_close(t, &nonblank)
	}

	isolated: Native_Fixture
	if native_fixture_init(t, &isolated, "alpha\n\nbeta", context.allocator) {
		blank, blank_ok, _ := editor.buffer_position(&isolated.buffer, editor.Byte_Offset(len("alpha\n")))
		if blank_ok do _, _ = editor_view.set_point(&isolated.view_registry, isolated.view, blank)
		result, changed, failure := execute_named(&isolated, "delete-blank-lines")
		testing.expectf(t, changed, "isolated blank-line deletion failed with %v", failure.code)
		if changed do native_result_close(&result)
		familiar_expect_text(t, &isolated, "alpha\nbeta")
		native_fixture_close(t, &isolated)
	}

	grouped: Native_Fixture
	if native_fixture_init(t, &grouped, "alpha\n\n\nbeta", context.allocator) {
		blank, blank_ok, _ := editor.buffer_position(&grouped.buffer, editor.Byte_Offset(len("alpha\n")))
		if blank_ok do _, _ = editor_view.set_point(&grouped.view_registry, grouped.view, blank)
		result, changed, failure := execute_named(&grouped, "delete-blank-lines")
		testing.expectf(t, changed, "grouped blank-line deletion failed with %v", failure.code)
		if changed do native_result_close(&result)
		familiar_expect_text(t, &grouped, "alpha\n\nbeta")
		native_fixture_close(t, &grouped)
	}
}

/* Verifies inferred abbreviation expansion publishes one reversible edit. */
@(test)
familiar_dynamic_abbrev_infers_prefix_and_undoes :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "configuration conf", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("configuration conf")))
	testing.expect(t, end_ok)
	if !end_ok do return
	point_ok, _ := editor_view.set_point(&fixture.view_registry, fixture.view, end)
	testing.expect(t, point_ok)
	result, expanded, failure := execute_named(&fixture, "dabbrev-expand")
	testing.expectf(t, expanded, "dynamic abbreviation failed with %v", failure.code)
	if expanded do native_result_close(&result)
	familiar_expect_text(t, &fixture, "configuration configuration")
	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "dynamic abbreviation undo failed with %v", undo_failure.code)
	if undone do native_result_close(&undo)
	familiar_expect_text(t, &fixture, "configuration conf")
}

/* Verifies rigid indentation applies to the retained range as one undo unit. */
@(test)
familiar_rigid_indentation_is_range_scoped_and_reversible :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha\n beta\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	start, start_ok, _ := editor.buffer_position(&fixture.buffer, 0)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("alpha\n beta")))
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	result, indented, failure := execute_named(
		&fixture,
		"rigid-indent-right",
		"",
		Native_Explicit_Range{present = true, start = start, end = end},
	)
	testing.expectf(t, indented, "rigid indentation failed with %v", failure.code)
	if indented do native_result_close(&result)
	familiar_expect_text(t, &fixture, " alpha\n  beta\n")
	undo, undone, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone, "rigid indentation undo failed with %v", undo_failure.code)
	if undone do native_result_close(&undo)
	familiar_expect_text(t, &fixture, "alpha\n beta\n")
}

/* Verifies read-only rejection leaves text and history unchanged. */
@(test)
familiar_edit_rejects_read_only_without_partial_publication :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "stable", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	_, policy_ok, policy_failure := editor.buffer_read_only_set(&fixture.buffer, true)
	testing.expectf(t, policy_ok, "read-only policy failed with %v", policy_failure.code)
	if !policy_ok do return
	_, changed, failure := execute_named(&fixture, "upcase-word")
	testing.expect(t, !changed)
	testing.expect_value(t, failure.code, Failure_Code.Publication_Failure)
	testing.expect_value(t, failure.editor_code, editor.Failure_Code.Read_Only_Buffer)
	familiar_expect_text(t, &fixture, "stable")
	stats, stats_ok, _ := history.store_stats(&fixture.history)
	testing.expect(t, stats_ok)
	if stats_ok do testing.expect_value(t, stats.current_revision, editor.Revision(0))
}

@(private)
familiar_execute_repeat :: proc(
	fixture: ^Native_Fixture,
	name: string,
	repeat_count: u64,
) -> (Native_Result, bool, Failure_Context) {
	handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	if !found {
		return {}, false, Failure_Context{
			code = .Invalid_Command,
			interaction_code = lookup_failure.code,
		}
	}
	request := native_request(fixture, handle)
	request.repeat_count = repeat_count
	request.history_store = &fixture.history
	request.kill_ring = &fixture.kill_ring
	request.kill_sequence_id = 1
	request.event_sequence = u64(request.transaction_id)
	request.yank_context = &fixture.yank_context
	request.history_grouping = history.Grouping_Context{
		kind = .Independent,
		view_id = fixture.view.view_id,
		view_generation = fixture.view.generation,
		continuity = 1,
		event_sequence = u64(request.transaction_id),
		monotonic_milliseconds = u64(request.transaction_id) * 10,
	}
	return native_command_execute(request)
}

@(private)
familiar_expect_text :: proc(t: ^testing.T, fixture: ^Native_Fixture, expected: string) {
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, stats_ok)
	if !stats_ok do return
	observed := make([]u8, int(stats.text_bytes), context.temp_allocator)
	defer delete(observed, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		&fixture.buffer,
		0,
		editor.Byte_Offset(stats.text_bytes),
		observed,
	)
	testing.expect(t, inspected)
	if inspected do testing.expect_value(t, string(observed), expected)
}
