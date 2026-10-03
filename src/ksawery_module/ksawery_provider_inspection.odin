// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import bridge "../ksawery_bridge"
import "../ksawery"
import "../ui"
import "base:runtime"
import "core:fmt"

/* ksawery_workflow_open_provider_inspection enters the bounded provider surface. */
ksawery_workflow_open_provider_inspection :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || !state.active || state.view_mode == .Provider_Inspection do return false
	state.provider_inspection_return_mode = state.view_mode
	state.provider_inspection_return_position = state.position
	state.position = {}
	state.view_mode = .Provider_Inspection
	return true
}

/* ksawery_workflow_return_from_provider_inspection restores the exact Ksawery surface. */
ksawery_workflow_return_from_provider_inspection :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Provider_Inspection do return false
	return_mode := state.provider_inspection_return_mode
	if return_mode == .Provider_Inspection do return_mode = .Status
	state.view_mode = return_mode
	state.position = state.provider_inspection_return_position
	state.provider_inspection_return_mode = .Status
	state.provider_inspection_return_position = {}
	return true
}

/* ksawery_provider_inspection_snapshot composes provider and Process identity without mutation. */
ksawery_provider_inspection_snapshot :: proc(
	state: ^Ksawery_Workflow_State,
) -> (inspection: ksawery.Contributor_Inspection, available: bool) {
	if state == nil do return {}, false
	inspection, available = ksawery_extension_provider_inspect(&state.extension_registry)
	if !available do return
	if state.extension_registry.latest_failure.code != .None {
		inspection.latest_failure = state.extension_registry.latest_failure
	}
	if state.extension_operation != nil && state.extension_operation.active &&
	   state.process_coordinator.active &&
	   state.process_coordinator.active_authority.kind == .External_Operation {
		inspection.active_process = state.process_coordinator.active_authority.operation
	}
	return
}

/* ksawery_provider_inspection_list_definitions renders one bounded provider inventory. */
ksawery_provider_inspection_list_definitions :: proc(
	commands: ^Command_Context,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if commands == nil || commands.ksawery_workflow == nil || viewport_items == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	state := commands.ksawery_workflow
	inspection, available := ksawery_provider_inspection_snapshot(state)
	contribution_count := 0
	if state.extension_registry.active != nil {
		contribution_count = len(state.extension_registry.active.contributions)
	}
	count := min(17 + contribution_count, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_provider_inspection_append_row(rows, storage, &write, "Ksawery Providers") ||
	   !ksawery_provider_inspection_append_row(
		rows, storage, &write,
		fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)),
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if !available {
		_ = ksawery_provider_inspection_append_row(rows, storage, &write, "Personal provider: absent")
		_ = ksawery_provider_inspection_append_configuration_row(commands, rows, storage, &write)
		_ = ksawery_provider_inspection_append_row(rows, storage, &write, "Effective provider: built-in fallback")
		_ = ksawery_provider_inspection_append_row(rows, storage, &write, "Actions: L reload; q return", false, false)
		state.position = {
			presentation_generation = 1,
			selection_owner = .View,
			current_item = i32(write - 1),
			first_visible_item = 0,
			viewport_items = min(viewport_items, u32(write)),
		}
		return rows[:write], storage, true
	}
	provider := state.extension_registry.active
	identity := string(inspection.identity.bytes[:inspection.identity.length])
	label := string(inspection.display_name.bytes[:inspection.display_name.length])
	provenance := string(inspection.provenance.bytes[:inspection.provenance.length])
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf("Contributor: %s (%s)", label, identity))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
		"Generation: contributor=%d personal=%d lifecycle=%v enabled=%v",
		inspection.handle.generation,
		state.extension_registry.personal_generation,
		inspection.lifecycle,
		provider.enabled,
	))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf("Provenance: origin=%v source=%s", inspection.provenance.origin, provenance))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf("Authority: %v", inspection.requested_authority))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
		"Inventory: contributions=%d provider-roles=%d",
		inspection.contribution_count,
		inspection.provider_role_count,
	))
	_ = ksawery_provider_inspection_append_configuration_row(commands, rows, storage, &write)
	for contribution, index in provider.contributions {
		contribution_identity := bridge.ksawery_extension_text(
			provider.text,
			contribution.identity_offset,
			contribution.identity_bytes,
		)
		if !ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
			"  %d. %s kind=%v role=%v observations=0x%x authority=0x%x",
			index + 1,
			contribution_identity,
			ksawery.Contribution_Kind(contribution.kind),
			ksawery.Provider_Role(contribution.provider_role),
			contribution.required_observations,
			contribution.requested_authorities,
		)) {
			break
		}
	}
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
		"Limits: deadline=%dns memory=%d callbacks=%d retained=%d",
		provider.limits.turn_deadline_ns,
		provider.limits.custodian_memory_bytes,
		provider.limits.callbacks_per_turn,
		provider.limits.retained_native_bytes,
	))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
		"Usage: turns=%d callbacks=%d failures=%d declaration=%d retained=%d",
		inspection.usage.turns,
		inspection.usage.callbacks,
		inspection.usage.failures,
		inspection.usage.declaration_bytes,
		inspection.usage.retained_native_bytes,
	))
	if inspection.latest_failure.code != .None {
		_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf(
			"Latest failure: operation=%v code=%v limit=%d actual=%d diagnostic-bytes=%d",
			inspection.latest_failure.operation,
			inspection.latest_failure.code,
			inspection.latest_failure.limit,
			inspection.latest_failure.actual,
			inspection.latest_failure.diagnostic_bytes,
		), true)
	} else {
		_ = ksawery_provider_inspection_append_row(rows, storage, &write, "Latest failure: none")
	}
	active_process := "none"
	if inspection.active_process != ksawery.Repository_Operation_ID(0) {
		active_process = fmt.tprintf("%d", inspection.active_process)
	}
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf("Active Process: %s", active_process))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, fmt.tprintf("Effective provider: %s", provider.enabled ? identity : "built-in fallback"))
	_ = ksawery_provider_inspection_append_row(rows, storage, &write, "Actions: L reload; z disable; q return", false, false)
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = i32(write - 1),
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return rows[:write], storage, true
}

