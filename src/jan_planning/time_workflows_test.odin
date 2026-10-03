// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:mem"
import "core:testing"

import "../editor"
import "../language"
import "../transaction"

/* Verifies zone precedence, DST gaps and folds, and locale-independent syntax. */
@(test)
time_workflows_resolve_zones_and_canonical_timestamps :: proc(t: ^testing.T) {
	zone, resolved, failure := time_zone_resolve([]Time_Zone_Candidate{
		{owner = .System, value = "UTC", active = true},
		{owner = .Document, value = "Europe/Warsaw", active = true},
		{owner = .Invocation, value = "America/Argentina/Buenos_Aires"},
	})
	testing.expectf(t, resolved, "zone resolution failed with %v", failure.code)
	testing.expect_value(t, zone.owner, Time_Zone_Owner.Document)

	local := Local_Date_Time{date = {2026, 3, 29}, time = {hour = 2, minute = 30}}
	input := Local_Time_Resolution_Input{
		local = local,
		zone = zone,
		classification = .Gap,
		earlier = {seconds = 100},
		later = {seconds = 200},
	}
	accepted: bool
	_, accepted, failure = local_time_resolve(input, .Invalid)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	input.local.date = {2026, 10, 25}
	input.classification = .Fold
	_, accepted, failure = local_time_resolve(input, .Invalid)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Confirmation_Required)
	fold: Local_Time_Resolution
	fold, accepted, failure = local_time_resolve(input, .Later)
	testing.expectf(t, accepted, "fold resolution failed with %v", failure.code)
	testing.expect_value(t, fold.instant.seconds, i64(200))

	spec := Timestamp_Spec{
		local = {date = {2026, 9, 16}, time = {hour = 10, minute = 30}},
		active = true,
		has_time = true,
		recurrence = {kind = .Catch_Up, interval = {amount = 1, unit = .Week}},
		warning = {amount = 2, unit = .Day},
	}
	english, english_ok := timestamp_text_format(spec, "en-US")
	polish, polish_ok := timestamp_text_format(spec, "pl-PL")
	testing.expect(t, english_ok && polish_ok)
	testing.expect_value(t, timestamp_text(&english), "<2026-09-16 Wed 10:30 ++1w -2d>")
	testing.expect_value(t, timestamp_text(&polish), timestamp_text(&english))
	range_start := spec
	range_start.recurrence = {}
	range_start.warning = {}
	range_end := range_start
	range_end.local.date.day = 17
	range_text, range_ok := timestamp_range_text_format({start = range_start, end = range_end}, "es-AR")
	testing.expect(t, range_ok)
	testing.expect_value(
		t,
		timestamp_range_text(&range_text),
		"<2026-09-16 Wed 10:30>--<2026-09-17 Thu 10:30>",
	)
	shifted, shift_ok := civil_date_shift_days({2024, 3, 1}, -1)
	testing.expect(t, shift_ok)
	testing.expect_value(t, shifted, Civil_Date{2024, 2, 29})
}

/* Verifies +, ++, and .+ recurrence plus explicit invalid-date policy. */
@(test)
time_workflows_advance_recurrence_deterministically :: proc(t: ^testing.T) {
	stored := Local_Date_Time{date = {2026, 9, 1}}
	completed := Local_Date_Time{date = {2026, 9, 16}}
	now := Local_Date_Time{date = {2026, 9, 16}}
	interval := Calendar_Interval{amount = 1, unit = .Week}
	one, steps, advanced, failure := recurrence_advance(
		stored,
		completed,
		now,
		{kind = .Stored_Base, interval = interval},
		.Clamp,
	)
	testing.expectf(t, advanced, "stored recurrence failed with %v", failure.code)
	testing.expect_value(t, steps, u32(1))
	testing.expect_value(t, one.date, Civil_Date{2026, 9, 8})
	catch_up: Local_Date_Time
	catch_up, steps, advanced, failure = recurrence_advance(
		stored,
		completed,
		now,
		{kind = .Catch_Up, interval = interval},
		.Clamp,
	)
	testing.expectf(t, advanced, "catch-up recurrence failed with %v", failure.code)
	testing.expect_value(t, steps, u32(3))
	testing.expect_value(t, catch_up.date, Civil_Date{2026, 9, 22})
	completion: Local_Date_Time
	completion, _, advanced, _ = recurrence_advance(
		stored,
		completed,
		now,
		{kind = .Completion_Base, interval = interval},
		.Clamp,
	)
	testing.expect(t, advanced)
	testing.expect_value(t, completion.date, Civil_Date{2026, 9, 23})

	leap := Local_Date_Time{date = {2024, 2, 29}}
	_, _, advanced, failure = recurrence_advance(
		leap,
		leap,
		leap,
		{kind = .Stored_Base, interval = {amount = 1, unit = .Year}},
		.Reject,
	)
	testing.expect(t, !advanced)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	clamped: Local_Date_Time
	clamped, _, advanced, _ = recurrence_advance(
		leap,
		leap,
		leap,
		{kind = .Stored_Base, interval = {amount = 1, unit = .Year}},
		.Clamp,
	)
	testing.expect(t, advanced)
	testing.expect_value(t, clamped.date, Civil_Date{2025, 2, 28})
	_, steps, advanced, failure = recurrence_advance(
		{date = {2000, 1, 1}},
		{date = {2000, 1, 1}},
		{date = {2026, 1, 1}},
		{kind = .Catch_Up, interval = {amount = 1, unit = .Day}},
		.Clamp,
	)
	testing.expect(t, !advanced)
	testing.expect_value(t, steps, u32(MAX_RECURRENCE_STEPS))
	testing.expect_value(t, failure.code, Failure_Code.Limited)
}

