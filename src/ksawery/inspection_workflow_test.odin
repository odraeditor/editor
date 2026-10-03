// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:os"
import "core:testing"

@(private)
inspection_test_request :: proc(
	family: Inspection_Family,
	action: Inspection_Action,
) -> Inspection_Request {
	repository: Repository_Context
	_ = repository_context_assign(&repository, "/work/inspection")
	return {
		repository = repository,
		observation_generation = 7,
		family = family,
		action = action,
		limits = DEFAULT_PROCESS_LIMITS,
	}
}

@(private)
inspection_test_observe_family :: proc(
	status: ^Status_Observation,
	request: Inspection_Request,
	generation: Inspection_Generation,
	family_observation: ^Inspection_Observation = nil,
) -> (Inspection_Observation, bool, Failure_Code) {
	process, started, failure := repository_process_start_inspection_workflow(
		status, request, 1, context.allocator, family_observation,
	)
	if !started do return {}, false, failure
	defer repository_process_close(&process)
	poll := repository_process_test_wait(&process)
	if poll.state != .Completed do return {}, false, poll.failure
	return repository_process_take_inspection_observation(&process, generation)
}

/* Verifies each family admits only its closed operation and argument shapes. */
@(test)
inspection_workflow_requests_are_family_scoped_and_confirmed :: proc(t: ^testing.T) {
	stash := inspection_test_request(.Stash, .List)
	testing.expect(t, inspection_request_is_valid(stash))
	stash.action = .Create
	testing.expect(t, !inspection_request_is_valid(stash))
	testing.expect(t, inspection_text_assign(&stash.target, "Odra checkpoint"))
	testing.expect(t, !inspection_request_is_valid(stash))
	stash.family_generation = 3
	stash.confirmed = true
	testing.expect(t, inspection_request_is_valid(stash))
	stash.action = .Apply
	testing.expect(t, !inspection_request_is_valid(stash))
	testing.expect(t, inspection_text_assign(&stash.evidence, "1111111111111111111111111111111111111111"))
	testing.expect(t, inspection_request_is_valid(stash))

	worktree := inspection_test_request(.Worktree, .Create)
	worktree.family_generation = 3
	testing.expect(t, inspection_text_assign(&worktree.target, "/work/topic"))
	testing.expect(t, inspection_text_assign(&worktree.secondary, "topic"))
	worktree.confirmed = true
	testing.expect(t, inspection_request_is_valid(worktree))
	worktree.family = .Blame
	testing.expect(t, !inspection_request_is_valid(worktree))

	blame := inspection_test_request(.Blame, .Inspect)
	testing.expect(t, inspection_text_assign(&blame.target, "src/main.odin"))
	testing.expect(t, inspection_request_is_valid(blame))
	blame.confirmed = true
	testing.expect(t, !inspection_request_is_valid(blame))

	reflog := inspection_test_request(.Reflog, .Visit)
	reflog.family_generation = 3
	testing.expect(t, inspection_text_assign(&reflog.target, "1111111111111111111111111111111111111111"))
	testing.expect(t, inspection_request_is_valid(reflog))
}

/* Verifies stash and reflog output retain semantic identities instead of row positions. */
@(test)
inspection_workflow_parses_triplet_observations :: proc(t: ^testing.T) {
	request := inspection_test_request(.Stash, .List)
	text := "stash@{0}\x001111111111111111111111111111111111111111\x00WIP on main\x00stash@{1}\x002222222222222222222222222222222222222222\x00older\x00"
	output := transmute([]u8)text
	observation, opened, failure := inspection_observation_open(request, 3, output)
	testing.expectf(t, opened, "stash observation failed with %v", failure)
	if !opened do return
	defer inspection_observation_close(&observation)
	descriptor, described := inspection_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.item_count, 2)
	item, found := inspection_observation_item(&observation, 0)
	testing.expect(t, found)
	testing.expect_value(t, inspection_text_string(&item.identity), "stash@{0}")
	testing.expect_value(t, inspection_text_string(&item.summary), "WIP on main")
	target, targeted := inspection_observation_target(&observation, 0)
	testing.expect(t, targeted && inspection_target_is_current(target, descriptor))
	stale := descriptor
	stale.generation += 1
	testing.expect(t, !inspection_target_is_current(target, stale))
}

/* Verifies worktree porcelain retains path, branch, and checked HEAD separately. */
@(test)
inspection_workflow_parses_worktree_porcelain :: proc(t: ^testing.T) {
	request := inspection_test_request(.Worktree, .List)
	text := "worktree /work/main\x00HEAD 1111111111111111111111111111111111111111\x00branch refs/heads/main\x00\x00worktree /work/topic\x00HEAD 2222222222222222222222222222222222222222\x00detached\x00\x00"
	output := transmute([]u8)text
	observation, opened, failure := inspection_observation_open(request, 4, output)
	testing.expectf(t, opened, "worktree observation failed with %v", failure)
	if !opened do return
	defer inspection_observation_close(&observation)
	descriptor, described := inspection_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.item_count, 2)
	second, found := inspection_observation_item(&observation, 1)
	testing.expect(t, found)
	testing.expect_value(t, inspection_text_string(&second.identity), "/work/topic")
	testing.expect_value(t, inspection_text_string(&second.summary), "detached")
}

