// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "core:mem"
import "core:testing"

/* Verifies factory and configured candidates compose with exact provenance and generations. */
@(test)
contextual_completion_composes_copied_candidates :: proc(t: ^testing.T) {
	source := "* TO\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_501) do return
	defer list_test_fixture_close(&fixture)
	fixture.scope.configuration_generation = 2
	fixture.scope.provider_generation = 2
	configuration: Editing_Configuration
	initialized, _ := editing_configuration_init(&configuration, 1, 1)
	testing.expect(t, initialized)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	values := []string{"READY", "DONE"}
	sources := []Configured_Completion_Source{{name = "team", kind = .Task_State, candidates = values}}
	candidate := editing_test_configuration_candidate(2, 2, nil, sources)
	_, published, failure := editing_configuration_publish(&configuration, candidate)
	testing.expectf(t, published, "configuration failed with %v", failure.code)
	if !published do return
	result: Completion_Result
	descriptor: Completion_Result_Descriptor
	prepared: bool
	descriptor, prepared, failure = contextual_completion_prepare(
		&result,
		&fixture.analysis,
		transmute([]u8)source,
		&configuration,
		{
			operation_id = 301,
			scope = fixture.scope,
			point = 4,
			kind = .Task_State,
		},
	)
	testing.expectf(t, prepared, "completion failed with %v", failure.code)
	if !prepared do return
	defer completion_result_close(&result)
	testing.expect_value(t, descriptor.factory_candidates, u16(2))
	testing.expect_value(t, descriptor.configured_candidates, u16(1))
	items := completion_result_candidates(&result)
	testing.expect_value(t, len(items), 3)
	testing.expect_value(t, items[0].provider, "odra-factory")
	testing.expect_value(t, items[2].provider, "team")
	testing.expect_value(t, items[2].text, "READY")
	testing.expect_value(t, items[2].configuration_generation, Configuration_Generation(2))
	plan: language.Jan_Rewrite_Plan
	planned, plan_failure := completion_candidate_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		items[2],
		301,
	)
	testing.expectf(t, planned, "candidate plan failed with %v", plan_failure.code)
	if planned {
		defer language.jan_rewrite_plan_close(&plan)
		testing.expect(t, list_test_publish_and_history(&fixture, &plan, "* READY\n"))
	}
	limited := DEFAULT_LIMITS
	limited.completion_candidates = 2
	fallback: Completion_Result
	fallback_descriptor, fallback_prepared, fallback_failure := contextual_completion_prepare(
		&fallback,
		&fixture.analysis,
		transmute([]u8)source,
		&configuration,
		{operation_id = 306, scope = fixture.scope, point = 4, kind = .Task_State},
		limited,
	)
	testing.expectf(t, fallback_prepared, "configured overflow blocked factory candidates with %v", fallback_failure.code)
	if fallback_prepared {
		defer completion_result_close(&fallback)
		testing.expect_value(t, fallback_descriptor.factory_candidates, u16(2))
		testing.expect_value(t, fallback_descriptor.configured_candidates, u16(0))
	}
}

/* Verifies factory candidates survive absent configured contributions and strict limits. */
@(test)
contextual_completion_preserves_factory_fallback :: proc(t: ^testing.T) {
	source := "#+"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_502) do return
	defer list_test_fixture_close(&fixture)
	configuration: Editing_Configuration
	initialized, _ := editing_configuration_init(&configuration, 1, 1)
	testing.expect(t, initialized)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	result: Completion_Result
	descriptor, prepared, failure := contextual_completion_prepare(
		&result,
		&fixture.analysis,
		transmute([]u8)source,
		&configuration,
		{operation_id = 302, scope = fixture.scope, point = 2, kind = .Keyword},
	)
	testing.expectf(t, prepared, "factory completion failed with %v", failure.code)
	if prepared {
		defer completion_result_close(&result)
		testing.expect_value(t, descriptor.factory_candidates, u16(3))
		testing.expect_value(t, descriptor.configured_candidates, u16(0))
	}
	limited := DEFAULT_LIMITS
	limited.completion_candidates = 2
	overflow: Completion_Result
	_, prepared, failure = contextual_completion_prepare(
		&overflow,
		&fixture.analysis,
		transmute([]u8)source,
		&configuration,
		{operation_id = 303, scope = fixture.scope, point = 2, kind = .Keyword},
		limited,
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
	testing.expect_value(t, overflow.state, rawptr(nil))
}

