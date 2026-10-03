// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"

/* Verifies fast-forward and merge-commit policies produce their distinct real repository relations. */
@(test)
merge_process_completes_fast_forward_and_merge_commit :: proc(t: ^testing.T) {
	fast_directory, fast_repository, fast_ready := sequence_process_repository(t)
	if len(fast_directory) == 0 do return
	defer {os.remove_all(fast_directory); delete(fast_directory)}
	fast_path, fast_path_error := os.join_path({fast_directory, "side.txt"}, context.allocator)
	testing.expect(t, fast_ready && fast_path_error == nil)
	if !fast_ready || fast_path_error != nil do return
	defer delete(fast_path)
	fast_ready = sequence_process_run(fast_directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(fast_path, "side\n") == nil &&
		sequence_process_run(fast_directory, "git", "add", "side.txt") &&
		sequence_process_run(fast_directory, "git", "commit", "-q", "-m", "side") &&
		sequence_process_run(fast_directory, "git", "checkout", "-q", "main")
	testing.expect(t, fast_ready)
	if !fast_ready do return
	fast_target := merge_process_revision(t, fast_directory, "refs/heads/side")
	fast_start, fast_start_ready := merge_process_start_precondition(
		t,
		fast_directory,
		fast_repository,
		.Fast_Forward_Only,
	)
	testing.expect(t, fast_start_ready)
	if !fast_start_ready do return
	fast_request, fast_requested := merge_process_request(t, fast_start, 181)
	if !fast_requested do return
	fast_process, fast_started, fast_failure := ksawery.repository_process_start_merge(
		fast_start,
		fast_request,
		1,
	)
	testing.expectf(t, fast_started, "fast-forward process failed to start with %v", fast_failure)
	if !fast_started do return
	fast_poll := sequence_process_wait(&fast_process, 2)
	testing.expect_value(t, fast_poll.state, ksawery.Repository_Process_State.Completed)
	fast_result, fast_retained, fast_result_failure := ksawery.repository_process_take_merge(&fast_process)
	testing.expectf(t, fast_retained, "fast-forward result failed with %v", fast_result_failure)
	if fast_retained do ksawery.merge_result_close(&fast_result)
	ksawery.repository_process_close(&fast_process)
	testing.expect_value(t, merge_process_revision(t, fast_directory, "HEAD"), fast_target)

	merge_directory, merge_repository, merge_ready := sequence_process_repository(t)
	if len(merge_directory) == 0 do return
	defer {os.remove_all(merge_directory); delete(merge_directory)}
	side_path, side_path_error := os.join_path({merge_directory, "side.txt"}, context.allocator)
	main_path, main_path_error := os.join_path({merge_directory, "main.txt"}, context.allocator)
	testing.expect(t, merge_ready && side_path_error == nil && main_path_error == nil)
	if !merge_ready || side_path_error != nil || main_path_error != nil {
		if side_path_error == nil do delete(side_path)
		if main_path_error == nil do delete(main_path)
		return
	}
	defer delete(side_path)
	defer delete(main_path)
	merge_ready = sequence_process_run(merge_directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(side_path, "side\n") == nil &&
		sequence_process_run(merge_directory, "git", "add", "side.txt") &&
		sequence_process_run(merge_directory, "git", "commit", "-q", "-m", "side") &&
		sequence_process_run(merge_directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(main_path, "main\n") == nil &&
		sequence_process_run(merge_directory, "git", "add", "main.txt") &&
		sequence_process_run(merge_directory, "git", "commit", "-q", "-m", "main")
	testing.expect(t, merge_ready)
	if !merge_ready do return
	merge_original := merge_process_revision(t, merge_directory, "HEAD")
	merge_target := merge_process_revision(t, merge_directory, "refs/heads/side")
	merge_start, merge_start_ready := merge_process_start_precondition(
		t,
		merge_directory,
		merge_repository,
		.Require_Merge_Commit,
	)
	testing.expect(t, merge_start_ready)
	if !merge_start_ready do return
	merge_request, merge_requested := merge_process_request(t, merge_start, 182)
	if !merge_requested do return
	merge_process, merge_started, merge_failure := ksawery.repository_process_start_merge(
		merge_start,
		merge_request,
		1,
	)
	testing.expectf(t, merge_started, "merge-commit process failed to start with %v", merge_failure)
	if !merge_started do return
	merge_poll := sequence_process_wait(&merge_process, 2)
	testing.expect_value(t, merge_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&merge_process)
	merge_head := merge_process_revision(t, merge_directory, "HEAD")
	testing.expect(t, merge_head != merge_original && merge_head != merge_target)
	testing.expect(t, sequence_process_run(merge_directory, "git", "merge-base", "--is-ancestor", "side", "HEAD"))
	ancestor := ksawery.revision_identity_string(&merge_original)
	testing.expect(t, sequence_process_run(merge_directory, "git", "merge-base", "--is-ancestor", ancestor, "HEAD"))
}

/* Verifies checked merge, whole-path resolution, and Continue run through the bounded process owner. */
@(test)
merge_process_resolves_and_continues_conflict :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(path, "side\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "side") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main")
	testing.expect(t, ready)
	if !ready do return

	start, start_ready := merge_process_start_precondition(t, directory, repository, .Allow_Merge_Commit)
	testing.expect(t, start_ready)
	if !start_ready do return
	start_request, requested := merge_process_request(t, start, 201)
	if !requested do return
	process, started, start_failure := ksawery.repository_process_start_merge(start, start_request, 1)
	testing.expectf(t, started, "merge process failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Process_Failed)
	result, retained, result_failure := ksawery.repository_process_take_merge(&process)
	testing.expectf(t, retained, "merge result failed with %v", result_failure)
	if retained {
		descriptor, described := ksawery.merge_result_descriptor(&result)
		testing.expect(t, described && descriptor.started && descriptor.refresh_required)
		ksawery.merge_result_close(&result)
	}
	ksawery.repository_process_close(&process)

	sequence, observed, observation_failure := sequence_process_observe(repository, 202)
	testing.expectf(t, observed, "conflicted merge observation failed with %v", observation_failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&sequence)
	descriptor, described := ksawery.sequence_observation_descriptor(&sequence)
	testing.expect(t, described && descriptor.kind == .Merge && descriptor.state == .Conflicted)
	if !described do return

	resolved_content := transmute([]u8)(string("resolved\n"))
	testing.expect(t, os.write_entire_file(path, resolved_content) == nil)
	resolution, resolution_ready := merge_process_resolution_precondition(
		t,
		directory,
		repository,
		&sequence,
		resolved_content,
	)
	testing.expect(t, resolution_ready)
	if !resolution_ready do return
	resolution_request, resolution_requested, resolution_request_failure :=
		ksawery.conflict_resolution_request_prepare(
			resolution,
			ksawery.Conflict_Resolution_Operation_ID(203),
		)
	testing.expectf(t, resolution_requested, "resolution request failed with %v", resolution_request_failure)
	if !resolution_requested do return
	resolution_process, resolution_started, resolution_start_failure :=
		ksawery.repository_process_start_conflict_resolution(
			&sequence,
			resolution,
			resolution_request,
			1,
		)
	testing.expectf(t, resolution_started, "resolution process failed to start with %v", resolution_start_failure)
	if !resolution_started do return
	resolution_poll := sequence_process_wait(&resolution_process, 2)
	testing.expect_value(t, resolution_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&resolution_process)

	post_resolution, refreshed, refresh_failure := sequence_process_observe(repository, 204)
	testing.expectf(t, refreshed, "resolved merge observation failed with %v", refresh_failure)
	if !refreshed do return
	defer ksawery.sequence_observation_close(&post_resolution)
	post_descriptor, post_described := ksawery.sequence_observation_descriptor(&post_resolution)
	testing.expect(t, post_described && post_descriptor.kind == .Merge && post_descriptor.state == .Active)
	if !post_described do return

	continued, continue_ready := merge_process_control_precondition(
		t,
		directory,
		repository,
		post_descriptor,
		.Continue,
	)
	testing.expect(t, continue_ready)
	if !continue_ready do return
	continue_request, continue_requested := merge_process_request(t, continued, 205)
	if !continue_requested do return
	continue_process, continue_started, continue_start_failure :=
		ksawery.repository_process_start_merge(continued, continue_request, 1)
	testing.expectf(t, continue_started, "continue process failed to start with %v", continue_start_failure)
	if !continue_started do return
	continue_poll := sequence_process_wait(&continue_process, 2)
	testing.expect_value(t, continue_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&continue_process)
	testing.expect(t, !sequence_process_run(directory, "git", "rev-parse", "--verify", "MERGE_HEAD"))
}

/* Verifies multiple conflict paths remain individually checked across each refreshed resolution. */
@(test)
merge_process_resolves_multiple_conflicts_sequentially :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	first_path, first_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	second_path, second_error := os.join_path({directory, "second.txt"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil)
	if first_error != nil || second_error != nil {
		if first_error == nil do delete(first_path)
		if second_error == nil do delete(second_path)
		return
	}
	defer delete(first_path)
	defer delete(second_path)
	ready = os.write_entire_file(second_path, "base\n") == nil &&
		sequence_process_run(directory, "git", "add", "second.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "second base") &&
		sequence_process_run(directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(first_path, "side first\n") == nil &&
		os.write_entire_file(second_path, "side second\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "side") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(first_path, "main first\n") == nil &&
		os.write_entire_file(second_path, "main second\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main") &&
		!sequence_process_run(directory, "git", "merge", "side")
	testing.expect(t, ready)
	if !ready do return

	for step in 0 ..< 2 {
		sequence, observed, observation_failure := sequence_process_observe(
			repository,
			ksawery.Sequence_Generation(230 + step),
		)
		testing.expectf(t, observed, "multiple-conflict observation failed with %v", observation_failure)
		if !observed do return
		descriptor, described := ksawery.sequence_observation_descriptor(&sequence)
		testing.expect(t, described && descriptor.state == .Conflicted)
		if !described {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		testing.expect_value(t, descriptor.observed_conflicts, u32(2 - step))
		precondition, prepared := merge_process_side_resolution_precondition(
			t,
			directory,
			repository,
			&sequence,
		)
		testing.expect(t, prepared)
		if !prepared {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		confirmation, confirmed_ready, confirmation_failure :=
			ksawery.conflict_resolution_confirmation_prepare(
				precondition,
				ksawery.Conflict_Resolution_Confirmation_ID(240 + step),
			)
		testing.expectf(t, confirmed_ready, "multiple-conflict confirmation failed with %v", confirmation_failure)
		confirmed, confirm_failure := ksawery.conflict_resolution_confirmation_confirm(
			&confirmation,
			confirmation.id,
		)
		testing.expectf(t, confirmed, "multiple-conflict confirmation was rejected with %v", confirm_failure)
		request, requested, request_failure := ksawery.conflict_resolution_request_prepare(
			precondition,
			ksawery.Conflict_Resolution_Operation_ID(240 + step),
			&confirmation,
		)
		testing.expectf(t, requested, "multiple-conflict request failed with %v", request_failure)
		if !requested {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		process, started, start_failure := ksawery.repository_process_start_conflict_resolution(
			&sequence,
			precondition,
			request,
			1,
		)
		testing.expectf(t, started, "multiple-conflict process failed to start with %v", start_failure)
		if started {
			poll := sequence_process_wait(&process, 2)
			testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
			stage_zero, stage_observed, stage_failure :=
				ksawery.repository_process_take_conflict_stage_zero(&process)
			testing.expectf(t, stage_observed, "final stage-zero observation failed with %v", stage_failure)
			if stage_observed {
				testing.expect_value(t, stage_zero.state, ksawery.Conflict_Stage_Zero_State.Present)
				testing.expect_value(t, stage_zero.object, precondition.target.stages[1].object)
			}
			ksawery.repository_process_close(&process)
		}
		ksawery.sequence_observation_close(&sequence)
		if !started do return
	}
	final, refreshed, refresh_failure := sequence_process_observe(repository, 250)
	testing.expectf(t, refreshed, "resolved multiple-conflict observation failed with %v", refresh_failure)
	if refreshed {
		defer ksawery.sequence_observation_close(&final)
		descriptor, described := ksawery.sequence_observation_descriptor(&final)
		testing.expect(t, described && descriptor.state == .Active && descriptor.observed_conflicts == 0)
	}
}

/* Verifies Abort is an explicit checked Git action and does not follow process cancellation. */
@(test)
merge_process_aborts_only_the_confirmed_sequence :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	if path_error != nil do return
	defer delete(path)
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "side") &&
		os.write_entire_file(path, "side\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "side") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main") &&
		!sequence_process_run(directory, "git", "merge", "side")
	testing.expect(t, ready)
	if !ready do return
	original := merge_process_revision(t, directory, "HEAD")
	sequence, observed, _ := sequence_process_observe(repository, 211)
	if !observed do return
	defer ksawery.sequence_observation_close(&sequence)
	descriptor, described := ksawery.sequence_observation_descriptor(&sequence)
	if !described do return
	aborted, abort_ready := merge_process_control_precondition(
		t,
		directory,
		repository,
		descriptor,
		.Abort,
	)
	testing.expect(t, abort_ready)
	if !abort_ready do return
	abort_request, abort_requested := merge_process_request(t, aborted, 212)
	if !abort_requested do return
	abort_process, abort_started, abort_failure := ksawery.repository_process_start_merge(
		aborted,
		abort_request,
		1,
	)
	testing.expectf(t, abort_started, "abort process failed to start with %v", abort_failure)
	if !abort_started do return
	abort_poll := sequence_process_wait(&abort_process, 2)
	testing.expect_value(t, abort_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&abort_process)
	testing.expect_value(t, merge_process_revision(t, directory, "HEAD"), original)
	testing.expect(t, !sequence_process_run(directory, "git", "rev-parse", "--verify", "MERGE_HEAD"))
}

merge_process_start_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	policy: ksawery.Merge_Fast_Forward_Policy,
) -> (ksawery.Merge_Precondition, bool) {
	current := merge_process_revision(t, directory, "HEAD")
	target := merge_process_revision(t, directory, "refs/heads/side")
	index_tree := merge_process_revision(t, directory, "HEAD^{tree}")
	index_fingerprint, fingerprint_ready := merge_process_index_fingerprint(t, directory)
	current_name, source_name: ksawery.Ref_Name
	ready := current != {} && target != {} && index_tree != {} && fingerprint_ready &&
		ksawery.ref_name_assign(&current_name, "refs/heads/main") &&
		ksawery.ref_name_assign(&source_name, "refs/heads/side")
	if !ready do return {}, false
	current_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = 301,
		kind = .Local_Branch,
		name = current_name,
		object = current,
		object_type = .Commit,
	}
	source_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = 301,
		kind = .Local_Branch,
		name = source_name,
		object = target,
		object_type = .Commit,
	}
	message := ksawery.Merge_Message{.Not_Used, {}}
	if policy != .Fast_Forward_Only do message = {.Git_Default, {}}
	precondition := ksawery.Merge_Precondition {
		repository = repository,
		status_generation = 300,
		ref_generation = 301,
		sequence_generation = 302,
		head = {.Symbolic, current_ref, current},
		index_tree = {index_tree},
		index_fingerprint = index_fingerprint,
		repository_operation = .Normal,
		sequence_state = .Inactive,
		action = .Start,
		source = {source_ref, target},
		target_revision = target,
		policy = policy,
		message = message,
	}
	return precondition, ksawery.merge_precondition_is_valid(precondition)
}

merge_process_control_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	sequence: ksawery.Sequence_Observation_Descriptor,
	action: ksawery.Merge_Action,
) -> (ksawery.Merge_Precondition, bool) {
	current := merge_process_revision(t, directory, "HEAD")
	target := merge_process_revision(t, directory, "MERGE_HEAD")
	index_fingerprint, fingerprint_ready := merge_process_index_fingerprint(t, directory)
	current_name: ksawery.Ref_Name
	ready := current != {} && target != {} && fingerprint_ready &&
		ksawery.ref_name_assign(&current_name, "refs/heads/main")
	if !ready do return {}, false
	current_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = 311,
		kind = .Local_Branch,
		name = current_name,
		object = current,
		object_type = .Commit,
	}
	index_tree: ksawery.Index_Tree_Identity
	message := ksawery.Merge_Message{.Not_Used, {}}
	if action == .Continue {
		index_tree.object = merge_process_write_tree(t, directory)
		message = {.Git_Default, {}}
	}
	precondition := ksawery.Merge_Precondition {
		repository = repository,
		status_generation = 310,
		ref_generation = 311,
		sequence_generation = sequence.generation,
		head = {.Symbolic, current_ref, current},
		index_tree = index_tree,
		index_fingerprint = index_fingerprint,
		repository_operation = .Merging,
		sequence_state = sequence.state,
		sequence = {generation = sequence.generation, fingerprint = sequence.fingerprint},
		worktree_paths = sequence.observed_conflicts,
		unmerged_paths = sequence.observed_conflicts,
		action = action,
		target_revision = target,
		message = message,
	}
	if action == .Continue {
		precondition.worktree_paths = 1
		precondition.unmerged_paths = 0
	}
	return precondition, ksawery.merge_precondition_is_valid(precondition)
}

merge_process_resolution_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	observation: ^ksawery.Sequence_Observation,
	content: []u8,
) -> (ksawery.Conflict_Resolution_Precondition, bool) {
	descriptor, described := ksawery.sequence_observation_descriptor(observation)
	target, found := ksawery.sequence_observation_conflict(observation, 0)
	object := merge_process_hash_object(t, directory, "conflict.txt")
	fingerprint: ksawery.Conflict_Content_Fingerprint
	ready := described && found && object != {} &&
		ksawery.conflict_content_fingerprint_compute(&fingerprint, content)
	if !ready do return {}, false
	sequence := ksawery.Sequence_Target{generation = descriptor.generation, fingerprint = descriptor.fingerprint}
	precondition := ksawery.Conflict_Resolution_Precondition {
		repository = repository,
		status_generation = 320,
		sequence_generation = descriptor.generation,
		repository_operation = .Merging,
		sequence_state = descriptor.state,
		sequence = sequence,
		conflict = {sequence = sequence, conflict = target.id},
		target = target,
		worktree = {
			exists = true,
			node = .Regular,
			content = .Text,
			mode = 0o100644,
			git_object = object,
			fingerprint = fingerprint,
		},
		unmerged_paths = descriptor.observed_conflicts,
		action = .Mark_Saved_Result,
	}
	return precondition, ksawery.conflict_resolution_precondition_is_valid(precondition)
}

merge_process_side_resolution_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	observation: ^ksawery.Sequence_Observation,
) -> (ksawery.Conflict_Resolution_Precondition, bool) {
	descriptor, described := ksawery.sequence_observation_descriptor(observation)
	target, found := ksawery.sequence_observation_conflict(observation, 0)
	path, path_found := ksawery.sequence_observation_conflict_path(observation, target)
	worktree_object := merge_process_hash_object(t, directory, path)
	fingerprint: ksawery.Conflict_Content_Fingerprint
	ready := described && found && path_found && worktree_object != {} && target.stages[1].available &&
		ksawery.conflict_content_fingerprint_compute(
			&fingerprint,
			transmute([]u8)(string("checked current side")),
		)
	if !ready do return {}, false
	sequence := ksawery.Sequence_Target{generation = descriptor.generation, fingerprint = descriptor.fingerprint}
	precondition := ksawery.Conflict_Resolution_Precondition {
		repository = repository,
		status_generation = 330,
		sequence_generation = descriptor.generation,
		repository_operation = .Merging,
		sequence_state = descriptor.state,
		sequence = sequence,
		conflict = {sequence = sequence, conflict = target.id},
		target = target,
		worktree = {
			exists = true,
			node = .Regular,
			content = .Text,
			mode = 0o100644,
			git_object = worktree_object,
			fingerprint = fingerprint,
		},
		unmerged_paths = descriptor.observed_conflicts,
		action = .Use_Current,
	}
	return precondition, ksawery.conflict_resolution_precondition_is_valid(precondition)
}

