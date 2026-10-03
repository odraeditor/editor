// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:os"
import "core:testing"

@(private)
revision_detail_test_repository :: proc() -> (Repository_Context, bool) {
	repository: Repository_Context
	return repository, repository_context_assign(&repository, "/work/revision-detail")
}

@(private)
revision_detail_test_request :: proc() -> (Revision_Detail_Request, bool) {
	parent, parent_assigned := history_test_identity(HISTORY_TEST_SHA1)
	target, target_assigned := history_test_identity(HISTORY_TEST_SHA256)
	if !parent_assigned || !target_assigned do return {}, false
	return Revision_Detail_Request {
		target = {generation = History_Generation(41), revision = target},
		parent = {kind = .Parent, parent = parent},
		limits = DEFAULT_REVISION_DETAIL_LIMITS,
	}, true
}

@(private)
revision_detail_test_metadata :: proc() -> []u8 {
	return transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 +
		"\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00" +
		"\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00" +
		"\x00child\x00child body\n\x00N\x00\x00\n",
	))
}

@(private)
revision_detail_test_comparison :: proc() -> []u8 {
	return transmute([]u8)(string(
		":100644 100644 0000000000000000000000000000000000000000 " +
		"1111111111111111111111111111111111111111 M\x00src/example.odin\x00\x00" +
		"diff --git a/src/example.odin b/src/example.odin\n" +
		"index 0000000..1111111 100644\n--- a/src/example.odin\n+++ b/src/example.odin\n" +
		"@@ -0,0 +1 @@\n+package example\n",
	))
}

/* Verifies one exact detail retains bounded metadata, changed paths, and explicit-parent diff bytes. */
@(test)
revision_detail_parses_exact_metadata_and_parent_comparison :: proc(t: ^testing.T) {
	repository, repository_ready := revision_detail_test_repository()
	request, prepared := revision_detail_test_request()
	testing.expect(t, repository_ready && prepared)
	if !repository_ready || !prepared do return
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	detail, opened, failure := revision_detail_open(
		repository,
		request,
		revision_detail_test_metadata(),
		revision_detail_test_comparison(),
		false,
		allocator,
	)
	testing.expectf(t, opened, "revision detail failed with %v", failure)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	descriptor, described := revision_detail_descriptor(&detail)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.target, request.target)
		testing.expect_value(t, descriptor.parent, request.parent)
		testing.expect_value(t, descriptor.parent_count, u8(1))
		testing.expect_value(t, descriptor.changed_paths, u32(1))
		testing.expect(t, !descriptor.truncated)
		message, copied := revision_detail_text(&detail, descriptor.message)
		testing.expect(t, copied)
		if copied do testing.expect_value(t, string(message), "child body\n")
		path, found := revision_detail_changed_path(&detail, 0)
		testing.expect(t, found)
		if found {
			testing.expect_value(t, path.kind, Revision_Change_Kind.Modified)
			path_text, path_copied := revision_detail_changed_path_text(&detail, path.path)
			testing.expect(t, path_copied)
			if path_copied do testing.expect_value(t, string(path_text), "src/example.odin")
		}
		diff, diff_available := revision_detail_diff(&detail)
		testing.expect(t, diff_available && revision_bytes_have_prefix(diff, transmute([]u8)(string("diff --git "))))
		usage, measured := revision_detail_usage(&detail)
		testing.expect(t, measured)
		if measured {
			inspection := Revision_Inspection_Request{kind = .Detail, detail = request}
			testing.expect(t, revision_inspection_usage_is_valid(usage, inspection))
		}
	}
	revision_detail_close(&detail)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies a truncated comparison preserves complete metadata while withholding incomplete path and diff material. */
@(test)
revision_detail_allows_truncated_comparison_without_partial_path_claims :: proc(t: ^testing.T) {
	repository, repository_ready := revision_detail_test_repository()
	request, prepared := revision_detail_test_request()
	testing.expect(t, repository_ready && prepared)
	if !repository_ready || !prepared do return
	detail, opened, failure := revision_detail_open(
		repository,
		request,
		revision_detail_test_metadata(),
		transmute([]u8)(string(":100644 100644")),
		true,
	)
	testing.expectf(t, opened, "truncated revision detail failed with %v", failure)
	if !opened do return
	defer revision_detail_close(&detail)
	descriptor, described := revision_detail_descriptor(&detail)
	testing.expect(t, described)
	if described {
		testing.expect(t, descriptor.truncated)
		testing.expect_value(t, descriptor.changed_paths, u32(0))
		testing.expect_value(t, descriptor.diff_bytes, u64(0))
	}
}

