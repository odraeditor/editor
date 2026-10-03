// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_process_focused

import ksawery "../../src/ksawery"
import "core:fmt"
import "core:os"
import "core:sys/posix"
import "core:testing"
import "core:time"

/* Runs one short fixture command without borrowing process output. */
focused_process_run :: proc(directory: string, command: ..string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	return process_error == nil && state.exited && state.success
}

/* Polls one real child until the native owner reaches a terminal state. */
focused_process_wait :: proc(
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> ksawery.Repository_Process_Poll {
	poll: ksawery.Repository_Process_Poll
	current_ns := now_ns
	for _ in 0 ..< 2_000 {
		polled: bool
		poll, polled = ksawery.repository_process_poll(process, current_ns)
		if !polled || poll.state != .Running do return poll
		time.sleep(time.Millisecond)
		current_ns += i64(time.Millisecond)
	}
	return poll
}

/* Opens one status observation through the production process owner. */
focused_status_observation :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.Observation_Generation,
	limits := ksawery.DEFAULT_PROCESS_LIMITS,
) -> (ksawery.Status_Observation, bool) {
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = limits,
	}
	process, started, _ := ksawery.repository_process_start(request, 1)
	if !started do return {}, false
	defer ksawery.repository_process_close(&process)
	poll := focused_process_wait(&process, 2)
	if poll.state != .Completed do return {}, false
	observation, opened, _ := ksawery.repository_process_take_status(&process, generation)
	return observation, opened
}

/* Selects the first status path in one exact change group. */
focused_status_group_selection :: proc(
	observation: ^ksawery.Status_Observation,
	group: ksawery.Change_Group,
) -> (ksawery.Status_Selection, bool) {
	descriptor, described := ksawery.status_observation_descriptor(observation)
	count, counted := ksawery.status_observation_path_count(observation)
	if !described || !counted do return {}, false
	for index in 0 ..< count {
		path, found := ksawery.status_observation_path(observation, index)
		if found && path.group == group {
			return {
				generation = descriptor.generation,
				current = {kind = .Path, group = group, path = path.id},
			}, true
		}
	}
	return {}, false
}

/* Replaces one regular Git metadata file with a FIFO that blocks the owned Git child. */
focused_block_git_file :: proc(directory: string, relative_path: string) -> (string, string, bool) {
	path, path_error := os.join_path({directory, relative_path}, context.allocator)
	if path_error != nil do return "", "", false
	saved_suffix := ".focused-saved"
	saved_relative := fmt.aprintf("%s%s", relative_path, saved_suffix)
	defer delete(saved_relative)
	saved, saved_error := os.join_path({directory, saved_relative}, context.allocator)
	if saved_error != nil {
		delete(path)
		return "", "", false
	}
	if os.rename(path, saved) != nil || !focused_process_run(directory, "mkfifo", relative_path) {
		_ = os.rename(saved, path)
		delete(path)
		delete(saved)
		return "", "", false
	}
	return path, saved, true
}

/* Restores one Git metadata file after a blocking-child fixture. */
focused_restore_git_file :: proc(path: string, saved: string) -> bool {
	restored := os.remove(path) == nil && os.rename(saved, path) == nil
	delete(path)
	delete(saved)
	return restored
}

/* Makes only the next spawned child inherit ignored SIGTERM disposition. */
focused_ignore_sigterm :: proc() -> (posix.sigaction_t, bool) {
	saved: posix.sigaction_t
	action: posix.sigaction_t
	action.sa_handler = auto_cast posix.SIG_IGN
	posix.sigemptyset(&action.sa_mask)
	return saved, posix.sigaction(posix.Signal(posix.SIGTERM), &action, &saved) == .OK
}

