// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:testing"

@(private)
profile_test_definition :: proc(features: Service_Features) -> Definition_View {
	return Definition_View{
		definition = {
			handle = {registry = {id = 1, generation = 1}, id = 1, generation = 1},
			requested_capabilities = {
				.Initialize,
				.Shutdown,
				.Cancellation,
				.Full_Synchronization,
				.Incremental_Synchronization,
				.Save_Notification,
				.Push_Diagnostics,
				.Log_Message,
				.Completion,
				.Hover,
			},
			preferred_encoding = .UTF_16,
			preferred_sync = .Incremental,
			limits = DEFAULT_LIMITS,
			deadlines = DEFAULT_DEADLINES,
			restart = DEFAULT_RESTART_POLICY,
		},
		initialization_options = `{"profile":"fixture"}`,
		client_settings = `{"fixture":{"enabled":true}}`,
		feature_policy = features,
	}
}

/* Verifies symbolic feature policy intersects implemented and negotiated behavior. */
@(test)
effective_profile_separates_requested_and_active_features :: proc(t: ^testing.T) {
	definition := profile_test_definition({.Diagnostics, .Completion, .Hover})
	profile, built := effective_service_profile(
		definition,
		{
			capabilities = {
				.Initialize,
				.Shutdown,
				.Incremental_Synchronization,
				.Save_Notification,
				.Push_Diagnostics,
			},
			position_encoding = .UTF_16,
			synchronization_mode = .Incremental,
		},
	)
	testing.expect(t, built)
	if !built do return
	testing.expect(t, .Diagnostics in profile.active_features)
	testing.expect(t, .Completion not_in profile.active_features)
	testing.expect(t, .Hover not_in profile.active_features)
	testing.expect(t, .Completion in profile.feature_policy)
	testing.expect(t, .Hover in profile.feature_policy)
	testing.expect(t, .Push_Diagnostics in profile.active_capabilities)
	testing.expect(t, .Completion not_in profile.active_capabilities)
	testing.expect_value(t, profile.synchronization_mode, Synchronization_Mode.Incremental)
	testing.expect_value(t, profile.initialization_options, `{"profile":"fixture"}`)
	testing.expect_value(t, profile.client_settings, `{"fixture":{"enabled":true}}`)
}

/* Verifies completion activates only when policy and server negotiation agree. */
@(test)
effective_profile_activates_negotiated_completion :: proc(t: ^testing.T) {
	definition := profile_test_definition({.Completion})
	profile, built := effective_service_profile(
		definition,
		{
			capabilities = {.Initialize, .Shutdown, .Full_Synchronization, .Completion},
			position_encoding = .UTF_8,
			synchronization_mode = .Full,
			completion = {available = true, resolve = true},
		},
	)
	testing.expect(t, built)
	if built {
		testing.expect(t, .Completion in profile.active_features)
		testing.expect(t, profile.completion.available)
		testing.expect(t, profile.completion.resolve)
		testing.expect_value(t, profile.position_encoding, Position_Encoding.UTF_8)
	}
}

/* Verifies settings use the distinct post-initialization notification path. */
@(test)
effective_profile_builds_configuration_notification :: proc(t: ^testing.T) {
	body, built := service_configuration_notification(`{"fixture":{"enabled":true}}`)
	testing.expect(t, built)
	if built {
		defer delete(body)
		testing.expect_value(
			t,
			body,
			`{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration","params":{"settings":{"fixture":{"enabled":true}}}}`,
		)
	}
}
