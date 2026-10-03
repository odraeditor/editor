// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* modal_operator_compose consumes one bounded operator and target grammar. */
modal_operator_compose :: proc(
	activation: ^Profile_Activation,
	request: Modal_Operator_Request,
) -> (result: Modal_Operator_Result, ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_operator_failure(request)
	if !modal_operator_request_is_current(activation, request) {
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
	if pending.kind != .None && !modal_operator_pending_matches(pending, request) {
		activation.modal_pending = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return {}, false, failure
	}
	if modal_navigation_cancel_input(request.input) {
		activation.modal_pending = {}
		activation.latest_rejection = {}
		return Modal_Operator_Result{disposition = .Cancelled}, true, {}
	}
	scalar, scalar_ok := modal_navigation_plain_scalar(request.input)
	if pending.kind == .Named_Slot {
		if !scalar_ok {
			return modal_operator_reject(activation, failure, .Invalid_Input, 0, 0)
		}
		sequence := modal_pending_sequence(pending)
		if !modal_sequence_append(&sequence, request.input.stroke) {
			return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_PENDING_STROKES, u64(sequence.stroke_count) + 1)
		}
		if pending.named_slot_length == 0 {
			if len(request.input.text) == 0 || len(request.input.text) > MAX_MODAL_PENDING_TEXT_BYTES {
				return modal_operator_reject(
					activation, failure, .Invalid_Input,
					MAX_MODAL_PENDING_TEXT_BYTES, u64(len(request.input.text)),
				)
			}
			started, begin_failure := profile_activation_modal_pending_begin(
				activation,
				modal_named_slot_pending_request(
					request,
					sequence,
					pending.count,
					pending.operator_count_explicit,
					request.input.text,
					pending.operator_origin,
				),
			)
			if !started do return {}, false, begin_failure
			return Modal_Operator_Result {
				disposition = .Pending,
				count = pending.count,
				count_explicit = pending.operator_count_explicit,
				sequence = sequence,
				capture = modal_operator_capture(request, pending.operator_origin),
			}, true, {}
		}
		slot := string(pending.named_slot[:pending.named_slot_length])
		if scalar == 'p' || scalar == 'P' {
			target := Modal_Operator_Target_Kind.Named_Slot_After
			if scalar == 'P' do target = .Named_Slot_Before
			return modal_operator_ready(
				activation, request,
				Modal_Pending_State {
					operator = .Yank,
					count = pending.count,
					operator_count_explicit = pending.operator_count_explicit,
					operator_origin = pending.operator_origin,
					named_slot = pending.named_slot,
					named_slot_length = pending.named_slot_length,
				},
				sequence, target, .None, "",
			)
		}
		operator, operator_ok := modal_operator_prefix(scalar)
		if !operator_ok ||
		   (operator != .Delete && operator != .Change && operator != .Yank) {
			return modal_operator_reject(activation, failure, .Invalid_Input, 0, u64(scalar))
		}
		started, begin_failure := profile_activation_modal_pending_begin(
			activation,
			modal_operator_pending_request(
				request, sequence, operator, .Target, pending.count, 0,
				pending.operator_count_explicit, false, .None, "", slot,
			),
		)
		if !started do return {}, false, begin_failure
		if profile_activation_modal_visual_kind(activation) != .None {
			return modal_operator_ready(
				activation, request, activation.modal_pending, sequence,
				.Active_Selection, .None, "",
			)
		}
		return Modal_Operator_Result {
			disposition = .Pending,
			operator = operator,
			count = pending.count,
			count_explicit = pending.operator_count_explicit,
			sequence = sequence,
			capture = modal_operator_capture(request, pending.operator_origin),
		}, true, {}
	}
	if pending.kind != .Operator {
		if !scalar_ok {
			return Modal_Operator_Result{disposition = .Pass_Through}, true, {}
		}
		if pending.kind != .None && pending.kind != .Count {
			return Modal_Operator_Result{disposition = .Pass_Through}, true, {}
		}
		if scalar >= '0' && scalar <= '9' && (scalar != '0' || pending.kind == .Count) {
			navigation, composed, count_failure := modal_navigation_compose(
				activation,
				modal_operator_navigation_request(request),
			)
			if !composed do return {}, false, count_failure
			return Modal_Operator_Result {
				disposition = .Pending,
				count = navigation.count,
				count_explicit = true,
				capture = modal_operator_capture(request, request.point_offset),
			}, true, {}
		}
		if scalar == '"' {
			count := u64(1)
			sequence := Key_Sequence{}
			count_explicit := false
			origin := request.point_offset
			if pending.kind == .Count {
				count = pending.count
				sequence = modal_pending_sequence(pending)
				count_explicit = true
				origin = pending.operator_origin
			}
			if !modal_sequence_append(&sequence, request.input.stroke) {
				return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_PENDING_STROKES, u64(sequence.stroke_count) + 1)
			}
			started, begin_failure := profile_activation_modal_pending_begin(
				activation,
				modal_named_slot_pending_request(
					request, sequence, count, count_explicit, "", origin,
				),
			)
			if !started do return {}, false, begin_failure
			return Modal_Operator_Result {
				disposition = .Pending,
				count = count,
				count_explicit = count_explicit,
				sequence = sequence,
				capture = modal_operator_capture(request, origin),
			}, true, {}
		}
		standalone, standalone_target, standalone_ok := modal_standalone_operator(scalar)
		if standalone_ok {
			count := u64(1)
			sequence := Key_Sequence{}
			count_explicit := false
			if pending.kind == .Count {
				count = pending.count
				sequence = modal_pending_sequence(pending)
				count_explicit = true
			}
			if !modal_sequence_append(&sequence, request.input.stroke) {
				return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_PENDING_STROKES, u64(sequence.stroke_count) + 1)
			}
			return modal_operator_ready(
				activation,
				request,
				Modal_Pending_State {
					operator = standalone,
					count = count,
					operator_count_explicit = count_explicit,
					operator_origin = request.point_offset,
				},
				sequence,
				standalone_target,
				.None,
				"",
			)
		}
		operator, operator_ok := modal_operator_prefix(scalar)
		if !operator_ok {
			return Modal_Operator_Result{disposition = .Pass_Through}, true, {}
		}
		count := u64(1)
		sequence := Key_Sequence{}
		count_explicit := false
		if pending.kind == .Count {
			count = pending.count
			sequence = modal_pending_sequence(pending)
			count_explicit = true
		}
		if !modal_sequence_append(&sequence, request.input.stroke) {
			return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_PENDING_STROKES, u64(sequence.stroke_count) + 1)
		}
		if profile_activation_modal_visual_kind(activation) != .None &&
		   operator != .Replace {
			return modal_operator_ready(
				activation,
				request,
				Modal_Pending_State {
					operator = operator,
					count = count,
					operator_count_explicit = count_explicit,
					operator_origin = request.point_offset,
				},
				sequence,
				.Active_Selection,
				.None,
				"",
			)
		}
		stage := Modal_Operator_Stage.Target
		if operator == .Replace do stage = .Character_Target
		started, begin_failure := profile_activation_modal_pending_begin(
			activation,
			modal_operator_pending_request(
				request, sequence, operator, stage, count, 0,
				count_explicit, false, .None, "", "",
			),
		)
		if !started do return {}, false, begin_failure
		return Modal_Operator_Result {
			disposition = .Pending,
			operator = operator,
			count = count,
			count_explicit = count_explicit,
			sequence = sequence,
			capture = modal_operator_capture(request, request.point_offset),
		}, true, {}
	}
	sequence := modal_pending_sequence(pending)
	if !modal_sequence_append(&sequence, request.input.stroke) {
		return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_PENDING_STROKES, u64(sequence.stroke_count) + 1)
	}
	if !scalar_ok {
		if pending.operator_stage == .Target {
			target, target_ok := modal_operator_logical_target(request.input)
			if target_ok {
				return modal_operator_ready(activation, request, pending, sequence, target, .None, "")
			}
		}
		return modal_operator_reject(activation, failure, .Invalid_Input, 0, 0)
	}
	if pending.operator_stage == .Character_Target {
		if len(request.input.text) == 0 || len(request.input.text) > MAX_MODAL_PENDING_TEXT_BYTES {
			return modal_operator_reject(
				activation, failure, .Invalid_Input,
				MAX_MODAL_PENDING_TEXT_BYTES, u64(len(request.input.text)),
			)
		}
		if pending.operator == .Replace {
			return modal_operator_ready(
				activation, request, pending, sequence, .Next_Grapheme,
				.None, request.input.text,
			)
		}
		return modal_operator_ready(
			activation, request, pending, sequence, .Character_Target,
			pending.character_target, request.input.text,
		)
	}
	if pending.operator_stage == .Text_Object {
		target := Modal_Operator_Target_Kind.None
		if pending.text_length == 1 && pending.text[0] == 'i' {
			switch scalar {
			case 'w': target = .Inner_Word
			case 'p': target = .Inner_Paragraph
			}
		} else if pending.text_length == 1 && pending.text[0] == 'a' {
			switch scalar {
			case 'w': target = .Around_Word
			case 'p': target = .Around_Paragraph
			}
		}
		if target == .None {
			return modal_operator_reject(activation, failure, .Invalid_Input, 0, u64(scalar))
		}
		return modal_operator_ready(activation, request, pending, sequence, target, .None, "")
	}
	if pending.operator_stage == .Buffer_Start {
		if scalar != 'g' {
			return modal_operator_reject(activation, failure, .Invalid_Input, 0, u64(scalar))
		}
		return modal_operator_ready(activation, request, pending, sequence, .Buffer_Start, .None, "")
	}
	if pending.operator_stage != .Target {
		return modal_operator_reject(activation, failure, .Invalid_Input, 0, u64(pending.operator_stage))
	}
	if scalar >= '0' && scalar <= '9' && (scalar != '0' || pending.target_count_explicit) {
		digit := u64(scalar - '0')
		target_count := digit
		count_ok := digit > 0
		if pending.target_count_explicit {
			target_count, count_ok = modal_count_extend(pending.target_count, digit)
		}
		if !count_ok {
			return modal_operator_reject(activation, failure, .Sequence_Limit, MAX_MODAL_COUNT, pending.target_count * 10 + digit)
		}
		return modal_operator_continue(
			activation, request, pending, sequence, .Target, target_count, true, .None, "",
		)
	}
	if scalar == modal_operator_scalar(pending.operator) {
		return modal_operator_ready(activation, request, pending, sequence, .Line, .None, "")
	}
	if scalar == 'i' || scalar == 'a' {
		text := "i"
		if scalar == 'a' do text = "a"
		return modal_operator_continue(
			activation, request, pending, sequence, .Text_Object,
			pending.target_count, pending.target_count_explicit, .None, text,
		)
	}
	if scalar == 'g' {
		return modal_operator_continue(
			activation, request, pending, sequence, .Buffer_Start,
			pending.target_count, pending.target_count_explicit, .None, "",
		)
	}
	character_target, character_prefix := modal_character_target_prefix(scalar)
	if character_prefix {
		return modal_operator_continue(
			activation, request, pending, sequence, .Character_Target,
			pending.target_count, pending.target_count_explicit, character_target, "",
		)
	}
	target, target_ok := modal_operator_movement_target(scalar)
	if !target_ok {
		return modal_operator_reject(activation, failure, .Invalid_Input, 0, u64(scalar))
	}
	character_target = .None
	if target == .Repeat_Character_Target {
		repeated, repeated_ok, repeat_failure := profile_activation_modal_character_search_repeat(
			activation,
			modal_operator_navigation_request(request),
			scalar == ',',
			1,
		)
		if !repeated_ok {
			activation.modal_pending = {}
			return {}, false, repeat_failure
		}
		character_target = repeated.character_target
		return modal_operator_ready(
			activation, request, pending, sequence, target, character_target,
			modal_navigation_result_text(&repeated),
		)
	}
	return modal_operator_ready(activation, request, pending, sequence, target, .None, "")
}

