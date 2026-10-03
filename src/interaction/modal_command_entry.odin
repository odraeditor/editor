// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

/* profile_activation_modal_command_entry_begin retains one checked command surface. */
profile_activation_modal_command_entry_begin :: proc(
	activation: ^Profile_Activation,
	request: Modal_Command_Entry_Request,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	failure = modal_command_entry_failure(request)
	if !modal_command_entry_request_is_current(activation, request) {
		activation.modal_pending = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return false, failure
	}
	return profile_activation_modal_pending_begin(
		activation,
		Modal_Pending_Request {
			kind = .Command_Entry,
			profile = request.profile,
			state = request.state,
			catalog_generation = request.catalog_generation,
			snapshot_generation = request.snapshot_generation,
			ctx = request.ctx,
			view_identity = request.view_identity,
			view_generation = request.view_generation,
			buffer_identity = request.buffer_identity,
			buffer_revision = request.buffer_revision,
			sequence = request.sequence,
			command_entry_surface = request.surface,
		},
	)
}

/* profile_activation_modal_command_entry_claim validates and releases dispatch ownership. */
profile_activation_modal_command_entry_claim :: proc(
	activation: ^Profile_Activation,
	request: Modal_Command_Entry_Request,
) -> (claimed: bool, failure: Failure_Context) {
	assert(activation != nil)
	pending := activation.modal_pending
	if pending.kind != .Command_Entry {
		return false, {}
	}
	failure = modal_command_entry_failure(request)
	if !modal_command_entry_request_is_current(activation, request) ||
	   pending.profile != request.profile || pending.state != request.state ||
	   pending.catalog_generation != request.catalog_generation ||
	   pending.snapshot_generation != request.snapshot_generation ||
	   pending.ctx != request.ctx || pending.view_identity != request.view_identity ||
	   pending.view_generation != request.view_generation ||
	   pending.buffer_identity != request.buffer_identity ||
	   pending.buffer_revision != request.buffer_revision ||
	   pending.command_entry_surface != request.surface {
		activation.modal_pending = {}
		failure.code = .Stale_Context
		activation.latest_rejection = failure
		return false, failure
	}
	activation.modal_pending = {}
	activation.latest_rejection = {}
	return true, {}
}

@(private)
modal_command_entry_request_is_current :: proc(
	activation: ^Profile_Activation,
	request: Modal_Command_Entry_Request,
) -> bool {
	if activation == nil || !activation.ready || activation.closed ||
	   request.profile != activation.active_profile ||
	   request.state != activation.active_state.identity ||
	   request.catalog_generation != activation.catalog_generation ||
	   request.snapshot_generation != activation.generation ||
	   request.view_identity == 0 || request.view_generation == 0 ||
	   request.buffer_identity == 0 || request.surface.id == Command_Entry_Surface_ID(0) ||
	   request.surface.revision == Command_Entry_Surface_Revision(0) ||
	   !sequence_valid(request.sequence) {
		return false
	}
	snapshot := snapshot_data(&activation.snapshot)
	return snapshot != nil && snapshot.ctx == request.ctx
}

@(private)
modal_command_entry_failure :: proc(request: Modal_Command_Entry_Request) -> Failure_Context {
	return Failure_Context {
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		profile = request.profile,
		state = request.state,
		ctx = request.ctx,
	}
}
