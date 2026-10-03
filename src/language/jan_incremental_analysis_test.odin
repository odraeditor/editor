// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

import "../editor"
import "../transaction"

/* Verifies one normalized commit updates a copied Jan tree and matches a full parse. */
@(test)
jan_incremental_analysis_matches_full_result :: proc(t: ^testing.T) {
	base_source := transmute([]u8)(string("* READY Title\nBody *bold*.\n"))
	result_source := transmute([]u8)(string("* DONE Title\nBody *bold*.\n"))
	base_scope := jan_incremental_test_scope(7, 19)
	result_scope := jan_incremental_test_scope(8, 20)

	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	base, analyzed, failure := jan_structural_owner_analyze(&owner, base_source, base_scope)
	testing.expectf(t, analyzed, "initial Jan analysis failed with %v", failure.code)
	if !analyzed do return
	defer jan_structural_analysis_close(&base)

	splices := [1]transaction.Normalized_Splice{{
		start = editor.Byte_Offset(2),
		end = editor.Byte_Offset(7),
		replacement_text = "DONE",
		removed_text = "READY",
	}}
	event := transaction.Commit_Event {
		buffer_id = base_scope.buffer_id,
		base_revision = base_scope.source_revision,
		result_revision = result_scope.source_revision,
		splices = splices[:],
	}
	incremental, updated, update_failure := jan_structural_owner_analyze_incremental(
		&owner,
		base_source,
		result_source,
		event,
		result_scope,
	)
	testing.expectf(t, updated, "incremental Jan analysis failed with %v", update_failure.code)
	if !updated do return
	defer jan_structural_analysis_close(&incremental)
	usage, usage_ok := jan_structural_analysis_usage(&incremental)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.incremental_edits, u32(1))

	full_owner: Jan_Structural_Owner
	full_initialized, _ := jan_structural_owner_init(&full_owner, 13)
	testing.expect(t, full_initialized)
	if !full_initialized do return
	defer jan_structural_owner_close(&full_owner)
	full, full_ok, full_failure := jan_structural_owner_analyze(&full_owner, result_source, result_scope)
	testing.expectf(t, full_ok, "full Jan analysis failed with %v", full_failure.code)
	if !full_ok do return
	defer jan_structural_analysis_close(&full)
	testing.expect(
		t,
		jan_incremental_test_nodes_match(
			jan_structural_analysis_nodes(&incremental),
			jan_structural_analysis_nodes(&full),
		),
	)
}

/* Verifies stale, forged, and cancelled candidates preserve the confirmed owner. */
@(test)
jan_incremental_analysis_rejects_unconfirmed_candidates :: proc(t: ^testing.T) {
	base_source := transmute([]u8)(string("* READY Title\n"))
	result_source := transmute([]u8)(string("* DONE Title\n"))
	base_scope := jan_incremental_test_scope(7, 19)
	result_scope := jan_incremental_test_scope(8, 20)
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	initial, analyzed, _ := jan_structural_owner_analyze(&owner, base_source, base_scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&initial)

	splices := [1]transaction.Normalized_Splice{{
		start = editor.Byte_Offset(2),
		end = editor.Byte_Offset(7),
		replacement_text = "DONE",
		removed_text = "forged",
	}}
	event := transaction.Commit_Event {
		buffer_id = base_scope.buffer_id,
		base_revision = base_scope.source_revision,
		result_revision = result_scope.source_revision,
		splices = splices[:],
	}
	_, updated, failure := jan_structural_owner_analyze_incremental(
		&owner,
		base_source,
		result_source,
		event,
		result_scope,
	)
	testing.expect(t, !updated)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Invalid_Rewrite)

	splices[0].removed_text = "READY"
	jan_structural_owner_request_cancel(&owner)
	_, updated, failure = jan_structural_owner_analyze_incremental(
		&owner,
		base_source,
		result_source,
		event,
		result_scope,
	)
	testing.expect(t, !updated)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Cancelled)
	jan_structural_owner_clear_cancel(&owner)
	result: Jan_Structural_Analysis
	result, updated, failure = jan_structural_owner_analyze_incremental(
		&owner,
		base_source,
		result_source,
		event,
		result_scope,
	)
	testing.expectf(t, updated, "confirmed tree was not reusable: %v", failure.code)
	if updated do jan_structural_analysis_close(&result)
}