/* modal_operator_result_text borrows one completed character target. */
modal_operator_result_text :: proc(result: ^Modal_Operator_Result) -> string {
	if result == nil || result.text_length == 0 do return ""
	return string(result.text[:result.text_length])
}

/* modal_operator_result_named_slot borrows one completed named text slot. */
modal_operator_result_named_slot :: proc(result: ^Modal_Operator_Result) -> string {
	if result == nil || result.named_slot_length == 0 do return ""
	return string(result.named_slot[:result.named_slot_length])
}

/* profile_activation_modal_operator_execution_begin retains one prompt-bound operation. */
profile_activation_modal_operator_execution_begin :: proc(
	activation: ^Profile_Activation,
	operation: Modal_Operator_Result,
) -> bool {
	if activation == nil || !activation.ready || activation.closed ||
	   operation.disposition != .Ready || operation.operator == .None ||
	   operation.capture.profile != activation.active_profile ||
	   operation.capture.state != activation.active_state.identity ||
	   operation.capture.catalog_generation != activation.catalog_generation ||
	   operation.capture.snapshot_generation != activation.generation {
		return false
	}
	activation.modal_operator_execution = {
		active = true,
		operation = operation,
	}
	return true
}

/* profile_activation_modal_operator_execution_defer stores one checked source range. */
profile_activation_modal_operator_execution_defer :: proc(
	activation: ^Profile_Activation,
	start_offset, end_offset: u64,
	backward: bool,
) -> bool {
	if activation == nil || !activation.ready || activation.closed ||
	   !activation.modal_operator_execution.active || start_offset >= end_offset {
		return false
	}
	activation.modal_operator_execution.start_offset = start_offset
	activation.modal_operator_execution.end_offset = end_offset
	activation.modal_operator_execution.backward = backward
	activation.modal_operator_execution.deferred = true
	return true
}

