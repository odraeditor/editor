// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_extension_focused

import odra "../../src/ksawery_module"
import ksawery "../../src/ksawery"
import "core:testing"
import "core:time"

/* conflict_assistance_workflow_evaluation builds one validated surface turn. */
conflict_assistance_workflow_evaluation :: proc(
	fixture: ^Conflict_Assistance_Process_Fixture,
	kind: ksawery.Conflict_Assistance_Response_Kind,
) -> odra.Ksawery_Conflict_Assistance_Evaluation {
	response := ksawery.Conflict_Assistance_Response {
		request = fixture.request.request,
		provider = fixture.request.provider,
		target = fixture.request.target,
		kind = kind,
	}
	if kind == .Guidance {
		assert(ksawery.conflict_assistance_guidance_assign(
			&response.guidance,
			"Compare the copied sides, then choose an explicit core resolution action.",
		))
	} else if kind == .External_Tool {
		response.tool = fixture.tool
	}
	evaluation := odra.Ksawery_Conflict_Assistance_Evaluation {
		provider = fixture.provider,
		provider_declaration = fixture.provider_declaration,
		operation_declaration = fixture.operation_declaration,
		selection = fixture.selection,
		request = fixture.request,
		response = response,
		available = true,
	}
	if kind == .External_Tool {
		argument_count := len(response.tool.operation.arguments)
		copy(evaluation.arguments[:argument_count], response.tool.operation.arguments)
		evaluation.response.tool.operation.arguments = evaluation.arguments[:argument_count]
	}
	return evaluation
}

/* conflict_assistance_workflow_run_tool completes one fixture through checked refresh. */
conflict_assistance_workflow_run_tool :: proc(
	t: ^testing.T,
	fixture: ^Conflict_Assistance_Process_Fixture,
) -> (ksawery.Repository_Process_Outcome, bool) {
	workflow: odra.Ksawery_Conflict_Assistance_Workflow
	evaluation := conflict_assistance_workflow_evaluation(fixture, .External_Tool)
	if !testing.expect(t, odra.ksawery_conflict_assistance_workflow_compose(&workflow, evaluation)) {
		return .None, false
	}
	defer odra.ksawery_conflict_assistance_workflow_close(&workflow)
	coordinator: odra.Ksawery_Process_Coordinator
	if !odra.ksawery_process_coordinator_init(&coordinator, fixture.request.target.repository) {
		return .None, false
	}
	defer odra.ksawery_process_coordinator_close(&coordinator)
	started, failure := odra.ksawery_conflict_assistance_workflow_begin_tool(
		&workflow,
		&coordinator,
		fixture.index,
		fixture.provider.contributor,
		fixture.request.target.repository,
		fixture.request.target.repository_generation,
		1,
	)
	if !testing.expectf(t, started, "tool start failed: %v", failure.code) {
		return .None, false
	}
	refresh_ready := false
	for step in 0 ..< 2_000 {
		_, refresh_ready, _ = odra.ksawery_conflict_assistance_workflow_poll(
			&workflow,
			&coordinator,
			i64(step + 2) * i64(time.Millisecond),
		)
		if refresh_ready do break
		time.sleep(time.Millisecond)
	}
	if !testing.expect(t, refresh_ready) do return .None, false
	evidence := conflict_assistance_process_refresh(fixture)
	completed, completion_failure := odra.ksawery_conflict_assistance_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		3 * i64(time.Second),
	)
	if !testing.expectf(t, completed, "tool completion failed: %v", completion_failure.code) {
		return .None, false
	}
	return workflow.result.operation.outcome, true
}

/* Verifies guidance, editor, fallback, and return remain ordinary Conflict composition. */
@(test)
conflict_assistance_surface_composes_bounded_actions :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	workflow: odra.Ksawery_Conflict_Assistance_Workflow
	evaluation := conflict_assistance_workflow_evaluation(&fixture, .Guidance)
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_compose(&workflow, evaluation))
	presentation, inspected := odra.ksawery_conflict_assistance_workflow_inspect(&workflow)
	testing.expect(t, inspected)
	testing.expect_value(t, presentation.response, ksawery.Conflict_Assistance_Response_Kind.Guidance)
	testing.expect(t, presentation.core_actions_only && presentation.return_available)
	testing.expect(t, !presentation.editor_available && !presentation.tool_available)
	testing.expect_value(t, presentation.guidance.length, evaluation.response.guidance.length)
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_choose(&workflow, .Return))

	evaluation = conflict_assistance_workflow_evaluation(&fixture, .Editor)
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_compose(&workflow, evaluation))
	presentation, inspected = odra.ksawery_conflict_assistance_workflow_inspect(&workflow)
	testing.expect(t, inspected && presentation.editor_available)
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_choose(&workflow, .Open_Editor))

	fallback := odra.Ksawery_Conflict_Assistance_Evaluation {
		provider = ksawery.conflict_assistance_builtin_no_op_provider(),
		selection = ksawery.conflict_assistance_builtin_fallback_selection(1),
		available = true,
		fallback = true,
	}
	fallback.request = {
		request = 83,
		selection_generation = fallback.selection.generation,
		provider = fallback.selection.provider,
		target = fixture.request.target,
	}
	fallback.response = {
		request = fallback.request.request,
		provider = fallback.request.provider,
		target = fallback.request.target,
		kind = .Declined,
	}
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_compose(
		&workflow,
		fallback,
		{code = .Provider_Exception},
	))
	presentation, inspected = odra.ksawery_conflict_assistance_workflow_inspect(&workflow)
	testing.expect(t, inspected && presentation.fallback && presentation.core_actions_only)
	testing.expect_value(t, presentation.failure.code, ksawery.Conflict_Assistance_Failure_Code.Provider_Exception)
}

