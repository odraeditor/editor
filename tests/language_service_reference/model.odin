// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_service_reference provides an independent pointer-free
// oracle for bounded language-service lifecycle and resource accounting.
package language_service_reference

MAX_SERVICE_DEFINITIONS :: 64
MAX_PROVIDERS :: 64
MAX_SESSIONS :: 32
MAX_DOCUMENTS_PER_SESSION :: 256
MAX_DOCUMENTS_TOTAL :: 4_096

MAX_EXECUTABLE_BYTES :: 4 * 1_024
MAX_ARGUMENTS :: 64
MAX_ARGUMENT_BYTES :: 64 * 1_024
MAX_ENVIRONMENT_ENTRIES :: 64
MAX_ENVIRONMENT_BYTES :: 64 * 1_024
MAX_ROOT_BYTES :: 16 * 1_024
MAX_URI_BYTES :: 32 * 1_024
MAX_OPTIONS_BYTES :: 1 * 1_024 * 1_024

MAX_FRAME_HEADER_BYTES :: 8 * 1_024
MAX_JSON_DEPTH :: 64
MAX_MESSAGE_BYTES :: 16 * 1_024 * 1_024
MAX_BUFFERED_STREAM_BYTES :: 32 * 1_024 * 1_024
MAX_OUTSTANDING_REQUESTS :: 1_024
MAX_NOTIFICATIONS :: 4_096
MAX_QUEUE_DEPTH :: 4_096
MAX_QUEUE_BYTES :: 64 * 1_024 * 1_024

MAX_SYNCHRONIZATION_CHANGES :: 4_096
MAX_SYNCHRONIZATION_BYTES :: 64 * 1_024 * 1_024
MAX_DIAGNOSTICS_PER_DOCUMENT :: 4_096
MAX_DIAGNOSTICS_PER_PROJECT :: 65_536
MAX_DIAGNOSTIC_FIELDS :: 32
MAX_DIAGNOSTIC_MESSAGE_BYTES :: 64 * 1_024
MAX_RELATED_LOCATIONS :: 32
MAX_DIAGNOSTIC_BYTES :: 128 * 1_024 * 1_024
MAX_CANDIDATES :: 65_536
MAX_CANDIDATE_TEXT_BYTES :: 64 * 1_024 * 1_024
MAX_STDERR_BYTES :: 1 * 1_024 * 1_024

MAX_WORK_BYTES_PER_TURN :: 256 * 1_024
MAX_RETAINED_BYTES :: 512 * 1_024 * 1_024
MAX_TEMPORARY_BYTES :: 128 * 1_024 * 1_024
MAX_AUTOMATIC_RESTARTS :: 1

DISCOVERY_DEADLINE_NS :: i64(500_000_000)
INITIALIZATION_DEADLINE_NS :: i64(10_000_000_000)
REQUEST_DEADLINE_NS :: i64(5_000_000_000)
CANCELLATION_DEADLINE_NS :: i64(1_000_000_000)
IDLE_STEP_DEADLINE_NS :: i64(50_000_000)
RESTART_STABILITY_NS :: i64(30_000_000_000)
SHUTDOWN_DEADLINE_NS :: i64(3_000_000_000)
FORCED_TERMINATION_DEADLINE_NS :: i64(1_000_000_000)

Health :: enum u8 {
	Stopped,
	Discovering,
	Starting,
	Initializing,
	Active,
	Cancelling,
	Shutting_Down,
	Terminating,
	Failed,
}

Deadline :: enum u8 {
	Discovery,
	Initialization,
	Request,
	Cancellation,
	Idle_Step,
	Restart_Stability,
	Shutdown,
	Forced_Termination,
}

Event_Kind :: enum u8 {
	Discover,
	Discovery_Succeeded,
	Spawned,
	Initialized,
	Account,
	Release,
	Cancel,
	Cancellation_Completed,
	Deadline_Expired,
	Process_Exited,
	Reaped,
	Restart,
	Begin_Shutdown,
	Shutdown_Completed,
	Force_Terminate,
}

Resource :: enum u8 {
	None,
	Documents,
	Outstanding_Requests,
	Notifications,
	Queue_Depth,
	Queue_Bytes,
	Synchronization_Changes,
	Synchronization_Bytes,
	Diagnostics,
	Diagnostic_Bytes,
	Candidates,
	Candidate_Text_Bytes,
	Standard_Error_Bytes,
	Retained_Bytes,
	Temporary_Bytes,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Transition,
	Overflow,
	Resource_Limit,
	Restart_Exhausted,
	Deadline,
	Process,
}

