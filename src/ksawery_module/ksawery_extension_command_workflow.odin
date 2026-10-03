// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../command"
import "../ksawery"
import "../ksawery_command"

/* Ksawery_Extension_Command_Workflow_Failure_Code classifies checked routing rejection. */
Ksawery_Extension_Command_Workflow_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Stale_Route,
	Stale_Request,
	Stale_Context,
	Operation_Active,
	Authority_Rejected,
	Confirmation_Reused,
	Core_Action_Rejected,
	External_Operation_Rejected,
	Invalid_Result,
	Refresh_Required,
}

/* Ksawery_Extension_Command_Workflow_Failure retains attributable contract evidence. */
Ksawery_Extension_Command_Workflow_Failure :: struct {
	code:      Ksawery_Extension_Command_Workflow_Failure_Code,
	contract:  ksawery.Extension_Repository_Command_Failure,
	extension: ksawery.Extension_Failure,
}

/* Ksawery_Extension_Core_Action_Request is one admitted typed core operation. */
Ksawery_Extension_Core_Action_Request :: struct {
	operation: ksawery.Repository_Operation_Kind,
	request:   ksawery.Extension_Command_Request_ID,
	arguments: []ksawery.Extension_Command_Argument_Value,
	command_context: ksawery.Extension_Command_Context,
}

/* Ksawery_Extension_Command_Workflow owns one operation and its last inspectable result. */
Ksawery_Extension_Command_Workflow :: struct {
	active:                 bool,
	request:                ksawery.Extension_Command_Request_ID,
	family:                 ksawery.Extension_Command_Family_ID,
	family_generation:      ksawery.Extension_Command_Family_Generation_ID,
	action:                 ksawery.Extension_Command_Action_ID,
	operation:              ksawery.Repository_Operation_Kind,
	external_operation:     bool,
	initial_context:        ksawery.Extension_Command_Context,
	last_confirmation:      ksawery.Extension_Command_Confirmation_ID,
	result:                 ksawery.Extension_Command_Result,
	result_available:       bool,
}

/* ksawery_extension_command_workflow_begin_external admits one confirmed external-operation request. */
ksawery_extension_command_workflow_begin_external :: proc(
	workflow: ^Ksawery_Extension_Command_Workflow,
	registry: ^Ksawery_Extension_Provider_Registry,
	route: ksawery_command.Ksawery_Extension_Command_Route,
	family: ksawery.Extension_Command_Family_Generation,
	request: ksawery.Extension_Command_Request,
	current_context: ksawery.Extension_Command_Context,
	capability: ksawery.Extension_Capability,
	current_scope: ksawery.Extension_Turn_Scope,
	current_thread: u64,
	elapsed_ns: i64,
	memory_bytes: u64,
	operation_active: bool,
) -> (bool, Ksawery_Extension_Command_Workflow_Failure) {
	if workflow == nil || workflow.active || registry == nil {
		return false, {code = .Invalid_State}
	}
	if operation_active do return false, {code = .Operation_Active}
	if route.route.provider != command.RACKET_KSAWERY_ROUTE_PROVIDER ||
	   route.contributor != family.contributor || route.family != family.family ||
	   route.family_generation != family.generation || route.action != request.action ||
	   request.family != route.family || request.family_generation != route.family_generation {
		return false, {code = .Stale_Route}
	}
	if request.command_context != current_context do return false, {code = .Stale_Context}
	_, contract_failure := ksawery.extension_command_request_validate(request, family)
	if contract_failure.code != .None {
		return false, {code = .Stale_Request, contract = contract_failure}
	}
	action, found := ksawery_extension_command_action(family, request.action)
	if !found || action.authority != .Submit_External_Operation ||
	   !action.confirmation_required || action.core_operation != .Invalid {
		return false, {code = .External_Operation_Rejected}
	}
	if request.confirmation <= workflow.last_confirmation {
		return false, {code = .Confirmation_Reused,
			contract = {code = .Confirmation_Required, action = request.action}}
	}
	authorized, extension_failure := ksawery_extension_provider_authorize(
		registry, capability, current_scope, current_thread,
		.Submit_External_Operation, elapsed_ns, memory_bytes,
	)
	if !authorized {
		return false, {code = .Authority_Rejected, extension = extension_failure}
	}
	workflow.active = true
	workflow.request = request.id
	workflow.family = request.family
	workflow.family_generation = request.family_generation
	workflow.action = request.action
	workflow.operation = .External_Operation
	workflow.external_operation = true
	workflow.initial_context = current_context
	workflow.last_confirmation = request.confirmation
	return true, {}
}

