// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interactive_session

import "base:runtime"
import "core:fmt"

@(private)
Session_State :: struct {
	record:            Session_Record,
	process:           Local_Process,
	limits:            Limits,
	occupied:          bool,
	requested_default: bool,
	input:             [dynamic]u8,
	input_offset:      int,
	output:            [dynamic]u8,
	output_offset:     int,
	cancel_deadline_ns: i64,
	cancel_phase:      u8,
	output_eof:        bool,
}

@(private)
Registry_State :: struct {
	entries:         [MAX_SESSIONS]^Session_State,
	generations:     [MAX_SESSIONS]Session_Generation,
	next_auto_name:  u32,
	default_session: Session_Ref,
	allocator:       runtime.Allocator,
	round_robin_cursor: u8,
}

/* registry_init creates one empty fixed-capacity session owner. */
registry_init :: proc(
	registry: ^Registry,
	allocator := context.allocator,
) -> (bool, Failure_Record) {
	if registry == nil || allocator.procedure == nil {
		return false, failure_record(.Prepare, .Invalid_Argument)
	}
	registry^ = {}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, failure_record(.Prepare, .Allocation)
	}
	state^ = Registry_State{next_auto_name = 1, allocator = allocator}
	registry.state = state
	return true, {}
}

/* registry_prepare reserves one generation without acquiring native resources. */
registry_prepare :: proc(
	registry: ^Registry,
	request: Session_Prepare_Request,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	if !limits_valid(request.limits) {
		return {}, false, failure_record(.Prepare, .Invalid_Argument)
	}
	index := registry_free_index(state)
	if index < 0 {
		return {}, false, failure_record(.Prepare, .Capacity, limit = MAX_SESSIONS, actual = MAX_SESSIONS + 1)
	}

	name := request.name
	name_storage: [MAX_NAME_BYTES]u8
	if len(name) == 0 {
		name, ok = registry_next_name(state, name_storage[:])
		if !ok {
			return {}, false, failure_record(.Prepare, .Capacity)
		}
	} else if registry_name_exists(state, name) {
		return {}, false, failure_record(.Prepare, .Duplicate_Name)
	}

	generation := state.generations[index]
	if generation == Session_Generation(max(u32)) {
		return {}, false, failure_record(.Prepare, .Capacity)
	}
	generation += 1
	ref := Session_Ref{id = Session_ID(index + 1), generation = generation}
	record, ok, failure = prepare_record(
		ref,
		name,
		request.owner_kind,
		request.owner_label,
		request.working_directory,
	)
	if !ok do return
	session, allocation_error := new(Session_State, state.allocator)
	if allocation_error != nil {
		return {}, false, failure_record(.Prepare, .Allocation)
	}
	session^ = Session_State {
		record = record,
		limits = request.limits,
		occupied = true,
		requested_default = request.make_default,
	}
	session.input, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(request.limits.input_bytes, OPERATING_CHUNK_BYTES)),
		state.allocator,
	)
	if allocation_error != nil {
		free(session, state.allocator)
		return {}, false, failure_record(.Prepare, .Allocation)
	}
	session.output, allocation_error = make(
		[dynamic]u8,
		0,
		int(min(request.limits.output_bytes, OPERATING_CHUNK_BYTES)),
		state.allocator,
	)
	if allocation_error != nil {
		delete(session.input)
		free(session, state.allocator)
		return {}, false, failure_record(.Prepare, .Allocation)
	}
	state.generations[index] = generation
	state.entries[index] = session
	return record, true, {}
}

/* registry_start acquires and publishes one prepared PTY process. */
registry_start :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	request: Process_Start_Request,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Start)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Start, code)
	}
	if session.record.lifecycle != .Prepared {
		return session.record, false, failure_record(.Start, .Invalid_Transition)
	}
	if request.working_directory != working_context_view(&session.record.working_context) ||
	   request.columns > session.limits.columns || request.rows > session.limits.rows {
		return session.record, false, failure_record(.Start, .Invalid_Argument)
	}
	started_transition, transition_failure := transition(&session.record, .Starting)
	if !started_transition {
		return session.record, false, transition_failure
	}
	process, started, process_failure := local_process_start(request)
	if !started {
		_ = record_failure(&session.record, process_failure)
		return session.record, false, process_failure
	}
	session.process = process
	info, inspected := local_process_inspect(&session.process)
	if !inspected {
		_, _ = local_process_close(&session.process)
		failure = failure_record(.Start, .Cleanup)
		_ = record_failure(&session.record, failure)
		return session.record, false, failure
	}
	running: bool
	running, transition_failure = transition(&session.record, .Running)
	if !running {
		_, _ = local_process_close(&session.process)
		_ = record_failure(&session.record, transition_failure)
		return session.record, false, transition_failure
	}
	session.record.resources.process_id = info.process_id
	session.record.resources.process_group_id = info.process_group_id
	session.record.resources.open_descriptors = info.open_descriptors
	if session.requested_default || !registry_default_is_running(state) {
		registry_assign_default(state, session)
	}
	return session.record, true, {}
}