/* Verifies publication advances atomically and rejected candidates remain inspectable. */
@(test)
jan_revision_publication_preserves_last_confirmed_inspection :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	configuration := jan_factory_configuration(1)
	base_scope := jan_incremental_test_scope(7, 19)
	source := transmute([]u8)(string("* READY Title\n"))
	initial, published, failure := jan_structural_owner_publish_initial(
		&owner,
		source,
		base_scope,
		configuration,
	)
	testing.expectf(t, published, "initial publication failed with %v", failure.code)
	if !published do return
	jan_structural_analysis_close(&initial)
	inspection, inspected, _ := jan_structural_owner_inspect(&owner, base_scope)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Jan_Analysis_Status.Current)
	testing.expect_value(t, inspection.scope, base_scope)
	testing.expect(t, inspection.has_node)

	stale_scope := base_scope
	refreshed: bool
	_, refreshed, failure = jan_structural_owner_refresh(
		&owner,
		source,
		stale_scope,
		configuration,
	)
	testing.expect(t, !refreshed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Stale)
	inspection, inspected, _ = jan_structural_owner_inspect(&owner, stale_scope)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.scope, base_scope)
	testing.expect_value(t, inspection.latest_failure.code, Jan_Failure_Code.Stale)

	configuration = jan_factory_configuration(2)
	refresh_scope := base_scope
	refresh_scope.configuration = configuration.identity
	refresh_scope.grammar_generation = 18
	refresh_scope.analysis_generation = 20
	refreshed_analysis: Jan_Structural_Analysis
	refreshed_analysis, refreshed, failure = jan_structural_owner_refresh(
		&owner,
		source,
		refresh_scope,
		configuration,
	)
	testing.expectf(t, refreshed, "configuration refresh failed with %v", failure.code)
	if !refreshed do return
	jan_structural_analysis_close(&refreshed_analysis)
	inspection, inspected, _ = jan_structural_owner_inspect(&owner, refresh_scope)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Jan_Analysis_Status.Current)
	testing.expect_value(t, inspection.scope, refresh_scope)
	testing.expect_value(t, inspection.latest_failure.code, Jan_Failure_Code.None)

	rejected_scope := refresh_scope
	rejected_scope.source_revision = 8
	rejected_scope.analysis_generation = 21
	invalid_utf8 := []u8{0xff}
	_, refreshed, failure = jan_structural_owner_refresh(
		&owner,
		invalid_utf8,
		rejected_scope,
		configuration,
	)
	testing.expect(t, !refreshed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Malformed)
	inspection, inspected, _ = jan_structural_owner_inspect(&owner, rejected_scope)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Jan_Analysis_Status.Incomplete)
	testing.expect_value(t, inspection.scope, refresh_scope)
	testing.expect_value(t, inspection.latest_failure.scope, rejected_scope)
	testing.expect_value(t, inspection.latest_failure.code, Jan_Failure_Code.Malformed)
}

