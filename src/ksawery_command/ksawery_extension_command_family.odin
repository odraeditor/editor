// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_command

import "../ksawery"
import "base:runtime"

/* Ksawery_Command_Family_Failure_Code classifies inert family-editing failures. */
Ksawery_Command_Family_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Invalid_Family,
	Invalid_Action,
	Invalid_Argument,
	Confirmation_Required,
	Confirmation_Sealed,
	Cancelled,
	Already_Submitted,
	Memory_Limit,
}

/* Ksawery_Command_Family_Failure retains the underlying repository-command rejection. */
Ksawery_Command_Family_Failure :: struct {
	code:     Ksawery_Command_Family_Failure_Code,
	argument: ksawery.Extension_Command_Argument_ID,
	contract: ksawery.Extension_Repository_Command_Failure,
}

/* Ksawery_Command_Argument_Entry owns one optional edited typed argument. */
Ksawery_Command_Argument_Entry :: struct {
	present: bool,
	value:   ksawery.Extension_Command_Argument_Value,
}

/* Ksawery_Command_Family_State owns one copied, effect-free family editing turn. */
Ksawery_Command_Family_State :: struct {
	family:             ksawery.Extension_Command_Family_Generation,
	command_context:    ksawery.Extension_Command_Context,
	request:            ksawery.Extension_Command_Request_ID,
	action:             ksawery.Extension_Command_Action_ID,
	entries:            []Ksawery_Command_Argument_Entry,
	submission:         []ksawery.Extension_Command_Argument_Value,
	argument_storage:   []ksawery.Extension_Command_Argument_Definition,
	choice_storage:     []ksawery.Extension_Command_Choice,
	action_storage:     []ksawery.Extension_Command_Action_Definition,
	confirmation:       ksawery.Extension_Command_Confirmation_ID,
	edit_generation:    u64,
	cancelled:          bool,
	submitted:          bool,
	allocator:          runtime.Allocator,
}

/* ksawery_command_family_begin copies one admitted family before interactive editing begins. */
ksawery_command_family_begin :: proc(
	state: ^Ksawery_Command_Family_State,
	family: ksawery.Extension_Command_Family_Generation,
	action: ksawery.Extension_Command_Action_ID,
	command_context: ksawery.Extension_Command_Context,
	request: ksawery.Extension_Command_Request_ID,
	allocator: runtime.Allocator,
) -> (bool, Ksawery_Command_Family_Failure) {
	if state == nil || state.allocator.procedure != nil || request == 0 || allocator.procedure == nil {
		return false, {code = .Invalid_State}
	}
	_, contract_failure := ksawery.extension_command_family_validate(family)
	if contract_failure.code != .None {
		return false, {code = .Invalid_Family, contract = contract_failure}
	}
	action_definition, action_found := ksawery_command_family_action(family, action)
	if !action_found {
		return false, {code = .Invalid_Action, contract = {code = .Invalid_Action, action = action}}
	}
	available, availability_failure := ksawery.extension_command_action_available(
		action_definition,
		command_context,
	)
	if !available {
		return false, {code = .Invalid_Action, contract = availability_failure}
	}
	choice_count := 0
	for argument in family.arguments do choice_count += len(argument.choices)
	argument_storage, argument_error := make(
		[]ksawery.Extension_Command_Argument_Definition,
		len(family.arguments),
		allocator,
	)
	if argument_error != nil {
		return false, {code = .Memory_Limit}
	}
	choice_storage, choice_error := make(
		[]ksawery.Extension_Command_Choice,
		choice_count,
		allocator,
	)
	if choice_error != nil {
		delete(argument_storage, allocator)
		return false, {code = .Memory_Limit}
	}
	action_storage, action_error := make(
		[]ksawery.Extension_Command_Action_Definition,
		len(family.actions),
		allocator,
	)
	if action_error != nil {
		delete(choice_storage, allocator)
		delete(argument_storage, allocator)
		return false, {code = .Memory_Limit}
	}
	entries, entries_error := make([]Ksawery_Command_Argument_Entry, len(family.arguments), allocator)
	if entries_error != nil {
		delete(action_storage, allocator)
		delete(choice_storage, allocator)
		delete(argument_storage, allocator)
		return false, {code = .Memory_Limit}
	}
	submission, submission_error := make(
		[]ksawery.Extension_Command_Argument_Value,
		len(family.arguments),
		allocator,
	)
	if submission_error != nil {
		delete(entries, allocator)
		delete(action_storage, allocator)
		delete(choice_storage, allocator)
		delete(argument_storage, allocator)
		return false, {code = .Memory_Limit}
	}
	copy(argument_storage, family.arguments)
	copy(action_storage, family.actions)
	choice_offset := 0
	for &argument in argument_storage {
		choice_end := choice_offset + len(argument.choices)
		copy(choice_storage[choice_offset:choice_end], argument.choices)
		argument.choices = choice_storage[choice_offset:choice_end]
		choice_offset = choice_end
	}
	state^ = {
		family = family,
		command_context = command_context,
		request = request,
		action = action,
		entries = entries,
		submission = submission,
		argument_storage = argument_storage,
		choice_storage = choice_storage,
		action_storage = action_storage,
		edit_generation = 1,
		allocator = allocator,
	}
	state.family.arguments = state.argument_storage
	state.family.actions = state.action_storage
	return true, {}
}

