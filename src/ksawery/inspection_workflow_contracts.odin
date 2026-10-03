// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:strings"

/* MAX_INSPECTION_ITEMS bounds one stash, worktree, blame, or reflog observation. */
MAX_INSPECTION_ITEMS :: u32(2_048)
/* MAX_INSPECTION_TEXT_BYTES bounds one copied target or display value. */
MAX_INSPECTION_TEXT_BYTES :: 4 * KIBIBYTE
/* MAX_INSPECTION_OUTPUT_BYTES bounds one retained family observation. */
MAX_INSPECTION_OUTPUT_BYTES :: 2 * MEBIBYTE

/* Inspection_Generation identifies one immutable auxiliary repository observation. */
Inspection_Generation :: distinct u64
/* Inspection_Item_ID identifies one semantic item within an observation generation. */
Inspection_Item_ID :: distinct u32

/* Inspection_Family identifies one familiar Ksawery repository workflow family. */
Inspection_Family :: enum u8 {
	Invalid,
	Stash,
	Worktree,
	Blame,
	Reflog,
}

/* Inspection_Action identifies one closed operation inside an inspection family. */
Inspection_Action :: enum u8 {
	Invalid,
	List,
	Create,
	Inspect,
	Apply,
	Pop,
	Branch,
	Drop,
	Visit,
	Lock,
	Unlock,
	Prune,
	Remove,
}

/* Inspection_Text owns one bounded UTF-8-compatible byte sequence without NULs. */
Inspection_Text :: struct {
	bytes:  [MAX_INSPECTION_TEXT_BYTES]u8,
	length: u32,
}

/* Inspection_Request binds one family action to exact repository evidence. */
Inspection_Request :: struct {
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	family_generation:      Inspection_Generation,
	family:                 Inspection_Family,
	action:                 Inspection_Action,
	target:                 Inspection_Text,
	secondary:              Inspection_Text,
	evidence:               Inspection_Text,
	confirmed:              bool,
	limits:                 Process_Limits,
}

/* Inspection_Item describes one immutable selectable family result. */
Inspection_Item :: struct {
	id:        Inspection_Item_ID,
	identity:  Inspection_Text,
	summary:   Inspection_Text,
	secondary: Inspection_Text,
}

/* Inspection_Observation owns one parsed immutable family result. */
Inspection_Observation :: struct {
	state: rawptr,
}

/* Inspection_Observation_Descriptor reports exact retained family evidence. */
Inspection_Observation_Descriptor :: struct {
	repository:             Repository_Context,
	status_generation:      Observation_Generation,
	generation:             Inspection_Generation,
	family:                 Inspection_Family,
	item_count:             u32,
	retained_bytes:         u64,
	truncated:              bool,
}

/* Inspection_Target identifies one exact item in one immutable family observation. */
Inspection_Target :: struct {
	generation: Inspection_Generation,
	item:       Inspection_Item_ID,
	identity:   Inspection_Text,
}

/* inspection_text_assign copies one bounded nonempty text value. */
inspection_text_assign :: proc(value: ^Inspection_Text, text: string) -> bool {
	if value == nil do return false
	value^ = {}
	if len(text) == 0 || len(text) > len(value.bytes) || strings.index_byte(text, 0) >= 0 {
		return false
	}
	copy(value.bytes[:len(text)], transmute([]u8)text)
	value.length = u32(len(text))
	return true
}

/* inspection_text_string returns one borrowed valid text value. */
inspection_text_string :: proc(value: ^Inspection_Text) -> string {
	if value == nil || !inspection_text_is_valid(value^, false) do return ""
	return string(value.bytes[:value.length])
}

/* inspection_text_is_valid checks one bounded copied value. */
inspection_text_is_valid :: proc(value: Inspection_Text, empty_allowed := true) -> bool {
	if value.length == 0 do return empty_allowed
	if int(value.length) > len(value.bytes) do return false
	owned := value
	return strings.index_byte(string(owned.bytes[:owned.length]), 0) < 0
}