merge_process_request :: proc(
	t: ^testing.T,
	precondition: ksawery.Merge_Precondition,
	id: u64,
) -> (ksawery.Merge_Request, bool) {
	confirmation, prepared, failure := ksawery.merge_confirmation_prepare(
		precondition,
		ksawery.Merge_Confirmation_ID(id),
	)
	testing.expectf(t, prepared, "merge process confirmation failed with %v", failure)
	if !prepared do return {}, false
	confirmed, confirmation_failure := ksawery.merge_confirmation_confirm(&confirmation, confirmation.id)
	testing.expectf(t, confirmed, "merge process confirmation was rejected with %v", confirmation_failure)
	if !confirmed do return {}, false
	request, requested, request_failure := ksawery.merge_request_prepare(
		precondition,
		ksawery.Merge_Operation_ID(id),
		&confirmation,
	)
	testing.expectf(t, requested, "merge process request failed with %v", request_failure)
	return request, requested
}

merge_process_revision :: proc(t: ^testing.T, directory, revision: string) -> ksawery.Revision_Identity {
	output, captured := merge_process_capture(directory, "git", "rev-parse", "--verify", revision)
	if !captured do return {}
	defer delete(output)
	end := len(output)
	for end > 0 && (output[end - 1] == '\n' || output[end - 1] == '\r') {
		end -= 1
	}
	identity: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&identity, string(output[:end])))
	return identity
}

