// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* profile_activation_modal_visual_kind identifies the active persistent visual state. */
profile_activation_modal_visual_kind :: proc(
	activation: ^Profile_Activation,
) -> Modal_Visual_Kind {
	if activation == nil || !activation.ready || activation.closed do return .None
	switch activation.active_state.name {
	case "Visual Character": return .Character
	case "Visual Line":      return .Line
	case "Visual Block":     return .Block
	case:                     return .None
	}
}

/* profile_activation_modal_visual_begin retains active-end intent for one canonical region. */
profile_activation_modal_visual_begin :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
	kind: Modal_Visual_Kind,
	anchor_offset, cursor_offset: u64,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_visual_failure(request)
	if kind != .Character && kind != .Line && kind != .Block {
		failure.code = .Invalid_Input
		activation.latest_rejection = failure
		return false, failure
	}
	if profile_activation_modal_visual_kind(activation) != kind {
		failure.code = .Invalid_Interaction_State
		activation.latest_rejection = failure
		return false, failure
	}
	if !modal_navigation_request_is_current(activation, request) {
		activation.modal_visual = {}
		failure.code = .Stale_Interaction_State
		activation.latest_rejection = failure
		return false, failure
	}
	activation.modal_visual = Modal_Visual_State {
		active = true,
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
		anchor_offset = anchor_offset,
		cursor_offset = cursor_offset,
	}
	activation.latest_rejection = {}
	return true, {}
}

/* profile_activation_modal_visual_update advances only one current visual selection. */
profile_activation_modal_visual_update :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
	cursor_offset: u64,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_visual_failure(request)
	visual := activation.modal_visual
	if !visual.active || !modal_navigation_request_is_current(activation, request) ||
	   visual.profile != request.profile || visual.state != request.state ||
	   visual.catalog_generation != request.catalog_generation ||
	   visual.snapshot_generation != request.snapshot_generation ||
	   visual.ctx != request.ctx || visual.view_identity != request.view_identity ||
	   visual.view_generation != request.view_generation ||
	   visual.buffer_identity != request.buffer_identity ||
	   visual.buffer_revision != request.buffer_revision {
		activation.modal_visual = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return false, failure
	}
	activation.modal_visual.cursor_offset = cursor_offset
	activation.latest_rejection = {}
	return true, {}
}

/* profile_activation_modal_visual_rebase adopts one canonical region as visual endpoints. */
profile_activation_modal_visual_rebase :: proc(
	activation: ^Profile_Activation,
	request: Modal_Navigation_Request,
	anchor_offset, cursor_offset: u64,
) -> (ok: bool, failure: Failure_Context) {
	updated, update_failure := profile_activation_modal_visual_update(
		activation, request, cursor_offset,
	)
	if !updated do return false, update_failure
	activation.modal_visual.anchor_offset = anchor_offset
	return true, {}
}

/* profile_activation_modal_visual_exchange swaps only canonical active-end intent. */
profile_activation_modal_visual_exchange :: proc(activation: ^Profile_Activation) -> bool {
	if activation == nil || !activation.ready || activation.closed ||
	   !activation.modal_visual.active {
		return false
	}
	activation.modal_visual.anchor_offset, activation.modal_visual.cursor_offset =
		activation.modal_visual.cursor_offset, activation.modal_visual.anchor_offset
	return true
}

/* profile_activation_modal_visual_inspect copies active visual endpoint intent. */
profile_activation_modal_visual_inspect :: proc(
	activation: ^Profile_Activation,
) -> (state: Modal_Visual_State, ok: bool) {
	if activation == nil || !activation.ready || activation.closed ||
	   !activation.modal_visual.active {
		return {}, false
	}
	return activation.modal_visual, true
}

/* profile_activation_modal_visual_clear releases active visual endpoint intent. */
profile_activation_modal_visual_clear :: proc(activation: ^Profile_Activation) -> bool {
	if activation == nil || !activation.ready || activation.closed do return false
	activation.modal_visual = {}
	return true
}

@(private)
modal_visual_failure :: proc(request: Modal_Navigation_Request) -> Failure_Context {
	return Failure_Context {
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
	}
}
