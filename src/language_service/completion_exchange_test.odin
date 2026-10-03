// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import completion "../completion"
import project_core "../project"
import "core:strings"
import "core:testing"

@(private)
completion_test_capabilities :: proc() -> Capability_Values {
	return {
		capabilities = {.Initialize, .Shutdown, .Cancellation, .Completion},
		position_encoding = .UTF_16,
		synchronization_mode = .Incremental,
		completion = {available = true, resolve = true},
	}
}

@(private)
completion_test_request :: proc(
	session: Session_Handle,
	binding: Document_Binding_Handle,
	revision: u64 = 1,
) -> completion.Request {
	query, _ := completion.text_copy("a")
	return {
		id = 1,
		generation = 1,
		scope = {
			document_id = 41,
			buffer_id = 43,
			document_revision = completion.Document_Revision(revision),
			view_id = 47,
			view_generation = 1,
			language_id = 53,
			language_generation = 1,
			provider_id = completion.Provider_ID(session.provider.id),
			provider_generation = completion.Provider_Generation(session.provider.generation),
			server_session_id = completion.Server_Session_ID(session.id),
			server_session_generation = completion.Server_Session_Generation(session.generation),
			document_binding_id = completion.Document_Binding_ID(binding.id),
			document_binding_generation = completion.Document_Binding_Generation(binding.generation),
			transmitted_revision = completion.Document_Revision(revision),
		},
		cursor_byte = 1,
		query_range = {start = 0, end = 1},
		query = query,
		trigger = .Explicit,
		provider_capabilities = {.Explicit, .Resolve, .Documentation},
		state = .Prepared,
	}
}

@(private)
completion_test_synchronizer :: proc(
	t: ^testing.T,
	registry: ^project_core.Registry,
	synchronizer: ^Document_Synchronizer,
	session: Session_Handle,
	seed: u64,
) -> (Document_Binding_Handle, bool) {
	_, project, membership, project_ok := synchronization_test_project(
		registry,
		"/work/fixture",
		.Trusted,
		seed,
	)
	testing.expect(t, project_ok)
	if !project_ok do return {}, false
	request := synchronization_test_request(session, project, membership, .Incremental)
	initialized, failure := document_synchronizer_init(synchronizer, registry, request)
	testing.expectf(t, initialized, "synchronizer init failed: %v", failure.code)
	if !initialized do return {}, false
	binding, opened, open_failure := document_synchronizer_open(
		synchronizer,
		synchronization_test_open_request(),
	)
	testing.expectf(t, opened, "document open failed: %v", open_failure.code)
	return binding, opened
}

@(private)
completion_test_ack_open :: proc(synchronizer: ^Document_Synchronizer) -> bool {
	view, queued := document_synchronizer_peek(synchronizer)
	return queued && view.operation == .Open &&
		document_synchronizer_ack(synchronizer, view.record.generation)
}

/* Verifies completion dispatch waits for the exact transmitted revision. */
@(test)
requires_transmitted_revision :: proc(t: ^testing.T) {
	session := synchronization_test_session(701)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := completion_test_synchronizer(t, &registry, &synchronizer, session, 709)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)

	exchange: Completion_Exchange
	initialized, init_failure := completion_exchange_init(
		&exchange,
		session,
		binding,
		completion_test_capabilities(),
	)
	testing.expectf(t, initialized, "exchange init failed: %v", init_failure.code)
	if !initialized do return
	defer completion_exchange_close(&exchange)

	request := completion_test_request(session, binding)
	_, prepared, failure := completion_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	testing.expect(t, completion_test_ack_open(&synchronizer))

	view: Completion_Request_View
	view, prepared, failure = completion_exchange_prepare(&exchange, &synchronizer, request, 2)
	testing.expectf(t, prepared, "completion prepare failed: %v", failure.code)
	if prepared {
		body := string(view.body)
		testing.expect(t, strings.contains(body, `"method":"textDocument/completion"`))
		testing.expect(t, strings.contains(body, `"line":0`))
		testing.expect(t, strings.contains(body, `"character":1`))
		testing.expect_value(t, view.state, Request_State.Queued)
	}
}

