// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../editor"
import "../interaction"
import editor_view "../view"
import "core:fmt"

@(private)
Modal_Repeat_Plan :: struct {
	route:        command.Native_Route,
	entry_route:  command.Native_Route,
	count:        u64,
	replace_text: bool,
	explicit:     command.Native_Explicit_Range,
	text:         [interaction.MAX_MODAL_REPEAT_TEXT_BYTES]u8,
	text_length:  u16,
}

@(private)
command_context_modal_repeat_state :: proc(
	commands: ^Command_Context,
	create: bool,
) -> ^interaction.Modal_Repeat_State {
	if commands == nil do return nil
	if commands.modal_repeat != nil || !create do return commands.modal_repeat
	if commands.persistent_allocator.procedure == nil do return nil
	state, allocation_error := new(
		interaction.Modal_Repeat_State,
		commands.persistent_allocator,
	)
	if allocation_error != nil do return nil
	commands.modal_repeat = state
	return state
}

@(private)
command_context_modal_repeat_inspect :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := command_context_modal_repeat_state(commands, false)
	if state == nil {
		command_context_set_diagnostic(commands, "No modal change is available to repeat")
		return Interaction_Result{changed = true}, {}
	}
	record, retained := interaction.modal_repeat_inspect(state)
	if !retained {
		command_context_set_diagnostic(commands, "No modal change is available to repeat")
		return Interaction_Result{changed = true}, {}
	}
	operation_name := "pending insert"
	handle := record.operation
	if handle.registry_generation == interaction.Registry_Generation(0) {
		handle = record.entry_operation
	}
	if handle.registry_generation != interaction.Registry_Generation(0) {
		metadata, found, _ := interaction.command_metadata(commands.registry, handle)
		if found do operation_name = metadata.name
	}
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Last modal change: kind=%v operation=%s operator=%v target=%v count=%d text-bytes=%d selection=%v named-slot=%q profile=%d/%d catalog=%d snapshot=%d",
		record.kind,
		operation_name,
		record.operator,
		record.target,
		record.count,
		record.text_length,
		record.selection_shape,
		interaction.modal_repeat_record_named_slot(&record),
		record.profile.id,
		record.profile.revision,
		record.catalog_generation,
		record.snapshot_generation,
	)
	commands.diagnostic_length = len(message)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_modal_repeat_identity :: proc(
	commands: ^Command_Context,
) -> (
	profile: interaction.Profile_Identity,
	catalog_generation: interaction.Profile_Catalog_Generation,
	snapshot_generation: interaction.Snapshot_Generation,
	ok: bool,
) {
	if commands == nil || commands.profile_activation == nil do return {}, 0, 0, false
	active_profile, _, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected do return {}, 0, 0, false
	catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
	if !catalog_ok do return {}, 0, 0, false
	modal := false
	for candidate in catalog.profiles {
		if candidate.identity == active_profile {
			modal = candidate.name == "modal"
			break
		}
	}
	if !modal do return {}, 0, 0, false
	return active_profile, catalog.generation, commands.profile_activation.generation, true
}

@(private)
command_context_modal_repeat_record_base :: proc(
	commands: ^Command_Context,
	kind: interaction.Modal_Repeat_Kind,
	operation: interaction.Command_Handle,
) -> (interaction.Modal_Repeat_Record, bool) {
	profile, catalog_generation, snapshot_generation, current :=
		command_context_modal_repeat_identity(commands)
	if !current do return {}, false
	return interaction.Modal_Repeat_Record {
		kind = kind,
		operation = operation,
		profile = profile,
		catalog_generation = catalog_generation,
		snapshot_generation = snapshot_generation,
		count = 1,
	}, true
}