/* inspection_action_is_mutating identifies actions that can change repository or filesystem state. */
inspection_action_is_mutating :: proc(action: Inspection_Action) -> bool {
	switch action {
	case .Create, .Apply, .Pop, .Branch, .Drop, .Lock, .Unlock, .Prune, .Remove:
		return true
	case .Invalid, .List, .Inspect, .Visit:
		return false
	}
	return false
}

/* inspection_request_is_valid admits only family-compatible, bounded, confirmed operations. */
inspection_request_is_valid :: proc(request: Inspection_Request) -> bool {
	if !repository_context_is_valid(request.repository) ||
	   request.observation_generation == Observation_Generation(0) ||
	   request.family == .Invalid || request.action == .Invalid ||
	   !process_limits_are_valid(request.limits) ||
	   !inspection_text_is_valid(request.target) ||
	   !inspection_text_is_valid(request.secondary) ||
	   !inspection_text_is_valid(request.evidence) ||
	   (inspection_action_is_mutating(request.action) && !request.confirmed) {
		return false
	}
	switch request.family {
	case .Stash:
		switch request.action {
		case .List:
			return request.family_generation == Inspection_Generation(0) &&
			       request.target == {} && request.secondary == {} && request.evidence == {} && !request.confirmed
		case .Create:
			return request.family_generation != Inspection_Generation(0) &&
			       request.target != {} && request.secondary == {} && request.evidence == {}
		case .Inspect, .Apply, .Pop, .Drop:
			return request.family_generation != Inspection_Generation(0) &&
			       request.target != {} && request.secondary == {} && request.evidence != {}
		case .Branch:
			return request.family_generation != Inspection_Generation(0) &&
			       request.target != {} && request.secondary != {} && request.evidence != {}
		case .Invalid, .Visit, .Lock, .Unlock, .Prune, .Remove:
			return false
		}
	case .Worktree:
		switch request.action {
		case .List:
			return request.family_generation == Inspection_Generation(0) &&
			       request.target == {} && request.secondary == {} && request.evidence == {}
		case .Prune:
			return request.family_generation != Inspection_Generation(0) &&
			       request.target == {} && request.secondary == {} && request.evidence == {}
		case .Create:
			target := request.target
			return request.family_generation != Inspection_Generation(0) &&
			       request.target != {} && request.secondary != {} && request.evidence == {} &&
			       target.bytes[0] == '/'
		case .Visit, .Lock, .Unlock, .Remove:
			return request.family_generation != Inspection_Generation(0) &&
			       request.target != {} && request.secondary == {} && request.evidence != {}
		case .Invalid, .Inspect, .Apply, .Pop, .Branch, .Drop:
			return false
		}
	case .Blame:
		if request.evidence != {} do return false
		if request.action == .Inspect {
			return request.family_generation == Inspection_Generation(0) &&
			       request.target != {} && request.secondary == {} && !request.confirmed
		}
		return request.action == .Visit && request.family_generation != Inspection_Generation(0) &&
		       request.target != {} && request.secondary == {} && !request.confirmed
	case .Reflog:
		if request.evidence != {} do return false
		if request.action == .List {
			return request.family_generation == Inspection_Generation(0) &&
			       request.target == {} && request.secondary == {} && !request.confirmed
		}
		return request.action == .Visit && request.family_generation != Inspection_Generation(0) && request.target != {} &&
		       request.secondary == {} && !request.confirmed
	case .Invalid:
		return false
	}
	return false
}

/* inspection_target_is_current rejects selections from replaced observations. */
inspection_target_is_current :: proc(
	target: Inspection_Target,
	descriptor: Inspection_Observation_Descriptor,
) -> bool {
	return target.generation != Inspection_Generation(0) &&
	       target.generation == descriptor.generation && target.item != Inspection_Item_ID(0) &&
	       inspection_text_is_valid(target.identity, false)
}
