// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:mem"
import "core:testing"

import "../language"

/* Verifies source generations retain confirmed, stale, and unavailable outcomes independently. */
@(test)
agenda_indexes_preserve_source_health_and_exact_rows :: proc(t: ^testing.T) {
	fixture: Agenda_Test_Fixture
	if !agenda_test_fixture_open(t, &fixture) do return
	defer agenda_index_close(&fixture.index)
	descriptor, inspected := agenda_index_descriptor(&fixture.index)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.source_count, u32(5))
	testing.expect_value(t, descriptor.confirmed_sources, u32(2))
	testing.expect_value(t, descriptor.stale_sources, u32(1))
	testing.expect_value(t, descriptor.unavailable_sources, u32(1))
	testing.expect_value(t, descriptor.failed_sources, u32(1))
	testing.expect_value(t, descriptor.indexed_entries, u32(7))
	stale, stale_ok := agenda_index_source(&fixture.index, 2)
	unavailable, unavailable_ok := agenda_index_source(&fixture.index, 3)
	testing.expect(t, stale_ok && unavailable_ok)
	testing.expect_value(t, stale.state, Agenda_Source_State.Stale)
	testing.expect_value(t, stale.failure_code, Failure_Code.Stale)
	testing.expect_value(t, unavailable.state, Agenda_Source_State.Unavailable)
	testing.expect_value(t, unavailable.failure_code, Failure_Code.Unavailable)
	entry, entry_ok := agenda_index_entry(&fixture.index, 0)
	testing.expect(t, entry_ok && entry.has_target)
	tags, tags_ok := agenda_index_entry_tags(&fixture.index, entry)
	properties, properties_ok := agenda_index_entry_properties(&fixture.index, entry)
	testing.expect(t, tags_ok && properties_ok)
	testing.expect_value(t, tags[1], "urgent")
	testing.expect_value(t, properties[0].name, "OWNER")
	testing.expect_value(t, properties[0].value, "Ada")
}

/* Verifies every native and typed-provider query family uses the same result contract. */
@(test)
agenda_queries_cover_factory_and_provider_families :: proc(t: ^testing.T) {
	fixture: Agenda_Test_Fixture
	if !agenda_test_fixture_open(t, &fixture) do return
	defer agenda_index_close(&fixture.index)
	test_cases := []struct {
		kind:      Agenda_Query_Kind,
		primary:   string,
		secondary: string,
		start:     i64,
		end:       i64,
		expected:  u32,
	}{
		{.Daily, "", "", 900, 1_600, 3},
		{.Weekly, "", "", 900, 2_100, 6},
		{.Unfinished, "", "", 0, 0, 1},
		{.Task, "TODO", "", 0, 0, 1},
		{.Tag, "urgent", "", 0, 0, 1},
		{.Property, "OWNER", "Ada", 0, 0, 1},
		{.Text, "release", "", 0, 0, 1},
		{.Regular_Expression, "Revi.*release", "", 0, 0, 1},
		{.Project, "alpha", "", 0, 0, 1},
		{.Stuck_Project, "alpha", "", 0, 0, 1},
		{.Clock, "", "", 0, 0, 1},
		{.Effort, "", "", 0, 0, 1},
		{.Column, "", "", 0, 0, 1},
		{.Block, "morning", "", 0, 0, 1},
		{.Custom, "focus", "", 0, 0, 1},
		{.Diary, "", "", 0, 0, 1},
		{.Calendar, "", "", 0, 0, 1},
		{.Anniversary, "", "", 0, 0, 1},
		{.Reminder, "", "", 0, 0, 1},
		{.Extension, "", "", 0, 0, 1},
	}
	for test_case in test_cases {
		request := agenda_test_query(test_case.kind)
		request.primary = test_case.primary
		request.secondary = test_case.secondary
		request.start_time = test_case.start
		request.end_time = test_case.end
		result: Agenda_Query_Result
		descriptor, prepared, failure := agenda_query_prepare(&result, &fixture.index, request)
		testing.expectf(t, prepared, "agenda query %v failed with %v", test_case.kind, failure.code)
		if prepared {
			testing.expect_value(t, descriptor.result_count, test_case.expected)
			agenda_query_close(&result)
		}
	}
	predicates := [3]Agenda_Predicate_Token{
		{kind = .Tag, primary = "work"},
		{kind = .Property, primary = "OWNER", secondary = "Ada"},
		{kind = .And},
	}
	combined := agenda_test_query(.Combined)
	combined.predicates = predicates[:]
	result: Agenda_Query_Result
	descriptor, prepared, failure := agenda_query_prepare(&result, &fixture.index, combined)
	testing.expectf(t, prepared, "combined agenda query failed with %v", failure.code)
	if prepared {
		testing.expect_value(t, descriptor.result_count, u32(1))
		agenda_query_close(&result)
	}
}

