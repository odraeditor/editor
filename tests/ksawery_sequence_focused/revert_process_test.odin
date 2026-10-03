// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"

/* Verifies checked revert inversely applies exact selected commits in retained order. */
@(test)
revert_process_applies_exact_commits_in_order :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	first_path, first_error := os.join_path({directory, "first.txt"}, context.allocator)
	second_path, second_error := os.join_path({directory, "second.txt"}, context.allocator)
	if first_error != nil || second_error != nil {
		if first_error == nil do delete(first_path)
		if second_error == nil do delete(second_path)
		return
	}
	defer delete(first_path)
	defer delete(second_path)
	ready = os.write_entire_file(first_path, "first\n") == nil &&
		sequence_process_run(directory, "git", "add", "first.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "first selected")
	if !ready do return
	first := merge_process_revision(t, directory, "HEAD")
	ready = os.write_entire_file(second_path, "second\n") == nil &&
		sequence_process_run(directory, "git", "add", "second.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "second selected")
	if !ready do return
	second := merge_process_revision(t, directory, "HEAD")
	targets := [?]ksawery.Revision_Sequence_Target {
		{revision = first, parent_count = 1},
		{revision = second, parent_count = 1},
	}
	set, opened, set_failure := ksawery.revision_sequence_set_open(targets[:])
	testing.expectf(t, opened, "ordered revert set failed with %v", set_failure)
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	precondition, prepared := revert_process_start_precondition(
		t, directory, repository, &set, "refs/heads/main",
	)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 601)
	if !requested do return
	sequence, observed, observation_failure := sequence_process_observe(repository, 503)
	testing.expectf(t, observed, "pre-revert sequence observation failed with %v", observation_failure)
	if !observed do return
	process, started, start_failure := ksawery.repository_process_start_revert(
		&sequence, &set, precondition, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "ordered revert failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	result, retained, result_failure := ksawery.repository_process_take_revert(&process)
	testing.expectf(t, retained, "ordered revert result failed with %v", result_failure)
	if retained {
		descriptor, described := ksawery.revision_sequence_result_descriptor(&result)
		testing.expect(t, described && descriptor.started && descriptor.process_succeeded)
		ksawery.revision_sequence_result_close(&result)
	}
	ksawery.repository_process_close(&process)
	testing.expect_value(t, merge_process_revision(t, directory, "HEAD~2"), second)
	testing.expect(t, !os.exists(first_path))
	testing.expect(t, !os.exists(second_path))
	subjects, captured := merge_process_capture(directory, "git", "log", "-2", "--format=%s")
	if captured {
		defer delete(subjects)
		testing.expect_value(t, string(subjects), "Revert \"second selected\"\nRevert \"first selected\"\n")
	}
}

/* Verifies a merge commit is reverted only against its checked numbered mainline parent. */
@(test)
revert_process_applies_checked_merge_mainline :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	side_path, side_error := os.join_path({directory, "side.txt"}, context.allocator)
	main_path, main_error := os.join_path({directory, "mainline.txt"}, context.allocator)
	if side_error != nil || main_error != nil {
		if side_error == nil do delete(side_path)
		if main_error == nil do delete(main_path)
		return
	}
	defer delete(side_path)
	defer delete(main_path)
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(side_path, "side\n") == nil &&
		sequence_process_run(directory, "git", "add", "side.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "side change") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(main_path, "mainline\n") == nil &&
		sequence_process_run(directory, "git", "add", "mainline.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "mainline change") &&
		sequence_process_run(directory, "git", "merge", "-q", "--no-ff", "-m", "merge side", "side")
	if !ready do return
	merge_revision := merge_process_revision(t, directory, "HEAD")
	mainline_parent := merge_process_revision(t, directory, "HEAD^1")
	target := ksawery.Revision_Sequence_Target {
		revision = merge_revision,
		parent_count = 2,
		mainline = {number = 1, parent = mainline_parent},
	}
	set, opened, _ := ksawery.revision_sequence_set_open([]ksawery.Revision_Sequence_Target{target})
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	precondition, prepared := revert_process_start_precondition(
		t, directory, repository, &set, "refs/heads/main",
	)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 611)
	if !requested do return
	sequence, observed, _ := sequence_process_observe(repository, 503)
	if !observed do return
	process, started, failure := ksawery.repository_process_start_revert(
		&sequence, &set, precondition, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "merge revert failed to start with %v", failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&process)
	testing.expect(t, !os.exists(side_path))
	testing.expect(t, os.exists(main_path))
}

/* Verifies Continue, Skip, and Abort act only on the refreshed exact revert step. */
@(test)
revert_process_controls_refreshed_conflict :: proc(t: ^testing.T) {
	actions := [3]ksawery.Revision_Sequence_Action {
		ksawery.Revision_Sequence_Action.Continue,
		ksawery.Revision_Sequence_Action.Skip,
		ksawery.Revision_Sequence_Action.Abort,
	}
	for action, action_index in actions {
		directory, repository, path, target, ready := revert_process_conflict_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		defer if len(path) > 0 do delete(path)
		if !ready do return
		targets := [1]ksawery.Revision_Sequence_Target{{revision = target, parent_count = 1}}
		set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
		if !opened do return
		defer ksawery.revision_sequence_set_close(&set)
		start, start_ready := revert_process_start_precondition(
			t, directory, repository, &set, "refs/heads/main",
		)
		if !start_ready do return
		original := start.original_head.revision
		request, requested := cherry_pick_process_request(t, start, u64(620 + action_index * 10))
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
		refreshed, refreshed_ok, refresh_failure := sequence_process_observe(repository, 504)
		testing.expectf(t, refreshed_ok, "refreshed revert conflict failed with %v", refresh_failure)
		if !refreshed_ok do return
		control, control_ready := revert_process_control_precondition(
			t, directory, repository, start, &refreshed, action,
		)
		testing.expectf(t, control_ready, "revert control %v was invalid", action)
		if !control_ready {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_request, control_requested := cherry_pick_process_request(
			t, control, u64(621 + action_index * 10),
		)
		if !control_requested {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_process, control_started, control_failure := ksawery.repository_process_start_revert(
			&refreshed, &set, control, control_request, 1,
		)
		ksawery.sequence_observation_close(&refreshed)
		testing.expectf(t, control_started, "revert control failed to start with %v", control_failure)
		if !control_started do return
		control_poll := sequence_process_wait(&control_process, 2)
		testing.expect_value(t, control_poll.state, ksawery.Repository_Process_State.Completed)
		ksawery.repository_process_close(&control_process)
		rebase_process_expect_inactive(t, repository, 505)
		if action != .Continue {
			testing.expect_value(t, merge_process_revision(t, directory, "HEAD"), original)
		}
	}
}

revert_process_conflict_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, string, ksawery.Revision_Identity, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return "", {}, "", {}, false
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	if path_error != nil {
		os.remove_all(directory)
		delete(directory)
		return "", {}, "", {}, false
	}
	ready = ready && os.write_entire_file(path, "selected\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "selected conflict")
	if !ready do return directory, repository, path, {}, false
	target := merge_process_revision(t, directory, "HEAD")
	ready = os.write_entire_file(path, "current\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "current conflict")
	return directory, repository, path, target, ready
}

revert_process_start_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	set: ^ksawery.Revision_Sequence_Set,
	branch_text: string,
) -> (ksawery.Revision_Sequence_Precondition, bool) {
	precondition, prepared := cherry_pick_process_start_precondition(
		t, directory, repository, set, branch_text,
	)
	if !prepared do return {}, false
	precondition.family = .Revert
	return precondition, ksawery.revision_sequence_precondition_is_valid(precondition)
}

revert_process_control_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	start: ksawery.Revision_Sequence_Precondition,
	sequence: ^ksawery.Sequence_Observation,
	action: ksawery.Revision_Sequence_Action,
) -> (ksawery.Revision_Sequence_Precondition, bool) {
	precondition, _ := cherry_pick_process_control_precondition(
		t, directory, repository, start, sequence, action,
	)
	precondition.repository_operation = .Reverting
	precondition.sequence_kind = .Revert
	precondition.family = .Revert
	return precondition, ksawery.revision_sequence_precondition_is_valid(precondition)
}
