// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:bytes"
import "core:os"
import "core:testing"

@(private)
grouped_index_action_test_count :: proc(content, wanted: []u8) -> u32 {
	if len(wanted) == 0 || len(wanted) > len(content) do return 0
	count: u32
	for index in 0 ..< len(content) - len(wanted) + 1 {
		if bytes.equal(content[index:index + len(wanted)], wanted) do count += 1
	}
	return count
}

/* Verifies path groups own NUL pathspecs and hunk groups own one ordered patch. */
@(test)
grouped_index_actions_own_exact_group_input :: proc(t: ^testing.T) {
	observation, opened := semantic_test_observation(
		Observation_Generation(401),
		"# branch.head main\x00? new.txt\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
	)
	testing.expect(t, opened)
	if !opened do return
	grouped, group_opened, _ := grouped_selection_open(&observation)
	testing.expect(t, group_opened)
	if !group_opened {
		status_observation_close(&observation)
		return
	}
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next)
	marked, _ := grouped_selection_mark(&observation, nil, selection, &grouped)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	second_marked, _ := grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expect(t, selected && marked && second_marked)
	request, prepared, failure := grouped_index_action_prepare(
		&observation,
		nil,
		&grouped,
		Index_Operation_ID(401),
	)
	testing.expectf(t, prepared, "path group request failed with %v", failure)
	if prepared {
		descriptor, described := grouped_index_action_request_descriptor(&request)
		input, copied := grouped_index_action_request_input(&request)
		testing.expect(t, described && copied)
		testing.expect_value(t, descriptor.input_kind, Grouped_Input_Kind.Pathspec)
		testing.expect_value(t, string(input), "new.txt\x00edited.txt\x00")
		refreshed, refreshed_opened := semantic_test_observation(
			Observation_Generation(402),
			"# branch.head main\x00? new.txt\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
		)
		testing.expect(t, refreshed_opened)
		if refreshed_opened {
			current, stale_failure := grouped_index_action_request_revalidate(
				&refreshed,
				nil,
				&grouped,
				&request,
			)
			testing.expect(t, !current)
			testing.expect_value(t, stale_failure, Failure_Code.Stale_Observation)
			status_observation_close(&refreshed)
		}
		result, result_opened, result_failure := grouped_index_action_result_open(
			descriptor,
			1,
			transmute([]u8)(string("partial output")),
			transmute([]u8)(string("ambiguous failure")),
			.Process_Failed,
		)
		testing.expectf(t, result_opened, "grouped failure result failed with %v", result_failure)
		if result_opened {
			result_descriptor, result_described := grouped_index_action_result_descriptor(&result)
			usage, measured := grouped_index_action_result_usage(&result)
			testing.expect(t, result_described && !result_descriptor.succeeded)
			testing.expect_value(t, result_descriptor.failure, Failure_Code.Process_Failed)
			testing.expect(t, measured && usage.output_bytes > 0 && usage.diagnostic_bytes > 0)
			grouped_index_action_result_close(&result)
		}
		grouped_index_action_request_close(&request)
	}
	grouped_selection_close(&grouped)
	status_observation_close(&observation)

	hunk_observation, detail, document, hunk, ready := partial_index_action_test_state(.Unstaged)
	testing.expect(t, ready)
	if !ready do return
	defer partial_index_action_test_close(&hunk_observation, &detail, &document)
	hunk_group, hunk_group_opened, _ := grouped_selection_open(&hunk_observation)
	testing.expect(t, hunk_group_opened)
	if !hunk_group_opened do return
	defer grouped_selection_close(&hunk_group)
	first_marked, _ := grouped_selection_mark(&hunk_observation, &document, hunk, &hunk_group)
	hunk, selected, _ = status_selection_move(&hunk_observation, hunk, .Next, &document)
	second_hunk_marked, _ := grouped_selection_mark(&hunk_observation, &document, hunk, &hunk_group)
	testing.expect(t, selected && first_marked && second_hunk_marked)
	hunk_request, hunk_prepared, hunk_failure := grouped_index_action_prepare(
		&hunk_observation,
		&document,
		&hunk_group,
		Index_Operation_ID(402),
	)
	testing.expectf(t, hunk_prepared, "hunk group request failed with %v", hunk_failure)
	if hunk_prepared {
		descriptor, described := grouped_index_action_request_descriptor(&hunk_request)
		input, copied := grouped_index_action_request_input(&hunk_request)
		testing.expect(t, described && copied)
		testing.expect_value(t, descriptor.input_kind, Grouped_Input_Kind.Patch)
		testing.expect_value(
			t,
			grouped_index_action_test_count(input, transmute([]u8)(string("diff --git "))),
			u32(1),
		)
		testing.expect_value(
			t,
			grouped_index_action_test_count(input, transmute([]u8)(string("@@ -"))),
			u32(2),
		)
		grouped_index_action_request_close(&hunk_request)
	}
}

