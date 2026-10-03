// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_operation_coordinator_focused

import odra "../../src/ksawery_module"
import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"
import "core:time"

/* Runs one short fixture command without retaining its output. */
observation_integration_run :: proc(directory: string, command: ..string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	return process_error == nil && state.exited && state.success
}

/* Polls one associated fixture child through the production owner. */
observation_integration_wait :: proc(
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> (ksawery.Repository_Process_Poll, i64) {
	poll: ksawery.Repository_Process_Poll
	current_ns := now_ns
	for _ in 0 ..< 2_000 {
		polled: bool
		poll, polled = ksawery.repository_process_poll(process, current_ns)
		if !polled || poll.state != .Running do return poll, current_ns
		time.sleep(time.Millisecond)
		current_ns += i64(time.Millisecond)
	}
	return poll, current_ns
}

/* Opens one checked Status observation for an integration fixture. */
observation_integration_status :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.Observation_Generation,
	now_ns: i64,
) -> (ksawery.Status_Observation, bool, i64) {
	process, started, _ := ksawery.repository_process_start(
		{kind = .Observe_Status, repository = repository, limits = ksawery.DEFAULT_PROCESS_LIMITS},
		now_ns,
	)
	if !started do return {}, false, now_ns
	defer ksawery.repository_process_close(&process)
	poll, finished_ns := observation_integration_wait(&process, now_ns + 1)
	if poll.state != .Completed do return {}, false, finished_ns
	observation, opened, _ := ksawery.repository_process_take_status(&process, generation)
	return observation, opened, finished_ns
}

/* Selects the first path in one exact Status group. */
observation_integration_selection :: proc(
	observation: ^ksawery.Status_Observation,
	group: ksawery.Change_Group,
) -> (ksawery.Status_Selection, []u8, bool) {
	descriptor, described := ksawery.status_observation_descriptor(observation)
	if !described do return {}, nil, false
	for index in 0 ..< descriptor.path_count {
		path, found := ksawery.status_observation_path(observation, index)
		if !found || path.group != group do continue
		text, available := ksawery.status_observation_path_text(observation, path)
		if !available do return {}, nil, false
		return {
			generation = descriptor.generation,
			current = {kind = .Path, group = group, path = path.id},
		}, text, true
	}
	return {}, nil, false
}

/* Verifies rejection before native start creates no operation record or cleanup ownership. */
@(test)
observation_integration_rejects_before_start_without_record :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-observation-rejected-before-start"))
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	process: ksawery.Repository_Process
	recorded, failure := odra.ksawery_process_observation_begin(
		&coordinator,
		&process,
		1,
		{
			kind = .Status,
			target_kind = .Repository,
			title = "Repository Status",
			target = "/tmp/odra-observation-rejected-before-start",
			phase_detail = "Reading repository status",
		},
		1,
	)
	testing.expect(t, !recorded)
	testing.expect_value(t, failure, ksawery.Failure_Code.Invalid_Request)
	usage, measured := odra.ksawery_process_coordinator_usage(&coordinator)
	testing.expect(t, measured)
	testing.expect_value(t, usage.records, u32(0))
	testing.expect_value(t, usage.active_operations, u8(0))
	testing.expect_value(t, usage.active_children, u8(0))
}

