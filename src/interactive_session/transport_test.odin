// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "core:strings"
import "core:testing"
import "core:time"

@(private)
transport_test_start :: proc(
	registry: ^Registry,
	name: string,
	executable: string,
	arguments: []string,
	limits := DEFAULT_LIMITS,
) -> (Session_Record, bool, Failure_Record) {
	prepare_request := registry_test_request(name)
	prepare_request.limits = limits
	record, prepared, failure := registry_prepare(registry, prepare_request)
	if !prepared do return record, false, failure
	return registry_start(
		registry,
		record.ref,
		Process_Start_Request {
			executable = executable,
			arguments = arguments,
			working_directory = "/tmp",
			columns = limits.columns,
			rows = limits.rows,
		},
	)
}

/* Verifies idle turns do not spin and queued input rejects overflow. */
@(test)
transport_bounds_input_and_reports_idle_work :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	limits := DEFAULT_LIMITS
	limits.input_bytes = 16
	limits.output_bytes = 128
	arguments: []string
	record, started, failure := transport_test_start(
		&registry,
		"bounded-input",
		"/bin/cat",
		arguments,
		limits,
	)
	testing.expectf(t, started, "cat start failed with %v", failure.code)
	if !started do return

	started_at := time.tick_now()
	step, stepped := registry_step(&registry, record.ref, 1)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started_at))
	testing.expect(t, stepped)
	testing.expect(t, !step.progress && step.would_block)
	testing.expect(t, elapsed_ns < 20 * i64(time.Millisecond))

	input := transmute([]u8)(string("0123456789abcdef"))
	queued, queue_failure := registry_send(&registry, record.ref, input)
	testing.expectf(t, queued, "input queue failed with %v", queue_failure.code)
	queued, queue_failure = registry_send(&registry, record.ref, []u8{'x'})
	testing.expect(t, !queued)
	testing.expect_value(t, queue_failure.code, Failure_Code.Input_Limit)

	output_ready := false
	for turn in 0 ..< 200 {
		step, stepped = registry_step(&registry, record.ref, i64(turn + 2))
		testing.expect(t, stepped)
		if step.output_ready {
			output_ready = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, output_ready)
}

/* Verifies a slow consumer backpressures the PTY without dropping output. */
@(test)
transport_backpressures_and_resumes_output :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	limits := DEFAULT_LIMITS
	limits.output_bytes = 4 * 1_024
	limits.read_chunk_bytes = 1_024
	limits.output_turn_bytes = 1_024
	arguments := []string {
		"-c",
		"dd if=/dev/zero bs=4096 count=8 2>/dev/null | tr '\\000' x",
	}
	record, started, failure := transport_test_start(
		&registry,
		"burst",
		"/bin/sh",
		arguments,
		limits,
	)
	testing.expectf(t, started, "burst start failed with %v", failure.code)
	if !started do return

	backpressured := false
	for turn in 0 ..< 2_000 {
		step, stepped := registry_step(&registry, record.ref, i64(turn + 1))
		testing.expect(t, stepped)
		if step.backpressured {
			backpressured = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, backpressured)
	storage: [4 * 1_024]u8
	copied, available, take_failure := registry_take_output(&registry, record.ref, storage[:])
	testing.expectf(t, available, "output take failed with %v", take_failure.code)
	testing.expect_value(t, copied, len(storage))

	resumed := false
	for turn in 0 ..< 2_000 {
		step, stepped := registry_step(&registry, record.ref, i64(turn + 2_001))
		testing.expect(t, stepped)
		if step.read_bytes > 0 {
			resumed = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, resumed)
}

/* Verifies round-robin stepping exposes output from independent sessions. */
@(test)
transport_steps_sessions_fairly :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	first_arguments := []string{"-c", "printf first; sleep 30"}
	second_arguments := []string{"-c", "printf second; sleep 30"}
	first, first_started, first_failure := transport_test_start(
		&registry,
		"first",
		"/bin/sh",
		first_arguments,
	)
	second, second_started, second_failure := transport_test_start(
		&registry,
		"second",
		"/bin/sh",
		second_arguments,
	)
	testing.expectf(t, first_started, "first start failed with %v", first_failure.code)
	testing.expectf(t, second_started, "second start failed with %v", second_failure.code)
	if !first_started || !second_started do return

	first_text, second_text := false, false
	storage: [128]u8
	for turn in 0 ..< 200 {
		batch, stepped := registry_step_all(&registry, i64(turn + 1))
		testing.expectf(t, stepped, "batch failed with %v", batch.failure.code)
		if copied, available, _ := registry_take_output(&registry, first.ref, storage[:]);
		   available && strings.contains(string(storage[:copied]), "first") {
			first_text = true
		}
		if copied, available, _ := registry_take_output(&registry, second.ref, storage[:]);
		   available && strings.contains(string(storage[:copied]), "second") {
			second_text = true
		}
		if first_text && second_text do break
		if batch.sessions_progressed == 0 do time.sleep(time.Millisecond)
	}
	testing.expect(t, first_text && second_text)
}

/* Verifies cancellation interrupts, reaps, and rejects repeated requests. */
@(test)
transport_cancels_without_affecting_other_sessions :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	arguments := []string{"30"}
	cancelled, started, failure := transport_test_start(
		&registry,
		"cancelled",
		"/bin/sleep",
		arguments,
	)
	other, other_started, other_failure := transport_test_start(
		&registry,
		"other",
		"/bin/sleep",
		arguments,
	)
	testing.expectf(t, started, "cancel target failed with %v", failure.code)
	testing.expectf(t, other_started, "other session failed with %v", other_failure.code)
	if !started || !other_started do return
	requested, cancel_failure := registry_request_cancel(&registry, cancelled.ref, 1)
	testing.expectf(t, requested, "cancel request failed with %v", cancel_failure.code)

	exited := false
	for turn in 0 ..< 2_000 {
		step, stepped := registry_step(&registry, cancelled.ref, i64(turn + 2))
		testing.expectf(t, stepped, "cancel step failed with %v", step.failure.code)
		if step.process_exited {
			exited = true
			break
		}
		if !step.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, exited)
	other_record, found, _ := registry_record(&registry, other.ref)
	testing.expect(t, found)
	testing.expect_value(t, other_record.lifecycle, Lifecycle.Running)
	requested, cancel_failure = registry_request_cancel(&registry, cancelled.ref, 3_000)
	testing.expect(t, !requested)
	testing.expect_value(t, cancel_failure.code, Failure_Code.Invalid_Transition)
}
