// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../language_service"
import "core:mem"
import "core:testing"

/* Verifies Project diagnostics publish stable ordered identities, annotations, and checked actions. */
@(test)
diagnostic_candidates_preserve_order :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	binding_a := diagnostic_candidate_test_binding(1)
	binding_b := diagnostic_candidate_test_binding(2)
	storage_a_text := "warning aodinW1"
	storage_b_text := "error bodinE1"
	storage_a := transmute([]u8)storage_a_text
	storage_b := transmute([]u8)storage_b_text
	records_a := [1]language_service.Diagnostic_Record {{binding = binding_a,
		generation = 7, id = 1, canonical_revision = 3, range = {start = 9, end = 10},
		severity = .Warning, message = {storage_generation = 7, length = 9},
		source = {storage_generation = 7, offset = 9, length = 4},
		code = {storage_generation = 7, offset = 13, length = 2}}}
	records_b := [1]language_service.Diagnostic_Record {{binding = binding_b,
		generation = 8, id = 1, canonical_revision = 5, range = {start = 2, end = 3},
		severity = .Error, message = {storage_generation = 8, length = 7},
		source = {storage_generation = 8, offset = 7, length = 4},
		code = {storage_generation = 8, offset = 11, length = 2}}}
	batch_a := language_service.Diagnostic_Batch_Copy {descriptor = {binding = binding_a,
		generation = 7, canonical_revision = 3, diagnostics = 1},
		records = records_a[:], storage = storage_a}
	batch_b := language_service.Diagnostic_Batch_Copy {descriptor = {binding = binding_b,
		generation = 8, canonical_revision = 5, diagnostics = 1},
		records = records_b[:], storage = storage_b}
	documents := [2]Diagnostic_Candidate_Document {
		{batch = &batch_a, path = "/project/z.odin", buffer_id = 31},
		{batch = &batch_b, path = "/project/a.odin", buffer_id = 32},
	}
	source, built, failure := diagnostic_candidate_source_build(
		{scope_identity = 11, scope_generation = 12, source_generation = 13,
			documents = documents[:]}, allocator)
	testing.expectf(t, built, "diagnostic source failed with %v", failure.code)
	if !built do return
	defer diagnostic_candidate_source_close(&source)
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Language_Diagnostics)
	testing.expect_value(t, len(source.definition.descriptors), 2)
	if len(source.definition.descriptors) == 2 {
		testing.expect_value(t, source.definition.descriptors[0].label, "error b")
		testing.expect_value(t, source.definition.descriptors[1].label, "warning a")
		testing.expect_value(t, source.definition.descriptors[0].annotations[0].text, "error")
		testing.expect_value(t, source.definition.descriptors[0].annotations[1].text, "/project/a.odin")
		testing.expect(t, diagnostic_candidate_action_matches(
			source.definition.descriptors[0].action, source.locations[0], 13))
		stale := source.locations[0]
		stale.canonical_revision += 1
		testing.expect(t, !diagnostic_candidate_action_matches(
			source.definition.descriptors[0].action, stale, 13))
	}
	session: Candidate_Session
	_, admitted, admission_failure := candidate_session_init(&session,
		{session_id = 81, limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator, temporary_allocator = context.temp_allocator},
		source.definition)
	testing.expectf(t, admitted, "diagnostic admission failed with %v", admission_failure.code)
	if admitted {
		view, viewed, _ := candidate_session_view(&session)
		testing.expect(t, viewed)
		if viewed {
			testing.expect_value(t, view.rows[0].identity, source.definition.descriptors[0].identity)
			storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
			prompt, prompt_ok := candidate_prompt_label(view, storage[:])
			testing.expect(t, prompt_ok)
			testing.expect(t, len(prompt) > 0)
		}
		_, _, _ = candidate_session_close(&session)
	}
}

@(private)
diagnostic_candidate_test_binding :: proc(id: u64) -> language_service.Document_Binding_Handle {
	return {session = {provider = {definition = {registry = {id = 1, generation = 1},
		id = 1, generation = 1}, id = 1, generation = 1}, id = 1, generation = 1},
		id = language_service.Document_Binding_ID(id), generation = 1}
}
