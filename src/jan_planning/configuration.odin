// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"

@(private)
Configuration_State :: struct {
	descriptor: Configuration_Descriptor,
	workflows:  []Workflow_Record,
	states:     []Workflow_State_Record,
	source_sets: []Source_Set_Record,
	sources:    []Source_Record,
	captures:   []Capture_Record,
	agendas:    []Agenda_Record,
	arena:      []u8,
	allocator:  runtime.Allocator,
}

/* planning_configuration_init installs one immutable factory fallback generation. */
planning_configuration_init :: proc(
	configuration: ^Configuration,
	generation: Configuration_Generation,
	provider_generation: Provider_Generation,
	allocator := context.allocator,
) -> (bool, Failure) {
	if configuration == nil || configuration.state != nil ||
	   generation == Configuration_Generation(0) ||
	   provider_generation == Provider_Generation(0) || allocator.procedure == nil {
		return false, planning_failure(.Configure, .Invalid_Request, .Generation)
	}
	state, allocation_error := new(Configuration_State, allocator)
	if allocation_error != nil {
		return false, planning_failure(.Configure, .Allocation_Failed, .Generation)
	}
	state^ = Configuration_State {
		descriptor = {
			generation = generation,
			provider_generation = provider_generation,
			factory_fallback = true,
		},
		allocator = allocator,
	}
	configuration.state = state
	return true, {}
}

/* planning_configuration_publish validates and swaps one complete copied generation. */
planning_configuration_publish :: proc(
	configuration: ^Configuration,
	candidate: Configuration_Candidate,
) -> (descriptor: Configuration_Descriptor, ok: bool, failure: Failure) {
	current := planning_configuration_state(configuration)
	if current == nil {
		return {}, false, planning_failure(.Configure, .Invalid_Request, .Generation)
	}
	if candidate.generation <= current.descriptor.generation ||
	   candidate.provider_generation == Provider_Generation(0) {
		return current.descriptor, false, planning_failure(.Configure, .Stale, .Generation)
	}
	valid, text_bytes, state_count, source_count, invalid_failure := planning_configuration_candidate_validate(candidate)
	if !valid do return current.descriptor, false, invalid_failure
	next, copied := planning_configuration_copy(
		candidate,
		text_bytes,
		state_count,
		source_count,
		current.allocator,
	)
	if !copied {
		return current.descriptor, false, planning_failure(.Configure, .Allocation_Failed, .Generation)
	}
	configuration.state = next
	planning_configuration_state_destroy(current)
	return next.descriptor, true, {}
}

/* planning_configuration_inspect copies current generation metadata. */
planning_configuration_inspect :: proc(configuration: ^Configuration) -> (Configuration_Descriptor, bool) {
	state := planning_configuration_state(configuration)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* planning_configuration_workflow borrows one confirmed workflow until replacement. */
planning_configuration_workflow :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Workflow_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.workflows) do return {}, false
	return state.workflows[index], true
}

/* planning_configuration_workflow_state borrows one confirmed state until replacement. */
planning_configuration_workflow_state :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Workflow_State_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.states) do return {}, false
	return state.states[index], true
}

/* planning_configuration_source_set borrows one confirmed source set until replacement. */
planning_configuration_source_set :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Source_Set_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.source_sets) do return {}, false
	return state.source_sets[index], true
}

/* planning_configuration_source borrows one confirmed source until replacement. */
planning_configuration_source :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Source_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.sources) do return {}, false
	return state.sources[index], true
}

/* planning_configuration_capture borrows one confirmed capture until replacement. */
planning_configuration_capture :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Capture_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.captures) do return {}, false
	return state.captures[index], true
}

/* planning_configuration_agenda borrows one confirmed agenda until replacement. */
planning_configuration_agenda :: proc(
	configuration: ^Configuration,
	index: int,
) -> (Agenda_Record, bool) {
	state := planning_configuration_state(configuration)
	if state == nil || index < 0 || index >= len(state.agendas) do return {}, false
	return state.agendas[index], true
}

/* planning_configuration_close releases every copied configured value exactly. */
planning_configuration_close :: proc(configuration: ^Configuration) {
	if configuration == nil do return
	state := planning_configuration_state(configuration)
	if state != nil do planning_configuration_state_destroy(state)
	configuration.state = nil
}

