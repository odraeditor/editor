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

/* Verifies generated confirmed-discard processes reap children and release every owner. */
@(test)
discard_process_sequences_refresh_and_release :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-process-sequence-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "notes.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	ready := repository_process_test_run(directory, "git", "init", "-q") &&
	         repository_process_test_run(directory, "git", "config", "user.name", "Odra Test") &&
	         repository_process_test_run(directory, "git", "config", "user.email", "odra@example.invalid")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, os.write_entire_file(path, "baseline\n") == nil)
	ready = repository_process_test_run(directory, "git", "add", "--", "notes.txt") &&
	        repository_process_test_run(directory, "git", "commit", "-qm", "baseline")
	testing.expect(t, ready)
	if !ready do return
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, directory))

	for sequence in 0 ..< 16 {
		content := fmt.tprintf("working %d\n", sequence)
		testing.expect(t, os.write_entire_file(path, content) == nil)
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		generation := Observation_Generation(sequence * 2 + 1)
		observation, observed := repository_process_test_observe(repository, generation, allocator)
		testing.expectf(t, observed, "generated process observation %d failed", sequence)
		if !observed {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		selection, selected := repository_process_test_select_group(&observation, .Unstaged)
		testing.expect(t, selected)
		request, prepared, prepare_failure := discard_action_prepare(
			&observation,
			selection,
			Index_Operation_ID(sequence + 1),
			Discard_Confirmation_ID(sequence + 1),
			false,
		)
		testing.expectf(t, prepared, "generated process discard %d failed with %v", sequence, prepare_failure)
		if !prepared {
			status_observation_close(&observation)
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		confirmed, confirm_failure := discard_action_confirm(
			&request,
			Discard_Confirmation_ID(sequence + 1),
		)
		testing.expectf(t, confirmed, "generated process confirmation %d failed with %v", sequence, confirm_failure)
		process, started, start_failure := repository_process_start_discard_action(
			&observation,
			request,
			false,
			1,
			allocator,
		)
		testing.expectf(t, started, "generated discard process %d failed with %v", sequence, start_failure)
		if started {
			poll := repository_process_test_wait(&process)
			testing.expect_value(t, poll.state, Repository_Process_State.Completed)
			result, opened, result_failure := repository_process_take_discard_action(&process, allocator)
			testing.expectf(t, opened, "generated discard outcome %d failed with %v", sequence, result_failure)
			if opened {
				descriptor, described := discard_action_result_descriptor(&result)
				testing.expect(t, described && descriptor.succeeded)
				discard_action_result_close(&result)
			}
			repository_process_close(&process)
		}

		refreshed, refreshed_ok := repository_process_test_observe(repository, generation + 1, allocator)
		testing.expectf(t, refreshed_ok, "generated process refresh %d failed", sequence)
		if refreshed_ok {
			reconciled, reconciled_ok, reconcile_failure := status_selection_reconcile(
				&observation,
				&refreshed,
				selection,
			)
			testing.expectf(t, reconciled_ok, "generated process reconciliation %d failed with %v", sequence, reconcile_failure)
			if reconciled_ok do testing.expect_value(t, reconciled.generation, generation + 1)
			status_observation_close(&refreshed)
		}
		status_observation_close(&observation)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
		testing.expect(t, repository_process_test_run(directory, "git", "diff", "--quiet"))
	}
}
