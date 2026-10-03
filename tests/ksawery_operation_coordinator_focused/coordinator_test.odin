// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_operation_coordinator_focused

import odra "../../src/ksawery_module"
import ksawery "../../src/ksawery"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"
import "core:time"

Coordinator_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

/* Builds one valid repository process proposal for coordinator transitions. */
coordinator_proposal :: proc(
	lifecycle: ksawery.Repository_Process_Lifecycle,
	phase: ksawery.Repository_Process_Phase,
	updated_ns: i64,
) -> ksawery.Process_Record_Proposal {
	proposal := ksawery.Process_Record_Proposal {
		lifecycle = lifecycle,
		phase = phase,
		target_kind = .Remote,
		title = "Fetch origin",
		target = "origin",
		phase_detail = "Repository operation",
		progress = {kind = .Phase},
		timing = {admitted_ns = 10, started_ns = 10, updated_ns = updated_ns, elapsed_ns = updated_ns - 10},
		action_count = 1,
	}
	proposal.actions[0] = {kind = .Inspect, available = true}
	if lifecycle == .Running {
		proposal.actions[1] = {kind = .Cancel, available = true}
		proposal.action_count = 2
	}
	return proposal
}

/* Verifies one stable identity crosses checking, execution, refresh, verification, and retention. */
@(test)
coordinator_advances_one_verified_operation :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-coordinator-focused"))
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	defer odra.ksawery_process_coordinator_close(&coordinator)

	current, current_failure := odra.ksawery_process_coordinator_command_is_current(&coordinator, repository, 1)
	testing.expectf(t, current, "initial command rejected with %v", current_failure)
	authority, admitted, admit_failure := odra.ksawery_process_coordinator_admit(
		&coordinator,
		1,
		.Fetch,
		coordinator_proposal(.Admitted, .Checking, 10),
	)
	testing.expectf(t, admitted, "operation admission failed with %v", admit_failure)
	if !admitted do return
	_, concurrent_failure := odra.ksawery_process_coordinator_command_is_current(&coordinator, repository, 1)
	testing.expect_value(t, concurrent_failure, ksawery.Failure_Code.Action_Unavailable)
	_, repeated, repeated_failure := odra.ksawery_process_coordinator_admit(
		&coordinator,
		1,
		.Fetch,
		coordinator_proposal(.Admitted, .Checking, 10),
	)
	testing.expect(t, !repeated)
	testing.expect_value(t, repeated_failure, ksawery.Failure_Code.Invalid_Request)

	running := coordinator_proposal(.Running, .Checking, 11)
	published, publish_failure := odra.ksawery_process_coordinator_publish(&coordinator, nil, running)
	testing.expectf(t, published, "checking publication failed with %v", publish_failure)
	changed_target := coordinator_proposal(.Running, .Executing, 12)
	changed_target.target = "upstream"
	published, publish_failure = odra.ksawery_process_coordinator_publish(&coordinator, nil, changed_target)
	testing.expect(t, !published)
	testing.expect_value(t, publish_failure, ksawery.Failure_Code.Stale_Observation)

	published, publish_failure = odra.ksawery_process_coordinator_publish(
		&coordinator,
		nil,
		coordinator_proposal(.Running, .Executing, 12),
	)
	testing.expectf(t, published, "execution publication failed with %v", publish_failure)
	published, publish_failure = odra.ksawery_process_coordinator_publish(
		&coordinator,
		nil,
		coordinator_proposal(.Running, .Verifying, 13),
	)
	testing.expect(t, !published)
	testing.expect_value(t, publish_failure, ksawery.Failure_Code.Stale_Observation)
	published, publish_failure = odra.ksawery_process_coordinator_publish(
		&coordinator,
		nil,
		coordinator_proposal(.Running, .Refreshing, 13),
	)
	testing.expectf(t, published, "refresh publication failed with %v", publish_failure)
	refreshed, refresh_failure := odra.ksawery_process_coordinator_confirm_refresh(&coordinator, repository, 2)
	testing.expectf(t, refreshed, "refresh confirmation failed with %v", refresh_failure)
	published, publish_failure = odra.ksawery_process_coordinator_publish(
		&coordinator,
		nil,
		coordinator_proposal(.Running, .Verifying, 15),
	)
	testing.expectf(t, published, "verification publication failed with %v", publish_failure)

	child := ksawery.Repository_Process_Lifecycle_View {
		association = {authority = authority, generation = coordinator.active_generation},
		owner_state = .Completed,
		phase = .Verifying,
		child = {state = .Reaped},
		failure_evidence = {effect = .May_Have_Started},
	}
	verification := odra.Ksawery_Repository_Verification {
		operation = authority.operation,
		repository = repository,
		admitted_generation = 1,
		refreshed_generation = 2,
		state = .Verified,
		refresh_attempted = true,
	}
	resolution, resolved, resolve_failure := odra.ksawery_process_coordinator_resolve_outcome(
		&coordinator,
		child,
		verification,
	)
	testing.expectf(t, resolved, "verified resolution failed with %v", resolve_failure)
	testing.expect_value(t, resolution.lifecycle, ksawery.Repository_Process_Lifecycle.Succeeded)
	testing.expect_value(t, resolution.outcome, ksawery.Repository_Process_Outcome.Verified_Success)
	terminal := coordinator_proposal(.Succeeded, .Verifying, 16)
	terminal.outcome = resolution.outcome
	terminal.message = "Fetch verified"
	terminal.timing.finished_ns = 16
	published, publish_failure = odra.ksawery_process_coordinator_publish(&coordinator, nil, terminal)
	testing.expectf(t, published, "terminal publication failed with %v", publish_failure)
	published, publish_failure = odra.ksawery_process_coordinator_publish(&coordinator, nil, terminal)
	testing.expect(t, !published)
	testing.expect_value(t, publish_failure, ksawery.Failure_Code.Invalid_Request)
	current, current_failure = odra.ksawery_process_coordinator_command_is_current(&coordinator, repository, 2)
	testing.expectf(t, current, "refreshed command rejected with %v", current_failure)
	current, current_failure = odra.ksawery_process_coordinator_command_is_current(&coordinator, repository, 1)
	testing.expect(t, !current)
	testing.expect_value(t, current_failure, ksawery.Failure_Code.Stale_Observation)
	usage, measured := odra.ksawery_process_coordinator_usage(&coordinator)
	testing.expect(t, measured)
	testing.expect_value(t, usage.records, u32(1))
	testing.expect_value(t, usage.active_operations, u8(0))
}

