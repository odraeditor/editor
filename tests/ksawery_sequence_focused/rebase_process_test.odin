// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:os"
import "core:testing"
import "core:time"

/* Verifies ordinary and accepted autosquash starts execute as closed noninteractive rebases. */
@(test)
rebase_process_starts_ordinary_and_autosquash_replays :: proc(t: ^testing.T) {
	ordinary_directory, ordinary_repository, ordinary_ready := sequence_process_repository(t)
	if len(ordinary_directory) == 0 do return
	defer {os.remove_all(ordinary_directory); delete(ordinary_directory)}
	ordinary_topic, topic_error := os.join_path({ordinary_directory, "topic.txt"}, context.allocator)
	ordinary_main, main_error := os.join_path({ordinary_directory, "main.txt"}, context.allocator)
	testing.expect(t, ordinary_ready && topic_error == nil && main_error == nil)
	if !ordinary_ready || topic_error != nil || main_error != nil {
		if topic_error == nil do delete(ordinary_topic)
		if main_error == nil do delete(ordinary_main)
		return
	}
	defer delete(ordinary_topic)
	defer delete(ordinary_main)
	ordinary_ready = sequence_process_run(ordinary_directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(ordinary_topic, "topic\n") == nil &&
		sequence_process_run(ordinary_directory, "git", "add", "topic.txt") &&
		sequence_process_run(ordinary_directory, "git", "commit", "-q", "-m", "topic") &&
		os.write_entire_file(ordinary_topic, "topic two\n") == nil &&
		sequence_process_run(ordinary_directory, "git", "commit", "-qam", "topic two") &&
		os.write_entire_file(ordinary_topic, "topic three\n") == nil &&
		sequence_process_run(ordinary_directory, "git", "commit", "-qam", "topic three") &&
		sequence_process_run(ordinary_directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(ordinary_main, "main\n") == nil &&
		sequence_process_run(ordinary_directory, "git", "add", "main.txt") &&
		sequence_process_run(ordinary_directory, "git", "commit", "-q", "-m", "main") &&
		sequence_process_run(ordinary_directory, "git", "checkout", "-q", "topic")
	testing.expect(t, ordinary_ready)
	if !ordinary_ready do return
	ordinary_sequence, ordinary_observed, ordinary_observation_failure :=
		sequence_process_observe(ordinary_repository, 401)
	testing.expectf(t, ordinary_observed, "ordinary pre-rebase observation failed with %v", ordinary_observation_failure)
	if !ordinary_observed do return
	defer ksawery.sequence_observation_close(&ordinary_sequence)
	ordinary, ordinary_prepared := rebase_process_precondition(
		t,
		ordinary_directory,
		ordinary_repository,
		&ordinary_sequence,
		.Start,
		.Ordinary,
	)
	testing.expect(t, ordinary_prepared)
	if !ordinary_prepared do return
	ordinary_request, ordinary_requested := rebase_process_request(t, ordinary, 402)
	if !ordinary_requested do return
	ordinary_process, ordinary_started, ordinary_failure := ksawery.repository_process_start_rebase(
		&ordinary_sequence,
		ordinary,
		ordinary_request,
		1,
	)
	testing.expectf(t, ordinary_started, "ordinary rebase failed to start with %v", ordinary_failure)
	if !ordinary_started do return
	ordinary_poll := sequence_process_wait(&ordinary_process, 2)
	testing.expect_value(t, ordinary_poll.state, ksawery.Repository_Process_State.Completed)
	ordinary_result, ordinary_retained, ordinary_result_failure :=
		ksawery.repository_process_take_rebase(&ordinary_process)
	testing.expectf(t, ordinary_retained, "ordinary result failed with %v", ordinary_result_failure)
	if ordinary_retained do ksawery.rebase_result_close(&ordinary_result)
	ksawery.repository_process_close(&ordinary_process)
	testing.expect_value(
		t,
		rebase_process_revision(t, ordinary_directory, "HEAD~3"),
		rebase_process_revision(t, ordinary_directory, "refs/heads/main"),
	)

	autosquash_directory, autosquash_repository, autosquash_ready := sequence_process_repository(t)
	if len(autosquash_directory) == 0 do return
	defer {os.remove_all(autosquash_directory); delete(autosquash_directory)}
	autosquash_path, autosquash_path_error := os.join_path(
		{autosquash_directory, "topic.txt"},
		context.allocator,
	)
	testing.expect(t, autosquash_ready && autosquash_path_error == nil)
	if !autosquash_ready || autosquash_path_error != nil do return
	defer delete(autosquash_path)
	autosquash_ready = sequence_process_run(autosquash_directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(autosquash_path, "one\n") == nil &&
		sequence_process_run(autosquash_directory, "git", "add", "topic.txt") &&
		sequence_process_run(autosquash_directory, "git", "commit", "-q", "-m", "topic subject") &&
		os.write_entire_file(autosquash_path, "two\n") == nil &&
		sequence_process_run(autosquash_directory, "git", "commit", "-qam", "fixup! topic subject")
	testing.expect(t, autosquash_ready)
	if !autosquash_ready do return
	autosquash_sequence, autosquash_observed, autosquash_observation_failure :=
		sequence_process_observe(autosquash_repository, 411)
	testing.expectf(t, autosquash_observed, "autosquash pre-rebase observation failed with %v", autosquash_observation_failure)
	if !autosquash_observed do return
	defer ksawery.sequence_observation_close(&autosquash_sequence)
	autosquash, autosquash_prepared := rebase_process_precondition(
		t,
		autosquash_directory,
		autosquash_repository,
		&autosquash_sequence,
		.Start,
		.Autosquash,
	)
	testing.expect(t, autosquash_prepared)
	if !autosquash_prepared do return
	autosquash_request, autosquash_requested := rebase_process_request(t, autosquash, 412)
	if !autosquash_requested do return
	autosquash_process, autosquash_started, autosquash_failure :=
		ksawery.repository_process_start_rebase(
			&autosquash_sequence,
			autosquash,
			autosquash_request,
			1,
		)
	testing.expectf(t, autosquash_started, "autosquash rebase failed to start with %v", autosquash_failure)
	if !autosquash_started do return
	autosquash_poll := sequence_process_wait(&autosquash_process, 2)
	testing.expect_value(t, autosquash_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&autosquash_process)
	testing.expect_value(
		t,
		rebase_process_revision(t, autosquash_directory, "HEAD^"),
		rebase_process_revision(t, autosquash_directory, "refs/heads/main"),
	)
}

/* Verifies a conflicted replay remains a started result and Continue uses refreshed exact state. */
@(test)
rebase_process_continues_only_refreshed_resolved_step :: proc(t: ^testing.T) {
	directory, repository, path, ready := rebase_process_conflict_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	defer if len(path) > 0 do delete(path)
	testing.expect(t, ready)
	if !ready do return
	sequence, observed, observation_failure := sequence_process_observe(repository, 421)
	testing.expectf(t, observed, "pre-rebase observation failed with %v", observation_failure)
	if !observed do return
	start, start_ready := rebase_process_precondition(t, directory, repository, &sequence, .Start, .Ordinary)
	testing.expect(t, start_ready)
	if !start_ready {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	request, requested := rebase_process_request(t, start, 422)
	if !requested {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	process, started, start_failure := ksawery.repository_process_start_rebase(&sequence, start, request, 1)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "conflicted rebase failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	result, retained, result_failure := ksawery.repository_process_take_rebase(&process)
	testing.expectf(t, retained, "conflicted rebase result failed with %v", result_failure)
	if retained {
		descriptor, described := ksawery.rebase_result_descriptor(&result)
		testing.expect(t, described && descriptor.started && descriptor.refresh_required && !descriptor.process_succeeded)
		ksawery.rebase_result_close(&result)
	}
	ksawery.repository_process_close(&process)

	conflicted, conflicted_observed, conflicted_failure := sequence_process_observe(repository, 423)
	testing.expectf(t, conflicted_observed, "conflicted observation failed with %v", conflicted_failure)
	if !conflicted_observed do return
	conflicted_descriptor, conflicted_described := ksawery.sequence_observation_descriptor(&conflicted)
	testing.expect(t, conflicted_described && conflicted_descriptor.state == .Conflicted)
	ksawery.sequence_observation_close(&conflicted)
	if !conflicted_described do return
	ready = os.write_entire_file(path, "resolved\n") == nil &&
		sequence_process_run(directory, "git", "add", "conflict.txt")
	testing.expect(t, ready)
	if !ready do return
	resolved, resolved_observed, resolved_failure := sequence_process_observe(repository, 424)
	testing.expectf(t, resolved_observed, "resolved observation failed with %v", resolved_failure)
	if !resolved_observed do return
	defer ksawery.sequence_observation_close(&resolved)
	continued, continue_ready := rebase_process_precondition(
		t,
		directory,
		repository,
		&resolved,
		.Continue,
		.Ordinary,
	)
	testing.expect(t, continue_ready)
	if !continue_ready do return
	continue_request, continue_requested := rebase_process_request(t, continued, 425)
	if !continue_requested do return
	continue_process, continue_started, continue_start_failure := ksawery.repository_process_start_rebase(
		&resolved,
		continued,
		continue_request,
		1,
	)
	testing.expectf(t, continue_started, "continue rebase failed to start with %v", continue_start_failure)
	if !continue_started do return
	continue_poll := sequence_process_wait(&continue_process, 2)
	testing.expect_value(t, continue_poll.state, ksawery.Repository_Process_State.Completed)
	ksawery.repository_process_close(&continue_process)
	rebase_process_expect_inactive(t, repository, 426)
}

/* Verifies Skip and Abort are distinct checked controls over the exact observed replay step. */
@(test)
rebase_process_skips_or_aborts_only_observed_sequence :: proc(t: ^testing.T) {
	actions := [2]ksawery.Rebase_Action{ksawery.Rebase_Action.Skip, ksawery.Rebase_Action.Abort}
	for action in actions {
		directory, repository, path, ready := rebase_process_conflict_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		defer if len(path) > 0 do delete(path)
		if !ready do return
		original := rebase_process_revision(t, directory, "refs/heads/topic")
		sequence, observed, _ := sequence_process_observe(repository, 431)
		if !observed do return
		start, start_ready := rebase_process_precondition(t, directory, repository, &sequence, .Start, .Ordinary)
		if !start_ready {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		request, requested := rebase_process_request(t, start, 432)
		if !requested {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		process, started, _ := ksawery.repository_process_start_rebase(&sequence, start, request, 1)
		ksawery.sequence_observation_close(&sequence)
		if !started do return
		_ = sequence_process_wait(&process, 2)
		ksawery.repository_process_close(&process)
		conflicted, conflicted_observed, _ := sequence_process_observe(repository, 433)
		if !conflicted_observed do return
		control, control_ready := rebase_process_precondition(
			t,
			directory,
			repository,
			&conflicted,
			action,
			.Ordinary,
		)
		testing.expect(t, control_ready)
		if !control_ready {
			ksawery.sequence_observation_close(&conflicted)
			return
		}
		control_request, control_requested := rebase_process_request(t, control, 434)
		if !control_requested {
			ksawery.sequence_observation_close(&conflicted)
			return
		}
		control_process, control_started, control_failure := ksawery.repository_process_start_rebase(
			&conflicted,
			control,
			control_request,
			1,
		)
		ksawery.sequence_observation_close(&conflicted)
		testing.expectf(t, control_started, "rebase control failed to start with %v", control_failure)
		if !control_started do return
		control_poll := sequence_process_wait(&control_process, 2)
		testing.expect_value(t, control_poll.state, ksawery.Repository_Process_State.Completed)
		ksawery.repository_process_close(&control_process)
		rebase_process_expect_inactive(t, repository, 435)
		if action == .Abort {
			testing.expect_value(t, rebase_process_revision(t, directory, "HEAD"), original)
		}
	}
}

/* Verifies pre-rebase hooks, cancellation, and deadlines stop replay without losing bounded cleanup. */
@(test)
rebase_process_contains_hooks_cancellation_and_timeout :: proc(t: ^testing.T) {
	hook_directory, hook_repository, hook_ready := rebase_process_divergent_repository(t)
	if len(hook_directory) == 0 do return
	defer {os.remove_all(hook_directory); delete(hook_directory)}
	testing.expect(t, hook_ready)
	if !hook_ready do return
	hook_sequence, hook_observed, _ := sequence_process_observe(hook_repository, 451)
	if !hook_observed do return
	hook_precondition, hook_prepared := rebase_process_precondition(
		t, hook_directory, hook_repository, &hook_sequence, .Start, .Ordinary,
	)
	if !hook_prepared {
		ksawery.sequence_observation_close(&hook_sequence)
		return
	}
	hook_request, hook_requested := rebase_process_request(t, hook_precondition, 452)
	if !hook_requested {
		ksawery.sequence_observation_close(&hook_sequence)
		return
	}
	hook_path, hook_path_error := os.join_path({hook_directory, ".git", "hooks", "pre-rebase"}, context.allocator)
	testing.expect(t, hook_path_error == nil)
	if hook_path_error != nil do return
	defer delete(hook_path)
	testing.expect(t, os.write_entire_file(hook_path, "#!/bin/sh\nexit 1\n") == nil)
	testing.expect(t, os.chmod(hook_path, {.Read_User, .Write_User, .Execute_User}) == nil)
	original := rebase_process_revision(t, hook_directory, "HEAD")
	hook_process, hook_started, hook_failure := ksawery.repository_process_start_rebase(
		&hook_sequence, hook_precondition, hook_request, 1,
	)
	ksawery.sequence_observation_close(&hook_sequence)
	testing.expectf(t, hook_started, "hooked rebase failed to start with %v", hook_failure)
	if hook_started {
		hook_poll := sequence_process_wait(&hook_process, 2)
		testing.expect(t, hook_poll.state == .Failed && hook_poll.failure == .Process_Failed)
		hook_result, retained, _ := ksawery.repository_process_take_rebase(&hook_process)
		if retained do ksawery.rebase_result_close(&hook_result)
		ksawery.repository_process_close(&hook_process)
		testing.expect_value(t, rebase_process_revision(t, hook_directory, "HEAD"), original)
	}

	for terminate in 0 ..< 2 {
		directory, repository, ready := rebase_process_divergent_repository(t)
		if len(directory) == 0 do return
		defer {os.remove_all(directory); delete(directory)}
		if !ready do return
		sequence, observed, _ := sequence_process_observe(repository, ksawery.Sequence_Generation(460 + terminate))
		if !observed do return
		precondition, prepared := rebase_process_precondition(
			t, directory, repository, &sequence, .Start, .Ordinary,
		)
		if !prepared {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		request, requested := rebase_process_request(t, precondition, u64(460 + terminate))
		if !requested {
			ksawery.sequence_observation_close(&sequence)
			return
		}
		process, started, start_failure := ksawery.repository_process_start_rebase(
			&sequence, precondition, request, 1,
		)
		ksawery.sequence_observation_close(&sequence)
		testing.expectf(t, started, "terminating rebase failed to start with %v", start_failure)
		if !started do return
		if terminate == 0 {
			testing.expect(t, ksawery.repository_process_cancel(&process))
			poll, polled := ksawery.repository_process_poll(&process, 2)
			testing.expect(t, polled && poll.state == .Failed && poll.failure == .Cancelled)
			cancelled, retained, result_failure := ksawery.repository_process_take_rebase(&process)
			testing.expectf(t, retained, "cancelled rebase result failed with %v", result_failure)
			if retained {
				descriptor, described := ksawery.rebase_result_descriptor(&cancelled)
				testing.expect(t, described && descriptor.outcome == .Cancelled_Before_Start)
				ksawery.rebase_result_close(&cancelled)
			}
		} else {
			now := i64(1) + request.limits.timeout_nanoseconds
			poll := rebase_process_wait_from(&process, now)
			testing.expect(t, poll.state == .Failed && poll.failure == .Timeout)
		}
		ksawery.repository_process_close(&process)
	}
}

/* Verifies UI preparation derives one exact confirmable rebase boundary from fresh observations. */
@(test)
rebase_process_prepares_exact_live_confirmation_boundary :: proc(t: ^testing.T) {
	directory, repository, ready := rebase_process_divergent_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	status, status_opened := rebase_process_observe_status(repository, 471)
	if !status_opened do return
	defer ksawery.status_observation_close(&status)
	refs, refs_opened := rebase_process_observe_refs(repository, 472)
	if !refs_opened do return
	defer ksawery.ref_observation_close(&refs)
	sequence, sequence_opened, _ := sequence_process_observe(repository, 473)
	if !sequence_opened do return
	defer ksawery.sequence_observation_close(&sequence)
	base: ksawery.Ref_Identity
	ref_count, counted := ksawery.ref_observation_ref_count(&refs)
	if !counted do return
	for index in 0 ..< ref_count {
		candidate, found := ksawery.ref_observation_ref(&refs, index)
		if found && candidate.kind == .Local_Branch &&
		   ksawery.ref_name_string(&candidate.name) == "refs/heads/main" {
			base = candidate
			break
		}
	}
	testing.expect(t, ksawery.ref_identity_is_valid(base))
	if !ksawery.ref_identity_is_valid(base) do return
	process, started, start_failure := ksawery.repository_process_start_rebase_precondition(
		&status,
		&refs,
		&sequence,
		base,
		.Start,
		.Ordinary,
		{},
		{},
		{},
		{repository_resources = 1},
		1,
	)
	testing.expectf(t, started, "rebase confirmation boundary failed to start with %v", start_failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	precondition, prepared, prepare_failure := ksawery.repository_process_take_rebase_precondition(&process)
	testing.expectf(t, prepared, "rebase confirmation boundary failed with %v", prepare_failure)
	if prepared {
		testing.expect(t, ksawery.rebase_precondition_is_valid(precondition))
		testing.expect_value(t, precondition.status_generation, ksawery.Observation_Generation(471))
		testing.expect_value(t, precondition.ref_generation, ksawery.Ref_Generation(472))
		testing.expect_value(t, precondition.sequence_generation, ksawery.Sequence_Generation(473))
		testing.expect_value(t, precondition.base.reference, base)
		testing.expect_value(t, precondition.base.revision, base.object)
		testing.expect(t, precondition.index_tree.object != {} && precondition.index_fingerprint != {})
	}
}

rebase_process_wait_from :: proc(
	process: ^ksawery.Repository_Process,
	now_ns: i64,
) -> ksawery.Repository_Process_Poll {
	poll: ksawery.Repository_Process_Poll
	current := now_ns
	for _ in 0 ..< 2_000 {
		polled: bool
		poll, polled = ksawery.repository_process_poll(process, current)
		if !polled || poll.state != .Running do return poll
		time.sleep(time.Millisecond)
		current += i64(time.Millisecond)
	}
	return poll
}

rebase_process_divergent_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 || !ready do return directory, repository, false
	topic_path, topic_error := os.join_path({directory, "topic.txt"}, context.allocator)
	main_path, main_error := os.join_path({directory, "main.txt"}, context.allocator)
	if topic_error != nil || main_error != nil {
		if topic_error == nil do delete(topic_path)
		if main_error == nil do delete(main_path)
		return directory, repository, false
	}
	defer delete(topic_path)
	defer delete(main_path)
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(topic_path, "topic\n") == nil &&
		sequence_process_run(directory, "git", "add", "topic.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "topic") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(main_path, "main\n") == nil &&
		sequence_process_run(directory, "git", "add", "main.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "main") &&
		sequence_process_run(directory, "git", "checkout", "-q", "topic")
	return directory, repository, ready
}

rebase_process_observe_status :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.Observation_Generation,
) -> (ksawery.Status_Observation, bool) {
	request := ksawery.Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, _ := ksawery.repository_process_start(request, 1)
	if !started do return {}, false
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	if poll.state != .Completed do return {}, false
	observation, opened, _ := ksawery.repository_process_take_status(&process, generation)
	return observation, opened
}

rebase_process_observe_refs :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.Ref_Generation,
) -> (ksawery.Ref_Observation, bool) {
	process, started, _ := ksawery.repository_process_start_ref_observation(repository, 1)
	if !started do return {}, false
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	if poll.state != .Completed do return {}, false
	observation, opened, _ := ksawery.repository_process_take_refs(&process, generation)
	return observation, opened
}

rebase_process_expect_inactive :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	generation: ksawery.Sequence_Generation,
) {
	observation, observed, failure := sequence_process_observe(repository, generation)
	testing.expectf(t, observed, "post-control observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described && descriptor.kind == .None && descriptor.state == .Inactive)
}

rebase_process_conflict_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, string, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return "", {}, "", false
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	if path_error != nil {
		os.remove_all(directory)
		delete(directory)
		return "", {}, "", false
	}
	ready = ready && sequence_process_run(directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(path, "topic\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "topic") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main") &&
		sequence_process_run(directory, "git", "checkout", "-q", "topic")
	return directory, repository, path, ready
}

rebase_process_precondition :: proc(
	t: ^testing.T,
	directory: string,
	repository: ksawery.Repository_Context,
	observation: ^ksawery.Sequence_Observation,
	action: ksawery.Rebase_Action,
	mode: ksawery.Rebase_Mode,
) -> (ksawery.Rebase_Precondition, bool) {
	descriptor, described := ksawery.sequence_observation_descriptor(observation)
	head := rebase_process_revision(t, directory, "HEAD")
	old_tip := rebase_process_revision(t, directory, "refs/heads/topic")
	base := rebase_process_revision(t, directory, "refs/heads/main")
	index_fingerprint, fingerprint_ready := rebase_process_index_fingerprint(t, directory)
	branch_name, base_name: ksawery.Ref_Name
	ready := described && head != {} && old_tip != {} && base != {} && fingerprint_ready &&
		ksawery.ref_name_assign(&branch_name, "refs/heads/topic") &&
		ksawery.ref_name_assign(&base_name, "refs/heads/main")
	if !ready do return {}, false
	ref_generation := ksawery.Ref_Generation(440)
	branch := ksawery.Ref_Identity {
		repository = repository,
		generation = ref_generation,
		kind = .Local_Branch,
		name = branch_name,
		object = old_tip,
		object_type = .Commit,
	}
	base_ref := ksawery.Ref_Identity {
		repository = repository,
		generation = ref_generation,
		kind = .Local_Branch,
		name = base_name,
		object = base,
		object_type = .Commit,
	}
	precondition := ksawery.Rebase_Precondition {
		repository = repository,
		status_generation = 439,
		ref_generation = ref_generation,
		sequence_generation = descriptor.generation,
		head = {.Detached, {}, head},
		branch = branch,
		old_tip = old_tip,
		base = {reference = base_ref, revision = base},
		index_fingerprint = index_fingerprint,
		repository_operation = .Rebasing,
		sequence_state = descriptor.state,
		sequence = {generation = descriptor.generation, fingerprint = descriptor.fingerprint},
		step = {
			position = descriptor.step.position,
			total = descriptor.step.total,
			action = .Pick,
			revision = descriptor.target,
		},
		worktree_paths = descriptor.observed_conflicts,
		unmerged_paths = descriptor.observed_conflicts,
		action = action,
		mode = mode,
		plan_limits = ksawery.DEFAULT_REBASE_PLAN_LIMITS,
	}
	if action == .Start {
		precondition.head = {.Symbolic, branch, old_tip}
		precondition.repository_operation = .Normal
		precondition.sequence_state = .Inactive
		precondition.sequence = {}
		precondition.step = {}
		precondition.worktree_paths = 0
		precondition.unmerged_paths = 0
	}
	if action == .Start || action == .Continue {
		precondition.index_tree.object = merge_process_write_tree(t, directory)
	}
	if action == .Continue {
		precondition.worktree_paths = 1
		precondition.unmerged_paths = 0
	}
	if mode == .Autosquash {
		_ = ksawery.rebase_plan_fingerprint_compute(
			&precondition.plan.fingerprint,
			transmute([]u8)(string("accepted autosquash plan")),
		)
		precondition.plan.old_tip = old_tip
		precondition.plan.upstream = base
		precondition.plan.steps = 2
		precondition.plan.fixups = 1
		precondition.plan.accepted = true
	}
	return precondition, ksawery.rebase_precondition_is_valid(precondition)
}

rebase_process_request :: proc(
	t: ^testing.T,
	precondition: ksawery.Rebase_Precondition,
	id: u64,
) -> (ksawery.Rebase_Request, bool) {
	confirmation, prepared, failure := ksawery.rebase_confirmation_prepare(
		precondition,
		ksawery.Rebase_Confirmation_ID(id),
	)
	testing.expectf(t, prepared, "rebase confirmation failed with %v", failure)
	if !prepared do return {}, false
	confirmed, confirmation_failure := ksawery.rebase_confirmation_confirm(&confirmation, confirmation.id)
	testing.expectf(t, confirmed, "rebase confirmation was rejected with %v", confirmation_failure)
	if !confirmed do return {}, false
	request, requested, request_failure := ksawery.rebase_request_prepare(
		precondition,
		ksawery.Rebase_Operation_ID(id),
		&confirmation,
	)
	testing.expectf(t, requested, "rebase request failed with %v", request_failure)
	return request, requested
}

rebase_process_revision :: proc(t: ^testing.T, directory, revision: string) -> ksawery.Revision_Identity {
	return merge_process_revision(t, directory, revision)
}

rebase_process_index_fingerprint :: proc(
	t: ^testing.T,
	directory: string,
) -> (ksawery.Rebase_Index_Fingerprint, bool) {
	output, captured := merge_process_capture(directory, "git", "ls-files", "--stage", "-z")
	if !captured do return {}, false
	defer delete(output)
	fingerprint: ksawery.Rebase_Index_Fingerprint
	ready := ksawery.rebase_index_fingerprint_compute(&fingerprint, output)
	testing.expect(t, ready)
	return fingerprint, ready
}