/* Verifies stale document, binding, and session generations are contained. */
@(test)
completion_exchange_rejects_stale_authority :: proc(t: ^testing.T) {
	session := synchronization_test_session(733)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := completion_test_synchronizer(t, &registry, &synchronizer, session, 739)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	testing.expect(t, completion_test_ack_open(&synchronizer))

	exchange: Completion_Exchange
	initialized, _ := completion_exchange_init(
		&exchange,
		session,
		binding,
		completion_test_capabilities(),
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer completion_exchange_close(&exchange)

	request := completion_test_request(session, binding)
	request.scope.document_revision = 2
	request.scope.transmitted_revision = 2
	_, prepared, failure := completion_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)

	request = completion_test_request(session, binding)
	request.scope.server_session_generation += 1
	_, prepared, failure = completion_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
}

/* Verifies unsupported providers cannot create a completion exchange. */
@(test)
requires_negotiated_capability :: proc(t: ^testing.T) {
	session := synchronization_test_session(761)
	binding := Document_Binding_Handle{session = session, id = 1, generation = 1}
	capabilities := completion_test_capabilities()
	capabilities.capabilities -= {.Completion}
	capabilities.completion = {}
	exchange: Completion_Exchange
	initialized, failure := completion_exchange_init(&exchange, session, binding, capabilities)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Unsupported_Capability)
}

/* Verifies queued cancellation retires the request without transport publication. */
@(test)
completion_exchange_cancels_queued_request :: proc(t: ^testing.T) {
	session := synchronization_test_session(787)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := completion_test_synchronizer(t, &registry, &synchronizer, session, 797)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	testing.expect(t, completion_test_ack_open(&synchronizer))

	exchange: Completion_Exchange
	initialized, _ := completion_exchange_init(
		&exchange,
		session,
		binding,
		completion_test_capabilities(),
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer completion_exchange_close(&exchange)
	request := completion_test_request(session, binding)
	_, prepared, _ := completion_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, prepared)
	process: Process_Session
	cancelled, failure := completion_exchange_cancel(&exchange, &process)
	testing.expectf(t, cancelled, "queued cancellation failed: %v", failure.code)
	inspection, inspected := completion_exchange_inspect(&exchange)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.state, Request_State.Cancelled)
	testing.expect_value(t, inspection.payload_bytes, u64(0))
}

/* Verifies request deadlines and transport failure release retained payloads. */
@(test)
contains_timeout_and_transport_failure :: proc(t: ^testing.T) {
	session := synchronization_test_session(809)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := completion_test_synchronizer(t, &registry, &synchronizer, session, 811)
	if !ready do return
	defer project_core.registry_close(&registry)
	defer document_synchronizer_close(&synchronizer)
	testing.expect(t, completion_test_ack_open(&synchronizer))

	exchange: Completion_Exchange
	initialized, _ := completion_exchange_init(
		&exchange,
		session,
		binding,
		completion_test_capabilities(),
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer completion_exchange_close(&exchange)
	request := completion_test_request(session, binding)
	view, prepared, _ := completion_exchange_prepare(&exchange, &synchronizer, request, 1)
	testing.expect(t, prepared)
	state, polled, _ := completion_exchange_poll(&exchange, view.deadline_ns - 1)
	testing.expect(t, polled)
	testing.expect_value(t, state, Request_State.Queued)
	timeout_failure: Failure_Context
	state, polled, timeout_failure = completion_exchange_poll(&exchange, view.deadline_ns)
	testing.expect(t, polled)
	testing.expect_value(t, state, Request_State.Timed_Out)
	testing.expect_value(t, timeout_failure.code, Failure_Code.Timeout)

	request.id = 2
	request.generation = 2
	_, prepared, _ = completion_exchange_prepare(&exchange, &synchronizer, request, 2)
	testing.expect(t, prepared)
	failed, failure := completion_exchange_fail(
		&exchange,
		Failure_Context{code = .Process_Exit},
	)
	testing.expect(t, failed)
	testing.expect_value(t, failure.code, Failure_Code.Process_Exit)
	inspection, inspected := completion_exchange_inspect(&exchange)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.state, Request_State.Failed)
	testing.expect_value(t, inspection.payload_bytes, u64(0))
}
