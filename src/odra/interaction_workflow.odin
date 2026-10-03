// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../editor_session"
import "../interaction"
import editor_view "../view"

@(private)
Interaction_Workflow_State :: struct {
	map_handle:          interaction.Context_Map_Handle,
	inspection_pending: interaction.Pending_State,
	inspection_sequence: interaction.Key_Sequence,
}

@(private)
List_Context_Kind :: enum u8 {
	Invalid,
	Startup,
	Buffer_Inventory,
	Project,
	Keymap_Inspection,
	Language_State,
	Language_Service_Inspection,
	Structural_State,
	Theme_Inspection,
}

@(private)
interaction_workflow_reset :: proc(state: ^Interaction_Workflow_State) {
	if state == nil {
		return
	}
	state.map_handle = {}
	state.inspection_pending = {}
	state.inspection_sequence = {}
}

@(private)
interaction_workflow_reset_inspection :: proc(state: ^Interaction_Workflow_State) {
	if state == nil {
		return
	}
	state.inspection_pending = {}
	state.inspection_sequence = {}
}

@(private)
command_context_sync_candidate_map :: proc(
	commands: ^Command_Context,
	source: interaction.Candidate_Source_Kind,
) -> App_Failure {
	if commands.context_maps == nil {
		return App_Failure{stage = .Command_Resolution}
	}
	map_id := interaction.Map_ID(0)
	owner_id := interaction.Owner_ID(0)
	name := ""
	policy := interaction.Unmatched_Input_Policy.Reject
	text_fallback_name := ""
	bindings: [48]interaction.Binding_Definition
	binding_count := 0
	#partial switch source {
	case .Package_Catalogs, .Packages, .Package_Catalog_Diagnostics:
		map_id = interaction.Map_ID(3_020)
		owner_id = interaction.Owner_ID(4_020)
		name = "package-catalog-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Personal_Command_Results:
		map_id = interaction.Map_ID(3_021)
		owner_id = interaction.Owner_ID(4_021)
		name = "personal-command-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('g', {}), "result-refresh")
	case .Status_Segments:
		map_id = interaction.Map_ID(3_014)
		owner_id = interaction.Owner_ID(4_014)
		name = "status-bar-segments-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Session_Buffers:
		map_id = interaction.Map_ID(3_008)
		owner_id = interaction.Owner_ID(4_008)
		name = "buffer-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Project_Files, .Dir_Files:
		map_id = interaction.Map_ID(3_006)
		owner_id = interaction.Owner_ID(4_006)
		name = "project-file-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_project_refresh_sequence(), "project-refresh")
	case .Project_Buffers:
		map_id = interaction.Map_ID(3_007)
		owner_id = interaction.Owner_ID(4_007)
		name = "project-buffer-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Commands:
		map_id = interaction.Map_ID(3_003)
		owner_id = interaction.Owner_ID(4_003)
		name = "command-navigation-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Escape), "component-close")
	case .Themes:
		map_id = interaction.Map_ID(3_009)
		owner_id = interaction.Owner_ID(4_009)
		name = "theme-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Interaction_Profiles:
		map_id = interaction.Map_ID(3_019)
		owner_id = interaction.Owner_ID(4_019)
		name = "interaction-profile-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Projects:
		map_id = interaction.Map_ID(3_015)
		owner_id = interaction.Owner_ID(4_015)
		name = "project-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Workspaces:
		map_id = interaction.Map_ID(3_014)
		owner_id = interaction.Owner_ID(4_014)
		name = "workspace-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Named_Locations:
		map_id = interaction.Map_ID(3_016)
		owner_id = interaction.Owner_ID(4_016)
		name = "named-location-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Named_Slots:
		map_id = interaction.Map_ID(3_017)
		owner_id = interaction.Owner_ID(4_017)
		name = "named-slot-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Language_Diagnostics:
		map_id = interaction.Map_ID(3_010)
		owner_id = interaction.Owner_ID(4_010)
		name = "language-diagnostic-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case .Results:
		map_id = interaction.Map_ID(3_018)
		owner_id = interaction.Owner_ID(4_018)
		name = "result-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Meta}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Meta}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('<', {}), "result-first")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('>', {}), "result-last")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('g', {}), "result-refresh")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('e', {}), "result-edit")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_pair('c', {.Control}, 'c', {.Control}), "result-apply")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Filesystem_Entries:
		map_id = interaction.Map_ID(3_013)
		owner_id = interaction.Owner_ID(4_013)
		name = "filesystem-path-candidates-ui"
		policy = .Text_Input
		text_fallback_name = "component-query-text"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('p', {.Control}), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('n', {.Control}), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Tab), "component-complete-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Backspace), "component-query-delete-previous")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Delete), "component-query-delete-previous")
	case:
		command_context_deactivate_context_map(commands, .Invalidated)
		return App_Failure{stage = .Component_Access}
	}
	return command_context_sync_context_map(
		commands, map_id, owner_id, name, policy, text_fallback_name, bindings[:binding_count],
	)
}

