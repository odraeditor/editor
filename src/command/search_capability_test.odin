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

/* Verifies policy and session inspection return bounded values with copied lifetimes. */
@(test)
search_capability_copies_session_state :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two one", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	capability := search_capability_test_context(&fixture, {
		.Policy_Inspection,
		.Session_Inspection,
		.Semantic_Invocation,
	})
	scope, scoped, scope_failure := search_capability_scope(capability)
	testing.expectf(t, scoped, "search scope failed with %v", scope_failure.search_capability_code)
	if !scoped {
		return
	}
	policy, policy_ok, policy_failure := search_policy_inspect(capability, scope)
	testing.expectf(t, policy_ok, "policy inspection failed with %v", policy_failure.search_capability_code)
	if policy_ok {
		testing.expect_value(t, policy.policy.generation, search.Policy_Generation(1))
		testing.expect_value(t, policy.policy.search_limits, search.DEFAULT_LIMITS)
	}

	invoked, search_ok, search_failure := search_command_invoke(
		capability,
		Search_Command_Request {
			expected_scope = scope,
			name = "isearch-forward-regexp",
			pattern = "(one)",
			incremental_turn = .Query_Update,
			query_id = search.Query_ID(1),
			search_generation = search.Search_Generation(1),
		},
	)
	testing.expectf(t, search_ok, "search invocation failed with %v", search_failure)
	if !search_ok {
		return
	}
	testing.expect_value(t, invoked.result_scope.session_kind, Search_Session_Kind.Incremental)
	testing.expect_value(t, invoked.result_scope.interaction_generation, u64(1))

	copy_result, copied, copy_failure := search_session_inspect(
		capability,
		Search_Session_Copy_Request {
			expected_scope = invoked.result_scope,
			occurrence_limit = 2,
			capture_limit = 8,
			text_bytes_limit = 64,
		},
	)
	testing.expectf(t, copied, "session inspection failed with %v", copy_failure.search_capability_code)
	if !copied {
		return
	}
	defer search_session_copy_close(&copy_result)
	testing.expect_value(t, string(copy_result.pattern), "(one)")
	testing.expect_value(t, copy_result.kind, Search_Session_Kind.Incremental)
	testing.expect(t, copy_result.has_current)
	testing.expect(t, len(copy_result.occurrences) > 0)
	testing.expect(t, len(copy_result.captures) > 0)
	testing.expect(t, copy_result.usage.logical_bytes > 0)
	accepted, accept_failure := incremental_search_accept(&fixture.view_registry, fixture.view)
	testing.expectf(t, accepted, "search accept failed with %v", accept_failure)
	testing.expect_value(t, string(copy_result.pattern), "(one)")
	testing.expect_value(t, copy_result.current.buffer_id, editor.Buffer_ID(81))
}

/* Verifies every mutable generation and authority dimension is revalidated. */
@(test)
search_capability_rejects_bad_scope :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "needle", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	capability := search_capability_test_context(&fixture, {.Policy_Inspection, .Session_Inspection})
	scope, scoped, _ := search_capability_scope(capability)
	testing.expect(t, scoped)
	if !scoped {
		return
	}

	wrong := scope
	wrong.editor_session_id = Editor_Session_ID(92)
	_, ok, failure := search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Wrong_Editor)

	wrong = scope
	wrong.view.generation += 1
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Wrong_View)

	wrong = scope
	wrong.buffer_id = editor.Buffer_ID(999)
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Wrong_Buffer)

	wrong = scope
	wrong.revision = editor.Revision(99)
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Stale_Revision)

	wrong = scope
	wrong.command_registry_generation = interaction.Registry_Generation(99)
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(
		t,
		failure.search_capability_code,
		Search_Capability_Failure_Code.Stale_Command_Registry,
	)

	wrong = scope
	wrong.view_state_generation += 1
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Stale_View_State)

	wrong = scope
	wrong.access = {.Policy_Inspection}
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Wrong_Authority)

	wrong = scope
	wrong.interaction_generation = 7
	_, ok, failure = search_policy_inspect(capability, wrong)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Stale_Interaction)

	new_policy := capability
	new_policy.policy.generation = search.Policy_Generation(2)
	_, ok, failure = search_policy_inspect(new_policy, scope)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Stale_Policy)

	policy_only := capability
	policy_only.access = {.Policy_Inspection}
	policy_scope, policy_scoped, _ := search_capability_scope(policy_only)
	testing.expect(t, policy_scoped)
	_, ok, failure = search_session_inspect(
		policy_only,
		Search_Session_Copy_Request {
			expected_scope = policy_scope,
			occurrence_limit = 1,
			capture_limit = 1,
			text_bytes_limit = 1,
		},
	)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.search_capability_code, Search_Capability_Failure_Code.Permission_Denied)
}

/* Verifies replacement invocation returns copied usage after native ownership is closed. */
@(test)
search_capability_invokes_atomic_replace :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one one", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	capability := search_capability_test_context(&fixture, {.Semantic_Invocation})
	scope, scoped, _ := search_capability_scope(capability)
	testing.expect(t, scoped)
	if !scoped {
		return
	}

	result, replaced, replace_failure := search_command_invoke(
		capability,
		Search_Command_Request {
			expected_scope = scope,
			name = "replace-string",
			pattern = "one",
			replacement = "two",
			query_id = search.Query_ID(3),
			search_generation = search.Search_Generation(3),
			scope = search.Scope {
				buffer_id = scope.buffer_id,
				revision = scope.revision,
				start = 0,
				end = 7,
			},
		},
	)
	testing.expectf(t, replaced, "replacement invocation failed with %v", replace_failure)
	if !replaced {
		return
	}
	testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
	testing.expect_value(t, result.replacements, u64(2))
	testing.expect_value(t, result.replace_all_usage.matches, u64(2))
	testing.expect_value(t, result.result_scope.revision, editor.Revision(1))
	expect_native_state(t, &fixture, 0, 0, 1, "two two")

	_, allowed, allowed_failure := search_command_invoke(
		capability,
		Search_Command_Request {
			expected_scope = result.result_scope,
			name = "cursor-next-grapheme",
		},
	)
	testing.expect(t, !allowed)
	testing.expect_value(
		t,
		allowed_failure.search_capability_code,
		Search_Capability_Failure_Code.Command_Not_Allowed,
	)
}

@(private)
search_capability_test_context :: proc(
	fixture: ^Native_Fixture,
	access: Search_Access_Set,
) -> Search_Capability_Context {
	native := native_request(fixture, {})
	native.history_store = &fixture.history
	native.event_sequence = u64(native.transaction_id)
	native.history_grouping = history.Grouping_Context {
		kind = .Independent,
		view_id = fixture.view.view_id,
		view_generation = fixture.view.generation,
		continuity = 1,
		event_sequence = u64(native.transaction_id),
		monotonic_milliseconds = u64(native.transaction_id) * 10,
	}
	return Search_Capability_Context {
		editor_session_id = Editor_Session_ID(91),
		access = access,
		native = native,
		policy = Search_Capability_Policy {
			generation = search.Policy_Generation(1),
			search_policy = search.DEFAULT_POLICY,
			search_limits = search.DEFAULT_LIMITS,
			replacement_policy = search.DEFAULT_REPLACEMENT_POLICY,
			replacement_limits = search.DEFAULT_REPLACEMENT_LIMITS,
			replace_all_limits = DEFAULT_REPLACE_ALL_LIMITS,
		},
	}
}
