// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:strings"
import "core:testing"
import "core:time"
import "../interactive_session"
import "../terminal_emulator"

/* Verifies split, malformed, and effect-producing streams continue in ground state. */
@(test)
output_processes_partial_streams_and_routes_effects :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	request := test_open_request(
		"partial-output",
		arguments = []string {
			"-c",
			"printf '\\033[999999999999999999999999xplain'; " +
				"printf '\\342'; sleep 0.05; " +
				"printf '\\202\\254\\033['; sleep 0.05; " +
				"printf '31mred\\033[0m\\a\\033[6n'; sleep 0.05",
		},
	)
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(t, opened, "terminal open failed with %v", failure.code)
	if !opened do return

	parsed_turns := 0
	parsed_bytes, writeback_bytes, bell_count: u64
	for turn in 0 ..< 2_000 {
		observation, stepped := registry_step_output(&registry, record.ref, i64(turn + 1))
		testing.expectf(t, stepped, "output turn failed with %v", observation.failure.code)
		if !stepped do break
		if observation.parsed_bytes > 0 do parsed_turns += 1
		parsed_bytes += observation.parsed_bytes
		writeback_bytes += observation.writeback_bytes
		bell_count += observation.bell_count
		if observation.process_exited && !observation.output_pending do break
		if !observation.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, parsed_turns >= 2)
	testing.expect(t, parsed_bytes > 0)
	testing.expect(t, writeback_bytes > 0)
	testing.expect_value(t, bell_count, u64(1))

	selection: [512]u8
	selected, selection_result := terminal_emulator.select_all(record.emulator, selection[:])
	testing.expect_value(t, selection_result, terminal_emulator.Result.OK)
	if selection_result == .OK {
		text := string(selection[:selected])
		testing.expect(t, strings.contains(text, "plain"))
		testing.expect(t, strings.contains(text, "€"))
		testing.expect(t, strings.contains(text, "red"))
	}
	current, found, record_failure := registry_record(&registry, record.ref)
	testing.expectf(t, found, "terminal record failed with %v", record_failure.code)
	if found {
		testing.expect_value(t, current.output_bytes, parsed_bytes)
		testing.expect_value(t, current.writeback_bytes, writeback_bytes)
	}
}

/* Verifies byte and time budgets retain unparsed output for later turns. */
@(test)
output_enforces_parser_turn_budgets :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	request := test_open_request(
		"byte-budget",
		arguments = []string {
			"-c",
			"dd if=/dev/zero bs=65536 count=1 2>/dev/null | tr '\\000' x",
		},
	)
	request.limits.output_turn_bytes = 1 * 1_024
	request.process.limits.read_chunk_bytes = 8 * 1_024
	request.process.limits.output_turn_bytes = 8 * 1_024
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(t, opened, "byte-budget terminal failed with %v", failure.code)
	if !opened do return

	total: u64
	saw_byte_limit := false
	process_exited := false
	for turn in 0 ..< 4_000 {
		observation, stepped := registry_step_output(&registry, record.ref, i64(turn + 1))
		testing.expectf(t, stepped, "byte-budget turn failed with %v", observation.failure.code)
		if !stepped do break
		testing.expect(t, observation.parsed_bytes <= request.limits.output_turn_bytes)
		total += observation.parsed_bytes
		saw_byte_limit = saw_byte_limit || observation.byte_budget_exhausted
		process_exited = process_exited || observation.process_exited
		if process_exited && total >= 64 * 1_024 && !observation.output_pending do break
		if !observation.progress do time.sleep(time.Millisecond)
	}
	testing.expect(t, saw_byte_limit)
	testing.expect(t, total >= 64 * 1_024)

	timed_request := test_open_request(
		"time-budget",
		arguments = []string{"-c", "printf timed; sleep 0.1"},
	)
	timed_request.limits.output_turn_nanoseconds = 1
	timed, timed_opened, timed_failure := registry_open(&registry, timed_request)
	testing.expectf(t, timed_opened, "time-budget terminal failed with %v", timed_failure.code)
	if !timed_opened do return
	saw_time_limit := false
	for turn in 0 ..< 500 {
		observation, stepped := registry_step_output(&registry, timed.ref, i64(turn + 5_000))
		testing.expectf(t, stepped, "time-budget turn failed with %v", observation.failure.code)
		if !stepped do break
		if observation.time_budget_exhausted {
			saw_time_limit = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, saw_time_limit)
}

/* Verifies write-back overflow is explicit and preserves the queued response. */
@(test)
output_reports_writeback_queue_overflow :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	request := test_open_request(
		"writeback-overflow",
		arguments = []string{"-c", "printf '\\033[6n'; sleep 0.1"},
	)
	request.process.limits.input_bytes = 1
	record, opened, failure := registry_open(&registry, request)
	testing.expectf(t, opened, "overflow terminal failed with %v", failure.code)
	if !opened do return

	saw_overflow := false
	for turn in 0 ..< 500 {
		observation, stepped := registry_step_output(&registry, record.ref, i64(turn + 1))
		if !stepped {
			testing.expect_value(t, observation.failure.stage, Failure_Stage.Parse)
			testing.expect_value(t, observation.failure.code, Failure_Code.Output_Limit)
			testing.expect_value(
				t,
				observation.failure.process_code,
				interactive_session.Failure_Code.Input_Limit,
			)
			saw_overflow = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, saw_overflow)
	effects, result := terminal_emulator.effects(record.emulator)
	testing.expect_value(t, result, terminal_emulator.Result.OK)
	testing.expect(t, effects.writeback_pending_bytes > 0)
}

/* Verifies aggregate stepping visits independent sessions fairly. */
@(test)
output_steps_composed_sessions_fairly :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	first, first_opened, first_failure := registry_open(
		&registry,
		test_open_request("fair-first", arguments = []string{"-c", "printf first; sleep 1"}),
	)
	second, second_opened, second_failure := registry_open(
		&registry,
		test_open_request("fair-second", arguments = []string{"-c", "printf second; sleep 1"}),
	)
	testing.expectf(t, first_opened, "first terminal failed with %v", first_failure.code)
	testing.expectf(t, second_opened, "second terminal failed with %v", second_failure.code)
	if !first_opened || !second_opened do return

	first_progress, second_progress := false, false
	for turn in 0 ..< 500 {
		batch, stepped := registry_step_output_all(&registry, i64(turn + 1))
		testing.expectf(t, stepped, "output batch failed with %v", batch.failure.code)
		first_record, first_found, _ := registry_record(&registry, first.ref)
		second_record, second_found, _ := registry_record(&registry, second.ref)
		first_progress = first_found && first_record.output_bytes > 0
		second_progress = second_found && second_record.output_bytes > 0
		if first_progress && second_progress do break
		if batch.sessions_progressed == 0 do time.sleep(time.Millisecond)
	}
	testing.expect(t, first_progress && second_progress)
}
