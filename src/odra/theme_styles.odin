// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../theme"
import "../ui"

@(private)
Theme_Transition_Kind :: enum u8 {
	None,
	Select,
	Restore,
	Baseline,
	Fail_Provider,
}

@(private)
Theme_Transition :: struct {
	kind:              Theme_Transition_Kind,
	expected:          theme.Selection,
	target:            theme.Definition_Handle,
	provider:          theme.Provider_Handle,
	expected_root:     ui.Root_Handle,
	expected_renderer: ui.Renderer_Profile,
}

@(private)
theme_transition_operation :: proc(kind: Theme_Transition_Kind) -> theme.Operation {
	switch kind {
	case .Select: return .Select
	case .Restore: return .Restore
	case .Baseline: return .Select_Baseline
	case .Fail_Provider: return .Fail
	case .None: return .None
	}
	return .None
}

@(private)
command_context_theme_transition_begin :: proc(
	commands: ^Command_Context,
	kind: Theme_Transition_Kind,
	expected: theme.Selection,
	target: theme.Definition_Handle = {},
	provider: theme.Provider_Handle = {},
) -> (ok: bool, failure: App_Failure) {
	operation := theme_transition_operation(kind)
	if commands == nil || kind == .None || commands.theme_transition.kind != .None {
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = operation, code = .Busy},
		}
	}
	current, selected, selection_failure := theme.theme_registry_selection(
		&commands.theme_registry,
	)
	if !selected {
		return false, App_Failure{stage = .Theme_Access, theme = selection_failure}
	}
	if current != expected {
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = operation, code = .Stale_Selection},
		}
	}
	if current.selection_generation == theme.Selection_Generation(max(u64)) {
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = operation, code = .Generation_Limit},
		}
	}
	resolved_target := target
	switch kind {
	case .Select:
	case .Restore:
		resolved_target = current.fallback
	case .Baseline:
		resolved_target = current.baseline
	case .Fail_Provider:
		active_provider := theme.Provider_Handle {
			registry_id = current.active.registry_id,
			provider_id = current.active.provider_id,
			provider_generation = current.active.provider_generation,
		}
		if active_provider != provider {
			return false, App_Failure {
				stage = .Theme_Access,
				theme = {operation = operation, code = .Invalid_Provider, provider = provider},
			}
		}
		resolved_target = current.fallback
	case .None:
		return false, App_Failure{stage = .Theme_Access}
	}
	definition, resolved, definition_failure := theme.theme_registry_definition(
		&commands.theme_registry,
		resolved_target,
	)
	if !resolved || definition.descriptor.state != .Confirmed {
		if !resolved {
			definition_failure.operation = operation
			return false, App_Failure{stage = .Theme_Access, theme = definition_failure}
		}
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {
				operation = operation,
				code = .Definition_Not_Confirmed,
				definition = resolved_target,
			},
		}
	}
	if !ui.renderer_profile_is_valid(commands.renderer_profile) {
		return false, App_Failure {
			stage = .Theme_Access,
			ui = {operation = .Prepare, code = .Renderer_Incompatible},
		}
	}
	commands.theme_transition = Theme_Transition {
		kind = kind,
		expected = current,
		target = resolved_target,
		provider = provider,
		expected_root = commands.ui_root,
		expected_renderer = commands.renderer_profile,
	}
	return true, {}
}

@(private)
command_context_theme_transition_validate :: proc(
	commands: ^Command_Context,
	profile: ui.Renderer_Profile,
) -> (ok: bool, failure: App_Failure) {
	if commands == nil || commands.theme_transition.kind == .None {
		return false, App_Failure{stage = .Theme_Access}
	}
	transition := &commands.theme_transition
	operation := theme_transition_operation(transition.kind)
	current, selected, selection_failure := theme.theme_registry_selection(
		&commands.theme_registry,
	)
	if !selected {
		commands.theme_transition = {}
		return false, App_Failure{stage = .Theme_Access, theme = selection_failure}
	}
	if current != transition.expected || commands.ui_root != transition.expected_root {
		commands.theme_transition = {}
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = operation, code = .Stale_Selection},
			ui = {operation = .Prepare, code = .Stale_Root},
		}
	}
	if profile != transition.expected_renderer {
		commands.theme_transition = {}
		return false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = operation, code = .Stale_Selection},
			ui = {operation = .Prepare, code = .Renderer_Incompatible},
		}
	}
	return true, {}
}