@(private)
command_context_sync_list_map :: proc(
	commands: ^Command_Context,
	kind: List_Context_Kind,
) -> App_Failure {
	bindings: [interaction.MAX_CONTEXT_BINDINGS]interaction.Binding_Definition
	binding_count := 0
	map_id: interaction.Map_ID
	owner_id: interaction.Owner_ID
	name := ""
	policy := interaction.Unmatched_Input_Policy.Reject
	switch kind {
	case .Startup:
		map_id = 3_001
		owner_id = 4_001
		name = "startup-list"
		policy = .Fallthrough
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
	case .Buffer_Inventory:
		map_id = 3_002
		owner_id = 4_002
		name = "buffer-inventory-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('s', {}), "component-mark-save")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('d', {}), "component-mark-kill")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('k', {}), "component-mark-kill")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('u', {}), "component-unmark")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('x', {}), "component-execute")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Project:
		map_id = 3_005
		owner_id = 4_005
		name = "project-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Enter), "component-activate-current")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Keymap_Inspection:
		map_id = 3_004
		owner_id = 4_004
		name = "keymap-inspection-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Language_State:
		map_id = 3_006
		owner_id = 4_006
		name = "language-state-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Language_Service_Inspection:
		map_id = 3_012
		owner_id = 4_012
		name = "language-service-inspection-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Structural_State:
		map_id = 3_011
		owner_id = 4_011
		name = "structural-state-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Theme_Inspection:
		map_id = 3_010
		owner_id = 4_010
		name = "theme-inspection-list"
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Up), "component-previous-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_special(.Down), "component-next-row")
		command_context_add_prompt_binding(bindings[:], &binding_count, command_context_prompt_scalar('q', {}), "component-close")
	case .Invalid:
		return App_Failure{stage = .Command_Resolution}
	}
	return command_context_sync_context_map(
		commands, map_id, owner_id, name, policy, "", bindings[:binding_count],
	)
}

@(private)
command_context_sync_context_map :: proc(
	commands: ^Command_Context,
	map_id: interaction.Map_ID,
	owner_id: interaction.Owner_ID,
	name: string,
	policy: interaction.Unmatched_Input_Policy,
	text_fallback_name: string,
	bindings: []interaction.Binding_Definition,
	precedence := interaction.Precedence_Class.Component_Tool,
) -> App_Failure {
	if commands.context_maps == nil {
		return App_Failure{stage = .Command_Resolution}
	}
	if interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) {
		if interaction.context_map_handle_is_active(
			commands.context_maps,
			commands.interaction_workflow.map_handle,
		) {
			if commands.interaction_workflow.map_handle.identity.id == map_id {
				command_context_suspend_modal_pending(commands, map_id == interaction.Map_ID(3_003))
				return {}
			}
			command_context_deactivate_context_map(commands, .Invalidated)
		} else {
			commands.interaction_workflow.map_handle = {}
		}
	}
	result, activated, activation_failure := interaction.context_map_activate(
		commands.context_maps,
		interaction.Context_Map_Definition {
			identity = interaction.Map_Identity{id = map_id, revision = 1},
			name = name,
			owner_id = owner_id,
			precedence = precedence,
			priority = 0,
			bindings = bindings,
			text_fallback_name = text_fallback_name,
			unmatched_input_policy = policy,
		},
		&commands.context_pending,
		&commands.pending,
	)
	if !activated {
		return App_Failure{stage = .Command_Resolution, interaction = activation_failure}
	}
	commands.interaction_workflow.map_handle = result.handle
	command_context_suspend_modal_pending(commands, map_id == interaction.Map_ID(3_003))
	return {}
}

@(private)
command_context_suspend_modal_pending :: proc(
	commands: ^Command_Context,
	preserve_command_entry: bool,
) {
	if commands == nil || commands.profile_activation == nil do return
	pending, inspected := interaction.profile_activation_modal_pending_inspect(
		commands.profile_activation,
	)
	if !inspected || pending.kind == .None ||
	   preserve_command_entry && pending.kind == .Command_Entry {
		return
	}
	_ = interaction.profile_activation_modal_pending_cancel(commands.profile_activation)
}

@(private)
command_context_project_refresh_sequence :: proc() -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 3
	sequence.strokes[0] = interaction.Key_Stroke {
		kind = .Unicode_Scalar,
		scalar = 'c',
		modifiers = {.Control},
	}
	sequence.strokes[1] = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'p'}
	sequence.strokes[2] = interaction.Key_Stroke{kind = .Unicode_Scalar, scalar = 'i'}
	return sequence
}

@(private)
command_context_resolve_context_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (metadata: interaction.Command_Metadata, resolution: interaction.Resolution, ok: bool, failure: App_Failure) {
	resolution_failure: interaction.Failure_Context
	resolution, resolution_failure = interaction.resolve_contextual_input(
		commands.context_maps,
		commands.keymap,
		commands.registry_generation,
		&commands.context_pending,
		&commands.pending,
		input,
	)
	if resolution_failure.code == .Context_Input_Rejected {
		return {}, interaction.Resolution{kind = .Unbound}, true, {}
	}
	if resolution_failure.code != .None {
		return {}, resolution, false, App_Failure {
			stage = .Command_Resolution,
			interaction = resolution_failure,
		}
	}
	if resolution.kind != .Command {
		return {}, resolution, true, {}
	}
	found: bool
	metadata_failure: interaction.Failure_Context
	metadata, found, metadata_failure = interaction.command_metadata(commands.registry, resolution.command)
	if !found {
		return {}, resolution, false, App_Failure {
			stage = .Command_Dispatch,
			interaction = metadata_failure,
		}
	}
	return metadata, resolution, true, {}
}

