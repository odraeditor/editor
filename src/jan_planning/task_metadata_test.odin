// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:mem"
import "core:testing"

import "../editor"
import "../history"
import "../language"
import "../transaction"

/* Verifies ordered transitions, dependency rejection, and one atomic source plan. */
@(test)
task_metadata_transitions_are_exact_and_atomic :: proc(t: ^testing.T) {
	configuration: Configuration
	configured := task_metadata_test_configuration(t, &configuration)
	if !configured do return
	defer planning_configuration_close(&configuration)

	source_text := "* TODO Ship\n"
	source := transmute([]u8)source_text
	scope := planning_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.source_revision = 0
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
	testing.expect(t, initialized)
	if !initialized do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, analysis_failure := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
	testing.expectf(t, analyzed, "task analysis failed with %v", analysis_failure.code)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	heading, found := task_metadata_test_node(&analysis, .Heading)
	testing.expect(t, found)
	if !found do return
	target := Semantic_Target{node_id = heading.id, kind = heading.kind, range = heading.range}

	request := Task_Transition_Request{
		operation_id = 3,
		scope = scope,
		target = target,
		workflow = "default",
		current_state = "TODO",
		direction = .Forward,
		dependency_policy = {require_finished_children = true, require_complete_checkboxes = true},
		rewrite_generation = 5,
	}
	transition, resolved, failure := task_transition_resolve(&configuration, request)
	testing.expectf(t, resolved, "task transition failed with %v", failure.code)
	testing.expect_value(t, transition.to, "NEXT")
	fast, fast_found := task_transition_destination_for_key(&configuration, "default", 'd')
	testing.expect(t, fast_found)
	testing.expect_value(t, fast.name, "DONE")

	request.destination_state = "DONE"
	request.dependencies.unfinished_children = 1
	_, resolved, failure = task_transition_resolve(&configuration, request)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	testing.expect_value(t, failure.actual, u64(1))

	request.dependencies = {}
	request.log_record = ":LOGBOOK:\n- State \"DONE\" from \"TODO\"\n:END:\n"
	plan: language.Jan_Rewrite_Plan
	planned: bool
	transition, planned, failure = task_transition_plan_prepare(
		&plan,
		&analysis,
		source,
		&configuration,
		request,
	)
	testing.expectf(t, planned, "task plan failed with %v", failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, transition.finished)
	descriptor, inspected := language.jan_rewrite_plan_descriptor(&plan)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.splice_count, u32(1))
	batch := language.jan_rewrite_plan_transaction_batch(&plan)
	testing.expect_value(t, len(batch), 1)
	testing.expect(t, len(batch[0].replacement) > len("DONE"))
	testing.expect(t, task_metadata_test_history(
		t,
		&plan,
		scope,
		source_text,
		"* DONE Ship\n:LOGBOOK:\n- State \"DONE\" from \"TODO\"\n:END:\n",
	))
}

/* Verifies task statistics, checkbox states, habits, and priority normalization. */
@(test)
task_metadata_derives_progress_without_history_mutation :: proc(t: ^testing.T) {
	next, cycled := task_checkbox_cycle(.Intermediate)
	testing.expect(t, cycled)
	testing.expect_value(t, next, Checkbox_State.Checked)
	statistics, derived := task_statistics_derive([]Checkbox_State{.Checked, .Unchecked, .Intermediate, .Checked})
	testing.expect(t, derived)
	testing.expect_value(t, statistics.completed, u32(2))
	testing.expect_value(t, statistics.percent, u8(50))
	habit, summarized := task_habit_summarize([]Habit_Occurrence{{true}, {false}, {true}, {true}})
	testing.expect(t, summarized)
	testing.expect_value(t, habit.completed, u32(3))
	testing.expect_value(t, habit.missed, u32(1))
	testing.expect_value(t, habit.current_streak, u32(2))
	alpha, alpha_ok := task_priority_normalize("B", 1, 9, 5)
	numeric, numeric_ok := task_priority_normalize("7", 1, 9, 5)
	defaulted, default_ok := task_priority_normalize("", 1, 9, 5)
	testing.expect(t, alpha_ok && numeric_ok && default_ok)
	testing.expect_value(t, alpha, i32(2))
	testing.expect_value(t, numeric, i32(7))
	testing.expect_value(t, defaulted, i32(5))
}