/* ksawery_command_family_set_boolean edits one inert Boolean argument. */
ksawery_command_family_set_boolean :: proc(
	state: ^Ksawery_Command_Family_State,
	argument: ksawery.Extension_Command_Argument_ID,
	value: bool,
) -> (bool, Ksawery_Command_Family_Failure) {
	return ksawery_command_family_set_value(state, {
		argument = argument,
		kind = .Boolean,
		boolean = value,
	})
}

/* ksawery_command_family_set_choice edits one inert closed-choice argument. */
ksawery_command_family_set_choice :: proc(
	state: ^Ksawery_Command_Family_State,
	argument: ksawery.Extension_Command_Argument_ID,
	choice: ksawery.Extension_Command_Choice_ID,
) -> (bool, Ksawery_Command_Family_Failure) {
	return ksawery_command_family_set_value(state, {
		argument = argument,
		kind = .Closed_Choice,
		choice = choice,
	})
}

/* ksawery_command_family_set_text copies one inert UTF-8 text argument. */
ksawery_command_family_set_text :: proc(
	state: ^Ksawery_Command_Family_State,
	argument: ksawery.Extension_Command_Argument_ID,
	text: string,
) -> (bool, Ksawery_Command_Family_Failure) {
	value := ksawery.Extension_Command_Argument_Value{argument = argument, kind = .Text}
	if !ksawery.extension_command_value_assign_text(&value.content, text) {
		return false, {code = .Invalid_Argument, argument = argument}
	}
	return ksawery_command_family_set_value(state, value)
}

/* ksawery_command_family_set_target copies one exact semantic repository target argument. */
ksawery_command_family_set_target :: proc(
	state: ^Ksawery_Command_Family_State,
	argument: ksawery.Extension_Command_Argument_ID,
	kind: ksawery.Extension_Command_Argument_Kind,
	target: ksawery.Extension_Annotation_Target,
) -> (bool, Ksawery_Command_Family_Failure) {
	if kind != .Selection && kind != .Ref && kind != .Revision && kind != .Revision_Range {
		return false, {code = .Invalid_Argument, argument = argument}
	}
	return ksawery_command_family_set_value(state, {
		argument = argument,
		kind = kind,
		target = target,
	})
}

/* ksawery_command_family_set_opaque copies one inert provider-owned value. */
ksawery_command_family_set_opaque :: proc(
	state: ^Ksawery_Command_Family_State,
	argument: ksawery.Extension_Command_Argument_ID,
	content: []u8,
) -> (bool, Ksawery_Command_Family_Failure) {
	value := ksawery.Extension_Command_Argument_Value{argument = argument, kind = .Opaque}
	if !ksawery.extension_command_value_assign_opaque(&value.content, content) {
		return false, {code = .Invalid_Argument, argument = argument}
	}
	return ksawery_command_family_set_value(state, value)
}

/* ksawery_command_family_confirm seals edited arguments with one confirmation identity. */
ksawery_command_family_confirm :: proc(
	state: ^Ksawery_Command_Family_State,
	confirmation: ksawery.Extension_Command_Confirmation_ID,
) -> (bool, Ksawery_Command_Family_Failure) {
	if failure := ksawery_command_family_editable(state); failure.code != .None do return false, failure
	if confirmation == 0 do return false, {code = .Confirmation_Required}
	action, found := ksawery_command_family_action(state.family, state.action)
	if !found || !action.confirmation_required {
		return false, {code = .Invalid_Action}
	}
	state.confirmation = confirmation
	return true, {}
}