/* Verifies a Status refresh records one associated child and advances confirmed authority. */
@(test)
status_observation_integration_publishes_one_terminal_operation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-ksawery-observation-integration-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer delete(directory)
	defer os.remove_all(directory)
	testing.expect(t, observation_integration_run(directory, "git", "init", "--quiet"))

	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	process, started, start_failure := ksawery.repository_process_start(
		{
			kind = .Observe_Status,
			repository = repository,
			limits = ksawery.DEFAULT_PROCESS_LIMITS,
		},
		1,
	)
	testing.expectf(t, started, "Status child failed to start with %v", start_failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	recorded, record_failure := odra.ksawery_process_observation_begin(
		&coordinator,
		&process,
		1,
		{
			kind = .Status,
			target_kind = .Repository,
			title = "Repository Status",
			target = directory,
			phase_detail = "Refreshing repository status",
			refreshing = true,
		},
		2,
	)
	testing.expectf(t, recorded, "Status operation failed to record with %v", record_failure)
	if !recorded do return
	testing.expect(t, coordinator.active)
	testing.expect(t, coordinator.child_attached)
	testing.expect_value(t, coordinator.record_count, u32(1))
	running, described := ksawery.process_record_descriptor(&coordinator.records[0])
	testing.expect(t, described)
	if described {
		testing.expect_value(t, running.lifecycle, ksawery.Repository_Process_Lifecycle.Running)
		testing.expect_value(t, running.phase, ksawery.Repository_Process_Phase.Refreshing)
		testing.expect_value(t, running.generation, ksawery.Process_Record_Generation(2))
	}

	poll, finished_ns := observation_integration_wait(&process, 3)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	if poll.state != .Completed do return
	observation, opened, observation_failure := ksawery.repository_process_take_status(&process, 2)
	testing.expectf(t, opened, "Status result failed with %v", observation_failure)
	if !opened do return
	defer ksawery.status_observation_close(&observation)
	confirmed, confirm_failure := odra.ksawery_process_observation_confirm_refresh(&coordinator, 2)
	testing.expectf(t, confirmed, "Status authority failed to advance with %v", confirm_failure)
	terminal, terminal_failure := odra.ksawery_process_observation_finish(
		&coordinator,
		&process,
		true,
		"Repository status available",
		finished_ns,
	)
	testing.expectf(t, terminal, "Status terminal record failed with %v", terminal_failure)
	if !terminal do return
	testing.expect(t, !coordinator.active)
	testing.expect(t, !coordinator.child_attached)
	testing.expect_value(t, coordinator.confirmed_observation, ksawery.Observation_Generation(2))
	finished, finished_described := ksawery.process_record_descriptor(&coordinator.records[0])
	testing.expect(t, finished_described)
	if finished_described {
		testing.expect_value(t, finished.lifecycle, ksawery.Repository_Process_Lifecycle.Succeeded)
		testing.expect_value(t, finished.outcome, ksawery.Repository_Process_Outcome.Verified_Success)
		testing.expect_value(t, finished.generation, ksawery.Process_Record_Generation(3))
		testing.expect_value(t, finished.action_count, u8(2))
	}
}