/* Verifies tag inheritance, groups, regular expressions, exceptions, and Boolean search. */
@(test)
task_metadata_resolves_case_sensitive_tags :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	target := planning_test_target(scope)
	candidates := []Tag_Candidate{
		{name = "project", origin = .Local, owner = target, active = true},
		{name = "work", origin = .Inherited, owner = target, active = true},
		{name = "backend", origin = .Computed, owner = target, active = true},
		{name = "Blocked", origin = .File, owner = target, active = true},
	}
	groups := []Tag_Group{
		{name = "project", kind = .Members, members = []string{"planning", "delivery"}},
		{name = "work", kind = .Regular_Expression, expression = "^(back|front)end$"},
	}
	output: [12]Tag_Record
	count, resolved, failure := tag_set_resolve(candidates, groups, []string{"delivery"}, output[:])
	testing.expectf(t, resolved, "tag resolution failed with %v", failure.code)
	testing.expect_value(t, count, 5)
	testing.expect(t, tag_record_has(output[:count], "planning"))
	testing.expect(t, tag_record_has(output[:count], "backend"))
	testing.expect(t, !tag_record_has(output[:count], "blocked"))
	query := []Tag_Query_Token{
		{kind = .Tag, name = "planning"},
		{kind = .Tag, name = "Blocked"},
		{kind = .And},
		{kind = .Tag, name = "missing"},
		{kind = .Not},
		{kind = .And},
	}
	matched, valid := tag_query_matches(output[:count], query)
	testing.expect(t, valid && matched)
}

/* Verifies property provenance, additive values, editable cells, and captured views. */
@(test)
task_metadata_projects_and_captures_properties :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	owner := planning_test_target(scope)
	properties := []Property_Candidate{
		{name = "OWNER", value = "Ada", origin = .Stored, owner = owner},
		{name = "OWNER", value = "Team", origin = .Inherited, owner = owner},
		{name = "LABELS", value = "editor", origin = .Stored, owner = owner, additive = true},
		{name = "LABELS", value = "jan", origin = .Inherited, owner = owner, additive = true},
		{name = "LEVEL", value = "1", origin = .Derived, owner = owner},
	}
	resolution, found, failure := property_resolve("OWNER", properties, scope.configuration_generation)
	testing.expectf(t, found, "property resolution failed with %v", failure.code)
	testing.expect_value(t, resolution.value, "Ada")
	testing.expect(t, resolution.editable)
	labels, labels_found, _ := property_resolve("LABELS", properties, scope.configuration_generation)
	testing.expect(t, labels_found)
	testing.expect_value(t, labels.component_count, u8(2))
	level, level_found, _ := property_resolve("LEVEL", properties, scope.configuration_generation)
	testing.expect(t, level_found && !level.editable)

	definitions := []Column_Definition{
		{property = "OWNER", heading = "Owner", width = 12},
		{property = "LEVEL", heading = "Level", width = 5},
	}
	rows := []Column_Row{{target = owner, properties = properties}}
	cells: [2]Column_Cell
	count, projected, projection_failure := column_view_project(definitions, rows, scope.configuration_generation, cells[:])
	testing.expectf(t, projected, "column projection failed with %v", projection_failure.code)
	testing.expect_value(t, count, 2)
	testing.expect(t, cells[0].editable && !cells[1].editable)
	snapshot: Column_Snapshot
	descriptor, captured, capture_failure := column_snapshot_capture(
		&snapshot,
		definitions,
		rows,
		scope.configuration_generation,
	)
	testing.expectf(t, captured, "column capture failed with %v", capture_failure.code)
	if !captured do return
	defer column_snapshot_close(&snapshot)
	text, inspected := column_snapshot_text(&snapshot)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.rows, u32(1))
	testing.expect_value(t, text, "Owner\tLevel\nAda\t1\n")
}

