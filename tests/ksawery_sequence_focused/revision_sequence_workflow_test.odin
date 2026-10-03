// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"

/* Verifies Continue and Skip resume every remaining exact cherry-pick target in order. */
@(test)
revision_sequence_cherry_pick_controls_resume_remaining_targets :: proc(t: ^testing.T) {
	actions := [2]ksawery.Revision_Sequence_Action {
		ksawery.Revision_Sequence_Action.Continue,
		ksawery.Revision_Sequence_Action.Skip,
	}
	for action in actions {
		directory, repository, path, remaining_path, first, second, ready := revision_sequence_cherry_pick_remaining_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		defer {delete(path); delete(remaining_path)}
		if !ready do return
		targets := [?]ksawery.Revision_Sequence_Target {
			{revision = first, parent_count = 1},
			{revision = second, parent_count = 1},
		}
		set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
		if !opened do return
		defer ksawery.revision_sequence_set_close(&set)
		start, prepared := cherry_pick_process_start_precondition(
			t, directory, repository, &set, "refs/heads/main",
		)
		if !prepared do return
		request, requested := cherry_pick_process_request(t, start, 701)
		if !requested do return
		sequence, observed, _ := sequence_process_observe(repository, 503)
		if !observed do return
		process, started, _ := ksawery.repository_process_start_cherry_pick(
			&sequence, &set, start, request, 1,
		)
		ksawery.sequence_observation_close(&sequence)
		if !started do return
		poll := sequence_process_wait(&process, 2)
		testing.expect(t, poll.state == .Failed && poll.failure == .Process_Failed)
		ksawery.repository_process_close(&process)
		if action == .Continue {
			testing.expect(t, os.write_entire_file(path, "resolved\n") == nil)
			testing.expect(t, sequence_process_run(directory, "git", "add", "conflict.txt"))
		}
		refreshed, refreshed_ok, _ := sequence_process_observe(repository, 504)
		if !refreshed_ok do return
		control, control_ok := cherry_pick_process_control_precondition(
			t, directory, repository, start, &refreshed, action,
		)
		if !control_ok {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_request, control_requested := cherry_pick_process_request(t, control, 702)
		if !control_requested {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_process, control_started, control_failure := ksawery.repository_process_start_cherry_pick(
			&refreshed, &set, control, control_request, 1,
		)
		ksawery.sequence_observation_close(&refreshed)
		testing.expectf(t, control_started, "remaining cherry-pick failed to start with %v", control_failure)
		if !control_started do return
		control_poll := sequence_process_wait(&control_process, 2)
		testing.expect_value(t, control_poll.state, ksawery.Repository_Process_State.Completed)
		ksawery.repository_process_close(&control_process)
		rebase_process_expect_inactive(t, repository, 505)
		testing.expect(t, os.exists(remaining_path))
	}
}

/* Verifies Continue and Skip resume every remaining exact revert target in order. */
@(test)
revision_sequence_revert_controls_resume_remaining_targets :: proc(t: ^testing.T) {
	actions := [2]ksawery.Revision_Sequence_Action {
		ksawery.Revision_Sequence_Action.Continue,
		ksawery.Revision_Sequence_Action.Skip,
	}
	for action in actions {
		directory, repository, path, remaining_path, first, second, ready := revision_sequence_revert_remaining_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		defer {delete(path); delete(remaining_path)}
		if !ready do return
		targets := [?]ksawery.Revision_Sequence_Target {
			{revision = first, parent_count = 1},
			{revision = second, parent_count = 1},
		}
		set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
		if !opened do return
		defer ksawery.revision_sequence_set_close(&set)
		start, prepared := revert_process_start_precondition(
			t, directory, repository, &set, "refs/heads/main",
		)
		if !prepared do return
		request, requested := cherry_pick_process_request(t, start, 711)
		if !requested do return
		sequence, observed, _ := sequence_process_observe(repository, 503)
		if !observed do return
		process, started, _ := ksawery.repository_process_start_revert(
			&sequence, &set, start, request, 1,
		)
		ksawery.sequence_observation_close(&sequence)
		if !started do return
		poll := sequence_process_wait(&process, 2)
		testing.expect(t, poll.state == .Failed && poll.failure == .Process_Failed)
		ksawery.repository_process_close(&process)
		if action == .Continue {
			testing.expect(t, os.write_entire_file(path, "resolved\n") == nil)
			testing.expect(t, sequence_process_run(directory, "git", "add", "conflict.txt"))
		}
		refreshed, refreshed_ok, _ := sequence_process_observe(repository, 504)
		if !refreshed_ok do return
		control, control_ok := revert_process_control_precondition(
			t, directory, repository, start, &refreshed, action,
		)
		if !control_ok {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_request, control_requested := cherry_pick_process_request(t, control, 712)
		if !control_requested {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_process, control_started, control_failure := ksawery.repository_process_start_revert(
			&refreshed, &set, control, control_request, 1,
		)
		ksawery.sequence_observation_close(&refreshed)
		testing.expectf(t, control_started, "remaining revert failed to start with %v", control_failure)
		if !control_started do return
		control_poll := sequence_process_wait(&control_process, 2)
		testing.expect_value(t, control_poll.state, ksawery.Repository_Process_State.Completed)
		ksawery.repository_process_close(&control_process)
		rebase_process_expect_inactive(t, repository, 505)
		testing.expect(t, !os.exists(remaining_path))
	}
}

/* Verifies fresh confirmation preparation rejects dirty starts and changed ordered authority. */
@(test)
revision_sequence_precondition_rejects_dirty_and_reordered_start :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	second_path, path_error := os.join_path({directory, "second.txt"}, context.allocator)
	if path_error != nil do return
	defer delete(second_path)
	first := merge_process_revision(t, directory, "HEAD")
	ready = os.write_entire_file(second_path, "second\n") == nil &&
		sequence_process_run(directory, "git", "add", "second.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "second")
	if !ready do return
	second := merge_process_revision(t, directory, "HEAD")
	targets := [?]ksawery.Revision_Sequence_Target {
		{revision = first, parent_count = 0},
		{revision = second, parent_count = 1},
	}
	set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	status, status_ok := rebase_process_observe_status(repository, 720)
	if !status_ok do return
	defer ksawery.status_observation_close(&status)
	history, history_ok := revision_sequence_observe_history(repository, 721)
	if !history_ok do return
	defer ksawery.history_observation_close(&history)
	refs, refs_ok := rebase_process_observe_refs(repository, 722)
	if !refs_ok do return
	defer ksawery.ref_observation_close(&refs)
	sequence, sequence_ok, _ := sequence_process_observe(repository, 723)
	if !sequence_ok do return
	defer ksawery.sequence_observation_close(&sequence)
	precondition_process, started, start_failure :=
		ksawery.repository_process_start_revision_sequence_precondition(
			&status, &history, &refs, &sequence, &set, .Cherry_Pick, .Start, {},
			{repository_resources = 1}, 1,
		)
	testing.expectf(t, started, "clean sequence precondition failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&precondition_process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	precondition, prepared, prepare_failure :=
		ksawery.repository_process_take_revision_sequence_precondition(&precondition_process)
	testing.expectf(t, prepared, "clean sequence precondition failed with %v", prepare_failure)
	ksawery.repository_process_close(&precondition_process)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 724)
	if !requested do return
	reversed_targets := [?]ksawery.Revision_Sequence_Target{targets[1], targets[0]}
	reversed, reversed_opened, _ := ksawery.revision_sequence_set_open(reversed_targets[:])
	if !reversed_opened do return
	defer ksawery.revision_sequence_set_close(&reversed)
	_, reordered_started, reordered_failure := ksawery.repository_process_start_cherry_pick(
		&sequence, &reversed, precondition, request, 1,
	)
	testing.expect(t, !reordered_started && reordered_failure == .Invalid_Request)
	dirty_path, dirty_error := os.join_path({directory, "dirty.txt"}, context.allocator)
	if dirty_error != nil do return
	defer delete(dirty_path)
	if os.write_entire_file(dirty_path, "dirty\n") != nil do return
	dirty_status, dirty_status_ok := rebase_process_observe_status(repository, 725)
	if !dirty_status_ok do return
	defer ksawery.status_observation_close(&dirty_status)
	dirty_process, dirty_started, dirty_failure :=
		ksawery.repository_process_start_revision_sequence_precondition(
			&dirty_status, &history, &refs, &sequence, &set, .Cherry_Pick, .Start, {},
			{repository_resources = 1}, 1,
		)
	testing.expectf(t, dirty_started, "dirty sequence check failed to start with %v", dirty_failure)
	if dirty_started {
		dirty_poll := sequence_process_wait(&dirty_process, 2)
		testing.expect(t, dirty_poll.state == .Failed && dirty_poll.failure == .Action_Unavailable)
		ksawery.repository_process_close(&dirty_process)
	}
}

/* Verifies external state, hook failure, cancellation, retained uncertainty, and cleanup stay explicit. */
@(test)
revision_sequence_external_failure_and_cleanup_are_bounded :: proc(t: ^testing.T) {
	directory, repository, path, target, ready := cherry_pick_process_conflict_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory); delete(path)}
	if !ready do return
	testing.expect(t, !sequence_process_run(directory, "git", "cherry-pick", ksawery.revision_identity_string(&target)))
	external, observed, _ := sequence_process_observe(repository, 731)
	if !observed do return
	descriptor, described := ksawery.sequence_observation_descriptor(&external)
	testing.expect(t, described && descriptor.origin == .External && descriptor.kind == .Cherry_Pick &&
		descriptor.state == .Conflicted && descriptor.target == target)
	ksawery.sequence_observation_close(&external)
	testing.expect(t, sequence_process_run(directory, "git", "cherry-pick", "--abort"))

	hook_directory, hook_repository, hook_path_target, hook_target, hook_ready :=
		revision_sequence_hook_repository(t)
	if len(hook_directory) == 0 do return
	defer {os.remove_all(hook_directory); delete(hook_directory); delete(hook_path_target)}
	if !hook_ready do return
	hook_path, hook_error := os.join_path({hook_directory, ".git", "hooks", "prepare-commit-msg"}, context.allocator)
	if hook_error != nil do return
	defer delete(hook_path)
	testing.expect(t, os.write_entire_file(hook_path, "#!/bin/sh\nexit 1\n") == nil)
	testing.expect(t, os.chmod(hook_path, {.Read_User, .Write_User, .Execute_User}) == nil)
	targets := [1]ksawery.Revision_Sequence_Target{{revision = hook_target, parent_count = 1}}
	set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	precondition, prepared := cherry_pick_process_start_precondition(
		t, hook_directory, hook_repository, &set, "refs/heads/main",
	)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 732)
	if !requested do return
	indeterminate, indeterminate_opened, indeterminate_failure := ksawery.revision_sequence_result_open(
		request, true, -1, []u8{}, []u8{}, .Timeout,
	)
	testing.expectf(t, indeterminate_opened, "indeterminate result failed to open with %v", indeterminate_failure)
	if indeterminate_opened {
		indeterminate_descriptor, indeterminate_described :=
			ksawery.revision_sequence_result_descriptor(&indeterminate)
		testing.expect(t, indeterminate_described && indeterminate_descriptor.started &&
			indeterminate_descriptor.refresh_required && !indeterminate_descriptor.process_succeeded &&
			indeterminate_descriptor.failure == .Timeout)
		ksawery.revision_sequence_result_close(&indeterminate)
	}
	sequence, sequence_ok, _ := sequence_process_observe(hook_repository, 503)
	if !sequence_ok do return
	process, started, _ := ksawery.repository_process_start_cherry_pick(
		&sequence, &set, precondition, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect(t, poll.state == .Failed && poll.failure == .Process_Failed)
	result, retained, result_failure := ksawery.repository_process_take_cherry_pick(&process)
	testing.expectf(t, retained, "hook failure result was not retained: %v", result_failure)
	if retained {
		result_descriptor, result_ok := ksawery.revision_sequence_result_descriptor(&result)
		testing.expect(t, result_ok && result_descriptor.started && result_descriptor.refresh_required &&
			!result_descriptor.process_succeeded && result_descriptor.failure == .Process_Failed)
		usage, measured := ksawery.revision_sequence_result_usage(&result)
		testing.expect(t, measured && usage.commits == 1)
		ksawery.revision_sequence_result_close(&result)
		testing.expect_value(t, result, ksawery.Revision_Sequence_Result{})
	}
	ksawery.repository_process_close(&process)
	set_usage, measured := ksawery.revision_sequence_set_usage(&set)
	testing.expect(t, measured && set_usage.commits == 1 && set_usage.allocation_bytes > 0)

	cancel_directory, cancel_repository, cancel_path, cancel_target, cancel_ready :=
		cherry_pick_process_conflict_repository(t)
	if len(cancel_directory) == 0 do return
	defer {os.remove_all(cancel_directory); delete(cancel_directory); delete(cancel_path)}
	if !cancel_ready do return
	cancel_targets := [1]ksawery.Revision_Sequence_Target{{revision = cancel_target, parent_count = 1}}
	cancel_set, cancel_opened, _ := ksawery.revision_sequence_set_open(cancel_targets[:])
	if !cancel_opened do return
	defer ksawery.revision_sequence_set_close(&cancel_set)
	cancel_precondition, cancel_prepared := cherry_pick_process_start_precondition(
		t, cancel_directory, cancel_repository, &cancel_set, "refs/heads/main",
	)
	if !cancel_prepared do return
	cancel_request, cancel_requested := cherry_pick_process_request(t, cancel_precondition, 733)
	if !cancel_requested do return
	cancel_sequence, cancel_observed, _ := sequence_process_observe(cancel_repository, 503)
	if !cancel_observed do return
	cancel_process, cancel_started, _ := ksawery.repository_process_start_cherry_pick(
		&cancel_sequence, &cancel_set, cancel_precondition, cancel_request, 1,
	)
	ksawery.sequence_observation_close(&cancel_sequence)
	if !cancel_started do return
	testing.expect(t, ksawery.repository_process_cancel(&cancel_process))
	cancel_poll, polled := ksawery.repository_process_poll(&cancel_process, 2)
	testing.expect(t, polled && cancel_poll.state == .Failed && cancel_poll.failure == .Cancelled)
	cancel_result, cancel_retained, _ := ksawery.repository_process_take_cherry_pick(&cancel_process)
	if cancel_retained {
		cancel_descriptor, cancel_described := ksawery.revision_sequence_result_descriptor(&cancel_result)
		testing.expect(t, cancel_described && !cancel_descriptor.started &&
			cancel_descriptor.outcome == .Cancelled_Before_Start)
		ksawery.revision_sequence_result_close(&cancel_result)
	}
	ksawery.repository_process_close(&cancel_process)
}

revision_sequence_cherry_pick_remaining_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, string, string, ksawery.Revision_Identity, ksawery.Revision_Identity, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return "", {}, "", "", {}, {}, false
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	remaining_path, remaining_error := os.join_path({directory, "remaining.txt"}, context.allocator)
	if path_error != nil || remaining_error != nil do return directory, repository, path, remaining_path, {}, {}, false
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "-b", "source") &&
		os.write_entire_file(path, "source\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "first source")
	first := merge_process_revision(t, directory, "HEAD")
	ready = ready && os.write_entire_file(remaining_path, "remaining\n") == nil &&
		sequence_process_run(directory, "git", "add", "remaining.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "second source")
	second := merge_process_revision(t, directory, "HEAD")
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main conflict")
	return directory, repository, path, remaining_path, first, second, ready
}

revision_sequence_revert_remaining_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, string, string, ksawery.Revision_Identity, ksawery.Revision_Identity, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return "", {}, "", "", {}, {}, false
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	remaining_path, remaining_error := os.join_path({directory, "remaining.txt"}, context.allocator)
	if path_error != nil || remaining_error != nil do return directory, repository, path, remaining_path, {}, {}, false
	ready = ready && os.write_entire_file(path, "selected\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "first selected")
	first := merge_process_revision(t, directory, "HEAD")
	ready = ready && os.write_entire_file(remaining_path, "remaining\n") == nil &&
		sequence_process_run(directory, "git", "add", "remaining.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "second selected")
	second := merge_process_revision(t, directory, "HEAD")
	ready = ready && os.write_entire_file(path, "current\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "current conflict")
	return directory, repository, path, remaining_path, first, second, ready
}

revision_sequence_hook_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, string, ksawery.Revision_Identity, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return "", {}, "", {}, false
	path, path_error := os.join_path({directory, "hook.txt"}, context.allocator)
	if path_error != nil do return directory, repository, "", {}, false
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "-b", "source") &&
		os.write_entire_file(path, "hook\n") == nil &&
		sequence_process_run(directory, "git", "add", "hook.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "hook target")
	target := merge_process_revision(t, directory, "HEAD")
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "main")
	return directory, repository, path, target, ready
}

revision_sequence_observe_history :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.History_Generation,
) -> (ksawery.History_Observation, bool) {
	request := ksawery.Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = ksawery.DEFAULT_HISTORY_LIMITS},
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, _ := ksawery.repository_process_start(request, 1)
	if !started do return {}, false
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	if poll.state != .Completed do return {}, false
	observation, opened, _ := ksawery.repository_process_take_history(&process, generation)
	return observation, opened
}
