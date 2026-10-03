// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"
import "core:time"

@(private)
repository_process_test_run :: proc(directory: string, command: ..string) -> bool {
	child, failure := local_child_start(command, directory)
	if failure != .None do return false
	defer local_child_close(&child)
	for _ in 0 ..< 2_000 {
		exited, exit_status, poll_failure := local_child_poll(&child)
		if poll_failure != .None do return false
		if exited do return exit_status == 0
		time.sleep(time.Millisecond)
	}
	return false
}

@(private)
repository_process_test_wait :: proc(process: ^Repository_Process) -> Repository_Process_Poll {
	now := i64(1)
	for _ in 0 ..< 2_000 {
		poll, polled := repository_process_poll(process, now)
		if !polled do return {}
		if poll.state == .Completed || poll.state == .Failed do return poll
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	return {}
}

@(private)
repository_process_test_observe :: proc(
	repository: Repository_Context,
	generation: Observation_Generation,
	allocator := context.allocator,
) -> (Status_Observation, bool) {
	request := Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	process, started, _ := repository_process_start(request, 1, allocator)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	observation, opened, _ := repository_process_take_status(&process, generation, allocator)
	return observation, opened
}

@(private)
repository_process_test_commit_precondition :: proc(
	observation: ^Status_Observation,
	allocator := context.allocator,
) -> (Commit_Precondition, bool) {
	process, started, _ := repository_process_start_commit_precondition(observation, 1, allocator)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	precondition, opened, _ := repository_process_take_commit_precondition(&process)
	return precondition, opened
}

@(private)
repository_process_test_history :: proc(
	repository: Repository_Context,
	generation: History_Generation,
	allocator := context.allocator,
) -> (History_Observation, bool) {
	request := Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = DEFAULT_HISTORY_LIMITS},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	process, started, _ := repository_process_start(request, 1, allocator)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	history, opened, _ := repository_process_take_history(&process, generation, allocator)
	return history, opened
}

@(private)
repository_process_test_refs :: proc(
	repository: Repository_Context,
	generation: Ref_Generation,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	process, started, _ := repository_process_start_ref_observation(repository, 1, allocator)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	refs, opened, _ := repository_process_take_refs(&process, generation, allocator)
	return refs, opened
}

@(private)
repository_process_test_select_remote :: proc(
	observation: ^Ref_Observation,
	wanted: string,
) -> (Ref_Selection, Remote_Identity, bool) {
	descriptor, described := ref_observation_descriptor(observation)
	count, counted := ref_hierarchy_item_count(observation)
	if !described || !counted do return {}, {}, false
	for ordinal in 0 ..< count {
		item, found := ref_hierarchy_item(observation, ordinal)
		if !found || item.kind != .Remote do continue
		remote := item.remote
		if remote_name_string(&remote.name) == wanted {
			return {generation = descriptor.generation, current = item}, remote, true
		}
	}
	return {}, {}, false
}

@(private)
repository_process_test_find_ref :: proc(
	observation: ^Ref_Observation,
	wanted: string,
) -> (Ref_Identity, bool) {
	count, counted := ref_observation_ref_count(observation)
	if !counted do return {}, false
	for ordinal in 0 ..< count {
		reference, found := ref_observation_ref(observation, ordinal)
		if !found do continue
		copy := reference
		if ref_name_string(&copy.name) == wanted do return reference, true
	}
	return {}, false
}

