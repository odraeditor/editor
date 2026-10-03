// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "base:runtime"
import "../interactive_session"
import "../terminal_emulator"

@(private)
Session_State :: struct {
	record:                    Session_Record,
	limits:                    Limits,
	process_input_bytes:       u64,
	process_output_turn_bytes: u64,
	process_output_turn_nanoseconds: i64,
	observed_effects:          terminal_emulator.Effects,
	last_admitted_bell_ns:     i64,
	bell_admitted_once:        bool,
	title:                     [MAX_METADATA_BYTES]u8,
	title_length:              u16,
	working_context:           [MAX_METADATA_BYTES]u8,
	working_context_length:    u16,
	images:                    [MAX_IMAGE_PLACEMENTS]Image_Placement,
	image_projection:          terminal_emulator.Image_Projection,
	projection:                terminal_emulator.Projection,
	projected_rows:            [dynamic]Render_Row,
	projected_cells:           [dynamic]Render_Cell,
	columns:                   u16,
	rows:                      u16,
	cell_width_pixels:         u32,
	cell_height_pixels:        u32,
	occupied:                  bool,
	semantic:                  Semantic_State,
	events:                    [dynamic]Event_Record,
	event_bytes:               u64,
	next_event_sequence:       u64,
	exit_event_published:      bool,
}

@(private)
Subscription_State :: struct {
	record:       Subscription_Record,
	sessions:     [MAX_SESSIONS]Session_Ref,
	cursors:      [MAX_SESSIONS]u64,
	kinds:        Event_Kind_Set,
	raw_output:   bool,
	occupied:     bool,
}

@(private)
Registry_State :: struct {
	interactive:       interactive_session.Registry,
	entries:           [MAX_SESSIONS]^Session_State,
	generations:       [MAX_SESSIONS]Session_Generation,
	allocator:         runtime.Allocator,
	round_robin_cursor: u8,
	subscriptions:      [MAX_SUBSCRIBERS]Subscription_State,
	subscription_generations: [MAX_SUBSCRIBERS]Subscription_Generation,
	subscriber_count:   u16,
	event_entries:      u64,
	event_bytes:        u64,
	next_subscription_cursor: u8,
	event_limits:       Event_Limits,
}

/* registry_init creates one empty composed terminal-session owner. */
registry_init :: proc(
	registry: ^Registry,
	allocator := context.allocator,
) -> (bool, Failure_Record) {
	if registry == nil || allocator.procedure == nil {
		return false, failure_record(.Initialize, .Invalid_Argument)
	}
	registry^ = {}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, failure_record(.Initialize, .Allocation)
	}
	state^ = Registry_State{allocator = allocator, event_limits = DEFAULT_EVENT_LIMITS}
	interactive_ok, interactive_failure := interactive_session.registry_init(
		&state.interactive,
		allocator,
	)
	if !interactive_ok {
		free(state, allocator)
		return false, process_failure(.Initialize, interactive_failure)
	}
	registry.state = state
	return true, {}
}