/* Verifies filters, stable sorting, grouping, prefixes, time grids, and truncation. */
@(test)
agenda_queries_present_bounded_deterministic_rows :: proc(t: ^testing.T) {
	fixture: Agenda_Test_Fixture
	if !agenda_test_fixture_open(t, &fixture) do return
	defer agenda_index_close(&fixture.index)
	sort_specs := [2]Agenda_Sort_Spec{
		{key = .Priority, descending = true},
		{key = .Heading_Path},
	}
	request := agenda_test_query(.Text)
	request.primary = "task"
	request.include_archived = true
	request.sort = sort_specs[:]
	request.group_by = .Category
	request.prefix_format = .Heading_Path
	request.time_grid = true
	request.result_limit = 2
	result: Agenda_Query_Result
	descriptor, prepared, failure := agenda_query_prepare(&result, &fixture.index, request)
	testing.expectf(t, prepared, "sorted agenda query failed with %v", failure.code)
	if prepared {
		defer agenda_query_close(&result)
		testing.expect_value(t, descriptor.result_count, u32(2))
		testing.expect_value(t, descriptor.matched_count, u32(2))
		testing.expect(t, !descriptor.complete)
		row, row_ok := agenda_query_row(&result, 0)
		testing.expect(t, row_ok)
		entry, entry_ok := agenda_index_entry(&fixture.index, int(row.entry_index))
		testing.expect(t, entry_ok)
		testing.expect_value(t, entry.identity, "done-task")
		testing.expect_value(t, agenda_display_text(&row.group), "Personal")
		testing.expect_value(t, agenda_display_text(&row.prefix), "Home / Done")
		testing.expect(t, row.time_grid)
	}

	request.result_limit = 1
	truncated: Agenda_Query_Result
	descriptor, prepared, failure = agenda_query_prepare(&truncated, &fixture.index, request)
	testing.expectf(t, prepared, "truncated agenda query failed with %v", failure.code)
	if prepared {
		testing.expect(t, descriptor.truncated)
		testing.expect_value(t, descriptor.matched_count, u32(2))
		agenda_query_close(&truncated)
	}

	required_tags := [1]string{"work"}
	property_filters := [1]Agenda_Property_Filter{{name = "OWNER", value = "Ada"}}
	computed := [1]Agenda_Predicate_Token{{kind = .Tag, primary = "urgent"}}
	filtered := agenda_test_query(.Unfinished)
	filtered.required_tags = required_tags[:]
	filtered.property_filters = property_filters[:]
	filtered.computed_tag_filter = computed[:]
	filtered_result: Agenda_Query_Result
	descriptor, prepared, failure = agenda_query_prepare(&filtered_result, &fixture.index, filtered)
	testing.expectf(t, prepared, "filtered agenda query failed with %v", failure.code)
	if prepared {
		testing.expect_value(t, descriptor.result_count, u32(1))
		agenda_query_close(&filtered_result)
	}
}