/* ksawery_extension_command_workflow_begin consumes one confirmed request into core ownership. */
ksawery_extension_command_workflow_begin :: proc(
	workflow: ^Ksawery_Extension_Command_Workflow,
	registry: ^Ksawery_Extension_Provider_Registry,
	route: ksawery_command.Ksawery_Extension_Command_Route,
	family: ksawery.Extension_Command_Family_Generation,
	request: ksawery.Extension_Command_Request,
	current_context: ksawery.Extension_Command_Context,
	capability: ksawery.Extension_Capability,
	current_scope: ksawery.Extension_Turn_Scope,
	current_thread: u64,
	elapsed_ns: i64,
	memory_bytes: u64,
	operation_active: bool,
) -> (Ksawery_Extension_Core_Action_Request, bool, Ksawery_Extension_Command_Workflow_Failure) {
	if workflow == nil || workflow.active || registry == nil {
		return {}, false, {code = .Invalid_State}
	}
	if operation_active {
		return {}, false, {code = .Operation_Active}
	}
	if route.route.provider != command.RACKET_KSAWERY_ROUTE_PROVIDER ||
	   route.contributor != family.contributor || route.family != family.family ||
	   route.family_generation != family.generation || route.action != request.action ||
	   request.family != route.family || request.family_generation != route.family_generation {
		return {}, false, {code = .Stale_Route}
	}
	if request.command_context != current_context {
		return {}, false, {code = .Stale_Context}
	}
	_, contract_failure := ksawery.extension_command_request_validate(request, family)
	if contract_failure.code != .None {
		return {}, false, {code = .Stale_Request, contract = contract_failure}
	}
	action, found := ksawery_extension_command_action(family, request.action)
	if !found || !action.mutates_repository || action.authority != .Request_Core_Action ||
	   action.core_operation == .Invalid {
		return {}, false, {code = .Core_Action_Rejected}
	}
	if request.confirmation <= workflow.last_confirmation {
		return {}, false, {code = .Confirmation_Reused,
			contract = {code = .Confirmation_Required, action = request.action}}
	}
	authorized, extension_failure := ksawery_extension_provider_authorize(
		registry,
		capability,
		current_scope,
		current_thread,
		.Request_Core_Action,
		elapsed_ns,
		memory_bytes,
	)
	if !authorized {
		return {}, false, {code = .Authority_Rejected, extension = extension_failure}
	}
	workflow.active = true
	workflow.request = request.id
	workflow.family = request.family
	workflow.family_generation = request.family_generation
	workflow.action = request.action
	workflow.operation = action.core_operation
	workflow.external_operation = false
	workflow.initial_context = current_context
	workflow.last_confirmation = request.confirmation
	return {
		operation = action.core_operation,
		request = request.id,
		arguments = request.arguments,
		command_context = current_context,
	}, true, {}
}

/* ksawery_extension_command_workflow_complete retains one outcome after mandatory refresh. */
ksawery_extension_command_workflow_complete :: proc(
	workflow: ^Ksawery_Extension_Command_Workflow,
	result: ksawery.Extension_Command_Result,
	refreshed_context: ksawery.Extension_Command_Context,
	refresh_completed: bool,
) -> (bool, Ksawery_Extension_Command_Workflow_Failure) {
	if workflow == nil || !workflow.active {
		return false, {code = .Invalid_State}
	}
	request := ksawery.Extension_Command_Request {
		id = workflow.request,
		family = workflow.family,
		family_generation = workflow.family_generation,
		action = workflow.action,
	}
	contract_failure := ksawery.extension_command_result_validate(result, request)
	if contract_failure.code != .None {
		return false, {code = .Invalid_Result, contract = contract_failure}
	}
	if result.core_action_requested || result.external_operation_requested {
		if result.core_action_requested == workflow.external_operation ||
		   result.external_operation_requested != workflow.external_operation {
			return false, {code = .Invalid_Result}
		}
		initial_repository := workflow.initial_context.repository
		refreshed_repository := refreshed_context.repository
		if !refresh_completed || refreshed_repository != initial_repository ||
		   refreshed_context.repository_generation <= workflow.initial_context.repository_generation ||
		   refreshed_context.worktree_generation < workflow.initial_context.worktree_generation {
			return false, {code = .Refresh_Required}
		}
	} else if result.status == .Completed {
		return false, {code = .Invalid_Result}
	}
	workflow.result = result
	workflow.result_available = true
	workflow.active = false
	workflow.request = 0
	workflow.family = 0
	workflow.family_generation = 0
	workflow.action = 0
	workflow.operation = .Invalid
	workflow.external_operation = false
	workflow.initial_context = {}
	return true, {}
}

/* ksawery_extension_command_workflow_abort clears one active turn without publishing a result. */
ksawery_extension_command_workflow_abort :: proc(
	workflow: ^Ksawery_Extension_Command_Workflow,
) -> bool {
	if workflow == nil || !workflow.active do return false
	workflow.active = false
	workflow.request = 0
	workflow.family = 0
	workflow.family_generation = 0
	workflow.action = 0
	workflow.operation = .Invalid
	workflow.external_operation = false
	workflow.initial_context = {}
	return true
}

/* ksawery_extension_command_workflow_inspect copies the last complete provider-visible result. */
ksawery_extension_command_workflow_inspect :: proc(
	workflow: ^Ksawery_Extension_Command_Workflow,
) -> (ksawery.Extension_Command_Result, bool) {
	if workflow == nil || !workflow.result_available do return {}, false
	return workflow.result, true
}

@(private)
ksawery_extension_command_action :: proc(
	family: ksawery.Extension_Command_Family_Generation,
	id: ksawery.Extension_Command_Action_ID,
) -> (ksawery.Extension_Command_Action_Definition, bool) {
	for action in family.actions {
		if action.id == id do return action, true
	}
	return {}, false
}