/* Verifies related schedule and deadline changes publish as one exact source transaction. */
@(test)
time_workflows_prepare_one_atomic_source_update :: proc(t: ^testing.T) {
	source_text := "* TODO Ship\nSCHEDULED: <2026-09-16 Wed>\nDEADLINE: <2026-09-18 Fri>\n"
	expected := "* TODO Ship\nSCHEDULED: <2026-09-23 Wed>\nDEADLINE: <2026-09-25 Fri>\n"
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
	testing.expectf(t, analyzed, "time analysis failed with %v", analysis_failure.code)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	heading, found := time_workflows_test_node(&analysis, .Heading)
	testing.expect(t, found)
	if !found do return
	target := Semantic_Target{node_id = heading.id, kind = heading.kind, range = heading.range}
	request := Time_Source_Edit_Request{
		operation_id = 41,
		scope = scope,
		target = target,
		replacements = []Time_Source_Replacement{
			{current = "<2026-09-16 Wed>", replacement = "<2026-09-23 Wed>"},
			{current = "<2026-09-18 Fri>", replacement = "<2026-09-25 Fri>"},
		},
		rewrite_generation = 41,
	}
	plan: language.Jan_Rewrite_Plan
	planned, failure := time_source_plan_prepare(&plan, &analysis, source, request)
	testing.expectf(t, planned, "time source plan failed with %v", failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	descriptor, inspected := language.jan_rewrite_plan_descriptor(&plan)
	testing.expect(t, inspected)
	testing.expect_value(t, descriptor.splice_count, u32(1))
	testing.expect(t, time_workflows_test_commit(t, &plan, scope, source_text, expected))

	stale := request
	stale.target.range.scope.source_revision += 1
	stale_plan: language.Jan_Rewrite_Plan
	planned, failure = time_source_plan_prepare(&stale_plan, &analysis, source, stale)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Planning_Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 0}
	fault_plan: language.Jan_Rewrite_Plan
	planned, failure = time_source_plan_prepare(
		&fault_plan,
		&analysis,
		source,
		request,
		planning_test_failing_allocator(&failing),
	)
	testing.expect(t, !planned)
	testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies repeating task completion advances state, logs, and timestamp together. */
@(test)
time_workflows_complete_repeating_tasks_atomically :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, failure := planning_configuration_init(&configuration, 22, 29)
	testing.expect(t, initialized)
	if !initialized do return
	defer planning_configuration_close(&configuration)
	states := [2]Workflow_State_Candidate{
		{name = "TODO", presentation = .Todo, log = .None},
		{name = "DONE", finished = true, presentation = .Done, log = .Time},
	}
	workflows := [1]Workflow_Candidate{{identity = "default", states = states[:]}}
	published: bool
	_, published, failure = planning_configuration_publish(
		&configuration,
		{generation = 23, provider_generation = 29, workflows = workflows[:]},
	)
	testing.expectf(t, published, "repeat configuration failed with %v", failure.code)
	if !published do return

	source_text := "* TODO Review\nSCHEDULED: <2026-09-16 Wed +1w>\n"
	source := transmute([]u8)source_text
	scope := planning_test_scope()
	scope.source_bytes = u64(len(source))
	scope.analysis.source_revision = 0
	scope.analysis.configuration = language.jan_factory_configuration(1).identity
	owner: language.Jan_Structural_Owner
	owner_ok, _ := language.jan_structural_owner_init(&owner, scope.analysis.parser_generation)
	if !owner_ok do return
	defer language.jan_structural_owner_close(&owner)
	analysis, analyzed, _ := language.jan_structural_owner_analyze(&owner, source, scope.analysis)
	if !analyzed do return
	defer language.jan_structural_analysis_close(&analysis)
	heading, found := time_workflows_test_node(&analysis, .Heading)
	if !found do return
	target := Semantic_Target{node_id = heading.id, kind = heading.kind, range = heading.range}
	plan: language.Jan_Rewrite_Plan
	transition, advanced_count, planned, plan_failure := repeating_task_transition_plan_prepare(
		&plan,
		&analysis,
		source,
		&configuration,
		{
			task = {
				operation_id = 42,
				scope = scope,
				target = target,
				workflow = "default",
				current_state = "TODO",
				destination_state = "DONE",
				log_record = "CLOSED: [2026-09-16 Wed 11:15]\n",
				rewrite_generation = 42,
			},
			timestamps = []Repeating_Timestamp_Candidate{{
				current = "<2026-09-16 Wed +1w>",
				spec = {
					local = {date = {2026, 9, 16}},
					active = true,
					recurrence = {kind = .Stored_Base, interval = {amount = 1, unit = .Week}},
				},
			}},
			completed = {date = {2026, 9, 16}},
			now = {date = {2026, 9, 16}},
			policy = .Clamp,
			locale = "en-US",
		},
	)
	testing.expectf(t, planned, "repeat completion failed with %v", plan_failure.code)
	if !planned do return
	defer language.jan_rewrite_plan_close(&plan)
	testing.expect(t, transition.finished)
	testing.expect_value(t, advanced_count, u32(1))
	testing.expect(t, time_workflows_test_commit(
		t,
		&plan,
		scope,
		source_text,
		"* DONE Review\nCLOSED: [2026-09-16 Wed 11:15]\nSCHEDULED: <2026-09-23 Wed +1w>\n",
	))
}

