// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:mem"
import "core:testing"
import "base:runtime"

@(private = "file")
Controller_Failing_Allocator :: struct {
	backing: runtime.Allocator,
	fail:    bool,
}

@(private = "file")
controller_failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^Controller_Failing_Allocator)data
	if state.fail && (mode == .Alloc || mode == .Alloc_Non_Zeroed ||
	   mode == .Resize || mode == .Resize_Non_Zeroed) {
		return nil, .Out_Of_Memory
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private = "file")
controller_failing_allocator :: proc(state: ^Controller_Failing_Allocator) -> runtime.Allocator {
	return {procedure = controller_failing_allocator_proc, data = state}
}

@(private)
controller_fixture :: proc(
	registry: ^Role_Registry,
	controller: ^Controller,
	allocator := context.allocator,
	policy := DEFAULT_SESSION_POLICY,
) -> (Composition_Scope, bool) {
	initialized, _ := registry_init(registry, 81, DEFAULT_LIMITS, allocator)
	if !initialized do return {}, false
	composition, scoped, _ := registry_scope(registry)
	if !scoped do return {}, false
	controller_ok, _ := controller_init(
		controller,
		82,
		1,
		composition,
		DEFAULT_LIMITS,
		allocator,
		policy,
	)
	return composition, controller_ok
}

@(private)
controller_request :: proc(id, generation, revision: u64, composition: Composition_Scope) -> Request {
	request := test_request()
	provider := composition.selections[0].selected
	request.id = Request_ID(id)
	request.generation = Request_Generation(generation)
	request.scope.document_revision = Document_Revision(revision)
	request.scope.transmitted_revision = Document_Revision(revision)
	request.scope.provider_id = Provider_ID(provider.implementation_id)
	request.scope.provider_generation = Provider_Generation(provider.implementation_generation)
	return request
}

@(private)
controller_batch :: proc(request: Request, items: []Candidate, generation := Batch_Generation(1)) -> Batch {
	for &item in items {
		item.provenance.provider_id = request.scope.provider_id
		item.provenance.provider_generation = request.scope.provider_generation
	}
	return {
		id = 91,
		generation = generation,
		request_id = request.id,
		request_generation = request.generation,
		scope = request.scope,
		request_cursor_byte = request.cursor_byte,
		query_range = request.query_range,
		disposition = .Complete,
		items = items,
		item_count = u16(len(items)),
	}
}

/* Verifies deterministic request and batch publication transitions. */
@(test)
controller_publishes_ready_and_empty_sessions :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(101, 1, 3, composition)
	started, _ := controller_start(&controller, 102, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	items := []Candidate{test_candidate(103)}
	batch := controller_batch(request, items)
	published, _ := controller_publish(&controller, &batch)
	ready, inspected, _ := controller_inspect(&controller)
	retired, _ := controller_retire(&controller)

	empty_request := controller_request(104, 2, 4, composition)
	empty_started, _ := controller_start(&controller, 105, 2, empty_request, composition)
	empty_queued, _ := controller_queue(&controller)
	empty_sent, _ := controller_send(&controller)
	empty_batch := controller_batch(empty_request, nil, 2)
	empty_published, _ := controller_publish(&controller, &empty_batch)
	empty, empty_inspected, _ := controller_inspect(&controller)

	testing.expect(t, started && queued && sent && published && inspected && retired)
	testing.expect_value(t, ready.state, Session_State.Ready)
	testing.expect_value(t, ready.selected_candidate, Candidate_ID(103))
	testing.expect(t, empty_started && empty_queued && empty_sent && empty_published && empty_inspected)
	testing.expect_value(t, empty.state, Session_State.Empty)
}

/* Verifies replacement rejects late response and admits only the newest generation. */
@(test)
controller_rejects_late_replaced_response :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	first := controller_request(111, 1, 3, composition)
	second := controller_request(112, 2, 4, composition)
	started, _ := controller_start(&controller, 113, 1, first, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	updated, _ := controller_update(&controller, second)
	second_queued, _ := controller_queue(&controller)
	second_sent, _ := controller_send(&controller)
	late_items := []Candidate{test_candidate(114)}
	late_batch := controller_batch(first, late_items)
	late, late_failure := controller_publish(&controller, &late_batch)
	current_items := []Candidate{test_candidate(115)}
	current_batch := controller_batch(second, current_items, 2)
	current, _ := controller_publish(&controller, &current_batch)
	inspection, _, _ := controller_inspect(&controller)

	testing.expect(t, started && queued && sent && updated && second_queued && second_sent)
	testing.expect(t, !late && current)
	testing.expect_value(t, late_failure.code, Failure_Code.Stale_Request)
	testing.expect_value(t, inspection.selected_candidate, Candidate_ID(115))
}

