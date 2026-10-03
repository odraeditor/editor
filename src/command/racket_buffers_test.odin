// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../hosting"
import "../interaction"
import "core:testing"

/* Verifies Racket composes create, inventory, and usage through one checked turn. */
@(private)
verify_racket_buffer_session_facade :: proc(
	t: ^testing.T,
	runtime: ^hosting.Runtime,
) {
	session: editor_session.Session
	handle, initialized, _ := editor_session.session_init(
		&session,
		editor_session.Session_ID(771),
		editor_session.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	capability := Buffer_Session_Capability_Context {
		editor_session_id = Editor_Session_ID(771),
		access = {
			.Usage_Inspection,
			.Descriptor_Inspection,
			.Create,
			.Open,
			.Activate,
			.Save,
			.Kill,
			.Marked_Execution,
		},
		buffer_session = Buffer_Session_Context {
			session = &session,
			handle = handle,
			command = interaction.Command_Handle {
				registry_generation = 1,
				slot = 1,
				entry_generation = 1,
			},
			configuration = editor_session.DEFAULT_ENTRY_CONFIGURATION,
		},
		temporary_allocator = context.allocator,
	}
	for _ in 0 ..< 4 {
		_, inspected, inspect_failure := racket_buffer_session_turn(runtime, capability, 0)
		testing.expectf(t, inspected, "repeated scope failed with %v", inspect_failure.code)
	}
	_, gc_ok, gc_failure := racket_buffer_session_turn(runtime, capability, 2)
	testing.expectf(t, gc_ok, "forced GC failed with %v", gc_failure.code)
	_, batch_ok, batch_failure := racket_buffer_session_turn(runtime, capability, 6)
	testing.expectf(t, batch_ok, "descriptor batch failed with %v", batch_failure.code)
	failure_scenarios := [?]struct{name: string, scenario: i32} {
		{"escaped-session", 1},
		{"cross-thread-session", 3},
		{"command-exception", 4},
		{"continuation-escape", 5},
		{"malformed-request", 9},
		{"excessive-descriptors", 10},
	}
	for test_case in failure_scenarios {
		_, contained, contained_failure := racket_buffer_session_turn(
			runtime,
			capability,
			test_case.scenario,
		)
		testing.expectf(
			t,
			!contained,
			"%s buffer-session scenario escaped with %v",
			test_case.name,
			contained_failure.code,
		)
	}
	cancelled := capability
	cancelled.cancelled = true
	_, cancellation_ok, cancellation_failure := racket_buffer_session_turn(
		runtime,
		cancelled,
		0,
	)
	testing.expect(t, !cancellation_ok)
	testing.expect_value(t, cancellation_failure.code, Failure_Code.Cancelled)

	result, composed, compose_failure := racket_buffer_session_turn(
		runtime,
		capability,
		7,
	)
	testing.expectf(t, composed, "Racket buffer session failed with %v", compose_failure)
	if composed {
		testing.expect_value(t, result.scope.visible.kind, editor_session.Visible_Target_Kind.Primary_View)
	}
	_, stale_ok, stale_failure := racket_buffer_session_turn(runtime, capability, 8)
	testing.expect(t, !stale_ok)
	testing.expect_value(
		t,
		stale_failure.buffer_session_capability_code,
		Buffer_Session_Capability_Failure_Code.Stale_Visible_Target,
	)
	descriptors, copied, _ := editor_session.session_descriptors(&session, handle)
	testing.expect(t, copied)
	if copied {
		testing.expect_value(t, len(descriptors.descriptors), 2)
		found_created := false
		found_stale := false
		for descriptor in descriptors.descriptors {
			found_created = found_created || descriptor.selection_label == "racket-created"
			found_stale = found_stale || descriptor.selection_label == "stale-scope-buffer"
		}
		testing.expect(t, found_created)
		testing.expect(t, found_stale)
		first_entry := descriptors.descriptors[0].graph.entry
		second_entry := descriptors.descriptors[1].graph.entry
		editor_session.descriptor_batch_close(&descriptors)
		closed, close_ok, _ := editor_session.session_close_buffer(
			&session,
			editor_session.Close_Buffer_Request{entry = first_entry},
		)
		testing.expect(t, close_ok && closed.outcome == .Closed)
		closed, close_ok, _ = editor_session.session_close_buffer(
			&session,
			editor_session.Close_Buffer_Request{entry = second_entry},
		)
		testing.expect(t, close_ok && closed.outcome == .Closed)
	}
	session_closed, _ := editor_session.session_close(&session)
	testing.expect(t, session_closed)
}