/* Verifies only local tags and stored properties can prepare exact owner edits. */
@(test)
task_metadata_edits_only_local_metadata_owners :: proc(t: ^testing.T) {
	source_text := "* TODO Ship :work:\n:PROPERTIES:\n:OWNER: Ada\n:END:\n"
	source := transmute([]u8)source_text
	scope := planning_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	initialized, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
	testing.expect(t, initialized)
	if !initialized do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, analysis_failure := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
	testing.expectf(t, analyzed, "metadata analysis failed with %v", analysis_failure.code)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	heading, found := task_metadata_test_node(&analysis, .Heading)
	testing.expect(t, found)
	if !found do return
	target := Semantic_Target{node_id = heading.id, kind = heading.kind, range = heading.range}

	property_plan: language.Jan_Rewrite_Plan
	property_request := Property_Edit_Request{
		operation_id = 15,
		scope = scope,
		target = target,
		origin = .Stored,
		current_value = "Ada",
		replacement_value = "Grace",
		allowed_values = []string{"Ada", "Grace"},
		rewrite_generation = 15,
	}
	planned, failure := property_edit_plan_prepare(&property_plan, &analysis, source, property_request)
	testing.expectf(t, planned, "property edit failed with %v", failure.code)
	if planned {
		defer language.jan_rewrite_plan_close(&property_plan)
		edits := language.jan_rewrite_plan_edits(&property_plan)
		replacement, replacement_ok := language.jan_rewrite_plan_replacement(&property_plan, edits[0])
		testing.expect(t, replacement_ok)
		testing.expect_value(t, replacement, "Grace")
	}

	inherited := property_request
	inherited.origin = .Inherited
	inherited_plan: language.Jan_Rewrite_Plan
	planned, failure = property_edit_plan_prepare(&inherited_plan, &analysis, source, inherited)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)

	tag_plan: language.Jan_Rewrite_Plan
	tag_request := Tag_Edit_Request{
		operation_id = 16,
		scope = scope,
		target = target,
		origin = .Local,
		current_value = "work",
		replacement_value = "home",
		rewrite_generation = 16,
	}
	planned, failure = tag_local_edit_plan_prepare(&tag_plan, &analysis, source, tag_request)
	testing.expectf(t, planned, "tag edit failed with %v", failure.code)
	if planned do language.jan_rewrite_plan_close(&tag_plan)
}

/* Verifies stale task scopes and allocation failures publish no partial metadata state. */
@(test)
task_metadata_rejects_stale_and_allocation_failures :: proc(t: ^testing.T) {
	configuration: Configuration
	configured := task_metadata_test_configuration(t, &configuration)
	if !configured do return
	defer planning_configuration_close(&configuration)
	scope := planning_test_scope()
	request := Task_Transition_Request{
		operation_id = 9,
		scope = scope,
		target = planning_test_target(scope),
		workflow = "default",
		current_state = "TODO",
		destination_state = "DONE",
		rewrite_generation = 1,
	}
	request.scope.configuration_generation += 1
	_, resolved, failure := task_transition_resolve(&configuration, request)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Failure_Code.Stale)
	request.scope = scope
	request.target = planning_test_target(scope)
	request.current_state = "BROKEN"
	_, resolved, failure = task_transition_resolve(&configuration, request)
	testing.expect(t, !resolved)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)

	tag_output: [2]Tag_Record
	_, tags_resolved, tag_failure := tag_set_resolve(
		[]Tag_Candidate{{name = "group", origin = .Local, owner = request.target, active = true}},
		[]Tag_Group{{name = "group", kind = .Regular_Expression, expression = "["}},
		nil,
		tag_output[:],
	)
	testing.expect(t, !tags_resolved)
	testing.expect_value(t, tag_failure.code, Failure_Code.Malformed)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	snapshot: Column_Snapshot
	_, captured, capture_failure := column_snapshot_capture(
		&snapshot,
		[]Column_Definition{{property = "OWNER", heading = "Owner", width = 8}},
		[]Column_Row{{target = planning_test_target(scope)}},
		scope.configuration_generation,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !captured)
	testing.expect_value(t, capture_failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private = "file")