/* Verifies blame output is bounded into exact revision-backed chunks. */
@(test)
inspection_workflow_parses_blame_chunks :: proc(t: ^testing.T) {
	request := inspection_test_request(.Blame, .Inspect)
	testing.expect(t, inspection_text_assign(&request.target, "src/main.odin"))
	text := "1111111111111111111111111111111111111111 1 1 2\nauthor Ada\n\tfirst\n2222222222222222222222222222222222222222 3 3 1\nauthor Grace\n\tsecond\n"
	output := transmute([]u8)text
	observation, opened, failure := inspection_observation_open(request, 5, output)
	testing.expectf(t, opened, "blame observation failed with %v", failure)
	if !opened do return
	defer inspection_observation_close(&observation)
	descriptor, described := inspection_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.item_count, 2)
}

/* Verifies each read-only family crosses the real bounded Git process boundary. */
@(test)
inspection_workflow_observes_real_repository_families :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-inspection-*", context.allocator)
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
	path, path_error := os.join_path({directory, "inspection.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	ready = os.write_entire_file(path, "first\n") == nil &&
	        repository_process_test_run(directory, "git", "add", "inspection.txt") &&
	        repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "root") &&
	        os.write_entire_file(path, "second\n") == nil &&
	        repository_process_test_run(directory, "git", "stash", "push", "-q", "-m", "checkpoint")
	testing.expect(t, ready)
	if !ready do return
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	status, observed := repository_process_test_observe(repository, Observation_Generation(19))
	testing.expect(t, observed)
	if !observed do return
	defer status_observation_close(&status)

	requests := [4]Inspection_Request {
		{
			repository = repository,
			observation_generation = 19,
			family = .Stash,
			action = .List,
			limits = DEFAULT_PROCESS_LIMITS,
		},
		{
			repository = repository,
			observation_generation = 19,
			family = .Worktree,
			action = .List,
			limits = DEFAULT_PROCESS_LIMITS,
		},
		{
			repository = repository,
			observation_generation = 19,
			family = .Blame,
			action = .Inspect,
			limits = DEFAULT_PROCESS_LIMITS,
		},
		{
			repository = repository,
			observation_generation = 19,
			family = .Reflog,
			action = .List,
			limits = DEFAULT_PROCESS_LIMITS,
		},
	}
	testing.expect(t, inspection_text_assign(&requests[2].target, "inspection.txt"))
	for request, index in requests {
		observation, opened, failure := inspection_test_observe_family(
			&status,
			request,
			Inspection_Generation(index + 1),
		)
		testing.expectf(t, opened, "%v observation failed with %v", request.family, failure)
		if !opened do continue
		descriptor, described := inspection_observation_descriptor(&observation)
		testing.expect(t, described && descriptor.item_count > 0)
		if described && descriptor.item_count > 0 && request.family == .Stash {
			item, found := inspection_observation_item(&observation, 0)
			testing.expect(t, found)
			if found {
				inspect := Inspection_Request {
					repository = repository,
					observation_generation = 19,
					family_generation = descriptor.generation,
					family = .Stash,
					action = .Inspect,
					target = item.identity,
					evidence = item.secondary,
					limits = DEFAULT_PROCESS_LIMITS,
				}
				process, started, start_failure := repository_process_start_inspection_workflow(
					&status, inspect, 1, context.allocator, &observation,
				)
				testing.expectf(t, started, "stash inspection start failed with %v", start_failure)
				if started {
					poll := repository_process_test_wait(&process)
					testing.expect_value(t, poll.state, Repository_Process_State.Completed)
					detail_observation, detail_opened, detail_failure :=
						repository_process_take_inspection_observation(&process, 20)
					testing.expectf(t, detail_opened, "stash detail failed with %v", detail_failure)
					if detail_opened {
						_, available := inspection_observation_detail(&detail_observation)
						testing.expect(t, available)
						inspection_observation_close(&detail_observation)
					}
					repository_process_close(&process)
				}
			}
		} else if described && descriptor.item_count > 0 && request.family == .Worktree {
			item, found := inspection_observation_item(&observation, 0)
			testing.expect(t, found)
			if found {
				visit := Inspection_Request {
					repository = repository,
					observation_generation = 19,
					family_generation = descriptor.generation,
					family = .Worktree,
					action = .Visit,
					target = item.identity,
					evidence = item.secondary,
					limits = DEFAULT_PROCESS_LIMITS,
				}
				visited, visit_opened, visit_failure := inspection_test_observe_family(
					&status, visit, 21, &observation,
				)
				testing.expectf(t, visit_opened, "worktree visit failed with %v", visit_failure)
				if visit_opened do inspection_observation_close(&visited)
			}
		}
		inspection_observation_close(&observation)
	}
}