/* Verifies an associated owner exposes monotonic phase, timing, and reaped-child evidence. */
@(test)
associated_repository_process_reports_child_lifecycle :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-process-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	testing.expect(t, focused_process_run(directory, "git", "init", "-q", "-b", "main"))

	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, start_failure := ksawery.repository_process_start(request, 10)
	testing.expectf(t, started, "repository process start failed with %v", start_failure)
	if !started do return
	defer ksawery.repository_process_close(&process)

	authority := ksawery.Process_Record_Authority {
		operation = 41,
		repository = repository,
		observation_generation = 1,
		kind = .Status,
	}
	association := ksawery.Repository_Process_Association {
		authority = authority,
		generation = 2,
	}
	associated, association_failure := ksawery.repository_process_associate(&process, association, 10)
	testing.expectf(t, associated, "repository process association failed with %v", association_failure)
	if !associated do return

	initial, viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, viewed)
	testing.expect_value(t, initial.owner_state, ksawery.Repository_Process_State.Running)
	testing.expect_value(t, initial.phase, ksawery.Repository_Process_Phase.Executing)
	testing.expect_value(t, initial.phase_generation, u32(1))
	testing.expect_value(t, initial.child.state, ksawery.Repository_Child_State.Running)
	testing.expect_value(t, initial.child.children_started, u32(1))

	_, stale_polled := ksawery.repository_process_poll(&process, 9)
	testing.expect(t, !stale_polled)
	preserved, preserved_view := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, preserved_view)
	testing.expect_value(t, preserved.timing.updated_ns, i64(10))

	now_ns := i64(11)
	poll: ksawery.Repository_Process_Poll
	for _ in 0 ..< 2_000 {
		poll, _ = ksawery.repository_process_poll(&process, now_ns)
		if poll.state != .Running do break
		time.sleep(time.Millisecond)
		now_ns += i64(time.Millisecond)
	}
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	terminal, terminal_view := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, terminal_view)
	testing.expect_value(t, terminal.owner_state, ksawery.Repository_Process_State.Completed)
	testing.expect_value(t, terminal.phase, ksawery.Repository_Process_Phase.Executing)
	testing.expect_value(t, terminal.child.state, ksawery.Repository_Child_State.Reaped)
	testing.expect_value(t, terminal.child.children_started, u32(1))
	testing.expect_value(t, terminal.child.children_reaped, u32(1))
	testing.expect(t, terminal.child.exit_status_available)
	testing.expect_value(t, terminal.child.exit_status, i32(0))
	testing.expect(t, terminal.timing.finished_ns >= terminal.timing.started_ns)
	testing.expect_value(t, terminal.timing.updated_ns, terminal.timing.finished_ns)

	advanced, advance_failure := ksawery.repository_process_advance_record_generation(&process, 2, 3)
	testing.expectf(t, advanced, "record generation advance failed with %v", advance_failure)
	advanced, advance_failure = ksawery.repository_process_advance_record_generation(&process, 2, 4)
	testing.expect(t, !advanced)
	testing.expect_value(t, advance_failure, ksawery.Failure_Code.Process_Record_Stale)
	ksawery.repository_process_close(&process)
	_, closed_view := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, !closed_view)
}

/* Verifies a real nonzero Git exit is retained as child evidence, not a repository outcome. */
@(test)
nonzero_repository_child_reports_exit_failure :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-nonrepo-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, start_failure := ksawery.repository_process_start(request, 10)
	testing.expectf(t, started, "non-repository child start failed with %v", start_failure)
	if !started do return
	authority := ksawery.Process_Record_Authority {
		operation = 51,
		repository = repository,
		observation_generation = 1,
		kind = .Status,
	}
	associated, association_failure := ksawery.repository_process_associate(
		&process,
		{authority = authority, generation = 1},
		10,
	)
	testing.expectf(t, associated, "non-repository association failed with %v", association_failure)
	if !associated {
		ksawery.repository_process_close(&process)
		return
	}
	poll := focused_process_wait(&process, 11)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	view, viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, viewed)
	testing.expect_value(t, view.failure_evidence.stage, ksawery.Repository_Process_Failure_Stage.Exit)
	testing.expect_value(t, view.failure_evidence.failure, ksawery.Failure_Code.Process_Failed)
	testing.expect_value(t, view.failure_evidence.effect, ksawery.Repository_Process_Effect_Exposure.Not_Applicable)
	testing.expect(t, view.failure_evidence.exit_status_available)
	testing.expect(t, view.failure_evidence.exit_status != 0)
	testing.expect_value(t, view.child.state, ksawery.Repository_Child_State.Reaped)
	ksawery.repository_process_close(&process)
}

