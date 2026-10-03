// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback

import "core:testing"

/* Verifies calibrated defaults and every configurable policy boundary. */
@(test)
feedback_policy_is_bounded :: proc(t: ^testing.T) {
	ok, failure := policy_validate(DEFAULT_POLICY)
	testing.expectf(t, ok, "default policy failed with %v", failure.code)
	invalid := DEFAULT_POLICY
	invalid.active_records = MIN_ACTIVE_RECORDS - 1
	ok, failure = policy_validate(invalid)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.field, Policy_Field.Active_Records)
}

/* Verifies admission copies semantic content and redacts sensitive inspection. */
@(test)
feedback_admission_is_copied_and_redacted :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(1), DEFAULT_POLICY)
	if !ready do return
	message := make([]u8, len("private build path"))
	defer delete(message)
	copy(message, "private build path")
	proposal := test_notification(1, 1, 1, "Build failed")
	proposal.message = string(message)
	proposal.sensitivity = .Sensitive
	proposal.metadata = []Metadata_Proposal{{key = "path", value = "/private/source", sensitive = true}}
	_, admitted, failure := registry_publish(&registry, proposal)
	testing.expectf(t, admitted, "admission failed with %v", failure.code)
	message[0] = 'X'
	stats, _, _ := registry_stats(&registry)
	inspection, inspected, inspect_failure := registry_inspect(
		&registry,
		{expected_generation = stats.generation, active_limit = 1, history_limit = 1},
		context.allocator,
	)
	testing.expectf(t, inspected, "inspection failed with %v", inspect_failure.code)
	if inspected {
		testing.expect_value(t, inspection.active[0].title, "<redacted>")
		testing.expect_value(t, inspection.active[0].message, "<redacted>")
		testing.expect_value(t, inspection.active[0].metadata[0].value, "<redacted>")
		inspection_release(&inspection, context.allocator)
	}
	test_registry_close(t, &registry)
}

/* Verifies exact replacement rejects stale generations and preserves last-valid state. */
@(test)
feedback_replacement_preserves_last_valid_generation :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(2), DEFAULT_POLICY)
	if !ready do return
	first := test_notification(7, 1, 1, "Saved")
	registry_publish(&registry, first)
	replacement := test_notification(7, 2, 2, "Saved again")
	replacement.replacement = 7
	_, replaced, replace_failure := registry_publish(&registry, replacement)
	testing.expectf(t, replaced, "replacement failed with %v", replace_failure.code)
	stale := test_notification(7, 2, 3, "Stale")
	stale.replacement = 7
	_, admitted, stale_failure := registry_publish(&registry, stale)
	testing.expect(t, !admitted)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
	stats, _, _ := registry_stats(&registry)
	inspection, inspected, _ := registry_inspect(
		&registry,
		{expected_generation = stats.generation, active_limit = 1},
		context.allocator,
	)
	if inspected {
		testing.expect_value(t, inspection.active[0].title, "Saved again")
		testing.expect_value(t, inspection.active[0].generation, Record_Generation(2))
		inspection_release(&inspection, context.allocator)
	}
	test_registry_close(t, &registry)
}

/* Verifies repeated equivalent notifications coalesce without losing severity. */
@(test)
feedback_notifications_coalesce_by_checked_source_key :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(3), DEFAULT_POLICY)
	if !ready do return
	first := test_notification(10, 1, 1, "Provider unavailable")
	first.coalescing_key = "provider-state"
	registry_publish(&registry, first)
	second := test_notification(11, 2, 2, "Provider still unavailable")
	second.coalescing_key = "provider-state"
	second.severity = .Error
	_, admitted, failure := registry_publish(&registry, second)
	testing.expectf(t, admitted, "coalescence failed with %v", failure.code)
	stats, _, _ := registry_stats(&registry)
	inspection, inspected, _ := registry_inspect(
		&registry,
		{expected_generation = stats.generation, active_limit = 2},
		context.allocator,
	)
	if inspected {
		testing.expect_value(t, len(inspection.active), 1)
		testing.expect_value(t, inspection.active[0].id, Record_ID(10))
		testing.expect_value(t, inspection.active[0].severity, Severity.Error)
		testing.expect_value(t, inspection.active[0].repetition_count, u32(2))
		inspection_release(&inspection, context.allocator)
	}
	test_registry_close(t, &registry)
}

