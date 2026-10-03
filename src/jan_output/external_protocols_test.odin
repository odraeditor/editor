// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies link and media actions select exact admitted provider capabilities. */
@(test)
external_link_operations_plan_checked_owners :: proc(t: ^testing.T) {
	providers := [1]Protocol_Provider_Descriptor {external_protocol_test_provider()}
	follow := external_protocol_test_link_request(.Follow)
	plan, ok, _ := prepare_link_effect(follow, providers[:])
	testing.expect(t, ok)
	testing.expect(t, plan.resource_read)
	testing.expect(t, plan.navigation)
	result := Link_Provider_Result {operation_id = follow.operation_id,
		provider_identity = follow.provider_identity,
		provider_generation = follow.provider_generation, state = .Completed,
		resource_id = 301, resource_revision = 17, result_count = 1, byte_count = 128, complete = true}
	testing.expect(t, link_provider_result_is_valid(plan, result))

	store := external_protocol_test_link_request(.Store)
	store_plan, store_ok, _ := prepare_link_effect(store, providers[:])
	testing.expect(t, store_ok)
	testing.expect(t, store_plan.resource_read)
	testing.expect(t, !store_plan.resource_write)
	search := external_protocol_test_link_request(.Search)
	search_plan, search_ok, _ := prepare_link_effect(search, providers[:])
	testing.expect(t, search_ok)
	testing.expect_value(t, search_plan.result_limit, u32(8))
	preview := external_protocol_test_link_request(.Preview)
	preview_plan, preview_ok, _ := prepare_link_effect(preview, providers[:])
	testing.expect(t, preview_ok)
	testing.expect(t, preview_plan.preview)
	media := external_protocol_test_link_request(.Media_Intake)
	media_plan, media_ok, _ := prepare_link_effect(media, providers[:])
	testing.expect(t, media_ok)
	testing.expect(t, media_plan.resource_read)
	testing.expect(t, media_plan.resource_write)
}

/* Verifies malformed, stale, unauthenticated, unavailable, and cancelled link requests reject. */
@(test)
external_link_failures_are_attributable_and_effect_free :: proc(t: ^testing.T) {
	providers := [1]Protocol_Provider_Descriptor {external_protocol_test_provider()}
	request := external_protocol_test_link_request(.Preview)
	request.authenticated = false
	_, auth_ok, auth_failure := prepare_link_effect(request, providers[:])
	testing.expect(t, !auth_ok)
	testing.expect_value(t, auth_failure.code, Failure_Code.Unauthorized)
	request.authenticated = true
	request.provider_generation += 1
	_, stale_ok, stale_failure := prepare_link_effect(request, providers[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
	request.provider_generation -= 1
	providers[0].state = .Unavailable
	_, unavailable_ok, unavailable_failure := prepare_link_effect(request, providers[:])
	testing.expect(t, !unavailable_ok)
	testing.expect_value(t, unavailable_failure.code, Failure_Code.Unavailable)
	providers[0].state = .Available
	request.cancelled = true
	_, cancelled_ok, cancelled_failure := prepare_link_effect(request, providers[:])
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
	request.cancelled = false
	request.expected_bytes = DEFAULT_LIMITS.output_bytes + 1
	_, limited_ok, limited_failure := prepare_link_effect(request, providers[:])
	testing.expect(t, !limited_ok)
	testing.expect_value(t, limited_failure.code, Failure_Code.Limited)
}

/* Verifies external store-link, capture, and source-location requests remain distinct. */
@(test)
external_protocol_entrypoints_are_versioned_and_bounded :: proc(t: ^testing.T) {
	providers := [1]Protocol_Provider_Descriptor {external_protocol_test_provider()}
	store_values := [2]Protocol_Initial_Value {
		{kind = .Title, value = "Checked page"},
		{kind = .Annotation, value = "Reviewed"},
	}
	store := external_protocol_test_request(.Store_Link, store_values[:])
	store.locator = "https://example.test/page"
	store_plan, store_replay, store_ok, _ := prepare_external_protocol_dispatch(store, providers[:], nil)
	testing.expect(t, store_ok)
	testing.expect(t, store_plan.link_state_change)
	testing.expect_value(t, store_replay.state, Protocol_Replay_State.Reserved)

	capture_values := [2]Protocol_Initial_Value {
		{kind = .Title, value = "Inbox item"},
		{kind = .Body, value = "Private draft", sensitive = true},
	}
	capture := external_protocol_test_request(.Start_Capture, capture_values[:])
	capture.template_identity = "inbox"
	capture.template_generation = 23
	capture.target_resource_id = 401
	capture.target_revision = 29
	capture_plan, _, capture_ok, _ := prepare_external_protocol_dispatch(capture, providers[:], nil)
	testing.expect(t, capture_ok)
	testing.expect(t, capture_plan.document_change)
	testing.expect_value(t, capture_plan.value_count, u16(2))
	testing.expect_value(t, capture_plan.sensitive_value_count, u16(1))

	no_values := []Protocol_Initial_Value{}
	open := external_protocol_test_request(.Open_Source, no_values)
	open.target_resource_id = 501
	open.target_revision = 31
	open.location_kind = .Source_Block
	open.location_identity = "results-analysis"
	open_plan, _, open_ok, _ := prepare_external_protocol_dispatch(open, providers[:], nil)
	testing.expect(t, open_ok)
	testing.expect(t, open_plan.navigation)
	testing.expect(t, !open_plan.document_change)
}

/* Verifies authentication, freshness, replay, payload, and provider failures precede dispatch. */
@(test)
external_protocol_admission_rejects_unsafe_requests :: proc(t: ^testing.T) {
	providers := [1]Protocol_Provider_Descriptor {external_protocol_test_provider()}
	values := [1]Protocol_Initial_Value {{kind = .Title, value = "Page"}}
	request := external_protocol_test_request(.Store_Link, values[:])
	request.locator = "https://example.test/page"
	_, replay, ok, _ := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, ok)
	records := [1]Protocol_Replay_Record {replay}
	_, _, replay_ok, replay_failure := prepare_external_protocol_dispatch(request, providers[:], records[:])
	testing.expect(t, !replay_ok)
	testing.expect_value(t, replay_failure.code, Failure_Code.Conflict)

	request.observed_at = request.expires_at + 1
	_, _, stale_ok, stale_failure := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
	request.observed_at = request.issued_at
	request.authenticated = false
	_, _, auth_ok, auth_failure := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, !auth_ok)
	testing.expect_value(t, auth_failure.code, Failure_Code.Unauthorized)
	request.authenticated = true
	request.envelope.payload_bytes = DEFAULT_LIMITS.protocol_payload_bytes + 1
	_, _, limited_ok, limited_failure := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, !limited_ok)
	testing.expect_value(t, limited_failure.code, Failure_Code.Limited)
	request.envelope.payload_bytes = 512
	request.schema_version += 1
	_, _, malformed_ok, malformed_failure := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, !malformed_ok)
	testing.expect_value(t, malformed_failure.code, Failure_Code.Malformed)
	request.schema_version = EXTERNAL_PROTOCOL_SCHEMA_VERSION
	providers[0].state = .Unavailable
	_, _, unavailable_ok, unavailable_failure := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, !unavailable_ok)
	testing.expect_value(t, unavailable_failure.code, Failure_Code.Unavailable)
}