@(private)
command_context_modal_repeat_capture :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	operation: interaction.Command_Handle,
	modal_operator: interaction.Modal_Operator_Result,
	modal_operator_active: bool,
	count: u64,
	count_explicit: bool,
	completion: command.Native_Completion,
) {
	if commands == nil do return
	if route == .Modal_Repeat_Last_Change do return
	_, _, _, modal_active := command_context_modal_repeat_identity(commands)
	if !modal_active do return
	state := command_context_modal_repeat_state(commands, true)
	if state == nil do return
	if route == .Modal_Enter_Normal {
		_ = interaction.modal_repeat_insert_finish(state)
		return
	}
	if route == .Modal_Enter_Insert || route == .Modal_Enter_Insert_After ||
	   route == .Modal_Enter_Insert_Line_First || route == .Modal_Enter_Insert_Line_End ||
	   route == .Modal_Open_Line_Below || route == .Modal_Open_Line_Above ||
	   route == .Modal_Enter_Replace {
		record, current := command_context_modal_repeat_record_base(
			commands, .Insert_Session, {},
		)
		if !current do return
		record.entry_operation = operation
		record.replace_text = route == .Modal_Enter_Replace
		changed := completion == .Buffer_Committed
		_ = interaction.modal_repeat_insert_begin(state, record, changed)
		return
	}
	if modal_operator_active && completion == .Buffer_Committed {
		record, current := command_context_modal_repeat_record_base(
			commands, .Operator, operation,
		)
		if !current do return
		record.operator = modal_operator.operator
		record.target = modal_operator.target
		record.character_target = modal_operator.character_target
		record.count = modal_operator.count
		record.count_explicit = modal_operator.count_explicit
		record.selection_shape = interaction.profile_activation_modal_visual_kind(
			commands.profile_activation,
		)
		captured_operator := modal_operator
		target_text := interaction.modal_operator_result_text(&captured_operator)
		if len(target_text) > 0 {
			copy(record.target_text[:], transmute([]u8)target_text)
			record.target_text_length = u8(len(target_text))
		}
		slot := interaction.modal_operator_result_named_slot(&captured_operator)
		if len(slot) > 0 {
			copy(record.named_slot[:], transmute([]u8)slot)
			record.named_slot_length = u8(len(slot))
		}
		if modal_operator.operator == .Change {
			_ = interaction.modal_repeat_insert_begin(state, record, true)
		} else {
			_ = interaction.modal_repeat_record(state, record)
		}
		return
	}
	if route == .Insert_Text && completion == .Buffer_Committed {
		if !state.pending_active {
			record, current := command_context_modal_repeat_record_base(
				commands, .Insert_Session, {},
			)
			if !current do return
			_ = interaction.modal_repeat_insert_begin(state, record)
		}
		return
	}
	if completion != .Buffer_Committed do return
	#partial switch route {
	case .Delete_Previous_Grapheme, .Delete_Next_Grapheme, .Yank, .Yank_After_Point:
		record, current := command_context_modal_repeat_record_base(
			commands, .Command, operation,
		)
		if current {
			record.count = count
			record.count_explicit = count_explicit
			_ = interaction.modal_repeat_record(state, record)
		}
	case:
	}
}

@(private)
command_context_modal_repeat_append_text :: proc(
	commands: ^Command_Context,
	operation: interaction.Command_Handle,
	text: string,
	replace_text: bool,
) {
	if commands == nil || len(text) == 0 do return
	state := command_context_modal_repeat_state(commands, true)
	if state == nil do return
	if !interaction.modal_repeat_insert_append(
		state, operation, text, replace_text,
	) {
		command_context_set_diagnostic(commands, "Last modal change exceeds the repeat limit")
	}
}

@(private)
command_context_modal_repeat_append_indentation :: proc(
	commands: ^Command_Context,
	operation: interaction.Command_Handle,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) {
	logical, viewed, _ := editor_view.snapshot(view_registry, view)
	if !viewed do return
	policy := logical.indentation_policy.policy
	if policy.indent_width == 0 || policy.indent_width > editor_view.MAX_TAB_WIDTH do return
	if policy.representation == .Tabs {
		command_context_modal_repeat_append_text(commands, operation, "\t", false)
		return
	}
	spaces: [editor_view.MAX_TAB_WIDTH]u8
	for index in 0 ..< int(policy.indent_width) do spaces[index] = ' '
	command_context_modal_repeat_append_text(
		commands, operation, string(spaces[:policy.indent_width]), false,
	)
}