/* registry_resize applies one checked PTY geometry to a running session. */
registry_resize :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	columns, rows: u16,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Resize)
	session, resolved, code := registry_resolve(state, ref)
	if !resolved do return false, failure_record(.Resize, code)
	if session.record.lifecycle != .Running || columns == 0 || rows == 0 ||
	   columns > session.limits.columns || rows > session.limits.rows {
		return false, failure_record(.Resize, .Invalid_Argument)
	}
	resized, resize_failure := local_process_resize(&session.process, columns, rows)
	if !resized do _ = record_failure(&session.record, resize_failure)
	return resized, resize_failure
}

/* registry_start_shell prepares and starts one interactive user shell. */
registry_start_shell :: proc(
	registry: ^Registry,
	request: Session_Prepare_Request,
) -> (Session_Record, bool, Failure_Record) {
	record, prepared, failure := registry_prepare(registry, request)
	if !prepared do return record, false, failure
	shell_path, shell_ok, shell_failure := user_shell()
	if !shell_ok {
		_, _ = registry_close_session(registry, record.ref)
		return {}, false, shell_failure
	}
	arguments := []string{"-i"}
	return registry_start(
		registry,
		record.ref,
		Process_Start_Request {
			executable = working_context_view(&shell_path),
			arguments = arguments,
			working_directory = request.working_directory,
			columns = request.limits.columns,
			rows = request.limits.rows,
		},
	)
}

/* registry_record copies one exact session generation. */
registry_record :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Prepare, code)
	}
	return session.record, true, {}
}

/* registry_session_at copies one occupied entry in stable slot order. */
registry_session_at :: proc(
	registry: ^Registry,
	index: u16,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	remaining := index
	for session in state.entries {
		if session == nil || !session.occupied do continue
		if remaining == 0 do return session.record, true, {}
		remaining -= 1
	}
	return {}, false, failure_record(.Prepare, .Stale_Reference)
}

/* registry_rename replaces one name while preserving session identity. */
registry_rename :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	name: string,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Prepare, code)
	}
	if !session_name_valid(name) {
		return session.record, false, failure_record(.Prepare, .Invalid_Argument)
	}
	for candidate in state.entries {
		if candidate != nil && candidate.occupied && candidate != session &&
		   session_name_view(&candidate.record.name) == name {
			return session.record, false, failure_record(.Prepare, .Duplicate_Name)
		}
	}
	session.record.name = {}
	session.record.name.length = u8(copy(session.record.name.bytes[:], transmute([]u8)name))
	return session.record, true, {}
}

/* registry_set_default assigns the Workspace or instance default role. */
registry_set_default :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Prepare, code)
	}
	if session.record.lifecycle != .Running {
		return session.record, false, failure_record(.Prepare, .Invalid_Transition)
	}
	registry_assign_default(state, session)
	return session.record, true, {}
}

/* registry_default copies the current running default session. */
registry_default :: proc(
	registry: ^Registry,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	session, resolved, _ := registry_resolve(state, state.default_session)
	if !resolved || session.record.lifecycle != .Running {
		return {}, false, failure_record(.Prepare, .Stale_Reference)
	}
	return session.record, true, {}
}

/* registry_poll collects exit state and replaces an exited default. */
registry_poll :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Poll)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Poll, code)
	}
	if session.record.lifecycle != .Running {
		return session.record, true, {}
	}
	poll, polled, poll_failure := local_process_poll(&session.process)
	if !polled {
		_ = record_failure(&session.record, poll_failure)
		return session.record, false, poll_failure
	}
	if poll.exited {
		_, exit_failure := record_exit(&session.record, poll.exit_status)
		if exit_failure.code != .None {
			_ = record_failure(&session.record, exit_failure)
			return session.record, false, exit_failure
		}
		session.record.resources.open_descriptors = 1
		if state.default_session == ref {
			registry_replace_default(state)
		}
	}
	return session.record, true, {}
}