/* Verifies cancellation during commit prechecks remains before any possible repository effect. */
@(test)
checked_cancellation_before_effect_reaps_blocked_child :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-cancel-check-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := focused_process_run(directory, "git", "init", "-q", "-b", "main") &&
	         focused_process_run(directory, "git", "config", "user.name", "Odra Test") &&
	         focused_process_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "staged.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "staged\n") == nil)
	testing.expect(t, focused_process_run(directory, "git", "add", "--", "staged.txt"))
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	observation, observed := focused_status_observation(repository, 61)
	testing.expect(t, observed)
	if !observed do return
	defer ksawery.status_observation_close(&observation)
	blocked, saved, blocked_ok := focused_block_git_file(directory, ".git/HEAD")
	testing.expect(t, blocked_ok)
	if !blocked_ok do return
	process, started, start_failure := ksawery.repository_process_start_commit_precondition(&observation, 10)
	testing.expectf(t, started, "commit precheck start failed with %v", start_failure)
	if !started {
		testing.expect(t, focused_restore_git_file(blocked, saved))
		return
	}
	authority := ksawery.Process_Record_Authority {
		operation = 61,
		repository = repository,
		observation_generation = 61,
		kind = .Commit,
	}
	associated, association_failure := ksawery.repository_process_associate(
		&process,
		{authority = authority, generation = 1},
		10,
	)
	testing.expectf(t, associated, "commit precheck association failed with %v", association_failure)
	stale_cancelled, stale_cancel_failure := ksawery.repository_process_request_cancellation(
		&process,
		{operation = 61, generation = 2, requested_ns = 20},
	)
	testing.expect(t, !stale_cancelled)
	testing.expect_value(t, stale_cancel_failure, ksawery.Failure_Code.Process_Record_Stale)
	cancelled, cancel_failure := ksawery.repository_process_request_cancellation(
		&process,
		{operation = 61, generation = 1, requested_ns = 20},
	)
	testing.expectf(t, cancelled, "commit precheck cancellation failed with %v", cancel_failure)
	repeated, repeated_failure := ksawery.repository_process_request_cancellation(
		&process,
		{operation = 61, generation = 1, requested_ns = 21},
	)
	testing.expect(t, !repeated)
	testing.expect_value(t, repeated_failure, ksawery.Failure_Code.Process_Record_Closed)
	poll := focused_process_wait(&process, 21)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Cancelled)
	view, viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, viewed)
	testing.expect_value(t, view.termination.reason, ksawery.Repository_Process_Termination_Reason.Cancellation)
	testing.expect_value(t, view.termination.phase, ksawery.Repository_Process_Termination_Phase.Reaped)
	testing.expect_value(t, view.failure_evidence.effect, ksawery.Repository_Process_Effect_Exposure.Not_Started)
	testing.expect_value(t, view.child.state, ksawery.Repository_Child_State.Reaped)
	ksawery.repository_process_close(&process)
	testing.expect(t, focused_restore_git_file(blocked, saved))
}

/* Verifies cancellation after a mutation child starts preserves possible-effect evidence. */
@(test)
checked_cancellation_after_possible_effect_reaps_blocked_child :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-cancel-effect-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := focused_process_run(directory, "git", "init", "-q", "-b", "main") &&
	         focused_process_run(directory, "git", "config", "user.name", "Odra Test") &&
	         focused_process_run(directory, "git", "config", "user.email", "odra@example.invalid") &&
	         focused_process_run(directory, "git", "config", "commit.gpgSign", "false")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "changed.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = focused_process_run(directory, "git", "add", "--", "changed.txt") &&
	        focused_process_run(directory, "git", "commit", "-q", "-m", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "changed\n") == nil)
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	observation, observed := focused_status_observation(repository, 71)
	testing.expect(t, observed)
	if !observed do return
	defer ksawery.status_observation_close(&observation)
	selection, selected := focused_status_group_selection(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected do return
	stage, prepared, prepare_failure := ksawery.index_action_prepare(&observation, selection, .Stage, 71)
	testing.expectf(t, prepared, "stage preparation failed with %v", prepare_failure)
	if !prepared do return
	blocked, saved, blocked_ok := focused_block_git_file(directory, ".git/index")
	testing.expect(t, blocked_ok)
	if !blocked_ok do return
	process, started, start_failure := ksawery.repository_process_start_index_action(&observation, stage, 10)
	testing.expectf(t, started, "stage child start failed with %v", start_failure)
	if !started {
		testing.expect(t, focused_restore_git_file(blocked, saved))
		return
	}
	authority := ksawery.Process_Record_Authority {
		operation = 71,
		repository = repository,
		observation_generation = 71,
		kind = .Stage,
	}
	associated, association_failure := ksawery.repository_process_associate(
		&process,
		{authority = authority, generation = 1},
		10,
	)
	testing.expectf(t, associated, "stage association failed with %v", association_failure)
	cancelled, cancel_failure := ksawery.repository_process_request_cancellation(
		&process,
		{operation = 71, generation = 1, requested_ns = 20},
	)
	testing.expectf(t, cancelled, "stage cancellation failed with %v", cancel_failure)
	poll := focused_process_wait(&process, 21)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Cancelled)
	view, viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, viewed)
	testing.expect_value(t, view.failure_evidence.effect, ksawery.Repository_Process_Effect_Exposure.May_Have_Started)
	testing.expect_value(t, view.child.state, ksawery.Repository_Child_State.Reaped)
	ksawery.repository_process_close(&process)
	testing.expect(t, focused_restore_git_file(blocked, saved))
}