/* Verifies an admitted tool uses Process and returns only after checked Conflict refresh. */
@(test)
conflict_assistance_surface_tool_returns_to_refreshed_conflict :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	workflow: odra.Ksawery_Conflict_Assistance_Workflow
	evaluation := conflict_assistance_workflow_evaluation(&fixture, .External_Tool)
	if !testing.expect(t, odra.ksawery_conflict_assistance_workflow_compose(&workflow, evaluation)) do return
	coordinator: odra.Ksawery_Process_Coordinator
	coordinator_ready := odra.ksawery_process_coordinator_init(
		&coordinator,
		fixture.request.target.repository,
	)
	if !testing.expect(t, coordinator_ready) do return
	defer odra.ksawery_process_coordinator_close(&coordinator)
	started, failure := odra.ksawery_conflict_assistance_workflow_begin_tool(
		&workflow,
		&coordinator,
		fixture.index,
		fixture.provider.contributor,
		fixture.request.target.repository,
		fixture.request.target.repository_generation,
		1,
	)
	testing.expectf(t, started, "tool start failed: %v", failure.code)
	if !started do return
	presentation, inspected := odra.ksawery_conflict_assistance_workflow_inspect(&workflow)
	testing.expect(t, inspected && !presentation.return_available && !presentation.tool_available)

	refresh_ready := false
	for step in 0 ..< 2_000 {
		_, refresh_ready, _ = odra.ksawery_conflict_assistance_workflow_poll(
			&workflow,
			&coordinator,
			i64(step + 2) * i64(time.Millisecond),
		)
		if refresh_ready do break
		time.sleep(time.Millisecond)
	}
	if !testing.expect(t, refresh_ready) do return
	evidence := conflict_assistance_process_refresh(&fixture)
	completed, completion_failure := odra.ksawery_conflict_assistance_workflow_complete(
		&workflow,
		&coordinator,
		evidence,
		3 * i64(time.Second),
	)
	testing.expectf(t, completed, "tool completion failed: %v", completion_failure.code)
	testing.expect(t, workflow.result_available)
	testing.expect(t, workflow.result.refresh_completed)
	testing.expect(t, workflow.result.index_preserved)
	testing.expect(t, workflow.result.conflict_retained)
	testing.expect(t, odra.ksawery_conflict_assistance_workflow_return(&workflow))
}

/* Verifies nonzero tool exit remains a known failure without taking core actions. */
@(test)
conflict_assistance_surface_contains_tool_failure :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	executable_ready := ksawery.extension_operation_executable_assign_absolute(
		&fixture.tool.operation.executable,
		"tools.false",
		"/usr/bin/false",
	)
	if !testing.expect(t, executable_ready) do return
	fixture.tool.operation.arguments = nil
	outcome, completed := conflict_assistance_workflow_run_tool(t, &fixture)
	testing.expect(t, completed)
	testing.expect_value(t, outcome, ksawery.Repository_Process_Outcome.Known_Failure)
}

/* Verifies Process timeout remains attributable and cleanup releases the child. */
@(test)
conflict_assistance_surface_contains_timeout_and_cleanup :: proc(t: ^testing.T) {
	fixture: Conflict_Assistance_Process_Fixture
	if !testing.expect(t, conflict_assistance_process_fixture_init(&fixture)) do return
	executable_ready := ksawery.extension_operation_executable_assign_absolute(
		&fixture.tool.operation.executable,
		"tools.sleep",
		"/usr/bin/sleep",
	)
	if !testing.expect(t, executable_ready) do return
	assert(ksawery.extension_operation_argument_assign(&fixture.arguments[0], "1"))
	fixture.tool.operation.arguments = fixture.arguments[:1]
	fixture.tool.operation.process_limits.deadline_nanoseconds =
		ksawery.MIN_EXTENSION_OPERATION_DEADLINE_NS
	fixture.tool.operation.process_limits.cancellation_grace_ns = 10 * i64(time.Millisecond)
	outcome, completed := conflict_assistance_workflow_run_tool(t, &fixture)
	testing.expect(t, completed)
	testing.expect_value(
		t,
		outcome,
		ksawery.Repository_Process_Outcome.Timed_Out_After_Possible_Effect,
	)

	workflow: odra.Ksawery_Conflict_Assistance_Workflow
	evaluation := conflict_assistance_workflow_evaluation(&fixture, .External_Tool)
	assert(odra.ksawery_conflict_assistance_workflow_compose(&workflow, evaluation))
	coordinator: odra.Ksawery_Process_Coordinator
	assert(odra.ksawery_process_coordinator_init(&coordinator, fixture.request.target.repository))
	_, _ = odra.ksawery_conflict_assistance_workflow_begin_tool(
		&workflow,
		&coordinator,
		fixture.index,
		fixture.provider.contributor,
		fixture.request.target.repository,
		fixture.request.target.repository_generation,
		1,
	)
	odra.ksawery_conflict_assistance_workflow_close(&workflow)
	testing.expect(t, !workflow.composed)
	testing.expect(t, !workflow.operation.active)
	testing.expect(t, workflow.operation.process.state == nil)
	odra.ksawery_process_coordinator_close(&coordinator)
}