@(private)
repository_process_test_remote_configuration :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	allocator := context.allocator,
) -> (Remote_Configuration_Identity, bool) {
	process, started, _ := repository_process_start_remote_configuration(
		observation,
		selection,
		1,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	configuration, observed, _ := repository_process_take_remote_configuration(&process)
	return configuration, observed
}

@(private)
repository_process_test_push_configuration :: proc(
	observation: ^Ref_Observation,
	selection: Ref_Selection,
	allocator := context.allocator,
) -> (Push_Configuration_Identity, bool) {
	process, started, _ := repository_process_start_push_configuration(
		observation,
		selection,
		1,
		DEFAULT_PROCESS_LIMITS,
		allocator,
	)
	if !started do return {}, false
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false
	configuration, observed, _ := repository_process_take_push_configuration(&process)
	return configuration, observed
}

@(private)
repository_process_test_push_request :: proc(
	observation: ^Ref_Observation,
	configuration: Push_Configuration_Identity,
	operation: Push_Operation_ID,
) -> (Push_Request, bool) {
	source, found := repository_process_test_find_ref(observation, "refs/heads/main")
	if !found do return {}, false
	precondition, prepared, _ := push_precondition_prepare(observation, source, configuration, .Normal)
	if !prepared do return {}, false
	confirmation, confirmation_ready, _ := push_confirmation_prepare(
		precondition,
		Push_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false
	confirmed, _ := push_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, request_ready, _ := push_request_prepare(precondition, operation, &confirmation)
	return request, request_ready
}

@(private)
repository_process_test_branch_request :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	intent: Branch_Intent,
	operation: Branch_Operation_ID,
) -> (Branch_Request, bool, Failure_Code) {
	precondition, prepared, failure := branch_precondition_prepare(status, refs, {}, intent)
	if !prepared do return {}, false, failure
	confirmation, confirmation_ready, confirmation_failure := branch_confirmation_prepare(
		precondition,
		Branch_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false, confirmation_failure
	confirmed, confirm_failure := branch_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false, confirm_failure
	return branch_request_prepare(precondition, operation, &confirmation)
}

@(private)
repository_process_test_tag_request :: proc(
	status: ^Status_Observation,
	refs: ^Ref_Observation,
	intent: Tag_Intent,
	operation: Tag_Operation_ID,
) -> (Tag_Request, bool, Failure_Code) {
	precondition, prepared, failure := tag_precondition_prepare(status, refs, intent)
	if !prepared do return {}, false, failure
	confirmation, confirmation_ready, confirmation_failure := tag_confirmation_prepare(
		precondition,
		Tag_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false, confirmation_failure
	confirmed, confirm_failure := tag_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false, confirm_failure
	return tag_request_prepare(precondition, operation, &confirmation)
}

@(private)
repository_process_test_select_group :: proc(
	observation: ^Status_Observation,
	group: Change_Group,
) -> (Status_Selection, bool) {
	descriptor, available := status_observation_descriptor(observation)
	if !available do return {}, false
	path_count, counted := status_observation_path_count(observation)
	if !counted do return {}, false
	for index in 0 ..< path_count {
		path, found := status_observation_path(observation, index)
		if found && path.group == group {
			return Status_Selection {
				generation = descriptor.generation,
				current = {kind = .Path, group = group, path = path.id},
			}, true
		}
	}
	return {}, false
}

@(private)
repository_process_test_diff_document :: proc(
	observation: ^Status_Observation,
	selection: Status_Selection,
	allocator := context.allocator,
) -> (Path_Detail, Diff_Document, bool) {
	target, targeted, _ := status_selection_path_target(observation, selection)
	if !targeted do return {}, {}, false
	process, started, _ := repository_process_start_path_detail(observation, target, 1, allocator)
	if !started do return {}, {}, false
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed {
		repository_process_close(&process)
		return {}, {}, false
	}
	detail, detailed, _ := repository_process_take_path_detail(&process, observation, allocator)
	repository_process_close(&process)
	if !detailed do return {}, {}, false
	document, parsed, _ := diff_document_open(&detail, DEFAULT_DIFF_LIMITS, allocator)
	if !parsed {
		path_detail_close(&detail)
		return {}, {}, false
	}
	return detail, document, true
}

/* Verifies the process owner observes exact bounded History pages and follows one checked continuation. */
@(test)
repository_process_observes_bounded_history_pages :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-history-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "history.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	for revision in 0 ..< int(MIN_HISTORY_PAGE_REVISIONS) + 1 {
		content := fmt.aprintf("revision-%02d\n", revision)
		written := os.write_entire_file(path, content) == nil
		delete(content)
		committed := written && repository_process_test_run(directory, "git", "add", "history.txt") &&
		             repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "history fixture")
		testing.expect(t, committed)
		if !committed do return
	}
	repository: Repository_Context
	observed := repository_context_assign(&repository, directory)
	testing.expect(t, observed)
	if !observed do return
	limits := DEFAULT_HISTORY_LIMITS
	limits.page_revisions = MIN_HISTORY_PAGE_REVISIONS
	request := Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = limits},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	process, started, start_failure := repository_process_start(request, 1, allocator)
	testing.expectf(t, started, "history start failed with %v", start_failure)
	if !started {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	page, opened, open_failure := repository_process_take_history(&process, History_Generation(1), allocator)
	testing.expectf(t, opened, "history page failed with %v", open_failure)
	if !opened {
		repository_process_close(&process)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	descriptor, described := history_observation_descriptor(&page)
	testing.expect(t, described)
	if !described {
		history_observation_close(&page)
		repository_process_close(&process)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	testing.expect_value(t, descriptor.revision_count, MIN_HISTORY_PAGE_REVISIONS)
	testing.expect(t, history_continuation_is_valid(descriptor.continuation))
	testing.expect_value(t, descriptor.continuation.skipped, MIN_HISTORY_PAGE_REVISIONS)
	first, first_found := history_observation_revision(&page, 0)
	testing.expect(t, first_found)
	if !first_found {
		history_observation_close(&page)
		repository_process_close(&process)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	next_request := request
	next_request.history.continuation = descriptor.continuation
	next_process, next_started, next_failure := repository_process_start(next_request, 1, allocator)
	testing.expectf(t, next_started, "continued history start failed with %v", next_failure)
	if next_started {
		next_poll := repository_process_test_wait(&next_process)
		testing.expect_value(t, next_poll.state, Repository_Process_State.Completed)
		next, next_opened, next_open_failure := repository_process_take_history(
			&next_process,
			History_Generation(2),
			allocator,
		)
		testing.expectf(t, next_opened, "continued history page failed with %v", next_open_failure)
		if next_opened {
			next_descriptor, next_described := history_observation_descriptor(&next)
			testing.expect(t, next_described)
			if next_described {
				testing.expect_value(t, next_descriptor.state, History_State.Available)
				testing.expect_value(t, next_descriptor.revision_count, u32(1))
				testing.expect_value(t, next_descriptor.head, first.identity)
				testing.expect(t, next_descriptor.continuation == {})
			}
			history_observation_close(&next)
		}
		repository_process_close(&next_process)
	}
	history_observation_close(&page)
	repository_process_close(&process)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies the process owner observes exact refs and configured remotes through closed Git commands. */
@(test)
repository_process_observes_bounded_refs_and_remotes :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-refs-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	remote_directory, remote_error := os.join_path({directory, "origin.git"}, context.allocator)
	testing.expect(t, remote_error == nil)
	if remote_error != nil do return
	defer delete(remote_directory)
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main") &&
		repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
		repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid") &&
		repository_process_test_run(directory, "git", "init", "--bare", "-q", remote_directory)
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "refs.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	written := os.write_entire_file(path, "refs\n") == nil
	committed := written && repository_process_test_run(directory, "git", "add", "refs.txt") &&
		repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "refs fixture") &&
		repository_process_test_run(directory, "git", "branch", "topic") &&
		repository_process_test_run(directory, "git", "tag", "v0.1.0") &&
		repository_process_test_run(directory, "git", "remote", "add", "origin", remote_directory) &&
		repository_process_test_run(directory, "git", "push", "-q", "-u", "origin", "main") &&
		repository_process_test_run(directory, "git", "fetch", "-q", "origin")
	testing.expect(t, committed)
	if !committed do return
	repository: Repository_Context
	observed := repository_context_assign(&repository, directory)
	testing.expect(t, observed)
	if !observed do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	refs, opened := repository_process_test_refs(repository, Ref_Generation(1), allocator)
	testing.expect(t, opened)
	if opened {
		descriptor, described := ref_observation_descriptor(&refs)
		testing.expect(t, described)
		if described {
			testing.expect_value(t, descriptor.head.state, Head_State.Symbolic)
			testing.expect(t, descriptor.local_branch_count >= 2)
			testing.expect(t, descriptor.remote_tracking_count >= 1)
			testing.expect_value(t, descriptor.tag_count, u32(1))
			testing.expect_value(t, descriptor.remote_count, u32(1))
		}
		ref_observation_close(&refs)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies the bounded repository runner observes status and releases its owner state. */
@(test)
repository_process_observes_current_repository_with_bounded_cleanup :: proc(t: ^testing.T) {
	directory, directory_error := os.getwd(context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer delete(directory)

	repository: Repository_Context
	ready := repository_context_assign(&repository, directory)
	testing.expect(t, ready)
	if !ready do return

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request := Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	process, started, failure := repository_process_start(request, 1, allocator)
	testing.expectf(t, started, "repository status start failed with %v", failure)
	if !started {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	completed := false
	now := i64(1)
	for _ in 0 ..< 2_000 {
		poll, polled := repository_process_poll(&process, now)
		testing.expect(t, polled)
		if poll.state == .Completed {
			completed = true
			break
		}
		if poll.state == .Failed do break
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	testing.expect(t, completed)
	if completed {
		output, available := repository_process_output(&process)
		testing.expect(t, available)
		testing.expect(t, len(output) <= int(DEFAULT_PROCESS_LIMITS.stdout_bytes))
		usage, usage_ok := repository_process_usage(&process)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.output_bytes, u64(len(output)))
		testing.expect(t, usage.diagnostic_bytes <= DEFAULT_PROCESS_LIMITS.diagnostic_bytes)
		observation, opened, observation_failure := repository_process_take_status(
			&process,
			Observation_Generation(1),
			allocator,
		)
		testing.expectf(t, opened, "status observation parse failed with %v", observation_failure)
		if opened {
			descriptor, described := status_observation_descriptor(&observation)
			testing.expect(t, described)
			testing.expect_value(t, descriptor.generation, Observation_Generation(1))
			status_observation_close(&observation)
		}
	}
	repository_process_close(&process)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies real Git detail becomes bounded semantic hunks with exact cleanup. */
@(test)
repository_process_parses_real_semantic_diff_units :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-diff-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	baseline := "line 01\nline 02\nline 03\nline 04\nline 05\nline 06\nline 07\nline 08\nline 09\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\n"
	changed := "line 01\nchanged 02\nline 03\nline 04\nline 05\nline 06\nline 07\nline 08\nline 09\nline 10\nline 11\nline 12\nline 13\nline 14\nchanged 15\nline 16\n"
	testing.expect(t, os.write_entire_file(path, baseline) == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, changed) == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(
		repository,
		Observation_Generation(60),
		allocator,
	)
	testing.expect(t, observed)
	if !observed {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	selection, selected := repository_process_test_select_group(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected {
		status_observation_close(&observation)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	target, targeted, _ := status_selection_path_target(&observation, selection)
	testing.expect(t, targeted)
	process, started, start_failure := repository_process_start_path_detail(
		&observation,
		target,
		1,
		allocator,
	)
	testing.expectf(t, started, "real diff process failed with %v", start_failure)
	if !started {
		status_observation_close(&observation)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	detail, detailed, detail_failure := repository_process_take_path_detail(
		&process,
		&observation,
		allocator,
	)
	testing.expectf(t, detailed, "real path detail failed with %v", detail_failure)
	if detailed {
		document, parsed, parse_failure := diff_document_open(&detail, DEFAULT_DIFF_LIMITS, allocator)
		testing.expectf(t, parsed, "real semantic diff failed with %v", parse_failure)
		if parsed {
			descriptor, described := diff_document_descriptor(&document)
			testing.expect(t, described)
			testing.expect_value(t, descriptor.unit_count, u32(2))
			testing.expect_value(t, descriptor.layer, Diff_Layer.Working_Tree)
			first, first_found := diff_document_unit(&document, 0)
			second, second_found := diff_document_unit(&document, 1)
			testing.expect(t, first_found && second_found)
			if first_found && second_found {
				testing.expect_value(t, first.old_start, u32(1))
				testing.expect(t, second.old_start > first.old_start)
			}
			diff_document_close(&document)
		}
		path_detail_close(&detail)
	}
	repository_process_close(&process)
	status_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies bounded patch input stages and reverses one exact hunk. */
@(test)
repository_process_applies_one_selected_diff_unit :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-partial-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	baseline := "line 01\nline 02\nline 03\nline 04\nline 05\nline 06\nline 07\nline 08\nline 09\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\n"
	changed := "line 01\nchanged 02\nline 03\nline 04\nline 05\nline 06\nline 07\nline 08\nline 09\nline 10\nline 11\nline 12\nline 13\nline 14\nchanged 15\nline 16\n"
	testing.expect(t, os.write_entire_file(path, baseline) == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, changed) == nil)

	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(90))
	testing.expect(t, observed)
	if !observed do return
	selection, selected := repository_process_test_select_group(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected {
		status_observation_close(&observation)
		return
	}
	detail, document, detailed := repository_process_test_diff_document(&observation, selection)
	testing.expect(t, detailed)
	if !detailed {
		status_observation_close(&observation)
		return
	}
	selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	testing.expect(t, selected && selection.current.kind == .Diff_Unit)
	request, prepared, prepare_failure := partial_index_action_prepare(
		&observation,
		&document,
		selection,
		.Stage,
		Index_Operation_ID(90),
	)
	testing.expectf(t, prepared, "partial stage failed with %v", prepare_failure)
	if !prepared {
		partial_index_action_test_close(&observation, &detail, &document)
		return
	}
	concurrent, concurrent_prepared, concurrent_failure := partial_index_action_prepare(
		&observation,
		&document,
		selection,
		.Stage,
		Index_Operation_ID(92),
	)
	testing.expectf(t, concurrent_prepared, "concurrent request failed with %v", concurrent_failure)
	if !concurrent_prepared {
		partial_index_action_request_close(&request)
		partial_index_action_test_close(&observation, &detail, &document)
		return
	}
	process, started, start_failure := repository_process_start_partial_index_action(
		&observation,
		&document,
		&request,
		1,
	)
	testing.expectf(t, started, "partial stage process failed with %v", start_failure)
	partial_index_action_request_close(&request)
	if !started {
		partial_index_action_request_close(&concurrent)
		partial_index_action_test_close(&observation, &detail, &document)
		return
	}
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	usage, measured := repository_process_usage(&process)
	testing.expect(t, measured && usage.input_bytes > 0)
	result, result_opened, result_failure := repository_process_take_partial_index_action(&process)
	testing.expectf(t, result_opened, "partial stage result failed with %v", result_failure)
	if result_opened {
		descriptor, described := partial_index_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		partial_index_action_result_close(&result)
	}
	repository_process_close(&process)
	concurrent_process, concurrent_started, concurrent_start_failure := repository_process_start_partial_index_action(
		&observation,
		&document,
		&concurrent,
		1,
	)
	testing.expectf(t, concurrent_started, "concurrent process failed to start with %v", concurrent_start_failure)
	partial_index_action_request_close(&concurrent)
	partial_index_action_test_close(&observation, &detail, &document)
	if concurrent_started {
		concurrent_poll := repository_process_test_wait(&concurrent_process)
		testing.expect_value(t, concurrent_poll.state, Repository_Process_State.Failed)
		concurrent_result, concurrent_opened, concurrent_result_failure := repository_process_take_partial_index_action(
			&concurrent_process,
		)
		testing.expectf(t, concurrent_opened, "concurrent result failed with %v", concurrent_result_failure)
		if concurrent_opened {
			descriptor, described := partial_index_action_result_descriptor(&concurrent_result)
			testing.expect(t, described && !descriptor.succeeded)
			testing.expect_value(t, descriptor.failure, Failure_Code.Process_Failed)
			partial_index_action_result_close(&concurrent_result)
		}
		repository_process_close(&concurrent_process)
	}
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--quiet"))

	staged, staged_observed := repository_process_test_observe(repository, Observation_Generation(91))
	testing.expect(t, staged_observed)
	if !staged_observed do return
	staged_selection, staged_selected := repository_process_test_select_group(&staged, .Staged)
	testing.expect(t, staged_selected)
	if !staged_selected {
		status_observation_close(&staged)
		return
	}
	staged_detail, staged_document, staged_detailed := repository_process_test_diff_document(
		&staged,
		staged_selection,
	)
	testing.expect(t, staged_detailed)
	if !staged_detailed {
		status_observation_close(&staged)
		return
	}
	staged_selection, staged_selected, _ = status_selection_move(
		&staged,
		staged_selection,
		.Next,
		&staged_document,
	)
	unstage, unstage_prepared, unstage_failure := partial_index_action_prepare(
		&staged,
		&staged_document,
		staged_selection,
		.Unstage,
		Index_Operation_ID(91),
	)
	testing.expectf(t, unstage_prepared, "partial unstage failed with %v", unstage_failure)
	if !unstage_prepared {
		partial_index_action_test_close(&staged, &staged_detail, &staged_document)
		return
	}
	unstage_process, unstage_started, unstage_start_failure := repository_process_start_partial_index_action(
		&staged,
		&staged_document,
		&unstage,
		1,
	)
	testing.expectf(t, unstage_started, "partial unstage process failed with %v", unstage_start_failure)
	partial_index_action_request_close(&unstage)
	partial_index_action_test_close(&staged, &staged_detail, &staged_document)
	if !unstage_started do return
	unstage_poll := repository_process_test_wait(&unstage_process)
	testing.expect_value(t, unstage_poll.state, Repository_Process_State.Completed)
	repository_process_close(&unstage_process)
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--quiet"))
}

/* Verifies complete-path stage and unstage preserve the working-tree content. */
@(test)
repository_process_runs_checked_index_actions :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-index-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "changed\n") == nil)

	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(70))
	testing.expect(t, observed)
	if !observed do return
	selection, selected := repository_process_test_select_group(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected {
		status_observation_close(&observation)
		return
	}
	stage, prepared, prepare_failure := index_action_prepare(
		&observation,
		selection,
		.Stage,
		Index_Operation_ID(70),
	)
	testing.expectf(t, prepared, "stage preparation failed with %v", prepare_failure)
	if !prepared {
		status_observation_close(&observation)
		return
	}
	stage_process, started, start_failure := repository_process_start_index_action(
		&observation,
		stage,
		1,
	)
	testing.expectf(t, started, "stage process failed with %v", start_failure)
	status_observation_close(&observation)
	if !started do return
	stage_poll := repository_process_test_wait(&stage_process)
	testing.expect_value(t, stage_poll.state, Repository_Process_State.Completed)
	stage_result, stage_result_opened, stage_result_failure := repository_process_take_index_action(&stage_process)
	testing.expectf(t, stage_result_opened, "stage result failed with %v", stage_result_failure)
	if stage_result_opened {
		descriptor, described := index_action_result_descriptor(&stage_result)
		testing.expect(t, described && descriptor.succeeded)
		index_action_result_close(&stage_result)
	}
	repository_process_close(&stage_process)

	staged, staged_observed := repository_process_test_observe(repository, Observation_Generation(71))
	testing.expect(t, staged_observed)
	if !staged_observed do return
	staged_selection, staged_selected := repository_process_test_select_group(&staged, .Staged)
	testing.expect(t, staged_selected)
	if !staged_selected {
		status_observation_close(&staged)
		return
	}
	unstage, unstage_prepared, unstage_prepare_failure := index_action_prepare(
		&staged,
		staged_selection,
		.Unstage,
		Index_Operation_ID(71),
	)
	testing.expectf(t, unstage_prepared, "unstage preparation failed with %v", unstage_prepare_failure)
	if !unstage_prepared {
		status_observation_close(&staged)
		return
	}
	unstage_process, unstage_started, unstage_start_failure := repository_process_start_index_action(
		&staged,
		unstage,
		1,
	)
	testing.expectf(t, unstage_started, "unstage process failed with %v", unstage_start_failure)
	status_observation_close(&staged)
	if !unstage_started do return
	unstage_poll := repository_process_test_wait(&unstage_process)
	testing.expect_value(t, unstage_poll.state, Repository_Process_State.Completed)
	repository_process_close(&unstage_process)

	unstaged, unstaged_observed := repository_process_test_observe(repository, Observation_Generation(72))
	testing.expect(t, unstaged_observed)
	if unstaged_observed {
		_, unstaged_selected := repository_process_test_select_group(&unstaged, .Unstaged)
		testing.expect(t, unstaged_selected)
		status_observation_close(&unstaged)
	}
	contents, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "changed\n")
		delete(contents)
	}
}

/* Verifies a disappeared observed path yields a retained failed outcome and fresh clean state. */
@(test)
repository_process_rejects_a_path_deleted_after_observation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-deleted-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	testing.expect(t, repository_process_test_run(directory, "git", "init", "-q"))
	path, path_error := os.join_path({directory, "removed.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "removed\n") == nil)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(80))
	testing.expect(t, observed)
	if !observed do return
	defer status_observation_close(&observation)
	selection, selected := repository_process_test_select_group(&observation, .Untracked)
	testing.expect(t, selected)
	if !selected do return
	request, prepared, _ := index_action_prepare(
		&observation,
		selection,
		.Stage,
		Index_Operation_ID(80),
	)
	testing.expect(t, prepared)
	if !prepared do return
	testing.expect(t, os.remove(path) == nil)
	process, started, start_failure := repository_process_start_index_action(&observation, request, 1)
	testing.expectf(t, started, "deleted-path process failed to start with %v", start_failure)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Failed)
	result, result_opened, result_failure := repository_process_take_index_action(&process)
	testing.expectf(t, result_opened, "deleted-path result failed with %v", result_failure)
	if result_opened {
		descriptor, described := index_action_result_descriptor(&result)
		testing.expect(t, described && !descriptor.succeeded)
		testing.expect_value(t, descriptor.failure, Failure_Code.Process_Failed)
		_, diagnostic, copied := index_action_result_output(&result)
		testing.expect(t, copied && len(diagnostic) > 0)
		index_action_result_close(&result)
	}
	repository_process_close(&process)
	fresh, fresh_observed := repository_process_test_observe(repository, Observation_Generation(81))
	testing.expect(t, fresh_observed)
	if fresh_observed {
		path_count, counted := status_observation_path_count(&fresh)
		testing.expect(t, counted)
		testing.expect_value(t, path_count, u32(0))
		status_observation_close(&fresh)
	}
}

/* Verifies an index permission failure is contained as a bounded process result. */
@(test)
repository_process_contains_index_permission_failure :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-permission-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "locked.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "locked.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "changed\n") == nil)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(90))
	testing.expect(t, observed)
	if !observed do return
	defer status_observation_close(&observation)
	selection, selected := repository_process_test_select_group(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected do return
	request, prepared, _ := index_action_prepare(
		&observation,
		selection,
		.Stage,
		Index_Operation_ID(90),
	)
	testing.expect(t, prepared)
	if !prepared do return
	metadata, metadata_error := os.join_path({directory, ".git"}, context.allocator)
	testing.expect(t, metadata_error == nil)
	if metadata_error != nil do return
	defer delete(metadata)
	readonly := os.Permissions{.Read_User, .Execute_User}
	writable := os.Permissions{.Read_User, .Write_User, .Execute_User}
	testing.expect(t, os.chmod(metadata, readonly) == nil)
	defer os.chmod(metadata, writable)
	process, started, start_failure := repository_process_start_index_action(&observation, request, 1)
	testing.expectf(t, started, "permission process failed to start with %v", start_failure)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Failed)
	result, result_opened, result_failure := repository_process_take_index_action(&process)
	testing.expectf(t, result_opened, "permission result failed with %v", result_failure)
	if result_opened {
		descriptor, described := index_action_result_descriptor(&result)
		testing.expect(t, described && !descriptor.succeeded)
		testing.expect_value(t, descriptor.failure, Failure_Code.Process_Failed)
		index_action_result_close(&result)
	}
	repository_process_close(&process)
}