/* registry_inspect returns aggregate immutable session accounting. */
registry_inspect :: proc(
	registry: ^Registry,
) -> (stats: Registry_Stats, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Prepare)
	}
	stats.default_session = state.default_session
	for session in state.entries {
		if session == nil || !session.occupied do continue
		stats.session_count += 1
		switch session.record.lifecycle {
		case .Starting, .Running, .Closing:
			stats.operating_count += 1
		case .Exited:
			stats.exited_count += 1
		case .Failed:
			stats.failed_count += 1
		case .Invalid, .Prepared, .Closed:
		}
		stats.open_descriptors += u16(session.record.resources.open_descriptors)
		stats.queued_input_bytes += session.record.resources.queued_input_bytes
		stats.queued_output_bytes += session.record.resources.queued_output_bytes
		stats.total_input_bytes += session.record.resources.total_input_bytes
		stats.total_output_bytes += session.record.resources.total_output_bytes
	}
	return stats, true, {}
}

/* registry_close_session releases one exact generation and invalidates its ref. */
registry_close_session :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	session, resolved, code := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Close, code)
	}
	first_failure: Failure_Record
	if session.process.state != nil {
		closed, close_failure := local_process_close(&session.process)
		if !closed do first_failure = close_failure
	}
	if session.record.lifecycle != .Closing {
		closing, transition_failure := transition(&session.record, .Closing)
		if !closing && first_failure.code == .None do first_failure = transition_failure
	}
	if session.record.lifecycle == .Closing {
		closed, transition_failure := transition(&session.record, .Closed)
		if !closed && first_failure.code == .None do first_failure = transition_failure
	}
	was_default := state.default_session == ref
	index := int(u32(ref.id) - 1)
	if session.input != nil do delete(session.input)
	if session.output != nil do delete(session.output)
	free(session, state.allocator)
	state.entries[index] = nil
	if was_default do registry_replace_default(state)
	return first_failure.code == .None, first_failure
}

/* registry_close releases every process and the registry exactly once. */
registry_close :: proc(registry: ^Registry) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	first_failure: Failure_Record
	for session in state.entries {
		if session == nil || !session.occupied do continue
		ref := session.record.ref
		closed, close_failure := registry_close_session(registry, ref)
		if !closed && first_failure.code == .None do first_failure = close_failure
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Registry{closed = true}
	return first_failure.code == .None, first_failure
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return cast(^Registry_State)registry.state
}

@(private)
registry_access_failure :: proc(registry: ^Registry, stage: Failure_Stage) -> Failure_Record {
	if registry != nil && registry.closed do return failure_record(stage, .Cleanup)
	return failure_record(stage, .Invalid_Argument)
}

@(private)
registry_free_index :: proc(state: ^Registry_State) -> int {
	for session, index in state.entries {
		if session == nil do return index
	}
	return -1
}

@(private)
registry_resolve :: proc(
	state: ^Registry_State,
	ref: Session_Ref,
) -> (session: ^Session_State, ok: bool, code: Failure_Code) {
	if ref.id == Session_ID(0) || ref.generation == Session_Generation(0) ||
	   u32(ref.id) > MAX_SESSIONS {
		return nil, false, .Stale_Reference
	}
	index := int(u32(ref.id) - 1)
	session = state.entries[index]
	if state.generations[index] != ref.generation || session == nil || !session.occupied ||
	   session.record.ref != ref {
		return nil, false, .Stale_Reference
	}
	return session, true, .None
}

@(private)
registry_name_exists :: proc(state: ^Registry_State, name: string) -> bool {
	for session in state.entries {
		if session != nil && session.occupied &&
		   session_name_view(&session.record.name) == name {
			return true
		}
	}
	return false
}

@(private)
registry_next_name :: proc(state: ^Registry_State, storage: []u8) -> (string, bool) {
	for _ in 0 ..< MAX_SESSIONS + 1 {
		if state.next_auto_name == 0 do return "", false
		candidate := "terminal"
		if state.next_auto_name > 1 {
			candidate = fmt.bprintf(storage, "terminal-%d", state.next_auto_name)
		}
		state.next_auto_name += 1
		if !registry_name_exists(state, candidate) do return candidate, true
	}
	return "", false
}

@(private)
registry_assign_default :: proc(state: ^Registry_State, session: ^Session_State) {
	for candidate in state.entries {
		if candidate != nil do candidate.record.default_session = false
	}
	state.default_session = session.record.ref
	session.record.default_session = true
}

@(private)
registry_replace_default :: proc(state: ^Registry_State) {
	state.default_session = {}
	for candidate in state.entries {
		if candidate == nil do continue
		candidate.record.default_session = false
		if state.default_session.id == Session_ID(0) && candidate.occupied &&
		   candidate.record.lifecycle == .Running {
			state.default_session = candidate.record.ref
			candidate.record.default_session = true
		}
	}
}

@(private)
registry_default_is_running :: proc(state: ^Registry_State) -> bool {
	session, ok, _ := registry_resolve(state, state.default_session)
	return ok && session.record.lifecycle == .Running
}