/* profile_activation_modal_operator_execution_slot_generation_set binds one confirmed slot view. */
profile_activation_modal_operator_execution_slot_generation_set :: proc(
	activation: ^Profile_Activation,
	generation: u64,
) -> bool {
	if activation == nil || !activation.ready || activation.closed || generation == 0 ||
	   !activation.modal_operator_execution.active || !activation.modal_operator_execution.deferred {
		return false
	}
	activation.modal_operator_execution.slot_generation = generation
	return true
}

/* profile_activation_modal_operator_execution_inspect copies prompt-bound execution state. */
profile_activation_modal_operator_execution_inspect :: proc(
	activation: ^Profile_Activation,
) -> (Modal_Operator_Execution_State, bool) {
	if activation == nil || !activation.ready || activation.closed do return {}, false
	return activation.modal_operator_execution, true
}

/* profile_activation_modal_operator_execution_clear releases prompt-bound execution state. */
profile_activation_modal_operator_execution_clear :: proc(
	activation: ^Profile_Activation,
) -> bool {
	if activation == nil || !activation.ready || activation.closed do return false
	activation.modal_operator_execution = {}
	return true
}

@(private)
modal_operator_prefix :: proc(value: rune) -> (Modal_Operator_Kind, bool) {
	switch value {
	case 'd': return .Delete, true
	case 'c': return .Change, true
	case 'y': return .Yank, true
	case '>': return .Indent, true
	case '<': return .Outdent, true
	case 'r': return .Replace, true
	}
	return .None, false
}