/* Verifies every delivered operation kind retains one identity through immediate completion and cleanup. */
@(test)
coordinator_quick_completion_matrix_retains_every_operation_kind :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-coordinator-operation-matrix"))
	kinds := [20]ksawery.Repository_Operation_Kind {
		.Status,
		.History,
		.Refs,
		.Revision_Detail,
		.Revision_Range,
		.Path_Detail,
		.Stage,
		.Unstage,
		.Discard,
		.Commit,
		.Amend,
		.Fixup,
		.Fetch,
		.Push,
		.Create_Branch,
		.Switch_Branch,
		.Rename_Branch,
		.Delete_Branch,
		.Create_Tag,
		.Delete_Tag,
	}
	for kind in kinds {
		coordinator: odra.Ksawery_Process_Coordinator
		testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
		_, admitted, admit_failure := odra.ksawery_process_coordinator_admit(
			&coordinator,
			1,
			kind,
			coordinator_proposal(.Admitted, .Checking, 10),
		)
		testing.expectf(t, admitted, "%v quick operation failed with %v", kind, admit_failure)
		if admitted {
			running, run_failure := odra.ksawery_process_coordinator_publish(
				&coordinator,
				nil,
				coordinator_proposal(.Running, .Checking, 11),
			)
			testing.expectf(t, running, "%v running publication failed with %v", kind, run_failure)
			finished := odra.ksawery_process_observation_finish_without_child(
				&coordinator,
				.Cancelled,
				.Cancelled_Before_Effect,
				"Repository operation cancelled before effect",
				12,
			)
			testing.expectf(t, finished, "%v quick terminal publication failed", kind)
			if finished {
				descriptor, described := ksawery.process_record_descriptor(&coordinator.records[0])
				testing.expect(t, described)
				if described {
					testing.expect_value(t, descriptor.kind, kind)
					testing.expect_value(t, descriptor.lifecycle, ksawery.Repository_Process_Lifecycle.Cancelled)
					testing.expect_value(t, descriptor.outcome, ksawery.Repository_Process_Outcome.Cancelled_Before_Effect)
					testing.expect_value(t, descriptor.generation, ksawery.Process_Record_Generation(3))
				}
			}
		}
		odra.ksawery_process_coordinator_close(&coordinator)
		testing.expect_value(t, coordinator.record_count, u32(0))
		testing.expect(t, coordinator.allocator.procedure == nil)
	}
}

