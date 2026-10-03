// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

PUSH_TEST_SOURCE_OBJECT :: "abcdef0123456789abcdef0123456789abcdef01"

@(private)
push_contracts_test_observation :: proc(
	generation: Ref_Generation,
	synchronized: bool,
	detached := false,
	allocator := context.allocator,
) -> (Ref_Observation, bool) {
	ref_output := transmute([]u8)(string(
		"refs/heads/main\x00" + PUSH_TEST_SOURCE_OBJECT + "\x00commit\x00refs/remotes/origin/main\x00[ahead 1]\x00*\x00\n" +
		"refs/remotes/origin/main\x00" + REF_TEST_SHA1 + "\x00commit\x00\x00\x00 \x00\n",
	))
	if synchronized {
		ref_output = transmute([]u8)(string(
			"refs/heads/main\x00" + PUSH_TEST_SOURCE_OBJECT + "\x00commit\x00refs/remotes/origin/main\x00\x00*\x00\n" +
			"refs/remotes/origin/main\x00" + PUSH_TEST_SOURCE_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		))
	}
	if detached {
		ref_output = transmute([]u8)(string(
			"refs/heads/main\x00" + PUSH_TEST_SOURCE_OBJECT + "\x00commit\x00refs/remotes/origin/main\x00[ahead 1]\x00 \x00\n" +
			"refs/remotes/origin/main\x00" + REF_TEST_SHA1 + "\x00commit\x00\x00\x00 \x00\n",
		))
	}
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/push") do return {}, false
	observation, opened, _ := ref_observation_open(
		repository,
		generation,
		ref_output,
		transmute([]u8)(string("origin\n")),
		transmute([]u8)(string(PUSH_TEST_SOURCE_OBJECT + "\n")),
		DEFAULT_REF_LIMITS,
		allocator,
	)
	return observation, opened
}

@(private)
push_contracts_test_inputs :: proc(
	observation: ^Ref_Observation,
) -> (Ref_Identity, Push_Configuration_Identity, bool) {
	ref_count, refs_available := ref_observation_ref_count(observation)
	remote_count, remotes_available := ref_observation_remote_count(observation)
	if !refs_available || !remotes_available || ref_count == 0 || remote_count == 0 do return {}, {}, false
	source, source_found := ref_observation_ref(observation, 0)
	remote, remote_found := ref_observation_remote(observation, 0)
	if !source_found || !remote_found do return {}, {}, false
	configuration := Push_Configuration_Identity{remote = remote}
	bytes: [REMOTE_CONFIGURATION_FINGERPRINT_BYTES]u8
	for index in 0 ..< len(bytes) do bytes[index] = u8(index + 1)
	return source, configuration, remote_configuration_fingerprint_assign(&configuration.fingerprint, bytes[:])
}

@(private)
push_contracts_test_request :: proc(
	observation: ^Ref_Observation,
	operation: Push_Operation_ID,
) -> (Push_Request, bool) {
	source, configuration, ready := push_contracts_test_inputs(observation)
	if !ready do return {}, false
	precondition, prepared, _ := push_precondition_prepare(observation, source, configuration, .Normal)
	if !prepared do return {}, false
	confirmation, confirmation_ready, _ := push_confirmation_prepare(
		precondition,
		Push_Confirmation_ID(u64(operation)),
	)
	if !confirmation_ready do return {}, false
	confirmed, _ := push_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, request_ready, _ := push_request_prepare(precondition, operation, &confirmation)
	return request, request_ready
}

/* Verifies push derives one exact tracked destination and consumes exact confirmation once. */
@(test)
push_request_requires_derived_destination_and_one_shot_confirmation :: proc(t: ^testing.T) {
	observation, opened := push_contracts_test_observation(Ref_Generation(61), false)
	testing.expect(t, opened)
	if !opened do return
	defer ref_observation_close(&observation)
	source, configuration, ready := push_contracts_test_inputs(&observation)
	testing.expect(t, ready)
	if !ready do return
	precondition, prepared, prepare_failure := push_precondition_prepare(
		&observation,
		source,
		configuration,
		.Normal,
	)
	testing.expectf(t, prepared, "push precondition failed with %v", prepare_failure)
	if !prepared do return
	destination := precondition.destination.branch
	testing.expect_value(t, ref_name_string(&destination), "refs/heads/main")
	testing.expect_value(t, precondition.tracking.state, Tracking_State.Ahead)
	arbitrary := precondition
	testing.expect(t, ref_name_assign(&arbitrary.destination.branch, "refs/heads/other"))
	testing.expect(t, !push_precondition_is_valid(arbitrary))
	_, request_ready, request_failure := push_request_prepare(
		precondition,
		Push_Operation_ID(61),
		nil,
	)
	testing.expect(t, !request_ready && request_failure == .Confirmation_Required)
	confirmation, confirmation_ready, confirmation_failure := push_confirmation_prepare(
		precondition,
		Push_Confirmation_ID(61),
	)
	testing.expectf(t, confirmation_ready, "push confirmation failed with %v", confirmation_failure)
	if !confirmation_ready do return
	confirmed, confirm_failure := push_confirmation_confirm(&confirmation, Push_Confirmation_ID(62))
	testing.expect(t, !confirmed && confirm_failure == .Confirmation_Mismatch)
	confirmed, confirm_failure = push_confirmation_confirm(&confirmation, Push_Confirmation_ID(61))
	testing.expectf(t, confirmed, "push confirmation acceptance failed with %v", confirm_failure)
	if !confirmed do return
	request, request_prepared, request_prepare_failure := push_request_prepare(
		precondition,
		Push_Operation_ID(61),
		&confirmation,
	)
	testing.expectf(t, request_prepared && push_request_is_valid(request), "push request failed with %v", request_prepare_failure)
	_, repeated, repeated_failure := push_request_prepare(
		precondition,
		Push_Operation_ID(62),
		&confirmation,
	)
	testing.expect(t, !repeated && repeated_failure == .Confirmation_Mismatch)
}