@(private)
modal_operator_scalar :: proc(operator: Modal_Operator_Kind) -> rune {
	switch operator {
	case .Delete:  return 'd'
	case .Change:  return 'c'
	case .Yank:    return 'y'
	case .Indent:  return '>'
	case .Outdent: return '<'
	case .Replace: return 'r'
	case .None:    return 0
	}
	unreachable()
}

@(private)
modal_standalone_operator :: proc(
	value: rune,
) -> (Modal_Operator_Kind, Modal_Operator_Target_Kind, bool) {
	switch value {
	case 'D': return .Delete, .Line_End, true
	case 'C': return .Change, .Line_End, true
	case 'Y': return .Yank, .Line, true
	}
	return .None, .None, false
}

@(private)
modal_operator_movement_target :: proc(value: rune) -> (Modal_Operator_Target_Kind, bool) {
	switch value {
	case 'h': return .Previous_Grapheme, true
	case 'l': return .Next_Grapheme, true
	case 'j': return .Next_Line, true
	case 'k': return .Previous_Line, true
	case '0': return .Line_Start, true
	case '$': return .Line_End, true
	case '^': return .Line_First_Non_Whitespace, true
	case 'b': return .Previous_Word, true
	case 'w': return .Next_Word_Start, true
	case 'e': return .Word_End, true
	case 'G': return .Buffer_End, true
	case ';', ',': return .Repeat_Character_Target, true
	case '/': return .Search_Forward, true
	case '?': return .Search_Backward, true
	case 'n': return .Search_Next, true
	case 'N': return .Search_Previous, true
	}
	return .None, false
}