@(private)
command_context_deactivate_context_map :: proc(
	commands: ^Command_Context,
	end: interaction.Context_Map_End,
) {
	if !interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) {
		return
	}
	_, ended, failure := interaction.context_map_end(
		commands.context_maps,
		commands.interaction_workflow.map_handle,
		end,
		&commands.context_pending,
		&commands.pending,
	)
	assert(ended && failure.code == .None)
	commands.interaction_workflow.map_handle = {}
}

@(private)
command_context_present_buffer_inventory :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	return command_context_present_inventory(commands, constraints, command_handle, false)
}

@(private)
command_context_present_inventory :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
	terminal_only: bool,
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	inventory_workflow_reset(&commands.inventory_workflow)
	commands.inventory_workflow.terminal_only = terminal_only
	commands.inventory_workflow.return_target = visible
	commands.inventory_workflow.command_handle = command_handle
	commands.inventory_workflow.model_generation = 1
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
	)
	if !copied {
		return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	filtered: [editor_session.MAX_LIVE_BUFFERS]editor_session.Entry_Descriptor
	inventory_descriptors := inventory_workflow_visible_descriptors(
		&commands.inventory_workflow,
		descriptors.descriptors,
		filtered[:],
	)
	if len(inventory_descriptors) == 0 {
		inventory_workflow_reset(&commands.inventory_workflow)
		command_context_set_diagnostic(commands, "No terminal sessions")
		return Interaction_Result{changed = true}, {}
	}
	prepared, prepare_failure := inventory_workflow_prepare(
		&commands.inventory_workflow,
		inventory_descriptors,
		constraints.height_rows,
	)
	if !prepared do return {}, App_Failure{stage = .UI, ui = prepare_failure}
	target := buffer_inventory_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.document_workflow.buffer_command = command_handle
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_present_terminal_inventory :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
) -> (Interaction_Result, App_Failure) {
	return command_context_present_inventory(commands, constraints, command_handle, true)
}

@(private)
command_context_command_navigation_describes :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.document_workflow.buffer_command.registry_generation ==
	   interaction.Registry_Generation(0) {
		return false
	}
	metadata, found, _ := interaction.command_metadata(
		commands.registry,
		commands.document_workflow.buffer_command,
	)
	if !found do return false
	route, decoded := command.native_route_decode(metadata.route)
	return decoded && (route == .Apropos_Command || route == .Describe_Function)
}

