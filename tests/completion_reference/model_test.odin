// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion_reference

import "core:mem"
import "core:testing"
import "base:runtime"

Failing_Allocator :: struct {
	fail: bool,
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size: int,
	alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^Failing_Allocator)data
	if mode == .Alloc && state.fail {
		return nil, .Out_Of_Memory
	}
	return runtime.default_allocator_proc(nil, mode, size, alignment, old_memory, old_size, location)
}

failing_allocator :: proc(state: ^Failing_Allocator) -> runtime.Allocator {
	return {procedure = failing_allocator_proc, data = state}
}

test_context :: proc(revision, provider_generation: u64) -> Context {
	return {document = 7, revision = revision, view = 11, provider_generation = provider_generation}
}

test_request :: proc(id, generation, revision, provider_generation: u64) -> Request {
	return {
		id = id,
		generation = generation,
		scope = test_context(revision, provider_generation),
		trigger = .Explicit,
		state = .Prepared,
	}
}

/* Verifies one exact request publishes candidates and a stable initial selection. */
@(test)
completion_model_publishes_exact_generation :: proc(t: ^testing.T) {
	session: Session
	request := test_request(13, 1, 5, 2)
	started := start(&session, 17, 1, request)
	sent := send(&session)
	published := publish(
		&session,
		request.id,
		request.generation,
		request.scope,
		[]Candidate{{id = 31}, {id = 32}},
	)
	defer retire(&session)

	testing.expect(t, started && sent && published)
	testing.expect_value(t, session.state, Session_State.Ready)
	testing.expect_value(t, session.selected_candidate, u64(31))
	testing.expect_value(t, len(session.candidates), 2)
}

/* Verifies empty completion is a valid terminal publication. */
@(test)
completion_model_accepts_empty_batch :: proc(t: ^testing.T) {
	session: Session
	request := test_request(14, 1, 6, 2)
	started := start(&session, 18, 1, request)
	sent := send(&session)
	published := publish(&session, request.id, request.generation, request.scope, nil)
	defer retire(&session)

	testing.expect(t, started && sent && published)
	testing.expect_value(t, session.state, Session_State.Empty)
	testing.expect_value(t, session.request.state, Request_State.Completed)
}

/* Verifies replacement rejects late responses from the cancelled request. */
@(test)
completion_model_rejects_late_replaced_response :: proc(t: ^testing.T) {
	session: Session
	first := test_request(15, 1, 7, 2)
	second := test_request(16, 2, 8, 2)
	started := start(&session, 19, 1, first)
	first_sent := send(&session)
	replaced := replace(&session, second)
	second_sent := send(&session)
	late := publish(&session, first.id, first.generation, first.scope, []Candidate{{id = 41}})
	current := publish(
		&session,
		second.id,
		second.generation,
		second.scope,
		[]Candidate{{id = 42}},
	)
	defer retire(&session)

	testing.expect(t, started && first_sent && replaced && second_sent && !late && current)
	testing.expect_value(t, session.selected_candidate, u64(42))
}

/* Verifies revision, provider generation, and cancellation races cannot publish. */
@(test)
rejects_stale_or_cancelled_response :: proc(t: ^testing.T) {
	session: Session
	request := test_request(17, 1, 9, 3)
	started := start(&session, 20, 1, request)
	sent := send(&session)
	stale_revision := publish(
		&session,
		request.id,
		request.generation,
		test_context(10, 3),
		[]Candidate{{id = 51}},
	)
	stale_provider := publish(
		&session,
		request.id,
		request.generation,
		test_context(9, 4),
		[]Candidate{{id = 51}},
	)
	cancelled := cancel(&session)
	late := publish(
		&session,
		request.id,
		request.generation,
		request.scope,
		[]Candidate{{id = 51}},
	)
	defer retire(&session)

	testing.expect(t, started && sent && !stale_revision && !stale_provider && cancelled && !late)
	testing.expect_value(t, session.state, Session_State.Dismissed)
	testing.expect_value(t, session.request.state, Request_State.Cancelled)
}

/* Verifies allocation failure preserves the requesting state and teardown leaks nothing. */
@(test)
completion_model_contains_allocation_failure :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session: Session
	request := test_request(18, 1, 10, 3)
	started := start(&session, 21, 1, request, allocator)
	sent := send(&session)
	failing: Failing_Allocator
	session.allocator = failing_allocator(&failing)
	failing.fail = true
	published := publish(
		&session,
		request.id,
		request.generation,
		request.scope,
		[]Candidate{{id = 61}},
	)
	session.allocator = allocator
	retired := retire(&session)

	testing.expect(t, started && sent && !published && retired)
	testing.expect_value(t, session.request.state, Request_State.Cancelled)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