/* Verifies failure, cancellation, timeout, mismatch, and ambiguous effects stay distinct. */
@(test)
coordinator_resolves_terminal_evidence_without_output_text :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-coordinator-outcomes"))

	for ordinal in 0 ..< 10 {
		coordinator: odra.Ksawery_Process_Coordinator
		testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
		kind := ksawery.Repository_Operation_Kind.Fetch
		if ordinal == 5 || ordinal == 6 || ordinal == 7 do kind = .Status
		authority, admitted, _ := odra.ksawery_process_coordinator_admit(
			&coordinator,
			1,
			kind,
			coordinator_proposal(.Admitted, .Checking, 10),
		)
		testing.expect(t, admitted)
		if !admitted {
			odra.ksawery_process_coordinator_close(&coordinator)
			continue
		}
		child := ksawery.Repository_Process_Lifecycle_View {
			association = {authority = authority, generation = 1},
			owner_state = .Failed,
			child = {state = .Reaped},
			failure = .Process_Failed,
			failure_evidence = {effect = .May_Have_Started},
		}
		verification := odra.Ksawery_Repository_Verification {
			operation = authority.operation,
			repository = repository,
			admitted_generation = 1,
			state = .Unavailable,
			refresh_attempted = true,
		}
		expected_lifecycle := ksawery.Repository_Process_Lifecycle.Indeterminate
		expected_outcome := ksawery.Repository_Process_Outcome.Indeterminate
		switch ordinal {
		case 0:
			child.termination.reason = .Cancellation
			child.failure_evidence.effect = .Not_Started
			expected_lifecycle = .Cancelled
			expected_outcome = .Cancelled_Before_Effect
		case 1:
			child.termination.reason = .Cancellation
			expected_lifecycle = .Cancelled
			expected_outcome = .Cancelled_After_Possible_Effect
		case 2:
			child.termination.reason = .Timeout
			child.failure_evidence.effect = .Not_Started
			expected_lifecycle = .Timed_Out
			expected_outcome = .Timed_Out_Before_Effect
		case 3:
			child.termination.reason = .Timeout
			expected_lifecycle = .Timed_Out
			expected_outcome = .Timed_Out_After_Possible_Effect
		case 4:
			child.child.state = .Uncertain
		case 5:
			child.owner_state = .Completed
			child.failure = .None
			child.failure_evidence.effect = .Not_Applicable
			verification.state = .Mismatch
			verification.refreshed_generation = 1
			verification.refresh_attempted = false
			expected_lifecycle = .Failed
			expected_outcome = .Verification_Mismatch
		case 6:
			child.owner_state = .Completed
			child.failure_evidence.effect = .Not_Applicable
			verification.state = .Known_Failure
			verification.refreshed_generation = 1
			verification.refresh_attempted = false
			expected_lifecycle = .Failed
			expected_outcome = .Known_Failure
		case 7:
			child.failure_evidence.effect = .Not_Started
			verification.state = .Known_Failure
			verification.refreshed_generation = 1
			verification.refresh_attempted = false
			expected_lifecycle = .Failed
			expected_outcome = .Known_Failure
		case 8:
			child.owner_state = .Completed
		case 9:
			child.failure_evidence.stage = .Cleanup
		}
		resolution, resolved, failure := odra.ksawery_process_coordinator_resolve_outcome(
			&coordinator,
			child,
			verification,
		)
		testing.expectf(t, resolved, "terminal case %d failed with %v", ordinal, failure)
		testing.expect_value(t, resolution.lifecycle, expected_lifecycle)
		testing.expect_value(t, resolution.outcome, expected_outcome)
		odra.ksawery_process_coordinator_close(&coordinator)
	}
}

