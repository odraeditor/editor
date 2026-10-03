// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "base:runtime"

@(private)
Result_State :: struct {
	outcome:       Outcome,
	scope:         Scope,
	has_current:   bool,
	current_index: u32,
	occurrences:   []Occurrence,
	captures:      []Capture,
	progress:      Progress,
	usage:         Usage,
	allocator:     runtime.Allocator,
}

@(private)
Result_Config :: struct {
	outcome:       Outcome,
	scope:         Scope,
	has_current:   bool,
	current_index: u32,
	occurrences:   []Occurrence,
	captures:      []Capture,
	progress:      Progress,
	usage:         Usage,
	limits:        Limits,
	allocator:     runtime.Allocator,
}

@(private)
result_init :: proc(result: ^Result, config: Result_Config) -> (ok: bool, failure: Failure) {
	assert(result != nil)
	assert(result.state == nil, "result is already initialized")
	if config.outcome == .Invalid || !limits_are_valid(config.limits) {
		return false, Failure{code = .Invalid_Limits}
	}
	if len(config.occurrences) > int(config.limits.retained_occurrences) {
		return false, Failure {
			code = .Work_Limit,
			buffer_id = config.scope.buffer_id,
			revision = config.scope.revision,
			limit = u64(config.limits.retained_occurrences),
			actual = u64(len(config.occurrences)),
		}
	}
	if config.has_current && int(config.current_index) >= len(config.occurrences) {
		return false, Failure {
			code = .Out_Of_Range,
			buffer_id = config.scope.buffer_id,
			revision = config.scope.revision,
			limit = u64(len(config.occurrences)),
			actual = u64(config.current_index),
		}
	}
	maximum_captures := u64(len(config.occurrences)) * u64(config.limits.capture_groups)
	if u64(len(config.captures)) > maximum_captures {
		return false, Failure {
			code = .Work_Limit,
			buffer_id = config.scope.buffer_id,
			revision = config.scope.revision,
			limit = maximum_captures,
			actual = u64(len(config.captures)),
		}
	}
	if config.allocator.procedure == nil {
		return false, Failure{code = .Persistent_Memory_Limit}
	}
	state, state_error := new(Result_State, config.allocator)
	if state_error != nil {
		return false, Failure {
			code = .Persistent_Memory_Limit,
			actual = u64(size_of(Result_State)),
		}
	}
	occurrences, occurrences_error := make(
		[]Occurrence,
		len(config.occurrences),
		config.allocator,
	)
	if occurrences_error != nil {
		free(state, config.allocator)
		return false, Failure {
			code = .Persistent_Memory_Limit,
			actual = u64(len(config.occurrences)) * u64(size_of(Occurrence)),
		}
	}
	captures, captures_error := make([]Capture, len(config.captures), config.allocator)
	if captures_error != nil {
		delete(occurrences, config.allocator)
		free(state, config.allocator)
		return false, Failure {
			code = .Persistent_Memory_Limit,
			actual = u64(len(config.captures)) * u64(size_of(Capture)),
		}
	}
	copy(occurrences, config.occurrences)
	copy(captures, config.captures)
	state.outcome = config.outcome
	state.scope = config.scope
	state.has_current = config.has_current
	state.current_index = config.current_index
	state.occurrences = occurrences
	state.captures = captures
	state.progress = config.progress
	state.usage = config.usage
	state.usage.retained_occurrences = u32(len(occurrences))
	state.usage.retained_captures = u32(len(captures))
	state.allocator = config.allocator
	result.state = state
	return true, {}
}

/* result_view borrows one live result's copied records until result_close. */
result_view :: proc(result: ^Result) -> (view: Result_View, ok: bool, failure: Failure) {
	state := result_state(result)
	if state == nil {
		return {}, false, Failure{code = .Closed_Result}
	}
	return Result_View {
		outcome = state.outcome,
		scope = state.scope,
		has_current = state.has_current,
		current_index = state.current_index,
		occurrences = state.occurrences,
		captures = state.captures,
		progress = state.progress,
		usage = state.usage,
	}, true, {}
}

/* result_close releases every copied record and invalidates its handle exactly once. */
result_close :: proc(result: ^Result) -> (ok: bool, failure: Failure) {
	state := result_state(result)
	if state == nil {
		return false, Failure{code = .Closed_Result}
	}
	allocator := state.allocator
	buffer_id := state.scope.buffer_id
	revision := state.scope.revision
	delete(state.captures, allocator)
	delete(state.occurrences, allocator)
	result.state = nil
	free(state, allocator)
	return true, Failure{buffer_id = buffer_id, revision = revision}
}

@(private)
result_state :: proc(result: ^Result) -> ^Result_State {
	if result == nil || result.state == nil {
		return nil
	}
	return (^Result_State)(result.state)
}
