// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../editor"
import "../language_interaction"
import "../language_service"
import "core:fmt"

@(private)
command_context_begin_language_interaction :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	route: command.Native_Route,
) -> (Interaction_Result, App_Failure) {
	if commands == nil do return {}, App_Failure{stage = .Command_Dispatch}
	operation, mapped := language_interaction_operation(route)
	if !mapped do return {}, App_Failure{stage = .Command_Dispatch}
	availability := language_interaction.availability_available()
	if !language_interaction_factory_owned(operation) {
		availability = command_context_language_interaction_availability(commands, buffer, operation)
	}
	snapshot, retained, failure := language_interaction.workflow_begin(
		&commands.language_interaction_workflow,
		{operation = operation, availability = availability},
	)
	if !retained {
		if failure.code == .Busy {
			command_context_set_channel_diagnostic(commands, .Language_Service, "Another language operation is active; press C-g to cancel it")
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	if failure.code == .Unavailable {
		reason := snapshot.failure
		recovery := snapshot.recovery
		message := fmt.bprintf(
			commands.feedback_content[:],
			"%s Recovery: %s",
			language_interaction.text_string(&reason),
			language_interaction.text_string(&recovery),
		)
		command_context_set_channel_diagnostic(commands, .Language_Service, message, .Warning)
		return Interaction_Result{changed = true}, {}
	}
	command_context_set_channel_diagnostic(
		commands,
		.Language_Service,
		fmt.bprintf(
			commands.feedback_content[:],
			"%s started; press C-g to cancel",
			language_interaction_operation_name(operation),
		),
	)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_language_interaction_cancel :: proc(commands: ^Command_Context) -> bool {
	if commands == nil do return false
	snapshot, present := language_interaction.workflow_snapshot(&commands.language_interaction_workflow)
	if !present || !language_interaction.snapshot_active(snapshot) do return false
	_, cancelled, _ := language_interaction.workflow_cancel(
		&commands.language_interaction_workflow,
		snapshot.generation,
	)
	if !cancelled do return false
	command_context_set_channel_diagnostic(commands, .Language_Service, "Language operation cancelled")
	return true
}

@(private)
command_context_language_interaction_availability :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	operation: language_interaction.Operation,
) -> language_interaction.Availability {
	unavailable := proc(reason, recovery: string) -> language_interaction.Availability {
		value, copied := language_interaction.availability_unavailable(reason, recovery)
		assert(copied)
		return value
	}
	if commands.language_service_workflow == nil || buffer == nil {
		return unavailable(
			"No active language service is associated with this document.",
			"Run describe-language-support and configure the documented service prerequisite.",
		)
	}
	stats, inspected, _ := editor.buffer_stats(buffer)
	if !inspected {
		return unavailable(
			"The active document cannot be inspected for language support.",
			"Reopen the document and run describe-language-support.",
		)
	}
	for &owner in commands.language_service_workflow.sessions {
		if !owner.live do continue
		for document_binding in owner.documents {
			if document_binding.buffer_id != stats.buffer_id do continue
			if owner.phase == .Initializing {
				return unavailable(
					"The selected language service is still initializing.",
					"Wait for the Status Bar service health to become active, then retry.",
				)
			}
			if owner.phase != .Active {
				return unavailable(
					"The selected language service is not active.",
					"Run describe-language-service for the failure and restart action.",
				)
			}
			if language_interaction_service_supports(owner.active_features, owner.capabilities, operation) {
				return language_interaction.availability_available()
			}
			return unavailable(
				"The selected language service does not provide this operation.",
				"Run describe-language-support to inspect negotiated capabilities and select another provider.",
			)
		}
	}
	return unavailable(
		"No synchronized language-service document is available.",
		"Save or reopen the document inside its Project, then run describe-language-support.",
	)
}

@(private)
language_interaction_service_supports :: proc(
	features: language_service.Service_Features,
	capabilities: language_service.Capability_Values,
	operation: language_interaction.Operation,
) -> bool {
	#partial switch operation {
	case .Show_Hover:        return .Hover in features && .Hover in capabilities.capabilities
	case .Go_To_Definition:  return .Navigation in features && .Definition in capabilities.capabilities
	case .Find_References:   return .References in features && .References in capabilities.capabilities
	case .Document_Symbols:  return .Symbols in features && .Document_Symbols in capabilities.capabilities
	case .Workspace_Symbols: return .Symbols in features && .Workspace_Symbols in capabilities.capabilities
	case .Signature_Help:    return .Signature_Help in features && .Signature_Help in capabilities.capabilities
	case .Rename:            return .Rename in features
	case .Format_Buffer, .Format_Region: return .Formatting in features
	case .Code_Actions:      return .Code_Actions in features
	case:                    return false
	}
}

@(private)
language_interaction_factory_owned :: proc(operation: language_interaction.Operation) -> bool {
	return operation >= .Describe_Bundle && operation <= .Bundle_Refresh_Catalogs
}

@(private)
language_interaction_operation :: proc(route: command.Native_Route) -> (language_interaction.Operation, bool) {
	#partial switch route {
	case .Language_Show_Hover:              return .Show_Hover, true
	case .Language_Go_To_Definition:        return .Go_To_Definition, true
	case .Language_Find_References:         return .Find_References, true
	case .Language_Document_Symbols:        return .Document_Symbols, true
	case .Language_Workspace_Symbols:       return .Workspace_Symbols, true
	case .Language_Signature_Help:          return .Signature_Help, true
	case .Language_Rename:                  return .Rename, true
	case .Language_Format_Buffer:           return .Format_Buffer, true
	case .Language_Format_Region:           return .Format_Region, true
	case .Language_Code_Actions:            return .Code_Actions, true
	case .Describe_Language_Bundle:         return .Describe_Bundle, true
	case .Language_Support_Doctor:          return .Support_Doctor, true
	case .Language_Bundle_List:             return .Bundle_List, true
	case .Language_Bundle_Search:           return .Bundle_Search, true
	case .Language_Bundle_Install:          return .Bundle_Install, true
	case .Language_Bundle_Enable:           return .Bundle_Enable, true
	case .Language_Bundle_Disable:          return .Bundle_Disable, true
	case .Language_Bundle_Update:           return .Bundle_Update, true
	case .Language_Bundle_Rollback:         return .Bundle_Rollback, true
	case .Language_Bundle_Remove:           return .Bundle_Remove, true
	case .Language_Bundle_Refresh_Catalogs: return .Bundle_Refresh_Catalogs, true
	case:                                   return .Invalid, false
	}
}