Usage :: struct {
	documents:               u32,
	outstanding_requests:    u32,
	notifications:           u32,
	queue_depth:             u32,
	queue_bytes:             u64,
	synchronization_changes: u32,
	synchronization_bytes:   u64,
	diagnostics:             u32,
	diagnostic_bytes:        u64,
	candidates:              u32,
	candidate_text_bytes:    u64,
	standard_error_bytes:    u64,
	retained_bytes:          u64,
	temporary_bytes:         u64,
}

Failure :: struct {
	code:     Failure_Code,
	resource: Resource,
	limit:    u64,
	actual:   u64,
	deadline: Deadline,
}

Session :: struct {
	generation:             u64,
	health:                 Health,
	automatic_restarts:     u8,
	process_live:           bool,
	waiting_for_reap:       bool,
	cancellation_requested: bool,
	usage:                  Usage,
}

Event :: struct {
	kind:     Event_Kind,
	usage:    Usage,
	deadline: Deadline,
}

initial_session :: proc() -> Session {
	return Session{generation = 1}
}

deadline_ns :: proc(deadline: Deadline) -> i64 {
	switch deadline {
	case .Discovery:
		return DISCOVERY_DEADLINE_NS
	case .Initialization:
		return INITIALIZATION_DEADLINE_NS
	case .Request:
		return REQUEST_DEADLINE_NS
	case .Cancellation:
		return CANCELLATION_DEADLINE_NS
	case .Idle_Step:
		return IDLE_STEP_DEADLINE_NS
	case .Restart_Stability:
		return RESTART_STABILITY_NS
	case .Shutdown:
		return SHUTDOWN_DEADLINE_NS
	case .Forced_Termination:
		return FORCED_TERMINATION_DEADLINE_NS
	}
	return 0
}

step :: proc(session: Session, event: Event) -> (Session, bool, Failure) {
	next := session
	switch event.kind {
	case .Discover:
		if session.health != .Stopped || session.process_live || session.waiting_for_reap {
			return session, false, invalid_transition()
		}
		next.health = .Discovering
	case .Discovery_Succeeded:
		if session.health != .Discovering do return session, false, invalid_transition()
		next.health = .Starting
	case .Spawned:
		if session.health != .Starting do return session, false, invalid_transition()
		next.health = .Initializing
		next.process_live = true
	case .Initialized:
		if session.health != .Initializing || !session.process_live {
			return session, false, invalid_transition()
		}
		next.health = .Active
	case .Account:
		if session.health != .Active do return session, false, invalid_transition()
		if !apply_usage(&next.usage, event.usage) {
			_, failure := usage_sum(session.usage, event.usage)
			return session, false, failure
		}
	case .Release:
		if session.health != .Active && session.health != .Shutting_Down {
			return session, false, invalid_transition()
		}
		if !release_usage(&next.usage, event.usage) {
			return session, false, Failure{code = .Overflow}
		}
	case .Cancel:
		if session.health != .Active || session.cancellation_requested {
			return session, false, invalid_transition()
		}
		next.health = .Cancelling
		next.cancellation_requested = true
	case .Cancellation_Completed:
		if session.health != .Cancelling || !session.cancellation_requested {
			return session, false, invalid_transition()
		}
		next.health = .Active
		next.cancellation_requested = false
	case .Deadline_Expired:
		if session.health == .Stopped || session.health == .Failed {
			return session, false, invalid_transition()
		}
		next.health = .Failed
		return next, true, Failure{code = .Deadline, deadline = event.deadline}
	case .Process_Exited:
		if !session.process_live do return session, false, invalid_transition()
		next.process_live = false
		next.waiting_for_reap = true
		if session.health != .Terminating {
			next.health = .Failed
			return next, true, Failure{code = .Process}
		}
	case .Reaped:
		if !session.waiting_for_reap || session.process_live {
			return session, false, invalid_transition()
		}
		next.waiting_for_reap = false
		if session.health == .Terminating {
			next.health = .Stopped
			next.usage = {}
			next.cancellation_requested = false
		}
	case .Restart:
		if session.health != .Failed || session.process_live || session.waiting_for_reap {
			return session, false, invalid_transition()
		}
		if session.automatic_restarts >= MAX_AUTOMATIC_RESTARTS {
			return session, false, Failure{
				code = .Restart_Exhausted,
				limit = MAX_AUTOMATIC_RESTARTS,
				actual = u64(session.automatic_restarts) + 1,
			}
		}
		if session.generation == max(u64) {
			return session, false, Failure{code = .Overflow}
		}
		next.generation += 1
		next.automatic_restarts += 1
		next.health = .Discovering
		next.usage = {}
		next.cancellation_requested = false
	case .Begin_Shutdown:
		if session.health != .Active do return session, false, invalid_transition()
		next.health = .Shutting_Down
	case .Shutdown_Completed:
		if session.health != .Shutting_Down do return session, false, invalid_transition()
		next.health = .Terminating
	case .Force_Terminate:
		if session.health != .Shutting_Down && session.health != .Failed {
			return session, false, invalid_transition()
		}
		if !session.process_live do return session, false, invalid_transition()
		next.health = .Terminating
	}
	return next, true, {}
}

