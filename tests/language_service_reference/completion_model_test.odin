// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_reference

import "core:testing"

completion_request :: proc(id, generation, session, binding, revision: u64) -> Completion_Request {
	return {
		id = id,
		generation = generation,
		session_generation = session,
		binding_generation = binding,
		revision = revision,
	}
}

/* Verifies negotiated completion admits complete and incomplete publications. */
@(test)
model_publishes_bounded_results :: proc(t: ^testing.T) {
	model := Completion{completion_enabled = true}
	request := completion_request(1, 1, 2, 3, 4)
	next, started := completion_start(model, request)
	model = next
	published: bool
	next, published = completion_publish(model, request, 8, true)
	model = next

	testing.expect(t, started && published)
	testing.expect_value(t, model.state, Completion_State.Complete)
	testing.expect(t, model.incomplete)
	testing.expect_value(t, model.candidate_count, u32(8))
}

/* Verifies absent capability and excessive candidate results preserve prior state. */
@(test)
model_contains_capability_failures :: proc(t: ^testing.T) {
	request := completion_request(2, 1, 2, 3, 4)
	disabled := Completion{}
	_, disabled_ok := completion_start(disabled, request)
	model := Completion{completion_enabled = true}
	next, started := completion_start(model, request)
	model = next
	prior := model
	_, overflow_ok := completion_publish(model, request, MAX_CANDIDATES + 1, false)

	testing.expect(t, !disabled_ok && started && !overflow_ok)
	testing.expect_value(t, model, prior)
}

/* Verifies cancellation and late responses cannot publish. */
@(test)
model_rejects_cancelled_response :: proc(t: ^testing.T) {
	model := Completion{completion_enabled = true}
	request := completion_request(3, 1, 2, 3, 4)
	next, started := completion_start(model, request)
	model = next
	cancelling: bool
	next, cancelling = completion_cancel(model)
	model = next
	_, late := completion_publish(model, request, 1, false)
	cancelled: bool
	next, cancelled = completion_cancelled(model)
	model = next

	testing.expect(t, started && cancelling && !late && cancelled)
	testing.expect_value(t, model.state, Completion_State.Idle)
}

/* Verifies request, revision, binding, and server generations reject stale results. */
@(test)
model_rejects_stale_authority :: proc(t: ^testing.T) {
	model := Completion{completion_enabled = true}
	request := completion_request(4, 1, 2, 3, 4)
	next, started := completion_start(model, request)
	model = next
	cases := [?]struct {
		name:    string,
		request: Completion_Request,
	} {
		{"request-generation", completion_request(5, 1, 2, 3, 4)},
		{"buffer-generation", completion_request(4, 2, 2, 3, 4)},
		{"revision", completion_request(4, 1, 3, 3, 4)},
		{"binding-generation", completion_request(4, 1, 2, 4, 4)},
		{"server-generation", completion_request(4, 1, 2, 3, 5)},
	}
	for test_case in cases {
		_, published := completion_publish(model, test_case.request, 1, false)
		testing.expectf(t, !published, "%s stale result was published", test_case.name)
	}
	testing.expect(t, started)
}

/* Verifies a server restart retires outstanding completion authority. */
@(test)
completion_protocol_model_retires_on_restart :: proc(t: ^testing.T) {
	model := Completion{completion_enabled = true}
	request := completion_request(6, 1, 2, 3, 4)
	next, started := completion_start(model, request)
	model = next
	model = completion_restart(model, 3)
	_, late := completion_publish(model, request, 1, false)

	testing.expect(t, started && !late)
	testing.expect_value(t, model.state, Completion_State.Idle)
	testing.expect_value(t, model.request, Completion_Request{})
}
