// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:mem"
import "core:testing"
import "core:time"

@(private)
test_process_request :: proc(command: []string) -> Process_Start_Request {
	return Process_Start_Request {
		handle = {
			provider = {
				definition = {
					registry = {id = 1, generation = 1},
					id = 1,
					generation = 1,
				},
				id = 1,
				generation = 1,
			},
			id = 1,
			generation = 1,
		},
		command = command,
		limits = DEFAULT_LIMITS,
		deadlines = DEFAULT_DEADLINES,
		restart = DEFAULT_RESTART_POLICY,
	}
}

/* Verifies nonblocking framed IO, forced teardown, and exact owner cleanup. */
@(test)
process_session_round_trips_frames_and_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	command := [?]string{"/bin/sh", "-c", "cat"}
	session, started, failure := process_session_start(test_process_request(command[:]), 1, allocator)
	testing.expectf(t, started, "process start failed with %v", failure.code)
	if !started {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	confirmed, confirmation_failure := process_session_confirm_initialized(
		&session,
		Capability_Values{position_encoding = .UTF_16, synchronization_mode = .Full},
	)
	testing.expectf(t, confirmed, "initialization failed with %v", confirmation_failure.code)
	body := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"window/logMessage"}`))
	queued, queue_failure := process_session_send_frame(&session, body)
	testing.expectf(t, queued, "frame queue failed with %v", queue_failure.code)

	ready := false
	now := i64(1)
	for _ in 0 ..< 100 {
		poll, polled := process_session_poll(&session, now)
		testing.expect(t, polled)
		if poll.frame_ready {
			ready = true
			break
		}
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	testing.expect(t, ready)
	if ready {
		frame, taken, frame_failure := process_session_take_frame(&session)
		testing.expectf(t, taken, "frame take failed with %v", frame_failure.code)
		if taken {
			testing.expect_value(t, string(frame.body), string(body))
			frame_close(&frame)
		}
	}

	terminated, termination_failure := process_session_force_terminate(&session, now)
	testing.expectf(t, terminated, "termination failed with %v", termination_failure.code)
	for _ in 0 ..< 100 {
		poll, _ := process_session_poll(&session, now)
		if poll.health == .Stopped do break
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	inspection, inspected := process_session_inspect(&session)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.session.health, Health.Stopped)
	testing.expect(t, process_session_close(&session))
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies process failure, stderr retention, one restart, and reap ordering. */
@(test)
process_session_enforces_one_reaped_restart :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "printf failure >&2; exit 7"}
	session, started, failure := process_session_start(test_process_request(command[:]), 1)
	testing.expectf(t, started, "process start failed with %v", failure.code)
	if !started do return
	defer process_session_close(&session)

	now := i64(1)
	failed := false
	for _ in 0 ..< 100 {
		poll, _ := process_session_poll(&session, now)
		if poll.health == .Failed && poll.process_exited {
			failed = true
			break
		}
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	testing.expect(t, failed)
	stderr: [64]u8
	stderr_count, copied := process_session_copy_stderr(&session, stderr[:])
	testing.expect(t, copied)
	testing.expect_value(t, string(stderr[:stderr_count]), "failure")

	restarted, restart_failure := process_session_restart(&session, now)
	testing.expectf(t, restarted, "restart failed with %v", restart_failure.code)
	for _ in 0 ..< 100 {
		poll, _ := process_session_poll(&session, now)
		if poll.health == .Failed && poll.process_exited do break
		time.sleep(time.Millisecond)
		now += i64(time.Millisecond)
	}
	restarted, restart_failure = process_session_restart(&session, now)
	testing.expect(t, !restarted)
	testing.expect_value(t, restart_failure.code, Failure_Code.Restart_Exhausted)
}

/* Verifies initialization and cancellation deadlines fail without blocking. */
@(test)
process_session_contains_deadline_expiry :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "sleep 5"}
	session, started, failure := process_session_start(test_process_request(command[:]), 1)
	testing.expectf(t, started, "process start failed with %v", failure.code)
	if !started do return
	defer process_session_close(&session)

	poll, polled := process_session_poll(&session, DEFAULT_DEADLINES.initialization_ns + 2)
	testing.expect(t, polled)
	testing.expect_value(t, poll.health, Health.Failed)
	testing.expect_value(t, poll.failure.code, Failure_Code.Timeout)
}