/* Verifies terminal failures consume replay identity while changing no editor state. */
@(test)
external_protocol_terminal_outcomes_preserve_no_effect_boundaries :: proc(t: ^testing.T) {
	providers := [1]Protocol_Provider_Descriptor {external_protocol_test_provider()}
	values := [1]Protocol_Initial_Value {{kind = .Body, value = "Draft", sensitive = true}}
	request := external_protocol_test_request(.Start_Capture, values[:])
	request.template_identity = "inbox"
	request.template_generation = 23
	plan, replay, ok, _ := prepare_external_protocol_dispatch(request, providers[:], nil)
	testing.expect(t, ok)
	failed := Protocol_Dispatch_Result {operation_id = plan.operation_id,
		provider_identity = plan.provider_identity,
		provider_generation = plan.provider_generation, state = .Failed}
	testing.expect(t, protocol_dispatch_result_is_valid(plan, failed))
	failed.document_changed = true
	testing.expect(t, !protocol_dispatch_result_is_valid(plan, failed))
	completed := Protocol_Dispatch_Result {operation_id = plan.operation_id,
		provider_identity = plan.provider_identity,
		provider_generation = plan.provider_generation, state = .Completed,
		document_changed = true, complete = true}
	testing.expect(t, protocol_dispatch_result_is_valid(plan, completed))
	consumed, consumed_ok := protocol_replay_complete(replay, .Failed)
	testing.expect(t, consumed_ok)
	testing.expect_value(t, consumed.state, Protocol_Replay_State.Consumed)
	_, duplicate_complete := protocol_replay_complete(consumed, .Completed)
	testing.expect(t, !duplicate_complete)
}

@(private = "file")
external_protocol_test_provider :: proc() -> Protocol_Provider_Descriptor {
	return {identity = "resource-provider", generation = 17,
		capabilities = {.Follow_Link, .Store_Link, .Search_Links, .Preview_Link,
			.Intake_Media, .Start_Capture, .Open_Source},
		state = .Available, admitted = true, authentication_required = true,
		authentication_generation = 5}
}

@(private = "file")
external_protocol_test_link_request :: proc(action: Link_Provider_Action) -> Link_Provider_Request {
	request := Link_Provider_Request {operation_id = 101, action = action,
		provider_identity = "resource-provider", provider_generation = 17,
		expected_bytes = 4096, result_limit = 8, authenticated = true,
		authentication_generation = 5, explicit = true}
	switch action {
	case .Follow, .Preview:
		request.locator = "jan:document/guide"
	case .Store:
		request.source_resource_id = 201
		request.source_revision = 7
	case .Search:
		request.query = "deployment"
	case .Media_Intake:
		request.locator = "https://example.test/image.png"
		request.destination_resource_id = 203
		request.expected_destination_revision = 11
	case .Invalid:
	}
	return request
}

@(private = "file")
external_protocol_test_request :: proc(action: Protocol_Dispatch_Action, values: []Protocol_Initial_Value) -> External_Protocol_Request {
	request := External_Protocol_Request {
		envelope = {operation_id = 301, provider_generation = 17, payload_bytes = 512, explicit = true},
		schema_version = EXTERNAL_PROTOCOL_SCHEMA_VERSION, action = action,
		provider_identity = "resource-provider", caller_identity = "browser-extension",
		caller_instance = "profile-1", caller_generation = 3,
		issued_at = 1_000, expires_at = 1_600, observed_at = 1_200,
		authentication_generation = 5, authenticated = true, values = values,
	}
	request.nonce_digest[0] = 1
	request.payload_digest[0] = 2
	return request
}