/* registry_open atomically acquires one process and one terminal emulator. */
registry_open :: proc(
	registry: ^Registry,
	request: Open_Request,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Open)
	}
	if !limits_valid(request.limits) || !terminal_geometry_valid(
		request.emulator.columns, request.emulator.rows,
	) ||
	   request.emulator.rows == 0 || request.start.columns != request.emulator.columns ||
	   request.start.rows != request.emulator.rows {
		return {}, false, failure_record(.Open, .Invalid_Argument)
	}
	index := registry_free_index(state)
	if index < 0 {
		return {}, false, failure_record(.Open, .Capacity, limit = MAX_SESSIONS, actual = MAX_SESSIONS + 1)
	}
	session, allocation_error := new(Session_State, state.allocator)
	if allocation_error != nil {
		return {}, false, failure_record(.Open, .Allocation)
	}
	session.projected_rows, allocation_error = make([dynamic]Render_Row, 0, 0, state.allocator)
	if allocation_error != nil {
		free(session, state.allocator)
		return {}, false, failure_record(.Open, .Allocation)
	}
	session.projected_cells, allocation_error = make([dynamic]Render_Cell, 0, 0, state.allocator)
	if allocation_error != nil {
		delete(session.projected_rows)
		free(session, state.allocator)
		return {}, false, failure_record(.Open, .Allocation)
	}
	session.events, allocation_error = make([dynamic]Event_Record, 0, 0, state.allocator)
	if allocation_error != nil {
		delete(session.projected_cells)
		delete(session.projected_rows)
		free(session, state.allocator)
		return {}, false, failure_record(.Open, .Allocation)
	}

	process_record, prepared, process_issue := interactive_session.registry_prepare(
		&state.interactive,
		request.process,
	)
	if !prepared {
		delete(session.events)
		delete(session.projected_cells)
		delete(session.projected_rows)
		free(session, state.allocator)
		return {}, false, process_failure(.Open, process_issue)
	}
	emulator_options := request.emulator
	emulator_options.scrollback_max_bytes = request.limits.scrollback_bytes
	emulator_options.scrollback_max_lines = request.limits.scrollback_rows
	emulator_ref, emulator_result := terminal_emulator.open(emulator_options)
	if emulator_result != .OK {
		_, _ = interactive_session.registry_close_session(&state.interactive, process_record.ref)
		delete(session.events)
		delete(session.projected_cells)
		delete(session.projected_rows)
		free(session, state.allocator)
		return {}, false, emulator_failure(.Open, emulator_result)
	}
	started: bool
	process_record, started, process_issue = interactive_session.registry_start(
		&state.interactive,
		process_record.ref,
		request.start,
	)
	if !started {
		_ = terminal_emulator.close(emulator_ref)
		_, _ = interactive_session.registry_close_session(&state.interactive, process_record.ref)
		delete(session.events)
		delete(session.projected_cells)
		delete(session.projected_rows)
		free(session, state.allocator)
		return {}, false, process_failure(.Open, process_issue)
	}

	generation := state.generations[index] + 1
	if generation == Session_Generation(0) do generation = 1
	session^ = Session_State {
		record = Session_Record {
			ref = Session_Ref{id = Session_ID(index + 1), generation = generation},
			lifecycle = .Running,
			process = process_record,
			emulator = emulator_ref,
		},
		limits = request.limits,
		process_input_bytes = request.process.limits.input_bytes,
		process_output_turn_bytes = request.process.limits.output_turn_bytes,
		process_output_turn_nanoseconds = request.process.limits.output_turn_nanoseconds,
		columns = request.emulator.columns,
		rows = request.emulator.rows,
		cell_width_pixels = request.emulator.cell_width_pixels,
		cell_height_pixels = request.emulator.cell_height_pixels,
		occupied = true,
		next_event_sequence = 1,
	}
	session.record.effects.policy = DEFAULT_EFFECT_POLICY
	terminal_effect_initialize_working_context(
		session,
		string(process_record.working_context.directory[:process_record.working_context.length]),
	)
	state.generations[index] = generation
	state.entries[index] = session
	return session.record, true, {}
}

/* registry_record copies one exact composed session generation. */
registry_record :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Process)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Process, .Stale_Reference)
	}
	return session.record, true, {}
}

/* registry_poll synchronizes copied process lifecycle with composed ownership. */
registry_poll :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (record: Session_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Process)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Process, .Stale_Reference)
	}
	process_record, polled, process_issue := interactive_session.registry_poll(
		&state.interactive,
		session.record.process.ref,
	)
	if !polled {
		failure = process_failure(.Process, process_issue)
		session.record.lifecycle = .Failed
		session.record.failure = failure
		return session.record, false, failure
	}
	session.record.process = process_record
	if process_record.lifecycle == .Exited do session.record.lifecycle = .Exited
	if process_record.lifecycle == .Failed {
		failure = process_failure(.Process, process_record.failure)
		session.record.lifecycle = .Failed
		session.record.failure = failure
		return session.record, false, failure
	}
	return session.record, true, {}
}

/* registry_inspect returns immutable aggregate terminal-session accounting. */
registry_inspect :: proc(
	registry: ^Registry,
) -> (stats: Registry_Stats, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Process)
	}
	for session in state.entries {
		if session == nil || !session.occupied do continue
		stats.session_count += 1
		switch session.record.lifecycle {
		case .Running: stats.running_count += 1
		case .Exited:  stats.exited_count += 1
		case .Failed:  stats.failed_count += 1
		case .Invalid, .Closed:
		}
		stats.output_bytes += session.record.output_bytes
		stats.writeback_bytes += session.record.writeback_bytes
		stats.retained_bytes += session.record.retained_bytes
		stats.projection_bytes += session.record.projection_bytes
	}
	return stats, true, {}
}

