// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package completion_reference provides an independent completion lifecycle oracle.
package completion_reference

import "base:runtime"

MAX_CANDIDATES :: 16

Trigger :: enum u8 {
	Invalid,
	Explicit,
	Identifier,
	Character,
	Incomplete,
}

Request_State :: enum u8 {
	Invalid,
	Prepared,
	Sent,
	Completed,
	Cancelled,
	Failed,
}

Session_State :: enum u8 {
	Invalid,
	Requesting,
	Ready,
	Empty,
	Dismissed,
	Retired,
}

Context :: struct {
	document:            u64,
	revision:            u64,
	view:                u64,
	provider_generation: u64,
}

Request :: struct {
	id:         u64,
	generation: u64,
	scope:      Context,
	trigger:    Trigger,
	state:      Request_State,
}

Candidate :: struct {
	id: u64,
}

Session :: struct {
	id:                 u64,
	generation:         u64,
	request:            Request,
	state:              Session_State,
	candidates:         []Candidate,
	selected_candidate: u64,
	allocator:          runtime.Allocator,
}

start :: proc(
	session: ^Session,
	id: u64,
	generation: u64,
	request: Request,
	allocator := context.allocator,
) -> bool {
	if session == nil || session.state != .Invalid || id == 0 || generation == 0 ||
	   request.id == 0 || request.generation == 0 || request.state != .Prepared ||
	   request.scope.document == 0 || request.scope.revision == 0 ||
	   request.scope.view == 0 || request.scope.provider_generation == 0 ||
	   request.trigger == .Invalid || allocator.procedure == nil {
		return false
	}
	session^ = {
		id = id,
		generation = generation,
		request = request,
		state = .Requesting,
		allocator = allocator,
	}
	return true
}

send :: proc(session: ^Session) -> bool {
	if session == nil || session.state != .Requesting || session.request.state != .Prepared {
		return false
	}
	session.request.state = .Sent
	return true
}

publish :: proc(
	session: ^Session,
	request_id: u64,
	request_generation: u64,
	scope: Context,
	candidates: []Candidate,
) -> bool {
	if session == nil || session.state != .Requesting || session.request.state != .Sent ||
	   session.request.id != request_id || session.request.generation != request_generation ||
	   session.request.scope != scope || len(candidates) > MAX_CANDIDATES {
		return false
	}
	if len(candidates) > 0 {
		copied, allocation_error := make([]Candidate, len(candidates), session.allocator)
		if allocation_error != nil {
			return false
		}
		copy(copied, candidates)
		session.candidates = copied
		session.selected_candidate = copied[0].id
		session.state = .Ready
	} else {
		session.state = .Empty
	}
	session.request.state = .Completed
	return true
}

cancel :: proc(session: ^Session) -> bool {
	if session == nil || session.state == .Invalid || session.state == .Retired {
		return false
	}
	if session.request.state == .Prepared || session.request.state == .Sent {
		session.request.state = .Cancelled
	}
	session.state = .Dismissed
	return true
}

replace :: proc(session: ^Session, request: Request) -> bool {
	if session == nil || session.state == .Invalid || session.state == .Retired ||
	   request.id == 0 || request.generation <= session.request.generation ||
	   request.state != .Prepared {
		return false
	}
	if session.candidates != nil {
		delete(session.candidates, session.allocator)
	}
	session.candidates = nil
	session.selected_candidate = 0
	if session.request.state == .Prepared || session.request.state == .Sent {
		session.request.state = .Cancelled
	}
	session.request = request
	session.state = .Requesting
	return true
}

retire :: proc(session: ^Session) -> bool {
	if session == nil || session.state == .Invalid || session.state == .Retired {
		return false
	}
	if session.candidates != nil {
		delete(session.candidates, session.allocator)
	}
	session.candidates = nil
	session.selected_candidate = 0
	if session.request.state == .Prepared || session.request.state == .Sent {
		session.request.state = .Cancelled
	}
	session.state = .Retired
	return true
}