/* Verifies factory precedence and configured templates expand as one undo unit. */
@(test)
structure_templates_resolve_conflicts_and_expand_atomically :: proc(t: ^testing.T) {
	source := "* Heading\nBody\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_503) do return
	defer list_test_fixture_close(&fixture)
	fixture.scope.configuration_generation = 2
	fixture.scope.provider_generation = 2
	configuration: Editing_Configuration
	initialized, _ := editing_configuration_init(&configuration, 1, 1)
	testing.expect(t, initialized)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	templates := []Configured_Template{
		{key = "src", template_context = .Document, source = "configured conflict\n"},
		{key = "note", template_context = .Document, source = "#+begin_note\n\n#+end_note\n"},
	}
	candidate := editing_test_configuration_candidate(2, 2, templates, nil)
	_, published, _ := editing_configuration_publish(&configuration, candidate)
	testing.expect(t, published)
	factory, resolved, _ := template_resolve(&configuration, fixture.scope, "src")
	testing.expect(t, resolved && factory.factory)
	testing.expect_value(t, factory.source, "#+begin_src \n\n#+end_src\n")
	plan: language.Jan_Rewrite_Plan
	resolution, planned, failure := template_expansion_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		&configuration,
		{
			operation_id = 304,
			scope = fixture.scope,
			key = "note",
			point = 0,
			rewrite_generation = 304,
		},
	)
	testing.expectf(t, planned, "template expansion failed with %v", failure.code)
	if planned {
		defer language.jan_rewrite_plan_close(&plan)
		testing.expect(t, !resolution.factory)
		testing.expect(t, list_test_publish_and_history(
			&fixture,
			&plan,
			"#+begin_note\n\n#+end_note\n* Heading\nBody\n",
		))
	}
}

/* Verifies hard indentation changes source explicitly and keeps headings left-aligned. */
@(test)
hard_indentation_uses_one_checked_rewrite :: proc(t: ^testing.T) {
	source := "  * Heading\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_504) do return
	defer list_test_fixture_close(&fixture)
	plan: language.Jan_Rewrite_Plan
	planned, failure := hard_indentation_plan_prepare(
		&plan,
		&fixture.analysis,
		transmute([]u8)source,
		fixture.scope,
		{scope = fixture.scope.analysis, start = 0, end = editor.Byte_Offset(len(source))},
		305,
		2,
	)
	testing.expectf(t, planned, "hard indentation failed with %v", failure.code)
	if planned {
		defer language.jan_rewrite_plan_close(&plan)
		testing.expect(t, list_test_publish_and_history(&fixture, &plan, "* Heading\n"))
	}
}

/* Verifies completion and template faults release candidates and rewrite plans exactly. */
@(test)
contextual_authoring_allocation_faults_leave_no_partial_state :: proc(t: ^testing.T) {
	completion_source := "#+"
	completion_fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &completion_fixture, completion_source, 2_505) do return
	defer list_test_fixture_close(&completion_fixture)
	configuration: Editing_Configuration
	initialized, _ := editing_configuration_init(&configuration, 1, 1)
	testing.expect(t, initialized)
	if !initialized do return
	defer editing_configuration_close(&configuration)
	for fail_after in 0 ..< 8 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator{
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		result: Completion_Result
		_, prepared, failure := contextual_completion_prepare(
			&result,
			&completion_fixture.analysis,
			transmute([]u8)completion_source,
			&configuration,
			{operation_id = Operation_ID(320 + fail_after), scope = completion_fixture.scope, point = 2, kind = .Keyword},
			allocator = visibility_test_failing_allocator(&failing),
		)
		if prepared {
			completion_result_close(&result)
		} else {
			testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
			testing.expect_value(t, result.state, rawptr(nil))
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	template_source := "* Heading\n"
	template_fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &template_fixture, template_source, 2_506) do return
	defer list_test_fixture_close(&template_fixture)
	for fail_after in 0 ..< 5 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Visibility_Test_Failing_Allocator{
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		plan: language.Jan_Rewrite_Plan
		_, planned, failure := template_expansion_plan_prepare(
			&plan,
			&template_fixture.analysis,
			transmute([]u8)template_source,
			&configuration,
			{operation_id = 330, scope = template_fixture.scope, key = "src", point = 0, rewrite_generation = 330},
			visibility_test_failing_allocator(&failing),
		)
		if planned {
			language.jan_rewrite_plan_close(&plan)
		} else {
			testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
			testing.expect_value(t, plan.state, rawptr(nil))
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}