/* Verifies cache keys invalidate and unhealthy sources never become confirmed absence. */
@(test)
agenda_queries_invalidate_caches_and_report_incomplete_sources :: proc(t: ^testing.T) {
	fixture: Agenda_Test_Fixture
	if !agenda_test_fixture_open(t, &fixture) do return
	defer agenda_index_close(&fixture.index)
	index_descriptor, _ := agenda_index_descriptor(&fixture.index)
	request := agenda_test_query(.Unfinished)
	key := Agenda_Cache_Key{
		index_generation = index_descriptor.generation,
		configuration_generation = index_descriptor.configuration_generation,
		source_set = index_descriptor.source_set,
		query_identity = 91,
	}
	testing.expect(t, agenda_cache_key_is_current(key, index_descriptor, request))
	key.index_generation += 1
	testing.expect(t, !agenda_cache_key_is_current(key, index_descriptor, request))
	result: Agenda_Query_Result
	descriptor, prepared, failure := agenda_query_prepare(&result, &fixture.index, request)
	testing.expectf(t, prepared, "health agenda query failed with %v", failure.code)
	if prepared {
		testing.expect_value(t, descriptor.stale_sources, u32(1))
		testing.expect_value(t, descriptor.unavailable_sources, u32(1))
		testing.expect_value(t, descriptor.failed_sources, u32(1))
		testing.expect(t, !descriptor.complete)
		agenda_query_close(&result)
	}
}