@(private)
planning_configuration_candidate_validate :: proc(
	candidate: Configuration_Candidate,
) -> (valid: bool, text_bytes: u64, state_count: int, source_count: int, failure: Failure) {
	if candidate.generation == Configuration_Generation(0) ||
	   candidate.provider_generation == Provider_Generation(0) || len(candidate.workflows) == 0 {
		return false, 0, 0, 0, planning_failure(.Configure, .Malformed, .Generation)
	}
	if len(candidate.workflows) > int(MAX_WORKFLOWS) ||
	   len(candidate.source_sets) > int(MAX_SOURCE_SETS) ||
	   len(candidate.captures) > int(MAX_CAPTURE_DEFINITIONS) ||
	   len(candidate.agendas) > int(MAX_AGENDA_DEFINITIONS) {
		return false, 0, 0, 0, planning_failure(.Configure, .Limited, .Limit)
	}
	for workflow, workflow_index in candidate.workflows {
		if !configuration_text_is_valid(workflow.identity, MAX_IDENTITY_BYTES) || len(workflow.states) == 0 {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Workflow)
		}
		for prior in candidate.workflows[:workflow_index] do if prior.identity == workflow.identity {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Workflow)
		}
		text_bytes += u64(len(workflow.identity))
		unfinished, finished := false, false
		for state, state_index in workflow.states {
			if !configuration_text_is_valid(state.name, MAX_IDENTITY_BYTES) ||
			   state.presentation == .Invalid || state.log == .Invalid {
				return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Workflow)
			}
			for prior in workflow.states[:state_index] do if prior.name == state.name {
				return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Workflow)
			}
			text_bytes += u64(len(state.name))
			state_count += 1
			if state.finished do finished = true
			if !state.finished do unfinished = true
		}
		if !unfinished || !finished {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Workflow)
		}
	}
	if state_count > int(MAX_WORKFLOW_STATES) {
		failure = planning_failure(.Configure, .Limited, .Workflow)
		failure.limit = u64(MAX_WORKFLOW_STATES)
		failure.actual = u64(state_count)
		return false, text_bytes, state_count, source_count, failure
	}
	for source_set, set_index in candidate.source_sets {
		if !configuration_text_is_valid(source_set.identity, MAX_IDENTITY_BYTES) {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Source_Set)
		}
		for prior in candidate.source_sets[:set_index] do if prior.identity == source_set.identity {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Source_Set)
		}
		text_bytes += u64(len(source_set.identity))
		for source, source_index in source_set.sources {
			if !configuration_text_is_valid(source.identity, MAX_IDENTITY_BYTES) ||
			   !configuration_text_is_valid(source.resource, MAX_RESOURCE_BYTES) ||
			   source.kind == .Invalid || source.discovery_depth > 64 ||
			   source.document_limit == 0 || source.document_limit > MAX_SOURCE_DOCUMENTS {
				return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Source_Set)
			}
			for prior in source_set.sources[:source_index] do if prior.identity == source.identity {
				return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Source_Set)
			}
			text_bytes += u64(len(source.identity) + len(source.resource))
			source_count += 1
		}
	}
	if source_count > int(MAX_SOURCE_DOCUMENTS) {
		failure = planning_failure(.Configure, .Limited, .Source_Set)
		failure.limit = u64(MAX_SOURCE_DOCUMENTS)
		failure.actual = u64(source_count)
		return false, text_bytes, state_count, source_count, failure
	}
	for capture, capture_index in candidate.captures {
		if capture.key == rune(0) || capture.entry_kind == .Invalid ||
		   !configuration_text_is_valid(capture.label, MAX_LABEL_BYTES) ||
		   !configuration_text_is_valid(capture.target, MAX_RESOURCE_BYTES) ||
		   !configuration_text_is_valid(capture.template, MAX_TEMPLATE_BYTES) {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Capture)
		}
		for prior in candidate.captures[:capture_index] do if prior.key == capture.key {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Capture)
		}
		text_bytes += u64(len(capture.label) + len(capture.target) + len(capture.template))
	}
	for agenda, agenda_index in candidate.agendas {
		if agenda.key == rune(0) || agenda.span == .Invalid ||
		   agenda.result_limit == 0 || agenda.result_limit > MAX_AGENDA_ENTRIES ||
		   !configuration_text_is_valid(agenda.label, MAX_LABEL_BYTES) ||
		   !configuration_text_is_valid(agenda.query, MAX_QUERY_BYTES) {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Malformed, .Agenda)
		}
		for prior in candidate.agendas[:agenda_index] do if prior.key == agenda.key {
			return false, text_bytes, state_count, source_count, planning_failure(.Configure, .Conflict, .Agenda)
		}
		text_bytes += u64(len(agenda.label) + len(agenda.query))
	}
	if text_bytes > MAX_CONFIGURATION_BYTES {
		failure = planning_failure(.Configure, .Limited, .Limit)
		failure.limit = MAX_CONFIGURATION_BYTES
		failure.actual = text_bytes
		return false, text_bytes, state_count, source_count, failure
	}
	return true, text_bytes, state_count, source_count, {}
}