/* Verifies a generated edit sequence stays equivalent to a fresh full analysis. */
@(test)
jan_generated_incremental_sequence_matches_full_analysis :: proc(t: ^testing.T) {
	sources := [6]string{
		"* TODO A\n:PROPERTIES:\n:ID: a\n:END:\n- one\n| a |\nText *bold*.\n",
		"* DONE A\n:PROPERTIES:\n:ID: a\n:END:\n- one\n| a |\nText *bold*.\n",
		"* DONE A\n:PROPERTIES:\n:ID: b\n:END:\n- one\n| a |\nText *bold*.\n",
		"* DONE A\n:PROPERTIES:\n:ID: b\n:END:\n- two\n| a |\nText *bold*.\n",
		"* DONE A\n:PROPERTIES:\n:ID: b\n:END:\n- two\n| b |\nText *bold*.\n",
		"* DONE A\n:PROPERTIES:\n:ID: b\n:END:\n- two\n| b |\nText *strong*.\n",
	}
	removed := [5]string{"TODO", ":ID: a", "- one", "| a |", "*bold*"}
	replacements := [5]string{"DONE", ":ID: b", "- two", "| b |", "*strong*"}
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	initial_scope := jan_incremental_test_scope(0, 19)
	initial, analyzed, failure := jan_structural_owner_analyze(
		&owner,
		transmute([]u8)sources[0],
		initial_scope,
	)
	testing.expectf(t, analyzed, "generated initial analysis failed with %v", failure.code)
	if !analyzed do return
	jan_structural_analysis_close(&initial)

	for transition in 0 ..< len(removed) {
		base_source := transmute([]u8)sources[transition]
		result_source := transmute([]u8)sources[transition + 1]
		start, found := jan_incremental_test_find(base_source, removed[transition])
		testing.expect(t, found)
		if !found do return
		base_scope := jan_incremental_test_scope(editor.Revision(transition), Jan_Analysis_Generation(19 + transition))
		result_scope := jan_incremental_test_scope(editor.Revision(transition + 1), Jan_Analysis_Generation(20 + transition))
		splices := [1]transaction.Normalized_Splice{{
			start = editor.Byte_Offset(start),
			end = editor.Byte_Offset(start + len(removed[transition])),
			replacement_text = replacements[transition],
			removed_text = removed[transition],
		}}
		event := transaction.Commit_Event {
			buffer_id = base_scope.buffer_id,
			base_revision = base_scope.source_revision,
			result_revision = result_scope.source_revision,
			splices = splices[:],
		}
		incremental, updated, update_failure := jan_structural_owner_analyze_incremental(
			&owner,
			base_source,
			result_source,
			event,
			result_scope,
		)
		testing.expectf(t, updated, "generated incremental step failed with %v", update_failure.code)
		if !updated do return

		full_owner: Jan_Structural_Owner
		full_initialized, _ := jan_structural_owner_init(&full_owner, 13)
		testing.expect(t, full_initialized)
		if !full_initialized {
			jan_structural_analysis_close(&incremental)
			return
		}
		full, full_ok, full_failure := jan_structural_owner_analyze(
			&full_owner,
			result_source,
			result_scope,
		)
		testing.expectf(t, full_ok, "generated full step failed with %v", full_failure.code)
		if full_ok {
			testing.expect(t, jan_incremental_test_analyses_match(&incremental, &full))
			jan_structural_analysis_close(&full)
		}
		jan_structural_owner_close(&full_owner)
		jan_structural_analysis_close(&incremental)
		if !full_ok do return
	}
}

/* Verifies malformed recovery publishes incrementally and injected timing rejects atomically. */
@(test)
jan_incremental_recovery_and_timing_are_bounded :: proc(t: ^testing.T) {
	base_source := transmute([]u8)(string("#+begin_src odin\nvalue :: 1\n#+end_src\n"))
	result_source := transmute([]u8)(string("#+begin_src odin\nvalue :: 1\n"))
	base_scope := jan_incremental_test_scope(0, 19)
	result_scope := jan_incremental_test_scope(1, 20)
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	configuration := jan_factory_configuration(1)
	initial, published, _ := jan_structural_owner_publish_initial(
		&owner,
		base_source,
		base_scope,
		configuration,
	)
	testing.expect(t, published)
	if !published do return
	jan_structural_analysis_close(&initial)
	removed := "#+end_src\n"
	start := len(base_source) - len(removed)
	splices := [1]transaction.Normalized_Splice{{
		start = editor.Byte_Offset(start),
		end = editor.Byte_Offset(len(base_source)),
		removed_text = removed,
	}}
	event := transaction.Commit_Event {
		buffer_id = base_scope.buffer_id,
		base_revision = base_scope.source_revision,
		result_revision = result_scope.source_revision,
		splices = splices[:],
	}
	malformed, updated, failure := jan_structural_owner_analyze_incremental(
		&owner,
		base_source,
		result_source,
		event,
		result_scope,
	)
	testing.expectf(t, updated, "malformed incremental recovery failed with %v", failure.code)
	if !updated do return
	testing.expect(t, len(jan_structural_analysis_recoveries(&malformed)) > 0)
	jan_structural_analysis_close(&malformed)

	timed_scope := result_scope
	timed_scope.analysis_generation = 21
	timing_limits := DEFAULT_JAN_RESOURCE_LIMITS
	timing_limits.maintenance_step_nanoseconds = 1
	timing_limits.candidate_nanoseconds = 1
	refreshed: bool
	_, refreshed, failure = jan_structural_owner_refresh(
		&owner,
		result_source,
		timed_scope,
		configuration,
		timing_limits,
	)
	testing.expect(t, !refreshed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Timeout)
	inspection, inspected, _ := jan_structural_owner_inspect(&owner, timed_scope)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.scope, result_scope)
	testing.expect_value(t, inspection.latest_failure.code, Jan_Failure_Code.Timeout)
}

