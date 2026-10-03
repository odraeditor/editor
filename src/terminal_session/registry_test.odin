// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:mem"
import "core:testing"
import "core:time"
import "../interactive_session"
import "../terminal_emulator"

@(private)
test_open_request :: proc(
	name := "terminal",
	arguments := []string{"-c", "printf ready; sleep 0.02"},
	emulator := terminal_emulator.DEFAULT_OPTIONS,
) -> Open_Request {
	return Open_Request {
		process = interactive_session.Session_Prepare_Request {
			name = name,
			owner_kind = .Interactive_User,
			owner_label = "terminal session test",
			working_directory = "/tmp",
			limits = interactive_session.DEFAULT_LIMITS,
			make_default = true,
		},
		start = interactive_session.Process_Start_Request {
			executable = "/bin/sh",
			arguments = arguments,
			working_directory = "/tmp",
			columns = 80,
			rows = 24,
		},
		emulator = emulator,
		limits = DEFAULT_LIMITS,
	}
}

/* Verifies one owner acquires, exposes, and releases both subordinate resources. */
@(test)
registry_composes_process_and_emulator_ownership :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	initialized, init_failure := registry_init(&registry, allocator)
	testing.expectf(t, initialized, "registry init failed with %v", init_failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	record, opened, open_failure := registry_open(&registry, test_open_request())
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if opened {
		testing.expect_value(t, record.lifecycle, Lifecycle.Running)
		testing.expect(t, record.process.resources.process_id > 0)
		stats, stats_result := terminal_emulator.stats(record.emulator)
		testing.expect_value(t, stats_result, terminal_emulator.Result.OK)
		testing.expect(t, stats.live)
		closed, close_failure := registry_close_session(&registry, record.ref)
		testing.expectf(t, closed, "terminal close failed with %v", close_failure.code)
		closed, close_failure = registry_close_session(&registry, record.ref)
		testing.expect(t, !closed)
		testing.expect_value(t, close_failure.code, Failure_Code.Stale_Reference)
		_, found, stale_failure := registry_record(&registry, record.ref)
		testing.expect(t, !found)
		testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)
		stats, stats_result = terminal_emulator.stats(record.emulator)
		testing.expect_value(t, stats_result, terminal_emulator.Result.OK)
		testing.expect(t, !stats.live)

		replacement, reopened, replacement_failure := registry_open(
			&registry,
			test_open_request("replacement"),
		)
		testing.expectf(t, reopened, "replacement open failed with %v", replacement_failure.code)
		if reopened {
			testing.expect_value(t, replacement.ref.id, record.ref.id)
			testing.expect_value(
				t,
				replacement.ref.generation,
				Session_Generation(u32(record.ref.generation) + 1),
			)
			_, found, stale_failure = registry_record(&registry, record.ref)
			testing.expect(t, !found)
			testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)
		}
	}

	closed, close_failure := registry_close(&registry)
	testing.expectf(t, closed, "registry close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies emulator and process startup failures roll back every acquired resource. */
@(test)
registry_rolls_back_partial_startup :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	emulator_options := terminal_emulator.DEFAULT_OPTIONS
	emulator_options.allocation_fail_after = 1
	_, opened, emulator_issue := registry_open(
		&registry,
		test_open_request("emulator failure", emulator = emulator_options),
	)
	testing.expect(t, !opened)
	testing.expect_value(t, emulator_issue.code, Failure_Code.Emulator)
	stats, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(0))

	request := test_open_request("process failure")
	request.start.executable = "/definitely/missing/terminal-session-test"
	process_issue: Failure_Record
	_, opened, process_issue = registry_open(&registry, request)
	testing.expect(t, !opened)
	testing.expect_value(t, process_issue.code, Failure_Code.Process)
	stats, inspected, _ = registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.session_count, u16(0))

	valid: Session_Record
	valid_issue: Failure_Record
	valid, opened, valid_issue = registry_open(&registry, test_open_request("replacement"))
	testing.expectf(t, opened, "replacement open failed with %v", valid_issue.code)
	if opened {
		testing.expect_value(t, valid.ref.id, Session_ID(1))
	}
}

/* Verifies process exit remains inspectable until coordinated close. */
@(test)
registry_retains_exited_generation :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	record, opened, _ := registry_open(
		&registry,
		test_open_request("exit", arguments = []string{"-c", "exit 7"}),
	)
	testing.expect(t, opened)
	if !opened do return

	for _ in 0 ..< 2_000 {
		record, opened, _ = registry_poll(&registry, record.ref)
		if !opened || record.lifecycle == .Exited do break
		time.sleep(time.Millisecond)
	}
	testing.expect(t, opened)
	testing.expect_value(t, record.lifecycle, Lifecycle.Exited)
	testing.expect_value(t, record.process.exit_status.value, i32(7))
	_, emulator_result := terminal_emulator.render(record.emulator)
	testing.expect_value(t, emulator_result, terminal_emulator.Result.OK)
}