/* Verifies durable clock lifecycle, idle decisions, recovery, and table totals. */
@(test)
time_workflows_manage_one_durable_clock_domain :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	resource, resource_ok := resource_identity_copy(1, "project/notes.org")
	zone, zone_ok := active_clock_time_zone_copy("Europe/Warsaw")
	testing.expect(t, resource_ok && zone_ok)
	request := Clock_Start_Request{
		domain = 1,
		resource = resource,
		scope = scope,
		target = planning_test_target(scope),
		started_at = {seconds = 1_000},
		time_zone = zone,
		transition = .Start,
	}
	record, started, failure := active_clock_start(nil, request)
	testing.expectf(t, started, "clock start failed with %v", failure.code)
	_, duplicate, duplicate_failure := active_clock_start(&record, request)
	testing.expect(t, !duplicate)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Conflict)
	idle: Clock_Idle_Result
	idle_ok: bool
	idle, idle_ok, failure = active_clock_resolve_idle(
		record,
		{seconds = 1_600},
		{seconds = 1_900},
		.Subtract,
	)
	testing.expectf(t, idle_ok, "idle resolution failed with %v", failure.code)
	testing.expect_value(t, idle.excluded_seconds, u64(300))
	closed: Active_Clock_Record
	entry: Clock_Entry
	stopped: bool
	closed, entry, stopped, failure = active_clock_stop(record, {seconds = 4_600}, idle.excluded_seconds)
	testing.expectf(t, stopped, "clock stop failed with %v", failure.code)
	testing.expect_value(t, closed.recovery_state, Clock_Recovery_State.Resolved)
	elapsed, elapsed_ok := clock_entry_elapsed_seconds(entry)
	testing.expect(t, elapsed_ok)
	testing.expect_value(t, elapsed, u64(3_300))
	resumed: Active_Clock_Record
	resumed_ok: bool
	resumed, resumed_ok, failure = active_clock_resume(
		entry,
		scope,
		request.target,
		{seconds = 5_000},
		zone,
	)
	testing.expectf(t, resumed_ok, "clock resume failed with %v", failure.code)
	testing.expect_value(t, resumed.last_transition, Clock_Transition.Resume)

	next_target := request.target
	next_target.node_id = 6
	next_request := request
	next_request.target = next_target
	switched: Active_Clock_Record
	prior: Clock_Entry
	switched_ok: bool
	switched, prior, switched_ok, failure = active_clock_switch(resumed, next_request, {seconds = 5_600})
	testing.expectf(t, switched_ok, "clock switch failed with %v", failure.code)
	testing.expect_value(t, switched.last_transition, Clock_Transition.Switch)
	testing.expect_value(t, prior.target.node_id, request.target.node_id)

	stale_scope := scope.analysis
	stale_scope.source_revision += 1
	testing.expect_value(t, active_clock_startup_state(switched, stale_scope), Clock_Recovery_State.Recovery_Required)
	recovered_target := switched.target
	recovered_target.range.scope = stale_scope
	recovery_scope := scope
	recovery_scope.analysis = stale_scope
	recovered: Clock_Recovery_Result
	recovered_ok: bool
	recovered, recovered_ok, failure = active_clock_recover(
		switched,
		recovery_scope,
		recovered_target,
		.Resume,
		{seconds = 6_000},
	)
	testing.expectf(t, recovered_ok, "clock recovery failed with %v", failure.code)
	testing.expect_value(t, recovered.record.last_transition, Clock_Transition.Recovery)

	entries := []Clock_Entry{entry, prior}
	rows: [2]Clock_Table_Row
	count, summarized, table_failure := clock_table_summarize(entries, rows[:])
	testing.expectf(t, summarized, "clock table failed with %v", table_failure.code)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, rows[0].entry_count, u32(2))
}

