// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

/* resolve_export_setting selects one scalar winner or counts additive contributions. */
resolve_export_setting :: proc(
	operation_id: Operation_ID,
	key, backend: string,
	candidates: []Setting_Candidate,
) -> (Setting_Resolution, bool, Failure) {
	if operation_id == Operation_ID(0) || !output_text_is_valid(key, MAX_IDENTITY_BYTES) ||
	   !output_text_is_valid(backend, MAX_IDENTITY_BYTES) || len(candidates) == 0 ||
	   len(candidates) > int(MAX_SETTINGS) {
		return {}, false, output_failure(operation_id, .Export, .Invalid_Request, .Setting)
	}
	resolution := Setting_Resolution {}
	found := false
	winning_source := Setting_Source.Invalid
	winning_backend_specific := false
	winning_order: u32
	for candidate, index in candidates {
		if !output_text_is_valid(candidate.key, MAX_IDENTITY_BYTES) ||
		   !output_text_is_valid(candidate.value, MAX_SETTING_VALUE_BYTES) ||
		   candidate.source == .Invalid ||
		   (len(candidate.backend) > 0 && !output_text_is_valid(candidate.backend, MAX_IDENTITY_BYTES)) {
			return {}, false, output_failure(operation_id, .Export, .Malformed, .Setting)
		}
		if candidate.key != key || (len(candidate.backend) > 0 && candidate.backend != backend) do continue
		backend_specific := len(candidate.backend) > 0
		if !found {
			found = true
			resolution.additive = candidate.additive
		} else if resolution.additive != candidate.additive {
			return {}, false, output_failure(operation_id, .Export, .Conflict, .Setting)
		}
		if candidate.additive {
			resolution.contribution_count += 1
			resolution.winner_index = u16(index)
			continue
		}
		if !found || candidate.source > winning_source ||
		   (candidate.source == winning_source && backend_specific && !winning_backend_specific) ||
		   (candidate.source == winning_source && backend_specific == winning_backend_specific &&
		    candidate.source_order >= winning_order) {
			if resolution.contribution_count > 0 do resolution.shadowed_count += 1
			resolution.winner_index = u16(index)
			winning_source = candidate.source
			winning_backend_specific = backend_specific
			winning_order = candidate.source_order
		} else {
			resolution.shadowed_count += 1
		}
		resolution.contribution_count = 1
	}
	if !found do return {}, false, output_failure(operation_id, .Export, .Missing, .Setting)
	return resolution, true, {}
}

/* prepare_output_plan validates one complete export request without performing effects. */
prepare_output_plan :: proc(request: Export_Request) -> (Output_Plan, bool, Failure) {
	if request.operation_id == Operation_ID(0) || !scope_is_valid(request.scope) ||
	   !selection_is_valid(request.selection, request.scope) ||
	   !output_text_is_valid(request.backend, MAX_IDENTITY_BYTES) || !request.explicit ||
	   !projection_policy_is_valid(request.projection, request.limits) ||
	   !destination_is_valid(request.destination) || !limits_are_valid(request.limits) {
		return {}, false, output_failure(request.operation_id, .Export, .Invalid_Request, .Scope)
	}
	if len(request.settings) > int(request.limits.settings) {
		return {}, false, output_limited_failure(request.operation_id, .Setting,
			u64(request.limits.settings), u64(len(request.settings)))
	}
	if len(request.includes) > int(request.limits.included_resources) {
		return {}, false, output_limited_failure(request.operation_id, .Include,
			u64(request.limits.included_resources), u64(len(request.includes)))
	}
	if len(request.macros) > int(request.limits.macro_expansions) {
		return {}, false, output_limited_failure(request.operation_id, .Macro,
			u64(request.limits.macro_expansions), u64(len(request.macros)))
	}
	if len(request.filters) > int(request.limits.filters) {
		return {}, false, output_limited_failure(request.operation_id, .Filter,
			u64(request.limits.filters), u64(len(request.filters)))
	}
	for candidate in request.settings {
		if !output_text_is_valid(candidate.key, MAX_IDENTITY_BYTES) ||
		   !output_text_is_valid(candidate.value, MAX_SETTING_VALUE_BYTES) ||
		   candidate.source == .Invalid ||
		   (len(candidate.backend) > 0 && !output_text_is_valid(candidate.backend, MAX_IDENTITY_BYTES)) {
			return {}, false, output_failure(request.operation_id, .Export, .Malformed, .Setting)
		}
	}
	for include, index in request.includes {
		if include.resource_id == 0 || include.resource_revision == 0 || include.depth == 0 ||
		   include.depth > request.limits.include_depth ||
		   (include.end_line != 0 && include.start_line > include.end_line) {
			return {}, false, output_failure(request.operation_id, .Export, .Malformed, .Include)
		}
		for prior in request.includes[:index] do if prior.resource_id == include.resource_id {
			return {}, false, output_failure(request.operation_id, .Export, .Cycle, .Include)
		}
	}
	total_expansion_bytes: u64
	for macro in request.macros {
		if !output_text_is_valid(macro.identity, MAX_IDENTITY_BYTES) || !macro.defined || macro.recursive ||
		   macro.depth == 0 || macro.depth > request.limits.include_depth ||
		   macro.expansion_bytes > request.limits.output_bytes {
			return {}, false, output_failure(request.operation_id, .Export, .Malformed, .Macro)
		}
		total_expansion_bytes += macro.expansion_bytes
		if total_expansion_bytes > request.limits.output_bytes {
			return {}, false, output_limited_failure(request.operation_id, .Macro,
				request.limits.output_bytes, total_expansion_bytes)
		}
	}
	for filter, index in request.filters {
		if !output_text_is_valid(filter.identity, MAX_IDENTITY_BYTES) ||
		   filter.generation != request.scope.filter_generation || !filter.available {
			return {}, false, output_failure(request.operation_id, .Export, .Unavailable, .Filter)
		}
		for prior in request.filters[:index] do if prior.identity == filter.identity || prior.order == filter.order {
			return {}, false, output_failure(request.operation_id, .Export, .Conflict, .Filter)
		}
	}
	return Output_Plan {
		operation_id = request.operation_id,
		scope = request.scope,
		selection = request.selection,
		setting_count = u16(len(request.settings)),
		include_count = u32(len(request.includes)),
		macro_count = u32(len(request.macros)),
		filter_count = u16(len(request.filters)),
		destination = request.destination,
		complete = true,
	}, true, {}
}

/* output_lifecycle_transition applies one closed deterministic state transition. */
output_lifecycle_transition :: proc(state: Lifecycle_State, event: Lifecycle_State) -> (Lifecycle_State, bool) {
	#partial switch state {
	case .Prepared:
		#partial switch event {
		case .Confirmed, .Cancelled, .Failed: return event, true
		case: return state, false
		}
	case .Confirmed:
		#partial switch event {
		case .Active, .Cancelled, .Failed: return event, true
		case: return state, false
		}
	case .Active:
		#partial switch event {
		case .Completed, .Cancelled, .Failed, .Recovery_Required: return event, true
		case: return state, false
		}
	case .Completed, .Cancelled, .Failed, .Recovery_Required:
		if event == .Closed do return .Closed, true
		return state, false
	case:
		return state, false
	}
}

@(private)
output_failure :: proc(operation_id: Operation_ID, kind: Operation_Kind, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = kind, code = code, field = field}
}

@(private)
output_limited_failure :: proc(operation_id: Operation_ID, field: Failure_Field, limit, actual: u64) -> Failure {
	return {operation_id = operation_id, kind = .Export, code = .Limited, field = field,
	        limit = limit, actual = actual}
}
