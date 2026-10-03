// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:encoding/endian"
import "core:mem"
import "core:testing"

/* Personal_Candidate_Test_Value describes one encoded result fixture row. */
Personal_Candidate_Test_Value :: struct {
	identity: string,
	label:    string,
	search:   string,
	path:     string,
	start:    u64,
	end:      u64,
	revision: u64,
	action:   Personal_Candidate_Action,
}

@(private)
personal_candidate_test_payload :: proc(allocator := context.allocator) -> []u8 {
	title := "Roman relations: Ada Lovelace"
	query := "Ada"
	values := [3]Personal_Candidate_Test_Value {
		{
			identity = "ada",
			label = "Ada Lovelace",
			search = "mathematician computing aja",
			path = "/brain/ada.org",
			start = 12,
			end = 24,
			revision = 0,
			action = .Navigate,
		},
		{
			identity = "engine",
			label = "Analytical Engine",
			search = "Ada machine",
			path = "/brain/engine.org",
			start = 40,
			end = 57,
			revision = 5,
			action = .Resume,
		},
		{
			identity = "interactive-value",
			label = "Use the entered value",
			search = "",
			path = "/brain/notes.org",
			start = 18,
			end = 18,
			revision = 8,
			action = .Resume_Query,
		},
	}
	string_bytes := len(title) + len(query)
	for value in values {
		string_bytes += len(value.identity) + len(value.label) + len(value.search) + len(value.path)
	}
	result := make(
		[]u8,
		PERSONAL_CANDIDATE_RESULT_HEADER_BYTES +
			len(values) * PERSONAL_CANDIDATE_RESULT_RECORD_BYTES + string_bytes,
		allocator,
	)
	string_start := PERSONAL_CANDIDATE_RESULT_HEADER_BYTES +
		len(values) * PERSONAL_CANDIDATE_RESULT_RECORD_BYTES
	string_cursor := 0
	copy(result[string_start:], transmute([]u8)title)
	string_cursor += len(title)
	copy(result[string_start + string_cursor:], transmute([]u8)query)
	query_offset := string_cursor
	string_cursor += len(query)
	for value, index in values {
		spans: [8]u64
		texts := [4]string {value.identity, value.label, value.search, value.path}
		for text, text_index in texts {
			spans[text_index * 2] = u64(string_cursor)
			spans[text_index * 2 + 1] = u64(len(text))
			copy(result[string_start + string_cursor:], transmute([]u8)text)
			string_cursor += len(text)
		}
		record := [12]u64 {
			spans[0], spans[1], spans[2], spans[3],
			spans[4], spans[5], spans[6], spans[7],
			value.start, value.end, value.revision, u64(value.action),
		}
		base := PERSONAL_CANDIDATE_RESULT_HEADER_BYTES +
			index * PERSONAL_CANDIDATE_RESULT_RECORD_BYTES
		for field, field_index in record {
			assert(endian.put_u64(result[base + field_index * 8:], .Little, field))
		}
	}
	header := [8]u64 {
		PERSONAL_CANDIDATE_RESULT_SCHEMA,
		7,
		u64(len(values)),
		PERSONAL_CANDIDATE_RESULT_RECORD_BYTES,
		u64(query_offset),
		u64(len(query)),
		u64(string_bytes),
		u64(len(title)),
	}
	for field, index in header {
		assert(endian.put_u64(result[index * 8:], .Little, field))
	}
	return result
}

