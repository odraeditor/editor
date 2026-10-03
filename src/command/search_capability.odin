// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor"
import "../interaction"
import "../search"
import editor_view "../view"
import "base:runtime"

/* MAX_SEARCH_CAPABILITY_TEXT_BYTES bounds one copied programmable inspection. */
MAX_SEARCH_CAPABILITY_TEXT_BYTES :: u64(
	2 * search.MAX_PATTERN_BYTES + search.MAX_REPLACEMENT_TEMPLATE_BYTES,
)

/* Search_Access identifies one independently granted programmable search operation. */
Search_Access :: enum u8 {
	Policy_Inspection,
	Session_Inspection,
	Semantic_Invocation,
}

/* Search_Access_Set is the immutable authority granted to one search capability. */
Search_Access_Set :: bit_set[Search_Access; u8]

/* Search_Session_Kind identifies the one active view-local search interaction. */
Search_Session_Kind :: enum u8 {
	None,
	Incremental,
	Query_Replacement,
}

/* Search_Capability_Failure_Code classifies rejection before any effect. */
Search_Capability_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Permission_Denied,
	Wrong_Authority,
	Wrong_Editor,
	Wrong_View,
	Stale_View_State,
	Wrong_Buffer,
	Stale_Revision,
	Stale_Command_Registry,
	Stale_Interaction,
	Stale_Policy,
	Conflicting_Sessions,
	Session_Unavailable,
	Command_Not_Allowed,
	Inspection_Limit,
	Temporary_Memory_Limit,
}

/* Search_Capability_Policy is one complete immutable programmable policy value. */
Search_Capability_Policy :: struct {
	generation:         search.Policy_Generation,
	search_policy:      search.Policy,
	search_limits:      search.Limits,
	replacement_policy: search.Replacement_Policy,
	replacement_limits: search.Replacement_Limits,
	replace_all_limits: Replace_All_Limits,
}

/* Search_Capability_Scope captures every identity required by one checked turn. */
Search_Capability_Scope :: struct {
	editor_session_id:          Editor_Session_ID,
	access:                     Search_Access_Set,
	view:                       editor_view.View_Handle,
	view_state_generation:      u64,
	buffer_id:                   editor.Buffer_ID,
	revision:                    editor.Revision,
	command_registry_generation: interaction.Registry_Generation,
	session_kind:                Search_Session_Kind,
	interaction_generation:      u64,
	policy_generation:           search.Policy_Generation,
}

/* Search_Capability_Context borrows native owners and one authoritative policy. */
Search_Capability_Context :: struct {
	editor_session_id: Editor_Session_ID,
	access:            Search_Access_Set,
	native:            Native_Context,
	policy:            Search_Capability_Policy,
}

/* Search_Policy_Summary returns one copied policy under its exact native scope. */
Search_Policy_Summary :: struct {
	scope:  Search_Capability_Scope,
	policy: Search_Capability_Policy,
}

/* Search_Session_Copy_Request bounds every allocation in one session inspection. */
Search_Session_Copy_Request :: struct {
	expected_scope:  Search_Capability_Scope,
	occurrence_limit: u32,
	capture_limit:    u32,
	text_bytes_limit: u64,
}

/* Search_Session_Copy owns all text, occurrence, and capture values it exposes. */
Search_Session_Copy :: struct {
	scope:                    Search_Capability_Scope,
	present:                  bool,
	kind:                     Search_Session_Kind,
	direction:                search.Direction,
	pattern_kind:             search.Pattern_Kind,
	search_scope:             search.Scope,
	search_status:            editor_view.Search_Status,
	query_status:             editor_view.Query_Replacement_Status,
	last_response:            editor_view.Query_Replacement_Response,
	semantic_group:           editor_view.Query_Replacement_Group_ID,
	pattern:                  []byte,
	last_successful_pattern:  []byte,
	replacement:              []byte,
	search_policy:            search.Policy,
	search_limits:            search.Limits,
	replacement_policy:       search.Replacement_Policy,
	replacement_limits:       search.Replacement_Limits,
	effective_case:           search.Effective_Case,
	source_revision:          editor.Revision,
	observed_revision:        editor.Revision,
	source_text_bytes:        u64,
	observed_text_bytes:      u64,
	replacements:             u64,
	skips:                    u64,
	recomputations:           u64,
	has_current:              bool,
	current:                  search.Occurrence,
	current_index:            u32,
	occurrences:              []search.Occurrence,
	captures:                 []search.Capture,
	progress:                 search.Progress,
	usage:                    search.Usage,
	allocator:                runtime.Allocator,
}