/* Verifies ordered range observations retain exact summary identities and rename source paths. */
@(test)
revision_range_observations_parse_summaries_and_changed_paths :: proc(t: ^testing.T) {
	repository, repository_ready := revision_detail_test_repository()
	base, base_assigned := history_test_identity(HISTORY_TEST_SHA1)
	target, target_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, repository_ready && base_assigned && target_assigned)
	if !repository_ready || !base_assigned || !target_assigned do return
	request := Revision_Range_Request {
		range = {
			base = {generation = History_Generation(41), revision = base},
			target = {generation = History_Generation(41), revision = target},
		},
		limits = DEFAULT_REVISION_RANGE_LIMITS,
	}
	summary := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00child\x00\n" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00root\x00\n",
	))
	comparison := transmute([]u8)(string(
		":100644 100644 0000000000000000000000000000000000000000 " +
		"1111111111111111111111111111111111111111 R100\x00old.odin\x00new.odin\x00\x00" +
		"diff --git a/old.odin b/new.odin\n",
	))
	observation, opened, failure := revision_range_observation_open(
		repository,
		request,
		summary,
		comparison,
		false,
	)
	testing.expectf(t, opened, "range observation failed with %v", failure)
	if !opened do return
	defer revision_range_observation_close(&observation)
	descriptor, described := revision_range_observation_descriptor(&observation)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.revision_count, u32(2))
		testing.expect_value(t, descriptor.changed_paths, u32(1))
	}
	path, found := revision_range_observation_changed_path(&observation, 0)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, path.kind, Revision_Change_Kind.Renamed)
		old_path, copied := revision_range_observation_changed_path_text(&observation, path.original_path)
		testing.expect(t, copied)
		if copied do testing.expect_value(t, string(old_path), "old.odin")
	}
}