/* Verifies effort and relative timers remain independent from clocks and notifications. */
@(test)
time_workflows_manage_effort_and_relative_timers :: proc(t: ^testing.T) {
	effort, parsed := effort_parse("1:30")
	testing.expect(t, parsed)
	testing.expect_value(t, effort.seconds, u64(5_400))
	minutes: Duration_Value
	minutes, parsed = effort_parse("90m")
	testing.expect(t, parsed)
	testing.expect_value(t, minutes.seconds, effort.seconds)
	text, formatted := duration_text_format(effort)
	testing.expect(t, formatted)
	testing.expect_value(t, duration_text(&text), "1:30")
	_, parsed = effort_parse("1:99")
	testing.expect(t, !parsed)

	timer, started, failure := relative_timer_start(1, .Countdown, {seconds = 100}, 60)
	testing.expectf(t, started, "timer start failed with %v", failure.code)
	snapshot: Relative_Timer_Snapshot
	ticked: bool
	snapshot, ticked, failure = relative_timer_tick(timer, {seconds = 160}, false)
	testing.expectf(t, ticked, "timer tick failed with %v", failure.code)
	testing.expect_value(t, snapshot.record.state, Relative_Timer_State.Completed)
	testing.expect_value(t, snapshot.notification, Timer_Notification_Outcome.Unavailable)
	testing.expect_value(t, snapshot.elapsed, u64(60))
	_, ticked, failure = relative_timer_tick(timer, {seconds = 120}, true, true)
	testing.expect(t, !ticked)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	stopwatch: Relative_Timer_Record
	stopwatch, started, _ = relative_timer_start(2, .Stopwatch, {seconds = 200})
	testing.expect(t, started)
	paused, paused_ok, _ := relative_timer_pause(stopwatch, {seconds = 230})
	testing.expect(t, paused_ok)
	resumed, resumed_ok, _ := relative_timer_resume(paused, {seconds = 300})
	testing.expect(t, resumed_ok)
	stopped, stopped_ok, _ := relative_timer_stop(resumed, {seconds = 345})
	testing.expect(t, stopped_ok)
	testing.expect_value(t, stopped.accumulated_seconds, u64(75))
	storage: [32]u8
	elapsed_text, elapsed_ok := relative_timer_elapsed_text(3_661, storage[:])
	testing.expect(t, elapsed_ok)
	testing.expect_value(t, elapsed_text, "01:01:01")
}

@(private = "file")
time_workflows_test_node :: proc(
	analysis: ^language.Jan_Structural_Analysis,
	kind: language.Jan_Node_Kind,
) -> (language.Jan_Node_Record, bool) {
	for node in language.jan_structural_analysis_nodes(analysis) {
		if node.kind == kind do return node, true
	}
	return {}, false
}

@(private = "file")
time_workflows_test_commit :: proc(
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
	if !buffer_ok do return false
	defer editor.buffer_close(&buffer)
	root: transaction.Multibuffer_Transaction
	admitted, _ := language.jan_rewrite_plan_admit(
		plan,
		&buffer,
		&root,
		71,
		71,
		"jan-time",
		transaction.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	if !admitted do return false
	_, committed, _ := transaction.multibuffer_commit(&root)
	transaction.multibuffer_close(&root)
	if !committed do return false
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	if !opened do return false
	defer editor.buffer_snapshot_close(&snapshot)
	actual, allocation_error := make([]u8, len(expected), context.temp_allocator)
	if allocation_error != nil do return false
	defer delete(actual, context.temp_allocator)
	copied, copied_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, actual)
	return copied_ok && copied == u64(len(expected)) && string(actual) == expected
}
