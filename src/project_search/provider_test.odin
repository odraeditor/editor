// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_search

import project_core "../project"
import "../search"
import "core:mem"
import "core:os"
import "core:testing"

@(test)
/* Verifies local search applies explicit file policies and shared matching rules. */
provider_applies_file_policies :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-search-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	main_path := native_test_path(t, root, "main.odin")
	hidden_path := native_test_path(t, root, ".hidden.odin")
	ignored_path := native_test_path(t, root, "ignored.odin")
	binary_path := native_test_path(t, root, "binary.odin")
	excluded_path := native_test_path(t, root, "skip.odin")
	ignore_path := native_test_path(t, root, ".ignore")
	defer {
		delete(ignore_path)
		delete(excluded_path)
		delete(binary_path)
		delete(ignored_path)
		delete(hidden_path)
		delete(main_path)
	}
	testing.expect(t, os.write_entire_file(main_path, "needle\nżółć needle\n") == nil)
	testing.expect(t, os.write_entire_file(hidden_path, "needle\n") == nil)
	testing.expect(t, os.write_entire_file(ignored_path, "needle\n") == nil)
	binary := []byte{'n', 'e', 'e', 'd', 'l', 'e', 0, '\n'}
	testing.expect(t, os.write_entire_file(binary_path, binary) == nil)
	testing.expect(t, os.write_entire_file(excluded_path, "needle\n") == nil)
	testing.expect(t, os.write_entire_file(ignore_path, "ignored.odin\n") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	request, roots, includes, excludes := native_test_request(root)
	_ = roots
	_ = includes
	_ = excludes
	provider: Native_Provider
	initialized, initialize_failure := native_provider_init(&provider, request,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator})
	testing.expectf(t, initialized, "provider init failed with %v", initialize_failure.code)
	if initialized {
		view, completed := native_test_complete(t, &provider, request.project)
		if completed {
			testing.expect_value(t, view.inspection.completeness, Completeness.Complete)
			testing.expect_value(t, len(view.matches), 2)
			testing.expect_value(t, view.matches[0].line, u64(1))
			testing.expect_value(t, view.matches[1].line, u64(2))
			testing.expect_value(t, view.matches[1].column, u64(6))
		}
		closed, close_failure := native_provider_close(&provider)
		testing.expectf(t, closed, "provider close failed with %v", close_failure.code)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(test)
/* Verifies policy inversion can include hidden, ignored, and binary sources. */
provider_includes_hidden_binary_sources :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-search-policy-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	paths := [4]string{
		native_test_path(t, root, "main.odin"),
		native_test_path(t, root, ".hidden.odin"),
		native_test_path(t, root, "ignored.odin"),
		native_test_path(t, root, "binary.odin"),
	}
	ignore_path := native_test_path(t, root, ".ignore")
	defer {
		for path in paths do delete(path)
		delete(ignore_path)
	}
	for path in paths do testing.expect(t, os.write_entire_file(path, "needle\x00\n") == nil)
	testing.expect(t, os.write_entire_file(ignore_path, "ignored.odin\n") == nil)
	request, roots, includes, excludes := native_test_request(root)
	_ = roots
	_ = includes
	_ = excludes
	request.policy.hidden = .Include
	request.policy.ignored = .Include_Ignored
	request.policy.binary = .Include
	provider: Native_Provider
	initialized, initialize_failure := native_provider_init(&provider, request,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expectf(t, initialized, "provider init failed with %v", initialize_failure.code)
	if initialized {
		view, completed := native_test_complete(t, &provider, request.project)
		if completed do testing.expect_value(t, len(view.matches), 4)
		native_provider_close(&provider)
	}
}

@(test)
/* Verifies Unicode expressions share semantics across ordered Project roots. */
provider_searches_unicode_across_roots :: proc(t: ^testing.T) {
	first, first_error := os.make_directory_temp("", "odra-project-search-first-*", context.allocator)
	second, second_error := os.make_directory_temp("", "odra-project-search-second-*", context.allocator)
	testing.expect(t, first_error == nil && second_error == nil)
	if first_error != nil || second_error != nil do return
	defer {
		os.remove_all(first)
		os.remove_all(second)
		delete(first)
		delete(second)
	}
	first_path := native_test_path(t, first, "a.odin")
	second_path := native_test_path(t, second, "b.odin")
	defer {
		delete(first_path)
		delete(second_path)
	}
	testing.expect(t, os.write_entire_file(first_path, "zażółć alpha-42\n") == nil)
	testing.expect(t, os.write_entire_file(second_path, "alpha-7 zażółć\n") == nil)
	request, roots, includes, excludes := native_test_request(first)
	_ = includes
	_ = excludes
	second_path_value: project_core.Directory_Path
	second_path_value.length = u32(copy(second_path_value.bytes[:], second))
	second_membership := roots[0].membership
	second_membership.id += 1
	second_membership.slot += 1
	ordered_roots := [2]Root {roots[0], {membership = second_membership, path = second_path_value}}
	request.roots = ordered_roots[:]
	request.pattern_kind = .Regular_Expression
	request.pattern = "alpha-[0-9]+"
	provider: Native_Provider
	initialized, _ := native_provider_init(&provider, request,
		{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer native_provider_close(&provider)
	view, completed := native_test_complete(t, &provider, request.project)
	if completed {
		testing.expect_value(t, len(view.matches), 2)
		testing.expect(t, view.matches[0].path < view.matches[1].path)
		testing.expect_value(t, view.matches[0].column, u64(8))
	}
}

@(test)
/* native_provider_reports_bounded_continuation_and_generation_scoped_cancellation. */
provider_reports_bounded_continuation :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-search-bounded-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	path := native_test_path(t, root, "dense.odin")
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "needle needle needle\n") == nil)
	request, roots, includes, excludes := native_test_request(root)
	_ = roots
	_ = includes
	_ = excludes
	request.limits.matches = 1
	provider: Native_Provider
	initialized, _ := native_provider_init(&provider, request,
		{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if initialized {
		view, completed := native_test_complete(t, &provider, request.project)
		if completed {
			testing.expect_value(t, view.inspection.completeness, Completeness.Incomplete)
			testing.expect(t, view.inspection.continuation.present)
			testing.expect_value(t, len(view.matches), 1)
		}
		native_provider_close(&provider)
	}
	request.generation += 1
	request.provider_generation += 1
	initialized, _ = native_provider_init(&provider, request,
		{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if initialized {
		cancellation := Cancellation{generation = request.generation}
		testing.expect(t, cancellation_request(&cancellation, request.generation))
		inspection, advanced, _ := native_provider_advance(&provider, request.project, &cancellation)
		testing.expect(t, advanced)
		testing.expect_value(t, inspection.lifecycle, Lifecycle.Cancelled)
		testing.expect(t, inspection.continuation.present)
		native_provider_close(&provider)
	}
}

@(test)
/* native_provider_revalidation_rejects_changed_sources_and_stale Projects. */
provider_rejects_changed_sources :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-search-stale-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	path := native_test_path(t, root, "main.odin")
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "needle\n") == nil)
	request, roots, includes, excludes := native_test_request(root)
	_ = roots
	_ = includes
	_ = excludes
	provider: Native_Provider
	initialized, _ := native_provider_init(&provider, request,
		{persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, initialized)
	if !initialized do return
	defer native_provider_close(&provider)
	_, advanced, stale_failure := native_provider_advance(
		&provider,
		project_core.Project_Handle {
			owner = request.project.owner,
			id = request.project.id,
			generation = request.project.generation + 1,
		},
	)
	testing.expect(t, !advanced)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Project)
	view, completed := native_test_complete(t, &provider, request.project)
	if completed && len(view.matches) == 1 {
		testing.expect(t, os.write_entire_file(path, "needle changed\n") == nil)
		_, current, fingerprint_failure := native_provider_revalidate(&provider, view.matches[0].id)
		testing.expect(t, !current)
		testing.expect_value(t, fingerprint_failure.code, Failure_Code.Stale_Fingerprint)
	}
}

@(private)
native_test_request :: proc(root: string) -> (Request, [1]Root, [1]string, [1]string) {
	project := project_core.Project_Handle{owner = {id = 41, generation = 1}, id = 42, generation = 3}
	membership := project_core.Membership_Handle{project = project, id = 43, slot = 0, generation = 2}
	path: project_core.Directory_Path
	path.length = u32(copy(path.bytes[:], root))
	roots := [1]Root{{membership = membership, path = path}}
	includes := [1]string{"*.odin"}
	excludes := [1]string{"skip.odin"}
	request := Request{id = 1, generation = 1, provider = 1, provider_generation = 1,
		project = project, query_id = 1, pattern_kind = .Literal, pattern = "needle",
		policy = {search = search.DEFAULT_POLICY, hidden = .Exclude, ignored = .Respect,
			binary = .Exclude, include_patterns = includes[:], exclude_patterns = excludes[:]},
		search_limits = search.DEFAULT_LIMITS, limits = DEFAULT_LIMITS, roots = roots[:]}
	return request, roots, includes, excludes
}

@(private)
native_test_complete :: proc(t: ^testing.T, provider: ^Native_Provider,
	project: project_core.Project_Handle) -> (Native_View, bool) {
	for _ in 0 ..< 1_024 {
		inspection, advanced, failure := native_provider_advance(provider, project)
		testing.expectf(t, advanced, "provider advance failed with %v", failure.code)
		if !advanced do return {}, false
		if inspection.lifecycle == .Complete || inspection.lifecycle == .Cancelled {
			view, viewed, view_failure := native_provider_view(provider)
			testing.expectf(t, viewed, "provider view failed with %v", view_failure.code)
			return view, viewed
		}
	}
	testing.expectf(t, false, "provider did not complete within the bounded test turns")
	return {}, false
}

@(private)
native_test_path :: proc(t: ^testing.T, root, name: string) -> string {
	path, path_error := os.join_path({root, name}, context.allocator)
	testing.expect(t, path_error == nil)
	return path
}