/* Verifies copied command candidates filter, move, cancel, and retain exact targets. */
@(test)
personal_candidates_use_the_shared_selection_session :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	payload := personal_candidate_test_payload(allocator)
	source, decoded, failure := personal_candidate_source_decode(payload, 11, allocator)
	testing.expectf(t, decoded, "personal candidate decode failed with %v", failure.code)
	if !decoded {
		delete(payload, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	testing.expect_value(t, source.title, "Roman relations: Ada Lovelace")
	testing.expect_value(t, source.initial_query, "Ada")
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Personal_Command_Results)
	session: Candidate_Session
	_, initialized, initialization_failure := candidate_session_init(
		&session,
		Candidate_Config {
			session_id = 9,
			limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = allocator,
		},
		source.definition,
		source.initial_query,
	)
	testing.expectf(t, initialized, "personal candidate session failed with %v", initialization_failure.code)
	if initialized {
		view, viewed, view_failure := candidate_session_view(&session)
		testing.expectf(t, viewed, "personal candidate view failed with %v", view_failure.code)
		testing.expect_value(t, len(view.rows), 3)
		prompt_storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
		prompt, prompt_ok := candidate_prompt_label(view, prompt_storage[:])
		testing.expect(t, prompt_ok)
		if prompt_ok do testing.expect_value(t, prompt, "Candidates 1/3 Select: ")
		if len(view.rows) == 3 {
			testing.expect_value(t, view.rows[0].label, "Ada Lovelace")
			testing.expect_value(t, view.rows[1].label, "Analytical Engine")
			row_storage: [64]u8
			row, row_ok := candidate_row_text_write(
				.Personal_Command_Results,
				view.rows[0],
				row_storage[:],
			)
			testing.expect(t, row_ok)
			if row_ok do testing.expect_value(t, row, "Ada Lovelace")
			target, found := personal_candidate_action_target(view.rows[1].action, &source)
			testing.expect(t, found)
			if found {
				testing.expect_value(t, target.identity, "engine")
				testing.expect_value(t, target.document_path, "/brain/engine.org")
				testing.expect_value(t, target.start, u64(40))
				testing.expect_value(t, target.end, u64(57))
				testing.expect_value(t, target.source_revision, u64(5))
				testing.expect_value(t, target.action, Personal_Candidate_Action.Resume)
			}
			prompt_target, prompt_found := personal_candidate_action_target(
				view.rows[2].action, &source,
			)
			testing.expect(t, prompt_found)
			if prompt_found {
				testing.expect_value(t, prompt_target.action, Personal_Candidate_Action.Resume_Query)
				testing.expect_value(t, view.rows[2].action.kind, Candidate_Action_Kind.Open_Command_Prompt)
			}
		}
		request := Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		}
		_, moved, move_failure := candidate_session_move(&session, request, 1)
		testing.expectf(t, moved, "personal candidate movement failed with %v", move_failure.code)
		view, _, _ = candidate_session_view(&session)
		_, alias_queried, alias_query_failure := candidate_session_set_query(
			&session,
			Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
			"aj",
		)
		testing.expectf(
			t,
			alias_queried,
			"personal alias query failed with %v",
			alias_query_failure.code,
		)
		view, _, _ = candidate_session_view(&session)
		testing.expect_value(t, len(view.rows), 2)
		if len(view.rows) == 2 {
			testing.expect_value(t, view.rows[0].label, "Ada Lovelace")
			target, found := personal_candidate_action_target(view.rows[0].action, &source)
			testing.expect(t, found)
			if found {
				testing.expect_value(t, target.identity, "ada")
				testing.expect_value(t, target.document_path, "/brain/ada.org")
			}
			testing.expect_value(t, view.rows[1].action.kind, Candidate_Action_Kind.Open_Command_Prompt)
		}
		_, queried, query_failure := candidate_session_set_query(
			&session,
			Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
			"unmatched arbitrary value",
		)
		testing.expectf(t, queried, "personal prompt query failed with %v", query_failure.code)
		view, _, _ = candidate_session_view(&session)
		testing.expect_value(t, len(view.rows), 1)
		if len(view.rows) == 1 {
			testing.expect_value(t, view.rows[0].action.kind, Candidate_Action_Kind.Open_Command_Prompt)
		}
		_, cancelled, cancel_failure := candidate_session_cancel(
			&session,
			Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
		)
		testing.expectf(t, cancelled, "personal candidate cancellation failed with %v", cancel_failure.code)
		_, closed, close_failure := candidate_session_close(&session)
		testing.expectf(t, closed, "personal candidate close failed with %v", close_failure.code)
	}
	personal_candidate_source_close(&source)
	delete(payload, allocator)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies malformed spans and stale actions never produce navigation targets. */
@(test)
personal_candidates_reject_malformed_and_stale_inputs :: proc(t: ^testing.T) {
	payload := personal_candidate_test_payload()
	defer delete(payload)
	assert(endian.put_u64(payload[64:], .Little, u64(len(payload))))
	_, decoded, failure := personal_candidate_source_decode(payload, 3)
	testing.expect(t, !decoded)
	testing.expect_value(t, failure.code, Candidate_Failure_Code.Invalid_Source)

	invalid_action := personal_candidate_test_payload()
	defer delete(invalid_action)
	assert(endian.put_u64(
		invalid_action[PERSONAL_CANDIDATE_RESULT_HEADER_BYTES + 11 * 8:],
		.Little,
		6,
	))
	_, action_decoded, action_failure := personal_candidate_source_decode(invalid_action, 3)
	testing.expect(t, !action_decoded)
	testing.expect_value(t, action_failure.code, Candidate_Failure_Code.Invalid_Source)

	valid := personal_candidate_test_payload()
	defer delete(valid)
	source, valid_decoded, _ := personal_candidate_source_decode(valid, 4)
	testing.expect(t, valid_decoded)
	if !valid_decoded do return
	defer personal_candidate_source_close(&source)
	_, found := personal_candidate_action_target(
		Candidate_Action {
			kind = .Open_Command_Candidate,
			owner_generation = source.definition.scope_generation + 1,
			primary = 1,
		},
		&source,
	)
	testing.expect(t, !found)
}