/* ksawery_command_family_prepare validates and seals one request without executing it. */
ksawery_command_family_prepare :: proc(
	state: ^Ksawery_Command_Family_State,
) -> (request: ksawery.Extension_Command_Request, ok: bool, failure: Ksawery_Command_Family_Failure) {
	if state == nil || state.allocator.procedure == nil do return {}, false, {code = .Invalid_State}
	if state.cancelled do return {}, false, {code = .Cancelled}
	if state.submitted do return {}, false, {code = .Already_Submitted}
	count := 0
	for entry in state.entries {
		if !entry.present do continue
		state.submission[count] = entry.value
		count += 1
	}
	request = {
		id = state.request,
		family = state.family.family,
		family_generation = state.family.generation,
		action = state.action,
		command_context = state.command_context,
		arguments = state.submission[:count],
		confirmation = state.confirmation,
	}
	_, contract_failure := ksawery.extension_command_request_validate(request, state.family)
	if contract_failure.code != .None {
		code := Ksawery_Command_Family_Failure_Code.Invalid_Argument
		if contract_failure.code == .Confirmation_Required do code = .Confirmation_Required
		return {}, false, {code = code, argument = contract_failure.argument, contract = contract_failure}
	}
	state.submitted = true
	state.confirmation = 0
	return request, true, {}
}

/* ksawery_command_family_cancel ends editing without producing an executable request. */
ksawery_command_family_cancel :: proc(
	state: ^Ksawery_Command_Family_State,
) -> (bool, Ksawery_Command_Family_Failure) {
	if state == nil || state.allocator.procedure == nil do return false, {code = .Invalid_State}
	if state.cancelled do return false, {code = .Cancelled}
	if state.submitted do return false, {code = .Already_Submitted}
	state.confirmation = 0
	state.cancelled = true
	for &entry in state.entries do entry = {}
	return true, {}
}

/* ksawery_command_family_close releases every copied family and argument record. */
ksawery_command_family_close :: proc(state: ^Ksawery_Command_Family_State) {
	if state == nil do return
	if state.allocator.procedure != nil {
		delete(state.submission, state.allocator)
		delete(state.entries, state.allocator)
		delete(state.action_storage, state.allocator)
		delete(state.choice_storage, state.allocator)
		delete(state.argument_storage, state.allocator)
	}
	state^ = {}
}

@(private)
ksawery_command_family_set_value :: proc(
	state: ^Ksawery_Command_Family_State,
	value: ksawery.Extension_Command_Argument_Value,
) -> (bool, Ksawery_Command_Family_Failure) {
	if failure := ksawery_command_family_editable(state); failure.code != .None do return false, failure
	definition, index, found := ksawery_command_family_argument(state.family, value.argument)
	if !found {
		return false, {code = .Invalid_Argument, argument = value.argument,
			contract = {code = .Unknown_Argument, argument = value.argument}}
	}
	contract_failure := ksawery.extension_command_argument_value_validate(
		value,
		definition,
		state.command_context,
		ksawery.DEFAULT_EXTENSION_COMMAND_LIMITS,
	)
	if contract_failure.code != .None {
		return false, {code = .Invalid_Argument, argument = value.argument, contract = contract_failure}
	}
	state.entries[index] = {present = true, value = value}
	state.edit_generation += 1
	return true, {}
}

@(private)
ksawery_command_family_editable :: proc(
	state: ^Ksawery_Command_Family_State,
) -> Ksawery_Command_Family_Failure {
	if state == nil || state.allocator.procedure == nil do return {code = .Invalid_State}
	if state.cancelled do return {code = .Cancelled}
	if state.submitted do return {code = .Already_Submitted}
	if state.confirmation != 0 do return {code = .Confirmation_Sealed}
	return {}
}

@(private)
ksawery_command_family_argument :: proc(
	family: ksawery.Extension_Command_Family_Generation,
	id: ksawery.Extension_Command_Argument_ID,
) -> (ksawery.Extension_Command_Argument_Definition, int, bool) {
	for argument, index in family.arguments {
		if argument.id == id do return argument, index, true
	}
	return {}, 0, false
}

@(private)
ksawery_command_family_action :: proc(
	family: ksawery.Extension_Command_Family_Generation,
	id: ksawery.Extension_Command_Action_ID,
) -> (ksawery.Extension_Command_Action_Definition, bool) {
	for action in family.actions {
		if action.id == id do return action, true
	}
	return {}, false
}
