// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* modal_navigation_compose consumes only bounded modal navigation prefixes. */
modal_navigation_compose :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
) -> (result: Modal_Navigation_Result, ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_navigation_failure(request)
	if !modal_navigation_request_is_current(activation, request) {
		activation.modal_pending = {}
		failure.code = .Stale_Interaction_State
		activation.latest_rejection = failure
		return {}, false, failure
	}
	if !input_is_valid(request.input) {
		activation.modal_pending = {}
		failure.code = .Invalid_Input
		activation.latest_rejection = failure
		return {}, false, failure
	}
	pending := activation.modal_pending
	if pending.kind != .None && !modal_pending_matches_request(pending, request) {
		activation.modal_pending = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return {}, false, failure
	}
	if modal_navigation_cancel_input(request.input) {
		activation.modal_pending = {}
		activation.latest_rejection = {}
		return Modal_Navigation_Result{disposition = .Cancelled}, true, {}
	}
	if pending.kind == .Character_Target {
		activation.modal_pending = {}
		if request.input.kind != .Key || request.input.stroke.kind != .Unicode_Scalar ||
		   len(request.input.text) == 0 || len(request.input.text) > MAX_MODAL_PENDING_TEXT_BYTES {
			failure.code = .Invalid_Input
			failure.limit = MAX_MODAL_PENDING_TEXT_BYTES
			failure.actual = u64(len(request.input.text))
			activation.latest_rejection = failure
			return {}, false, failure
		}
		result = Modal_Navigation_Result {
			disposition = .Character_Target,
			count = pending.count,
			count_explicit = pending.stroke_count > 1,
			character_target = pending.character_target,
			text_length = u8(len(request.input.text)),
		}
		copy(result.text[:], transmute([]u8)request.input.text)
		activation.latest_rejection = {}
		return result, true, {}
	}
	scalar, scalar_ok := modal_navigation_plain_scalar(request.input)
	if !scalar_ok {
		return modal_navigation_pass_through(activation, pending), true, {}
	}
	if scalar >= '0' && scalar <= '9' && (scalar != '0' || pending.kind == .Count) {
		count := u64(scalar - '0')
		sequence := Key_Sequence{}
		if pending.kind == .Count {
			count, ok = modal_count_extend(pending.count, count)
			sequence = modal_pending_sequence(pending)
		} else {
			ok = count > 0
		}
		if !ok || !modal_sequence_append(&sequence, request.input.stroke) {
			activation.modal_pending = {}
			failure.code = .Sequence_Limit
			failure.limit = MAX_MODAL_COUNT
			failure.actual = pending.count * 10 + u64(scalar - '0')
			activation.latest_rejection = failure
			return {}, false, failure
		}
		started, begin_failure := profile_activation_modal_pending_begin(
			activation,
			modal_navigation_pending_request(request, .Count, sequence, count, .None),
		)
		if !started do return {}, false, begin_failure
		return Modal_Navigation_Result {
			disposition = .Pending,
			count = count,
			count_explicit = true,
		}, true, {}
	}
	character_target, target_prefix := modal_character_target_prefix(scalar)
	if target_prefix {
		count := u64(1)
		sequence := Key_Sequence{}
		if pending.kind == .Count {
			count = pending.count
			sequence = modal_pending_sequence(pending)
		}
		if !modal_sequence_append(&sequence, request.input.stroke) {
			activation.modal_pending = {}
			failure.code = .Sequence_Limit
			failure.limit = MAX_MODAL_PENDING_STROKES
			failure.actual = u64(sequence.stroke_count) + 1
			activation.latest_rejection = failure
			return {}, false, failure
		}
		started, begin_failure := profile_activation_modal_pending_begin(
			activation,
			modal_navigation_pending_request(
				request,
				.Character_Target,
				sequence,
				count,
				character_target,
			),
		)
		if !started do return {}, false, begin_failure
		return Modal_Navigation_Result {
			disposition = .Pending,
			count = count,
			count_explicit = pending.kind == .Count,
			character_target = character_target,
		}, true, {}
	}
	if scalar == ';' || scalar == ',' {
		count := u64(1)
		if pending.kind == .Count do count = pending.count
		activation.modal_pending = {}
		return profile_activation_modal_character_search_repeat(
			activation,
			request,
			scalar == ',',
			count,
		)
	}
	return modal_navigation_pass_through(activation, pending), true, {}
}