/* Verifies confirmed discard restores only the working tree and preserves indexed content. */
@(test)
repository_process_discards_one_tracked_path_without_changing_index :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-discard-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "indexed\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	testing.expect(t, os.write_entire_file(path, "working\n") == nil)

	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(101))
	testing.expect(t, observed)
	if !observed do return
	defer status_observation_close(&observation)
	selection, selected := repository_process_test_select_group(&observation, .Unstaged)
	testing.expect(t, selected)
	if !selected do return
	request, prepared, prepare_failure := discard_action_prepare(
		&observation,
		selection,
		Index_Operation_ID(101),
		Discard_Confirmation_ID(101),
		false,
	)
	testing.expectf(t, prepared, "discard preparation failed with %v", prepare_failure)
	if !prepared do return
	confirmed, confirm_failure := discard_action_confirm(&request, Discard_Confirmation_ID(101))
	testing.expectf(t, confirmed, "discard confirmation failed with %v", confirm_failure)
	if !confirmed do return
	process, started, start_failure := repository_process_start_discard_action(
		&observation,
		request,
		false,
		1,
	)
	testing.expectf(t, started, "discard process failed with %v", start_failure)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	result, result_opened, result_failure := repository_process_take_discard_action(&process)
	testing.expectf(t, result_opened, "discard result failed with %v", result_failure)
	if result_opened {
		descriptor, described := discard_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		discard_action_result_close(&result)
	}
	repository_process_close(&process)

	contents, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "indexed\n")
		delete(contents)
	}
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--quiet"))
}