/* Verifies the checked process owner acquires and parses real exact-revision and range data. */
@(test)
revision_processes_observe_real_details_and_ranges :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-revision-*", context.allocator)
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
	path, path_error := os.join_path({directory, "revision.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	first_written := os.write_entire_file(path, "first\n") == nil
	first_committed := first_written && repository_process_test_run(directory, "git", "add", "revision.txt") &&
	                   repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "root")
	second_written := first_committed && os.write_entire_file(path, "second\n") == nil
	second_committed := second_written && repository_process_test_run(directory, "git", "add", "revision.txt") &&
	                    repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "child")
	testing.expect(t, second_committed)
	if !second_committed do return
	repository: Repository_Context
	observed := repository_context_assign(&repository, directory)
	testing.expect(t, observed)
	if !observed do return
	history_request := Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = DEFAULT_HISTORY_LIMITS},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	history_process, history_started, history_failure := repository_process_start(history_request, 1)
	testing.expectf(t, history_started, "history start failed with %v", history_failure)
	if !history_started do return
	defer repository_process_close(&history_process)
	history_poll := repository_process_test_wait(&history_process)
	testing.expect_value(t, history_poll.state, Repository_Process_State.Completed)
	if history_poll.state != .Completed do return
	history, history_opened, history_open_failure := repository_process_take_history(
		&history_process,
		History_Generation(51),
	)
	testing.expectf(t, history_opened, "history parse failed with %v", history_open_failure)
	if !history_opened do return
	defer history_observation_close(&history)
	child, child_found := history_observation_revision(&history, 0)
	testing.expect(t, child_found && child.parent_count == 1)
	if !child_found || child.parent_count != 1 do return
	detail_request := Revision_Detail_Request {
		target = {generation = History_Generation(51), revision = child.identity},
		parent = {kind = .Parent, parent = child.parents[0]},
		limits = DEFAULT_REVISION_DETAIL_LIMITS,
	}
	metadata_process, metadata_started, metadata_failure := repository_process_start_revision_detail_metadata(
		&history,
		detail_request,
		1,
	)
	testing.expectf(t, metadata_started, "detail metadata start failed with %v", metadata_failure)
	if !metadata_started do return
	defer repository_process_close(&metadata_process)
	metadata_poll := repository_process_test_wait(&metadata_process)
	testing.expectf(t, metadata_poll.state == .Completed, "metadata process failed with %v", metadata_poll.failure)
	if metadata_poll.state != .Completed {
		diagnostic, available := repository_process_diagnostic(&metadata_process)
		if available do testing.expectf(t, false, "metadata diagnostic: %s", string(diagnostic))
		return
	}
	comparison_process, comparison_started, comparison_failure := repository_process_start_revision_detail_comparison(
		&history,
		detail_request,
		1,
	)
	testing.expectf(t, comparison_started, "detail comparison start failed with %v", comparison_failure)
	if !comparison_started do return
	defer repository_process_close(&comparison_process)
	comparison_poll := repository_process_test_wait(&comparison_process)
	testing.expect_value(t, comparison_poll.state, Repository_Process_State.Completed)
	if comparison_poll.state != .Completed do return
	metadata, metadata_available := repository_process_output(&metadata_process)
	comparison, comparison_available := repository_process_output(&comparison_process)
	testing.expect(t, metadata_available && comparison_available)
	if !metadata_available || !comparison_available do return
	detail, detail_opened, detail_failure := revision_detail_open(
		repository,
		detail_request,
		metadata,
		comparison,
		false,
	)
	testing.expectf(t, detail_opened, "detail parse failed with %v", detail_failure)
	if !detail_opened do return
	defer revision_detail_close(&detail)
	detail_descriptor, detail_described := revision_detail_descriptor(&detail)
	testing.expect(t, detail_described)
	if detail_described {
		testing.expect_value(t, detail_descriptor.target.revision, child.identity)
		testing.expect_value(t, detail_descriptor.changed_paths, u32(1))
		testing.expect(t, detail_descriptor.diff_bytes > 0)
	}

	range_request := Revision_Range_Request {
		range = {
			base = {generation = History_Generation(51), revision = child.parents[0]},
			target = {generation = History_Generation(51), revision = child.identity},
		},
		limits = DEFAULT_REVISION_RANGE_LIMITS,
	}
	summary_process, summary_started, summary_failure := repository_process_start_revision_range_summary(
		&history,
		range_request,
		1,
	)
	testing.expectf(t, summary_started, "range summary start failed with %v", summary_failure)
	if !summary_started do return
	defer repository_process_close(&summary_process)
	summary_poll := repository_process_test_wait(&summary_process)
	testing.expect_value(t, summary_poll.state, Repository_Process_State.Completed)
	if summary_poll.state != .Completed do return
	range_comparison_process, range_comparison_started, range_comparison_failure :=
		repository_process_start_revision_range_comparison(&history, range_request, 1)
	testing.expectf(t, range_comparison_started, "range comparison start failed with %v", range_comparison_failure)
	if !range_comparison_started do return
	defer repository_process_close(&range_comparison_process)
	range_comparison_poll := repository_process_test_wait(&range_comparison_process)
	testing.expect_value(t, range_comparison_poll.state, Repository_Process_State.Completed)
	if range_comparison_poll.state != .Completed do return
	summary, summary_available := repository_process_output(&summary_process)
	range_comparison, range_comparison_available := repository_process_output(&range_comparison_process)
	testing.expect(t, summary_available && range_comparison_available)
	if !summary_available || !range_comparison_available do return
	range, range_opened, range_failure := revision_range_observation_open(
		repository,
		range_request,
		summary,
		range_comparison,
		false,
	)
	testing.expectf(t, range_opened, "range parse failed with %v", range_failure)
	if !range_opened do return
	defer revision_range_observation_close(&range)
	range_descriptor, range_described := revision_range_observation_descriptor(&range)
	testing.expect(t, range_described)
	if range_described {
		testing.expect(t, range_descriptor.revision_count > 0)
		testing.expect_value(t, range_descriptor.changed_paths, u32(1))
		testing.expect(t, range_descriptor.diff_bytes > 0)
	}
}