apply_usage :: proc(usage: ^Usage, delta: Usage) -> bool {
	if usage == nil do return false
	candidate, failure := usage_sum(usage^, delta)
	if failure.code != .None do return false
	usage^ = candidate
	return true
}

usage_sum :: proc(current, delta: Usage) -> (Usage, Failure) {
	candidate: Usage
	if value, ok := add_u32(current.documents, delta.documents); ok {
		candidate.documents = value
	} else do return current, overflow(.Documents)
	if value, ok := add_u32(current.outstanding_requests, delta.outstanding_requests); ok {
		candidate.outstanding_requests = value
	} else do return current, overflow(.Outstanding_Requests)
	if value, ok := add_u32(current.notifications, delta.notifications); ok {
		candidate.notifications = value
	} else do return current, overflow(.Notifications)
	if value, ok := add_u32(current.queue_depth, delta.queue_depth); ok {
		candidate.queue_depth = value
	} else do return current, overflow(.Queue_Depth)
	if value, ok := add_u64(current.queue_bytes, delta.queue_bytes); ok {
		candidate.queue_bytes = value
	} else do return current, overflow(.Queue_Bytes)
	if value, ok := add_u32(current.synchronization_changes, delta.synchronization_changes); ok {
		candidate.synchronization_changes = value
	} else do return current, overflow(.Synchronization_Changes)
	if value, ok := add_u64(current.synchronization_bytes, delta.synchronization_bytes); ok {
		candidate.synchronization_bytes = value
	} else do return current, overflow(.Synchronization_Bytes)
	if value, ok := add_u32(current.diagnostics, delta.diagnostics); ok {
		candidate.diagnostics = value
	} else do return current, overflow(.Diagnostics)
	if value, ok := add_u64(current.diagnostic_bytes, delta.diagnostic_bytes); ok {
		candidate.diagnostic_bytes = value
	} else do return current, overflow(.Diagnostic_Bytes)
	if value, ok := add_u32(current.candidates, delta.candidates); ok {
		candidate.candidates = value
	} else do return current, overflow(.Candidates)
	if value, ok := add_u64(current.candidate_text_bytes, delta.candidate_text_bytes); ok {
		candidate.candidate_text_bytes = value
	} else do return current, overflow(.Candidate_Text_Bytes)
	if value, ok := add_u64(current.standard_error_bytes, delta.standard_error_bytes); ok {
		candidate.standard_error_bytes = value
	} else do return current, overflow(.Standard_Error_Bytes)
	if value, ok := add_u64(current.retained_bytes, delta.retained_bytes); ok {
		candidate.retained_bytes = value
	} else do return current, overflow(.Retained_Bytes)
	if value, ok := add_u64(current.temporary_bytes, delta.temporary_bytes); ok {
		candidate.temporary_bytes = value
	} else do return current, overflow(.Temporary_Bytes)
	if failure := usage_failure(candidate); failure.code != .None do return current, failure
	return candidate, {}
}

