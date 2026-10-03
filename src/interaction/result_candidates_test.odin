// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../result_set"
import "core:testing"

@(test)
/* Verifies result candidates retain checked set, generation, and location identity. */
preserve_checked_location_identity :: proc(t: ^testing.T) {
	locations := []result_set.Location {{
		id = 7, buffer_id = 4, revision = 3, start = 8, end = 13,
		source_identity = 99, preview = "call needle now", annotation = "2:6",
		preview_match_start = 5, preview_match_end = 11, preview_match_present = true,
	}}
	view := result_set.View {
		set_id = 2, generation = 5,
		source = {id = 6, generation = 1, kind = .Active_Search},
		metadata = {descriptor = "needle"}, locations = locations,
	}
	source, built, failure := result_candidate_source_build(view, 9)
	testing.expectf(t, built, "result candidate build failed with %v", failure.code)
	defer result_candidate_source_close(&source)
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Results)
	testing.expect_value(t, source.definition.descriptors[0].label, "call needle now")
	testing.expect_value(t, source.definition.descriptors[0].label_highlight_start, u32(5))
	testing.expect_value(t, source.definition.descriptors[0].label_highlight_end, u32(11))
	testing.expect(t, source.definition.descriptors[0].label_highlight_present)
	action := source.definition.descriptors[0].action
	testing.expect_value(t, action.kind, Candidate_Action_Kind.Visit_Result)
	testing.expect_value(t, action.owner_generation, u64(5))
	testing.expect_value(t, action.graph_identity[1], u64(3))
	session: Candidate_Session
	_, initialized, _ := candidate_session_init(&session, Candidate_Config{
		session_id = 1,
		limits = DEFAULT_CANDIDATE_LIMITS,
		persistent_allocator = context.allocator,
		temporary_allocator = context.temp_allocator,
	}, source.definition)
	testing.expect(t, initialized)
	defer if initialized do _, _, _ = candidate_session_close(&session)
	candidate_view, viewed, _ := candidate_session_view(&session)
	testing.expect(t, viewed)
	prompt_storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	prompt, prompt_ok := candidate_prompt_label(candidate_view, prompt_storage[:])
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt, "Results [current set] 1/1 Result: ")
}

/* Verifies result presentation replaces tabs without mutating source result storage. */
@(test)
normalize_tabs_at_the_presentation_boundary :: proc(t: ^testing.T) {
	locations := []result_set.Location{{
		id = 1, buffer_id = 1, revision = 1, start = 1, end = 5,
		preview = "\t\tmake_task", annotation = "4:3",
		preview_match_start = 7, preview_match_end = 11, preview_match_present = true,
	}}
	view := result_set.View{
		set_id = 1, generation = 1,
		source = {id = 1, generation = 1, kind = .Active_Search},
		metadata = {descriptor = "task"}, locations = locations,
	}
	source, built, failure := result_candidate_source_build(view, 1)
	testing.expectf(t, built, "result candidate build failed with %v", failure.code)
	if !built do return
	defer result_candidate_source_close(&source)
	testing.expect_value(t, source.definition.descriptors[0].label, "  make_task")
	testing.expect_value(t, source.definition.descriptors[0].label_highlight_start, u32(7))
	testing.expect_value(t, source.definition.descriptors[0].label_highlight_end, u32(11))
}

@(test)
/* Verifies each result file independently zero-pads line and column decimal places. */
result_candidates_align_location_digits_per_file :: proc(t: ^testing.T) {
	locations := []result_set.Location {
		{id = 1, group_id = 1, buffer_id = 1, revision = 1, start = 1, end = 2,
			preview = "first", annotation = "11:9"},
		{id = 2, group_id = 1, buffer_id = 1, revision = 1, start = 3, end = 4,
			preview = "second", annotation = "14:12"},
		{id = 3, group_id = 1, buffer_id = 1, revision = 1, start = 5, end = 6,
			preview = "third", annotation = "22:7"},
		{id = 4, group_id = 2, buffer_id = 2, revision = 1, start = 1, end = 2,
			preview = "fourth", annotation = "11:9"},
		{id = 5, group_id = 2, buffer_id = 2, revision = 1, start = 3, end = 4,
			preview = "fifth", annotation = "14:12"},
		{id = 6, group_id = 2, buffer_id = 2, revision = 1, start = 5, end = 6,
			preview = "sixth", annotation = "122:7"},
	}
	groups := []result_set.Group {
		{id = 1, label = "src/first.odin"},
		{id = 2, label = "src/second.odin"},
	}
	view := result_set.View {
		set_id = 1, generation = 1,
		source = {id = 1, generation = 1, kind = .Project_Search},
		metadata = {descriptor = "result"}, locations = locations, groups = groups,
	}
	source, built, failure := result_candidate_source_build(view, 1)
	testing.expectf(t, built, "result candidate build failed with %v", failure.code)
	if !built do return
	defer result_candidate_source_close(&source)
	expected := []string {"11:09", "14:12", "22:07", "011:09", "014:12", "122:07"}
	for descriptor, index in source.definition.descriptors {
		testing.expect_value(t, descriptor.annotations[1].text, expected[index])
	}
}

/* Verifies filtering preserves canonical result location order instead of label ranking. */
@(test)
keep_canonical_location_order_while_filtering :: proc(t: ^testing.T) {
	locations := []result_set.Location{
		{id = 2, buffer_id = 1, revision = 1, start = 6, end = 10,
			preview = "task alpha", annotation = "8:1"},
		{id = 1, buffer_id = 1, revision = 1, start = 1, end = 5,
			preview = "zeta task", annotation = "2:1"},
	}
	view := result_set.View{
		set_id = 1, generation = 1,
		source = {id = 1, generation = 1, kind = .Active_Search},
		metadata = {descriptor = "task"}, locations = locations,
	}
	source, built, failure := result_candidate_source_build(view, 1)
	testing.expectf(t, built, "result candidate build failed with %v", failure.code)
	if !built do return
	defer result_candidate_source_close(&source)
	session: Candidate_Session
	result, initialized, initialization_failure := candidate_session_init(&session, Candidate_Config{
		session_id = 1, limits = DEFAULT_CANDIDATE_LIMITS,
		persistent_allocator = context.allocator, temporary_allocator = context.temp_allocator,
	}, source.definition)
	testing.expectf(t, initialized, "result candidate init failed with %v", initialization_failure.code)
	if !initialized do return
	defer candidate_session_close(&session)
	candidate_view, viewed, _ := candidate_session_view(&session)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, candidate_view.rows[0].label, "zeta task")
		testing.expect_value(t, candidate_view.rows[1].label, "task alpha")
	}
	_, filtered, filter_failure := candidate_session_set_query(&session, {
		session_id = result.session_id, session_generation = result.session_generation,
	}, "task")
	testing.expectf(t, filtered, "result candidate filter failed with %v", filter_failure.code)
	candidate_view, viewed, _ = candidate_session_view(&session)
	if viewed {
		testing.expect_value(t, candidate_view.rows[0].label, "zeta task")
		testing.expect_value(t, candidate_view.rows[1].label, "task alpha")
	}
}