/* Verifies one bounded pathspec process stages and unstages two paths together. */
@(test)
repository_process_applies_complete_path_group :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-path-group-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	testing.expect(t, repository_process_test_run(directory, "git", "init", "-q"))
	first_path, first_error := os.join_path({directory, "first.txt"}, context.allocator)
	second_path, second_error := os.join_path({directory, "second.txt"}, context.allocator)
	testing.expect(t, first_error == nil && second_error == nil)
	if first_error != nil || second_error != nil do return
	defer delete(first_path)
	defer delete(second_path)
	testing.expect(t, os.write_entire_file(first_path, "first\n") == nil)
	testing.expect(t, os.write_entire_file(second_path, "second\n") == nil)
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))
	observation, observed := repository_process_test_observe(repository, Observation_Generation(403))
	testing.expect(t, observed)
	if !observed do return
	grouped, opened, _ := grouped_selection_open(&observation)
	testing.expect(t, opened)
	if !opened {
		status_observation_close(&observation)
		return
	}
	selection, selected := status_selection_begin(&observation)
	if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next)
	first_marked, _ := grouped_selection_mark(&observation, nil, selection, &grouped)
	selection, selected, _ = status_selection_move(&observation, selection, .Next)
	second_marked, _ := grouped_selection_mark(&observation, nil, selection, &grouped)
	testing.expect(t, selected && first_marked && second_marked)
	request, prepared, failure := grouped_index_action_prepare(
		&observation,
		nil,
		&grouped,
		Index_Operation_ID(403),
	)
	testing.expectf(t, prepared, "real path group failed with %v", failure)
	if !prepared {
		grouped_selection_close(&grouped)
		status_observation_close(&observation)
		return
	}
	process, started, start_failure := repository_process_start_grouped_index_action(
		&observation,
		nil,
		&grouped,
		&request,
		1,
	)
	testing.expectf(t, started, "path group process failed with %v", start_failure)
	grouped_index_action_request_close(&request)
	grouped_selection_close(&grouped)
	status_observation_close(&observation)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	result, result_opened, result_failure := repository_process_take_grouped_index_action(&process)
	testing.expectf(t, result_opened, "path group result failed with %v", result_failure)
	if result_opened {
		descriptor, described := grouped_index_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		grouped_index_action_result_close(&result)
	}
	repository_process_close(&process)
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))

	staged, staged_observed := repository_process_test_observe(repository, Observation_Generation(404))
	testing.expect(t, staged_observed)
	if !staged_observed do return
	staged_group, staged_opened, _ := grouped_selection_open(&staged)
	testing.expect(t, staged_opened)
	if !staged_opened {
		status_observation_close(&staged)
		return
	}
	staged_selection, staged_selected := status_selection_begin(&staged)
	if staged_selected {
		staged_selection, staged_selected, _ = status_selection_move(&staged, staged_selection, .Next)
	}
	first_unstage_marked, _ := grouped_selection_mark(&staged, nil, staged_selection, &staged_group)
	staged_selection, staged_selected, _ = status_selection_move(&staged, staged_selection, .Next)
	second_unstage_marked, _ := grouped_selection_mark(&staged, nil, staged_selection, &staged_group)
	testing.expect(t, staged_selected && first_unstage_marked && second_unstage_marked)
	unstage, unstage_prepared, unstage_failure := grouped_index_action_prepare(
		&staged,
		nil,
		&staged_group,
		Index_Operation_ID(404),
	)
	testing.expectf(t, unstage_prepared, "real path unstage group failed with %v", unstage_failure)
	if !unstage_prepared {
		grouped_selection_close(&staged_group)
		status_observation_close(&staged)
		return
	}
	unstage_process, unstage_started, unstage_start_failure := repository_process_start_grouped_index_action(
		&staged,
		nil,
		&staged_group,
		&unstage,
		1,
	)
	testing.expectf(t, unstage_started, "path group unstage process failed with %v", unstage_start_failure)
	grouped_index_action_request_close(&unstage)
	grouped_selection_close(&staged_group)
	status_observation_close(&staged)
	if !unstage_started do return
	unstage_poll := repository_process_test_wait(&unstage_process)
	testing.expect_value(t, unstage_poll.state, Repository_Process_State.Completed)
	unstage_result, unstage_result_opened, unstage_result_failure := repository_process_take_grouped_index_action(
		&unstage_process,
	)
	testing.expectf(t, unstage_result_opened, "path group unstage result failed with %v", unstage_result_failure)
	if unstage_result_opened {
		descriptor, described := grouped_index_action_result_descriptor(&unstage_result)
		testing.expect(t, described && descriptor.succeeded)
		grouped_index_action_result_close(&unstage_result)
	}
	repository_process_close(&unstage_process)
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--quiet"))
	testing.expect(t, !repository_process_test_run(directory, "git", "ls-files", "--error-unmatch", "first.txt"))
	testing.expect(t, !repository_process_test_run(directory, "git", "ls-files", "--error-unmatch", "second.txt"))
}

