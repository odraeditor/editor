// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"

/* MAX_JAN_LINT_CHECKER_BYTES bounds one copied checker identity. */
MAX_JAN_LINT_CHECKER_BYTES :: 64
/* MAX_JAN_LINT_EXPLANATION_BYTES bounds one copied diagnostic explanation. */
MAX_JAN_LINT_EXPLANATION_BYTES :: 256

/* Jan_Lint_Generation identifies one exact lint computation. */
Jan_Lint_Generation :: distinct u64

/* Jan_Lint_Severity is the stable user-visible importance of one lint fact. */
Jan_Lint_Severity :: enum u8 {
	Invalid,
	Advice,
	Warning,
	Error,
}

/* Jan_Lint_Confidence reports how conclusively source evidence supports a fact. */
Jan_Lint_Confidence :: enum u8 {
	Invalid,
	Tentative,
	Likely,
	Certain,
}

/* Jan_Lint_Code classifies deterministic Stage 1 document diagnostics. */
Jan_Lint_Code :: enum u8 {
	Invalid,
	Malformed,
	Unterminated,
	Context_Invalid,
	Ambiguous,
	Resource_Limited,
	Configuration_Invalid,
}

/* Jan_Lint_Checker is one bounded copied checker identity. */
Jan_Lint_Checker :: struct {
	bytes:  [MAX_JAN_LINT_CHECKER_BYTES]u8,
	length: u16,
}

/* Jan_Lint_Explanation is one bounded copied source-only explanation. */
Jan_Lint_Explanation :: struct {
	bytes:  [MAX_JAN_LINT_EXPLANATION_BYTES]u8,
	length: u16,
}

/* Jan_Lint_Record is one copied diagnostic tied to an exact analysis scope. */
Jan_Lint_Record :: struct {
	id:            u32,
	generation:    Jan_Lint_Generation,
	scope:         Jan_Analysis_Scope,
	range:         Jan_Source_Range,
	has_range:     bool,
	code:          Jan_Lint_Code,
	severity:      Jan_Lint_Severity,
	confidence:    Jan_Lint_Confidence,
	checker:       Jan_Lint_Checker,
	explanation:   Jan_Lint_Explanation,
}

/* Jan_Lint_Result owns one bounded copied diagnostic generation. */
Jan_Lint_Result :: struct {
	state: rawptr,
}

@(private)
Jan_Lint_Result_State :: struct {
	scope:       Jan_Analysis_Scope,
	generation:  Jan_Lint_Generation,
	records:     [dynamic]Jan_Lint_Record,
	retained_bytes: u64,
	allocator:   runtime.Allocator,
}