@(private)
jan_incremental_test_scope :: proc(
	revision: editor.Revision,
	generation: Jan_Analysis_Generation,
) -> Jan_Analysis_Scope {
	language_name: Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	return {
		buffer_id = 3,
		document_id = 5,
		has_document = true,
		source_revision = revision,
		language = {id = 2, generation = 1, name = language_name},
		provider = {registry_id = 2, language_id = 2, provider_id = 1, provider_generation = 1},
		selection_generation = 11,
		parser_generation = 13,
		grammar_generation = 17,
		configuration = jan_factory_configuration(1).identity,
		baseline = jan_factory_baseline(),
		analysis_generation = generation,
	}
}

@(private = "file")
jan_incremental_test_nodes_match :: proc(left, right: []Jan_Node_Record) -> bool {
	if len(left) != len(right) do return false
	for node, index in left {
		other := right[index]
		if node.id != other.id || node.parent_id != other.parent_id ||
		   node.layer != other.layer || node.kind != other.kind ||
		   node.kind_text != other.kind_text ||
		   node.structural_depth != other.structural_depth ||
		   node.inline_depth != other.inline_depth ||
		   node.range.start != other.range.start || node.range.end != other.range.end ||
		   node.attribute_count != other.attribute_count {
			return false
		}
	}
	return true
}

@(private = "file")
jan_incremental_test_analyses_match :: proc(
	left, right: ^Jan_Structural_Analysis,
) -> bool {
	if !jan_incremental_test_nodes_match(
		jan_structural_analysis_nodes(left),
		jan_structural_analysis_nodes(right),
	) {
		return false
	}
	left_attributes := jan_structural_analysis_attributes(left)
	right_attributes := jan_structural_analysis_attributes(right)
	if len(left_attributes) != len(right_attributes) do return false
	for attribute, index in left_attributes {
		other := right_attributes[index]
		if attribute.node_id != other.node_id || attribute.kind != other.kind ||
		   attribute.name != other.name || attribute.value != other.value ||
		   attribute.range.start != other.range.start || attribute.range.end != other.range.end {
			return false
		}
	}
	left_recoveries := jan_structural_analysis_recoveries(left)
	right_recoveries := jan_structural_analysis_recoveries(right)
	if len(left_recoveries) != len(right_recoveries) do return false
	for recovery, index in left_recoveries {
		other := right_recoveries[index]
		if recovery.node_id != other.node_id || recovery.code != other.code ||
		   recovery.range.start != other.range.start || recovery.range.end != other.range.end {
			return false
		}
	}
	left_indexes := jan_structural_analysis_indexes(left)
	right_indexes := jan_structural_analysis_indexes(right)
	if len(left_indexes) != len(right_indexes) do return false
	for fact, index in left_indexes {
		other := right_indexes[index]
		if fact.id != other.id || fact.kind != other.kind || fact.node_id != other.node_id ||
		   fact.range.start != other.range.start || fact.range.end != other.range.end {
			return false
		}
	}
	return true
}

@(private = "file")
jan_incremental_test_find :: proc(source: []u8, needle: string) -> (int, bool) {
	if len(needle) == 0 || len(needle) > len(source) do return 0, false
	for start in 0 ..= len(source) - len(needle) {
		if string(source[start:start + len(needle)]) == needle do return start, true
	}
	return 0, false
}
