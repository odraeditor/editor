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

/* Runs one short fixture command and reports its exit result. */
sequence_process_run :: proc(directory: string, command: ..string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	return process_error == nil && state.exited && state.success
}

/* Polls one bounded production sequence process to a terminal state. */
sequence_process_wait :: proc(
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

/* Opens one immutable sequence observation through the production process owner. */
sequence_process_observe :: proc(
	repository: ksawery.Repository_Context,
	generation: ksawery.Sequence_Generation,
) -> (ksawery.Sequence_Observation, bool, ksawery.Failure_Code) {
	process, started, failure := ksawery.repository_process_start_sequence_observation(repository, 1)
	if !started do return {}, false, failure
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	if poll.state != .Completed do return {}, false, poll.failure
	return ksawery.repository_process_take_sequence(&process, generation)
}

/* Creates one committed repository with deterministic local identity. */
sequence_process_repository :: proc(t: ^testing.T) -> (string, ksawery.Repository_Context, bool) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-sequence-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return "", {}, false
	ok := sequence_process_run(directory, "git", "init", "-q", "-b", "main") &&
		sequence_process_run(directory, "git", "config", "user.name", "Odra Test") &&
		sequence_process_run(directory, "git", "config", "user.email", "odra@example.invalid")
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	if path_error != nil {
		os.remove_all(directory)
		delete(directory)
		return "", {}, false
	}
	ok = ok && os.write_entire_file(path, "base\n") == nil &&
		sequence_process_run(directory, "git", "add", "conflict.txt") &&
		sequence_process_run(directory, "git", "commit", "-q", "-m", "base")
	delete(path)
	repository: ksawery.Repository_Context
	ok = ok && ksawery.repository_context_assign(&repository, directory)
	return directory, repository, ok
}

/* Verifies a clean repository is reconstructed as an inactive external observation. */
@(test)
sequence_process_observes_normal_repository :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	observation, observed, failure := sequence_process_observe(repository, ksawery.Sequence_Generation(20))
	testing.expectf(t, observed, "normal sequence observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Inactive)
	testing.expect_value(t, descriptor.kind, ksawery.Sequence_Kind.None)
	testing.expect_value(t, descriptor.origin, ksawery.Sequence_Origin.External)
	testing.expect(t, ksawery.revision_identity_is_valid(descriptor.current))
}

/* Verifies a real external merge conflict is reconstructed with exact target and index stages. */
@(test)
sequence_process_adopts_external_merge_conflict :: proc(t: ^testing.T) {
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
	testing.expect(t, !sequence_process_run(directory, "git", "merge", "side"))
	observation, observed, failure := sequence_process_observe(repository, ksawery.Sequence_Generation(21))
	testing.expectf(t, observed, "merge sequence observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.kind, ksawery.Sequence_Kind.Merge)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Conflicted)
	testing.expect(t, ksawery.revision_identity_is_valid(descriptor.current))
	testing.expect(t, ksawery.revision_identity_is_valid(descriptor.target))
	testing.expect_value(t, descriptor.conflict_count, u32(1))
	conflict, found := ksawery.sequence_observation_conflict(&observation, 0)
	testing.expect(t, found)
	for stage in conflict.stages do testing.expect(t, stage.available)
}

/* Verifies a real external rebase exposes determinate progress from Git metadata. */
@(test)
sequence_process_observes_rebase_progress :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	path, path_error := os.join_path({directory, "conflict.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	ready = sequence_process_run(directory, "git", "checkout", "-q", "-b", "topic") &&
		os.write_entire_file(path, "topic\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "topic") &&
		sequence_process_run(directory, "git", "checkout", "-q", "main") &&
		os.write_entire_file(path, "main\n") == nil &&
		sequence_process_run(directory, "git", "commit", "-qam", "main") &&
		sequence_process_run(directory, "git", "checkout", "-q", "topic")
	testing.expect(t, ready)
	if !ready do return
	testing.expect(t, !sequence_process_run(directory, "git", "rebase", "main"))
	observation, observed, failure := sequence_process_observe(repository, ksawery.Sequence_Generation(23))
	testing.expectf(t, observed, "rebase sequence observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.kind, ksawery.Sequence_Kind.Rebase)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Conflicted)
	testing.expect(t, descriptor.step.position > 0)
	testing.expect(t, descriptor.step.total >= descriptor.step.position)
	testing.expect(t, ksawery.revision_identity_is_valid(descriptor.target))
}

/* Verifies an externally started manual bisect is adopted as exact read-only sequence state. */
@(test)
sequence_process_adopts_external_manual_bisect :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	bad_copy := bad
	good_copy := good
	testing.expect(t, sequence_process_run(
		directory,
		"git",
		"bisect",
		"start",
		ksawery.revision_identity_string(&bad_copy),
		ksawery.revision_identity_string(&good_copy),
	))
	observation, observed, failure := sequence_process_observe(repository, ksawery.Sequence_Generation(24))
	testing.expectf(t, observed, "external bisect observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.kind, ksawery.Sequence_Kind.Bisect)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Active)
	testing.expect_value(t, descriptor.origin, ksawery.Sequence_Origin.External)
	testing.expect(t, ksawery.revision_identity_is_valid(descriptor.current))
}

/* Verifies malformed sequence identity metadata fails instead of publishing guessed state. */
@(test)
sequence_process_rejects_malformed_marker :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	marker, marker_error := os.join_path({directory, ".git/MERGE_HEAD"}, context.allocator)
	testing.expect(t, marker_error == nil)
	if marker_error != nil do return
	defer delete(marker)
	testing.expect(t, os.write_entire_file(marker, "not-an-object\n") == nil)
	process, started, failure := ksawery.repository_process_start_sequence_observation(repository, 1)
	testing.expectf(t, started, "malformed marker process failed to start with %v", failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Parse)
}

/* Verifies incompatible live markers are exposed as unsupported instead of guessed. */
@(test)
sequence_process_reports_ambiguous_markers :: proc(t: ^testing.T) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	git_directory, path_error := os.join_path({directory, ".git"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(git_directory)
	merge_head, merge_error := os.join_path({git_directory, "MERGE_HEAD"}, context.allocator)
	bisect_log, bisect_error := os.join_path({git_directory, "BISECT_LOG"}, context.allocator)
	testing.expect(t, merge_error == nil && bisect_error == nil)
	if merge_error != nil || bisect_error != nil {
		if merge_error == nil do delete(merge_head)
		if bisect_error == nil do delete(bisect_log)
		return
	}
	defer delete(merge_head)
	defer delete(bisect_log)
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = {"git", "rev-parse", "HEAD"}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	ready = process_error == nil && state.exited && state.success &&
		os.write_entire_file(merge_head, stdout) == nil && os.write_entire_file(bisect_log, "synthetic\n") == nil
	testing.expect(t, ready)
	if !ready do return
	observation, observed, failure := sequence_process_observe(repository, ksawery.Sequence_Generation(22))
	testing.expectf(t, observed, "ambiguous sequence observation failed with %v", failure)
	if !observed do return
	defer ksawery.sequence_observation_close(&observation)
	descriptor, described := ksawery.sequence_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.kind, ksawery.Sequence_Kind.Other)
	testing.expect_value(t, descriptor.state, ksawery.Sequence_Observation_State.Unsupported)
}