/* Verifies bounded revision-process output remains parseable as an explicitly truncated read-only detail. */
@(test)
revision_processes_expose_truncated_comparison_output_without_mutation :: proc(t: ^testing.T) {
	directory, directory_error := os.make_directory_temp("", "odra-ksawery-revision-truncated-*", context.allocator)
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
	path, path_error := os.join_path({directory, "large.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	root_committed := os.write_entire_file(path, "root\n") == nil &&
	                  repository_process_test_run(directory, "git", "add", "large.txt") &&
	                  repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "root")
	testing.expect(t, root_committed)
	if !root_committed do return
	large, allocation_error := make([dynamic]u8, 0, int(MIN_REVISION_DETAIL_DIFF_BYTES) + int(32 * KIBIBYTE), context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(large)
	for _ in 0 ..< int(MIN_REVISION_DETAIL_DIFF_BYTES) / 2 + int(16 * KIBIBYTE) {
		append(&large, u8('x'))
		append(&large, u8('\n'))
	}
	child_committed := os.write_entire_file(path, large[:]) == nil &&
	                 repository_process_test_run(directory, "git", "add", "large.txt") &&
	                 repository_process_test_run(directory, "git", "-c", "commit.gpgSign=false", "commit", "-q", "-m", "large child")
	testing.expect(t, child_committed)
	if !child_committed do return

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)
	repository: Repository_Context
	observed := repository_context_assign(&repository, directory)
	testing.expect(t, observed)
	if !observed do return
	history_request := Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = DEFAULT_HISTORY_LIMITS},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	history_process, history_started, history_failure := repository_process_start(history_request, 1, allocator)
	testing.expectf(t, history_started, "history start failed with %v", history_failure)
	if !history_started do return
	history_poll := repository_process_test_wait(&history_process)
	history, history_opened, history_open_failure := repository_process_take_history(
		&history_process, History_Generation(61), allocator,
	)
	repository_process_close(&history_process)
	testing.expectf(t, history_poll.state == .Completed && history_opened, "history parse failed with %v", history_open_failure)
	if history_poll.state != .Completed || !history_opened do return
	defer history_observation_close(&history)
	child, child_found := history_observation_revision(&history, 0)
	testing.expect(t, child_found && child.parent_count == 1)
	if !child_found || child.parent_count != 1 do return
	request := Revision_Detail_Request {
		target = {generation = History_Generation(61), revision = child.identity},
		parent = {kind = .Parent, parent = child.parents[0]},
		limits = DEFAULT_REVISION_DETAIL_LIMITS,
	}
	request.limits.changed_path_bytes = MIN_REVISION_CHANGED_PATH_BYTES
	request.limits.diff_bytes = MIN_REVISION_DETAIL_DIFF_BYTES
	metadata_process, metadata_started, metadata_failure := repository_process_start_revision_detail_metadata(
		&history, request, 1, allocator,
	)
	testing.expectf(t, metadata_started, "metadata start failed with %v", metadata_failure)
	if !metadata_started do return
	metadata_poll := repository_process_test_wait(&metadata_process)
	metadata, metadata_available := repository_process_output(&metadata_process)
	comparison_process, comparison_started, comparison_failure := repository_process_start_revision_detail_comparison(
		&history, request, 1, allocator,
	)
	testing.expectf(t, comparison_started, "comparison start failed with %v", comparison_failure)
	if !comparison_started {
		repository_process_close(&metadata_process)
		return
	}
	comparison_poll := repository_process_test_wait(&comparison_process)
	comparison, comparison_available := repository_process_revision_output(&comparison_process)
	testing.expect(t, metadata_poll.state == .Completed && metadata_available)
	testing.expect(t, comparison_poll.failure == .Output_Limit && comparison_available)
	if metadata_poll.state != .Completed || !metadata_available || !comparison_available {
		repository_process_close(&metadata_process)
		repository_process_close(&comparison_process)
		return
	}
	detail, detail_opened, detail_failure := revision_detail_open(
		repository, request, metadata, comparison, true, allocator,
	)
	repository_process_close(&metadata_process)
	repository_process_close(&comparison_process)
	testing.expectf(t, detail_opened, "truncated comparison parse failed with %v", detail_failure)
	if !detail_opened do return
	detail_descriptor, described := revision_detail_descriptor(&detail)
	testing.expect(t, described)
	if described do testing.expect(t, detail_descriptor.truncated)
	revision_detail_close(&detail)
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--quiet"))
	testing.expect(t, repository_process_test_run(directory, "git", "diff", "--cached", "--quiet"))
	history_observation_close(&history)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}