/* Verifies progress advances monotonically and terminal outcomes leave active state. */
@(test)
feedback_progress_transitions_to_retained_completion :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(4), DEFAULT_POLICY)
	if !ready do return
	pending := test_progress(20, 1, 1, .Pending, 0, 4)
	registry_publish(&registry, pending)
	running := test_progress(20, 2, 2, .Running, 2, 4)
	running.replacement = 20
	_, advanced, advance_failure := registry_publish(&registry, running)
	testing.expectf(t, advanced, "running update failed with %v", advance_failure.code)
	complete := test_progress(20, 3, 3, .Succeeded, 4, 4)
	complete.replacement = 20
	complete.class = .Completion
	_, completed, completion_failure := registry_publish(&registry, complete)
	testing.expectf(t, completed, "completion failed with %v", completion_failure.code)
	stats, _, _ := registry_stats(&registry)
	testing.expect_value(t, stats.usage.active_records, u64(0))
	testing.expect_value(t, stats.usage.history_records, u64(1))
	late := test_progress(20, 4, 4, .Running, 3, 4)
	late.replacement = 20
	_, accepted, late_failure := registry_publish(&registry, late)
	testing.expect(t, !accepted)
	testing.expect_value(t, late_failure.code, Failure_Code.Record_Not_Found)
	test_registry_close(t, &registry)
}

/* Verifies dismissal, expiry, and source retirement affect active state only. */
@(test)
feedback_lifecycle_operations_are_independent_from_history :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(5), DEFAULT_POLICY)
	if !ready do return
	retained := test_notification(30, 1, 1, "Retained")
	retained.lifecycle = .Retained
	retained.retention = .History
	registry_publish(&registry, retained)
	dismissed, dismiss_failure := registry_dismiss(&registry, 30, 1)
	testing.expectf(t, dismissed, "dismiss failed with %v", dismiss_failure.code)
	transient := test_notification(31, 1, 2, "Transient")
	registry_publish(&registry, transient)
	stats, _, _ := registry_stats(&registry)
	expired, _ := registry_expire(&registry, stats.sequence)
	testing.expect_value(t, expired, u64(1))
	source_bound := test_notification(32, 1, 3, "Source bound")
	source_bound.lifecycle = .Source_Bound
	registry_publish(&registry, source_bound)
	retired, _ := registry_retire_source(&registry, source_bound.source)
	testing.expect_value(t, retired, u64(1))
	stats, _, _ = registry_stats(&registry)
	testing.expect_value(t, stats.usage.active_records, u64(0))
	testing.expect_value(t, stats.usage.history_records, u64(1))
	cleared, _ := registry_clear_history(&registry)
	testing.expect_value(t, cleared, u64(1))
	test_registry_close(t, &registry)
}

/* Verifies bounded history evicts ordinary records and never displaces attention for ordinary input. */
@(test)
feedback_history_has_deterministic_priority_eviction :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.history_records = MIN_HISTORY_RECORDS
	policy.history_bytes = MIN_HISTORY_BYTES
	registry, ready := test_registry(t, Registry_ID(6), policy)
	if !ready do return
	for index in 0 ..< int(MIN_HISTORY_RECORDS) {
		proposal := test_notification(Record_ID(index + 1), 1, Source_Generation(index + 1), "Ordinary")
		proposal.retention = .History
		registry_publish(&registry, proposal)
	}
	extra := test_notification(100, 1, 100, "Newest")
	extra.retention = .History
	registry_publish(&registry, extra)
	stats, _, _ := registry_stats(&registry)
	testing.expect_value(t, stats.usage.history_records, MIN_HISTORY_RECORDS)
	testing.expect_value(t, stats.usage.evicted_history, u64(1))
	test_registry_close(t, &registry)

	registry, ready = test_registry(t, Registry_ID(7), policy)
	if !ready do return
	for index in 0 ..< int(MIN_HISTORY_RECORDS) {
		proposal := test_notification(Record_ID(index + 1), 1, Source_Generation(index + 1), "Attention")
		proposal.attention = .Required
		proposal.lifecycle = .Attention
		proposal.retention = .History
		registry_publish(&registry, proposal)
	}
	extra = test_notification(101, 1, 101, "Ordinary")
	extra.retention = .History
	registry_publish(&registry, extra)
	stats, _, _ = registry_stats(&registry)
	testing.expect_value(t, stats.usage.history_records, MIN_HISTORY_RECORDS)
	testing.expect_value(t, stats.usage.evicted_history, u64(0))
	testing.expect_value(t, stats.usage.dropped_history, u64(1))
	test_registry_close(t, &registry)
}

/* Verifies cancellation returns copied command authority without mutating operation state. */
@(test)
feedback_cancellation_preserves_source_authority :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, Registry_ID(8), DEFAULT_POLICY)
	if !ready do return
	proposal := test_progress(40, 1, 1, .Running, 1, 10)
	proposal.actions = []Action_Proposal{{id = 1, command = "cancel-build", argument = "build-40", cancel = true}}
	registry_publish(&registry, proposal)
	cancellation, available, failure := registry_request_cancellation(
		&registry,
		{record_id = 40, record_generation = 1, source = proposal.source},
		context.allocator,
	)
	testing.expectf(t, available, "cancellation unavailable with %v", failure.code)
	if available {
		testing.expect_value(t, cancellation.action.command, "cancel-build")
		cancellation_release(&cancellation, context.allocator)
	}
	stats, _, _ := registry_stats(&registry)
	testing.expect_value(t, stats.usage.active_records, u64(1))
	test_registry_close(t, &registry)
}