/* Verifies a blocked child that ignores SIGTERM times out, escalates once, and is reaped. */
@(test)
repository_process_timeout_escalates_and_reaps :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-timeout-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	testing.expect(t, focused_process_run(directory, "git", "init", "-q", "-b", "main"))
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, directory))
	blocked, saved, blocked_ok := focused_block_git_file(directory, ".git/HEAD")
	testing.expect(t, blocked_ok)
	if !blocked_ok do return
	limits := ksawery.DEFAULT_PROCESS_LIMITS
	limits.timeout_nanoseconds = ksawery.MIN_PROCESS_TIMEOUT_NANOSECONDS
	limits.cancellation_grace_ns = 1
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = limits,
	}
	saved_action, ignored := focused_ignore_sigterm()
	testing.expect(t, ignored)
	if !ignored {
		testing.expect(t, focused_restore_git_file(blocked, saved))
		return
	}
	process, started, start_failure := ksawery.repository_process_start(request, 10)
	restored_signal := posix.sigaction(posix.Signal(posix.SIGTERM), &saved_action, nil) == .OK
	testing.expect(t, restored_signal)
	testing.expectf(t, started, "timeout child start failed with %v", start_failure)
	if !started {
		testing.expect(t, focused_restore_git_file(blocked, saved))
		return
	}
	authority := ksawery.Process_Record_Authority {
		operation = 81,
		repository = repository,
		observation_generation = 1,
		kind = .Status,
	}
	associated, association_failure := ksawery.repository_process_associate(
		&process,
		{authority = authority, generation = 1},
		10,
	)
	testing.expectf(t, associated, "timeout association failed with %v", association_failure)
	deadline_ns := i64(10) + limits.timeout_nanoseconds
	first_poll, first_polled := ksawery.repository_process_poll(&process, deadline_ns)
	testing.expect(t, first_polled)
	testing.expect_value(t, first_poll.state, ksawery.Repository_Process_State.Running)
	grace_view, grace_viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, grace_viewed)
	testing.expect_value(t, grace_view.termination.phase, ksawery.Repository_Process_Termination_Phase.Graceful_Signal)
	_, escalated := ksawery.repository_process_poll(&process, deadline_ns + 2)
	testing.expect(t, escalated)
	forced_view, forced_viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, forced_viewed)
	testing.expect_value(t, forced_view.termination.phase, ksawery.Repository_Process_Termination_Phase.Forced_Signal)
	poll := focused_process_wait(&process, deadline_ns + 3)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Timeout)
	terminal, terminal_viewed := ksawery.repository_process_lifecycle_view(&process)
	testing.expect(t, terminal_viewed)
	testing.expect_value(t, terminal.termination.reason, ksawery.Repository_Process_Termination_Reason.Timeout)
	testing.expect_value(t, terminal.termination.phase, ksawery.Repository_Process_Termination_Phase.Reaped)
	testing.expect(t, terminal.termination.forced_ns != 0)
	testing.expect_value(t, terminal.failure_evidence.stage, ksawery.Repository_Process_Failure_Stage.Timeout)
	testing.expect_value(t, terminal.child.state, ksawery.Repository_Child_State.Reaped)
	ksawery.repository_process_close(&process)
	testing.expect(t, focused_restore_git_file(blocked, saved))
}