/* Verifies document changes and repeated cancellation preserve plain editing. */
@(test)
controller_contains_change_and_cancel :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(121, 1, 3, composition)
	started, _ := controller_start(&controller, 122, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	compatible, _ := controller_document_changed(&controller, 3)
	unchanged, _, _ := controller_inspect(&controller)
	current, stale_failure := controller_document_changed(&controller, 4)
	cancelled, _, _ := controller_inspect(&controller)
	repeated, repeated_failure := controller_cancel(&controller)

	testing.expect(t, started && queued && sent && compatible && !current && !repeated)
	testing.expect_value(t, unchanged.state, Session_State.Requesting)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Document)
	testing.expect_value(t, cancelled.state, Session_State.Dismissed)
	testing.expect_value(t, repeated_failure.code, Failure_Code.Invalid_State)
}

/* Verifies provider replacement dismisses the exact active session. */
@(test)
controller_reconciles_provider_generation :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)

	request := controller_request(131, 1, 3, composition)
	started, _ := controller_start(&controller, 132, 1, request, composition)
	provider, registered, _ := registry_register(&registry, test_definition("replacement", .Provider))
	after_register, _, _ := registry_scope(&registry)
	replaced, selected, _ := registry_select(&registry, after_register, provider.handle)
	compatible, reconcile_failure := controller_reconcile_composition(&controller, replaced)
	inspection, _, _ := controller_inspect(&controller)

	testing.expect(t, started && registered && selected && !compatible)
	testing.expect_value(t, reconcile_failure.code, Failure_Code.Stale_Provider)
	testing.expect_value(t, inspection.state, Session_State.Dismissed)
}

/* Verifies copied candidate storage and controller teardown release all allocations. */
@(test)
completion_controller_releases_owned_batch :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller, allocator)
	request := controller_request(141, 1, 3, composition)
	started, _ := controller_start(&controller, 142, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	items := []Candidate{test_candidate(143), test_candidate(144)}
	batch := controller_batch(request, items)
	published, _ := controller_publish(&controller, &batch)
	closed_controller, _ := controller_close(&controller)
	closed_registry, _ := registry_close(&registry)

	testing.expect(t, initialized && started && queued && sent && published)
	testing.expect(t, closed_controller && closed_registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies batch allocation failure preserves the live request and leaks nothing. */
@(test)
controller_contains_batch_allocation_failure :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	backing := mem.tracking_allocator(&tracking)
	failing := Controller_Failing_Allocator{backing = backing}
	allocator := controller_failing_allocator(&failing)
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller, allocator)
	request := controller_request(151, 1, 3, composition)
	started, _ := controller_start(&controller, 152, 1, request, composition)
	queued, _ := controller_queue(&controller)
	sent, _ := controller_send(&controller)
	items := []Candidate{test_candidate(153)}
	batch := controller_batch(request, items)
	failing.fail = true
	published, publish_failure := controller_publish(&controller, &batch)
	failing.fail = false
	inspection, inspected, _ := controller_inspect(&controller)
	closed_controller, _ := controller_close(&controller)
	closed_registry, _ := registry_close(&registry)

	testing.expect(t, initialized && started && queued && sent && !published && inspected)
	testing.expect_value(t, publish_failure.code, Failure_Code.Allocation)
	testing.expect_value(t, inspection.state, Session_State.Requesting)
	testing.expect(t, closed_controller && closed_registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies bounded request replacement rejects overflow without losing the current request. */
@(test)
completion_controller_bounds_request_replacement :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 83)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	composition, _, _ := registry_scope(&registry)
	limits := DEFAULT_LIMITS
	limits.request_replacements = 1
	controller: Controller
	controller_ready, _ := controller_init(&controller, 84, 1, composition, limits)
	testing.expect(t, controller_ready)
	if !controller_ready do return
	defer controller_close(&controller)

	first := controller_request(161, 1, 3, composition)
	second := controller_request(162, 2, 4, composition)
	third := controller_request(163, 3, 5, composition)
	started, _ := controller_start(&controller, 164, 1, first, composition)
	updated, _ := controller_update(&controller, second)
	overflow, overflow_failure := controller_update(&controller, third)
	inspection, _, _ := controller_inspect(&controller)

	testing.expect(t, started && updated && !overflow)
	testing.expect_value(t, overflow_failure.code, Failure_Code.Request_Limit)
	testing.expect_value(t, inspection.request.id, second.id)
}