/* Verifies checked root and ordinary commits consume only the admitted index tree. */
@(test)
repository_process_commits_checked_root_and_ordinary_indexes :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-commit-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid") &&
	         repository_process_test_run(directory, "git", "config", "commit.gpgSign", "false")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	if repository == {} do return

	testing.expect(t, os.write_entire_file(path, "root indexed\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	root_observation, observed := repository_process_test_observe(repository, Observation_Generation(301), allocator)
	testing.expect(t, observed)
	if !observed do return
	root_precondition, checked := repository_process_test_commit_precondition(&root_observation, allocator)
	testing.expect(t, checked && root_precondition.head.kind == .Unborn)
	if !checked {
		status_observation_close(&root_observation)
		return
	}
	root_message: Commit_Message
	testing.expect(t, commit_message_assign(&root_message, "root commit"))
	root_request, prepared, prepare_failure := commit_request_prepare(root_precondition, root_message, Commit_Operation_ID(301))
	testing.expectf(t, prepared, "root commit preparation failed with %v", prepare_failure)
	if !prepared {
		status_observation_close(&root_observation)
		return
	}
	root_process, started, start_failure := repository_process_start_commit(root_request, 1, allocator)
	testing.expectf(t, started, "root commit start failed with %v", start_failure)
	if !started {
		status_observation_close(&root_observation)
		return
	}
	root_poll := repository_process_test_wait(&root_process)
	testing.expect_value(t, root_poll.state, Repository_Process_State.Completed)
	root_result, result_opened, result_failure := repository_process_take_commit(&root_process, allocator)
	testing.expectf(t, result_opened, "root commit result failed with %v", result_failure)
	if result_opened {
		descriptor, described := commit_result_descriptor(&root_result)
		testing.expect(t, described && descriptor.succeeded)
		commit_result_close(&root_result)
	}
	repository_process_close(&root_process)
	status_observation_close(&root_observation)
	testing.expect(t, repository_process_test_run(directory, "git", "rev-parse", "--verify", "HEAD"))

	testing.expect(t, os.write_entire_file(path, "ordinary indexed\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	testing.expect(t, os.write_entire_file(path, "working tree remains\n") == nil)
	ordinary_observation, ordinary_observed := repository_process_test_observe(repository, Observation_Generation(302), allocator)
	testing.expect(t, ordinary_observed)
	if !ordinary_observed do return
	ordinary_precondition, ordinary_checked := repository_process_test_commit_precondition(&ordinary_observation, allocator)
	testing.expect(t, ordinary_checked && ordinary_precondition.head.kind == .Revision)
	if !ordinary_checked {
		status_observation_close(&ordinary_observation)
		return
	}
	ordinary_message: Commit_Message
	testing.expect(t, commit_message_assign(&ordinary_message, "ordinary commit\n\nbody"))
	ordinary_request, ordinary_prepared, ordinary_prepare_failure := commit_request_prepare(
		ordinary_precondition, ordinary_message, Commit_Operation_ID(302),
	)
	testing.expectf(t, ordinary_prepared, "ordinary commit preparation failed with %v", ordinary_prepare_failure)
	if !ordinary_prepared {
		status_observation_close(&ordinary_observation)
		return
	}
	ordinary_process, ordinary_started, ordinary_start_failure := repository_process_start_commit(ordinary_request, 1, allocator)
	testing.expectf(t, ordinary_started, "ordinary commit start failed with %v", ordinary_start_failure)
	if !ordinary_started {
		status_observation_close(&ordinary_observation)
		return
	}
	ordinary_poll := repository_process_test_wait(&ordinary_process)
	testing.expect_value(t, ordinary_poll.state, Repository_Process_State.Completed)
	ordinary_result, ordinary_result_opened, ordinary_result_failure := repository_process_take_commit(&ordinary_process, allocator)
	testing.expectf(t, ordinary_result_opened, "ordinary commit result failed with %v", ordinary_result_failure)
	if ordinary_result_opened {
		descriptor, described := commit_result_descriptor(&ordinary_result)
		testing.expect(t, described && descriptor.succeeded)
		commit_result_close(&ordinary_result)
	}
	repository_process_close(&ordinary_process)
	status_observation_close(&ordinary_observation)
	contents, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "working tree remains\n")
		delete(contents)
	}
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--quiet"))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies checked amend and exact-target fixup processes retain lineage and reject stale state. */
@(test)
repository_process_amends_and_creates_exact_fixups_safely :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-amend-fixup-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid") &&
	         repository_process_test_run(directory, "git", "config", "commit.gpgSign", "false")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "root target\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "root target")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "replaceable head\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "replaceable head")
	testing.expect(t, ready)
	if !ready do return

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	if repository == {} do return

	testing.expect(t, os.write_entire_file(path, "amended index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	amend_observation, amend_observed := repository_process_test_observe(repository, Observation_Generation(401), allocator)
	testing.expect(t, amend_observed)
	if !amend_observed do return
	amend_precondition, amend_checked := repository_process_test_commit_precondition(&amend_observation, allocator)
	testing.expect(t, amend_checked)
	if !amend_checked {
		status_observation_close(&amend_observation)
		return
	}
	amend_history, amend_history_opened := repository_process_test_history(repository, History_Generation(401), allocator)
	testing.expect(t, amend_history_opened)
	if !amend_history_opened {
		status_observation_close(&amend_observation)
		return
	}
	amend_message: Commit_Message
	testing.expect(t, commit_message_assign(&amend_message, "amended subject\n\namended body"))
	confirmation, confirmation_prepared, confirmation_failure := amend_confirmation_prepare(
		amend_precondition, &amend_history, amend_message, Commit_Confirmation_ID(401),
	)
	testing.expectf(t, confirmation_prepared, "amend confirmation failed with %v", confirmation_failure)
	if !confirmation_prepared {
		history_observation_close(&amend_history)
		status_observation_close(&amend_observation)
		return
	}
	confirmed, confirm_failure := amend_confirmation_confirm(&confirmation, Commit_Confirmation_ID(401))
	testing.expectf(t, confirmed, "amend confirmation acceptance failed with %v", confirm_failure)
	if !confirmed {
		history_observation_close(&amend_history)
		status_observation_close(&amend_observation)
		return
	}
	amend_request, amend_prepared, amend_prepare_failure := amend_request_prepare(
		amend_precondition, amend_message, Commit_Operation_ID(401), &confirmation,
	)
	testing.expectf(t, amend_prepared, "amend request failed with %v", amend_prepare_failure)
	if !amend_prepared {
		history_observation_close(&amend_history)
		status_observation_close(&amend_observation)
		return
	}
	amend_process, amend_started, amend_start_failure := repository_process_start_commit(amend_request, 1, allocator)
	testing.expectf(t, amend_started, "amend process failed to start with %v", amend_start_failure)
	if !amend_started {
		history_observation_close(&amend_history)
		status_observation_close(&amend_observation)
		return
	}
	amend_poll := repository_process_test_wait(&amend_process)
	testing.expect_value(t, amend_poll.state, Repository_Process_State.Completed)
	amend_result, amend_result_opened, amend_result_failure := repository_process_take_commit(&amend_process, allocator)
	testing.expectf(t, amend_result_opened, "amend result failed with %v", amend_result_failure)
	replacement: Revision_Identity
	if amend_result_opened {
		amend_descriptor, amend_described := commit_result_descriptor(&amend_result)
		testing.expect(t, amend_described && amend_descriptor.succeeded)
		if amend_described {
			testing.expect_value(t, amend_descriptor.lineage.replaced, amend_precondition.head.revision)
			testing.expect(t, amend_descriptor.lineage.resulting != amend_precondition.head.revision)
			replacement = amend_descriptor.lineage.resulting
		}
		commit_result_close(&amend_result)
	}
	repository_process_close(&amend_process)
	history_observation_close(&amend_history)
	status_observation_close(&amend_observation)
	if replacement == {} do return

	testing.expect(t, os.write_entire_file(path, "fixup index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	fixup_observation, fixup_observed := repository_process_test_observe(repository, Observation_Generation(402), allocator)
	testing.expect(t, fixup_observed)
	if !fixup_observed do return
	fixup_precondition, fixup_checked := repository_process_test_commit_precondition(&fixup_observation, allocator)
	testing.expect(t, fixup_checked)
	if !fixup_checked {
		status_observation_close(&fixup_observation)
		return
	}
	fixup_history, fixup_history_opened := repository_process_test_history(repository, History_Generation(402), allocator)
	testing.expect(t, fixup_history_opened)
	if !fixup_history_opened {
		status_observation_close(&fixup_observation)
		return
	}
	target_entry, target_found := history_observation_revision(&fixup_history, 1)
	testing.expect(t, target_found)
	if !target_found {
		history_observation_close(&fixup_history)
		status_observation_close(&fixup_observation)
		return
	}
	target := History_Target{generation = History_Generation(402), revision = target_entry.identity}
	fixup_request, fixup_prepared, fixup_prepare_failure := fixup_request_prepare(
		fixup_precondition, &fixup_history, target, Commit_Operation_ID(402),
	)
	testing.expectf(t, fixup_prepared, "fixup request failed with %v", fixup_prepare_failure)
	if !fixup_prepared {
		history_observation_close(&fixup_history)
		status_observation_close(&fixup_observation)
		return
	}
	fixup_message, message_copied := commit_message_text(&fixup_request.message)
	testing.expect(t, message_copied)
	if message_copied do testing.expect_value(t, string(fixup_message), "fixup! root target")
	fixup_process, fixup_started, fixup_start_failure := repository_process_start_commit(fixup_request, 1, allocator)
	testing.expectf(t, fixup_started, "fixup process failed to start with %v", fixup_start_failure)
	if !fixup_started {
		history_observation_close(&fixup_history)
		status_observation_close(&fixup_observation)
		return
	}
	fixup_poll := repository_process_test_wait(&fixup_process)
	testing.expect_value(t, fixup_poll.state, Repository_Process_State.Completed)
	fixup_result, fixup_result_opened, fixup_result_failure := repository_process_take_commit(&fixup_process, allocator)
	testing.expectf(t, fixup_result_opened, "fixup result failed with %v", fixup_result_failure)
	fixup_identity: Revision_Identity
	if fixup_result_opened {
		fixup_descriptor, fixup_described := commit_result_descriptor(&fixup_result)
		testing.expect(t, fixup_described && fixup_descriptor.succeeded)
		if fixup_described {
			testing.expect_value(t, fixup_descriptor.lineage.fixup_target, target.revision)
			testing.expect_value(t, fixup_descriptor.lineage.prior_head.revision, replacement)
			fixup_identity = fixup_descriptor.lineage.resulting
		}
		commit_result_close(&fixup_result)
	}
	repository_process_close(&fixup_process)
	history_observation_close(&fixup_history)
	status_observation_close(&fixup_observation)
	if fixup_identity == {} do return

	refreshed_history, refreshed_history_opened := repository_process_test_history(repository, History_Generation(403), allocator)
	testing.expect(t, refreshed_history_opened)
	if !refreshed_history_opened do return
	refreshed_descriptor, refreshed_described := history_observation_descriptor(&refreshed_history)
	testing.expect(t, refreshed_described && refreshed_descriptor.head == fixup_identity)
	refreshed_head, refreshed_found := history_observation_revision(&refreshed_history, 0)
	testing.expect(t, refreshed_found)
	if refreshed_found {
		refreshed_subject, subject_copied := history_observation_text(&refreshed_history, refreshed_head.subject)
		testing.expect(t, subject_copied)
		if subject_copied do testing.expect_value(t, string(refreshed_subject), "fixup! root target")
	}
	history_observation_close(&refreshed_history)

	testing.expect(t, os.write_entire_file(path, "drifted index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	drift_observation, drift_observed := repository_process_test_observe(repository, Observation_Generation(404), allocator)
	testing.expect(t, drift_observed)
	if !drift_observed do return
	drift_precondition, drift_checked := repository_process_test_commit_precondition(&drift_observation, allocator)
	testing.expect(t, drift_checked)
	drift_history, drift_history_opened := repository_process_test_history(repository, History_Generation(404), allocator)
	testing.expect(t, drift_history_opened)
	if !drift_checked || !drift_history_opened {
		if drift_history_opened do history_observation_close(&drift_history)
		status_observation_close(&drift_observation)
		return
	}
	drift_target := History_Target{generation = History_Generation(404), revision = fixup_identity}
	drift_request, drift_prepared, drift_prepare_failure := fixup_request_prepare(
		drift_precondition, &drift_history, drift_target, Commit_Operation_ID(404),
	)
	testing.expectf(t, drift_prepared, "drift request failed with %v", drift_prepare_failure)
	testing.expect(t, os.write_entire_file(path, "newer index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	if drift_prepared {
		drift_process, drift_started, drift_start_failure := repository_process_start_commit(drift_request, 1, allocator)
		testing.expectf(t, drift_started, "drift process failed to start with %v", drift_start_failure)
		if drift_started {
			drift_poll := repository_process_test_wait(&drift_process)
			testing.expect_value(t, drift_poll.state, Repository_Process_State.Failed)
			drift_result, drift_result_opened, drift_result_failure := repository_process_take_commit(&drift_process, allocator)
			testing.expectf(t, drift_result_opened, "drift result failed with %v", drift_result_failure)
			if drift_result_opened {
				drift_descriptor, drift_described := commit_result_descriptor(&drift_result)
				testing.expect(t, drift_described && !drift_descriptor.succeeded)
				if drift_described do testing.expect_value(t, drift_descriptor.failure, Failure_Code.Stale_Observation)
				commit_result_close(&drift_result)
			}
			repository_process_close(&drift_process)
		}
	}
	history_observation_close(&drift_history)
	status_observation_close(&drift_observation)

	stale_observation, stale_observed := repository_process_test_observe(repository, Observation_Generation(405), allocator)
	testing.expect(t, stale_observed)
	if !stale_observed do return
	stale_precondition, stale_checked := repository_process_test_commit_precondition(&stale_observation, allocator)
	testing.expect(t, stale_checked)
	stale_history, stale_history_opened := repository_process_test_history(repository, History_Generation(405), allocator)
	testing.expect(t, stale_history_opened)
	if !stale_checked || !stale_history_opened {
		if stale_history_opened do history_observation_close(&stale_history)
		status_observation_close(&stale_observation)
		return
	}
	stale_message: Commit_Message
	testing.expect(t, commit_message_assign(&stale_message, "stale replacement"))
	stale_confirmation, stale_confirmation_prepared, stale_confirmation_failure := amend_confirmation_prepare(
		stale_precondition, &stale_history, stale_message, Commit_Confirmation_ID(405),
	)
	testing.expectf(t, stale_confirmation_prepared, "stale confirmation failed with %v", stale_confirmation_failure)
	stale_confirmed := false
	if stale_confirmation_prepared {
		stale_confirmed, _ = amend_confirmation_confirm(&stale_confirmation, Commit_Confirmation_ID(405))
	}
	stale_request, stale_prepared, stale_prepare_failure := amend_request_prepare(
		stale_precondition, stale_message, Commit_Operation_ID(405), &stale_confirmation,
	)
	testing.expectf(t, stale_confirmation_prepared && stale_confirmed && stale_prepared, "stale amend request failed with %v", stale_prepare_failure)
	testing.expect(t, repository_process_test_run(directory, "git", "commit", "-qm", "external head"))
	if stale_confirmation_prepared && stale_confirmed && stale_prepared {
		stale_process, stale_started, stale_start_failure := repository_process_start_commit(stale_request, 1, allocator)
		testing.expectf(t, stale_started, "stale amend process failed to start with %v", stale_start_failure)
		if stale_started {
			stale_poll := repository_process_test_wait(&stale_process)
			testing.expect_value(t, stale_poll.state, Repository_Process_State.Failed)
			stale_result, stale_result_opened, stale_result_failure := repository_process_take_commit(&stale_process, allocator)
			testing.expectf(t, stale_result_opened, "stale amend result failed with %v", stale_result_failure)
			if stale_result_opened {
				stale_descriptor, stale_described := commit_result_descriptor(&stale_result)
				testing.expect(t, stale_described && !stale_descriptor.succeeded)
				if stale_described do testing.expect_value(t, stale_descriptor.failure, Failure_Code.Stale_Observation)
				commit_result_close(&stale_result)
			}
			repository_process_close(&stale_process)
		}
	}
	history_observation_close(&stale_history)
	status_observation_close(&stale_observation)

	testing.expect(t, os.write_entire_file(path, "sequenced index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	sequence_observation, sequence_observed := repository_process_test_observe(repository, Observation_Generation(406), allocator)
	testing.expect(t, sequence_observed)
	if !sequence_observed do return
	sequence_precondition, sequence_checked := repository_process_test_commit_precondition(&sequence_observation, allocator)
	testing.expect(t, sequence_checked)
	sequence_history, sequence_history_opened := repository_process_test_history(repository, History_Generation(406), allocator)
	testing.expect(t, sequence_history_opened)
	if !sequence_checked || !sequence_history_opened {
		if sequence_history_opened do history_observation_close(&sequence_history)
		status_observation_close(&sequence_observation)
		return
	}
	sequence_descriptor, sequence_described := history_observation_descriptor(&sequence_history)
	sequence_request, sequence_prepared, sequence_prepare_failure := fixup_request_prepare(
		sequence_precondition,
		&sequence_history,
		{generation = History_Generation(406), revision = sequence_descriptor.head},
		Commit_Operation_ID(406),
	)
	testing.expectf(t, sequence_described && sequence_prepared, "sequence fixup request failed with %v", sequence_prepare_failure)
	metadata, metadata_error := os.join_path({directory, ".git", "MERGE_HEAD"}, context.allocator)
	testing.expect(t, metadata_error == nil)
	if metadata_error == nil {
		defer delete(metadata)
		testing.expect(t, os.write_entire_file(metadata, "synthetic sequence\n") == nil)
		if sequence_described && sequence_prepared {
			sequence_process, sequence_started, sequence_start_failure := repository_process_start_commit(sequence_request, 1, allocator)
			testing.expectf(t, sequence_started, "sequence fixup process failed to start with %v", sequence_start_failure)
			if sequence_started {
				sequence_poll := repository_process_test_wait(&sequence_process)
				testing.expect_value(t, sequence_poll.state, Repository_Process_State.Failed)
				sequence_result, sequence_result_opened, sequence_result_failure := repository_process_take_commit(&sequence_process, allocator)
				testing.expectf(t, sequence_result_opened, "sequence fixup result failed with %v", sequence_result_failure)
				if sequence_result_opened {
					sequence_result_descriptor, sequence_result_described := commit_result_descriptor(&sequence_result)
					testing.expect(t, sequence_result_described && !sequence_result_descriptor.succeeded)
					if sequence_result_described do testing.expect_value(t, sequence_result_descriptor.failure, Failure_Code.Commit_Unavailable)
					commit_result_close(&sequence_result)
				}
				repository_process_close(&sequence_process)
			}
		}
		testing.expect(t, os.remove(metadata) == nil)
	}
	history_observation_close(&sequence_history)
	status_observation_close(&sequence_observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies index drift and active Git sequences reject an admitted normal commit. */
@(test)
repository_process_rejects_drifted_indexes_and_active_sequences :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-commit-stale-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid") &&
	         repository_process_test_run(directory, "git", "config", "commit.gpgSign", "false")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "first index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(311))
	testing.expect(t, observed)
	if !observed do return
	precondition, checked := repository_process_test_commit_precondition(&observation)
	status_observation_close(&observation)
	testing.expect(t, checked)
	if !checked do return
	message: Commit_Message
	testing.expect(t, commit_message_assign(&message, "stale request"))
	stale_request, prepared, prepare_failure := commit_request_prepare(precondition, message, Commit_Operation_ID(311))
	testing.expectf(t, prepared, "stale request preparation failed with %v", prepare_failure)
	if !prepared do return
	testing.expect(t, os.write_entire_file(path, "second index\n") == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "add", "--", "notes.txt"))
	stale_process, stale_started, stale_start_failure := repository_process_start_commit(stale_request, 1)
	testing.expectf(t, stale_started, "stale commit start failed with %v", stale_start_failure)
	if !stale_started do return
	stale_poll := repository_process_test_wait(&stale_process)
	testing.expect_value(t, stale_poll.state, Repository_Process_State.Failed)
	stale_result, stale_opened, stale_failure := repository_process_take_commit(&stale_process)
	testing.expectf(t, stale_opened, "stale commit result failed with %v", stale_failure)
	if stale_opened {
		descriptor, described := commit_result_descriptor(&stale_result)
		testing.expect(t, described && !descriptor.succeeded)
		testing.expect_value(t, descriptor.failure, Failure_Code.Stale_Observation)
		commit_result_close(&stale_result)
	}
	repository_process_close(&stale_process)

	current_observation, current_observed := repository_process_test_observe(repository, Observation_Generation(312))
	testing.expect(t, current_observed)
	if !current_observed do return
	current_precondition, current_checked := repository_process_test_commit_precondition(&current_observation)
	status_observation_close(&current_observation)
	testing.expect(t, current_checked)
	if !current_checked do return
	sequence_request, sequence_prepared, sequence_prepare_failure := commit_request_prepare(
		current_precondition, message, Commit_Operation_ID(312),
	)
	testing.expectf(t, sequence_prepared, "sequence request preparation failed with %v", sequence_prepare_failure)
	if !sequence_prepared do return
	metadata, metadata_error := os.join_path({directory, ".git", "MERGE_HEAD"}, context.allocator)
	testing.expect(t, metadata_error == nil)
	if metadata_error != nil do return
	defer delete(metadata)
	testing.expect(t, os.write_entire_file(metadata, "synthetic sequence\n") == nil)
	sequence_process, sequence_started, sequence_start_failure := repository_process_start_commit(sequence_request, 1)
	testing.expectf(t, sequence_started, "sequence commit start failed with %v", sequence_start_failure)
	if !sequence_started do return
	sequence_poll := repository_process_test_wait(&sequence_process)
	testing.expect_value(t, sequence_poll.state, Repository_Process_State.Failed)
	sequence_result, sequence_opened, sequence_failure := repository_process_take_commit(&sequence_process)
	testing.expectf(t, sequence_opened, "sequence commit result failed with %v", sequence_failure)
	if sequence_opened {
		descriptor, described := commit_result_descriptor(&sequence_result)
		testing.expect(t, described && !descriptor.succeeded)
		testing.expect_value(t, descriptor.failure, Failure_Code.Commit_Unavailable)
		commit_result_close(&sequence_result)
	}
	repository_process_close(&sequence_process)
	testing.expect(t, os.remove(metadata) == nil)
	testing.expect(t, repository_process_test_run(directory, "git", "rev-parse", "--verify", "HEAD"))
}

/* Verifies checked fetch updates only remote-tracking truth across terminal outcomes. */
@(test)
repository_process_fetches_one_exact_local_bare_remote :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-fetch-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	remote_directory, remote_error := os.join_path({directory, "origin.git"}, context.allocator)
	seed_directory, seed_error := os.join_path({directory, "seed"}, context.allocator)
	local_directory, local_error := os.join_path({directory, "local"}, context.allocator)
	alternate_directory, alternate_error := os.join_path({directory, "alternate.git"}, context.allocator)
	testing.expect(t, remote_error == nil && seed_error == nil && local_error == nil && alternate_error == nil)
	if remote_error != nil || seed_error != nil || local_error != nil || alternate_error != nil do return
	defer delete(remote_directory)
	defer delete(seed_directory)
	defer delete(local_directory)
	defer delete(alternate_directory)
	ready := repository_process_test_run(directory, "git", "init", "--bare", "-q", "--initial-branch=main", remote_directory) &&
	         repository_process_test_run(directory, "git", "init", "-q", "-b", "main", seed_directory) &&
	         repository_process_test_run(seed_directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(seed_directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	seed_path, seed_path_error := os.join_path({seed_directory, "fetch.txt"}, context.allocator)
	testing.expect(t, seed_path_error == nil)
	if seed_path_error != nil do return
	defer delete(seed_path)
	ready = os.write_entire_file(seed_path, "baseline\n") == nil &&
	        repository_process_test_run(seed_directory, "git", "add", "--", "fetch.txt") &&
	        repository_process_test_run(seed_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "baseline") &&
	        repository_process_test_run(seed_directory, "git", "remote", "add", "origin", remote_directory) &&
	        repository_process_test_run(seed_directory, "git", "push", "-q", "-u", "origin", "main") &&
	        repository_process_test_run(directory, "git", "clone", "-q", remote_directory, local_directory) &&
	        repository_process_test_run(local_directory, "git", "config", "user.name", "Odra Test") &&
	        repository_process_test_run(local_directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, local_directory))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	before: Ref_Observation
	after: Ref_Observation
	defer {
		if before.state != nil do ref_observation_close(&before)
		if after.state != nil do ref_observation_close(&after)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	before, ready = repository_process_test_refs(repository, Ref_Generation(41), allocator)
	testing.expect(t, ready)
	if !ready do return
	selection, _, selected := repository_process_test_select_remote(&before, "origin")
	configuration, configured := repository_process_test_remote_configuration(&before, selection, allocator)
	local_before, local_found := repository_process_test_find_ref(&before, "refs/heads/main")
	tracking_before, tracking_found := repository_process_test_find_ref(&before, "refs/remotes/origin/main")
	testing.expect(t, selected && configured && local_found && tracking_found)
	if !selected || !configured || !local_found || !tracking_found do return
	ready = os.write_entire_file(seed_path, "baseline\nremote\n") == nil &&
	        repository_process_test_run(seed_directory, "git", "add", "--", "fetch.txt") &&
	        repository_process_test_run(seed_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "remote update") &&
	        repository_process_test_run(seed_directory, "git", "push", "-q", "origin", "main")
	testing.expect(t, ready)
	if !ready do return
	request, prepared, prepare_failure := fetch_request_prepare(
		&before,
		selection,
		configuration,
		.Normal,
		Fetch_Operation_ID(41),
	)
	testing.expectf(t, prepared, "fetch preparation failed with %v", prepare_failure)
	if !prepared do return
	process, started, start_failure := repository_process_start_fetch(
		&before,
		configuration,
		.Normal,
		request,
		1,
		allocator,
	)
	testing.expectf(t, started, "fetch process failed to start with %v", start_failure)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	result, result_opened, result_failure := repository_process_take_fetch(&process, allocator)
	testing.expectf(t, result_opened, "fetch result failed with %v", result_failure)
	if result_opened {
		descriptor, described := fetch_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded && descriptor.refresh_required)
		fetch_result_close(&result)
	}
	repository_process_close(&process)
	after, ready = repository_process_test_refs(repository, Ref_Generation(42), allocator)
	testing.expect(t, ready)
	if !ready do return
	local_after, local_after_found := repository_process_test_find_ref(&after, "refs/heads/main")
	tracking_after, tracking_after_found := repository_process_test_find_ref(&after, "refs/remotes/origin/main")
	testing.expect(t, local_after_found && tracking_after_found)
	if local_after_found && tracking_after_found {
		testing.expect_value(t, local_after.object, local_before.object)
		testing.expect(t, tracking_after.object != tracking_before.object)
	}

	stale_selection, _, stale_selected := repository_process_test_select_remote(&after, "origin")
	stale_configuration, stale_configured := repository_process_test_remote_configuration(&after, stale_selection, allocator)
	stale_request, stale_prepared, stale_prepare_failure := fetch_request_prepare(
		&after,
		stale_selection,
		stale_configuration,
		.Normal,
		Fetch_Operation_ID(42),
	)
	testing.expectf(t, stale_selected && stale_configured && stale_prepared, "stale fetch setup failed with %v", stale_prepare_failure)
	if !stale_selected || !stale_configured || !stale_prepared do return
	testing.expect(t, repository_process_test_run(directory, "git", "init", "--bare", "-q", alternate_directory))
	testing.expect(t, repository_process_test_run(local_directory, "git", "remote", "set-url", "origin", alternate_directory))
	stale_process, stale_started, stale_start_failure := repository_process_start_fetch(
		&after,
		stale_configuration,
		.Normal,
		stale_request,
		1,
		allocator,
	)
	testing.expectf(t, stale_started, "stale fetch process failed to start with %v", stale_start_failure)
	if stale_started {
		stale_poll := repository_process_test_wait(&stale_process)
		testing.expect_value(t, stale_poll.state, Repository_Process_State.Failed)
		testing.expect_value(t, stale_poll.failure, Failure_Code.Stale_Observation)
		_, stale_opened, stale_failure := repository_process_take_fetch(&stale_process, allocator)
		testing.expect(t, !stale_opened && stale_failure == .Stale_Observation)
		repository_process_close(&stale_process)
	}

	testing.expect(t, repository_process_test_run(local_directory, "git", "remote", "set-url", "origin", remote_directory))
	cancelled_process, cancelled_started, cancelled_start_failure := repository_process_start_fetch(
		&after,
		stale_configuration,
		.Normal,
		stale_request,
		1,
		allocator,
	)
	testing.expectf(t, cancelled_started, "cancelled fetch process failed to start with %v", cancelled_start_failure)
	if cancelled_started {
		testing.expect(t, repository_process_cancel(&cancelled_process))
		cancelled_result, cancelled_opened, cancelled_failure := repository_process_take_fetch(&cancelled_process, allocator)
		testing.expectf(t, cancelled_opened, "cancelled fetch result failed with %v", cancelled_failure)
		if cancelled_opened {
			descriptor, described := fetch_result_descriptor(&cancelled_result)
			testing.expect(t, described && !descriptor.started && !descriptor.refresh_required)
			testing.expect_value(t, fetch_feedback(descriptor), Fetch_Feedback.Cancelled)
			fetch_result_close(&cancelled_result)
		}
		repository_process_close(&cancelled_process)
	}

	missing_directory, missing_error := os.join_path({directory, "missing.git"}, context.allocator)
	testing.expect(t, missing_error == nil)
	if missing_error != nil do return
	defer delete(missing_directory)
	testing.expect(t, repository_process_test_run(local_directory, "git", "remote", "set-url", "origin", missing_directory))
	failing_configuration, failing_configured := repository_process_test_remote_configuration(
		&after,
		stale_selection,
		allocator,
	)
	failing_request, failing_prepared, failing_prepare_failure := fetch_request_prepare(
		&after,
		stale_selection,
		failing_configuration,
		.Normal,
		Fetch_Operation_ID(43),
	)
	testing.expectf(
		t,
		failing_configured && failing_prepared,
		"failing fetch setup failed with %v",
		failing_prepare_failure,
	)
	if !failing_configured || !failing_prepared do return
	failing_process, failing_started, failing_start_failure := repository_process_start_fetch(
		&after,
		failing_configuration,
		.Normal,
		failing_request,
		1,
		allocator,
	)
	testing.expectf(t, failing_started, "failing fetch process failed to start with %v", failing_start_failure)
	if failing_started {
		failing_poll := repository_process_test_wait(&failing_process)
		testing.expect_value(t, failing_poll.state, Repository_Process_State.Failed)
		failing_result, failing_opened, failing_failure := repository_process_take_fetch(&failing_process, allocator)
		testing.expectf(t, failing_opened, "failing fetch result failed with %v", failing_failure)
		if failing_opened {
			descriptor, described := fetch_result_descriptor(&failing_result)
			testing.expect(t, described && descriptor.started && !descriptor.succeeded && descriptor.refresh_required)
			testing.expect_value(t, descriptor.failure, Failure_Code.Process_Failed)
			testing.expect_value(t, fetch_feedback(descriptor), Fetch_Feedback.Failed)
			fetch_result_close(&failing_result)
		}
		repository_process_close(&failing_process)
	}
}

/* Verifies one confirmed non-force branch push against fresh Ref truth and bounded terminal failures. */
@(test)
repository_process_pushes_one_exact_tracked_branch :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-push-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	remote_directory, remote_error := os.join_path({directory, "origin.git"}, context.allocator)
	local_directory, local_error := os.join_path({directory, "local"}, context.allocator)
	missing_directory, missing_error := os.join_path({directory, "missing.git"}, context.allocator)
	testing.expect(t, remote_error == nil && local_error == nil && missing_error == nil)
	if remote_error != nil || local_error != nil || missing_error != nil do return
	defer delete(remote_directory)
	defer delete(local_directory)
	defer delete(missing_directory)
	ready := repository_process_test_run(directory, "git", "init", "--bare", "-q", "--initial-branch=main", remote_directory) &&
	         repository_process_test_run(directory, "git", "init", "-q", "-b", "main", local_directory) &&
	         repository_process_test_run(local_directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(local_directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({local_directory, "push.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	ready = os.write_entire_file(path, "baseline\n") == nil &&
	        repository_process_test_run(local_directory, "git", "add", "--", "push.txt") &&
	        repository_process_test_run(local_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "baseline") &&
	        repository_process_test_run(local_directory, "git", "remote", "add", "origin", remote_directory) &&
	        repository_process_test_run(local_directory, "git", "push", "-q", "-u", "origin", "main") &&
	        os.write_entire_file(path, "baseline\nlocal publication\n") == nil &&
	        repository_process_test_run(local_directory, "git", "add", "--", "push.txt") &&
	        repository_process_test_run(local_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "local publication")
	testing.expect(t, ready)
	if !ready do return
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, local_directory))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	before: Ref_Observation
	after: Ref_Observation
	drifted: Ref_Observation
	rejected: Ref_Observation
	defer {
		if before.state != nil do ref_observation_close(&before)
		if after.state != nil do ref_observation_close(&after)
		if drifted.state != nil do ref_observation_close(&drifted)
		if rejected.state != nil do ref_observation_close(&rejected)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	before, ready = repository_process_test_refs(repository, Ref_Generation(51), allocator)
	testing.expect(t, ready)
	if !ready do return
	selection, _, selected := repository_process_test_select_remote(&before, "origin")
	configuration, configured := repository_process_test_push_configuration(&before, selection, allocator)
	request, prepared := repository_process_test_push_request(&before, configuration, Push_Operation_ID(51))
	testing.expect(t, selected && configured && prepared)
	if !selected || !configured || !prepared do return
	destination := request.precondition.destination.branch
	testing.expect_value(t, ref_name_string(&destination), "refs/heads/main")
	testing.expect_value(t, request.precondition.destination.remote, configuration.remote)
	process, started, start_failure := repository_process_start_push(
		&before,
		configuration,
		.Normal,
		request,
		1,
		allocator,
	)
	testing.expectf(t, started, "push process failed to start with %v", start_failure)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	result, result_opened, result_failure := repository_process_take_push(&process, allocator)
	testing.expectf(t, result_opened, "push result failed with %v", result_failure)
	repository_process_close(&process)
	if !result_opened do return
	descriptor, described := push_result_descriptor(&result)
	testing.expect(t, described && descriptor.started && descriptor.transport_succeeded && !descriptor.verified)
	testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Refreshing)
	after, ready = repository_process_test_refs(repository, Ref_Generation(52), allocator)
	testing.expect(t, ready)
	if ready {
		verified, verify_failure := push_result_verify(&result, &after)
		testing.expectf(t, verified, "push verification failed with %v", verify_failure)
		descriptor, described = push_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded && descriptor.verified)
		testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Completed)
		local_after, local_found := repository_process_test_find_ref(&after, "refs/heads/main")
		tracking_after, tracking_found := repository_process_test_find_ref(&after, "refs/remotes/origin/main")
		testing.expect(t, local_found && tracking_found && local_after.object == tracking_after.object)
	}
	push_result_close(&result)

	selection, _, selected = repository_process_test_select_remote(&after, "origin")
	configuration, configured = repository_process_test_push_configuration(&after, selection, allocator)
	drift_request, drift_prepared := repository_process_test_push_request(&after, configuration, Push_Operation_ID(52))
	ready = os.write_entire_file(path, "baseline\nlocal publication\nsource drift\n") == nil &&
	        repository_process_test_run(local_directory, "git", "add", "--", "push.txt") &&
	        repository_process_test_run(local_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "source drift")
	testing.expect(t, selected && configured && drift_prepared && ready)
	if !selected || !configured || !drift_prepared || !ready do return
	drift_process, drift_started, drift_start_failure := repository_process_start_push(
		&after,
		configuration,
		.Normal,
		drift_request,
		1,
		allocator,
	)
	testing.expectf(t, drift_started, "drift process failed to start with %v", drift_start_failure)
	if drift_started {
		drift_poll := repository_process_test_wait(&drift_process)
		testing.expect_value(t, drift_poll.state, Repository_Process_State.Failed)
		testing.expect_value(t, drift_poll.failure, Failure_Code.Stale_Observation)
		_, drift_opened, drift_failure := repository_process_take_push(&drift_process, allocator)
		testing.expect(t, !drift_opened && drift_failure == .Stale_Observation)
		repository_process_close(&drift_process)
	}

	drifted, ready = repository_process_test_refs(repository, Ref_Generation(53), allocator)
	testing.expect(t, ready)
	if !ready do return
	selection, _, selected = repository_process_test_select_remote(&drifted, "origin")
	testing.expect(t, repository_process_test_run(local_directory, "git", "remote", "set-url", "--push", "origin", missing_directory))
	rejected_configuration, rejected_configured := repository_process_test_push_configuration(&drifted, selection, allocator)
	rejected_request, rejected_prepared := repository_process_test_push_request(
		&drifted,
		rejected_configuration,
		Push_Operation_ID(53),
	)
	testing.expect(t, selected && rejected_configured && rejected_prepared)
	if !selected || !rejected_configured || !rejected_prepared do return
	rejected_process, rejected_started, rejected_start_failure := repository_process_start_push(
		&drifted,
		rejected_configuration,
		.Normal,
		rejected_request,
		1,
		allocator,
	)
	testing.expectf(t, rejected_started, "rejected process failed to start with %v", rejected_start_failure)
	if rejected_started {
		rejected_poll := repository_process_test_wait(&rejected_process)
		testing.expect_value(t, rejected_poll.state, Repository_Process_State.Failed)
		rejected_result, rejected_opened, rejected_failure := repository_process_take_push(&rejected_process, allocator)
		testing.expectf(t, rejected_opened, "rejected result failed with %v", rejected_failure)
		if rejected_opened {
			descriptor, described = push_result_descriptor(&rejected_result)
			testing.expect(t, described && descriptor.started && !descriptor.transport_succeeded && descriptor.refresh_required)
			testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Refreshing)
			rejected, ready = repository_process_test_refs(repository, Ref_Generation(54), allocator)
			if ready {
				_, _ = push_result_verify(&rejected_result, &rejected)
				descriptor, described = push_result_descriptor(&rejected_result)
				testing.expect(t, described && !descriptor.succeeded)
				testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Failed)
			}
			push_result_close(&rejected_result)
		}
		repository_process_close(&rejected_process)
	}

	testing.expect(t, repository_process_test_run(local_directory, "git", "remote", "set-url", "--push", "origin", remote_directory))
	selection, _, selected = repository_process_test_select_remote(&drifted, "origin")
	cancel_configuration, cancel_configured := repository_process_test_push_configuration(&drifted, selection, allocator)
	cancel_request, cancel_prepared := repository_process_test_push_request(
		&drifted,
		cancel_configuration,
		Push_Operation_ID(54),
	)
	testing.expect(t, selected && cancel_configured && cancel_prepared)
	if !selected || !cancel_configured || !cancel_prepared do return
	cancel_process, cancel_started, cancel_start_failure := repository_process_start_push(
		&drifted,
		cancel_configuration,
		.Normal,
		cancel_request,
		1,
		allocator,
	)
	testing.expectf(t, cancel_started, "cancel process failed to start with %v", cancel_start_failure)
	if cancel_started {
		testing.expect(t, repository_process_cancel(&cancel_process))
		cancel_result, cancel_opened, cancel_failure := repository_process_take_push(&cancel_process, allocator)
		testing.expectf(t, cancel_opened, "cancel result failed with %v", cancel_failure)
		if cancel_opened {
			descriptor, described = push_result_descriptor(&cancel_result)
			testing.expect(t, described && !descriptor.started && !descriptor.refresh_required)
			testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Cancelled)
			push_result_close(&cancel_result)
		}
		repository_process_close(&cancel_process)
	}
}

/* Verifies local branch mutation rechecks temporary-repository truth and releases every retained result. */
@(test)
repository_process_checks_local_branch_lifecycle_before_mutation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-branch-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	work_directory, work_error := os.join_path({directory, "work"}, context.allocator)
	testing.expect(t, work_error == nil)
	if work_error != nil do return
	defer delete(work_directory)
	path, path_error := os.join_path({work_directory, "branch.txt"}, context.allocator)
	unmerged_path, unmerged_path_error := os.join_path({work_directory, "unmerged.txt"}, context.allocator)
	dirty_path, dirty_path_error := os.join_path({work_directory, "dirty.txt"}, context.allocator)
	lock_path, lock_path_error := os.join_path({work_directory, ".git/refs/heads/locked.lock"}, context.allocator)
	testing.expect(t, path_error == nil && unmerged_path_error == nil && dirty_path_error == nil && lock_path_error == nil)
	if path_error != nil || unmerged_path_error != nil || dirty_path_error != nil || lock_path_error != nil do return
	defer delete(path)
	defer delete(unmerged_path)
	defer delete(dirty_path)
	defer delete(lock_path)
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main", work_directory) &&
	         repository_process_test_run(work_directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(work_directory, "git", "config", "user.email", "odra@example.invalid") &&
	         os.write_entire_file(path, "baseline\n") == nil &&
	         repository_process_test_run(work_directory, "git", "add", "--", "branch.txt") &&
	         repository_process_test_run(work_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "baseline") &&
	         repository_process_test_run(work_directory, "git", "branch", "topic") &&
	         os.write_entire_file(path, "baseline\nmain\n") == nil &&
	         repository_process_test_run(work_directory, "git", "add", "--", "branch.txt") &&
	         repository_process_test_run(work_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "main update") &&
	         repository_process_test_run(work_directory, "git", "switch", "-q", "-c", "unmerged") &&
	         os.write_entire_file(unmerged_path, "unmerged\n") == nil &&
	         repository_process_test_run(work_directory, "git", "add", "--", "unmerged.txt") &&
	         repository_process_test_run(work_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "unmerged update") &&
	         repository_process_test_run(work_directory, "git", "switch", "-q", "main")
	testing.expect(t, ready)
	if !ready do return

	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, work_directory))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	status: Status_Observation
	refs: Ref_Observation
	defer {
		if status.state != nil do status_observation_close(&status)
		if refs.state != nil do ref_observation_close(&refs)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	status_ready: bool
	refs_ready: bool
	status, status_ready = repository_process_test_observe(repository, Observation_Generation(81), allocator)
	refs, refs_ready = repository_process_test_refs(repository, Ref_Generation(81), allocator)
	testing.expect(t, status_ready && refs_ready)
	if !status_ready || !refs_ready do return
	main, main_found := repository_process_test_find_ref(&refs, "refs/heads/main")
	topic, topic_found := repository_process_test_find_ref(&refs, "refs/heads/topic")
	unmerged, unmerged_found := repository_process_test_find_ref(&refs, "refs/heads/unmerged")
	testing.expect(t, main_found && topic_found && unmerged_found)
	if !main_found || !topic_found || !unmerged_found do return

	_, current_ready, current_failure := branch_precondition_prepare(
		&status,
		&refs,
		{},
		{operation = .Delete, selected = main, require_merged_to_head = true},
	)
	testing.expect(t, !current_ready && current_failure == .Action_Unavailable)

	dirty_request, dirty_ready, dirty_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Switch, selected = topic},
		Branch_Operation_ID(81),
	)
	testing.expectf(t, dirty_ready, "dirty switch request failed with %v", dirty_failure)
	if !dirty_ready do return
	testing.expect(t, os.write_entire_file(dirty_path, "dirty\n") == nil)
	dirty_process, dirty_started, dirty_start_failure := repository_process_start_branch(
		&status,
		&refs,
		{},
		dirty_request,
		1,
		allocator,
	)
	testing.expectf(t, dirty_started, "dirty switch process failed to start with %v", dirty_start_failure)
	if dirty_started {
		dirty_poll := repository_process_test_wait(&dirty_process)
		testing.expect_value(t, dirty_poll.state, Repository_Process_State.Failed)
		testing.expect_value(t, dirty_poll.failure, Failure_Code.Action_Unavailable)
		_, dirty_opened, dirty_result_failure := repository_process_take_branch(&dirty_process, allocator)
		testing.expect(t, !dirty_opened && dirty_result_failure == .Action_Unavailable)
		repository_process_close(&dirty_process)
	}
	testing.expect(t, os.remove(dirty_path) == nil)

	unmerged_request, unmerged_ready, unmerged_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Delete, selected = unmerged, require_merged_to_head = true},
		Branch_Operation_ID(82),
	)
	testing.expectf(t, unmerged_ready, "unmerged delete request failed with %v", unmerged_failure)
	if unmerged_ready {
		unmerged_process, unmerged_started, unmerged_start_failure := repository_process_start_branch(
			&status, &refs, {}, unmerged_request, 1, allocator,
		)
		testing.expectf(t, unmerged_started, "unmerged delete process failed to start with %v", unmerged_start_failure)
		if unmerged_started {
			unmerged_poll := repository_process_test_wait(&unmerged_process)
			testing.expect_value(t, unmerged_poll.state, Repository_Process_State.Failed)
			testing.expect_value(t, unmerged_poll.failure, Failure_Code.Action_Unavailable)
			_, unmerged_opened, unmerged_result_failure := repository_process_take_branch(&unmerged_process, allocator)
			testing.expect(t, !unmerged_opened && unmerged_result_failure == .Action_Unavailable)
			repository_process_close(&unmerged_process)
		}
	}

	stale_request, stale_ready, stale_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Switch, selected = topic},
		Branch_Operation_ID(83),
	)
	testing.expectf(t, stale_ready, "stale switch request failed with %v", stale_failure)
	if stale_ready {
		testing.expect(t, repository_process_test_run(work_directory, "git", "branch", "-f", "topic", "unmerged"))
		stale_process, stale_started, stale_start_failure := repository_process_start_branch(
			&status, &refs, {}, stale_request, 1, allocator,
		)
		testing.expectf(t, stale_started, "stale switch process failed to start with %v", stale_start_failure)
		if stale_started {
			stale_poll := repository_process_test_wait(&stale_process)
			testing.expect_value(t, stale_poll.state, Repository_Process_State.Failed)
			testing.expect_value(t, stale_poll.failure, Failure_Code.Stale_Observation)
			_, stale_opened, stale_result_failure := repository_process_take_branch(&stale_process, allocator)
			testing.expect(t, !stale_opened && stale_result_failure == .Stale_Observation)
			repository_process_close(&stale_process)
		}
		testing.expect(t, repository_process_test_run(work_directory, "git", "branch", "-f", "topic", "main~1"))
	}

	cancelled_name: Local_Branch_Name
	testing.expect(t, local_branch_name_assign(&cancelled_name, "cancelled"))
	cancelled_request, cancelled_ready, cancelled_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Create, name = cancelled_name},
		Branch_Operation_ID(84),
	)
	testing.expectf(t, cancelled_ready, "cancelled create request failed with %v", cancelled_failure)
	if cancelled_ready {
		cancelled_process, cancelled_started, cancelled_start_failure := repository_process_start_branch(
			&status, &refs, {}, cancelled_request, 1, allocator,
		)
		testing.expectf(t, cancelled_started, "cancelled create process failed to start with %v", cancelled_start_failure)
		if cancelled_started {
			testing.expect(t, repository_process_cancel(&cancelled_process))
			cancelled_result, cancelled_opened, cancelled_result_failure := repository_process_take_branch(
				&cancelled_process,
				allocator,
			)
			testing.expectf(t, cancelled_opened, "cancelled create result failed with %v", cancelled_result_failure)
			if cancelled_opened {
				descriptor, described := branch_result_descriptor(&cancelled_result)
				testing.expect(t, described && !descriptor.started && !descriptor.refresh_required)
				testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Cancelled)
				branch_result_close(&cancelled_result)
			}
			repository_process_close(&cancelled_process)
		}
	}

	locked_name: Local_Branch_Name
	testing.expect(t, local_branch_name_assign(&locked_name, "locked"))
	locked_request, locked_ready, locked_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Create, name = locked_name},
		Branch_Operation_ID(85),
	)
	testing.expectf(t, locked_ready, "locked create request failed with %v", locked_failure)
	if locked_ready {
		testing.expect(t, os.write_entire_file(lock_path, "locked\n") == nil)
		locked_process, locked_started, locked_start_failure := repository_process_start_branch(
			&status, &refs, {}, locked_request, 1, allocator,
		)
		testing.expectf(t, locked_started, "locked create process failed to start with %v", locked_start_failure)
		if locked_started {
			locked_poll := repository_process_test_wait(&locked_process)
			testing.expect_value(t, locked_poll.state, Repository_Process_State.Failed)
			locked_result, locked_opened, locked_result_failure := repository_process_take_branch(&locked_process, allocator)
			testing.expectf(t, locked_opened, "locked create result failed with %v", locked_result_failure)
			if locked_opened {
				descriptor, described := branch_result_descriptor(&locked_result)
				testing.expect(t, described && descriptor.started && !descriptor.process_succeeded)
				testing.expect_value(t, descriptor.failure, Failure_Code.Process_Failed)
				fresh_status, fresh_status_opened := repository_process_test_observe(
					repository, Observation_Generation(82), allocator,
				)
				fresh_refs, fresh_refs_opened := repository_process_test_refs(
					repository, Ref_Generation(82), allocator,
				)
				testing.expect(t, fresh_status_opened && fresh_refs_opened)
				if fresh_status_opened && fresh_refs_opened {
					_, _ = branch_result_verify(&locked_result, &fresh_status, &fresh_refs)
					descriptor, described = branch_result_descriptor(&locked_result)
					testing.expect(t, described && descriptor.verified && !descriptor.succeeded)
					testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Failed)
				}
				if fresh_status.state != nil do status_observation_close(&fresh_status)
				if fresh_refs.state != nil do ref_observation_close(&fresh_refs)
				branch_result_close(&locked_result)
			}
			repository_process_close(&locked_process)
		}
		testing.expect(t, os.remove(lock_path) == nil)
	}

	created_name: Local_Branch_Name
	testing.expect(t, local_branch_name_assign(&created_name, "created"))
	created_request, created_ready, created_failure := repository_process_test_branch_request(
		&status,
		&refs,
		{operation = .Create, name = created_name},
		Branch_Operation_ID(86),
	)
	testing.expectf(t, created_ready, "create request failed with %v", created_failure)
	if created_ready {
		created_process, created_started, created_start_failure := repository_process_start_branch(
			&status, &refs, {}, created_request, 1, allocator,
		)
		testing.expectf(t, created_started, "create process failed to start with %v", created_start_failure)
		if created_started {
			created_poll := repository_process_test_wait(&created_process)
			testing.expect_value(t, created_poll.state, Repository_Process_State.Completed)
			created_result, created_opened, created_result_failure := repository_process_take_branch(
				&created_process,
				allocator,
			)
			testing.expectf(t, created_opened, "create result failed with %v", created_result_failure)
			if created_opened {
				fresh_status, fresh_status_opened := repository_process_test_observe(
					repository, Observation_Generation(83), allocator,
				)
				fresh_refs, fresh_refs_opened := repository_process_test_refs(
					repository, Ref_Generation(83), allocator,
				)
				testing.expect(t, fresh_status_opened && fresh_refs_opened)
				if fresh_status_opened && fresh_refs_opened {
					verified, verify_failure := branch_result_verify(&created_result, &fresh_status, &fresh_refs)
					testing.expectf(t, verified, "created branch verification failed with %v", verify_failure)
					descriptor, described := branch_result_descriptor(&created_result)
					testing.expect(t, described && descriptor.verified && descriptor.succeeded)
					testing.expect_value(t, branch_feedback(descriptor), Branch_Feedback.Completed)
					_, found := repository_process_test_find_ref(&fresh_refs, "refs/heads/created")
					testing.expect(t, found)
				}
				if fresh_status.state != nil do status_observation_close(&fresh_status)
				if fresh_refs.state != nil do ref_observation_close(&fresh_refs)
				branch_result_close(&created_result)
			}
			repository_process_close(&created_process)
		}
	}
}

