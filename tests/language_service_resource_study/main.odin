// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "base:runtime"
import reference "../language_service_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

ACCOUNTING_GATE_NS :: i64(1_000_000)
LIFECYCLE_GATE_NS :: i64(1_000_000)
TEARDOWN_GATE_NS :: i64(500_000_000)

Definition_Record :: struct {
	id:           u64,
	provider_id:  u64,
	option_bytes: u32,
}

Session_Record :: struct {
	id:           u64,
	generation:   u64,
	first_doc:    u32,
	document_count: u16,
	health:       reference.Health,
}

Document_Record :: struct {
	id:               u64,
	session_id:       u64,
	revision:         u64,
	document_version: i64,
	uri_bytes:        u32,
}

Frame_Record :: struct {
	session_id: u64,
	request_id: u64,
	body_bytes: u32,
	depth:      u16,
}

Request_Record :: struct {
	id:         u64,
	session_id: u64,
	deadline:   i64,
}

Diagnostic_Record :: struct {
	document_id: u64,
	revision:    u64,
	start:       u32,
	end:         u32,
	message_bytes: u32,
	severity:    u8,
}

Profile :: struct {
	name:                  string,
	definitions:           int,
	sessions:              int,
	documents:             int,
	frames:                int,
	requests:              int,
	diagnostics:           int,
	accounted_queue_bytes: u64,
	accounted_sync_bytes:  u64,
	queue_window_bytes:    int,
	sync_window_bytes:     int,
	temporary_bytes:       int,
	samples:               int,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	profiles := [?]Profile {
		{
			name = "ordinary",
			definitions = 2,
			sessions = 1,
			documents = 8,
			frames = 32,
			requests = 16,
			diagnostics = 256,
			accounted_queue_bytes = 256 * 1_024,
			accounted_sync_bytes = 1 * 1_024 * 1_024,
			queue_window_bytes = 256 * 1_024,
			sync_window_bytes = 1 * 1_024 * 1_024,
			temporary_bytes = 2 * 1_024 * 1_024,
			samples = 128,
		},
		{
			name = "demanding",
			definitions = 16,
			sessions = 8,
			documents = 1_024,
			frames = 2_048,
			requests = 512,
			diagnostics = 16_384,
			accounted_queue_bytes = 16 * 1_024 * 1_024,
			accounted_sync_bytes = 32 * 1_024 * 1_024,
			queue_window_bytes = 8 * 1_024 * 1_024,
			sync_window_bytes = 16 * 1_024 * 1_024,
			temporary_bytes = 32 * 1_024 * 1_024,
			samples = 32,
		},
		{
			name = "stress",
			definitions = reference.MAX_SERVICE_DEFINITIONS,
			sessions = reference.MAX_SESSIONS,
			documents = reference.MAX_DOCUMENTS_TOTAL,
			frames = reference.MAX_QUEUE_DEPTH,
			requests = reference.MAX_OUTSTANDING_REQUESTS,
			diagnostics = reference.MAX_DIAGNOSTICS_PER_PROJECT,
			accounted_queue_bytes = reference.MAX_QUEUE_BYTES,
			accounted_sync_bytes = reference.MAX_SYNCHRONIZATION_BYTES,
			queue_window_bytes = 16 * 1_024 * 1_024,
			sync_window_bytes = 32 * 1_024 * 1_024,
			temporary_bytes = 64 * 1_024 * 1_024,
			samples = 8,
		},
	}

	passed := print_policy()
	for profile in profiles do passed = run_profile(profile) && passed
	passed = run_rejections() && passed
	passed = run_allocation_fault() && passed
	if !passed do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := reference.MAX_SERVICE_DEFINITIONS == 64 &&
		reference.MAX_PROVIDERS == 64 &&
		reference.MAX_SESSIONS == 32 &&
		reference.MAX_DOCUMENTS_TOTAL == 4_096 &&
		reference.MAX_FRAME_HEADER_BYTES == 8 * 1_024 &&
		reference.MAX_JSON_DEPTH == 64 &&
		reference.MAX_MESSAGE_BYTES == 16 * 1_024 * 1_024 &&
		reference.MAX_QUEUE_DEPTH == 4_096 &&
		reference.MAX_OUTSTANDING_REQUESTS == 1_024 &&
		reference.MAX_SYNCHRONIZATION_BYTES == 64 * 1_024 * 1_024 &&
		reference.MAX_DIAGNOSTICS_PER_PROJECT == 65_536 &&
		reference.MAX_AUTOMATIC_RESTARTS == 1
	fmt.printf(
		"study=language-service profile=policy valid=%v definitions=%d providers=%d sessions=%d documents_per_session=%d documents_total=%d executable_bytes=%d arguments=%d argument_bytes=%d environment_entries=%d environment_bytes=%d root_bytes=%d uri_bytes=%d options_bytes=%d frame_header_bytes=%d json_depth=%d message_bytes=%d stream_bytes=%d requests=%d notifications=%d queue_depth=%d queue_bytes=%d sync_changes=%d sync_bytes=%d diagnostics_per_document=%d diagnostics_per_project=%d diagnostic_fields=%d diagnostic_message_bytes=%d related_locations=%d diagnostic_bytes=%d candidates=%d candidate_text_bytes=%d stderr_bytes=%d work_bytes_per_turn=%d retained_bytes=%d temporary_bytes=%d automatic_restarts=%d accounting_gate_ns=%d lifecycle_gate_ns=%d teardown_gate_ns=%d\n",
		valid,
		reference.MAX_SERVICE_DEFINITIONS,
		reference.MAX_PROVIDERS,
		reference.MAX_SESSIONS,
		reference.MAX_DOCUMENTS_PER_SESSION,
		reference.MAX_DOCUMENTS_TOTAL,
		reference.MAX_EXECUTABLE_BYTES,
		reference.MAX_ARGUMENTS,
		reference.MAX_ARGUMENT_BYTES,
		reference.MAX_ENVIRONMENT_ENTRIES,
		reference.MAX_ENVIRONMENT_BYTES,
		reference.MAX_ROOT_BYTES,
		reference.MAX_URI_BYTES,
		reference.MAX_OPTIONS_BYTES,
		reference.MAX_FRAME_HEADER_BYTES,
		reference.MAX_JSON_DEPTH,
		reference.MAX_MESSAGE_BYTES,
		reference.MAX_BUFFERED_STREAM_BYTES,
		reference.MAX_OUTSTANDING_REQUESTS,
		reference.MAX_NOTIFICATIONS,
		reference.MAX_QUEUE_DEPTH,
		reference.MAX_QUEUE_BYTES,
		reference.MAX_SYNCHRONIZATION_CHANGES,
		reference.MAX_SYNCHRONIZATION_BYTES,
		reference.MAX_DIAGNOSTICS_PER_DOCUMENT,
		reference.MAX_DIAGNOSTICS_PER_PROJECT,
		reference.MAX_DIAGNOSTIC_FIELDS,
		reference.MAX_DIAGNOSTIC_MESSAGE_BYTES,
		reference.MAX_RELATED_LOCATIONS,
		reference.MAX_DIAGNOSTIC_BYTES,
		reference.MAX_CANDIDATES,
		reference.MAX_CANDIDATE_TEXT_BYTES,
		reference.MAX_STDERR_BYTES,
		reference.MAX_WORK_BYTES_PER_TURN,
		reference.MAX_RETAINED_BYTES,
		reference.MAX_TEMPORARY_BYTES,
		reference.MAX_AUTOMATIC_RESTARTS,
		ACCOUNTING_GATE_NS,
		LIFECYCLE_GATE_NS,
		TEARDOWN_GATE_NS,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	definitions, definitions_error := make([]Definition_Record, profile.definitions, allocator)
	sessions, sessions_error := make([]Session_Record, profile.sessions, allocator)
	documents, documents_error := make([]Document_Record, profile.documents, allocator)
	frames, frames_error := make([]Frame_Record, profile.frames, allocator)
	requests, requests_error := make([]Request_Record, profile.requests, allocator)
	diagnostics, diagnostics_error := make([]Diagnostic_Record, profile.diagnostics, allocator)
	queue_window, queue_error := make([]u8, profile.queue_window_bytes, allocator)
	sync_window, sync_error := make([]u8, profile.sync_window_bytes, allocator)
	if definitions_error != nil || sessions_error != nil || documents_error != nil ||
	   frames_error != nil || requests_error != nil || diagnostics_error != nil ||
	   queue_error != nil || sync_error != nil {
		cleanup_storage(definitions, sessions, documents, frames, requests, diagnostics, queue_window, sync_window, allocator)
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=language-service profile=%s phase=allocation valid=false\n", profile.name)
		return false
	}

	fill_storage(definitions, sessions, documents, frames, requests, diagnostics)
	retained_bytes := tracking.current_memory_allocated
	retained_usage_bytes := u64(max(retained_bytes, 0))
	usage := reference.Usage {
		documents = u32(min(profile.documents / profile.sessions, reference.MAX_DOCUMENTS_PER_SESSION)),
		outstanding_requests = u32(profile.requests),
		notifications = u32(profile.frames),
		queue_depth = u32(profile.frames),
		queue_bytes = profile.accounted_queue_bytes,
		synchronization_changes = u32(profile.frames),
		synchronization_bytes = profile.accounted_sync_bytes,
		diagnostics = u32(profile.diagnostics),
		diagnostic_bytes = u64(profile.diagnostics * size_of(Diagnostic_Record)),
		candidates = u32(profile.diagnostics),
		candidate_text_bytes = u64(profile.diagnostics * 64),
		standard_error_bytes = min(u64(profile.queue_window_bytes), u64(reference.MAX_STDERR_BYTES)),
		retained_bytes = retained_usage_bytes,
		temporary_bytes = u64(profile.temporary_bytes),
	}

	accounting_samples := make([]i64, profile.samples)
	lifecycle_samples := make([]i64, profile.samples)
	profile_valid := true
	for sample in 0 ..< profile.samples {
		started := time.tick_now()
		_, accounting_failure := reference.usage_sum({}, usage)
		accounting_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		started = time.tick_now()
		lifecycle_ok := lifecycle_oracle()
		lifecycle_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		profile_valid = accounting_failure.code == .None && lifecycle_ok && profile_valid
	}
	slice.sort(accounting_samples)
	slice.sort(lifecycle_samples)
	accounting_latency := latency(accounting_samples)
	lifecycle_latency := latency(lifecycle_samples)
	delete(accounting_samples)
	delete(lifecycle_samples)

	temporary, temporary_error := make([]u8, profile.temporary_bytes, allocator)
	if temporary_error != nil {
		cleanup_storage(definitions, sessions, documents, frames, requests, diagnostics, queue_window, sync_window, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	peak_bytes := tracking.peak_memory_allocated
	delete(temporary, allocator)

	teardown_started := time.tick_now()
	cleanup_storage(definitions, sessions, documents, frames, requests, diagnostics, queue_window, sync_window, allocator)
	teardown_ns := time.duration_nanoseconds(time.tick_since(teardown_started))
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	valid := profile_valid &&
		accounting_latency.p99_ns <= ACCOUNTING_GATE_NS &&
		lifecycle_latency.p99_ns <= LIFECYCLE_GATE_NS &&
		peak_bytes <= reference.MAX_RETAINED_BYTES + reference.MAX_TEMPORARY_BYTES &&
		teardown_ns <= TEARDOWN_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=language-service profile=%s valid=%v definitions=%d sessions=%d documents=%d frames=%d requests=%d diagnostics=%d accounted_queue_bytes=%d accounted_sync_bytes=%d retained_bytes=%d peak_bytes=%d accounting_p50_ns=%d accounting_p99_ns=%d lifecycle_p50_ns=%d lifecycle_p99_ns=%d teardown_ns=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.definitions,
		profile.sessions,
		profile.documents,
		profile.frames,
		profile.requests,
		profile.diagnostics,
		profile.accounted_queue_bytes,
		profile.accounted_sync_bytes,
		retained_bytes,
		peak_bytes,
		accounting_latency.p50_ns,
		accounting_latency.p99_ns,
		lifecycle_latency.p50_ns,
		lifecycle_latency.p99_ns,
		teardown_ns,
		cleanup_bytes,
	)
	return valid
}

run_rejections :: proc() -> bool {
	_, document_failure := reference.usage_sum(
		{},
		reference.Usage{documents = reference.MAX_DOCUMENTS_PER_SESSION + 1},
	)
	_, queue_failure := reference.usage_sum(
		reference.Usage{queue_bytes = max(u64)},
		reference.Usage{queue_bytes = 1},
	)
	session := active_session()
	failed, exited, process_failure := reference.step(session, reference.Event{kind = .Process_Exited})
	reaped, reap_ok, _ := reference.step(failed, reference.Event{kind = .Reaped})
	restarted, restart_ok, _ := reference.step(reaped, reference.Event{kind = .Restart})
	restarted.health = .Failed
	_, second_restart, restart_failure := reference.step(restarted, reference.Event{kind = .Restart})
	cancelled, cancel_ok, _ := reference.step(session, reference.Event{kind = .Cancel})
	_, timeout_ok, timeout_failure := reference.step(
		cancelled,
		reference.Event{kind = .Deadline_Expired, deadline = .Cancellation},
	)
	valid := document_failure.code == .Resource_Limit &&
		queue_failure.code == .Overflow && exited &&
		process_failure.code == .Process && reap_ok && restart_ok &&
		!second_restart && restart_failure.code == .Restart_Exhausted &&
		cancel_ok && timeout_ok && timeout_failure.code == .Deadline
	fmt.printf(
		"study=language-service profile=rejection valid=%v document_limit_rejected=%v queue_overflow_rejected=%v process_failure_contained=%v one_restart_enforced=%v cancellation_timeout_contained=%v\n",
		valid,
		document_failure.code == .Resource_Limit,
		queue_failure.code == .Overflow,
		exited && process_failure.code == .Process,
		restart_ok && !second_restart,
		cancel_ok && timeout_ok,
	)
	return valid
}

run_allocation_fault :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Failing_Allocator{backing = mem.tracking_allocator(&tracking), fail_after = 1}
	allocator := failing_allocator(&failing)
	first, first_error := make([]u8, 1_024, allocator)
	_, second_error := make([]u8, 1_024, allocator)
	if first != nil do delete(first, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := first_error == nil && second_error != nil && cleanup_bytes == 0
	fmt.printf(
		"study=language-service profile=allocation-fault valid=%v allocation_rejected=%v cleanup_bytes=%d\n",
		valid,
		second_error != nil,
		cleanup_bytes,
	)
	return valid
}

active_session :: proc() -> reference.Session {
	session := reference.initial_session()
	events := [?]reference.Event {
		{kind = .Discover},
		{kind = .Discovery_Succeeded},
		{kind = .Spawned},
		{kind = .Initialized},
	}
	for event in events {
		next, accepted, _ := reference.step(session, event)
		if !accepted do return {}
		session = next
	}
	return session
}

lifecycle_oracle :: proc() -> bool {
	session := active_session()
	if session.health != .Active do return false
	cancelled, cancel_ok, _ := reference.step(session, reference.Event{kind = .Cancel})
	resumed, resume_ok, _ := reference.step(cancelled, reference.Event{kind = .Cancellation_Completed})
	shutting, shutdown_ok, _ := reference.step(resumed, reference.Event{kind = .Begin_Shutdown})
	terminating, termination_ok, _ := reference.step(shutting, reference.Event{kind = .Shutdown_Completed})
	exited, exit_ok, _ := reference.step(terminating, reference.Event{kind = .Process_Exited})
	stopped, reap_ok, _ := reference.step(exited, reference.Event{kind = .Reaped})
	return cancel_ok && resume_ok && shutdown_ok && termination_ok && exit_ok &&
		reap_ok && stopped.health == .Stopped
}

fill_storage :: proc(
	definitions: []Definition_Record,
	sessions: []Session_Record,
	documents: []Document_Record,
	frames: []Frame_Record,
	requests: []Request_Record,
	diagnostics: []Diagnostic_Record,
) {
	for &definition, index in definitions {
		definition = Definition_Record{id = u64(index + 1), provider_id = u64(index + 1), option_bytes = 256}
	}
	for &session, index in sessions {
		first_doc := index * (len(documents) / len(sessions))
		session = Session_Record{
			id = u64(index + 1),
			generation = 1,
			first_doc = u32(first_doc),
			document_count = u16(min(len(documents) / len(sessions), reference.MAX_DOCUMENTS_PER_SESSION)),
			health = .Active,
		}
	}
	for &document, index in documents {
		document = Document_Record{
			id = u64(index + 1),
			session_id = u64(index % len(sessions) + 1),
			revision = 1,
			document_version = 1,
			uri_bytes = 128,
		}
	}
	for &frame, index in frames {
		frame = Frame_Record{
			session_id = u64(index % len(sessions) + 1),
			request_id = u64(index + 1),
			body_bytes = 1_024,
			depth = 8,
		}
	}
	for &request, index in requests {
		request = Request_Record{
			id = u64(index + 1),
			session_id = u64(index % len(sessions) + 1),
			deadline = reference.REQUEST_DEADLINE_NS,
		}
	}
	for &diagnostic, index in diagnostics {
		diagnostic = Diagnostic_Record{
			document_id = u64(index % len(documents) + 1),
			revision = 1,
			start = u32(index),
			end = u32(index + 1),
			message_bytes = 64,
			severity = u8(index % 4 + 1),
		}
	}
}

cleanup_storage :: proc(
	definitions: []Definition_Record,
	sessions: []Session_Record,
	documents: []Document_Record,
	frames: []Frame_Record,
	requests: []Request_Record,
	diagnostics: []Diagnostic_Record,
	queue_window, sync_window: []u8,
	allocator: runtime.Allocator,
) {
	if sync_window != nil do delete(sync_window, allocator)
	if queue_window != nil do delete(queue_window, allocator)
	if diagnostics != nil do delete(diagnostics, allocator)
	if requests != nil do delete(requests, allocator)
	if frames != nil do delete(frames, allocator)
	if documents != nil do delete(documents, allocator)
	if sessions != nil do delete(sessions, allocator)
	if definitions != nil do delete(definitions, allocator)
}

latency :: proc(samples: []i64) -> Latency {
	return Latency{
		p50_ns = samples[(len(samples) - 1) * 50 / 100],
		p99_ns = samples[(len(samples) - 1) * 99 / 100],
	}
}

Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = failing_allocator_proc, data = data}
}

failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
