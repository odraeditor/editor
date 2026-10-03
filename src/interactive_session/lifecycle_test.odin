// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "core:testing"

@(private)
test_record :: proc(t: ^testing.T) -> Session_Record {
	record, ok, failure := prepare_record(
		Session_Ref{id = 1, generation = 1},
		"terminal",
		.Interactive_User,
		"user command",
		"/tmp",
	)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	return record
}

/* Verifies the complete normal lifecycle and resource-free terminal state. */
@(test)
session_record_accepts_only_normal_lifecycle_edges :: proc(t: ^testing.T) {
	record := test_record(t)
	testing.expect_value(t, record.lifecycle, Lifecycle.Prepared)
	testing.expect_value(t, record.resources, Resource_Usage{})

	normal_transitions := []Lifecycle{Lifecycle.Starting, Lifecycle.Running}
	for target in normal_transitions {
		ok, failure := transition(&record, target)
		testing.expect(t, ok)
		testing.expect_value(t, failure.code, Failure_Code.None)
	}
	record.resources = Resource_Usage {
		process_id = 42,
		process_group_id = 42,
		open_descriptors = 1,
	}
	exited, _ := record_exit(&record, Exit_Status{kind = .Code, value = 0})
	testing.expect(t, exited)
	testing.expect_value(t, record.lifecycle, Lifecycle.Exited)
	testing.expect_value(t, record.exit_status.value, i32(0))

	closing, _ := transition(&record, .Closing)
	closed, _ := transition(&record, .Closed)
	testing.expect(t, closing && closed)
	testing.expect_value(t, record.resources, Resource_Usage{})
	_, repeated := transition(&record, .Closed)
	testing.expect_value(t, repeated.code, Failure_Code.Invalid_Transition)
}

/* Verifies forbidden edges cannot alter the confirmed state. */
@(test)
session_record_rejects_forbidden_transitions :: proc(t: ^testing.T) {
	record := test_record(t)
	forbidden_transitions := []Lifecycle {
		Lifecycle.Running,
		Lifecycle.Exited,
		Lifecycle.Closed,
	}
	for target in forbidden_transitions {
		ok, failure := transition(&record, target)
		testing.expect(t, !ok)
		testing.expect_value(t, failure.code, Failure_Code.Invalid_Transition)
		testing.expect_value(t, record.lifecycle, Lifecycle.Prepared)
	}
	testing.expect(t, !request_cancel(&record))
}

/* Verifies the first failure survives later cleanup and cancellation changes. */
@(test)
session_record_preserves_first_failure :: proc(t: ^testing.T) {
	record := test_record(t)
	_, _ = transition(&record, .Starting)
	testing.expect(t, request_cancel(&record))
	testing.expect(t, record.cancel_requested)
	first := failure_record(.Start, .Spawn, 2, diagnostic = "missing executable")
	second := failure_record(.Close, .Cleanup, 5, diagnostic = "later cleanup")
	testing.expect(t, record_failure(&record, first))
	testing.expect(t, record_failure(&record, second))
	testing.expect_value(t, record.failure.code, Failure_Code.Spawn)
	testing.expect_value(t, record.failure.os_errno, i32(2))
	_, _ = transition(&record, .Closing)
	_, _ = transition(&record, .Closed)
	testing.expect_value(t, record.failure.code, Failure_Code.Spawn)
}

/* Verifies identities, contexts, and limits reject invalid or oversized values. */
@(test)
session_record_validates_prepared_inputs_and_limits :: proc(t: ^testing.T) {
	_, ok, failure := prepare_record({}, "", .Invalid, "", "relative")
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Argument)
	testing.expect(t, limits_valid(DEFAULT_LIMITS))
	invalid_limits := DEFAULT_LIMITS
	invalid_limits.input_bytes = MAX_INPUT_BYTES + 1
	testing.expect(t, !limits_valid(invalid_limits))
}