/* Verifies one real native child attaches and detaches only through its exact association. */
@(test)
coordinator_associates_one_real_repository_child :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-coordinator-child-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = []string{"git", "init", "-q", "-b", "main"}},
		context.allocator,
	)
	delete(stdout)
	delete(stderr)
	testing.expect(t, process_error == nil && state.exited && state.success)
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	request := ksawery.Process_Request{kind = .Observe_Status, repository = repository, limits = ksawery.DEFAULT_PROCESS_LIMITS}
	process, started, start_failure := ksawery.repository_process_start(request, 10)
	testing.expectf(t, started, "real child start failed with %v", start_failure)
	if !started do return
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	authority, admitted, _ := odra.ksawery_process_coordinator_admit(
		&coordinator,
		1,
		.Status,
		coordinator_proposal(.Admitted, .Executing, 10),
	)
	testing.expect(t, admitted)
	attached, attach_failure := odra.ksawery_process_coordinator_attach_child(&coordinator, &process, 10)
	testing.expectf(t, attached, "real child association failed with %v", attach_failure)
	attached, _ = odra.ksawery_process_coordinator_attach_child(&coordinator, &process, 10)
	testing.expect(t, !attached)
	now_ns := i64(11)
	for _ in 0 ..< 2_000 {
		poll, polled := ksawery.repository_process_poll(&process, now_ns)
		if !polled || poll.state != .Running do break
		time.sleep(time.Millisecond)
		now_ns += i64(time.Millisecond)
	}
	view, viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, viewed)
	testing.expect_value(t, view.association.authority, authority)
	wrong := view.association
	wrong.generation += 1
	testing.expect(t, !odra.ksawery_process_coordinator_detach_child(&coordinator, wrong))
	testing.expect(t, odra.ksawery_process_coordinator_detach_child(&coordinator, view.association))
	ksawery.repository_process_close(&process)
	odra.ksawery_process_coordinator_close(&coordinator)
}

/* Verifies record allocation failure preserves an empty coordinator and releases all storage. */
@(test)
coordinator_allocation_failure_preserves_empty_state :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-coordinator-allocation"))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Coordinator_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(
		&coordinator,
		repository,
		ksawery.DEFAULT_PROCESS_RECORD_LIMITS,
		coordinator_failing_allocator(&failing),
	))
	_, admitted, failure := odra.ksawery_process_coordinator_admit(
		&coordinator,
		1,
		.Fetch,
		coordinator_proposal(.Admitted, .Checking, 10),
	)
	testing.expect(t, !admitted)
	testing.expect_value(t, failure, ksawery.Failure_Code.Allocation)
	usage, measured := odra.ksawery_process_coordinator_usage(&coordinator)
	testing.expect(t, measured)
	testing.expect_value(t, usage.records, u32(0))
	odra.ksawery_process_coordinator_close(&coordinator)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

coordinator_failing_allocator :: proc(state: ^Coordinator_Failing_Allocator) -> runtime.Allocator {
	return {procedure = coordinator_failing_allocator_proc, data = state}
}

coordinator_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Coordinator_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
