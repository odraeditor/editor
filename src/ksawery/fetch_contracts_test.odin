// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

@(private)
fetch_contracts_test_configuration :: proc(remote: Remote_Identity, seed: u8) -> (Remote_Configuration_Identity, bool) {
	bytes: [REMOTE_CONFIGURATION_FINGERPRINT_BYTES]u8
	for index in 0 ..< len(bytes) do bytes[index] = seed + u8(index)
	configuration := Remote_Configuration_Identity{remote = remote}
	return configuration, remote_configuration_fingerprint_assign(&configuration.fingerprint, bytes[:])
}

@(private)
fetch_contracts_test_observation :: proc() -> (Ref_Observation, Ref_Selection, Remote_Identity, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/fetch") do return {}, {}, {}, false
	observation, opened, _ := ref_observation_open(
		repository,
		Ref_Generation(17),
		nil,
		transmute([]u8)(string("origin\n")),
		nil,
	)
	if !opened do return {}, {}, {}, false
	selection, selected := ref_selection_begin(&observation)
	if !selected || selection.current.kind != .Remote {
		ref_observation_close(&observation)
		return {}, {}, {}, false
	}
	return observation, selection, selection.current.remote, true
}

/* Verifies a checked fetch binds one exact selected remote and configuration digest. */
@(test)
fetch_request_requires_exact_selected_remote_configuration :: proc(t: ^testing.T) {
	observation, selection, remote, ready := fetch_contracts_test_observation()
	testing.expect(t, ready)
	if !ready do return
	defer ref_observation_close(&observation)
	configuration, configured := fetch_contracts_test_configuration(remote, 1)
	testing.expect(t, configured)
	if !configured do return

	request, prepared, failure := fetch_request_prepare(
		&observation,
		selection,
		configuration,
		.Normal,
		Fetch_Operation_ID(1),
	)
	testing.expect(t, prepared && failure == .None && fetch_request_is_valid(request))

	changed, changed_ready := fetch_contracts_test_configuration(remote, 2)
	testing.expect(t, changed_ready)
	if changed_ready {
		current, current_failure := fetch_request_revalidate(&observation, changed, .Normal, request)
		testing.expect(t, !current && current_failure == .Stale_Observation)
	}
	current, current_failure := fetch_request_revalidate(&observation, configuration, .Normal, request)
	testing.expect(t, current && current_failure == .None)
}

/* Verifies stale selection and active repository sequences reject fetch admission. */
@(test)
fetch_request_rejects_stale_or_conflicting_repository_state :: proc(t: ^testing.T) {
	observation, selection, remote, ready := fetch_contracts_test_observation()
	testing.expect(t, ready)
	if !ready do return
	defer ref_observation_close(&observation)
	configuration, configured := fetch_contracts_test_configuration(remote, 3)
	testing.expect(t, configured)
	if !configured do return

	_, prepared, failure := fetch_request_prepare(
		&observation,
		selection,
		configuration,
		.Merging,
		Fetch_Operation_ID(2),
	)
	testing.expect(t, !prepared && failure == .Action_Unavailable)

	stale := selection
	stale.generation = Ref_Generation(18)
	_, prepared, failure = fetch_request_prepare(
		&observation,
		stale,
		configuration,
		.Normal,
		Fetch_Operation_ID(3),
	)
	testing.expect(t, !prepared && failure == .Remote_Unavailable)
}

/* Verifies cancellation before start does not require refresh while every started fetch does. */
@(test)
fetch_result_preserves_started_refresh_and_cancellation_contracts :: proc(t: ^testing.T) {
	observation, selection, remote, ready := fetch_contracts_test_observation()
	testing.expect(t, ready)
	if !ready do return
	defer ref_observation_close(&observation)
	configuration, configured := fetch_contracts_test_configuration(remote, 5)
	testing.expect(t, configured)
	if !configured do return
	request, prepared, _ := fetch_request_prepare(
		&observation,
		selection,
		configuration,
		.Normal,
		Fetch_Operation_ID(4),
	)
	testing.expect(t, prepared)
	if !prepared do return

	cancelled, opened, failure := fetch_result_open(request, false, 0, nil, nil, .Cancelled)
	testing.expect(t, opened && failure == .None)
	if opened {
		descriptor, described := fetch_result_descriptor(&cancelled)
		testing.expect(t, described && fetch_result_descriptor_is_valid(descriptor))
		testing.expect(t, !descriptor.started && !descriptor.refresh_required)
		testing.expect_value(t, fetch_feedback(descriptor), Fetch_Feedback.Cancelled)
		fetch_result_close(&cancelled)
		testing.expect(t, cancelled.state == nil)
	}

	completed, completed_opened, completed_failure := fetch_result_open(
		request,
		true,
		0,
		transmute([]u8)(string("updated origin")),
		nil,
	)
	testing.expect(t, completed_opened && completed_failure == .None)
	if completed_opened {
		descriptor, described := fetch_result_descriptor(&completed)
		testing.expect(t, described && descriptor.succeeded && descriptor.refresh_required)
		testing.expect_value(t, fetch_feedback(descriptor), Fetch_Feedback.Completed)
		usage, measured := fetch_result_usage(&completed)
		testing.expect(t, measured && usage.output_bytes == 14 && usage.diagnostic_bytes == 0)
		fetch_result_close(&completed)
	}

	timed_out, timed_out_opened, timed_out_failure := fetch_result_open(
		request,
		true,
		1,
		nil,
		transmute([]u8)(string("timeout")),
		.Timeout,
	)
	testing.expect(t, timed_out_opened && timed_out_failure == .None)
	if timed_out_opened {
		descriptor, described := fetch_result_descriptor(&timed_out)
		testing.expect(t, described && !descriptor.succeeded && descriptor.refresh_required)
		testing.expect_value(t, fetch_feedback(descriptor), Fetch_Feedback.Timed_Out)
		fetch_result_close(&timed_out)
	}
}

/* Verifies fetch result payloads remain within the checked process limits. */
@(test)
fetch_result_rejects_unbounded_retained_output :: proc(t: ^testing.T) {
	observation, selection, remote, ready := fetch_contracts_test_observation()
	testing.expect(t, ready)
	if !ready do return
	defer ref_observation_close(&observation)
	configuration, configured := fetch_contracts_test_configuration(remote, 7)
	if !configured do return
	limits := DEFAULT_PROCESS_LIMITS
	request, prepared, _ := fetch_request_prepare(
		&observation,
		selection,
		configuration,
		.Normal,
		Fetch_Operation_ID(5),
		limits,
	)
	if !prepared do return
	oversized := make([]u8, int(limits.stdout_bytes) + 1, context.temp_allocator)
	_, opened, failure := fetch_result_open(request, true, 0, oversized, nil)
	testing.expect(t, !opened && failure == .Output_Limit)
}