@(private)
modal_operator_logical_target :: proc(input: Input) -> (Modal_Operator_Target_Kind, bool) {
	if input.kind != .Key || input.stroke.modifiers != {} do return .None, false
	#partial switch input.stroke.kind {
	case .Left:  return .Previous_Grapheme, true
	case .Right: return .Next_Grapheme, true
	case .Up:    return .Previous_Line, true
	case .Down:  return .Next_Line, true
	case .Home:  return .Line_Start, true
	case .End:   return .Line_End, true
	case .Prior: return .Previous_Page, true
	case .Next:  return .Next_Page, true
	}
	return .None, false
}

@(private)
modal_operator_continue :: proc(
	activation: ^Profile_Activation,
	request: Modal_Operator_Request,
	pending: Modal_Pending_State,
	sequence: Key_Sequence,
	stage: Modal_Operator_Stage,
	target_count: u64,
	target_count_explicit: bool,
	character_target: Modal_Character_Target_Kind,
	text: string,
) -> (Modal_Operator_Result, bool, Failure_Context) {
	named_slot := pending.named_slot
	started, failure := profile_activation_modal_pending_begin(
		activation,
		modal_operator_pending_request(
			request, sequence, pending.operator, stage, pending.count,
			target_count, pending.operator_count_explicit,
			target_count_explicit, character_target, text,
			string(named_slot[:pending.named_slot_length]),
		),
	)
	if !started do return {}, false, failure
	return Modal_Operator_Result {
		disposition = .Pending,
		operator = pending.operator,
		count = pending.count,
		count_explicit = pending.operator_count_explicit || target_count_explicit,
		character_target = character_target,
		sequence = sequence,
		capture = modal_operator_capture(request, pending.operator_origin),
	}, true, {}
}

@(private)
modal_operator_ready :: proc(
	activation: ^Profile_Activation,
	request: Modal_Operator_Request,
	pending: Modal_Pending_State,
	sequence: Key_Sequence,
	target: Modal_Operator_Target_Kind,
	character_target: Modal_Character_Target_Kind,
	text: string,
) -> (Modal_Operator_Result, bool, Failure_Context) {
	target_count := u64(1)
	if pending.target_count_explicit do target_count = pending.target_count
	count, count_ok := modal_count_combine(pending.count, target_count)
	if !count_ok {
		return modal_operator_reject(
			activation, modal_operator_failure(request), .Sequence_Limit,
			MAX_MODAL_COUNT, pending.count * target_count,
		)
	}
	result := Modal_Operator_Result {
		disposition = .Ready,
		operator = pending.operator,
		target = target,
		count = count,
		count_explicit = pending.operator_count_explicit || pending.target_count_explicit,
		character_target = character_target,
		sequence = sequence,
		capture = modal_operator_capture(request, pending.operator_origin),
		text_length = u8(len(text)),
		named_slot = pending.named_slot,
		named_slot_length = pending.named_slot_length,
	}
	copy(result.text[:], transmute([]u8)text)
	activation.modal_pending = {}
	activation.latest_rejection = {}
	return result, true, {}
}

