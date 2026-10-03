// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_reference

import "core:testing"

activate :: proc(t: ^testing.T) -> Session {
	session := initial_session()
	events := [?]Event {
		{kind = .Discover},
		{kind = .Discovery_Succeeded},
		{kind = .Spawned},
		{kind = .Initialized},
	}
	for event in events {
		next, accepted, failure := step(session, event)
		testing.expect(t, accepted)
		testing.expect_value(t, failure.code, Failure_Code.None)
		session = next
	}
	return session
}

/* Ensures activation and process reaping complete without retained state. */
@(test)
lifecycle_activates_and_reaps_cleanly :: proc(t: ^testing.T) {
	session := activate(t)
	testing.expect_value(t, session.health, Health.Active)
	testing.expect(t, session.process_live)

	events := [?]Event {
		{kind = .Begin_Shutdown},
		{kind = .Shutdown_Completed},
		{kind = .Process_Exited},
		{kind = .Reaped},
	}
	for event in events {
		next, accepted, _ := step(session, event)
		testing.expect(t, accepted)
		session = next
	}

	testing.expect_value(t, session.health, Health.Stopped)
	testing.expect(t, !session.process_live && !session.waiting_for_reap)
	testing.expect_value(t, session.usage, Usage{})
}

/* Ensures resource limits admit exact bounds and reject without mutation. */
@(test)
accounting_keeps_state_on_rejection :: proc(t: ^testing.T) {
	session := activate(t)
	admitted := Usage {
		documents = MAX_DOCUMENTS_PER_SESSION,
		outstanding_requests = MAX_OUTSTANDING_REQUESTS,
		notifications = MAX_NOTIFICATIONS,
		queue_depth = MAX_QUEUE_DEPTH,
		queue_bytes = MAX_QUEUE_BYTES,
		synchronization_changes = MAX_SYNCHRONIZATION_CHANGES,
		synchronization_bytes = MAX_SYNCHRONIZATION_BYTES,
		diagnostics = MAX_DIAGNOSTICS_PER_PROJECT,
		diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
		candidates = MAX_CANDIDATES,
		candidate_text_bytes = MAX_CANDIDATE_TEXT_BYTES,
		standard_error_bytes = MAX_STDERR_BYTES,
		retained_bytes = MAX_RETAINED_BYTES,
		temporary_bytes = MAX_TEMPORARY_BYTES,
	}
	next, accepted, failure := step(session, Event{kind = .Account, usage = admitted})
	session = next
	testing.expect(t, accepted)
	testing.expect_value(t, failure.code, Failure_Code.None)

	prior := session
	_, accepted, failure = step(session, Event{kind = .Account, usage = Usage{queue_depth = 1}})
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Resource_Limit)
	testing.expect_value(t, failure.resource, Resource.Queue_Depth)
	testing.expect_value(t, session, prior)
}

/* Ensures release accounting cannot underflow or mutate confirmed usage. */
@(test)
release_rejects_underflow_without_mutation :: proc(t: ^testing.T) {
	session := activate(t)
	next, admitted, _ := step(
		session,
		Event{kind = .Account, usage = Usage{documents = 1, queue_bytes = 128}},
	)
	session = next
	testing.expect(t, admitted)
	prior := session
	_, released, failure := step(
		session,
		Event{kind = .Release, usage = Usage{documents = 2}},
	)
	testing.expect(t, !released)
	testing.expect_value(t, failure.code, Failure_Code.Overflow)
	testing.expect_value(t, session, prior)
}

/* Ensures request cancellation and deadline ownership remain explicit. */
@(test)
cancellation_and_deadlines_are_explicit :: proc(t: ^testing.T) {
	session := activate(t)
	next, cancelled, _ := step(session, Event{kind = .Cancel})
	session = next
	testing.expect(t, cancelled && session.cancellation_requested)
	testing.expect_value(t, session.health, Health.Cancelling)

	expired_session, expired, failure := step(
		session,
		Event{kind = .Deadline_Expired, deadline = .Cancellation},
	)
	session = expired_session
	testing.expect(t, expired)
	testing.expect_value(t, session.health, Health.Failed)
	testing.expect_value(t, failure.code, Failure_Code.Deadline)
	testing.expect_value(t, failure.deadline, Deadline.Cancellation)
	testing.expect_value(t, deadline_ns(.Cancellation), CANCELLATION_DEADLINE_NS)
}

/* Ensures a failed process restarts only after its prior instance is reaped. */
@(test)
process_failure_allows_one_reaped_restart :: proc(t: ^testing.T) {
	session := activate(t)
	next, exited, failure := step(session, Event{kind = .Process_Exited})
	session = next
	testing.expect(t, exited)
	testing.expect_value(t, failure.code, Failure_Code.Process)
	testing.expect(t, session.waiting_for_reap)

	reaped_session, reaped, _ := step(session, Event{kind = .Reaped})
	session = reaped_session
	testing.expect(t, reaped && !session.waiting_for_reap)
	restarted_session, restarted, _ := step(session, Event{kind = .Restart})
	session = restarted_session
	testing.expect(t, restarted)
	testing.expect_value(t, session.generation, u64(2))
	testing.expect_value(t, session.automatic_restarts, u8(1))

	session.health = .Failed
	_, restarted, failure = step(session, Event{kind = .Restart})
	testing.expect(t, !restarted)
	testing.expect_value(t, failure.code, Failure_Code.Restart_Exhausted)
}

/* Ensures rejected lifecycle transitions preserve the prior generation. */
@(test)
bad_transitions_keep_generation :: proc(t: ^testing.T) {
	session := initial_session()
	prior := session
	_, accepted, failure := step(session, Event{kind = .Initialized})
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Transition)
	testing.expect_value(t, session, prior)
}

/* Ensures restart cannot wrap the service generation. */
@(test)
restart_rejects_generation_overflow :: proc(t: ^testing.T) {
	session := Session{
		generation = max(u64),
		health = .Failed,
	}
	_, accepted, failure := step(session, Event{kind = .Restart})
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Overflow)
}

/* Ensures selected deadlines are positive and preserve phase ordering. */
@(test)
selected_deadlines_are_positive_and_ordered :: proc(t: ^testing.T) {
	testing.expect(t, deadline_ns(.Idle_Step) < deadline_ns(.Discovery))
	testing.expect(t, deadline_ns(.Discovery) < deadline_ns(.Initialization))
	testing.expect(t, deadline_ns(.Forced_Termination) < deadline_ns(.Shutdown))
	testing.expect(t, deadline_ns(.Shutdown) < deadline_ns(.Restart_Stability))
}