/* modal_navigation_result_text borrows one result target for immediate dispatch. */
modal_navigation_result_text :: proc(result: ^Modal_Navigation_Result) -> string {
	if result == nil || result.text_length == 0 do return ""
	return string(result.text[:result.text_length])
}

/* modal_count_combine multiplies operator and movement counts within one bound. */
modal_count_combine :: proc(operator_count, movement_count: u64) -> (u64, bool) {
	if operator_count == 0 || movement_count == 0 ||
	   operator_count > MAX_MODAL_COUNT / movement_count {
		return 0, false
	}
	return operator_count * movement_count, true
}

/* profile_activation_modal_character_search_confirm records one admitted target. */
profile_activation_modal_character_search_confirm :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
	character_target: Modal_Character_Target_Kind,
	text: string,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_navigation_failure(request)
	if !modal_navigation_request_is_current(activation, request) {
		failure.code = .Stale_Interaction_State
		activation.latest_rejection = failure
		return false, failure
	}
	if character_target == .None || len(text) == 0 || len(text) > MAX_MODAL_PENDING_TEXT_BYTES {
		failure.code = .Invalid_Input
		failure.limit = MAX_MODAL_PENDING_TEXT_BYTES
		failure.actual = u64(len(text))
		activation.latest_rejection = failure
		return false, failure
	}
	state := Modal_Character_Search_State {
		valid = true,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		character_target = character_target,
		text_length = u8(len(text)),
	}
	copy(state.text[:], transmute([]u8)text)
	activation.modal_character_search = state
	activation.latest_rejection = {}
	return true, {}
}

/* profile_activation_modal_character_search_inspect copies the repeat state. */
profile_activation_modal_character_search_inspect :: proc(
	activation: ^Profile_Activation,
) -> (state: Modal_Character_Search_State, ok: bool) {
	if activation == nil || !activation.ready || activation.closed do return {}, false
	return activation.modal_character_search, true
}

/* profile_activation_modal_character_search_repeat resolves same or opposite direction. */
profile_activation_modal_character_search_repeat :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
	opposite: bool,
	count: u64,
) -> (result: Modal_Navigation_Result, ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_navigation_failure(request)
	state := activation.modal_character_search
	if !state.valid || count == 0 || count > MAX_MODAL_COUNT {
		failure.code = .Invalid_Input
		failure.limit = MAX_MODAL_COUNT
		failure.actual = count
		activation.latest_rejection = failure
		return {}, false, failure
	}
	if !modal_navigation_request_is_current(activation, request) ||
	   state.profile != request.profile || state.state != request.state ||
	   state.ctx != request.ctx || state.view_identity != request.view_identity ||
	   state.view_generation != request.view_generation ||
	   state.buffer_identity != request.buffer_identity ||
	   state.buffer_revision != request.buffer_revision {
		activation.modal_character_search = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return {}, false, failure
	}
	character_target := state.character_target
	if opposite do character_target = modal_character_target_opposite(character_target)
	result = Modal_Navigation_Result {
		disposition = .Repeat_Character_Target,
		count = count,
		count_explicit = count != 1,
		character_target = character_target,
		text = state.text,
		text_length = state.text_length,
	}
	activation.latest_rejection = {}
	return result, true, {}
}

@(private)
modal_navigation_pass_through :: proc(
	activation: ^Profile_Activation,
	pending: Modal_Pending_State,
) -> Modal_Navigation_Result {
	count := u64(1)
	if pending.kind == .Count do count = pending.count
	activation.latest_rejection = {}
	return Modal_Navigation_Result {
		disposition = .Pass_Through,
		count = count,
		count_explicit = pending.kind == .Count,
	}
}