merge_process_write_tree :: proc(t: ^testing.T, directory: string) -> ksawery.Revision_Identity {
	output, captured := merge_process_capture(directory, "git", "write-tree")
	if !captured do return {}
	defer delete(output)
	end := len(output)
	for end > 0 && (output[end - 1] == '\n' || output[end - 1] == '\r') {
		end -= 1
	}
	identity: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&identity, string(output[:end])))
	return identity
}

merge_process_hash_object :: proc(
	t: ^testing.T,
	directory, path: string,
) -> ksawery.Revision_Identity {
	output, captured := merge_process_capture(directory, "git", "hash-object", "--", path)
	if !captured do return {}
	defer delete(output)
	end := len(output)
	for end > 0 && (output[end - 1] == '\n' || output[end - 1] == '\r') {
		end -= 1
	}
	identity: ksawery.Revision_Identity
	testing.expect(t, ksawery.revision_identity_assign(&identity, string(output[:end])))
	return identity
}

merge_process_index_fingerprint :: proc(
	t: ^testing.T,
	directory: string,
) -> (ksawery.Merge_Index_Fingerprint, bool) {
	output, captured := merge_process_capture(directory, "git", "ls-files", "--stage", "-z")
	if !captured do return {}, false
	defer delete(output)
	fingerprint: ksawery.Merge_Index_Fingerprint
	ready := ksawery.merge_index_fingerprint_compute(&fingerprint, output)
	testing.expect(t, ready)
	return fingerprint, ready
}

merge_process_capture :: proc(directory: string, command: ..string) -> ([]u8, bool) {
	state, output, diagnostic, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = command},
		context.allocator,
	)
	delete(diagnostic)
	if process_error != nil || !state.exited || !state.success {
		delete(output)
		return nil, false
	}
	return output, true
}
