// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* Presentation_Surface identifies the full-canvas repository surface supplying one semantic row. */
Presentation_Surface :: enum u8 {
	Invalid,
	Status,
	Sequence,
	Conflict,
	History,
	Refs,
	Process,
	Inspection,
}

/* Presentation_Subject identifies the repository meaning beneath any emphasis. */
Presentation_Subject :: enum u8 {
	Invalid,
	Repository,
	Branch,
	Remote,
	Tag,
	Tracking,
	Section,
	Path,
	Revision,
	Parent,
	Operation,
	Step,
	Conflict,
	Stage,
	Failure,
}

/* Presentation_Emphasis identifies the single highest-precedence visual meaning for one row. */
Presentation_Emphasis :: enum u8 {
	None,
	Destructive,
	Head,
	Marked,
	Current,
}

/* Presentation_Cue provides the non-color fallback for one emphasized semantic row. */
Presentation_Cue :: enum u8 {
	None,
	Destructive,
	Head,
	Marked,
	Current,
}

/* Presentation_State is the complete semantic input for one Status, History, Ref, or Process row. */
Presentation_State :: struct {
	surface:     Presentation_Surface,
	subject:     Presentation_Subject,
	current:     bool,
	marked:      bool,
	head:        bool,
	destructive: bool,
}

/* Presentation_Role composes a semantic base, visual precedence, and non-color fallback. */
Presentation_Role :: struct {
	surface:   Presentation_Surface,
	subject:   Presentation_Subject,
	emphasis: Presentation_Emphasis,
	cue:       Presentation_Cue,
}

/* presentation_state_is_valid checks surface-specific semantic-state combinations. */
presentation_state_is_valid :: proc(state: Presentation_State) -> bool {
	if state.surface == .Invalid || state.subject == .Invalid do return false
	if state.head && state.subject != .Revision && state.subject != .Branch do return false
	if state.marked && state.subject != .Path && state.subject != .Conflict && state.subject != .Revision && state.subject != .Branch &&
	   state.subject != .Remote && state.subject != .Tag {
		return false
	}
	if state.destructive && state.subject != .Path && state.subject != .Revision &&
	   state.subject != .Operation && state.subject != .Failure {
		return false
	}
	return true
}

/* presentation_role_compose selects the highest semantic emphasis and a matching non-color cue. */
presentation_role_compose :: proc(state: Presentation_State) -> (Presentation_Role, bool) {
	if !presentation_state_is_valid(state) do return {}, false
	emphasis := Presentation_Emphasis.None
	cue := Presentation_Cue.None
	if state.destructive {
		emphasis = .Destructive
		cue = .Destructive
	}
	if state.head {
		emphasis = .Head
		cue = .Head
	}
	if state.marked {
		emphasis = .Marked
		cue = .Marked
	}
	if state.current {
		emphasis = .Current
		cue = .Current
	}
	return Presentation_Role {
		surface = state.surface,
		subject = state.subject,
		emphasis = emphasis,
		cue = cue,
	}, true
}

/* presentation_role_is_valid checks a composed role and its required monochrome fallback. */
presentation_role_is_valid :: proc(role: Presentation_Role) -> bool {
	state := Presentation_State{surface = role.surface, subject = role.subject}
	switch role.emphasis {
	case .None:
		return presentation_state_is_valid(state) && role.cue == .None
	case .Destructive:
		state.destructive = true
		return presentation_state_is_valid(state) && role.cue == .Destructive
	case .Head:
		state.head = true
		return presentation_state_is_valid(state) && role.cue == .Head
	case .Marked:
		state.marked = true
		return presentation_state_is_valid(state) && role.cue == .Marked
	case .Current:
		state.current = true
		return presentation_state_is_valid(state) && role.cue == .Current
	}
	return false
}