@(private)
command_context_theme_transition_commit :: proc(
	commands: ^Command_Context,
) -> (selection: theme.Selection, ok: bool, failure: App_Failure) {
	if commands == nil || commands.theme_transition.kind == .None {
		return {}, false, App_Failure{stage = .Theme_Access}
	}
	transition := commands.theme_transition
	commands.theme_transition = {}
	theme_failure: theme.Failure
	switch transition.kind {
	case .Select:
		selection, ok, theme_failure = theme.theme_registry_select(
			&commands.theme_registry, transition.expected, transition.target,
		)
	case .Restore:
		selection, ok, theme_failure = theme.theme_registry_restore(
			&commands.theme_registry, transition.expected,
		)
	case .Baseline:
		selection, ok, theme_failure = theme.theme_registry_select_baseline(
			&commands.theme_registry, transition.expected,
		)
	case .Fail_Provider:
		selection, ok, theme_failure = theme.theme_registry_fail_provider(
			&commands.theme_registry, transition.expected, transition.provider,
		)
	case .None:
		return {}, false, App_Failure{stage = .Theme_Access}
	}
	if !ok do return {}, false, App_Failure{stage = .Theme_Access, theme = theme_failure}
	return selection, true, {}
}

@(private)
command_context_theme_transition_abort :: proc(commands: ^Command_Context) {
	if commands != nil do commands.theme_transition = {}
}

@(private)
command_context_theme_definition :: proc(
	commands: ^Command_Context,
) -> (definition: theme.Definition_View, ok: bool, failure: App_Failure) {
	if commands == nil {
		return {}, false, App_Failure {
			stage = .Theme_Access,
			theme = {operation = .Inspect, code = .Invalid_Registry},
		}
	}
	if commands.theme_transition.kind != .None {
		active, resolved, definition_failure := theme.theme_registry_definition(
			&commands.theme_registry,
			commands.theme_transition.target,
		)
		if !resolved {
			definition_failure.operation = theme_transition_operation(commands.theme_transition.kind)
			return {}, false, App_Failure{stage = .Theme_Access, theme = definition_failure}
		}
		return active, true, {}
	}
	selection, selected, selection_failure := theme.theme_registry_selection(
		&commands.theme_registry,
	)
	if !selected {
		return {}, false, App_Failure{stage = .Theme_Access, theme = selection_failure}
	}
	active, resolved, definition_failure := theme.theme_registry_definition(
		&commands.theme_registry,
		selection.active,
	)
	if !resolved {
		return {}, false, App_Failure{stage = .Theme_Access, theme = definition_failure}
	}
	return active, true, {}
}

@(private)
proposal_resolve_session_theme :: proc(
	proposal: ^ui.Proposal,
	commands: ^Command_Context,
) -> (ok: bool, failure: App_Failure) {
	if commands == nil {
		styles := theme.factory_fallback_styles()
		resolved, ui_failure := theme.definition_resolve_ui(proposal, styles[:])
		if !resolved do return false, App_Failure{stage = .UI, ui = ui_failure}
		return true, {}
	}
	definition, found, definition_failure := command_context_theme_definition(commands)
	if !found do return false, definition_failure
	resolved, ui_failure := theme.definition_resolve_ui(proposal, definition.styles)
	if !resolved do return false, App_Failure{stage = .UI, ui = ui_failure}
	return true, {}
}