/* jan_lint_analyze derives source-only diagnostics from one confirmed analysis. */
jan_lint_analyze :: proc(
	analysis: ^Jan_Structural_Analysis,
	latest_failure: Jan_Failure,
	generation: Jan_Lint_Generation,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (result: Jan_Lint_Result, ok: bool, failure: Jan_Failure) {
	_, usage_ok := jan_structural_analysis_usage(analysis)
	nodes := jan_structural_analysis_nodes(analysis)
	if !usage_ok || len(nodes) == 0 {
		return {}, false, jan_lint_failure({}, .Incomplete)
	}
	scope := nodes[0].range.scope
	if !jan_analysis_scope_is_valid(scope) || generation == Jan_Lint_Generation(0) ||
	   !jan_resource_limits_are_valid(limits) {
		return {}, false, jan_lint_failure(scope, .Invalid_Range)
	}
	if allocator.procedure == nil {
		return {}, false, jan_lint_failure(scope, .Allocation_Failed)
	}
	recoveries := jan_structural_analysis_recoveries(analysis)
	extra := 0
	if jan_lint_failure_is_current(scope, latest_failure) do extra = 1
	count := len(recoveries) + extra
	retained_bytes := u64(count) * u64(size_of(Jan_Lint_Record))
	if count > int(limits.diagnostics) || retained_bytes > limits.inspection_bytes {
		failure = jan_lint_failure(scope, .Limited)
		failure.limit = min(u64(limits.diagnostics), limits.inspection_bytes / u64(size_of(Jan_Lint_Record)))
		failure.actual = u64(count)
		return {}, false, failure
	}
	state, state_error := new(Jan_Lint_Result_State, allocator)
	if state_error != nil do return {}, false, jan_lint_failure(scope, .Allocation_Failed)
	state^ = Jan_Lint_Result_State{scope = scope, generation = generation, allocator = allocator}
	state.records, state_error = make([dynamic]Jan_Lint_Record, 0, count, allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, jan_lint_failure(scope, .Allocation_Failed)
	}
	for recovery in recoveries {
		record := jan_lint_recovery_record(recovery, generation, u32(len(state.records)) + 1)
		_, append_error := append(&state.records, record)
		if append_error != nil {
		delete(state.records)
			free(state, allocator)
			return {}, false, jan_lint_failure(scope, .Allocation_Failed)
		}
	}
	if extra == 1 {
		record := jan_lint_failure_record(latest_failure, generation, u32(len(state.records)) + 1)
		_, append_error := append(&state.records, record)
		if append_error != nil {
			delete(state.records)
			free(state, allocator)
			return {}, false, jan_lint_failure(scope, .Allocation_Failed)
		}
	}
	state.retained_bytes = retained_bytes
	return Jan_Lint_Result{state = state}, true, {}
}

/* jan_lint_refresh atomically replaces one result for the same document lineage. */
jan_lint_refresh :: proc(
	result: ^Jan_Lint_Result,
	analysis: ^Jan_Structural_Analysis,
	latest_failure: Jan_Failure,
	generation: Jan_Lint_Generation,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Jan_Failure) {
	if result == nil do return false, jan_lint_failure({}, .Invalid_Range)
	previous := jan_lint_result_state(result)
	candidate, built, build_failure := jan_lint_analyze(
		analysis,
		latest_failure,
		generation,
		limits,
		allocator,
	)
	if !built do return false, build_failure
	if previous != nil {
		candidate_state := jan_lint_result_state(&candidate)
		if candidate_state == nil || generation <= previous.generation ||
		   candidate_state.scope.buffer_id != previous.scope.buffer_id ||
		   candidate_state.scope.document_id != previous.scope.document_id ||
		   candidate_state.scope.language != previous.scope.language ||
		   candidate_state.scope.source_revision < previous.scope.source_revision {
			jan_lint_result_close(&candidate)
			return false, jan_lint_failure(previous.scope, .Stale)
		}
	}
	jan_lint_result_close(result)
	result^ = candidate
	return true, {}
}

/* jan_lint_result_records returns copied records owned by one result. */
jan_lint_result_records :: proc(result: ^Jan_Lint_Result) -> []Jan_Lint_Record {
	state := jan_lint_result_state(result)
	if state == nil do return nil
	return state.records[:]
}

/* jan_lint_result_scope returns the exact confirmed analysis scope. */
jan_lint_result_scope :: proc(result: ^Jan_Lint_Result) -> (Jan_Analysis_Scope, bool) {
	state := jan_lint_result_state(result)
	if state == nil do return {}, false
	return state.scope, true
}

/* jan_lint_result_generation returns the exact lint generation. */
jan_lint_result_generation :: proc(result: ^Jan_Lint_Result) -> (Jan_Lint_Generation, bool) {
	state := jan_lint_result_state(result)
	if state == nil do return 0, false
	return state.generation, true
}

/* jan_lint_result_close releases one copied lint generation deterministically. */
jan_lint_result_close :: proc(result: ^Jan_Lint_Result) -> bool {
	state := jan_lint_result_state(result)
	if state == nil do return false
	delete(state.records)
	allocator := state.allocator
	free(state, allocator)
	result^ = {}
	return true
}

@(private)
jan_lint_recovery_record :: proc(
	recovery: Jan_Recovery_Record,
	generation: Jan_Lint_Generation,
	id: u32,
) -> Jan_Lint_Record {
	code, severity, confidence, explanation := jan_lint_recovery_classification(recovery.code)
	return {
		id = id,
		generation = generation,
		scope = recovery.range.scope,
		range = recovery.range,
		has_range = true,
		code = code,
		severity = severity,
		confidence = confidence,
		checker = jan_lint_checker("jan-syntax-recovery"),
		explanation = jan_lint_explanation(explanation),
	}
}

@(private)
jan_lint_failure_record :: proc(
	failure: Jan_Failure,
	generation: Jan_Lint_Generation,
	id: u32,
) -> Jan_Lint_Record {
	code := Jan_Lint_Code.Resource_Limited
	explanation := "Jan syntax analysis reached a configured resource limit."
	if failure.code == .Invalid_Configuration {
		code = .Configuration_Invalid
		explanation = "Jan syntax configuration is invalid for this analysis generation."
	}
	return {
		id = id,
		generation = generation,
		scope = failure.scope,
		code = code,
		severity = .Error,
		confidence = .Certain,
		checker = jan_lint_checker("jan-analysis-policy"),
		explanation = jan_lint_explanation(explanation),
	}
}

@(private)
jan_lint_recovery_classification :: proc(
	code: Jan_Recovery_Code,
) -> (Jan_Lint_Code, Jan_Lint_Severity, Jan_Lint_Confidence, string) {
	switch code {
	case .Malformed:
		return .Malformed, .Error, .Certain, "Malformed Jan syntax is preserved in this source range."
	case .Unterminated:
		return .Unterminated, .Error, .Certain, "Jan syntax is unterminated in this source range."
	case .Context_Invalid:
		return .Context_Invalid, .Warning, .Certain, "Jan syntax is not valid in this source context."
	case .Ambiguous:
		return .Ambiguous, .Warning, .Likely, "Jan syntax is ambiguous in this source context."
	case .Limited:
		return .Resource_Limited, .Error, .Certain, "Jan syntax exceeded a bounded analysis limit."
	case .Invalid:
	}
	return .Malformed, .Error, .Tentative, "Jan syntax recovery is incomplete."
}

@(private)
jan_lint_failure_is_current :: proc(scope: Jan_Analysis_Scope, failure: Jan_Failure) -> bool {
	return (failure.code == .Limited || failure.code == .Invalid_Configuration) &&
		failure.scope == scope
}

@(private)
jan_lint_checker :: proc(value: string) -> (result: Jan_Lint_Checker) {
	result.length = u16(copy(result.bytes[:], value[:min(len(value), MAX_JAN_LINT_CHECKER_BYTES)]))
	return
}

@(private)
jan_lint_explanation :: proc(value: string) -> (result: Jan_Lint_Explanation) {
	result.length = u16(copy(result.bytes[:], value[:min(len(value), MAX_JAN_LINT_EXPLANATION_BYTES)]))
	return
}

@(private)
jan_lint_result_state :: proc(result: ^Jan_Lint_Result) -> ^Jan_Lint_Result_State {
	if result == nil || result.state == nil do return nil
	return cast(^Jan_Lint_Result_State)result.state
}

@(private)
jan_lint_failure :: proc(scope: Jan_Analysis_Scope, code: Jan_Failure_Code) -> Jan_Failure {
	return {operation = .Lint, code = code, scope = scope}
}
