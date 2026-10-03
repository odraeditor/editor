// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../theme"
import "../ui"

@(private)
command_context_contextual_presentation_profile :: proc(
	commands: ^Command_Context,
) -> (record: ui.Presentation_Profile_Record, ok: bool, failure: App_Failure) {
	return command_context_presentation_profile(commands, .Contextual_Information)
}

@(private)
command_context_interactive_candidate_presentation_profile :: proc(
	commands: ^Command_Context,
) -> (record: ui.Presentation_Profile_Record, ok: bool, failure: App_Failure) {
	return command_context_presentation_profile(commands, .Interactive_Candidates)
}

@(private)
command_context_presentation_profile :: proc(
	commands: ^Command_Context,
	role: ui.Presentation_Profile_Role,
) -> (record: ui.Presentation_Profile_Record, ok: bool, failure: App_Failure) {
	if commands == nil {
		return {}, false, App_Failure{stage = .UI, ui = {
			operation = .Inspect,
			code = .Invalid_Registry,
		}}
	}
	scope, scoped, scope_failure := ui.presentation_profile_registry_scope(
		&commands.presentation_profiles,
		role,
	)
	if !scoped {
		return {}, false, presentation_profile_app_failure(scope_failure)
	}
	resolved_record, recorded, record_failure := ui.presentation_profile_registry_record(
		&commands.presentation_profiles,
		scope.selected,
	)
	if !recorded {
		return {}, false, presentation_profile_app_failure(record_failure)
	}
	definition, theme_ok, theme_failure := command_context_theme_definition(commands)
	if !theme_ok {
		return {}, false, theme_failure
	}
	_, resolved, resolution_failure := theme.definition_resolve_presentation_profile(
		definition.styles,
		resolved_record,
	)
	if !resolved {
		return {}, false, App_Failure{stage = .Theme_Access, ui = resolution_failure}
	}
	return resolved_record, true, {}
}

@(private)
presentation_profile_app_failure :: proc(
	failure: ui.Presentation_Profile_Failure,
) -> App_Failure {
	code := ui.Failure_Code.Invalid_Popup
	if failure.code == .Allocation do code = .Allocation
	if failure.code == .Renderer_Incompatible do code = .Renderer_Incompatible
	return App_Failure{stage = .UI, ui = {operation = .Inspect, code = code}}
}