@(private)
modal_count_extend :: proc(count, digit: u64) -> (u64, bool) {
	if count == 0 || count > (MAX_MODAL_COUNT - digit) / 10 do return 0, false
	return count * 10 + digit, true
}

@(private)
modal_navigation_request_is_current :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
) -> bool {
	if !activation.ready || activation.closed ||
	   request.catalog_generation != activation.catalog_generation ||
	   request.snapshot_generation != activation.generation ||
	   request.profile != activation.active_profile ||
	   request.state != activation.active_state.identity {
		return false
	}
	snapshot := snapshot_data(&activation.snapshot)
	return snapshot != nil && snapshot.ctx == request.ctx &&
	       request.view_identity != 0 && request.view_generation != 0 &&
	       request.buffer_identity != 0
}

@(private)
modal_pending_matches_request :: proc(
	pending: Modal_Pending_State,
	request: Modal_Navigation_Request,
) -> bool {
	return pending.profile == request.profile && pending.state == request.state &&
	       pending.catalog_generation == request.catalog_generation &&
	       pending.snapshot_generation == request.snapshot_generation &&
	       pending.ctx == request.ctx && pending.view_identity == request.view_identity &&
	       pending.view_generation == request.view_generation &&
	       pending.buffer_identity == request.buffer_identity &&
	       pending.buffer_revision == request.buffer_revision &&
	       pending.operator_origin == request.point_offset
}

@(private)
modal_navigation_failure :: proc(request: Modal_Navigation_Request) -> Failure_Context {
	return Failure_Context {
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
	}
}

@(private)
modal_navigation_plain_scalar :: proc(input: Input) -> (rune, bool) {
	if input.kind != .Key || input.stroke.kind != .Unicode_Scalar ||
	   input.stroke.modifiers != {} {
		return 0, false
	}
	return input.stroke.scalar, true
}

@(private)
modal_navigation_cancel_input :: proc(input: Input) -> bool {
	if input.kind != .Key do return false
	if input.stroke.kind == .Escape && input.stroke.modifiers == {} do return true
	return input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == '[' &&
	       input.stroke.modifiers == {Modifier.Control}
}

@(private)
modal_character_target_prefix :: proc(value: rune) -> (Modal_Character_Target_Kind, bool) {
	switch value {
	case 'f': return .Find_Next, true
	case 'F': return .Find_Previous, true
	case 't': return .Till_Next, true
	case 'T': return .Till_Previous, true
	}
	return .None, false
}

@(private)
modal_character_target_opposite :: proc(
	kind: Modal_Character_Target_Kind,
) -> Modal_Character_Target_Kind {
	switch kind {
	case .Find_Next:     return .Find_Previous
	case .Find_Previous: return .Find_Next
	case .Till_Next:     return .Till_Previous
	case .Till_Previous: return .Till_Next
	case .None:          return .None
	}
	unreachable()
}

@(private)
modal_pending_sequence :: proc(pending: Modal_Pending_State) -> Key_Sequence {
	return Key_Sequence{strokes = pending.strokes, stroke_count = pending.stroke_count}
}

@(private)
modal_sequence_append :: proc(sequence: ^Key_Sequence, stroke: Key_Stroke) -> bool {
	assert(sequence != nil)
	if sequence.stroke_count >= MAX_MODAL_PENDING_STROKES do return false
	sequence.strokes[sequence.stroke_count] = stroke
	sequence.stroke_count += 1
	return true
}

@(private)
modal_navigation_pending_request :: proc(
	request: Modal_Navigation_Request,
	kind: Modal_Pending_Kind,
	sequence: Key_Sequence,
	count: u64,
	character_target: Modal_Character_Target_Kind,
) -> Modal_Pending_Request {
	return Modal_Pending_Request {
		kind = kind,
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		operator_origin = request.point_offset,
		sequence = sequence,
		count = count,
		character_target = character_target,
	}
}