/* Verifies detached, non-branch, conflicting, and stale inputs reject push admission. */
@(test)
push_request_rejects_unsafe_or_stale_publication_inputs :: proc(t: ^testing.T) {
	observation, opened := push_contracts_test_observation(Ref_Generation(63), false)
	testing.expect(t, opened)
	if !opened do return
	defer ref_observation_close(&observation)
	source, configuration, ready := push_contracts_test_inputs(&observation)
	if !ready do return
	_, prepared, failure := push_precondition_prepare(&observation, source, configuration, .Merging)
	testing.expect(t, !prepared && failure == .Action_Unavailable)
	remote_tracking, found := ref_observation_ref(&observation, 1)
	testing.expect(t, found)
	if found {
		_, prepared, failure = push_precondition_prepare(&observation, remote_tracking, configuration, .Normal)
		testing.expect(t, !prepared && failure == .Ref_Unavailable)
	}

	detached, detached_opened := push_contracts_test_observation(Ref_Generation(64), false, true)
	testing.expect(t, detached_opened)
	if detached_opened {
		defer ref_observation_close(&detached)
		detached_source, detached_configuration, detached_ready := push_contracts_test_inputs(&detached)
		if detached_ready {
			_, prepared, failure = push_precondition_prepare(
				&detached,
				detached_source,
				detached_configuration,
				.Normal,
			)
			testing.expect(t, !prepared && failure == .Ref_Unavailable)
		}
	}

	request, request_ready := push_contracts_test_request(&observation, Push_Operation_ID(63))
	testing.expect(t, request_ready)
	if request_ready {
		changed := configuration
		changed.fingerprint.bytes[0] = changed.fingerprint.bytes[0] ~ 0xff
		current, current_failure := push_request_revalidate(&observation, changed, .Normal, request)
		testing.expect(t, !current && current_failure == .Stale_Observation)
	}
}

/* Verifies refreshed Ref truth, not transport output, is the push success authority. */
@(test)
push_result_requires_refreshed_tracking_proof_and_releases_owned_output :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	before, before_opened := push_contracts_test_observation(Ref_Generation(65), false, false, allocator)
	testing.expect(t, before_opened)
	if !before_opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	request, request_ready := push_contracts_test_request(&before, Push_Operation_ID(65))
	testing.expect(t, request_ready)
	if !request_ready {
		ref_observation_close(&before)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	result, result_opened, result_failure := push_result_open(
		request,
		true,
		0,
		transmute([]u8)(string("published main")),
		nil,
		.None,
		allocator,
	)
	testing.expectf(t, result_opened, "push result failed with %v", result_failure)
	if !result_opened {
		ref_observation_close(&before)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	descriptor, described := push_result_descriptor(&result)
	testing.expect(t, described && descriptor.transport_succeeded && !descriptor.succeeded)
	testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Refreshing)
	fresh, fresh_opened := push_contracts_test_observation(Ref_Generation(66), true, false, allocator)
	testing.expect(t, fresh_opened)
	if fresh_opened {
		verified, verify_failure := push_result_verify(&result, &fresh)
		testing.expectf(t, verified, "push verification failed with %v", verify_failure)
		descriptor, described = push_result_descriptor(&result)
		testing.expect(t, described && descriptor.verified && descriptor.succeeded)
		testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Completed)
		usage, measured := push_result_usage(&result)
		testing.expect(t, measured && usage.output_bytes == 14 && usage.diagnostic_bytes == 0)
		ref_observation_close(&fresh)
	}
	push_result_close(&result)
	ref_observation_close(&before)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies cancellation and transport failure remain non-success outcomes after refresh. */
@(test)
push_result_preserves_cancellation_and_failed_transport :: proc(t: ^testing.T) {
	before, before_opened := push_contracts_test_observation(Ref_Generation(67), false)
	testing.expect(t, before_opened)
	if !before_opened do return
	defer ref_observation_close(&before)
	request, request_ready := push_contracts_test_request(&before, Push_Operation_ID(67))
	if !request_ready do return
	cancelled, cancelled_opened, cancelled_failure := push_result_open(
		request,
		false,
		0,
		nil,
		nil,
		.Cancelled,
	)
	testing.expectf(t, cancelled_opened, "cancelled push result failed with %v", cancelled_failure)
	if cancelled_opened {
		descriptor, described := push_result_descriptor(&cancelled)
		testing.expect(t, described && !descriptor.started && !descriptor.refresh_required)
		testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Cancelled)
		push_result_close(&cancelled)
	}
	failed, failed_opened, failed_failure := push_result_open(
		request,
		true,
		1,
		nil,
		transmute([]u8)(string("rejected")),
	)
	testing.expectf(t, failed_opened, "failed push result failed with %v", failed_failure)
	if !failed_opened do return
	fresh, fresh_opened := push_contracts_test_observation(Ref_Generation(68), false)
	testing.expect(t, fresh_opened)
	if fresh_opened {
		verified, _ := push_result_verify(&failed, &fresh)
		descriptor, described := push_result_descriptor(&failed)
		testing.expect(t, verified && described && descriptor.verified && !descriptor.succeeded)
		testing.expect_value(t, push_feedback(descriptor), Push_Feedback.Failed)
		ref_observation_close(&fresh)
	}
	push_result_close(&failed)
}