/* Search_Command_Request invokes one admitted semantic search command. */
Search_Command_Request :: struct {
	expected_scope:    Search_Capability_Scope,
	name:              string,
	pattern:           string,
	replacement:       string,
	direction:         search.Direction,
	incremental_turn:  Incremental_Search_Turn,
	query_action:      Query_Replacement_Action,
	query_id:          search.Query_ID,
	search_generation: search.Search_Generation,
	semantic_group:    editor_view.Query_Replacement_Group_ID,
	scope:             search.Scope,
	cancellation:      ^search.Cancellation,
	policy:            Search_Capability_Policy,
}

/* Search_Command_Result is a copied result with no retained native ownership. */
Search_Command_Result :: struct {
	result_scope:             Search_Capability_Scope,
	completion:               Native_Completion,
	changed:                  bool,
	query_status:             editor_view.Query_Replacement_Status,
	replacements:             u64,
	skips:                    u64,
	finished:                 bool,
	replacement_usage:        search.Replacement_Usage,
	replace_all_usage:        Replace_All_Usage,
	continuation_code:        Failure_Code,
	continuation_search_code: search.Failure_Code,
}

/* search_capability_scope captures the exact live editor and interaction identity. */
search_capability_scope :: proc(
	ctx: Search_Capability_Context,
) -> (scope: Search_Capability_Scope, ok: bool, failure: Failure_Context) {
	if !search_capability_context_is_valid(ctx) {
		return {}, false, search_capability_failure(.Invalid_Context)
	}
	if ctx.native.cancelled {
		return {}, false, Failure_Context{code = .Cancelled}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !logical_ok {
		failure = native_view_failure(ctx.native.command, logical_failure)
		failure.search_capability_code = .Wrong_View
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(ctx.native.buffer)
	if !stats_ok {
		failure = native_editor_failure(ctx.native.command, stats_failure)
		failure.search_capability_code = .Wrong_Buffer
		return {}, false, failure
	}
	if logical.buffer_id != stats.buffer_id {
		return {}, false, search_capability_failure(.Wrong_Buffer)
	}
	if logical.revision != stats.revision {
		failure = search_capability_failure(.Stale_Revision)
		failure.buffer_id = stats.buffer_id
		failure.revision = logical.revision
		failure.actual = u64(stats.revision)
		return {}, false, failure
	}
	registry_stats, registry_ok, registry_failure := interaction.command_registry_stats(
		ctx.native.registry,
	)
	if !registry_ok {
		failure = search_capability_failure(.Stale_Command_Registry)
		failure.interaction_code = registry_failure.code
		return {}, false, failure
	}
	incremental, incremental_ok, incremental_failure := editor_view.search_session_view(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !incremental_ok {
		failure = native_view_failure(ctx.native.command, incremental_failure)
		failure.search_capability_code = .Stale_Interaction
		return {}, false, failure
	}
	query, query_ok, query_failure := editor_view.query_replacement_session_view(
		ctx.native.view_registry,
		ctx.native.view,
	)
	if !query_ok {
		failure = native_view_failure(ctx.native.command, query_failure)
		failure.search_capability_code = .Stale_Interaction
		return {}, false, failure
	}
	if incremental.present && query.present {
		return {}, false, search_capability_failure(.Conflicting_Sessions)
	}
	session_kind := Search_Session_Kind.None
	interaction_generation: u64
	policy_generation := ctx.policy.generation
	if incremental.present {
		if incremental.policy_generation != ctx.policy.generation ||
		   incremental.policy != ctx.policy.search_policy ||
		   incremental.limits != ctx.policy.search_limits {
			return {}, false, search_capability_failure(.Stale_Policy)
		}
		session_kind = .Incremental
		interaction_generation = incremental.interaction_generation
		policy_generation = incremental.policy_generation
	} else if query.present {
		if query.policy_generation != ctx.policy.generation ||
		   query.search_policy != ctx.policy.search_policy ||
		   query.search_limits != ctx.policy.search_limits ||
		   query.replacement_policy != ctx.policy.replacement_policy ||
		   query.replacement_limits != ctx.policy.replacement_limits {
			return {}, false, search_capability_failure(.Stale_Policy)
		}
		session_kind = .Query_Replacement
		interaction_generation = query.interaction_generation
		policy_generation = query.policy_generation
	}
	return Search_Capability_Scope {
		editor_session_id = ctx.editor_session_id,
		access = ctx.access,
		view = ctx.native.view,
		view_state_generation = logical.state_generation,
		buffer_id = stats.buffer_id,
		revision = stats.revision,
		command_registry_generation = registry_stats.generation,
		session_kind = session_kind,
		interaction_generation = interaction_generation,
		policy_generation = policy_generation,
	}, true, {}
}

/* search_policy_inspect copies the complete policy after exact scope validation. */
search_policy_inspect :: proc(
	ctx: Search_Capability_Context,
	expected_scope: Search_Capability_Scope,
) -> (summary: Search_Policy_Summary, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := search_capability_validate(
		ctx,
		expected_scope,
		.Policy_Inspection,
	)
	if !valid {
		return {}, false, validation_failure
	}
	return Search_Policy_Summary{scope = actual, policy = ctx.policy}, true, {}
}

/* search_session_inspect returns a bounded owned copy of one active interaction. */
search_session_inspect :: proc(
	ctx: Search_Capability_Context,
	request: Search_Session_Copy_Request,
) -> (copied: Search_Session_Copy, ok: bool, failure: Failure_Context) {
	actual, valid, validation_failure := search_capability_validate(
		ctx,
		request.expected_scope,
		.Session_Inspection,
	)
	if !valid {
		return {}, false, validation_failure
	}
	if actual.session_kind == .None {
		return Search_Session_Copy{scope = actual}, true, {}
	}
	if request.occurrence_limit == 0 || request.capture_limit == 0 ||
	   request.occurrence_limit > ctx.policy.search_limits.retained_occurrences ||
	   request.text_bytes_limit > MAX_SEARCH_CAPABILITY_TEXT_BYTES {
		return {}, false, search_capability_failure(.Inspection_Limit)
	}
	allocator := ctx.native.temporary_allocator
	result := Search_Session_Copy {
		scope = actual,
		present = true,
		kind = actual.session_kind,
		allocator = allocator,
	}
	borrowed_occurrences: []search.Occurrence
	borrowed_captures: []search.Capture
	if actual.session_kind == .Incremental {
		state, state_ok, state_failure := editor_view.search_session_view(
			ctx.native.view_registry,
			ctx.native.view,
		)
		if !state_ok || !state.present {
			return {}, false, search_capability_view_failure(state_failure)
		}
		result.direction = state.direction
		result.pattern_kind = state.kind
		result.search_scope = state.scope
		result.search_status = state.status
		result.search_policy = state.policy
		result.search_limits = state.limits
		result.effective_case = state.effective_case
		result.source_revision = state.source_revision
		result.has_current = state.has_current
		result.current_index = state.current_index
		result.progress = state.progress
		result.usage = state.usage
		if u64(len(state.query)) + u64(len(state.last_successful_query)) >
		   request.text_bytes_limit {
			return {}, false, search_capability_failure(.Inspection_Limit)
		}
		if !search_capability_copy_texts(
			&result,
			state.query,
			state.last_successful_query,
			"",
		) {
			search_session_copy_close(&result)
			return {}, false, search_capability_failure(.Temporary_Memory_Limit)
		}
		borrowed_occurrences = state.occurrences
		borrowed_captures = state.captures
	} else {
		state, state_ok, state_failure := editor_view.query_replacement_session_view(
			ctx.native.view_registry,
			ctx.native.view,
		)
		if !state_ok || !state.present {
			return {}, false, search_capability_view_failure(state_failure)
		}
		result.direction = state.direction
		result.pattern_kind = state.kind
		result.search_scope = state.scope
		result.query_status = state.status
		result.last_response = state.last_response
		result.semantic_group = state.semantic_group
		result.search_policy = state.search_policy
		result.search_limits = state.search_limits
		result.replacement_policy = state.replacement_policy
		result.replacement_limits = state.replacement_limits
		result.effective_case = state.effective_case
		result.source_revision = state.source_revision
		result.observed_revision = state.observed_revision
		result.source_text_bytes = state.source_text_bytes
		result.observed_text_bytes = state.observed_text_bytes
		result.replacements = state.replacements
		result.skips = state.skips
		result.recomputations = state.recomputations
		result.has_current = state.has_current
		result.current_index = state.current_index
		result.progress = state.progress
		result.usage = state.usage
		if u64(len(state.pattern)) + u64(len(state.replacement)) > request.text_bytes_limit {
			return {}, false, search_capability_failure(.Inspection_Limit)
		}
		if !search_capability_copy_texts(
			&result,
			state.pattern,
			"",
			state.replacement,
		) {
			search_session_copy_close(&result)
			return {}, false, search_capability_failure(.Temporary_Memory_Limit)
		}
		borrowed_occurrences = state.occurrences
		borrowed_captures = state.captures
	}
	arrays_ok, arrays_failure := search_capability_copy_occurrences(
		&result,
		borrowed_occurrences,
		borrowed_captures,
		request.occurrence_limit,
		request.capture_limit,
	)
	if !arrays_ok {
		search_session_copy_close(&result)
		return {}, false, arrays_failure
	}
	return result, true, {}
}

/* search_session_copy_close releases all storage owned by one copied inspection. */
search_session_copy_close :: proc(copied: ^Search_Session_Copy) {
	if copied == nil {
		return
	}
	allocator := copied.allocator
	if allocator.procedure != nil {
		delete(copied.captures, allocator)
		delete(copied.occurrences, allocator)
		delete(copied.replacement, allocator)
		delete(copied.last_successful_pattern, allocator)
		delete(copied.pattern, allocator)
	}
	copied^ = {}
}

/* search_command_invoke executes one admitted command and closes native results locally. */
search_command_invoke :: proc(
	ctx: Search_Capability_Context,
	request: Search_Command_Request,
) -> (result: Search_Command_Result, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := search_capability_validate(
		ctx,
		request.expected_scope,
		.Semantic_Invocation,
	)
	if !valid {
		return {}, false, validation_failure
	}
	handle, found, lookup_failure := interaction.command_lookup(ctx.native.registry, request.name)
	if !found {
		failure = search_capability_failure(.Command_Not_Allowed)
		failure.interaction_code = lookup_failure.code
		return {}, false, failure
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(ctx.native.registry, handle)
	route, route_ok := native_route_decode(metadata.route)
	if !metadata_ok || !route_ok || !search_capability_command_is_admitted(route) {
		failure = search_capability_failure(.Command_Not_Allowed)
		failure.interaction_code = metadata_failure.code
		return {}, false, failure
	}
	native := ctx.native
	native.command = handle
	policy := ctx.policy
	if request.policy.generation != search.Policy_Generation(0) {
		if request.policy.generation != ctx.policy.generation {
			return {}, false, search_capability_failure(.Stale_Policy)
		}
		if !search_capability_policy_is_valid(request.policy) {
			return {}, false, Failure_Context{code = .Invalid_Request}
		}
		policy = request.policy
	}
	if route == .ISearch_Forward || route == .ISearch_Backward ||
	   route == .ISearch_Forward_Regexp || route == .ISearch_Backward_Regexp {
		kind, direction := search_capability_command_pattern(route)
		changed, invoked, invoke_failure := incremental_search(
			Incremental_Search_Request {
				buffer = native.buffer,
				view_registry = native.view_registry,
				view = native.view,
				pattern = request.pattern,
				pattern_kind = kind,
				direction = direction,
				turn = request.incremental_turn,
				query_id = request.query_id,
				search_generation = request.search_generation,
				policy_generation = policy.generation,
				cancellation = request.cancellation,
				policy = policy.search_policy,
				limits = policy.search_limits,
				profile = native.profile,
				constraints = native.constraints,
				persistent_allocator = native.persistent_allocator,
				temporary_allocator = native.temporary_allocator,
			},
		)
		if !invoked {
			return {}, false, invoke_failure
		}
		result.changed = changed
		result.completion = .No_Op
		if changed {
			result.completion = .View_Changed
		}
	} else if route == .Query_Replace || route == .Query_Replace_Regexp {
		kind, _ := search_capability_command_pattern(route)
		query_result, invoked, invoke_failure := query_replacement(
			Query_Replacement_Request {
				native = native,
				action = request.query_action,
				pattern = request.pattern,
				replacement = request.replacement,
				pattern_kind = kind,
				direction = request.direction,
				semantic_group = request.semantic_group,
				query_id = request.query_id,
				search_generation = request.search_generation,
				policy_generation = policy.generation,
				cancellation = request.cancellation,
				search_policy = policy.search_policy,
				search_limits = policy.search_limits,
				replacement_policy = policy.replacement_policy,
				replace_all_limits = policy.replace_all_limits,
				replacement_limits = policy.replacement_limits,
			},
		)
		if !invoked {
			return {}, false, invoke_failure
		}
		result.completion = query_result.native.completion
		if result.completion == .Invalid {
			result.completion = .View_Changed
		}
		result.changed = true
		result.query_status = query_result.status
		result.replacements = query_result.replacements
		result.skips = query_result.skips
		result.finished = query_result.finished
		result.replacement_usage = query_result.replacement_usage
		result.replace_all_usage = query_result.replace_all_usage
		result.continuation_code = query_result.continuation_failure.code
		result.continuation_search_code = query_result.continuation_failure.search_code
		query_replacement_result_close(&query_result)
	} else {
		kind, _ := search_capability_command_pattern(route)
		replace_result, invoked, invoke_failure := replace_all(
			Replace_All_Request {
				native = native,
				pattern = request.pattern,
				replacement = request.replacement,
				pattern_kind = kind,
				search_policy = policy.search_policy,
				replacement_policy = policy.replacement_policy,
				query_id = request.query_id,
				search_generation = request.search_generation,
				cancellation = request.cancellation,
				scope = request.scope,
				limits = policy.replace_all_limits,
				replacement_limits = policy.replacement_limits,
			},
		)
		if !invoked {
			return {}, false, invoke_failure
		}
		result.completion = replace_result.native.completion
		result.changed = replace_result.usage.matches > 0
		result.replacements = replace_result.usage.matches
		result.replace_all_usage = replace_result.usage
		replace_all_result_close(&replace_result)
	}
	effective_ctx := ctx
	effective_ctx.policy = policy
	result_scope, refreshed, refresh_failure := search_capability_scope(effective_ctx)
	assert(refreshed, "successful search command invalidated its native owners")
	if !refreshed {
		return {}, false, refresh_failure
	}
	result.result_scope = result_scope
	return result, true, {}
}

@(private)
search_capability_validate :: proc(
	ctx: Search_Capability_Context,
	expected: Search_Capability_Scope,
	required: Search_Access,
) -> (actual: Search_Capability_Scope, ok: bool, failure: Failure_Context) {
	actual, ok, failure = search_capability_scope(ctx)
	if !ok {
		return {}, false, failure
	}
	if required not_in actual.access {
		return {}, false, search_capability_failure(.Permission_Denied)
	}
	if expected.access != actual.access {
		return {}, false, search_capability_failure(.Wrong_Authority)
	}
	if expected.editor_session_id != actual.editor_session_id {
		return {}, false, search_capability_failure(.Wrong_Editor)
	}
	if expected.view != actual.view {
		return {}, false, search_capability_failure(.Wrong_View)
	}
	if expected.view_state_generation != actual.view_state_generation {
		failure = search_capability_failure(.Stale_View_State)
		failure.limit = expected.view_state_generation
		failure.actual = actual.view_state_generation
		return {}, false, failure
	}
	if expected.buffer_id != actual.buffer_id {
		return {}, false, search_capability_failure(.Wrong_Buffer)
	}
	if expected.revision != actual.revision {
		failure = search_capability_failure(.Stale_Revision)
		failure.revision = expected.revision
		failure.actual = u64(actual.revision)
		return {}, false, failure
	}
	if expected.command_registry_generation != actual.command_registry_generation {
		return {}, false, search_capability_failure(.Stale_Command_Registry)
	}
	if expected.session_kind != actual.session_kind ||
	   expected.interaction_generation != actual.interaction_generation {
		return {}, false, search_capability_failure(.Stale_Interaction)
	}
	if expected.policy_generation != actual.policy_generation ||
	   expected.policy_generation != ctx.policy.generation {
		return {}, false, search_capability_failure(.Stale_Policy)
	}
	return actual, true, {}
}

@(private)
search_capability_context_is_valid :: proc(ctx: Search_Capability_Context) -> bool {
	return ctx.editor_session_id != Editor_Session_ID(0) && ctx.access != {} &&
	       ctx.native.registry != nil && ctx.native.buffer != nil &&
	       ctx.native.view_registry != nil &&
	       ctx.native.persistent_allocator.procedure != nil &&
	       ctx.native.temporary_allocator.procedure != nil &&
	       search_capability_policy_is_valid(ctx.policy)
}

@(private)
search_capability_policy_is_valid :: proc(policy: Search_Capability_Policy) -> bool {
	return policy.generation != search.Policy_Generation(0) &&
	       (policy.search_policy.case_mode == .Smart ||
	        policy.search_policy.case_mode == .Sensitive ||
	        policy.search_policy.case_mode == .Insensitive) &&
	       (policy.search_policy.boundary_mode == .Unrestricted ||
	        policy.search_policy.boundary_mode == .Word ||
	        policy.search_policy.boundary_mode == .Symbol) &&
	       (policy.search_policy.whitespace_mode == .Exact ||
	        policy.search_policy.whitespace_mode == .Flexible) &&
	       search.limits_are_valid(policy.search_limits) &&
	       (policy.replacement_policy.case_preservation == .None ||
	        policy.replacement_policy.case_preservation == .Smart) &&
	       search.replacement_limits_are_valid(policy.replacement_limits) &&
	       replace_all_limits_are_valid(policy.replace_all_limits)
}

@(private)
search_capability_copy_texts :: proc(
	result: ^Search_Session_Copy,
	pattern, successful, replacement: string,
) -> bool {
	ok: bool
	result.pattern, ok = search_capability_copy_text(pattern, result.allocator)
	if !ok {
		return false
	}
	result.last_successful_pattern, ok = search_capability_copy_text(successful, result.allocator)
	if !ok {
		return false
	}
	result.replacement, ok = search_capability_copy_text(replacement, result.allocator)
	return ok
}

@(private)
search_capability_copy_text :: proc(
	value: string,
	allocator: runtime.Allocator,
) -> ([]byte, bool) {
	copied, allocation_error := make([]byte, len(value), allocator)
	if allocation_error != nil {
		return nil, false
	}
	copy(copied, value)
	return copied, true
}

@(private)
search_capability_copy_occurrences :: proc(
	result: ^Search_Session_Copy,
	occurrences: []search.Occurrence,
	captures: []search.Capture,
	occurrence_limit, capture_limit: u32,
) -> (bool, Failure_Context) {
	if len(occurrences) == 0 {
		result.has_current = false
		result.current_index = 0
		return true, {}
	}
	count := min(len(occurrences), int(occurrence_limit))
	start := 0
	if result.has_current {
		current := int(result.current_index)
		start = max(0, current - count / 2)
		start = min(start, len(occurrences) - count)
	}
	capture_count: u64
	for occurrence in occurrences[start:start + count] {
		capture_count += u64(occurrence.capture_count)
	}
	if capture_count > u64(capture_limit) {
		failure := search_capability_failure(.Inspection_Limit)
		failure.limit = u64(capture_limit)
		failure.actual = capture_count
		return false, failure
	}
	result.occurrences, _ = make([]search.Occurrence, count, result.allocator)
	if result.occurrences == nil && count > 0 {
		return false, search_capability_failure(.Temporary_Memory_Limit)
	}
	result.captures, _ = make([]search.Capture, int(capture_count), result.allocator)
	if result.captures == nil && capture_count > 0 {
		return false, search_capability_failure(.Temporary_Memory_Limit)
	}
	next_capture := 0
	for occurrence, index in occurrences[start:start + count] {
		copied := occurrence
		copied.first_capture = u32(next_capture)
		result.occurrences[index] = copied
		first := int(occurrence.first_capture)
		last := first + int(occurrence.capture_count)
		copy(result.captures[next_capture:], captures[first:last])
		next_capture += int(occurrence.capture_count)
	}
	if result.has_current {
		result.current_index = u32(int(result.current_index) - start)
		result.current = result.occurrences[result.current_index]
	}
	return true, {}
}

@(private)
search_capability_command_is_admitted :: proc(route: Native_Route) -> bool {
	#partial switch route {
	case .ISearch_Forward, .ISearch_Backward, .ISearch_Forward_Regexp,
	     .ISearch_Backward_Regexp, .Query_Replace, .Query_Replace_Regexp,
	     .Replace_String, .Replace_Regexp:
		return true
	}
	return false
}

@(private)
search_capability_command_pattern :: proc(route: Native_Route) -> (search.Pattern_Kind, search.Direction) {
	kind := search.Pattern_Kind.Literal
	direction := search.Direction.Forward
	if route == .ISearch_Forward_Regexp || route == .ISearch_Backward_Regexp ||
	   route == .Query_Replace_Regexp || route == .Replace_Regexp {
		kind = .Regular_Expression
	}
	if route == .ISearch_Backward || route == .ISearch_Backward_Regexp {
		direction = .Backward
	}
	return kind, direction
}

@(private)
search_capability_view_failure :: proc(view_failure: editor_view.Failure_Context) -> Failure_Context {
	failure := native_view_failure({}, view_failure)
	failure.search_capability_code = .Session_Unavailable
	return failure
}

@(private)
search_capability_failure :: proc(code: Search_Capability_Failure_Code) -> Failure_Context {
	return Failure_Context{code = .Capability_Failure, search_capability_code = code}
}