/* registry_close_session releases emulator and process ownership exactly once. */
registry_close_session :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return false, failure_record(.Close, .Stale_Reference)
	}
	first_failure: Failure_Record
	if result := terminal_emulator.close(session.record.emulator); result != .OK {
		first_failure = emulator_failure(.Close, result)
	}
	if closed, process_issue := interactive_session.registry_close_session(
		&state.interactive,
		session.record.process.ref,
	); !closed && first_failure.code == .None {
		first_failure = process_failure(.Close, process_issue)
	}
	index := int(u32(ref.id) - 1)
	session.record.lifecycle = .Closed
	registry_event_session_close(state, ref)
	delete(session.events)
	delete(session.projected_cells)
	delete(session.projected_rows)
	free(session, state.allocator)
	state.entries[index] = nil
	return first_failure.code == .None, first_failure
}

/* registry_close releases all composed sessions and subordinate ownership. */
registry_close :: proc(registry: ^Registry) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_access_failure(registry, .Close)
	}
	first_failure: Failure_Record
	for session in state.entries {
		if session == nil || !session.occupied do continue
		closed, close_issue := registry_close_session(registry, session.record.ref)
		if !closed && first_failure.code == .None do first_failure = close_issue
	}
	if state.interactive.state != nil {
		closed, process_issue := interactive_session.registry_close(&state.interactive)
		if !closed && first_failure.code == .None {
			first_failure = process_failure(.Close, process_issue)
		}
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
registry_free_index :: proc(state: ^Registry_State) -> int {
	for session, index in state.entries {
		if session == nil do return index
	}
	return -1
}

@(private)
registry_resolve :: proc(state: ^Registry_State, ref: Session_Ref) -> (^Session_State, bool) {
	if ref.id == Session_ID(0) || ref.generation == Session_Generation(0) ||
	   u32(ref.id) > MAX_SESSIONS {
		return nil, false
	}
	index := int(u32(ref.id) - 1)
	session := state.entries[index]
	if session == nil || !session.occupied || state.generations[index] != ref.generation ||
	   session.record.ref != ref {
		return nil, false
	}
	return session, true
}

@(private)
limits_valid :: proc(limits: Limits) -> bool {
	return limits.output_turn_bytes > 0 && limits.output_turn_bytes <= MAX_OUTPUT_TURN_BYTES &&
		limits.output_turn_nanoseconds > 0 &&
		limits.output_turn_nanoseconds <= MAX_OUTPUT_TURN_NANOSECONDS &&
		limits.scrollback_bytes > 0 && limits.scrollback_bytes <= MAX_SCROLLBACK_BYTES &&
		limits.scrollback_rows > 0 && limits.scrollback_rows <= MAX_SCROLLBACK_ROWS &&
		limits.state_bytes >= limits.scrollback_bytes && limits.state_bytes <= MAX_STATE_BYTES &&
		limits.copied_text_bytes > 0 && limits.copied_text_bytes <= MAX_COPIED_TEXT_BYTES
}

@(private)
terminal_geometry_valid :: proc(columns, rows: u16) -> bool {
	return columns > 0 && rows > 0 && columns <= MAX_TERMINAL_COLUMNS &&
		rows <= MAX_TERMINAL_ROWS && u64(columns) * u64(rows) <= MAX_PROJECTED_CELLS
}

@(private)
failure_record :: proc(
	stage: Failure_Stage,
	code: Failure_Code,
	limit: u64 = 0,
	actual: u64 = 0,
) -> Failure_Record {
	return Failure_Record{stage = stage, code = code, limit = limit, actual = actual}
}

@(private)
process_failure :: proc(
	stage: Failure_Stage,
	issue: interactive_session.Failure_Record,
) -> Failure_Record {
	return Failure_Record {
		stage = stage,
		code = .Process,
		process_code = issue.code,
		limit = issue.limit,
		actual = issue.actual,
	}
}

@(private)
emulator_failure :: proc(
	stage: Failure_Stage,
	result: terminal_emulator.Result,
) -> Failure_Record {
	return Failure_Record{stage = stage, code = .Emulator, emulator_result = result}
}

@(private)
registry_access_failure :: proc(registry: ^Registry, stage: Failure_Stage) -> Failure_Record {
	if registry != nil && registry.closed do return failure_record(stage, .Cleanup)
	return failure_record(stage, .Invalid_Argument)
}