task_metadata_test_configuration :: proc(t: ^testing.T, configuration: ^Configuration) -> bool {
	initialized, failure := planning_configuration_init(configuration, 22, 29)
	testing.expectf(t, initialized, "configuration init failed with %v", failure.code)
	if !initialized do return false
	states := [3]Workflow_State_Candidate{
		{name = "TODO", fast_key = 't', presentation = .Todo, log = .State},
		{name = "NEXT", fast_key = 'n', presentation = .Active, log = .None},
		{name = "DONE", finished = true, fast_key = 'd', presentation = .Done, log = .Time},
	}
	workflows := [1]Workflow_Candidate{{identity = "default", states = states[:]}}
	published: bool
	_, published, failure = planning_configuration_publish(
		configuration,
		{generation = 23, provider_generation = 29, workflows = workflows[:]},
	)
	testing.expectf(t, published, "configuration publish failed with %v", failure.code)
	if !published do planning_configuration_close(configuration)
	return published
}

@(private = "file")
task_metadata_test_node :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	kind: language.Jan_Node_Kind,
) -> (language.Jan_Node_Record, bool) {
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind == kind do return node, true
	}
	return {}, false
}

@(private = "file")
task_metadata_test_history :: proc(
	t: ^testing.T,
	plan: ^language.Jan_Rewrite_Plan,
	scope: Scope,
	source_text, expected: string,
) -> bool {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		scope.analysis.buffer_id,
		source_text,
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, buffer_ok)
	if !buffer_ok do return false
	defer editor.buffer_close(&buffer)
	store: history.Store
	store_ok, _ := history.store_init(
		&store,
		19,
		scope.analysis.buffer_id,
		scope.analysis.source_revision,
		history.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, store_ok)
	if !store_ok do return false
	defer history.store_close(&store)
	root: transaction.Transaction
	started, transaction_failure := transaction.transaction_begin(
		&root,
		19,
		19,
		&buffer,
		{kind = .Language_Tool, descriptor = "jan-task"},
		"jan-task-transition",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !started do return false
	applied, _ := transaction.transaction_apply_batch(&root, language.jan_rewrite_plan_transaction_batch(plan))
	tracked, _ := transaction.transaction_track_history(&root, &store)
	validated, _ := transaction.transaction_validate(&root)
	committed: bool
	_, committed, transaction_failure = transaction.transaction_commit(&root)
	transaction.transaction_close(&root)
	testing.expectf(t, applied && tracked && validated && committed, "task transaction failed with %v", transaction_failure.code)
	if !applied || !tracked || !validated || !committed do return false
	if !task_metadata_test_buffer_matches(&buffer, expected) do return false
	_, undone, _ := transaction.transaction_history_navigate(
		&store,
		&buffer,
		.Undo,
		20,
		20,
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	return undone && task_metadata_test_buffer_matches(&buffer, source_text)
}

@(private = "file")
task_metadata_test_buffer_matches :: proc(buffer: ^editor.Buffer, expected: string) -> bool {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return false
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok || stats.text_bytes != u64(len(expected)) do return false
	actual, allocation_error := make([]u8, len(expected), context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(actual, context.temp_allocator)
	copied, copied_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, actual)
	return copied_ok && copied == u64(len(expected)) && string(actual) == expected
}