release_usage :: proc(usage: ^Usage, released: Usage) -> bool {
	if usage == nil || released.documents > usage.documents ||
	   released.outstanding_requests > usage.outstanding_requests ||
	   released.notifications > usage.notifications ||
	   released.queue_depth > usage.queue_depth ||
	   released.queue_bytes > usage.queue_bytes ||
	   released.synchronization_changes > usage.synchronization_changes ||
	   released.synchronization_bytes > usage.synchronization_bytes ||
	   released.diagnostics > usage.diagnostics ||
	   released.diagnostic_bytes > usage.diagnostic_bytes ||
	   released.candidates > usage.candidates ||
	   released.candidate_text_bytes > usage.candidate_text_bytes ||
	   released.standard_error_bytes > usage.standard_error_bytes ||
	   released.retained_bytes > usage.retained_bytes ||
	   released.temporary_bytes > usage.temporary_bytes {
		return false
	}
	usage.documents -= released.documents
	usage.outstanding_requests -= released.outstanding_requests
	usage.notifications -= released.notifications
	usage.queue_depth -= released.queue_depth
	usage.queue_bytes -= released.queue_bytes
	usage.synchronization_changes -= released.synchronization_changes
	usage.synchronization_bytes -= released.synchronization_bytes
	usage.diagnostics -= released.diagnostics
	usage.diagnostic_bytes -= released.diagnostic_bytes
	usage.candidates -= released.candidates
	usage.candidate_text_bytes -= released.candidate_text_bytes
	usage.standard_error_bytes -= released.standard_error_bytes
	usage.retained_bytes -= released.retained_bytes
	usage.temporary_bytes -= released.temporary_bytes
	return true
}

usage_failure :: proc(usage: Usage) -> Failure {
	if usage.documents > MAX_DOCUMENTS_PER_SESSION do return limit(.Documents, MAX_DOCUMENTS_PER_SESSION, u64(usage.documents))
	if usage.outstanding_requests > MAX_OUTSTANDING_REQUESTS do return limit(.Outstanding_Requests, MAX_OUTSTANDING_REQUESTS, u64(usage.outstanding_requests))
	if usage.notifications > MAX_NOTIFICATIONS do return limit(.Notifications, MAX_NOTIFICATIONS, u64(usage.notifications))
	if usage.queue_depth > MAX_QUEUE_DEPTH do return limit(.Queue_Depth, MAX_QUEUE_DEPTH, u64(usage.queue_depth))
	if usage.queue_bytes > MAX_QUEUE_BYTES do return limit(.Queue_Bytes, MAX_QUEUE_BYTES, usage.queue_bytes)
	if usage.synchronization_changes > MAX_SYNCHRONIZATION_CHANGES do return limit(.Synchronization_Changes, MAX_SYNCHRONIZATION_CHANGES, u64(usage.synchronization_changes))
	if usage.synchronization_bytes > MAX_SYNCHRONIZATION_BYTES do return limit(.Synchronization_Bytes, MAX_SYNCHRONIZATION_BYTES, usage.synchronization_bytes)
	if usage.diagnostics > MAX_DIAGNOSTICS_PER_PROJECT do return limit(.Diagnostics, MAX_DIAGNOSTICS_PER_PROJECT, u64(usage.diagnostics))
	if usage.diagnostic_bytes > MAX_DIAGNOSTIC_BYTES do return limit(.Diagnostic_Bytes, MAX_DIAGNOSTIC_BYTES, usage.diagnostic_bytes)
	if usage.candidates > MAX_CANDIDATES do return limit(.Candidates, MAX_CANDIDATES, u64(usage.candidates))
	if usage.candidate_text_bytes > MAX_CANDIDATE_TEXT_BYTES do return limit(.Candidate_Text_Bytes, MAX_CANDIDATE_TEXT_BYTES, usage.candidate_text_bytes)
	if usage.standard_error_bytes > MAX_STDERR_BYTES do return limit(.Standard_Error_Bytes, MAX_STDERR_BYTES, usage.standard_error_bytes)
	if usage.retained_bytes > MAX_RETAINED_BYTES do return limit(.Retained_Bytes, MAX_RETAINED_BYTES, usage.retained_bytes)
	if usage.temporary_bytes > MAX_TEMPORARY_BYTES do return limit(.Temporary_Bytes, MAX_TEMPORARY_BYTES, usage.temporary_bytes)
	return {}
}

@(private = "file")
add_u32 :: proc(left, right: u32) -> (u32, bool) {
	if right > max(u32) - left do return 0, false
	return left + right, true
}

@(private = "file")
add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left do return 0, false
	return left + right, true
}

@(private = "file")
invalid_transition :: proc() -> Failure {
	return Failure{code = .Invalid_Transition}
}

@(private = "file")
overflow :: proc(resource: Resource) -> Failure {
	return Failure{code = .Overflow, resource = resource}
}

@(private = "file")
limit :: proc(resource: Resource, selected, actual: u64) -> Failure {
	return Failure{
		code = .Resource_Limit,
		resource = resource,
		limit = selected,
		actual = actual,
	}
}