@(private)
planning_configuration_copy :: proc(
	candidate: Configuration_Candidate,
	text_bytes: u64,
	state_count, source_count: int,
	allocator: runtime.Allocator,
) -> (state: ^Configuration_State, ok: bool) {
	allocation_error: runtime.Allocator_Error
	state, allocation_error = new(Configuration_State, allocator)
	if allocation_error != nil do return nil, false
	state^ = Configuration_State{allocator = allocator}
	state.workflows, allocation_error = make([]Workflow_Record, len(candidate.workflows), allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.states, allocation_error = make([]Workflow_State_Record, state_count, allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.source_sets, allocation_error = make([]Source_Set_Record, len(candidate.source_sets), allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.sources, allocation_error = make([]Source_Record, source_count, allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.captures, allocation_error = make([]Capture_Record, len(candidate.captures), allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.agendas, allocation_error = make([]Agenda_Record, len(candidate.agendas), allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	state.arena, allocation_error = make([]u8, int(text_bytes), allocator)
	if allocation_error != nil do return planning_configuration_copy_failed(state)
	cursor, state_index, source_index := 0, 0, 0
	for workflow, workflow_index in candidate.workflows {
		state.workflows[workflow_index] = {
			identity = planning_configuration_arena_copy(state.arena, &cursor, workflow.identity),
			states = {start = u16(state_index), count = u16(len(workflow.states))},
		}
		for candidate_state in workflow.states {
			state.states[state_index] = {
				name = planning_configuration_arena_copy(state.arena, &cursor, candidate_state.name),
				finished = candidate_state.finished,
				fast_key = candidate_state.fast_key,
				presentation = candidate_state.presentation,
				log = candidate_state.log,
			}
			state_index += 1
		}
	}
	for source_set, set_index in candidate.source_sets {
		state.source_sets[set_index] = {
			identity = planning_configuration_arena_copy(state.arena, &cursor, source_set.identity),
			sources = {start = u16(source_index), count = u16(len(source_set.sources))},
		}
		for source in source_set.sources {
			state.sources[source_index] = {
				identity = planning_configuration_arena_copy(state.arena, &cursor, source.identity),
				kind = source.kind,
				resource = planning_configuration_arena_copy(state.arena, &cursor, source.resource),
				discovery_depth = source.discovery_depth,
				document_limit = source.document_limit,
			}
			source_index += 1
		}
	}
	for capture, index in candidate.captures {
		state.captures[index] = {
			key = capture.key,
			label = planning_configuration_arena_copy(state.arena, &cursor, capture.label),
			entry_kind = capture.entry_kind,
			target = planning_configuration_arena_copy(state.arena, &cursor, capture.target),
			template = planning_configuration_arena_copy(state.arena, &cursor, capture.template),
			immediate_finish = capture.immediate_finish,
		}
	}
	for agenda, index in candidate.agendas {
		state.agendas[index] = {
			key = agenda.key,
			label = planning_configuration_arena_copy(state.arena, &cursor, agenda.label),
			query = planning_configuration_arena_copy(state.arena, &cursor, agenda.query),
			span = agenda.span,
			result_limit = agenda.result_limit,
		}
	}
	assert(cursor == len(state.arena))
	retained_bytes := text_bytes + u64(size_of(Configuration_State)) +
	                  u64(len(state.workflows) * size_of(Workflow_Record)) +
	                  u64(len(state.states) * size_of(Workflow_State_Record)) +
	                  u64(len(state.source_sets) * size_of(Source_Set_Record)) +
	                  u64(len(state.sources) * size_of(Source_Record)) +
	                  u64(len(state.captures) * size_of(Capture_Record)) +
	                  u64(len(state.agendas) * size_of(Agenda_Record))
	state.descriptor = {
		generation = candidate.generation,
		provider_generation = candidate.provider_generation,
		workflow_count = u16(len(state.workflows)),
		workflow_states = u16(len(state.states)),
		source_set_count = u16(len(state.source_sets)),
		source_count = u16(len(state.sources)),
		capture_count = u16(len(state.captures)),
		agenda_count = u16(len(state.agendas)),
		retained_bytes = retained_bytes,
	}
	return state, true
}

@(private)
planning_configuration_arena_copy :: proc(arena: []u8, cursor: ^int, value: string) -> string {
	start := cursor^
	cursor^ += copy(arena[start:], value)
	return string(arena[start:cursor^])
}

@(private)
planning_configuration_copy_failed :: proc(state: ^Configuration_State) -> (^Configuration_State, bool) {
	planning_configuration_state_destroy(state)
	return nil, false
}

@(private)
planning_configuration_state :: proc(configuration: ^Configuration) -> ^Configuration_State {
	if configuration == nil || configuration.state == nil do return nil
	return (^Configuration_State)(configuration.state)
}

@(private)
planning_configuration_state_destroy :: proc(state: ^Configuration_State) {
	if state == nil do return
	allocator := state.allocator
	if state.workflows != nil do delete(state.workflows, allocator)
	if state.states != nil do delete(state.states, allocator)
	if state.source_sets != nil do delete(state.source_sets, allocator)
	if state.sources != nil do delete(state.sources, allocator)
	if state.captures != nil do delete(state.captures, allocator)
	if state.agendas != nil do delete(state.agendas, allocator)
	if state.arena != nil do delete(state.arena, allocator)
	free(state, allocator)
}

@(private)
planning_failure :: proc(kind: Operation_Kind, code: Failure_Code, field: Failure_Field) -> Failure {
	return {kind = kind, code = code, field = field}
}