@(private)
command_context_modal_repeat_prepare :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	count_override: u64,
	count_explicit: bool,
) -> (plan: Modal_Repeat_Plan, ready: bool, failure: App_Failure) {
	state := command_context_modal_repeat_state(commands, false)
	if state == nil {
		command_context_set_diagnostic(commands, "No modal change is available to repeat")
		return {}, false, {}
	}
	record, retained := interaction.modal_repeat_inspect(state)
	if !retained {
		command_context_set_diagnostic(commands, "No modal change is available to repeat")
		return {}, false, {}
	}
	profile, catalog_generation, _, current :=
		command_context_modal_repeat_identity(commands)
	if !current || record.profile != profile ||
	   record.catalog_generation != catalog_generation ||
	   record.operation.registry_generation != interaction.Registry_Generation(0) &&
	   record.operation.registry_generation != commands.registry_generation ||
	   record.entry_operation.registry_generation != interaction.Registry_Generation(0) &&
	   record.entry_operation.registry_generation != commands.registry_generation {
		command_context_set_diagnostic(commands, "The last modal change is stale")
		return {}, false, {}
	}
	plan.count = record.count
	if plan.count == 0 do plan.count = 1
	if count_explicit do plan.count = count_override
	plan.replace_text = record.replace_text
	retained_text := interaction.modal_repeat_record_text(&record)
	if len(retained_text) > 0 {
		copy(plan.text[:], transmute([]u8)retained_text)
		plan.text_length = u16(len(retained_text))
	}
	if record.kind == .Insert_Session {
		plan.route = .Insert_Text
		if record.entry_operation.registry_generation != interaction.Registry_Generation(0) {
			entry_metadata, entry_ok, _ := interaction.command_metadata(
				commands.registry, record.entry_operation,
			)
			if !entry_ok {
				command_context_set_diagnostic(commands, "The last modal change is stale")
				return {}, false, {}
			}
			entry_route, decoded := command.native_route_decode(entry_metadata.route)
			if !decoded {
				command_context_set_diagnostic(commands, "The last modal change is incompatible")
				return {}, false, {}
			}
			plan.entry_route = entry_route
		}
		if plan.text_length == 0 && plan.entry_route != .Modal_Open_Line_Below &&
		   plan.entry_route != .Modal_Open_Line_Above {
			command_context_set_diagnostic(commands, "No inserted text is available to repeat")
			return {}, false, {}
		}
		return plan, true, {}
	}
	if record.kind == .Command {
		metadata, metadata_ok, _ := interaction.command_metadata(commands.registry, record.operation)
		if !metadata_ok {
			command_context_set_diagnostic(commands, "The last modal change is stale")
			return {}, false, {}
		}
		plan.route, ready = command.native_route_decode(metadata.route)
		if !ready do command_context_set_diagnostic(commands, "The last modal change is incompatible")
		return plan, ready, {}
	}
	if record.kind != .Operator {
		command_context_set_diagnostic(commands, "The last modal change is incompatible")
		return {}, false, {}
	}
	operation := interaction.Modal_Operator_Result {
		disposition = .Ready,
		operator = record.operator,
		target = record.target,
		character_target = record.character_target,
		count = plan.count,
		count_explicit = record.count_explicit || count_explicit,
		named_slot = record.named_slot,
		named_slot_length = record.named_slot_length,
	}
	copy(operation.text[:], record.target_text[:record.target_text_length])
	operation.text_length = record.target_text_length
	request, request_ok := command_context_modal_navigation_request(
		commands, buffer, view, interaction.Input{kind = .Key, stroke = {kind = .Escape}},
	)
	if !request_ok {
		command_context_set_diagnostic(commands, "The last modal change is unavailable here")
		return {}, false, {}
	}
	operation.capture = {
		profile = request.profile,
		state = request.state,
		catalog_generation = request.catalog_generation,
		snapshot_generation = request.snapshot_generation,
		ctx = request.ctx,
		view_identity = request.view_identity,
		view_generation = request.view_generation,
		buffer_identity = request.buffer_identity,
		buffer_revision = request.buffer_revision,
		point_offset = request.point_offset,
	}
	if operation.target == .Named_Slot_Before || operation.target == .Named_Slot_After {
		text, found, slot_failure := command_context_modal_named_slot_text(commands, operation)
		if slot_failure.stage != .None do return {}, false, slot_failure
		if !found {
			command_context_set_diagnostic(commands, "The named text slot is unavailable")
			return {}, false, {}
		}
		defer delete(text, commands.temporary_allocator)
		if len(text) > len(plan.text) {
			command_context_set_diagnostic(commands, "The named text slot exceeds the repeat limit")
			return {}, false, {}
		}
		copy(plan.text[:], text)
		plan.text_length = u16(len(text))
		plan.route = .Insert_Text
		if operation.target == .Named_Slot_After do plan.route = .Insert_Text_After_Point
		return plan, true, {}
	}
	explicit, ranged, range_failure := command_context_modal_operator_range(
		buffer, view_registry, view, operation,
		display.terminal_unicode17_profile(), constraints,
	)
	if range_failure.stage != .None do return {}, false, range_failure
	if !ranged {
		command_context_set_diagnostic(commands, "The last modal change has no target here")
		return {}, false, {}
	}
	plan.explicit = explicit
	switch operation.operator {
	case .Delete:
		plan.route = .Kill_Region
	case .Change:
		plan.route = .Kill_Region
		if plan.text_length > 0 do plan.route = .Replace_Region_Text
	case .Replace:
		plan.route = .Replace_Region_Text
		copy(plan.text[:], record.target_text[:record.target_text_length])
		plan.text_length = u16(record.target_text_length)
	case .Indent:
		plan.route = .Indent_Lines
	case .Outdent:
		plan.route = .Outdent_Lines
	case .Yank, .None:
		command_context_set_diagnostic(commands, "The last modal operation did not change text")
		return {}, false, {}
	}
	return plan, true, {}
}
