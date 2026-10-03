// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "base:runtime"
import "core:testing"

/* Verifies malformed analysis produces deterministic exact-revision lint facts. */
@(test)
jan_lint_reports_recovery_facts :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 42)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("* Heading\n#+begin_src odin\nmain :: proc() {}\n"))
	scope := jan_lint_test_scope(1, 1)
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	result, linted, lint_failure := jan_lint_analyze(&analysis, {}, 1)
	testing.expect(t, linted)
	testing.expect_value(t, lint_failure.code, Jan_Failure_Code.None)
	if !linted do return
	defer jan_lint_result_close(&result)
	records := jan_lint_result_records(&result)
	testing.expect(t, len(records) > 0)
	for record in records {
		testing.expect_value(t, record.scope, scope)
		testing.expect_value(t, record.generation, Jan_Lint_Generation(1))
		testing.expect(t, record.id != 0 && record.has_range)
		testing.expect(t, record.code != .Invalid)
		testing.expect(t, record.severity != .Invalid)
		testing.expect(t, record.confidence != .Invalid)
		testing.expect(t, record.checker.length > 0 && record.explanation.length > 0)
	}
}

/* Verifies refresh replaces only a newer result in the same document lineage. */
@(test)
jan_lint_refresh_is_atomic_and_revision_bound :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 42)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("* Heading\n"))
	first_scope := jan_lint_test_scope(2, 2)
	first, analyzed, _ := jan_structural_owner_analyze(&owner, source, first_scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&first)
	result, linted, _ := jan_lint_analyze(&first, {}, 4)
	testing.expect(t, linted)
	if !linted do return
	defer jan_lint_result_close(&result)
	refreshed, refresh_failure := jan_lint_refresh(&result, &first, {}, 3)
	testing.expect(t, !refreshed)
	testing.expect_value(t, refresh_failure.code, Jan_Failure_Code.Stale)
	generation, live := jan_lint_result_generation(&result)
	testing.expect(t, live)
	testing.expect_value(t, generation, Jan_Lint_Generation(4))
	second_scope := first_scope
	second_scope.source_revision = 3
	second_scope.analysis_generation = 3
	second, second_ok, _ := jan_structural_owner_analyze(&owner, source, second_scope)
	testing.expect(t, second_ok)
	if !second_ok do return
	defer jan_structural_analysis_close(&second)
	refreshed, refresh_failure = jan_lint_refresh(&result, &second, {}, 5)
	testing.expect(t, refreshed)
	testing.expect_value(t, refresh_failure.code, Jan_Failure_Code.None)
	result_scope, scoped := jan_lint_result_scope(&result)
	testing.expect(t, scoped)
	testing.expect_value(t, result_scope.source_revision, editor.Revision(3))
}

/* Verifies lint limits, allocation faults, and cleanup preserve confirmed analysis. */
@(test)
jan_lint_contains_limits_faults_and_cleanup :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 42)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("#+begin_src odin\nmain :: proc() {}\n"))
	scope := jan_lint_test_scope(8, 8)
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, analyzed)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	limits := DEFAULT_JAN_RESOURCE_LIMITS
	limits.inspection_bytes = 1
	_, limited, limit_failure := jan_lint_analyze(&analysis, {}, 8, limits)
	testing.expect(t, !limited)
	testing.expect_value(t, limit_failure.code, Jan_Failure_Code.Limited)
	failing := Jan_Lint_Failing_Allocator{backing = context.allocator}
	_, allocated, allocation_failure := jan_lint_analyze(
		&analysis,
		{},
		8,
		DEFAULT_JAN_RESOURCE_LIMITS,
		jan_lint_failing_allocator(&failing),
	)
	testing.expect(t, !allocated)
	testing.expect_value(t, allocation_failure.code, Jan_Failure_Code.Allocation_Failed)
	result, linted, _ := jan_lint_analyze(&analysis, {}, 8)
	testing.expect(t, linted)
	if linted {
		testing.expect(t, jan_lint_result_close(&result))
		testing.expect(t, !jan_lint_result_close(&result))
	}
	usage, usage_ok := jan_structural_analysis_usage(&analysis)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.source_bytes, u64(len(source)))
}

@(private)
jan_lint_test_scope :: proc(revision: editor.Revision, generation: Jan_Analysis_Generation) -> Jan_Analysis_Scope {
	registration, _ := factory_bundle_registration(FACTORY_JAN_BUNDLE_IDENTITY)
	return {
		buffer_id = 91,
		document_id = 92,
		has_document = true,
		source_revision = revision,
		language = registration.language,
		provider = {registry_id = 2, language_id = registration.language.id, provider_id = 1, provider_generation = 1},
		selection_generation = 7,
		parser_generation = 42,
		grammar_generation = 1,
		configuration = registration.jan_configuration.identity,
		baseline = registration.jan_baseline,
		analysis_generation = generation,
	}
}

@(private = "file")
Jan_Lint_Failing_Allocator :: struct {
	backing: runtime.Allocator,
}

@(private = "file")
jan_lint_failing_allocator :: proc(data: ^Jan_Lint_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = jan_lint_failing_allocator_proc, data = data}
}

@(private = "file")
jan_lint_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Jan_Lint_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		return nil, .Out_Of_Memory
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