@(private)
language_interaction_operation_name :: proc(operation: language_interaction.Operation) -> string {
	switch operation {
	case .Show_Hover:              return "Language hover"
	case .Go_To_Definition:        return "Language definition"
	case .Find_References:         return "Language references"
	case .Document_Symbols:        return "Document symbols"
	case .Workspace_Symbols:       return "Workspace symbols"
	case .Signature_Help:          return "Signature help"
	case .Rename:                  return "Language rename"
	case .Format_Buffer:           return "Buffer formatting"
	case .Format_Region:           return "Region formatting"
	case .Code_Actions:            return "Language code actions"
	case .Describe_Bundle:         return "Language bundle inspection"
	case .Support_Doctor:          return "Language support doctor"
	case .Bundle_List:             return "Language bundle list"
	case .Bundle_Search:           return "Language bundle search"
	case .Bundle_Install:          return "Language bundle installation"
	case .Bundle_Enable:           return "Language bundle enablement"
	case .Bundle_Disable:          return "Language bundle disablement"
	case .Bundle_Update:           return "Language bundle update"
	case .Bundle_Rollback:         return "Language bundle rollback"
	case .Bundle_Remove:           return "Language bundle removal"
	case .Bundle_Refresh_Catalogs: return "Language catalog refresh"
	case .Invalid:                 return "Language operation"
	}
	return "Language operation"
}
