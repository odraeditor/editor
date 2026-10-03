// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "core:mem"
import "core:testing"
import "core:time"

@(private)
registry_test_request :: proc(name: string = "", make_default := false) -> Session_Prepare_Request {
	return Session_Prepare_Request {
		name = name,
		owner_kind = .Interactive_User,
		owner_label = "test owner",
		working_directory = "/tmp",
		limits = DEFAULT_LIMITS,
		make_default = make_default,
	}
}

@(private)
registry_test_start :: proc(
	registry: ^Registry,
	name: string,
	arguments: []string,
	make_default := false,
) -> (Session_Record, bool, Failure_Record) {
	record, prepared, failure := registry_prepare(
		registry,
		registry_test_request(name, make_default),
	)
	if !prepared do return record, false, failure
	return registry_start(
		registry,
		record.ref,
		Process_Start_Request {
			executable = "/bin/sh",
			arguments = arguments,
			working_directory = "/tmp",
			columns = 80,
			rows = 24,
		},
	)
}

@(private)
registry_test_wait_for_exit :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (Session_Record, bool, Failure_Record) {
	for _ in 0 ..< 2_000 {
		record, ok, failure := registry_poll(registry, ref)
		if !ok || record.lifecycle == .Exited || record.lifecycle == .Failed {
			return record, ok, failure
		}
		time.sleep(time.Millisecond)
	}
	return {}, false, failure_record(.Poll, .Reap)
}

/* Verifies fixed capacity, stable names, generations, and exact registry cleanup. */
@(test)
registry_enforces_capacity_names_and_stale_generations :: proc(t: ^testing.T) {
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

	first_ref: Session_Ref
	for index in 0 ..< MAX_SESSIONS {
		record, prepared, failure := registry_prepare(&registry, registry_test_request())
		testing.expectf(t, prepared, "prepare %v failed with %v", index, failure.code)
		if !prepared do continue
		if index == 0 {
			first_ref = record.ref
			testing.expect_value(t, session_name_view(&record.name), "terminal")
		}
		if index == 1 {
			testing.expect_value(t, session_name_view(&record.name), "terminal-2")
		}
	}
	_, capacity_prepared, capacity_failure := registry_prepare(&registry, registry_test_request())
	testing.expect(t, !capacity_prepared)
	testing.expect_value(t, capacity_failure.code, Failure_Code.Capacity)

	closed, close_failure := registry_close_session(&registry, first_ref)
	testing.expectf(t, closed, "session close failed with %v", close_failure.code)
	replacement, replacement_prepared, replacement_failure := registry_prepare(
		&registry,
		registry_test_request("replacement"),
	)
	testing.expectf(t, replacement_prepared, "replacement failed with %v", replacement_failure.code)
	testing.expect_value(t, replacement.ref.id, first_ref.id)
	testing.expect_value(
		t,
		replacement.ref.generation,
		Session_Generation(u32(first_ref.generation) + 1),
	)
	_, found, stale_failure := registry_record(&registry, first_ref)
	testing.expect(t, !found)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)

	closed, close_failure = registry_close(&registry)
	testing.expectf(t, closed, "registry close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	closed, close_failure = registry_close(&registry)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Cleanup)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies duplicate protection, explicit rename, and copied provenance inspection. */
@(test)
registry_renames_and_inspects_copied_sessions :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	first, first_ok, _ := registry_prepare(&registry, registry_test_request("build"))
	second, second_ok, _ := registry_prepare(&registry, registry_test_request("repl"))
	testing.expect(t, first_ok && second_ok)
	_, renamed, duplicate_failure := registry_rename(&registry, second.ref, "build")
	testing.expect(t, !renamed)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Name)
	second, renamed, duplicate_failure = registry_rename(&registry, second.ref, "shell")
	testing.expectf(t, renamed, "rename failed with %v", duplicate_failure.code)
	testing.expect_value(t, session_name_view(&second.name), "shell")
	testing.expect_value(t, owner_label_view(&second.owner), "test owner")
	testing.expect_value(t, working_context_view(&second.working_context), "/tmp")

	copy, found, _ := registry_record(&registry, first.ref)
	testing.expect(t, found)
	copy.name.bytes[0] = 'X'
	canonical, canonical_found, _ := registry_record(&registry, first.ref)
	testing.expect(t, canonical_found)
	testing.expect_value(t, session_name_view(&canonical.name), "build")
}

/* Verifies eight operating children and aggregate descriptor accounting. */
@(test)
registry_owns_eight_concurrent_processes :: proc(t: ^testing.T) {
	registry: Registry
	initialized, init_failure := registry_init(&registry)
	testing.expectf(t, initialized, "registry init failed with %v", init_failure.code)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	arguments := []string{"-c", "sleep 30"}
	for _ in 0 ..< OPERATING_SESSIONS {
		_, started, failure := registry_test_start(&registry, "", arguments)
		testing.expectf(t, started, "concurrent start failed with %v", failure.code)
	}
	stats, inspected, inspect_failure := registry_inspect(&registry)
	testing.expectf(t, inspected, "registry inspect failed with %v", inspect_failure.code)
	testing.expect_value(t, stats.session_count, u16(OPERATING_SESSIONS))
	testing.expect_value(t, stats.operating_count, u16(OPERATING_SESSIONS))
	testing.expect_value(t, stats.open_descriptors, u16(OPERATING_SESSIONS))
}

/* Verifies an exited default is replaced by another running session. */
@(test)
registry_replaces_exited_default_session :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	long_arguments := []string{"-c", "sleep 30"}
	long_session, started, failure := registry_test_start(
		&registry,
		"long-running",
		long_arguments,
	)
	testing.expectf(t, started, "long-running start failed with %v", failure.code)
	quick_arguments := []string{"-c", "exit 0"}
	quick_session, quick_started, quick_failure := registry_test_start(
		&registry,
		"quick",
		quick_arguments,
		true,
	)
	testing.expectf(t, quick_started, "quick start failed with %v", quick_failure.code)
	default_record, default_ok, _ := registry_default(&registry)
	testing.expect(t, default_ok)
	testing.expect_value(t, default_record.ref, quick_session.ref)

	exited, polled, poll_failure := registry_test_wait_for_exit(&registry, quick_session.ref)
	testing.expectf(t, polled, "quick poll failed with %v", poll_failure.code)
	testing.expect_value(t, exited.lifecycle, Lifecycle.Exited)
	default_record, default_ok, _ = registry_default(&registry)
	testing.expect(t, default_ok)
	testing.expect_value(t, default_record.ref, long_session.ref)
}