/* Verifies one ordered patch process stages and unstages every marked hunk. */
@(test)
repository_process_applies_same_path_hunk_group :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-hunk-group-*", context.allocator)
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
	observation, observed := repository_process_test_observe(repository, Observation_Generation(405))
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
	grouped, grouped_opened, _ := grouped_selection_open(&observation)
	testing.expect(t, grouped_opened)
	if !grouped_opened {
		partial_index_action_test_close(&observation, &detail, &document)
		return
	}
	first_marked, _ := grouped_selection_mark(&observation, &document, selection, &grouped)
	selection, selected, _ = status_selection_move(&observation, selection, .Next, &document)
	second_marked, _ := grouped_selection_mark(&observation, &document, selection, &grouped)
	testing.expect(t, selected && first_marked && second_marked)
	stage, stage_prepared, stage_failure := grouped_index_action_prepare(
		&observation,
		&document,
		&grouped,
		Index_Operation_ID(405),
	)
	testing.expectf(t, stage_prepared, "real hunk group failed with %v", stage_failure)
	if !stage_prepared {
		grouped_selection_close(&grouped)
		partial_index_action_test_close(&observation, &detail, &document)
		return
	}
	process, started, start_failure := repository_process_start_grouped_index_action(
		&observation,
		&document,
		&grouped,
		&stage,
		1,
	)
	testing.expectf(t, started, "hunk group stage process failed with %v", start_failure)
	grouped_index_action_request_close(&stage)
	grouped_selection_close(&grouped)
	partial_index_action_test_close(&observation, &detail, &document)
	if !started do return
	poll := repository_process_test_wait(&process)
	testing.expect_value(t, poll.state, Repository_Process_State.Completed)
	result, result_opened, result_failure := repository_process_take_grouped_index_action(&process)
	testing.expectf(t, result_opened, "hunk group stage result failed with %v", result_failure)
	if result_opened {
		descriptor, described := grouped_index_action_result_descriptor(&result)
		testing.expect(t, described && descriptor.succeeded)
		grouped_index_action_result_close(&result)
	}
	repository_process_close(&process)
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--quiet"))

	staged, staged_observed := repository_process_test_observe(repository, Observation_Generation(406))
	testing.expect(t, staged_observed)
	if !staged_observed do return
	staged_selection, staged_selected := repository_process_test_select_group(&staged, .Staged)
	testing.expect(t, staged_selected)
	if !staged_selected {
		status_observation_close(&staged)
		return
	}
	staged_detail, staged_document, staged_detailed := repository_process_test_diff_document(&staged, staged_selection)
	testing.expect(t, staged_detailed)
	if !staged_detailed {
		status_observation_close(&staged)
		return
	}
	staged_selection, staged_selected, _ = status_selection_move(&staged, staged_selection, .Next, &staged_document)
	staged_group, staged_group_opened, _ := grouped_selection_open(&staged)
	testing.expect(t, staged_group_opened)
	if !staged_group_opened {
		partial_index_action_test_close(&staged, &staged_detail, &staged_document)
		return
	}
	first_unstage_marked, _ := grouped_selection_mark(&staged, &staged_document, staged_selection, &staged_group)
	staged_selection, staged_selected, _ = status_selection_move(&staged, staged_selection, .Next, &staged_document)
	second_unstage_marked, _ := grouped_selection_mark(&staged, &staged_document, staged_selection, &staged_group)
	testing.expect(t, staged_selected && first_unstage_marked && second_unstage_marked)
	unstage, unstage_prepared, unstage_failure := grouped_index_action_prepare(
		&staged,
		&staged_document,
		&staged_group,
		Index_Operation_ID(406),
	)
	testing.expectf(t, unstage_prepared, "real hunk unstage group failed with %v", unstage_failure)
	if !unstage_prepared {
		grouped_selection_close(&staged_group)
		partial_index_action_test_close(&staged, &staged_detail, &staged_document)
		return
	}
	unstage_process, unstage_started, unstage_start_failure := repository_process_start_grouped_index_action(
		&staged,
		&staged_document,
		&staged_group,
		&unstage,
		1,
	)
	testing.expectf(t, unstage_started, "hunk group unstage process failed with %v", unstage_start_failure)
	grouped_index_action_request_close(&unstage)
	grouped_selection_close(&staged_group)
	partial_index_action_test_close(&staged, &staged_detail, &staged_document)
	if !unstage_started do return
	unstage_poll := repository_process_test_wait(&unstage_process)
	testing.expect_value(t, unstage_poll.state, Repository_Process_State.Completed)
	unstage_result, unstage_result_opened, unstage_result_failure := repository_process_take_grouped_index_action(
		&unstage_process,
	)
	testing.expectf(t, unstage_result_opened, "hunk group unstage result failed with %v", unstage_result_failure)
	if unstage_result_opened {
		descriptor, described := grouped_index_action_result_descriptor(&unstage_result)
		testing.expect(t, described && descriptor.succeeded)
		grouped_index_action_result_close(&unstage_result)
	}
	repository_process_close(&unstage_process)
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	testing.expect(t, !repository_process_test_run(directory, "git", "diff", "--quiet"))
}
