// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"

/* Verifies checked cherry-pick applies exact selected commits in retained order. */
@(test)
cherry_pick_process_applies_exact_commits_in_order :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	path, path_error := os.join_path({directory, "ordered.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	base := merge_process_revision(t, directory, "HEAD")
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(path, "first\n") == nil &&
		sequence_process_run(directory, "git", "add", "ordered.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "first selected")
	if !ready do return
	first := merge_process_revision(t, directory, "HEAD")
	ready = os.write_entire_file(path, "first\nsecond\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "second selected")
	if !ready do return
	second := merge_process_revision(t, directory, "HEAD")
	ready = sequence_process_run(directory, "git", "checkout", "-q", "main")
	testing.expect(t, ready)
	if !ready do return
	targets := [?]ksawery.Revision_Sequence_Target {
		{revision = first, parent_count = 1},
		{revision = second, parent_count = 1},
	}
	set, opened, set_failure := ksawery.revision_sequence_set_open(targets[:])
	testing.expectf(t, opened, "ordered cherry-pick set failed with %v", set_failure)
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	precondition, prepared := cherry_pick_process_start_precondition(
		t, directory, repository, &set, "refs/heads/main",
	)
	testing.expect(t, prepared)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 501)
	if !requested do return
	sequence, observed, observation_failure := sequence_process_observe(repository, 503)
	testing.expectf(t, observed, "pre-cherry-pick sequence observation failed with %v", observation_failure)
	if !observed do return
	process, started, start_failure := ksawery.repository_process_start_cherry_pick(
		&sequence, &set, precondition, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "ordered cherry-pick failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	result, retained, result_failure := ksawery.repository_process_take_cherry_pick(&process)
	testing.expectf(t, retained, "ordered cherry-pick result failed with %v", result_failure)
	if retained {
		descriptor, described := ksawery.revision_sequence_result_descriptor(&result)
		testing.expect(t, described && descriptor.started && descriptor.process_succeeded)
		ksawery.revision_sequence_result_close(&result)
	}
	ksawery.repository_process_close(&process)
	testing.expect_value(t, merge_process_revision(t, directory, "HEAD~2"), base)
	contents, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		defer delete(contents)
		testing.expect_value(t, string(contents), "first\nsecond\n")
	}
}

/* Verifies a merge commit is applied only with its checked numbered mainline parent. */
@(test)
cherry_pick_process_applies_checked_merge_mainline :: proc(t: ^testing.T) {
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
	base := merge_process_revision(t, directory, "HEAD")
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
	ready = sequence_process_run(
		directory, "git", "checkout", "-q", "-b", "destination", ksawery.revision_identity_string(&base),
	)
	testing.expect(t, ready)
	if !ready do return
	target := ksawery.Revision_Sequence_Target {
		revision = merge_revision,
		parent_count = 2,
		mainline = {number = 1, parent = mainline_parent},
	}
	set, opened, _ := ksawery.revision_sequence_set_open([]ksawery.Revision_Sequence_Target{target})
	if !opened do return
	defer ksawery.revision_sequence_set_close(&set)
	precondition, prepared := cherry_pick_process_start_precondition(
		t, directory, repository, &set, "refs/heads/destination",
	)
	if !prepared do return
	request, requested := cherry_pick_process_request(t, precondition, 511)
	if !requested do return
	sequence, observed, _ := sequence_process_observe(repository, 503)
	if !observed do return
	process, started, failure := ksawery.repository_process_start_cherry_pick(
		&sequence, &set, precondition, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "merge cherry-pick failed to start with %v", failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&process)
	testing.expect(t, os.exists(side_path))
	testing.expect(t, !os.exists(main_path))
}

/* Verifies Continue, Skip, and Abort act only on the refreshed exact cherry-pick step. */
@(test)
cherry_pick_process_controls_refreshed_conflict :: proc(t: ^testing.T) {
	actions := [3]ksawery.Revision_Sequence_Action {
		ksawery.Revision_Sequence_Action.Continue,
		ksawery.Revision_Sequence_Action.Skip,
		ksawery.Revision_Sequence_Action.Abort,
	}
	for action, action_index in actions {
		directory, repository, path, target, ready := cherry_pick_process_conflict_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		defer if len(path) > 0 do delete(path)
		if !ready do return
		targets := [1]ksawery.Revision_Sequence_Target{{revision = target, parent_count = 1}}
		set, opened, _ := ksawery.revision_sequence_set_open(targets[:])
		if !opened do return
		defer ksawery.revision_sequence_set_close(&set)
		start, start_ready := cherry_pick_process_start_precondition(
			t, directory, repository, &set, "refs/heads/main",
		)
		if !start_ready do return
		original := start.original_head.revision
		request, requested := cherry_pick_process_request(t, start, u64(520 + action_index * 10))
		if !requested do return
		sequence, observed, _ := sequence_process_observe(
			repository, ksawery.Sequence_Generation(503),
		)
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
		refreshed, refreshed_ok, refresh_failure := sequence_process_observe(
			repository, ksawery.Sequence_Generation(504),
		)
		testing.expectf(t, refreshed_ok, "refreshed cherry-pick conflict failed with %v", refresh_failure)
		if !refreshed_ok do return
		control, control_ready := cherry_pick_process_control_precondition(
			t, directory, repository, start, &refreshed, action,
		)
		testing.expectf(
			t,
			control_ready,
			"cherry-pick control %v was invalid with %v state=%v step=%d/%d selected=%d paths=%d/%d",
			action,
			ksawery.revision_sequence_precondition_failure(control),
			control.sequence_state,
			control.step.position,
			control.step.total,
			control.selection.commits,
			control.worktree_paths,
			control.unmerged_paths,
		)
		if !control_ready {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_request, control_requested := cherry_pick_process_request(
			t, control, u64(521 + action_index * 10),
		)
		if !control_requested {
			ksawery.sequence_observation_close(&refreshed)
			return
		}
		control_process, control_started, control_failure := ksawery.repository_process_start_cherry_pick(
			&refreshed, &set, control, control_request, 1,
		)
		ksawery.sequence_observation_close(&refreshed)
		testing.expectf(t, control_started, "cherry-pick control failed to start with %v", control_failure)
		if !control_started do return
		control_poll := sequence_process_wait(&control_process, 2)
		testing.expect_value(t, control_poll.state, ksawery.Repository_Process_State.Completed)
		ksawery.repository_process_close(&control_process)
		rebase_process_expect_inactive(t, repository, ksawery.Sequence_Generation(505))
		if action != .Continue {
			testing.expect_value(t, merge_process_revision(t, directory, "HEAD"), original)
		}
	}
}

cherry_pick_process_conflict_repository :: proc(
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
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "-b", "source") &&
		os.write_entire_file(path, "source\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "source conflict")
	if !ready do return directory, repository, path, {}, false
	target := merge_process_revision(t, directory, "HEAD")
	ready = sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main conflict")
	return directory, repository, path, target, ready
}

cherry_pick_process_control_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	start: ksawery.Revision_Sequence_Precondition,
	sequence: ^ksawery.Sequence_Observation,
	action: ksawery.Revision_Sequence_Action,
) -> (ksawery.Revision_Sequence_Precondition, bool) {
	descriptor, described := ksawery.sequence_observation_descriptor(sequence)
	current := merge_process_revision(t, directory, "HEAD")
	index_output, captured := merge_process_capture(directory, "git", "ls-files", "--stage", "-z")
	if captured do defer delete(index_output)
	index_fingerprint: ksawery.Revision_Sequence_Index_Fingerprint
	ready := described && current != {} && captured &&
		ksawery.revision_sequence_index_fingerprint_compute(&index_fingerprint, index_output)
	if !ready do return {}, false
	precondition := start
	precondition.sequence_generation = descriptor.generation
	precondition.head.object = current
	precondition.head.branch.object = current
	precondition.repository_operation = .Cherry_Picking
	precondition.sequence_kind = .Cherry_Pick
	precondition.sequence_state = descriptor.state
	precondition.sequence = {generation = descriptor.generation, fingerprint = descriptor.fingerprint}
	position := descriptor.step.position
	total := descriptor.step.total
	if descriptor.step == {} {
		position = 1
		total = 1
	}
	precondition.step = {
		position = position,
		total = total,
		target = {revision = descriptor.target, parent_count = 1},
	}
	precondition.index_tree = {}
	precondition.index_fingerprint = index_fingerprint
	precondition.worktree_paths = descriptor.observed_conflicts
	precondition.unmerged_paths = descriptor.observed_conflicts
	precondition.action = action
	precondition.message = {.Not_Used, {}}
	precondition.signing = .Not_Used
	if action == .Continue {
		precondition.index_tree = {merge_process_write_tree(t, directory)}
		precondition.unmerged_paths = 0
		precondition.message = {.Git_Prepared, {}}
		precondition.signing = .Configured
	}
	return precondition, ksawery.revision_sequence_precondition_is_valid(precondition)
}

cherry_pick_process_start_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	set: ^ksawery.Revision_Sequence_Set,
	branch_text: string,
) -> (ksawery.Revision_Sequence_Precondition, bool) {
	selection, selected := ksawery.revision_sequence_set_descriptor(set)
	current := merge_process_revision(t, directory, "HEAD")
	index_tree := merge_process_write_tree(t, directory)
	index_output, captured := merge_process_capture(directory, "git", "ls-files", "--stage", "-z")
	if captured do defer delete(index_output)
	index_fingerprint: ksawery.Revision_Sequence_Index_Fingerprint
	branch_name: ksawery.Ref_Name
	ready := selected && current != {} && index_tree != {} && captured &&
		ksawery.revision_sequence_index_fingerprint_compute(&index_fingerprint, index_output) &&
		ksawery.ref_name_assign(&branch_name, branch_text)
	if !ready do return {}, false
	branch := ksawery.Ref_Identity {
		repository = repository,
		generation = 502,
		kind = .Local_Branch,
		name = branch_name,
		object = current,
		object_type = .Commit,
	}
	precondition := ksawery.Revision_Sequence_Precondition {
		repository = repository,
		status_generation = 500,
		history_generation = 501,
		ref_generation = 502,
		sequence_generation = 503,
		head = {.Symbolic, branch, current},
		original_head = {branch = branch_name, revision = current},
		index_tree = {index_tree},
		index_fingerprint = index_fingerprint,
		repository_operation = .Normal,
		sequence_kind = .None,
		sequence_state = .Inactive,
		editor = {repository_resources = 1},
		family = .Cherry_Pick,
		action = .Start,
		selection = selection,
		message = {.Preserve_Selected, {}},
		signing = .Configured,
	}
	return precondition, ksawery.revision_sequence_precondition_is_valid(precondition)
}

cherry_pick_process_request :: proc(
	t: ^testing.T,
	precondition: ksawery.Revision_Sequence_Precondition,
	id: u64,
) -> (ksawery.Revision_Sequence_Request, bool) {
	confirmation, prepared, failure := ksawery.revision_sequence_confirmation_prepare(
		precondition, ksawery.Revision_Sequence_Confirmation_ID(id),
	)
	testing.expectf(t, prepared, "cherry-pick confirmation failed with %v", failure)
	if !prepared do return {}, false
	confirmed, confirmation_failure := ksawery.revision_sequence_confirmation_confirm(
		&confirmation, confirmation.id,
	)
	testing.expectf(t, confirmed, "cherry-pick confirmation was rejected with %v", confirmation_failure)
	if !confirmed do return {}, false
	request, requested, request_failure := ksawery.revision_sequence_request_prepare(
		precondition, ksawery.Revision_Sequence_Operation_ID(id), &confirmation,
	)
	testing.expectf(t, requested, "cherry-pick request failed with %v", request_failure)
	return request, requested
}
