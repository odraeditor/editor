// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_reference

Completion_State :: enum u8 {
	Idle,
	Requesting,
	Cancelling,
	Complete,
	Failed,
}

Completion_Request :: struct {
	id:                 u64,
	generation:         u64,
	session_generation: u64,
	binding_generation: u64,
	revision:           u64,
}

Completion :: struct {
	state:              Completion_State,
	request:            Completion_Request,
	incomplete:         bool,
	candidate_count:    u32,
	completion_enabled: bool,
}

completion_start :: proc(
	model: Completion,
	request: Completion_Request,
) -> (Completion, bool) {
	if !model.completion_enabled || model.state == .Requesting || model.state == .Cancelling ||
	   request.id == 0 || request.generation == 0 || request.session_generation == 0 ||
	   request.binding_generation == 0 || request.revision == 0 {
		return model, false
	}
	next := model
	next.state = .Requesting
	next.request = request
	next.incomplete = false
	next.candidate_count = 0
	return next, true
}

completion_cancel :: proc(model: Completion) -> (Completion, bool) {
	if model.state != .Requesting {
		return model, false
	}
	next := model
	next.state = .Cancelling
	return next, true
}

completion_cancelled :: proc(model: Completion) -> (Completion, bool) {
	if model.state != .Cancelling {
		return model, false
	}
	next := model
	next.state = .Idle
	return next, true
}

completion_publish :: proc(
	model: Completion,
	request: Completion_Request,
	candidates: u32,
	incomplete: bool,
) -> (Completion, bool) {
	if model.state != .Requesting || model.request != request || candidates > MAX_CANDIDATES {
		return model, false
	}
	next := model
	next.state = .Complete
	next.candidate_count = candidates
	next.incomplete = incomplete
	return next, true
}

completion_restart :: proc(model: Completion, session_generation: u64) -> Completion {
	next := model
	if model.request.session_generation != 0 && model.request.session_generation != session_generation {
		next.state = .Idle
		next.request = {}
		next.incomplete = false
		next.candidate_count = 0
	}
	return next
}