/* Verifies one index mutation keeps its identity across effect, Status refresh, and resolution. */
@(test)
index_mutation_integration_preserves_one_verified_operation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-ksawery-mutation-integration-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer delete(directory)
	defer os.remove_all(directory)
	ready := observation_integration_run(directory, "git", "init", "--quiet") &&
	         observation_integration_run(directory, "git", "config", "user.name", "Odra Test") &&
	         observation_integration_run(directory, "git", "config", "user.email", "odra@example.invalid")
	path, path_error := os.join_path({directory, "change.txt"}, context.allocator)
	testing.expect(t, ready && path_error == nil)
	if !ready || path_error != nil do return
	defer delete(path)
	ready = os.write_entire_file(path, "baseline\n") == nil &&
	        observation_integration_run(directory, "git", "add", "--", "change.txt") &&
	        observation_integration_run(directory, "git", "commit", "--quiet", "-m", "baseline") &&
	        os.write_entire_file(path, "changed\n") == nil
	testing.expect(t, ready)
	if !ready do return

	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	before, observed, observed_ns := observation_integration_status(repository, 1, 1)
	testing.expect(t, observed)
	if !observed do return
	defer ksawery.status_observation_close(&before)
	selection, path_text, selected := observation_integration_selection(&before, .Unstaged)
	testing.expect(t, selected)
	if !selected do return
	request, prepared, prepare_failure := ksawery.index_action_prepare(&before, selection, .Stage, 1)
	testing.expectf(t, prepared, "stage request failed with %v", prepare_failure)
	if !prepared do return
	process, started, start_failure := ksawery.repository_process_start_index_action(
		&before,
		request,
		observed_ns + 1,
	)
	testing.expectf(t, started, "stage child failed with %v", start_failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	recorded, record_failure := odra.ksawery_process_observation_begin(
		&coordinator,
		&process,
		1,
		{
			kind = .Stage,
			target_kind = .Path,
			title = "Stage Repository Path",
			target = string(path_text),
			phase_detail = "Staging repository path",
		},
		observed_ns + 2,
	)
	testing.expectf(t, recorded, "stage operation failed to record with %v", record_failure)
	if !recorded do return
	poll, effect_finished_ns := observation_integration_wait(&process, observed_ns + 3)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	if poll.state != .Completed do return
	result, result_opened, result_failure := ksawery.repository_process_take_index_action(&process)
	testing.expectf(t, result_opened, "stage result failed with %v", result_failure)
	if !result_opened do return
	defer ksawery.index_action_result_close(&result)
	result_descriptor, result_described := ksawery.index_action_result_descriptor(&result)
	testing.expect(t, result_described && result_descriptor.succeeded)
	if !result_described || !result_descriptor.succeeded do return
	effect, refreshing, refresh_failure := odra.ksawery_process_operation_prepare_refresh(
		&coordinator,
		&process,
		"Refreshing repository status",
		effect_finished_ns,
	)
	testing.expectf(t, refreshing, "stage refresh phase failed with %v", refresh_failure)
	if !refreshing do return
	ksawery.repository_process_close(&process)
	refresh_process, refresh_started, refresh_start_failure := ksawery.repository_process_start(
		{kind = .Observe_Status, repository = repository, limits = ksawery.DEFAULT_PROCESS_LIMITS},
		effect_finished_ns + 1,
	)
	testing.expectf(t, refresh_started, "Status refresh failed with %v", refresh_start_failure)
	if !refresh_started do return
	defer ksawery.repository_process_close(&refresh_process)
	attached, attach_failure := odra.ksawery_process_operation_attach_child(
		&coordinator,
		&refresh_process,
		effect_finished_ns + 2,
	)
	testing.expectf(t, attached, "Status refresh association failed with %v", attach_failure)
	if !attached do return
	refresh_poll, refresh_finished_ns := observation_integration_wait(&refresh_process, effect_finished_ns + 3)
	testing.expect_value(t, refresh_poll.state, ksawery.Repository_Process_State.Completed)
	if refresh_poll.state != .Completed do return
	after, after_opened, after_failure := ksawery.repository_process_take_status(&refresh_process, 2)
	testing.expectf(t, after_opened, "refreshed Status failed with %v", after_failure)
	if !after_opened do return
	defer ksawery.status_observation_close(&after)
	confirmed, confirm_failure := odra.ksawery_process_observation_confirm_refresh(&coordinator, 2)
	testing.expectf(t, confirmed, "refreshed authority failed with %v", confirm_failure)
	resolution, resolved, resolve_failure := odra.ksawery_process_operation_resolve(
		&coordinator,
		effect,
		.Verified,
		2,
		true,
	)
	testing.expectf(t, resolved, "stage outcome failed with %v", resolve_failure)
	if !resolved do return
	testing.expect_value(t, resolution.lifecycle, ksawery.Repository_Process_Lifecycle.Succeeded)
	terminal, terminal_failure := odra.ksawery_process_operation_finish_resolution(
		&coordinator,
		&refresh_process,
		resolution,
		"Repository mutation verified",
		refresh_finished_ns,
	)
	testing.expectf(t, terminal, "stage terminal record failed with %v", terminal_failure)
	if terminal {
		finished, described := ksawery.process_record_descriptor(&coordinator.records[0])
		testing.expect(t, described)
		if described {
			testing.expect_value(t, finished.kind, ksawery.Repository_Operation_Kind.Stage)
			testing.expect_value(t, finished.lifecycle, ksawery.Repository_Process_Lifecycle.Succeeded)
			testing.expect_value(t, finished.generation, ksawery.Process_Record_Generation(4))
		}
	}
}