/* Verifies current and retained actions require exact record and source authority. */
@(test)
feedback_actions_revalidate_exact_authority :: proc(t: ^testing.T) {
	registry, ready := test_registry(t, 17, DEFAULT_POLICY)
	if !ready do return
	defer test_registry_close(t, &registry)
	proposal := test_notification(41, 1, 1, "Package log")
	proposal.lifecycle = .Retained
	proposal.retention = .History
	proposal.actions = []Action_Proposal{{id = 7, command = "show-log", argument = "operation-41"}}
	record, published, publish_failure := registry_publish(&registry, proposal)
	testing.expectf(t, published, "action publication failed with %v", publish_failure.code)
	if !published do return
	request := Action_Request {
		record_id = record.id,
		record_generation = record.generation,
		source = record.source,
		action_id = 7,
	}
	authority, resolved, resolve_failure := registry_resolve_action(&registry, request, context.allocator)
	testing.expectf(t, resolved, "action resolution failed with %v", resolve_failure.code)
	if resolved {
		testing.expect_value(t, authority.action.command, "show-log")
		testing.expect_value(t, authority.action.argument, "operation-41")
		action_authority_release(&authority, context.allocator)
	}
	request.record_generation += 1
	stale_failure: Failure
	_, resolved, stale_failure = registry_resolve_action(&registry, request, context.allocator)
	testing.expect(t, !resolved)
	testing.expect_value(t, stale_failure.code, Failure_Code.Record_Not_Found)
}

/* Verifies headless observation coalesces progress and always exposes redacted terminal failure. */
@(test)
feedback_headless_observation_is_bounded_and_redacted :: proc(t: ^testing.T) {
	observer: Headless_Observer
	testing.expect(t, headless_observer_init(&observer, 3))
	storage: [MAX_HEADLESS_BYTES]u8
	first := test_progress_record(50, 1, .Running, .Ordinary)
	_, emitted, failure := headless_observe(&observer, first, storage[:])
	testing.expectf(t, emitted, "first observation failed with %v", failure.code)
	second := test_progress_record(50, 2, .Running, .Ordinary)
	_, emitted, _ = headless_observe(&observer, second, storage[:])
	testing.expect(t, !emitted)
	third := test_progress_record(50, 3, .Running, .Ordinary)
	_, emitted, _ = headless_observe(&observer, third, storage[:])
	testing.expect(t, emitted)
	failure_record := test_progress_record(50, 4, .Failed, .Required)
	failure_record.severity = .Error
	failure_record.sensitivity = .Sensitive
	failure_record.message = "token=secret"
	observation: Headless_Observation
	observation, emitted, _ = headless_observe(&observer, failure_record, storage[:])
	testing.expect(t, emitted)
	testing.expect(t, observation.terminal)
	testing.expect_value(t, observation.content, "Error: <redacted> - <redacted>")
	testing.expect_value(t, observer.suppressed_updates, u64(1))
}

@(private)
test_registry :: proc(t: ^testing.T, id: Registry_ID, policy: Policy) -> (registry: Registry, ready: bool) {
	failure: Failure
	ready, failure = registry_init(&registry, id, {persistent = context.allocator, temporary = context.temp_allocator}, policy)
	testing.expectf(t, ready, "registry init failed with %v", failure.code)
	return registry, ready
}

@(private)
test_registry_close :: proc(t: ^testing.T, registry: ^Registry) {
	closed, failure := registry_close(registry)
	testing.expectf(t, closed, "registry close failed with %v", failure.code)
}

@(private)
test_notification :: proc(id: Record_ID, generation: Record_Generation, source_generation: Source_Generation, title: string) -> Proposal {
	return {
		id = id,
		generation = generation,
		source = {id = 1, generation = source_generation},
		kind = .Notification,
		class = .Information,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Transient,
		retention = .None,
		visibility = .Public,
		title = title,
	}
}

@(private)
test_progress :: proc(id: Record_ID, generation: Record_Generation, source_generation: Source_Generation, state: Progress_State, current, total: u64) -> Proposal {
	return {
		id = id,
		generation = generation,
		source = {id = 2, generation = source_generation},
		kind = .Progress,
		class = .Progress,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Retained,
		retention = .History,
		visibility = .Public,
		title = "Build",
		progress = {state = state, measurement = .Determinate, current = current, total = total, phase = "compile"},
	}
}

@(private)
test_progress_record :: proc(id: Record_ID, generation: Record_Generation, state: Progress_State, attention: Attention) -> Record {
	return {
		id = id,
		generation = generation,
		source = {id = 2, generation = Source_Generation(generation)},
		kind = .Progress,
		class = .Progress,
		severity = .Information,
		attention = attention,
		lifecycle = .Retained,
		retention = .History,
		visibility = .Public,
		title = "Build",
		progress = {state = state, measurement = .Determinate, current = u64(generation), total = 10, phase = "compile"},
	}
}
