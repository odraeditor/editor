// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor"
import "../language"
import "core:testing"

@(test)
/* injections_compose_nested_regions_with_stable_precedence verifies deterministic nesting. */
injections_compose_nested_regions_with_stable_precedence :: proc(t: ^testing.T) {
	fixture: Injection_Test_Fixture
	injection_test_fixture_init(&fixture)
	request := fixture.request
	result, composed, failure := injection_compose(request)
	testing.expect(t, composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.None)
	defer injection_result_close(&result)
	testing.expect_value(t, len(result.regions), 3)
	testing.expect_value(t, result.regions[0].identity, Injection_Region_ID(3))
	testing.expect_value(t, result.regions[1].identity, Injection_Region_ID(2))
	testing.expect_value(t, result.regions[1].depth, u8(1))
	testing.expect_value(t, result.regions[2].identity, Injection_Region_ID(1))
	testing.expect_value(t, result.skipped_missing_child, u16(1))
}

@(test)
/* injections_reject_cycles_invalid_parents_and_resource_excess verifies invalid graphs. */
injections_reject_cycles_invalid_parents_and_resource_excess :: proc(t: ^testing.T) {
	fixture: Injection_Test_Fixture
	injection_test_fixture_init(&fixture)
	request := fixture.request
	request.candidates[0].start = request.candidates[1].start
	request.candidates[0].end = request.candidates[1].end
	request.candidates[0].parent_identity = 2
	request.candidates[1].parent_identity = 1
	_, composed, failure := injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Cycle)

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.candidates[1].start = 5
	_, composed, failure = injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Invalid_Parent)

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.limits.span_bytes = 10
	_, composed, failure = injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Resource_Limit)
}

@(test)
/* injections_incremental_invalidation_preserves_only_proven_prefix verifies edit invalidation. */
injections_incremental_invalidation_preserves_only_proven_prefix :: proc(t: ^testing.T) {
	fixture: Injection_Test_Fixture
	injection_test_fixture_init(&fixture)
	request := fixture.request
	result, composed, _ := injection_compose(request)
	testing.expect(t, composed)
	defer injection_result_close(&result)
	invalidated, updated := injection_invalidate(&result, 18, 2, 2)
	testing.expect(t, updated)
	testing.expect_value(t, invalidated, u16(2))
	testing.expect_value(t, len(result.regions), 1)
	testing.expect_value(t, result.regions[0].identity, Injection_Region_ID(3))
	testing.expect_value(t, result.regions[0].source_revision, editor.Revision(2))
}

@(test)
/* injections_handle_empty_overlap_malformed_and_excessive_inputs verifies edge cases. */
injections_handle_empty_overlap_malformed_and_excessive_inputs :: proc(t: ^testing.T) {
	fixture: Injection_Test_Fixture
	injection_test_fixture_init(&fixture)
	request := fixture.request
	request.candidates = nil
	empty, composed, failure := injection_compose(request)
	testing.expect(t, composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.None)
	testing.expect_value(t, len(empty.regions), 0)
	injection_result_close(&empty)

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.candidates[1].parent_identity = 0
	request.candidates[1].start = 15
	request.candidates[1].end = 95
	overlap: Injection_Result
	overlap, composed, failure = injection_compose(request)
	testing.expect(t, composed)
	if composed {
		defer injection_result_close(&overlap)
		testing.expect_value(t, overlap.regions[0].identity, Injection_Region_ID(3))
		testing.expect_value(t, overlap.regions[1].identity, Injection_Region_ID(2))
		testing.expect_value(t, overlap.regions[2].identity, Injection_Region_ID(1))
	}

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.candidates[1].identity = request.candidates[0].identity
	_, composed, failure = injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Duplicate_Identity)

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.candidates[0].end = editor.Byte_Offset(request.source_bytes + 1)
	_, composed, failure = injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Invalid_Range)

	injection_test_fixture_init(&fixture)
	request = fixture.request
	request.limits.regions = 2
	_, composed, failure = injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Region_Limit)
}

@(test)
/* injections_honor_cancellation_without_publication verifies cancelled composition. */
injections_honor_cancellation_without_publication :: proc(t: ^testing.T) {
	fixture: Injection_Test_Fixture
	injection_test_fixture_init(&fixture)
	cancelled := true
	request := fixture.request
	request.cancellation = {
		user_data = &cancelled,
		check = injection_test_cancelled,
	}
	result, composed, failure := injection_compose(request)
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Injection_Failure_Code.Cancelled)
	testing.expect(t, result.regions == nil)
}

/* Injection_Test_Fixture owns reusable containing and embedded provider data. */
Injection_Test_Fixture :: struct {
	request:    Injection_Compose_Request,
	candidates: [4]Injection_Candidate,
	children:   [2]Injection_Child_Provider,
}

/* injection_test_fixture_init resets one fixture to a valid nested baseline. */
injection_test_fixture_init :: proc(fixture: ^Injection_Test_Fixture) {
	fixture^ = {}
	odin := injection_test_language(1, "odin")
	javascript := injection_test_language(2, "javascript")
	css := injection_test_language(3, "css")
	fixture.candidates = {
		{identity = 1, start = 10, end = 90, language_id = 2, priority = 10},
		{identity = 2, parent_identity = 1, start = 20, end = 40, language_id = 3, priority = 20},
		{identity = 3, start = 0, end = 8, language_id = 2, priority = 30},
		{identity = 4, start = 91, end = 99, language_id = 9, priority = 40},
	}
	fixture.children = {
		{identity = javascript, selection = injection_test_selection(javascript, 2)},
		{identity = css, selection = injection_test_selection(css, 3)},
	}
	fixture.request = {
		buffer_id = 1,
		source_revision = 1,
		source_bytes = 100,
		containing_language = odin,
		containing_provider = injection_test_handle(1, 1),
		generation = 1,
		candidates = fixture.candidates[:],
		children = fixture.children[:],
		limits = DEFAULT_INJECTION_LIMITS,
	}
}

/* injection_test_language builds one bounded test language identity. */
injection_test_language :: proc(id: language.Language_ID, name: string) -> language.Language_Identity {
	result := language.Language_Identity {id = id, generation = 1}
	result.name.length = u16(copy(result.name.bytes[:], name))
	return result
}

/* injection_test_handle builds one active provider handle. */
injection_test_handle :: proc(language_id: language.Language_ID, provider_id: language.Provider_ID) -> language.Provider_Handle {
	return {registry_id = 1, language_id = language_id, provider_id = provider_id, provider_generation = 1}
}

/* injection_test_selection builds one factory provider selection. */
injection_test_selection :: proc(identity: language.Language_Identity, provider_id: language.Provider_ID) -> language.Provider_Selection {
	handle := injection_test_handle(identity.id, provider_id)
	return {registry_id = 1, registry_generation = 1, language = identity, state = .Factory, active = handle, factory = handle}
}

/* injection_test_cancelled reads the fixture cancellation flag. */
injection_test_cancelled :: proc "odin" (user_data: rawptr) -> bool {
	return user_data != nil && (cast(^bool)user_data)^
}