/* Verifies checked local tag creation and deletion against live temporary-repository truth. */
@(test)
repository_process_checks_local_tag_lifecycle_before_mutation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-tag-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		_ = os.remove_all(directory)
		delete(directory)
	}
	work_directory, work_error := os.join_path({directory, "work"}, context.allocator)
	remote_directory, remote_error := os.join_path({directory, "origin.git"}, context.allocator)
	path, path_error := os.join_path({work_directory, "tag.txt"}, context.allocator)
	lock_path, lock_error := os.join_path({work_directory, ".git/refs/tags/locked.lock"}, context.allocator)
	testing.expect(t, work_error == nil && remote_error == nil && path_error == nil && lock_error == nil)
	if work_error != nil || remote_error != nil || path_error != nil || lock_error != nil do return
	defer delete(work_directory)
	defer delete(remote_directory)
	defer delete(path)
	defer delete(lock_path)
	ready := repository_process_test_run(directory, "git", "init", "-q", "-b", "main", work_directory) &&
	         repository_process_test_run(work_directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(work_directory, "git", "config", "user.email", "odra@example.invalid") &&
	         os.write_entire_file(path, "baseline\n") == nil &&
	         repository_process_test_run(work_directory, "git", "add", "--", "tag.txt") &&
	         repository_process_test_run(work_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "baseline") &&
	         repository_process_test_run(directory, "git", "init", "--bare", "-q", "--initial-branch=main", remote_directory) &&
	         repository_process_test_run(work_directory, "git", "remote", "add", "origin", remote_directory) &&
	         repository_process_test_run(work_directory, "git", "push", "-q", "-u", "origin", "main") &&
	         repository_process_test_run(work_directory, "git", "tag", "existing") &&
	         repository_process_test_run(work_directory, "git", "push", "-q", "origin", "refs/tags/existing")
	testing.expect(t, ready)
	if !ready do return

	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, work_directory))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	status: Status_Observation
	refs: Ref_Observation
	defer {
		if status.state != nil do status_observation_close(&status)
		if refs.state != nil do ref_observation_close(&refs)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	status_ready: bool
	refs_ready: bool
	status, status_ready = repository_process_test_observe(repository, Observation_Generation(91), allocator)
	refs, refs_ready = repository_process_test_refs(repository, Ref_Generation(91), allocator)
	testing.expect(t, status_ready && refs_ready)
	if !status_ready || !refs_ready do return
	main, main_found := repository_process_test_find_ref(&refs, "refs/heads/main")
	existing, existing_found := repository_process_test_find_ref(&refs, "refs/tags/existing")
	testing.expect(t, main_found && existing_found)
	if !main_found || !existing_found do return

	invalid_name: Local_Tag_Name
	testing.expect(t, !local_tag_name_assign(&invalid_name, "invalid..tag"))
	existing_name: Local_Tag_Name
	testing.expect(t, local_tag_name_assign(&existing_name, "existing"))
	_, duplicate_ready, duplicate_failure := tag_precondition_prepare(
		&status,
		&refs,
		{operation = .Create, target = main, name = existing_name},
	)
	testing.expect(t, !duplicate_ready && duplicate_failure == .Target_Duplicate)

	stale_name: Local_Tag_Name
	testing.expect(t, local_tag_name_assign(&stale_name, "stale"))
	stale_request, stale_ready, stale_failure := repository_process_test_tag_request(
		&status,
		&refs,
		{operation = .Create, target = main, name = stale_name},
		Tag_Operation_ID(91),
	)
	testing.expectf(t, stale_ready, "stale tag request failed with %v", stale_failure)
	if stale_ready {
		testing.expect(t, os.write_entire_file(path, "baseline\nchanged\n") == nil)
		testing.expect(t, repository_process_test_run(work_directory, "git", "add", "--", "tag.txt"))
		testing.expect(t, repository_process_test_run(work_directory, "git", "-c", "commit.gpgSign=false", "commit", "-qm", "move target"))
		stale_process, stale_started, stale_start_failure := repository_process_start_tag(
			&status, &refs, stale_request, 1, allocator,
		)
		testing.expectf(t, stale_started, "stale tag process failed to start with %v", stale_start_failure)
		if stale_started {
			stale_poll := repository_process_test_wait(&stale_process)
			testing.expect_value(t, stale_poll.state, Repository_Process_State.Failed)
			testing.expect_value(t, stale_poll.failure, Failure_Code.Stale_Observation)
			_, stale_opened, stale_result_failure := repository_process_take_tag(&stale_process, allocator)
			testing.expect(t, !stale_opened && stale_result_failure == .Stale_Observation)
			repository_process_close(&stale_process)
		}
	}
	status_observation_close(&status)
	ref_observation_close(&refs)
	status, status_ready = repository_process_test_observe(repository, Observation_Generation(92), allocator)
	refs, refs_ready = repository_process_test_refs(repository, Ref_Generation(92), allocator)
	testing.expect(t, status_ready && refs_ready)
	if !status_ready || !refs_ready do return
	main, main_found = repository_process_test_find_ref(&refs, "refs/heads/main")
	existing, existing_found = repository_process_test_find_ref(&refs, "refs/tags/existing")
	testing.expect(t, main_found && existing_found)
	if !main_found || !existing_found do return

	cancelled_name: Local_Tag_Name
	testing.expect(t, local_tag_name_assign(&cancelled_name, "cancelled"))
	cancelled_request, cancelled_ready, cancelled_failure := repository_process_test_tag_request(
		&status,
		&refs,
		{operation = .Create, target = main, name = cancelled_name},
		Tag_Operation_ID(92),
	)
	testing.expectf(t, cancelled_ready, "cancelled tag request failed with %v", cancelled_failure)
	if cancelled_ready {
		cancelled_process, cancelled_started, cancelled_start_failure := repository_process_start_tag(
			&status, &refs, cancelled_request, 1, allocator,
		)
		testing.expectf(t, cancelled_started, "cancelled tag process failed to start with %v", cancelled_start_failure)
		if cancelled_started {
			testing.expect(t, repository_process_cancel(&cancelled_process))
			cancelled_result, cancelled_opened, cancelled_result_failure := repository_process_take_tag(
				&cancelled_process,
				allocator,
			)
			testing.expectf(t, cancelled_opened, "cancelled tag result failed with %v", cancelled_result_failure)
			if cancelled_opened {
				descriptor, described := tag_result_descriptor(&cancelled_result)
				testing.expect(t, described && !descriptor.started && !descriptor.refresh_required)
				testing.expect_value(t, tag_feedback(descriptor), Tag_Feedback.Cancelled)
				tag_result_close(&cancelled_result)
			}
			repository_process_close(&cancelled_process)
		}
	}

	locked_name: Local_Tag_Name
	testing.expect(t, local_tag_name_assign(&locked_name, "locked"))
	locked_request, locked_ready, locked_failure := repository_process_test_tag_request(
		&status,
		&refs,
		{operation = .Create, target = main, name = locked_name},
		Tag_Operation_ID(93),
	)
	testing.expectf(t, locked_ready, "locked tag request failed with %v", locked_failure)
	if locked_ready {
		testing.expect(t, os.write_entire_file(lock_path, "locked\n") == nil)
		locked_process, locked_started, locked_start_failure := repository_process_start_tag(
			&status, &refs, locked_request, 1, allocator,
		)
		testing.expectf(t, locked_started, "locked tag process failed to start with %v", locked_start_failure)
		if locked_started {
			locked_poll := repository_process_test_wait(&locked_process)
			testing.expect_value(t, locked_poll.state, Repository_Process_State.Failed)
			locked_result, locked_opened, locked_result_failure := repository_process_take_tag(&locked_process, allocator)
			testing.expectf(t, locked_opened, "locked tag result failed with %v", locked_result_failure)
			if locked_opened {
				fresh_refs, fresh_ready := repository_process_test_refs(repository, Ref_Generation(93), allocator)
				testing.expect(t, fresh_ready)
				if fresh_ready {
					_, _ = tag_result_verify(&locked_result, &fresh_refs)
					descriptor, described := tag_result_descriptor(&locked_result)
					testing.expect(t, described && descriptor.verified && !descriptor.succeeded)
					testing.expect_value(t, tag_feedback(descriptor), Tag_Feedback.Failed)
					ref_observation_close(&fresh_refs)
				}
				tag_result_close(&locked_result)
			}
			repository_process_close(&locked_process)
		}
		testing.expect(t, os.remove(lock_path) == nil)
	}

	created_name: Local_Tag_Name
	testing.expect(t, local_tag_name_assign(&created_name, "created"))
	created_request, created_ready, created_failure := repository_process_test_tag_request(
		&status,
		&refs,
		{operation = .Create, target = main, name = created_name},
		Tag_Operation_ID(94),
	)
	testing.expectf(t, created_ready, "create tag request failed with %v", created_failure)
	if !created_ready do return
	created_process, created_started, created_start_failure := repository_process_start_tag(
		&status, &refs, created_request, 1, allocator,
	)
	testing.expectf(t, created_started, "create tag process failed to start with %v", created_start_failure)
	if !created_started do return
	created_poll := repository_process_test_wait(&created_process)
	testing.expect_value(t, created_poll.state, Repository_Process_State.Completed)
	created_result, created_opened, created_result_failure := repository_process_take_tag(&created_process, allocator)
	testing.expectf(t, created_opened, "create tag result failed with %v", created_result_failure)
	repository_process_close(&created_process)
	if !created_opened do return
	fresh_refs, fresh_ready := repository_process_test_refs(repository, Ref_Generation(94), allocator)
	testing.expect(t, fresh_ready)
	if !fresh_ready {
		tag_result_close(&created_result)
		return
	}
	verified, verify_failure := tag_result_verify(&created_result, &fresh_refs)
	testing.expectf(t, verified, "created tag verification failed with %v", verify_failure)
	created_descriptor, created_described := tag_result_descriptor(&created_result)
	testing.expect(t, created_described && created_descriptor.verified && created_descriptor.succeeded)
	testing.expect_value(t, tag_feedback(created_descriptor), Tag_Feedback.Completed)
	created, created_found := repository_process_test_find_ref(&fresh_refs, "refs/tags/created")
	testing.expect(t, created_found && created.object == main.object)
	testing.expect(t, !repository_process_test_run(
		work_directory, "git", "--git-dir", remote_directory, "show-ref", "--verify", "--quiet", "refs/tags/created",
	))
	tag_result_close(&created_result)
	ref_observation_close(&refs)
	refs = fresh_refs
	existing, existing_found = repository_process_test_find_ref(&refs, "refs/tags/existing")
	testing.expect(t, existing_found)
	if !existing_found do return

	delete_precondition, delete_ready, delete_failure := tag_precondition_prepare(
		&status,
		&refs,
		{operation = .Delete, target = existing},
	)
	testing.expectf(t, delete_ready, "delete tag precondition failed with %v", delete_failure)
	if !delete_ready do return
	delete_confirmation, confirmation_ready, confirmation_failure := tag_confirmation_prepare(
		delete_precondition,
		Tag_Confirmation_ID(95),
	)
	testing.expectf(t, confirmation_ready, "delete tag confirmation failed with %v", confirmation_failure)
	if !confirmation_ready do return
	_, unconfirmed_ready, unconfirmed_failure := tag_request_prepare(
		delete_precondition,
		Tag_Operation_ID(95),
		&delete_confirmation,
	)
	testing.expect(t, !unconfirmed_ready && unconfirmed_failure == .Confirmation_Required)
	confirmed, confirm_failure := tag_confirmation_confirm(&delete_confirmation, delete_confirmation.id)
	testing.expectf(t, confirmed, "delete tag confirmation was rejected with %v", confirm_failure)
	if !confirmed do return
	delete_request, request_ready, request_failure := tag_request_prepare(
		delete_precondition,
		Tag_Operation_ID(95),
		&delete_confirmation,
	)
	testing.expectf(t, request_ready, "delete tag request failed with %v", request_failure)
	if !request_ready do return
	delete_process, delete_started, delete_start_failure := repository_process_start_tag(
		&status, &refs, delete_request, 1, allocator,
	)
	testing.expectf(t, delete_started, "delete tag process failed to start with %v", delete_start_failure)
	if !delete_started do return
	delete_poll := repository_process_test_wait(&delete_process)
	testing.expect_value(t, delete_poll.state, Repository_Process_State.Completed)
	delete_result, delete_opened, delete_result_failure := repository_process_take_tag(&delete_process, allocator)
	testing.expectf(t, delete_opened, "delete tag result failed with %v", delete_result_failure)
	repository_process_close(&delete_process)
	if !delete_opened do return
	deleted_refs, deleted_ready := repository_process_test_refs(repository, Ref_Generation(95), allocator)
	testing.expect(t, deleted_ready)
	if deleted_ready {
		verified, verify_failure = tag_result_verify(&delete_result, &deleted_refs)
		testing.expectf(t, verified, "deleted tag verification failed with %v", verify_failure)
		delete_descriptor, delete_described := tag_result_descriptor(&delete_result)
		testing.expect(t, delete_described && delete_descriptor.verified && delete_descriptor.succeeded)
		testing.expect_value(t, tag_feedback(delete_descriptor), Tag_Feedback.Completed)
		_, still_found := repository_process_test_find_ref(&deleted_refs, "refs/tags/existing")
		testing.expect(t, !still_found)
		ref_observation_close(&deleted_refs)
	}
	testing.expect(t, repository_process_test_run(
		work_directory, "git", "--git-dir", remote_directory, "show-ref", "--verify", "--quiet", "refs/tags/existing",
	))
	tag_result_close(&delete_result)
}