/* Verifies cancellation, malformed predicates, allocation faults, and cleanup. */
@(test)
agenda_queries_contain_faults_and_release_owned_state :: proc(t: ^testing.T) {
	fixture: Agenda_Test_Fixture
	agenda_test_fixture_populate(&fixture)
	request := agenda_test_index_request(&fixture)
	request.cancel_requested = true
	_, prepared, failure := agenda_index_prepare(&fixture.index, request)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
	request.cancel_requested = false

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	_, prepared, failure = agenda_index_prepare(&fixture.index, request, allocator)
	testing.expectf(t, prepared, "tracked agenda index failed with %v", failure.code)
	if prepared do agenda_index_close(&fixture.index)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	_, prepared, failure = agenda_index_prepare(
		&fixture.index,
		request,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)

	if !agenda_test_fixture_open(t, &fixture) do return
	defer agenda_index_close(&fixture.index)
	malformed := agenda_test_query(.Combined)
	malformed_tokens := [1]Agenda_Predicate_Token{{kind = .And}}
	malformed.predicates = malformed_tokens[:]
	result: Agenda_Query_Result
	_, prepared, failure = agenda_query_prepare(&result, &fixture.index, malformed)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	mem.tracking_allocator_init(&tracking, context.allocator)
	failing = {backing = mem.tracking_allocator(&tracking), fail_after = 0}
	query := agenda_test_query(.Unfinished)
	fault_result: Agenda_Query_Result
	_, prepared, failure = agenda_query_prepare(
		&fault_result,
		&fixture.index,
		query,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
Agenda_Test_Fixture :: struct {
	work_tags:       [2]string,
	home_tags:       [1]string,
	work_properties: [1]Agenda_Property_Candidate,
	home_properties: [1]Agenda_Property_Candidate,
	document_entries:[2]Agenda_Entry_Candidate,
	provider_entries:[5]Agenda_Entry_Candidate,
	sources:          [5]Agenda_Source_Candidate,
	index:            Agenda_Index,
}

@(private = "file")
agenda_test_fixture_open :: proc(t: ^testing.T, fixture: ^Agenda_Test_Fixture) -> bool {
	agenda_test_fixture_populate(fixture)
	descriptor, prepared, failure := agenda_index_prepare(&fixture.index, agenda_test_index_request(fixture))
	testing.expectf(t, prepared, "agenda index failed with %v", failure.code)
	if prepared do testing.expect_value(t, descriptor.indexed_entries, u32(7))
	return prepared
}

@(private = "file")
agenda_test_fixture_populate :: proc(fixture: ^Agenda_Test_Fixture) {
	fixture^ = {}
	fixture.work_tags = {"work", "urgent"}
	fixture.home_tags = {"home"}
	fixture.work_properties = {{name = "OWNER", value = "Ada"}}
	fixture.home_properties = {{name = "OWNER", value = "Bob"}}
	scope := planning_test_scope()
	fixture.document_entries = {
		{
			identity = "review-task",
			kind = .Document,
			target = planning_test_target(scope),
			has_target = true,
			category = "Work",
			heading_path = "Project / Review",
			task_state = "TODO",
			priority = 2,
			tags = fixture.work_tags[:],
			properties = fixture.work_properties[:],
			scheduled = 900,
			timestamp = 1_000,
			time_of_day_minutes = 600,
			warning = true,
			project = "alpha",
			stuck_project = true,
			clock_seconds = 3_600,
			effort_seconds = 7_200,
			column_text = "Ada\t2h",
			plain_text = "Review release task",
			block_identity = "morning",
			custom_identity = "focus",
		},
		{
			identity = "done-task",
			kind = .Document,
			target = planning_test_target(scope),
			has_target = true,
			category = "Personal",
			heading_path = "Home / Done",
			task_state = "DONE",
			finished = true,
			priority = 5,
			tags = fixture.home_tags[:],
			properties = fixture.home_properties[:],
			timestamp = 2_000,
			time_of_day_minutes = 720,
			project = "beta",
			plain_text = "Finished home task",
			archived = true,
		},
	}
	provider_kinds := [5]Agenda_Entry_Kind{.Diary, .Calendar, .Anniversary, .Reminder, .Extension}
	provider_names := [5]string{"diary", "calendar", "anniversary", "reminder", "extension"}
	for kind, index in provider_kinds {
		fixture.provider_entries[index] = {
			identity = provider_names[index],
			kind = kind,
			category = "Provider",
			heading_path = provider_names[index],
			timestamp = i64(1_500 + index * 100),
			time_of_day_minutes = i16(480 + index * 10),
			plain_text = provider_names[index],
			provider_annotation = "optional-provider",
		}
	}
	document_resource, _ := resource_identity_copy(7, "notes/tasks.org")
	provider_resource, _ := resource_identity_copy(8, "calendar/default")
	stale_resource, _ := resource_identity_copy(7, "notes/stale.org")
	unavailable_resource, _ := resource_identity_copy(9, "diary/unavailable")
	failed_resource, _ := resource_identity_copy(9, "calendar/failed")
	baseline := language.jan_factory_baseline()
	fixture.sources = {
		{
			identity = "tasks",
			kind = .File,
			state = .Confirmed,
			resource = document_resource,
			document_revision = 7,
			baseline = baseline,
			configuration_generation = 23,
			provider_generation = 29,
			document_limit = 8,
			discovered_documents = 1,
			root_admitted = true,
			entries = fixture.document_entries[:],
		},
		{
			identity = "calendar",
			kind = .Provider,
			state = .Confirmed,
			resource = provider_resource,
			durable_version = 42,
			baseline = baseline,
			configuration_generation = 23,
			provider_generation = 29,
			document_limit = 8,
			discovered_documents = 1,
			root_admitted = true,
			entries = fixture.provider_entries[:],
		},
		{
			identity = "stale",
			kind = .Workspace,
			state = .Stale,
			failure_code = .Stale,
			resource = stale_resource,
			document_revision = 6,
			baseline = baseline,
			configuration_generation = 22,
			provider_generation = 29,
			document_limit = 8,
			discovered_documents = 1,
			root_admitted = true,
		},
		{
			identity = "unavailable",
			kind = .Provider,
			state = .Unavailable,
			failure_code = .Unavailable,
			resource = unavailable_resource,
			durable_version = 1,
			baseline = baseline,
			configuration_generation = 23,
			provider_generation = 29,
			document_limit = 8,
			discovered_documents = 1,
			root_admitted = true,
		},
		{
			identity = "failed",
			kind = .Provider,
			state = .Failed,
			failure_code = .Malformed,
			resource = failed_resource,
			durable_version = 1,
			baseline = baseline,
			configuration_generation = 23,
			provider_generation = 29,
			document_limit = 8,
			discovered_documents = 1,
			root_admitted = true,
		},
	}
}

@(private = "file")
agenda_test_index_request :: proc(fixture: ^Agenda_Test_Fixture) -> Agenda_Index_Request {
	return {
		operation_id = 71,
		generation = 77,
		source_set = 31,
		configuration_generation = 23,
		provider_generation = 29,
		sources = fixture.sources[:],
		entry_limit = 64,
		copied_text_limit = 1_048_576,
		derived_state_limit = 8_388_608,
	}
}

@(private = "file")
agenda_test_query :: proc(kind: Agenda_Query_Kind) -> Agenda_Query_Request {
	return {
		operation_id = 72,
		index_generation = 77,
		configuration_generation = 23,
		query_dialect = "jan-agenda-v1",
		kind = kind,
		result_limit = 64,
	}
}