@(private)
modal_operator_reject :: proc(
	activation: ^Profile_Activation,
	failure: Failure_Context,
	code: Failure_Code,
	limit, actual: u64,
) -> (Modal_Operator_Result, bool, Failure_Context) {
	activation.modal_pending = {}
	rejection := failure
	rejection.code = code
	rejection.limit = limit
	rejection.actual = actual
	activation.latest_rejection = rejection
	return {}, false, rejection
}

@(private)
modal_operator_pending_request :: proc(
	request: Modal_Operator_Request,
	sequence: Key_Sequence,
	operator: Modal_Operator_Kind,
	stage: Modal_Operator_Stage,
	count, target_count: u64,
	count_explicit, target_count_explicit: bool,
	character_target: Modal_Character_Target_Kind,
	text: string,
	named_slot: string,
) -> Modal_Pending_Request {
	return Modal_Pending_Request {
		kind = .Operator,
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
		text = text,
		count = count,
		character_target = character_target,
		operator = operator,
		operator_stage = stage,
		target_count = target_count,
		operator_count_explicit = count_explicit,
		target_count_explicit = target_count_explicit,
		named_slot = named_slot,
	}
}

@(private)
modal_named_slot_pending_request :: proc(
	request: Modal_Operator_Request,
	sequence: Key_Sequence,
	count: u64,
	count_explicit: bool,
	name: string,
	origin: u64,
) -> Modal_Pending_Request {
	return Modal_Pending_Request {
		kind = .Named_Slot,
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		operator_origin = origin,
		sequence = sequence,
		count = count,
		operator_count_explicit = count_explicit,
		named_slot = name,
	}
}

@(private)
modal_operator_capture :: proc(
	request: Modal_Operator_Request,
	point_offset: u64,
) -> Modal_Operator_Capture {
	return Modal_Operator_Capture {
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		point_offset = point_offset,
	}
}

@(private)
modal_operator_request_is_current :: proc(
	activation: ^Profile_Activation,
	request: Modal_Operator_Request,
) -> bool {
	return modal_navigation_request_is_current(
		activation,
		Modal_Navigation_Request {
			profile = request.profile,
			state = request.state,
			catalog_generation = request.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			ctx = request.ctx,
			view_identity = request.view_identity,
			view_generation = request.view_generation,
			buffer_identity = request.buffer_identity,
			buffer_revision = request.buffer_revision,
			point_offset = request.point_offset,
			input = request.input,
		},
	)
}

@(private)
modal_operator_navigation_request :: proc(
	request: Modal_Operator_Request,
) -> Modal_Navigation_Request {
	return Modal_Navigation_Request {
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		point_offset = request.point_offset,
		input = request.input,
	}
}

@(private)
modal_operator_pending_matches :: proc(
	pending: Modal_Pending_State,
	request: Modal_Operator_Request,
) -> bool {
	return modal_pending_matches_request(
		pending,
		Modal_Navigation_Request {
			profile = request.profile,
			state = request.state,
			catalog_generation = request.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			ctx = request.ctx,
			view_identity = request.view_identity,
			view_generation = request.view_generation,
			buffer_identity = request.buffer_identity,
			buffer_revision = request.buffer_revision,
			point_offset = request.point_offset,
			input = request.input,
		},
	)
}

@(private)
modal_operator_failure :: proc(request: Modal_Operator_Request) -> Failure_Context {
	return Failure_Context {
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
	}
}