@(private)
command_context_present_command_navigation :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	initial_query := "",
) -> (Interaction_Result, App_Failure) {
	if buffer == nil || commands.registry == nil || commands.keymap == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
	if !logical_ok {
		return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
	}
	surface, surface_ok := interaction.profile_activation_command_entry_surface(
		commands.profile_activation,
		"extended-command",
	)
	if !surface_ok {
		return {}, App_Failure {
			stage = .Command_Resolution,
			interaction = {code = .Invalid_Command_Entry_Surface},
		}
	}
	catalog_context := command_context_catalog_context(commands, true, logical.region_active)
	catalog_context.command_entry_surface = surface.identity
	catalog, catalog_ok, catalog_failure := interaction.command_catalog_build(
		commands.registry,
		commands.keymap,
		catalog_context,
		commands.persistent_allocator,
	)
	if !catalog_ok {
		return {}, App_Failure{stage = .Command_Resolution, interaction = catalog_failure}
	}
	keep_catalog := false
	defer if !keep_catalog {
		interaction.command_catalog_close(&catalog)
	}
	source, source_ok, source_failure := interaction.command_candidate_source_build(
		&catalog,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Command candidate source", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.command_candidate_source_close(&source)
	command_context_candidate_history_rank_source(commands, &source.definition, {})
	session_id := commands.candidate_ui.next_session_id
	if session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source.definition,
		initial_query,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Command candidate session", initialization_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session {
		_, _, _ = interaction.candidate_session_close(&candidate_session)
	}
	_, viewed, candidate_view_failure := interaction.candidate_session_view(&candidate_session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_view_failure}
	}
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(
			&commands.candidate_ui.session,
		)
	}
	commands.candidate_ui.catalog = catalog
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	keep_catalog = true
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_present_buffer_navigation :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	command_handle: interaction.Command_Handle,
	initial_query := "",
) -> (Interaction_Result, App_Failure) {
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok || visible.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied {
		return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	source_generation := commands.candidate_ui.next_source_generation
	session_id := commands.candidate_ui.next_session_id
	if source_generation == 0 || source_generation == max(u64) ||
	   session_id == 0 || session_id == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.session_buffer_candidate_source_build_query(
		&descriptors,
		initial_query,
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Buffer candidate source", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.buffer_candidate_source_close(&source)
	command_context_candidate_history_rank_source(commands, &source.definition, command_handle)
	candidate_session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
		&candidate_session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(session_id),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = commands.persistent_allocator,
			temporary_allocator = commands.temporary_allocator,
		},
		source.definition,
		initial_query,
	)
	if !initialized {
		command_context_candidate_failure_diagnostic(commands, "Buffer candidate session", initialization_failure)
		return Interaction_Result{changed = true}, {}
	}
	keep_session := false
	defer if !keep_session {_, _, _ = interaction.candidate_session_close(&candidate_session)}
	_, viewed, candidate_failure := interaction.candidate_session_view(&candidate_session)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.session = candidate_session
	commands.candidate_ui.return_target = visible
	commands.candidate_ui.next_session_id = session_id + 1
	commands.candidate_ui.next_source_generation = source_generation + 1
	commands.document_workflow.buffer_command = command_handle
	keep_session = true
	target := candidate_ui_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_refresh_buffer_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed || view.source_kind != .Session_Buffers {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	descriptors, copied, copy_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied {
		return {}, App_Failure{stage = .Session_Access, editor_session = copy_failure}
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	source_generation := commands.candidate_ui.next_source_generation
	if source_generation == 0 || source_generation == max(u64) {
		return {}, App_Failure{stage = .Component_Access}
	}
	source, source_ok, source_failure := interaction.session_buffer_candidate_source_build_query(
		&descriptors,
		query,
		source_generation,
		commands.temporary_allocator,
	)
	if !source_ok {
		command_context_candidate_failure_diagnostic(commands, "Buffer candidate refresh", source_failure)
		return Interaction_Result{changed = true}, {}
	}
	defer interaction.buffer_candidate_source_close(&source)
	command_context_candidate_history_rank_source(
		commands,
		&source.definition,
		commands.document_workflow.buffer_command,
	)
	request := interaction.Candidate_Request {
		session_id = view.session_id,
		session_generation = view.session_generation,
	}
	_, refreshed, refresh_failure := interaction.candidate_session_refresh(
		&commands.candidate_ui.session,
		request,
		source.definition,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Buffer candidate refresh", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	commands.candidate_ui.next_source_generation = source_generation + 1
	view, viewed, view_failure = interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, queried, query_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !queried {
		command_context_candidate_failure_diagnostic(commands, "Buffer candidate query", query_failure)
		return Interaction_Result{changed = true}, {}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_catalog_context :: proc(
	commands: ^Command_Context,
	active_buffer: bool,
	active_region: bool,
) -> interaction.Command_Catalog_Context {
	result := interaction.Command_Catalog_Context {
		active_buffer = active_buffer,
		active_document = commands.document_owner != nil,
		active_region = active_region,
		active_terminal = command_context_active_terminal(commands),
	}
	if commands.profile_activation == nil {
		return result
	}
	profile, state, selected := interaction.profile_activation_selection(
		commands.profile_activation,
	)
	if selected {
		result.profile = profile
		result.state = state.identity
		result.admits_text_input = state.admits_text_input
		result.admitted_effects = state.admitted_effects
	}
	return result
}

@(private)
command_context_present_keymap_inspection :: proc(
	commands: ^Command_Context,
	query: interaction.Inspection_Query,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.registry == nil || commands.profile_activation == nil {
		return {}, App_Failure{stage = .Command_Resolution}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	region_active := false
	if buffer != nil {
		if view_registry == nil {
			return {}, App_Failure{stage = .View_Snapshot}
		}
		logical, logical_ok, logical_failure := editor_view.snapshot(view_registry, view)
		if !logical_ok {
			return {}, App_Failure{stage = .View_Snapshot, view = logical_failure}
		}
		region_active = logical.region_active
	}
	catalog, catalog_ok, catalog_failure := interaction.command_catalog_build(
		commands.registry,
		commands.keymap,
		command_context_catalog_context(commands, true, region_active),
		commands.persistent_allocator,
	)
	if !catalog_ok {
		return {}, App_Failure{stage = .Command_Resolution, interaction = catalog_failure}
	}
	inspection, inspected, inspection_failure := command.keymap_inspection_run(
		command.Keymap_Inspection_Request {
			registry = commands.registry,
			activation = commands.profile_activation,
			pending = &commands.pending,
			query = query,
			allocator = commands.persistent_allocator,
		},
	)
	if !inspected {
		interaction.command_catalog_close(&catalog)
		return {}, App_Failure{stage = .Command_Resolution, command = inspection_failure}
	}
	return command_context_present_keymap_inspection_result(
		commands,
		inspection,
		catalog,
		visible,
		constraints,
		false,
	)
}

@(private)
command_context_present_context_map_inspection :: proc(
	commands: ^Command_Context,
	map_id: interaction.Map_ID,
	include_sequences: bool,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.registry == nil || commands.context_maps == nil {
		return {}, App_Failure{stage = .Command_Resolution}
	}
	visible, visible_ok, visible_failure := editor_session.session_visible_target(
		commands.session_owner,
		commands.session_handle,
	)
	if !visible_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = visible_failure}
	}
	catalog, catalog_ok, catalog_failure := interaction.command_catalog_build(
		commands.registry,
		commands.keymap,
		command_context_catalog_context(commands, true, false),
		commands.persistent_allocator,
	)
	if !catalog_ok {
		return {}, App_Failure{stage = .Command_Resolution, interaction = catalog_failure}
	}
	inspection, inspected, inspection_failure := interaction.context_map_inspect(
		commands.context_maps,
		map_id,
		include_sequences,
		commands.persistent_allocator,
	)
	if !inspected {
		interaction.command_catalog_close(&catalog)
		return {}, App_Failure{stage = .Command_Resolution, interaction = inspection_failure}
	}
	return command_context_present_keymap_inspection_result(
		commands,
		inspection,
		catalog,
		visible,
		constraints,
		true,
	)
}

@(private)
command_context_present_keymap_inspection_result :: proc(
	commands: ^Command_Context,
	inspection: interaction.Inspection_Result,
	catalog: interaction.Command_Catalog,
	visible: editor_session.Visible_Target,
	constraints: display.Viewport_Constraints,
	concise: bool,
) -> (Interaction_Result, App_Failure) {
	state := &commands.keymap_inspection_workflow
	keymap_inspection_workflow_reset(state)
	state.inspection = inspection
	state.catalog = catalog
	state.return_target = visible
	state.presentation = .Full
	if concise do state.presentation = .Concise
	if !keymap_inspection_workflow_advance_generation(state) {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	if prepared, prepare_failure := keymap_inspection_workflow_prepare(
		state,
		constraints.height_rows,
	); !prepared {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	target := keymap_inspection_visible_target()
	_, _, presented, present_failure := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if !presented {
		keymap_inspection_workflow_reset(state)
		return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	}
	commands.pending = {}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_command_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.mode != .None {
		return {}, App_Failure{stage = .Prompt}
	}
	if commands.candidate_ui.catalog.state == nil ||
	   commands.candidate_ui.session.state == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_view, candidate_ok, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !candidate_ok || candidate_view.source_kind != .Commands {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, candidate_view.source_kind); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved {
		return {}, resolution_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	request := interaction.Candidate_Request {
		session_id = candidate_view.session_id,
		session_generation = candidate_view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(candidate_view.rows) == 0 {
			return {}, {}
		}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {
			delta = -1
		}
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Command candidate movement", move_failure)
			return Interaction_Result{changed = true}, {}
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 {
			return {}, {}
		}
		if len(candidate_view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Command query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)candidate_view.query)
		copy(query[len(candidate_view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_command_navigation(
			commands,
			string(query[:len(candidate_view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(candidate_view.query) == 0 {
			return {}, {}
		}
		end := len(candidate_view.query) - 1
		bytes := transmute([]u8)candidate_view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 {
			end -= 1
		}
		return command_context_refresh_command_navigation(commands, candidate_view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !candidate_view.has_selection || len(candidate_view.rows) == 0 {
			return {}, {}
		}
		row := candidate_view.rows[candidate_view.selected_row]
		if !command_context_navigation_selection_is_current(commands, candidate_view, row.action) {
			command_context_set_diagnostic(commands, "Interaction profile changed; reopen M-x")
			return Interaction_Result{changed = true}, {}
		}
		command_handle, handle_ok := interaction.command_candidate_action_handle(row.action)
		if !handle_ok {
			return {}, App_Failure{stage = .Command_Resolution}
		}
		entry, found := interaction.command_catalog_entry(
			&commands.candidate_ui.catalog,
			command_handle,
		)
		if !found {
			return {}, App_Failure{stage = .Command_Resolution}
		}
		if command_context_command_navigation_describes(commands) {
			return command_context_describe_navigation_selection(
				commands,
				entry.metadata.name,
				constraints,
			)
		}
		if entry.availability != .Available {
			command_context_set_diagnostic(commands, entry.unavailable_reason)
			return Interaction_Result{changed = true}, {}
		}
		return command_context_execute_navigation_selection(
			commands,
			commands.candidate_ui.return_target,
			request,
			row.identity,
			row.durable_category,
			row.durable_key,
			command_handle,
			constraints,
		)
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_command_navigation(commands, commands.candidate_ui.return_target)
	}
	return {}, {}
}

@(private)
dispatch_buffer_navigation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.mode != .None {
		return {}, App_Failure{stage = .Prompt}
	}
	if commands.candidate_ui.session.state == nil {
		return {}, App_Failure{stage = .Component_Access}
	}
	candidate_view, candidate_ok, candidate_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !candidate_ok || candidate_view.source_kind != .Session_Buffers ||
	   candidate_view.scope_identity != u64(commands.session_handle.session_id) ||
	   candidate_view.scope_generation != u64(commands.session_handle.generation) {
		return {}, App_Failure{stage = .Component_Access, candidate = candidate_failure}
	}
	if map_failure := command_context_sync_candidate_map(commands, candidate_view.source_kind);
	   map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved {
		return {}, resolution_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	request := interaction.Candidate_Request {
		session_id = candidate_view.session_id,
		session_generation = candidate_view.session_generation,
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if len(candidate_view.rows) == 0 {return {}, {}}
		delta := i32(1)
		if contextual_route == .Component_Previous_Row {delta = -1}
		_, moved, move_failure := interaction.candidate_session_move(
			&commands.candidate_ui.session,
			request,
			delta,
		)
		if !moved {
			command_context_candidate_failure_diagnostic(commands, "Buffer candidate movement", move_failure)
			return Interaction_Result{changed = true}, {}
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Query_Text {
		if len(resolution.text) == 0 {return {}, {}}
		if len(candidate_view.query) + len(resolution.text) > int(interaction.MAX_CANDIDATE_QUERY_BYTES) {
			command_context_set_diagnostic(commands, "Buffer query limit reached")
			return Interaction_Result{changed = true}, {}
		}
		query: [interaction.MAX_CANDIDATE_QUERY_BYTES]u8
		copy(query[:], transmute([]u8)candidate_view.query)
		copy(query[len(candidate_view.query):], transmute([]u8)resolution.text)
		return command_context_refresh_buffer_navigation(
			commands,
			string(query[:len(candidate_view.query) + len(resolution.text)]),
		)
	}
	if contextual_route == .Component_Query_Delete_Previous {
		if len(candidate_view.query) == 0 {return {}, {}}
		end := len(candidate_view.query) - 1
		bytes := transmute([]u8)candidate_view.query
		for end > 0 && bytes[end] & 0xc0 == 0x80 {end -= 1}
		return command_context_refresh_buffer_navigation(commands, candidate_view.query[:end])
	}
	if contextual_route == .Component_Activate_Current {
		if !candidate_view.has_selection || len(candidate_view.rows) == 0 {return {}, {}}
		row := candidate_view.rows[candidate_view.selected_row]
		buffer_route := command_context_buffer_navigation_route(commands)
		other_pane := buffer_route == .Switch_To_Buffer_Other_Pane ||
		              buffer_route == .Display_Buffer_Other_Pane
		focus_other_pane := buffer_route == .Switch_To_Buffer_Other_Pane
		activated_entry: editor_session.Entry_Handle
		if row.action.kind == .Activate_Buffer {
			entry, entry_ok := interaction.buffer_candidate_action_entry(
				row.action,
				commands.session_handle,
			)
			if !entry_ok || !command_context_buffer_candidate_is_current(commands, row.action) {
				command_context_set_diagnostic(commands, "Buffer candidate changed; reopen switch-to-buffer")
				return Interaction_Result{changed = true}, {}
			}
			if other_pane {
				displayed, display_failure := command_context_layout_display_entry(
					commands,
					entry,
					focus_other_pane,
				)
				if !displayed {
					command_context_layout_display_diagnostic(commands, display_failure)
					return Interaction_Result{changed = true}, {}
				}
			} else {
				_, activated, activation_failure := editor_session.session_activate(
					commands.session_owner,
					entry,
				)
				if !activated {
					command_context_set_diagnostic(commands, "Buffer candidate changed; reopen switch-to-buffer")
					_ = activation_failure
					return Interaction_Result{changed = true}, {}
				}
			}
			activated_entry = entry
		} else if row.action.kind == .Create_Buffer {
			current, current_ok := command_context_buffer_registry_generation(commands)
			if !current_ok || current != row.action.owner_generation {
				command_context_set_diagnostic(commands, "Buffer inventory changed; reopen switch-to-buffer")
				return Interaction_Result{changed = true}, {}
			}
			switched_result, switched, switch_failure := command.buffer_session_switch_to_buffer(
				command.Buffer_Session_Context {
					session = commands.session_owner,
					handle = commands.session_handle,
					command = commands.document_workflow.buffer_command,
					configuration = commands.entry_configuration,
				},
				row.label,
			)
			if !switched {
				command_context_buffer_session_diagnostic(commands, switch_failure)
				return Interaction_Result{changed = true}, {}
			}
			if other_pane {
				displayed, display_failure := command_context_layout_display_entry(
					commands,
					switched_result.entry,
					focus_other_pane,
				)
				if !displayed {
					target := candidate_ui_visible_target()
					_, _, _, _ = editor_session.session_present_ui(
						commands.session_owner,
						commands.session_handle,
						target.ui,
					)
					command_context_layout_display_diagnostic(commands, display_failure)
					return Interaction_Result{changed = true}, {}
				}
			}
			activated_entry = switched_result.entry
		} else {
			return {}, App_Failure{stage = .Component_Access}
		}
		if buffer_route == .Display_Buffer_Other_Pane {
			if commands.candidate_ui.return_target.kind != .Primary_View {
				return {}, App_Failure{stage = .Session_Access}
			}
			_, restored, restore_failure := editor_session.session_activate(
				commands.session_owner,
				commands.candidate_ui.return_target.entry,
			)
			if !restored {
				return {}, App_Failure{stage = .Session_Access, editor_session = restore_failure}
			}
		} else {
			_, visual_failure := command_context_modal_visual_finish_buffer_switch(
				commands,
				activated_entry,
			)
			if visual_failure.stage != .None do return {}, visual_failure
		}
		_ = command_context_candidate_history_record(
			commands,
			row.durable_category,
			row.durable_key,
		)
		_, recorded, record_failure := interaction.candidate_session_record_success(
			&commands.candidate_ui.session,
			request,
			row.identity,
		)
		command_context_deactivate_context_map(commands, .Completed)
		command_context_close_buffer_navigation(commands)
		if !recorded {
			command_context_candidate_failure_diagnostic(commands, "Buffer candidate recency", record_failure)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return command_context_leave_buffer_navigation(commands, commands.candidate_ui.return_target)
	}
	return {}, {}
}

@(private)
command_context_buffer_navigation_route :: proc(commands: ^Command_Context) -> command.Native_Route {
	if commands == nil || commands.document_workflow.buffer_command.registry_generation ==
	   interaction.Registry_Generation(0) {
		return .Switch_To_Buffer
	}
	metadata, metadata_ok, _ := interaction.command_metadata(
		commands.registry,
		commands.document_workflow.buffer_command,
	)
	if !metadata_ok {
		return .Switch_To_Buffer
	}
	route, route_ok := command.native_route_decode(metadata.route)
	if !route_ok {
		return .Switch_To_Buffer
	}
	return route
}

@(private)
command_context_buffer_registry_generation :: proc(commands: ^Command_Context) -> (u64, bool) {
	descriptors, copied, _ := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied {return 0, false}
	defer editor_session.descriptor_batch_close(&descriptors)
	if len(descriptors.descriptors) == 0 {return 0, false}
	return u64(descriptors.descriptors[0].graph.entry.registry.generation), true
}

@(private)
command_context_buffer_candidate_is_current :: proc(
	commands: ^Command_Context,
	action: interaction.Candidate_Action,
) -> bool {
	descriptors, copied, _ := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied {return false}
	defer editor_session.descriptor_batch_close(&descriptors)
	for descriptor in descriptors.descriptors {
		if interaction.buffer_candidate_action_graph_matches(action, descriptor.graph) {return true}
	}
	return false
}

@(private)
command_context_leave_buffer_navigation :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if viewed {
		_, cancelled, cancel_failure := interaction.candidate_session_cancel(
			&commands.candidate_ui.session,
			interaction.Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
		)
		if !cancelled {
			return {}, App_Failure{stage = .Component_Access, candidate = cancel_failure}
		}
	} else {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	defer command_context_close_buffer_navigation(commands)
	commands.diagnostic_length = 0
	if return_target.kind != .Primary_View {
		return {}, App_Failure{stage = .Session_Access}
	}
	_, activated, activation_failure := editor_session.session_activate(
		commands.session_owner,
		return_target.entry,
	)
	if !activated {
		return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_close_buffer_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(&commands.candidate_ui.session)
	}
	commands.candidate_ui.return_target = {}
	commands.document_workflow.buffer_command = {}
}

@(private)
command_context_navigation_selection_is_current :: proc(
	commands: ^Command_Context,
	view: interaction.Candidate_View,
	action: interaction.Candidate_Action,
) -> bool {
	if commands == nil || commands.keymap == nil ||
	   view.source_kind != .Commands ||
	   view.scope_identity != u64(commands.registry_generation) ||
	   action.kind != .Invoke_Command ||
	   action.owner_generation != u64(commands.registry_generation) {
		return false
	}
	stats, stats_ok, _ := interaction.snapshot_stats(commands.keymap)
	return stats_ok && view.scope_generation == u64(stats.generation) &&
	       view.source_generation == u64(stats.generation)
}

@(private)
command_context_refresh_command_navigation :: proc(
	commands: ^Command_Context,
	query: string,
) -> (Interaction_Result, App_Failure) {
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if !viewed {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	_, refreshed, refresh_failure := interaction.candidate_session_set_query(
		&commands.candidate_ui.session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		query,
	)
	if !refreshed {
		command_context_candidate_failure_diagnostic(commands, "Command candidate query", refresh_failure)
		return Interaction_Result{changed = true}, {}
	}
	commands.diagnostic_length = 0
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_leave_command_navigation :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
) -> (Interaction_Result, App_Failure) {
	pending, pending_ok := interaction.profile_activation_modal_pending_inspect(
		commands.profile_activation,
	)
	if pending_ok && pending.kind == .Command_Entry {
		_ = interaction.profile_activation_modal_pending_cancel(commands.profile_activation)
	}
	command_context_deactivate_context_map(commands, .Completed)
	view, viewed, view_failure := interaction.candidate_session_view(
		&commands.candidate_ui.session,
	)
	if viewed {
		_, cancelled, cancel_failure := interaction.candidate_session_cancel(
			&commands.candidate_ui.session,
			interaction.Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
		)
		if !cancelled {
			return {}, App_Failure{stage = .Component_Access, candidate = cancel_failure}
		}
	} else if commands.candidate_ui.session.state != nil {
		return {}, App_Failure{stage = .Component_Access, candidate = view_failure}
	}
	defer command_context_close_command_navigation(commands)
	commands.diagnostic_length = 0
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, presentation_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			return {}, App_Failure{stage = .Session_Access, editor_session = presentation_failure}
		}
	case .None:
		return {}, App_Failure{stage = .Session_Access}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_describe_navigation_selection :: proc(
	commands: ^Command_Context,
	command_name: string,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	name: [interaction.MAX_COMMAND_NAME_BYTES]u8
	if len(command_name) == 0 || len(command_name) > len(name) {
		return {}, App_Failure{stage = .Command_Resolution}
	}
	name_length := copy(name[:], transmute([]u8)command_name)
	return_target := commands.candidate_ui.return_target
	left, leave_failure := command_context_leave_command_navigation(commands, return_target)
	if leave_failure.stage != .None do return {}, leave_failure
	access, access_ok, access_failure := editor_session.session_active_entry_access(
		commands.session_owner,
		commands.session_handle,
	)
	if !access_ok {
		return {}, App_Failure{stage = .Session_Access, editor_session = access_failure}
	}
	entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, App_Failure{stage = .Session_Access, editor_session = borrow_failure}
	}
	command_context_bind_entry(commands, access.entry, entry)
	result, present_failure := command_context_present_keymap_inspection(
		commands,
		interaction.Inspection_Query {
			kind = .Command,
			command_name = string(name[:name_length]),
		},
		entry.buffer,
		entry.view_registry,
		entry.primary_view,
		constraints,
	)
	_, reconciled, reconcile_failure := editor_session.entry_access_reconcile(access)
	if !reconciled {
		return {}, App_Failure{stage = .Session_Access, editor_session = reconcile_failure}
	}
	result.changed = result.changed || left.changed
	return result, present_failure
}

@(private)
command_context_execute_navigation_selection :: proc(
	commands: ^Command_Context,
	return_target: editor_session.Visible_Target,
	request: interaction.Candidate_Request,
	identity: interaction.Candidate_Identity,
	durable_category: interaction.Candidate_Durable_Category,
	durable_key: string,
	command_handle: interaction.Command_Handle,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	command_context_deactivate_context_map(commands, .Completed)
	switch return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(
			commands.session_owner,
			return_target.entry,
		)
		if !activated {
			command_context_close_command_navigation(commands)
			return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
		}
	case .UI_Root:
		_, _, presented, presentation_failure := editor_session.session_present_ui(
			commands.session_owner,
			commands.session_handle,
			return_target.ui,
		)
		if !presented {
			command_context_close_command_navigation(commands)
			return {}, App_Failure{stage = .Session_Access, editor_session = presentation_failure}
		}
	case .None:
		command_context_close_command_navigation(commands)
		return {}, App_Failure{stage = .Session_Access}
	}
	navigation_session := commands.candidate_ui.session
	navigation_catalog := commands.candidate_ui.catalog
	commands.candidate_ui.session = {}
	commands.candidate_ui.catalog = {}
	commands.candidate_ui.return_target = {}
	commands.document_workflow.buffer_command = {}
	defer {
		if navigation_session.state != nil {
			_, _, _ = interaction.candidate_session_close(&navigation_session)
		}
		if navigation_catalog.state != nil {
			interaction.command_catalog_close(&navigation_catalog)
		}
	}
	_ = constraints
	_ = command_context_candidate_history_record(commands, durable_category, durable_key)
	_, recorded, record_failure := interaction.candidate_session_record_success(
		&navigation_session,
		request,
		identity,
	)
	if !recorded {
		command_context_candidate_failure_diagnostic(commands, "Command candidate recency", record_failure)
	}
	return Interaction_Result{changed = true, deferred_command = command_handle}, {}
}

@(private)
command_context_close_command_navigation :: proc(commands: ^Command_Context) {
	if commands.candidate_ui.session.state != nil {
		_, _, _ = interaction.candidate_session_close(
			&commands.candidate_ui.session,
		)
	}
	if commands.candidate_ui.catalog.state != nil {
		interaction.command_catalog_close(&commands.candidate_ui.catalog)
	}
	commands.candidate_ui.return_target = {}
	commands.document_workflow.buffer_command = {}
}

@(private)
dispatch_startup_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	if commands.prompt_workflow.mode != .None {
		if commands.prompt_workflow.mode != .Project_Create_Directory &&
		   commands.prompt_workflow.mode != .Find_File &&
		   commands.prompt_workflow.mode != .Find_File_Other_Pane &&
		   commands.prompt_workflow.mode != .Switch_To_Buffer {
			return {}, App_Failure{stage = .Prompt}
		}
		return dispatch_prompt(commands, nil, nil, {}, input, constraints)
	}
	if prepared, prepare_failure := startup_workflow_prepare(
		&commands.startup_workflow,
		constraints.height_rows,
	); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Startup); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(
		commands,
		input,
	)
	if !resolved {
		return {}, resolution_failure
	}
	if resolution.kind != .Command {
		return {}, {}
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	native_route, native_ok := command.native_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		changed, moved, move_failure := startup_workflow_move(
			&commands.startup_workflow,
			delta,
		)
		if !moved {
			return {}, App_Failure{stage = .UI, ui = move_failure}
		}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_route == .Component_Activate_Current {
		action, action_ok := startup_workflow_current_action(&commands.startup_workflow)
		if !action_ok {
			return {}, App_Failure{stage = .UI}
		}
		if action == STARTUP_OPEN_PROJECT_DIRECTORY_ACTION {
			return command_context_begin_project_prompt(commands, .Project_Create_Directory, {})
		}
		if action == STARTUP_OPEN_PROJECT_ACTION {
			return command_context_present_project_navigation(commands)
		}
		if action == STARTUP_OPEN_WORKSPACE_ACTION {
			return command_context_present_workspace_navigation(commands)
		}
		mode := Prompt_Mode.Switch_To_Buffer
		if action == STARTUP_OPEN_PATH_ACTION {
			mode = .Find_File
		} else if action != STARTUP_CREATE_BUFFER_ACTION {
			return {}, App_Failure{stage = .UI}
		}
		return command_context_begin_buffer_prompt(commands, mode, {})
	}
	if native_ok && native_route == .Find_File {
		return command_context_begin_buffer_prompt(commands, .Find_File, resolution.command)
	}
	if native_ok && native_route == .Switch_To_Buffer {
		return command_context_present_buffer_navigation(commands, constraints, resolution.command)
	}
	if native_ok && native_route == .Find_File_Other_Pane {
		return command_context_begin_buffer_prompt(commands, .Find_File_Other_Pane, resolution.command)
	}
	if native_ok &&
	   (native_route == .Switch_To_Buffer_Other_Pane ||
	    native_route == .Display_Buffer_Other_Pane) {
		return command_context_present_buffer_navigation(commands, constraints, resolution.command)
	}
	if native_ok && native_route == .Request_Editor_Exit {
		return command_context_request_exit(commands, resolution.command, nil)
	}
	if native_ok && native_route == .Keyboard_Quit {
		commands.pending = {}
		return {}, {}
	}
	return {}, {}
}