/* Verifies commit checking can wait without a child and cancel before repository effect. */
@(test)
commit_precondition_integration_retains_one_childless_operation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp(
		"",
		"odra-ksawery-commit-precondition-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer delete(directory)
	defer os.remove_all(directory)
	ready := observation_integration_run(directory, "git", "init", "--quiet")
	path, path_error := os.join_path({directory, "commit.txt"}, context.allocator)
	testing.expect(t, ready && path_error == nil)
	if !ready || path_error != nil do return
	defer delete(path)
	ready = os.write_entire_file(path, "staged\n") == nil &&
	        observation_integration_run(directory, "git", "add", "--", "commit.txt")
	testing.expect(t, ready)
	if !ready do return
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	status, observed, observed_ns := observation_integration_status(repository, 1, 1)
	testing.expect(t, observed)
	if !observed do return
	defer ksawery.status_observation_close(&status)
	process, started, start_failure := ksawery.repository_process_start_commit_precondition(
		&status,
		observed_ns + 1,
	)
	testing.expectf(t, started, "commit precondition failed to start with %v", start_failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	coordinator: odra.Ksawery_Process_Coordinator
	testing.expect(t, odra.ksawery_process_coordinator_init(&coordinator, repository))
	defer odra.ksawery_process_coordinator_close(&coordinator)
	recorded, record_failure := odra.ksawery_process_observation_begin(
		&coordinator,
		&process,
		1,
		{
			kind = .Commit,
			target_kind = .Repository,
			title = "Create Repository Commit",
			target = directory,
			phase_detail = "Checking commit preconditions",
			checking = true,
		},
		observed_ns + 2,
	)
	testing.expectf(t, recorded, "commit precondition failed to record with %v", record_failure)
	if !recorded do return
	poll, checked_ns := observation_integration_wait(&process, observed_ns + 3)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	if poll.state != .Completed do return
	precondition, opened, precondition_failure := ksawery.repository_process_take_commit_precondition(&process)
	testing.expectf(t, opened, "commit precondition failed with %v", precondition_failure)
	testing.expect(t, precondition.staged_paths > 0)
	if !opened do return
	detached, detach_failure := odra.ksawery_process_operation_detach_child(&coordinator, &process)
	testing.expectf(t, detached, "commit precondition failed to detach with %v", detach_failure)
	if !detached do return
	ksawery.repository_process_close(&process)
	published, publish_failure := odra.ksawery_process_operation_publish_phase(
		&coordinator,
		nil,
		.Checking,
		"Waiting for commit message",
		false,
		checked_ns,
	)
	testing.expectf(t, published, "commit waiting phase failed with %v", publish_failure)
	if !published do return
	testing.expect(t, coordinator.active)
	testing.expect(t, !coordinator.child_attached)
	testing.expect(t, !coordinator.observation_stale)
	cancelled := odra.ksawery_process_observation_finish_without_child(
		&coordinator,
		.Cancelled,
		.Cancelled_Before_Effect,
		"Commit composition cancelled",
		checked_ns,
	)
	testing.expect(t, cancelled)
	if cancelled {
		finished, described := ksawery.process_record_descriptor(&coordinator.records[0])
		testing.expect(t, described)
		if described {
			testing.expect_value(t, finished.kind, ksawery.Repository_Operation_Kind.Commit)
			testing.expect_value(t, finished.lifecycle, ksawery.Repository_Process_Lifecycle.Cancelled)
			testing.expect_value(t, finished.outcome, ksawery.Repository_Process_Outcome.Cancelled_Before_Effect)
		}
	}
}