/* ksawery_workflow_reload_provider performs one atomic personal-generation reload. */
ksawery_workflow_reload_provider :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	if commands.ksawery_workflow.view_mode != .Provider_Inspection {
		command_context_set_diagnostic(commands, "Open Ksawery Providers with v before reloading")
		return Interaction_Result{changed = true}, {}
	}
	if !ksawery_workflow_provider_lifecycle_is_idle(commands.ksawery_workflow) {
		command_context_set_diagnostic(commands, "Provider reload is unavailable while a repository operation is active")
		return Interaction_Result{changed = true}, {}
	}
	return command_context_reload_personal_commands(commands)
}

/* ksawery_workflow_disable_provider revokes routes and projections before fallback. */
ksawery_workflow_disable_provider :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	if commands.ksawery_workflow.view_mode != .Provider_Inspection {
		command_context_set_diagnostic(commands, "Open Ksawery Providers with v before disabling")
		return Interaction_Result{changed = true}, {}
	}
	state := commands.ksawery_workflow
	if !ksawery_workflow_provider_lifecycle_is_idle(state) {
		command_context_set_diagnostic(commands, "Provider disablement is unavailable while a repository operation is active")
		return Interaction_Result{changed = true}, {}
	}
	if state.extension_registry.active == nil {
		command_context_set_diagnostic(commands, "No personal Ksawery provider is active")
		return Interaction_Result{changed = true}, {}
	}
	handle := state.extension_registry.active.inspection.handle
	disabled, _ := ksawery_extension_provider_disable(&state.extension_registry, handle)
	if !disabled {
		command_context_set_diagnostic(commands, "Personal Ksawery provider is already disabled or stale")
		return Interaction_Result{changed = true}, {}
	}
	state.extension_status = nil
	state.extension_status_selection = {}
	state.extension_annotation_selection = {}
	command_context_set_diagnostic(commands, "Personal Ksawery provider disabled; built-in fallback active")
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_provider_lifecycle_is_idle :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil do return false
	return state.process.state == nil && !state.process_coordinator.active &&
	       !state.extension_command_workflow.active && state.extension_command_family == nil &&
	       (state.extension_operation == nil || !state.extension_operation.active) &&
	       (state.conflict_assistance == nil || !state.conflict_assistance.operation.active) &&
	       (state.extension_registry.active == nil || !state.extension_registry.active.turn_active)
}

@(private)
ksawery_provider_inspection_append_configuration_row :: proc(
	commands: ^Command_Context,
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
) -> bool {
	configuration := commands.personal_configuration
	return ksawery_provider_inspection_append_row(
		rows, storage, write,
		fmt.tprintf(
			"Personal configuration: status=%v confirmed=%d rejected=%d diagnostic-bytes=%d",
			configuration.status,
			configuration.confirmed_generation,
			configuration.rejected_generation,
			configuration.diagnostic_length,
		),
		configuration.status == .Rejected,
	)
}

@(private)
ksawery_provider_inspection_append_row :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	label: string,
	destructive := false,
	passive := true,
) -> bool {
	if write == nil do return false
	return ksawery_append_presented_label(
		rows, storage, write,
		ui.List_Item_ID(0xF300_0000_0000_0000) + ui.List_Item_ID(write^ + 1),
		label, passive,
		{surface = .Inspection, subject = destructive ? .Failure : .Section, destructive = destructive},
	)
}
