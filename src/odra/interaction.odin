// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../bridge"
import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../hosting"
import "../gutter"
import "../history"
import "../indentation"
import "../interaction"
import "../kill_ring"
import "../language"
import "../language_interaction"
import "../layout"
import "../package_catalog_interaction"
import "../project"
import "../search"
import "../status_bar"
import "../theme"
import edit_transaction "../transaction"
import "../ui"
import editor_view "../view"
import "base:runtime"
import "core:fmt"
import "core:time"

@(private)
Command_Context :: struct {
	session_owner:       ^editor_session.Session,
	session_handle:      editor_session.Session_Handle,
	entry_configuration: editor_session.Entry_Configuration,
	document_owner:      ^document.Document,
	history_store:       ^history.Store,
	location_history:    ^command.Location_History,
	kill_ring:           ^kill_ring.Ring,
	racket_runtime:      ^hosting.Runtime,
	capabilities:        ^bridge.Buffer_Capability_Registry,
	transaction_capabilities: ^bridge.Transaction_Capability_Registry,
	registry:            ^interaction.Command_Registry,
	registry_generation: interaction.Registry_Generation,
	keymap:              ^interaction.Resolution_Snapshot,
	profile_activation:  ^interaction.Profile_Activation,
	interaction_generation: ^interaction.Generation_Activation,
	active_interaction_context: interaction.Active_Context,
	context_maps:        ^interaction.Context_Map_Stack,
	context_pending:     interaction.Context_Pending_State,
	interaction_workflow:  Interaction_Workflow_State,
	language_keymap_workflow: Language_Keymap_Workflow_State,
	candidate_ui:        Candidate_UI_Workflow_State,
	status_bar_interaction: Status_Bar_Interaction_State,
	gutter_inspection:     ^Gutter_Inspection_State,
	filesystem_path_navigation: Filesystem_Path_Navigation_State,
	keymap_inspection_workflow: Keymap_Inspection_Workflow_State,
	language_state_workflow: Language_State_Workflow_State,
	language_service_inspection_workflow: Language_Service_Inspection_Workflow_State,
	language_interaction_workflow: language_interaction.Workflow,
	package_catalog_interaction_workflow: ^package_catalog_interaction.Workflow,
	package_catalog_runtime_workflow: ^Package_Catalog_Runtime_Workflow_State,
	structural_state_workflow: Structural_State_Workflow_State,
	structural_command_state: ^command.Structural_Capability_State,
	structural_capability_generation: u64,
	theme_inspection_workflow: Theme_Inspection_Workflow_State,
	pending:             interaction.Pending_State,
	prompt_workflow:     Prompt_Workflow_State,
	search:              Search_Workflow_State,
	document_workflow:   Document_Workflow_State,
	project_workflow:    Project_Workflow_State,
	workspace_workflow:  Workspace_Workflow_State,
	named_location_workflow: Named_Location_Workflow_State,
	named_slot_workflow: Named_Slot_Workflow_State,
	result_workflow:     Result_Workflow_State,
	personal_candidate_workflow: Personal_Candidate_Workflow_State,
	symbol_workflow:     Symbol_Workflow_State,
	project_search_workflow: Project_Search_Workflow_State,
	home_directory:      string,
	projects_directory:  string,
	lifecycle_configuration_root: string,
	candidate_history_state_root: string,
	project_catalog_root: string,
	personal_configuration: Personal_Configuration_Startup_State,
	status_bar_policy:  status_bar.Factory_Policy,
	gutter_policy:      gutter.Factory_Policy,
	completion_configuration: Completion_Configuration_State,
	indentation_registry: ^indentation.Registry,
	terminal_configuration: ^Terminal_Configuration_State,
	gutter_separator:   [gutter.MAX_REPRESENTATION_BYTES]u8,
	gutter_separator_fallback: [gutter.MAX_REPRESENTATION_BYTES]u8,
	gutter_registry: gutter.Programmable_Registry,
	status_bar_registry: status_bar.Registry,
	inventory_workflow:  Inventory_Workflow_State,
	current_entry:       editor_session.Entry_Handle,
	overlay_label:       [128]byte,
	overlay_text:        [document.MAX_DIAGNOSTIC_BYTES]byte,
	feedback_content:    [document.MAX_DIAGNOSTIC_BYTES]byte,
	diagnostic:          [document.MAX_DIAGNOSTIC_BYTES]byte,
	diagnostic_length:   int,
	feedback_state:      ^Feedback_Workflow_State,
	persistent_allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
	next_transaction_id: u64,
	next_undo_unit_id:   u64,
	grouping_started:    time.Tick,
	grouping_continuity: u64,
	clipboard_workflow:  Clipboard_Workflow_State,
	startup_workflow:    Startup_Workflow_State,
	layout_registry:     layout.Registry,
	layout_entry:        editor_session.Entry_Handle,
	ui_registry:         ui.Registry,
	ui_root:             ui.Root_Handle,
	popup_workflow:      Popup_Workflow_State,
	popup_fallback:      Popup_Fallback_State,
	presentation_profiles: ui.Presentation_Profile_Registry,
	theme_registry:      theme.Registry,
	theme_transition:    Theme_Transition,
	renderer_profile:    ui.Renderer_Profile,
	syntax_workflow:     ^Syntax_Workflow_State,
	language_service_workflow: ^Language_Service_Workflow_State,
	completion_workflow: ^Completion_Workflow_State,
	terminal_workflow: ^Terminal_Workflow_State,
	recovery_workflow: ^Recovery_Workflow_State,
	terminal_global_shell: string,
	terminal_workspace_shell: string,
	product_module_workflow: Product_Module_Workflow_State,
	pointer_text_capture: Pointer_Text_Capture,
	modal_repeat:        ^interaction.Modal_Repeat_State,
	keyboard_macro:      ^interaction.Keyboard_Macro_State,
	prefix_argument:     interaction.Prefix_Argument_State,
	rigid_indentation:   ^Rigid_Indentation_State,
}

@(private)
Interaction_Result :: struct {
	changed: bool,
	exit:    bool,
	active_entry_closed: bool,
	save:    document.Save_Result,
	deferred_command: interaction.Command_Handle,
}

@(private)
dispatch_input :: #force_no_inline proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
	direct_command: interaction.Command_Handle = {},
	direct_text: string = "",
	direct_prefix: interaction.Prefix_Argument = {},
) -> (Interaction_Result, App_Failure) {
	command_context_sync_indentation_policy(
		commands,
		buffer,
		view_registry,
		view,
	)
	if language_keymap_failure := command_context_sync_language_keymap(commands, buffer);
	   language_keymap_failure.stage != .None {
		return {}, language_keymap_failure
	}
	if commands.prompt_workflow.mode != .None {
		if interaction.prefix_argument_is_cancel_input(input) {
			interaction.prefix_argument_clear(&commands.prefix_argument)
		}
		return dispatch_prompt(commands, buffer, view_registry, view, input, constraints)
	}
	commands.diagnostic_length = 0
	resolution: interaction.Resolution
	modal_navigation := interaction.Modal_Navigation_Result {
		disposition = .Pass_Through,
		count = 1,
	}
	modal_navigation_active := false
	modal_navigation_request: interaction.Modal_Navigation_Request
	modal_operator := interaction.Modal_Operator_Result {
		disposition = .Pass_Through,
	}
	modal_visual_cancel := false
	modal_operator_active := false
	modal_operator_range: command.Native_Explicit_Range
	modal_named_slot_text: []u8
	modal_command_entry_active := false
	modal_repeat_plan: Modal_Repeat_Plan
	modal_repeat_active := false
	prefix_argument: interaction.Prefix_Argument
	direct_profile_active := command_context_direct_profile_active(commands)
	if !direct_profile_active {
		interaction.prefix_argument_clear(&commands.prefix_argument)
	}
	if direct_command.registry_generation != interaction.Registry_Generation(0) {
		claimed, claim_ok := command_context_modal_command_entry_claim(commands, buffer, view)
		if !claim_ok {
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		modal_command_entry_active = claimed
		deferred_failure: App_Failure
		modal_operator, modal_operator_range, modal_operator_active, deferred_failure =
			command_context_modal_operator_deferred(commands, buffer)
		if deferred_failure.stage != .None do return {}, deferred_failure
		resolution = interaction.Resolution {
			kind = .Command,
			command = direct_command,
			text = direct_text,
		}
	} else if completion_workflow_has_interaction(commands.completion_workflow) {
		if map_failure := command_context_sync_completion_map(commands); map_failure.stage != .None {
			return {}, map_failure
		}
		_, contextual_resolution, resolved, resolve_failure := command_context_resolve_context_input(
			commands,
			input,
		)
		if !resolved do return {}, resolve_failure
		resolution = contextual_resolution
	} else if rigid_indentation_active(commands) {
		if map_failure := command_context_sync_rigid_indentation_map(commands); map_failure.stage != .None {
			return {}, map_failure
		}
		_, contextual_resolution, resolved, resolve_failure := command_context_resolve_context_input(
			commands,
			input,
		)
		if !resolved do return {}, resolve_failure
		resolution = contextual_resolution
	} else if darek_workflow_is_focused(commands) {
		if commands.product_module_workflow.workspace_hierarchy_prompt_active {
			return product_module_workflow_dispatch_role_input(
				commands, .Workspace_Hierarchy, input,
			)
		}
		if map_failure := command_context_sync_darek_map(commands); map_failure.stage != .None {
			return {}, map_failure
		}
		_, contextual_resolution, resolved, resolve_failure := command_context_resolve_context_input(
			commands,
			input,
		)
		if !resolved do return {}, resolve_failure
		resolution = contextual_resolution
	} else if _, terminal_active := command_context_active_terminal_state(commands); terminal_active {
		if map_failure := command_context_sync_terminal_map(commands); map_failure.stage != .None {
			return {}, map_failure
		}
		terminal_resolution, handled, terminal_result, terminal_failure :=
			command_context_route_terminal_input(commands, input)
		if terminal_failure.stage != .None do return {}, terminal_failure
		if handled do return terminal_result, {}
		resolution = terminal_resolution
	} else {
		command_context_deactivate_terminal_map(commands)
		if direct_profile_active {
			prefix_result := interaction.prefix_argument_compose(&commands.prefix_argument, input)
			switch prefix_result.disposition {
			case .Pending:
				command_context_set_diagnostic(
					commands,
					fmt.tprintf("Prefix argument: %d", prefix_result.argument.value),
				)
				return Interaction_Result{changed = true}, {}
			case .Cancelled:
				command_context_set_diagnostic(commands, "Prefix argument cancelled")
				return Interaction_Result{changed = true}, {}
			case .Rejected:
				command_context_set_diagnostic(commands, "Prefix argument is too large")
				return Interaction_Result{changed = true}, {}
			case .Ready, .Pass_Through:
			}
		}
		modal_navigation_request, modal_navigation_active =
			command_context_modal_navigation_request(commands, buffer, view, input)
		if modal_navigation_active {
			composed: bool
			modal_operator, composed, _ = interaction.modal_operator_compose(
				commands.profile_activation,
				command_context_modal_operator_request(modal_navigation_request),
			)
			if !composed {
				command_context_set_diagnostic(commands, "Modal operator input rejected")
				return Interaction_Result{changed = true}, {}
			}
			if modal_operator.disposition == .Pending {
				return Interaction_Result{changed = true}, {}
			}
			if modal_operator.disposition == .Cancelled {
				modal_visual_cancel = interaction.profile_activation_modal_visual_kind(
					commands.profile_activation,
				) != .None
				if !modal_visual_cancel do return Interaction_Result{changed = true}, {}
			}
			if modal_visual_cancel {
				resolution_failure: interaction.Failure_Context
				resolution, resolution_failure = interaction.resolve_contextual_input(
					commands.context_maps,
					commands.keymap,
					commands.registry_generation,
					&commands.context_pending,
					&commands.pending,
					input,
				)
				if resolution.kind != .Pending {
					_ = interaction.profile_activation_modal_pending_cancel(commands.profile_activation)
				}
				if resolution_failure.code == .Context_Input_Rejected do return {}, {}
				if resolution_failure.code != .None {
					return {}, App_Failure {
						stage = .Command_Resolution,
						interaction = resolution_failure,
					}
				}
			} else if modal_operator.disposition == .Ready {
				if modal_operator.target == .Named_Slot_Before ||
				   modal_operator.target == .Named_Slot_After {
					slot_failure: App_Failure
					modal_named_slot_text, composed, slot_failure =
						command_context_modal_named_slot_text(commands, modal_operator)
					if slot_failure.stage != .None do return {}, slot_failure
					if !composed {
						command_context_set_diagnostic(commands, "Named text slot not found")
						return Interaction_Result{changed = true}, {}
					}
					command_name := "insert-text"
					if modal_operator.target == .Named_Slot_After {
						command_name = "insert-text-after-point"
					}
					handle, found, lookup_failure := interaction.command_lookup(commands.registry, command_name)
					if !found {
						return {}, App_Failure{stage = .Command_Resolution, interaction = lookup_failure}
					}
					resolution = {
						kind = .Command,
						command = handle,
						text = string(modal_named_slot_text),
					}
					modal_operator_active = true
				} else if modal_operator.target == .Search_Forward ||
				   modal_operator.target == .Search_Backward {
					return command_context_modal_operator_begin_search(commands, modal_operator)
				} else if modal_operator.target == .Search_Next ||
				   modal_operator.target == .Search_Previous {
					if commands.profile_activation == nil ||
					   !interaction.profile_activation_modal_operator_execution_begin(
						commands.profile_activation,
						modal_operator,
					) {
						return {}, App_Failure{stage = .Command_Dispatch}
					}
					_, search_failure := command_context_repeat_confirmed_search(
						commands,
						buffer,
						view_registry,
						view,
						modal_operator.target == .Search_Next,
						modal_operator.count,
						constraints,
					)
					if search_failure.stage != .None {
						interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
						return {}, search_failure
					}
					return command_context_modal_operator_defer_search(
						commands, buffer, view_registry, view,
					)
				} else {
					block_operator := modal_operator.target == .Active_Selection &&
						interaction.profile_activation_modal_visual_kind(
							commands.profile_activation,
						) == .Block
					if block_operator {
						composed = true
					} else {
						operator_failure: App_Failure
						modal_operator_range, composed, operator_failure =
						command_context_modal_operator_range(
							buffer,
							view_registry,
							view,
							modal_operator,
							display.terminal_unicode17_profile(),
							constraints,
						)
						if operator_failure.stage != .None do return {}, operator_failure
					}
					if !composed {
						command_context_set_diagnostic(commands, "Modal operator target unavailable")
						return Interaction_Result{changed = true}, {}
					}
					command_name, named := command_context_modal_operator_command(modal_operator.operator)
					if block_operator {
						switch modal_operator.operator {
						case .Delete, .Change: command_name, named = "kill-rectangle", true
						case .Yank:            command_name, named = "copy-rectangle", true
						case .Replace:         command_name, named = "replace-rectangle-text", true
						case .Indent, .Outdent, .None: command_name, named = "", false
						}
					}
					if !named {
						command_context_set_diagnostic(commands, "Modal operator is unavailable")
						return Interaction_Result{changed = true}, {}
					}
					handle, found, lookup_failure := interaction.command_lookup(commands.registry, command_name)
					if !found {
						return {}, App_Failure{stage = .Command_Resolution, interaction = lookup_failure}
					}
					if len(interaction.modal_operator_result_named_slot(&modal_operator)) > 0 {
						store_result, execute, handled, store_failure :=
							command_context_modal_named_slot_store(
								commands,
								buffer,
								modal_operator,
								modal_operator_range,
								handle,
							)
						if store_failure.stage != .None do return {}, store_failure
						if handled do return store_result, {}
						if !execute {
							command_context_set_diagnostic(commands, "Named text slot operation rejected")
							return Interaction_Result{changed = true}, {}
						}
					}
					resolution = interaction.Resolution {
						kind = .Command,
						command = handle,
						text = interaction.modal_operator_result_text(&modal_operator) if
						       modal_operator.operator == .Replace else "",
					}
					modal_operator_active = true
				}
			} else {
				modal_navigation, composed, _ = interaction.modal_navigation_compose(
				commands.profile_activation,
				modal_navigation_request,
				)
				if !composed {
					command_context_set_diagnostic(commands, "Modal navigation input rejected")
					return Interaction_Result{changed = true}, {}
				}
				if modal_navigation.disposition == .Pending ||
				   modal_navigation.disposition == .Cancelled {
					return Interaction_Result{changed = true}, {}
				}
				if modal_navigation.disposition == .Character_Target ||
				   modal_navigation.disposition == .Repeat_Character_Target {
					command_name, named := command_context_modal_character_command(
						modal_navigation.character_target,
					)
					if !named {
						command_context_set_diagnostic(commands, "Modal character target rejected")
						return Interaction_Result{changed = true}, {}
					}
					handle, found, lookup_failure := interaction.command_lookup(commands.registry, command_name)
					if !found {
						return {}, App_Failure{stage = .Command_Resolution, interaction = lookup_failure}
					}
					resolution = interaction.Resolution {
						kind = .Command,
						command = handle,
						text = interaction.modal_navigation_result_text(&modal_navigation),
					}
				} else {
					resolution_failure: interaction.Failure_Context
					resolution, resolution_failure = interaction.resolve_contextual_input(
						commands.context_maps,
						commands.keymap,
						commands.registry_generation,
						&commands.context_pending,
						&commands.pending,
						input,
					)
					if resolution.kind != .Pending {
						_ = interaction.profile_activation_modal_pending_cancel(commands.profile_activation)
					}
					if resolution_failure.code == .Context_Input_Rejected {
						return {}, {}
					}
					if resolution_failure.code != .None {
						return {}, App_Failure {
							stage = .Command_Resolution,
							interaction = resolution_failure,
						}
					}
				}
			}
		} else {
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
				return {}, {}
			}
			if resolution_failure.code != .None {
				return {}, App_Failure {
					stage = .Command_Resolution,
					interaction = resolution_failure,
				}
			}
		}
	}
	switch resolution.kind {
	case .Pending:
		return {}, {}
	case .Unbound:
		interaction.prefix_argument_clear(&commands.prefix_argument)
		return {}, {}
	case .Rejected, .Invalid:
		interaction.prefix_argument_clear(&commands.prefix_argument)
		return {}, App_Failure{stage = .Command_Resolution}
	case .Command:
		defer if len(modal_named_slot_text) > 0 do delete(modal_named_slot_text, commands.temporary_allocator)
		metadata, metadata_ok, metadata_failure := interaction.command_metadata(
			commands.registry,
			resolution.command,
		)
		if !metadata_ok {
			interaction.prefix_argument_clear(&commands.prefix_argument)
			return {}, App_Failure {
				stage = .Command_Dispatch,
				interaction = metadata_failure,
			}
		}
		retain_prefix := direct_command.registry_generation == interaction.Registry_Generation(0) &&
		                 command_metadata_is_native(metadata, .Execute_Extended_Command)
		if direct_prefix.present {
			interaction.prefix_argument_clear(&commands.prefix_argument)
			prefix_argument = direct_prefix
		} else if direct_profile_active && !retain_prefix {
			prefix_argument = interaction.prefix_argument_take(&commands.prefix_argument)
		}
		if commands.profile_activation != nil {
			admitted, admission_failure := interaction.profile_activation_command_admit(
				commands.profile_activation,
				commands.registry,
				resolution.command,
			)
			if !admitted {
				return {}, App_Failure {
					stage = .Command_Dispatch,
					interaction = admission_failure,
				}
			}
		}
		if command_metadata_is_cancel(metadata) &&
		   completion_workflow_has_interaction(commands.completion_workflow) {
			completion_workflow_cancel_current(commands, true)
			return Interaction_Result{changed = true}, {}
		}
		if command_metadata_is_cancel(metadata) && rigid_indentation_active(commands) {
			command_context_finish_rigid_indentation(commands, .Cancelled)
			return Interaction_Result{changed = true}, {}
		}
		if command_metadata_is_cancel(metadata) &&
		   command_context_language_interaction_cancel(commands) {
			return Interaction_Result{changed = true}, {}
		}
		if command_metadata_is_cancel(metadata) &&
		   command_context_package_catalog_interaction_cancel(commands) {
			return Interaction_Result{changed = true}, {}
		}
		if command_metadata_is_cancel(metadata) {
			macro_state := command_context_keyboard_macro_state(commands, false)
			if interaction.keyboard_macro_cancel(macro_state) {
				command_context_set_diagnostic(commands, "Keyboard macro definition cancelled")
				return Interaction_Result{changed = true}, {}
			}
		}
		if command_metadata_is_cancel(metadata) {
			_, popup_dismissed := popup_workflow_dismiss(
				&commands.popup_workflow,
				.Explicit_Cancel,
				commands.ui_root,
			)
			if popup_dismissed {
				gutter_inspection_popup_dismiss(commands.gutter_inspection)
				popup_fallback_clear(&commands.popup_fallback)
				return Interaction_Result{changed = true}, {}
			}
		}
		native_route, native_route_ok := command.native_route_decode(metadata.route)
		if rigid_indentation_active(commands) &&
		   (!native_route_ok ||
		    native_route != .Rigid_Indent_Right && native_route != .Rigid_Indent_Left &&
		    native_route != .Rigid_Indent_Right_Fast && native_route != .Rigid_Indent_Left_Fast) {
			command_context_finish_rigid_indentation(commands, .Completed)
		}
		deferred_insert_file := native_route_ok && native_route == .Insert_File &&
		                        len(commands.document_workflow.deferred_text) > 0 &&
		                        commands.document_workflow.deferred_command == resolution.command
		if deferred_insert_file {
			resolution.text = string(commands.document_workflow.deferred_text)
		}
		deferred_navigation_target := native_route_ok &&
		                              (native_route == .Goto_Line || native_route == .Goto_Char) &&
		                              commands.document_workflow.deferred_argument > 0 &&
		                              commands.document_workflow.deferred_command == resolution.command
		if deferred_navigation_target {
			prefix_argument = {
				present = true,
				value = commands.document_workflow.deferred_argument,
				repeat_count = 1,
			}
		}
		command_context_keyboard_macro_record(commands, metadata, resolution.text, prefix_argument)
		if modal_navigation_active && modal_navigation.count_explicit &&
		   (!native_route_ok || !command_context_is_modal_count_route(native_route)) {
			command_context_set_diagnostic(commands, "Modal count is unavailable for this command")
			return Interaction_Result{changed = true}, {}
		}
		if native_route_ok &&
		   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None &&
		   command_context_modal_visual_movement_route(native_route) {
			return command_context_modal_visual_move(
				commands,
				buffer,
				view_registry,
				view,
				native_route,
				modal_navigation.count if modal_navigation_active else 1,
				resolution.text,
				display.terminal_unicode17_profile(),
				constraints,
			)
		}
		if native_route_ok &&
		   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None &&
		   (native_route == .ISearch_Forward || native_route == .ISearch_Backward ||
		    native_route == .Search_Next_Occurrence ||
		    native_route == .Search_Previous_Occurrence) {
			if visual_search_failure := command_context_modal_visual_prepare_search(
				commands, buffer, view_registry, view,
			); visual_search_failure.stage != .None {
				return {}, visual_search_failure
			}
		}
		if native_route_ok {
			copy_result, copy_handled, copy_failure :=
				command_context_dispatch_terminal_copy_command(
					commands, native_route, resolution.command,
				)
			if copy_handled do return copy_result, copy_failure
		}
		if command_context_layout_is_insufficient(commands) &&
		   !command_context_recovery_route_is_allowed(metadata.route) {
			command_context_set_diagnostic(
				commands,
				"Terminal geometry is insufficient; resize, close the active pane, keep only the active pane, or exit.",
			)
			return Interaction_Result{changed = true}, {}
		}
		if command_context_is_keymap_inspection_command(metadata.route) {
			return command_context_begin_keymap_inspection(
				commands,
				metadata.name,
				resolution.command,
				buffer,
				view_registry,
				view,
				constraints,
			)
		}
		if command_metadata_is_native(metadata, .Save_Associated_Document) && commands.document_owner == nil &&
		   commands.session_owner != nil &&
		   editor_session.entry_handle_is_valid(commands.current_entry) {
			return command_context_begin_save_path(commands, false)
		}
		if command_metadata_is_native(metadata, .Yank) ||
		   command_metadata_is_native(metadata, .Yank_After_Point) {
			clipboard_output := clipboard_workflow_import(
				&commands.clipboard_workflow,
				commands.kill_ring,
				resolution.command,
				commands.temporary_allocator,
			)
			if clipboard_output.diagnostic_length > 0 {
				command_context_set_diagnostic(
					commands,
					string(clipboard_output.diagnostic[:clipboard_output.diagnostic_length]),
				)
			}
			if !clipboard_output.ready {
				clipboard_workflow_cancel_yank(&commands.clipboard_workflow)
				return Interaction_Result{changed = clipboard_output.changed}, {}
			}
		}
		racket_dispatch, _, racket_route_ok := command.racket_route_decode(metadata.route)
		if racket_route_ok && racket_dispatch == .Ksawery_Extension {
			return product_module_workflow_invoke(commands, metadata, constraints)
		}
		result: command.Native_Result
		executed := false
		execute_failure: command.Failure_Context
		if commands.next_transaction_id == 0 || commands.next_undo_unit_id == 0 {
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		if native_route == .Modal_Repeat_Last_Change {
			repeat_failure: App_Failure
			modal_repeat_plan, modal_repeat_active, repeat_failure =
				command_context_modal_repeat_prepare(
					commands,
					buffer,
					view_registry,
					view,
					constraints,
					modal_navigation.count if modal_navigation_active else 1,
					modal_navigation.count_explicit if modal_navigation_active else false,
				)
			if repeat_failure.stage != .None do return {}, repeat_failure
			if !modal_repeat_active do return Interaction_Result{changed = true}, {}
		}
		transaction_id := commands.next_transaction_id
		undo_unit_id := commands.next_undo_unit_id
		if command_context_is_layout_route(native_route) {
			layout_failure := command_context_layout_ensure(
				commands,
				view_registry,
				view,
				constraints,
			)
			if layout_failure.stage != .None {
				command_context_layout_failure_diagnostic(
					commands,
					"Pane command rejected",
					layout_failure.layout,
				)
				return Interaction_Result{changed = true}, {}
			}
		}
		if native_route == .Close_Pane && command_context_layout_has_single_pane(commands) {
			return command_context_begin_last_pane_exit(commands, resolution.command)
		}
		grouping := command_history_grouping(commands, native_route, view, transaction_id)
		syntax_observer_context := Syntax_Commit_Observer_Context {
			workflow = commands.syntax_workflow,
			buffer = buffer,
		}
		commit_observer := syntax_workflow_commit_observer(&syntax_observer_context)
		kill_command := native_route == .Kill_Region || native_route == .Kill_Rectangle ||
		                native_route == .Kill_Line || native_route == .Backward_Kill_Word ||
		                native_route == .Kill_Word
		kill_sequence_id := clipboard_workflow_kill_sequence(&commands.clipboard_workflow, kill_command)
		if transaction_id == max(u64) {
			commands.next_transaction_id = 0
		} else {
			commands.next_transaction_id += 1
		}
		if undo_unit_id == max(u64) {
			commands.next_undo_unit_id = 0
		} else {
			commands.next_undo_unit_id += 1
		}
		switch metadata.implementation {
		case .Native:
			location_history := commands.location_history
			if location_history == nil {
				allocation_error: runtime.Allocator_Error
				location_history, allocation_error = new(
					command.Location_History,
					commands.persistent_allocator,
				)
				if allocation_error != nil {
					return {}, App_Failure{stage = .Command_Dispatch}
				}
				commands.location_history = location_history
			}
			native_context := command.Native_Context {
				registry = commands.registry,
				command = resolution.command,
				buffer = buffer,
				document = commands.document_owner,
				view_registry = view_registry,
				view = view,
				text = string(modal_repeat_plan.text[:modal_repeat_plan.text_length]) if
				       modal_repeat_active else resolution.text,
				profile = display.terminal_unicode17_profile(),
				constraints = constraints,
				temporary_allocator = commands.temporary_allocator,
				persistent_allocator = commands.persistent_allocator,
				transaction_id = edit_transaction.Transaction_ID(transaction_id),
				undo_unit_id = edit_transaction.Undo_Unit_ID(undo_unit_id),
				history_store = commands.history_store,
				location_history = location_history,
				history_grouping = grouping,
				kill_ring = commands.kill_ring,
				kill_sequence_id = kill_sequence_id,
				event_sequence = transaction_id,
				yank_context = &commands.clipboard_workflow.yank_context,
				layout_registry = &commands.layout_registry if command_context_layout_is_live(commands) else nil,
				commit_observer = commit_observer,
				argument_present = prefix_argument.present,
				argument = prefix_argument.value,
				repeat_count = modal_repeat_plan.count if modal_repeat_active else
				               modal_operator.count if modal_operator_active else
				               modal_navigation.count if modal_navigation_active else
				               prefix_argument.repeat_count if prefix_argument.present else 1,
				explicit_range = modal_repeat_plan.explicit if modal_repeat_active else
				                 modal_operator_range if modal_operator_active else {},
				replace_text_input = native_route == .Insert_Text &&
				                     command_context_modal_replace_active(commands),
				replay_route = modal_repeat_plan.route if modal_repeat_active else .Invalid,
				replay_entry_route = modal_repeat_plan.entry_route if modal_repeat_active else .Invalid,
				replay_replace_text = modal_repeat_plan.replace_text if modal_repeat_active else false,
			}
			if native_route == .Rigid_Indent_Right || native_route == .Rigid_Indent_Left ||
			   native_route == .Rigid_Indent_Right_Fast || native_route == .Rigid_Indent_Left_Fast {
				rigid_range, rigid_range_ok := command_context_rigid_indentation_range(commands, buffer)
				if !rigid_range_ok {
					command_context_finish_rigid_indentation(commands, .Invalidated)
					command_context_set_diagnostic(commands, "Rigid indentation target is no longer available")
					return Interaction_Result{changed = true}, {}
				}
				native_context.explicit_range = rigid_range
			}
			if command_context_is_structural_route(native_route) {
				owner, source, scope, available, structural_failure :=
					syntax_workflow_structural_context(commands.syntax_workflow, buffer)
				if !available {
					contained_failure := command.Failure_Context {
						code = .Capability_Failure,
						structural_code = .Analysis_Rejected,
						language_code = structural_failure.code,
						revision = structural_failure.source_revision,
						limit = structural_failure.limit,
						actual = structural_failure.actual,
					}
					command.structural_capability_record_failure(
						commands.structural_command_state,
						command_context_structural_operation(native_route),
						contained_failure,
					)
					command_context_structural_language_diagnostic(commands, structural_failure)
					return Interaction_Result{changed = true}, {}
				}
				native_context.language_owner = owner
				native_context.language_source = source
				native_context.structural_scope = scope
				native_context.editor_session_id = command.Editor_Session_ID(
					commands.session_handle.session_id,
				)
				native_context.structural_access = {
					.Inspect, .Forward, .Backward, .Up, .Down, .Select, .Indent, .Definition,
				}
				native_context.structural_capability_generation =
					commands.structural_capability_generation
				native_context.structural_state = commands.structural_command_state
			}
			result, executed, execute_failure = command.native_command_execute(
				native_context,
			)
			if deferred_insert_file {
				document_workflow_clear_deferred_text(&commands.document_workflow)
			}
			if deferred_navigation_target {
				document_workflow_clear_deferred_argument(&commands.document_workflow)
			}
		case .Racket:
			result, executed, execute_failure = command.racket_command_execute(
				command.Racket_Context {
					runtime = commands.racket_runtime,
					capabilities = commands.capabilities,
					transaction_capabilities = commands.transaction_capabilities,
					command_registry = commands.registry,
					command = resolution.command,
					buffer = buffer,
					document = commands.document_owner,
					session_owner = commands.session_owner,
					session_handle = commands.session_handle,
					view_registry = view_registry,
					view = view,
					profile = display.terminal_unicode17_profile(),
					constraints = constraints,
					temporary_allocator = commands.temporary_allocator,
					persistent_allocator = commands.persistent_allocator,
					transaction_id = edit_transaction.Transaction_ID(transaction_id),
					undo_unit_id = edit_transaction.Undo_Unit_ID(undo_unit_id),
					history_store = commands.history_store,
					commit_observer = commit_observer,
					argument_present = prefix_argument.present,
					argument = prefix_argument.value,
					repeat_count = prefix_argument.repeat_count if prefix_argument.present else 1,
				},
			)
		case .Invalid:
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		return command_context_dispatch_execution_result(
			commands,
			buffer,
			view_registry,
			view,
			input,
			constraints,
			resolution,
			metadata,
			native_route,
			result,
			executed,
			execute_failure,
			racket_dispatch,
			kill_command,
			modal_operator,
			modal_operator_active,
			modal_navigation,
			modal_navigation_active,
			modal_navigation_request,
			modal_command_entry_active,
			prefix_argument,
			transaction_id,
			undo_unit_id,
			grouping,
			commit_observer,
		)
	}
	unreachable()
}

@(private)
command_context_dispatch_execution_result :: #force_no_inline proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
	resolution: interaction.Resolution,
	metadata: interaction.Command_Metadata,
	native_route: command.Native_Route,
	execution_result: command.Native_Result,
	executed: bool,
	execute_failure: command.Failure_Context,
	racket_dispatch: command.Racket_Dispatch_Class,
	kill_command: bool,
	modal_operator: interaction.Modal_Operator_Result,
	modal_operator_active: bool,
	navigation_result: interaction.Modal_Navigation_Result,
	modal_navigation_active: bool,
	modal_navigation_request: interaction.Modal_Navigation_Request,
	modal_command_entry_active: bool,
	prefix_argument: interaction.Prefix_Argument,
	transaction_id: u64,
	undo_unit_id: u64,
	grouping: history.Grouping_Context,
	commit_observer: edit_transaction.Commit_Observer,
) -> (Interaction_Result, App_Failure) {
	result := execution_result
	modal_navigation := navigation_result
	defer command.native_result_close(&result)
	clipboard_workflow_finish_command(&commands.clipboard_workflow, executed, kill_command)
	if !executed {
		if modal_operator_active do interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		if command_context_contain_personal_command_failure(
			commands,
			racket_dispatch,
			execute_failure,
		) {
			return Interaction_Result{changed = true}, {}
		}
		if command_context_is_structural_route(native_route) {
			command.structural_capability_record_failure(
				commands.structural_command_state,
				command_context_structural_operation(native_route),
				execute_failure,
			)
			command_context_structural_command_diagnostic(commands, execute_failure)
			return Interaction_Result{changed = true}, {}
		}
		if execute_failure.code == .Layout_Failure {
			command_context_layout_failure_diagnostic(
				commands,
				"Pane command rejected",
				execute_failure.layout_failure,
			)
			return Interaction_Result{changed = true}, {}
		}
		if execute_failure.code == .Region_Unavailable && modal_operator_active {
			command_context_set_diagnostic(commands, "Modal operator target unavailable")
			return Interaction_Result{changed = true}, {}
		}
		if execute_failure.code == .Region_Unavailable {
			command_context_set_diagnostic(commands, "No active selection")
			return Interaction_Result{changed = true}, {}
		}
		return {}, App_Failure{stage = .Command_Dispatch, command = execute_failure}
	}
	command_context_modal_repeat_capture(
		commands,
		native_route,
		resolution.command,
		modal_operator,
		modal_operator_active,
		modal_navigation.count if modal_navigation_active else 1,
		modal_navigation.count_explicit if modal_navigation_active else false,
		result.completion,
	)
	if native_route == .Insert_Text && result.completion == .Buffer_Committed &&
	   !modal_operator_active {
		command_context_modal_repeat_append_text(
			commands,
			resolution.command,
			resolution.text,
			command_context_modal_replace_active(commands),
		)
	} else if native_route == .Insert_Line_Break &&
	          result.completion == .Buffer_Committed &&
	          commands.modal_repeat != nil && commands.modal_repeat.pending_active {
		command_context_modal_repeat_append_text(
			commands, resolution.command, "\n", false,
		)
	} else if native_route == .Insert_Indentation &&
	          result.completion == .Buffer_Committed &&
	          commands.modal_repeat != nil && commands.modal_repeat.pending_active {
		command_context_modal_repeat_append_indentation(
			commands, resolution.command, view_registry, view,
		)
	}
	if metadata.implementation == .Racket {
		message := hosting.runtime_diagnostic(commands.racket_runtime)
		if len(message) > 0 do command_context_set_diagnostic(commands, message)
		if len(result.personal_result) > 0 {
			return command_context_present_personal_candidates(
				commands,
				result.personal_result,
				resolution.command,
				constraints,
			)
		}
	}
	if modal_navigation_active &&
	   modal_navigation.disposition == .Character_Target {
		confirmed, confirm_failure := interaction.profile_activation_modal_character_search_confirm(
			commands.profile_activation,
			modal_navigation_request,
			modal_navigation.character_target,
			interaction.modal_navigation_result_text(&modal_navigation),
		)
		if !confirmed {
			return {}, App_Failure {
				stage = .Command_Dispatch,
				interaction = confirm_failure,
			}
		}
	}
	if native_route == .Modal_Enter_Visual_Character {
		return command_context_modal_visual_transition(
			commands, buffer, view_registry, view, .Character,
		)
	}
	if native_route == .Modal_Enter_Visual_Line {
		return command_context_modal_visual_transition(
			commands, buffer, view_registry, view, .Line,
		)
	}
	if native_route == .Modal_Enter_Visual_Block {
		return command_context_modal_visual_transition(
			commands, buffer, view_registry, view, .Block,
		)
	}
	if native_route == .Modal_Enter_Normal &&
	   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
		return command_context_modal_visual_transition(
			commands, buffer, view_registry, view, .None,
		)
	}
	if native_route == .Exchange_Point_And_Mark &&
	   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
		if !interaction.profile_activation_modal_visual_exchange(commands.profile_activation) {
			return {}, App_Failure{stage = .Command_Dispatch}
		}
		return interaction_result(result)
	}
	if (native_route == .Select_Word || native_route == .Select_Paragraph) &&
	   interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
		return command_context_modal_visual_adopt_region(
			commands, buffer, view_registry, view,
		)
	}
	if native_route == .Modal_Enter_Insert ||
	   native_route == .Modal_Enter_Insert_After ||
	   native_route == .Modal_Enter_Replace ||
	   native_route == .Modal_Enter_Insert_Line_First ||
	   native_route == .Modal_Enter_Insert_Line_End ||
	   native_route == .Modal_Open_Line_Below ||
	   native_route == .Modal_Open_Line_Above ||
	   native_route == .Modal_Enter_Normal {
		target := "Insert"
		if native_route == .Modal_Enter_Normal {
			target = "Normal"
		} else if native_route == .Modal_Enter_Replace {
			target = "Replace"
		}
		return command_context_transition_modal_state(commands, target)
	}
	if command_context_is_layout_route(native_route) {
		if layout_sync_failure := command_context_layout_sync_active_entry(
			commands,
		); layout_sync_failure.stage != .None {
			return {}, layout_sync_failure
		}
	}
	if result.completion == .Exit_Requested {
		return command_context_request_exit(commands, resolution.command, buffer)
	}
	if result.completion == .Document_Target_Required {
		return command_context_begin_save_path(commands, false)
	}
	if result.completion == .Document_Saved {
		command_context_set_channel_diagnostic(commands, .Save, "Saved")
		return Interaction_Result{changed = true, save = result.save}, {}
	}
	if result.completion == .Completion_Command_Requested {
		return command_context_dispatch_completion_route(
			commands,
			buffer,
			view_registry,
			view,
			native_route,
			edit_transaction.Transaction_ID(transaction_id),
			edit_transaction.Undo_Unit_ID(undo_unit_id),
		)
	}
	if result.completion == .Terminal_Command_Requested {
		return command_context_dispatch_terminal_route(
			commands,
			native_route,
			resolution.command,
			constraints,
		)
	}
	if result.completion == .Ksawery_Status_Requested {
		return product_module_workflow_activate_source_control(commands)
	}
	if result.completion == .Find_File_Requested {
		return command_context_begin_buffer_prompt(commands, .Find_File, resolution.command)
	}
	if result.completion == .Find_Alternate_File_Requested {
		return command_context_begin_alternate_file(commands, resolution.command)
	}
	if result.completion == .Write_File_Requested {
		return command_context_begin_save_path(commands, false, true)
	}
	if result.completion == .Save_Some_Buffers_Requested {
		return command_context_present_save_some_buffers(
			commands,
			constraints,
			resolution.command,
			prefix_argument.present,
		)
	}
	if result.completion == .Insert_File_Requested {
		return command_context_begin_insert_file_path(commands, resolution.command)
	}
	if result.completion == .Next_Buffer_Requested {
		return command_context_traverse_buffer(commands, true)
	}
	if result.completion == .Previous_Buffer_Requested {
		return command_context_traverse_buffer(commands, false)
	}
	if result.completion == .Numeric_Navigation_Target_Requested {
		return command_context_begin_navigation_target(commands, resolution.command)
	}
	if result.completion == .Switch_To_Buffer_Requested {
		return command_context_present_buffer_navigation(
			commands,
			constraints,
			resolution.command,
		)
	}
	if result.completion == .Find_File_Other_Pane_Requested {
		return command_context_begin_buffer_prompt(commands, .Find_File_Other_Pane, resolution.command)
	}
	if result.completion == .Maksym_Command_Requested {
		return command_context_dispatch_maksym_route(
			commands,
			native_route,
			constraints,
			resolution.command,
		)
	}
	if result.completion == .Darek_Command_Requested {
		return command_context_dispatch_darek_route(
			commands,
			native_route,
			constraints,
			resolution.command,
		)
	}
	if result.completion == .Switch_To_Buffer_Other_Pane_Requested ||
	   result.completion == .Display_Buffer_Other_Pane_Requested {
		return command_context_present_buffer_navigation(
			commands,
			constraints,
			resolution.command,
		)
	}
	if result.completion == .Kill_Buffer_Requested {
		return command_context_begin_buffer_prompt(commands, .Kill_Buffer, resolution.command)
	}
	if result.completion == .List_Buffers_Requested {
		return command_context_present_buffer_inventory(commands, constraints, resolution.command)
	}
	if result.completion == .Interaction_Profile_Reload_Requested {
		if commands.profile_activation == nil {
			return {}, App_Failure{stage = .Keymap_Activation}
		}
		reloaded, reload_failure := command.racket_profile_reload(
			commands.racket_runtime,
			commands.registry,
			commands.profile_activation,
			commands.active_interaction_context,
			&commands.pending,
			commands.persistent_allocator,
		)
		if !reloaded {
			return {}, App_Failure{stage = .Keymap_Activation, command = reload_failure}
		}
		commands.context_pending = {}
		return Interaction_Result{changed = true}, {}
	}
	if result.completion == .Personal_Commands_Reload_Requested {
		return command_context_reload_personal_commands(commands)
	}
	if result.completion == .Command_Navigation_Requested {
		commands.document_workflow.buffer_command = resolution.command
		if _, terminal_active := command_context_active_terminal_state(commands);
		   !terminal_active {
			if !command_context_modal_command_entry_begin(commands, buffer, view, input) {
				return {}, App_Failure{stage = .Command_Dispatch}
			}
		}
		return command_context_present_command_navigation(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if result.completion == .Command_Description_Requested {
		commands.document_workflow.buffer_command = resolution.command
		return command_context_present_command_navigation(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if result.completion == .Help_Requested {
		topic, topic_ok := command_context_help_topic(native_route)
		if !topic_ok do return {}, App_Failure{stage = .Command_Dispatch}
		return command_context_present_help(commands, topic, constraints)
	}
	if result.completion == .Interaction_Profile_Selection_Requested {
		return command_context_present_interaction_profile_navigation(commands)
	}
	if result.completion == .Modal_Repeat_Inspection_Requested {
		return command_context_modal_repeat_inspect(commands)
	}
	if result.completion == .Keyboard_Macro_Start_Requested {
		return command_context_keyboard_macro_start(commands)
	}
	if result.completion == .Keyboard_Macro_End_Requested {
		return command_context_keyboard_macro_end(commands)
	}
	if result.completion == .Keyboard_Macro_Call_Last_Requested {
		return command_context_keyboard_macro_replay(
			commands, buffer, view_registry, view, constraints, prefix_argument,
		)
	}
	if result.completion == .Keyboard_Macro_Finish_Or_Call_Requested {
		return command_context_keyboard_macro_finish_or_replay(
			commands, buffer, view_registry, view, constraints, prefix_argument,
		)
	}
	if result.completion == .Keyboard_Macro_Name_Last_Requested {
		return command_context_begin_keyboard_macro_prompt(commands, .Keyboard_Macro_Name)
	}
	if result.completion == .Keyboard_Macro_Call_Named_Requested {
		return command_context_begin_keyboard_macro_prompt(commands, .Keyboard_Macro_Call)
	}
	if result.completion == .Theme_Selection_Requested {
		return command_context_present_theme_navigation(commands)
	}
	if result.completion == .Theme_Inspection_Requested {
		return command_context_present_theme_inspection(commands, constraints)
	}
	if result.completion == .Status_Bar_Inspect_Requested {
		return command_context_present_status_bar_segments(commands, constraints, false)
	}
	if result.completion == .Status_Bar_Actions_Requested ||
	   result.completion == .Status_Bar_Activate_Segment_Requested {
		return command_context_present_status_bar_segments(commands, constraints, true)
	}
	if result.completion == .Gutter_Command_Requested {
		return command_context_apply_gutter_command(
			commands,
			buffer,
			view_registry,
			view,
			native_route,
			constraints,
		)
	}
	if result.completion == .Project_Inspect_Active_Requested {
		return command_context_inspect_active_project(commands)
	}
	if result.completion == .Project_Promote_Requested {
		return command_context_begin_project_prompt(
			commands,
			.Project_Promote_Name,
			resolution.command,
		)
	}
	if result.completion == .Project_Unregister_Requested {
		return command_context_present_project_navigation(commands, .Unregister)
	}
	if result.completion == .Workspace_Add_Project_Requested {
		return command_context_present_project_navigation(commands, .Workspace_Add)
	}
	if result.completion == .Workspace_Remove_Project_Requested {
		return command_context_present_project_navigation(commands, .Workspace_Remove)
	}
	if result.completion == .Workspace_Unregister_Requested {
		return command_context_present_workspace_navigation(commands, .Unregister)
	}
	if result.completion == .Save_Location_Requested {
		return command_context_begin_named_location_save(
			commands,
			resolution.command,
			commands.document_owner,
			view_registry,
			view,
		)
	}
	if result.completion == .List_Locations_Requested ||
	   result.completion == .Visit_Location_Requested {
		return command_context_present_named_locations(commands, resolution.command)
	}
	if result.completion == .Store_Number_Requested {
		return command_context_begin_named_slot(commands, .Store_Number, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Increment_Number_Requested {
		return command_context_begin_named_slot(commands, .Increment_Number, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Store_Text_Requested {
		return command_context_begin_named_slot(commands, .Store_Text, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Store_Region_Text_Requested {
		return command_context_begin_named_slot(commands, .Store_Region_Text, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Store_Position_Requested {
		return command_context_begin_named_slot(commands, .Store_Position, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Insert_Slot_Requested {
		return command_context_begin_named_slot(commands, .Insert_Slot, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Store_Layout_Requested {
		return command_context_begin_named_slot(commands, .Store_Layout, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Visit_Slot_Requested {
		return command_context_begin_named_slot(commands, .Visit_Slot, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Restore_Layout_Requested {
		return command_context_begin_named_slot(commands, .Restore_Layout, resolution.command, buffer, commands.document_owner, view_registry, view)
	}
	if result.completion == .Project_Find_File_Requested {
		return command_context_present_project_files(commands, constraints, resolution.command)
	}
	if result.completion == .Project_Switch_Buffer_Requested {
		return command_context_present_project_buffers(commands, constraints, resolution.command)
	}
	if result.completion == .Project_Save_Buffers_Requested {
		return command_context_save_project_buffers(commands, resolution.command)
	}
	if result.completion == .Project_Close_Buffers_Requested {
		return command_context_close_project_buffers(commands, resolution.command, constraints)
	}
	if result.completion == .Project_Refresh_Requested {
		return command_context_refresh_project(commands, resolution.command)
	}
	if result.completion == .Project_Command_Menu_Requested {
		return command_context_present_command_navigation(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
			"project-",
		)
	}
	if result.completion == .Describe_Project_Bindings_Requested {
		return command_context_present_keymap_inspection(
			commands,
			interaction.Inspection_Query {
				kind = .Map,
				map_id = interaction.Map_ID(2),
				include_inactive = true,
			},
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if result.completion == .Recovery_Requested {
		if recovery_workflow_present_startup(commands.recovery_workflow, commands, global_review = true) {
			return Interaction_Result{changed = true}, {}
		}
		command_context_set_diagnostic(commands, "No retained unsaved work")
		return Interaction_Result{changed = true}, {}
	}
	if result.completion == .Describe_Language_State_Requested {
		return command_context_present_language_state(commands, buffer, constraints)
	}
	if result.completion == .Jan_Command_Requested {
		return product_module_workflow_invoke_structured_document(
			commands,
			buffer,
			view_registry,
			view,
			resolution.command,
			constraints,
			edit_transaction.Transaction_ID(transaction_id),
			edit_transaction.Undo_Unit_ID(undo_unit_id),
			grouping,
			commit_observer,
		)
	}
	if result.completion == .Describe_Structural_State_Requested {
		return command_context_present_structural_state(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if result.completion == .Language_Diagnostics_Requested {
		return command_context_present_language_diagnostics(commands)
	}
	if result.completion == .Next_Language_Diagnostic_Requested {
		return command_context_move_language_diagnostic(
			commands,
			buffer,
			view_registry,
			view,
			true,
		)
	}
	if result.completion == .Previous_Language_Diagnostic_Requested {
		return command_context_move_language_diagnostic(
			commands,
			buffer,
			view_registry,
			view,
			false,
		)
	}
	if result.completion == .Next_Location_Requested {
		return command_context_move_active_location(commands, true)
	}
	if result.completion == .Previous_Location_Requested {
		return command_context_move_active_location(commands, false)
	}
	if result.completion == .Language_Service_Inspection_Requested {
		return command_context_present_language_service_inspection(commands, buffer, constraints)
	}
	if result.completion == .Language_Service_Restart_Requested {
		return command_context_restart_language_service(commands, buffer)
	}
	if result.completion == .Language_Interaction_Requested {
		return command_context_begin_language_interaction(commands, buffer, native_route)
	}
	if result.completion == .Package_Catalog_Interaction_Requested {
		return command_context_begin_package_catalog_interaction(commands, native_route)
	}
	if result.completion == .Incremental_Search_Forward_Requested {
		return command_context_begin_search(commands, search.Direction.Forward, .Literal)
	}
	if result.completion == .Incremental_Search_Backward_Requested {
		return command_context_begin_search(commands, search.Direction.Backward, .Literal)
	}
	if result.completion == .Incremental_Regexp_Search_Forward_Requested {
		return command_context_begin_search(
			commands,
			search.Direction.Forward,
			.Regular_Expression,
		)
	}
	if result.completion == .Incremental_Regexp_Search_Backward_Requested {
		return command_context_begin_search(
			commands,
			search.Direction.Backward,
			.Regular_Expression,
		)
	}
	if result.completion == .Search_Next_Occurrence_Requested {
		search_result, search_failure := command_context_repeat_confirmed_search(
			commands,
			buffer,
			view_registry,
			view,
			true,
			modal_navigation.count if modal_navigation_active else 1,
			constraints,
		)
		if search_failure.stage != .None do return search_result, search_failure
		if interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
			visual_result, visual_failure := command_context_modal_visual_reconcile_point(
				commands, buffer, view_registry, view,
			)
			if visual_failure.stage != .None do return {}, visual_failure
			search_result.changed = search_result.changed || visual_result.changed
		}
		return search_result, {}
	}
	if result.completion == .Search_Previous_Occurrence_Requested {
		search_result, search_failure := command_context_repeat_confirmed_search(
			commands,
			buffer,
			view_registry,
			view,
			false,
			modal_navigation.count if modal_navigation_active else 1,
			constraints,
		)
		if search_failure.stage != .None do return search_result, search_failure
		if interaction.profile_activation_modal_visual_kind(commands.profile_activation) != .None {
			visual_result, visual_failure := command_context_modal_visual_reconcile_point(
				commands, buffer, view_registry, view,
			)
			if visual_failure.stage != .None do return {}, visual_failure
			search_result.changed = search_result.changed || visual_result.changed
		}
		return search_result, {}
	}
	if result.completion == .Search_Symbol_At_Point_Requested {
		return command_context_search_symbol_at_point(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
	}
	if result.completion == .Rigid_Indentation_Requested {
		return command_context_begin_rigid_indentation(commands, buffer, view_registry, view)
	}
	search_handled, search_result, search_failure := command_context_dispatch_search_completion(
		commands,
		buffer,
		view_registry,
		view,
		constraints,
		result.completion,
	)
	if search_handled do return search_result, search_failure
	if result.completion == .Symbol_Navigator_Requested {
		return command_context_present_symbol_navigator(commands)
	}
	if result.completion == .Project_Search_Text_Requested {
		return command_context_begin_project_search(commands, .Literal, resolution.command)
	}
	if result.completion == .Project_Search_Text_Regexp_Requested {
		return command_context_begin_project_search(commands, .Regular_Expression, resolution.command)
	}
	if result.completion == .Project_Search_Repeat_Requested {
		return command_context_repeat_project_search(commands, resolution.command)
	}
	if result.completion == .Query_Replace_Requested {
		return command_context_begin_query_replacement(
			commands,
			resolution.command,
			search.Pattern_Kind.Literal,
		)
	}
	if result.completion == .Query_Replace_Regexp_Requested {
		return command_context_begin_query_replacement(
			commands,
			resolution.command,
			search.Pattern_Kind.Regular_Expression,
		)
	}
	if native_route == .Copy_Region || native_route == .Kill_Region ||
	   native_route == .Copy_Rectangle || native_route == .Kill_Rectangle {
		clipboard_output := clipboard_workflow_export(
			&commands.clipboard_workflow,
			commands.kill_ring,
			resolution.command,
			result.transfer,
			commands.temporary_allocator,
		)
		if clipboard_output.diagnostic_length > 0 {
			command_context_set_diagnostic(
				commands,
				string(clipboard_output.diagnostic[:clipboard_output.diagnostic_length]),
			)
		}
	}
	if modal_operator_active &&
	   modal_operator.target == .Active_Selection {
		target_name := "Normal"
		if modal_operator.operator == .Change do target_name = "Insert"
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return command_context_modal_visual_finish(
			commands, view_registry, view, target_name,
		)
	}
	if modal_operator_active && modal_operator.operator == .Change {
		interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
		return command_context_transition_modal_state(commands, "Insert")
	}
	if modal_operator_active do interaction.profile_activation_modal_operator_execution_clear(commands.profile_activation)
	completion_workflow_after_command(
		commands,
		buffer,
		view_registry,
		view,
		native_route,
		&result,
	)
	if modal_command_entry_active {
		_, state, selected := interaction.profile_activation_selection(commands.profile_activation)
		if selected && state.name != "Normal" {
			transition_result, transition_failure := command_context_transition_modal_state(
				commands,
				"Normal",
			)
			if transition_failure.stage != .None do return {}, transition_failure
			canonical_result, canonical_failure := interaction_result(result)
			canonical_result.changed = canonical_result.changed || transition_result.changed
			return canonical_result, canonical_failure
		}
	}
	return interaction_result(result)
}

@(private)
command_context_dispatch_search_completion :: #force_no_inline proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	constraints: display.Viewport_Constraints,
	completion: command.Native_Completion,
) -> (handled: bool, result: Interaction_Result, failure: App_Failure) {
	if completion == .Search_Word_Requested {
		result, failure = command_context_begin_search(
			commands,
			search.Direction.Forward,
			.Literal,
		)
		if failure.stage != .None do return true, result, failure
		commands.search.policy.boundary_mode = .Word
		commands.search.policy_generation += 1
		return true, result, {}
	}
	if completion == .Search_Occur_Requested {
		result, failure = command_context_begin_search(
			commands,
			search.Direction.Forward,
			.Regular_Expression,
		)
		if failure.stage == .None {
			commands.search.post_accept = .Materialize_Results
		}
		return true, result, failure
	}
	if completion == .Search_Highlight_Symbol_Requested {
		result, failure = command_context_begin_search(
			commands,
			search.Direction.Forward,
			.Literal,
		)
		if failure.stage != .None do return true, result, failure
		commands.search.post_accept = .Retain_Highlight
		result, failure = command_context_search_symbol_at_point(
			commands,
			buffer,
			view_registry,
			view,
			constraints,
		)
		return true, result, failure
	}
	if completion == .Search_Highlight_Phrase_Requested ||
	   completion == .Search_Highlight_Regexp_Requested ||
	   completion == .Search_Highlight_Lines_Requested {
		kind := search.Pattern_Kind.Literal
		if completion != .Search_Highlight_Phrase_Requested {
			kind = .Regular_Expression
		}
		result, failure = command_context_begin_search(
			commands,
			search.Direction.Forward,
			kind,
		)
		if failure.stage == .None {
			commands.search.post_accept = .Retain_Highlight
			if completion == .Search_Highlight_Lines_Requested {
				commands.search.post_accept = .Retain_Line_Highlight
			}
		}
		return true, result, failure
	}
	if completion == .Search_Highlight_Remove_Requested {
		search_snapshot, viewed, view_failure := editor_view.search_session_view(
			view_registry,
			view,
		)
		if !viewed {
			return true, {}, App_Failure{stage = .Command_Dispatch, view = view_failure}
		}
		if !search_snapshot.present {
			command_context_set_diagnostic(commands, "No active highlight")
			return true, Interaction_Result{changed = true}, {}
		}
		cleared, clear_failure := command.incremental_search_accept(view_registry, view)
		if !cleared {
			return true, {}, App_Failure{stage = .Command_Dispatch, command = clear_failure}
		}
		return true, Interaction_Result{changed = true}, {}
	}
	return false, {}, {}
}

@(private)
command_history_grouping :: proc(
	commands: ^Command_Context,
	route: command.Native_Route,
	view: editor_view.View_Handle,
	event_sequence: u64,
) -> history.Grouping_Context {
	kind := history.Grouping_Kind.Independent
	if route == .Insert_Text || route == .Insert_Indentation {
		kind = .Typing_Insert
	} else if route == .Delete_Previous_Grapheme {
		kind = .Typing_Backspace
	}
	continuity := commands.grouping_continuity
	if continuity == 0 {
		continuity = 1
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(commands.grouping_started))
	milliseconds := u64(0)
	if elapsed_ns > 0 {
		milliseconds = u64(elapsed_ns) / 1_000_000
	}
	return history.Grouping_Context {
		kind = kind,
		view_id = view.view_id,
		view_generation = view.generation,
		continuity = continuity,
		event_sequence = event_sequence,
		monotonic_milliseconds = milliseconds,
	}
}

@(private)
interaction_result :: proc(
	result: command.Native_Result,
) -> (Interaction_Result, App_Failure) {
	switch result.completion {
	case .No_Op, .Pending_Input_Cancelled:
		return {}, {}
	case .View_Changed, .Buffer_Committed, .Text_Retained:
		return Interaction_Result{changed = true}, {}
	case .Exit_Requested, .Query_Replace_Requested, .Query_Replace_Regexp_Requested:
		return {}, App_Failure{stage = .Command_Dispatch}
	case .Document_Saved:
		return Interaction_Result{save = result.save}, {}
	case .Document_Target_Required:
		return {}, App_Failure{stage = .Command_Dispatch}
	case .Find_File_Requested, .Find_Alternate_File_Requested, .Write_File_Requested,
	     .Save_Some_Buffers_Requested, .Insert_File_Requested,
	     .Next_Buffer_Requested, .Previous_Buffer_Requested,
	     .Numeric_Navigation_Target_Requested, .Rigid_Indentation_Requested,
	     .Switch_To_Buffer_Requested, .Find_File_Other_Pane_Requested,
	     .Switch_To_Buffer_Other_Pane_Requested, .Display_Buffer_Other_Pane_Requested,
	     .Kill_Buffer_Requested,
	     .List_Buffers_Requested, .Interaction_Profile_Reload_Requested,
	     .Personal_Commands_Reload_Requested,
	     .Command_Navigation_Requested, .Command_Description_Requested,
	     .Help_Requested, .Interaction_Profile_Selection_Requested,
	     .Modal_Repeat_Inspection_Requested,
	     .Keyboard_Macro_Start_Requested, .Keyboard_Macro_End_Requested,
	     .Keyboard_Macro_Call_Last_Requested, .Keyboard_Macro_Finish_Or_Call_Requested,
	     .Keyboard_Macro_Name_Last_Requested, .Keyboard_Macro_Call_Named_Requested,
	     .Theme_Selection_Requested,
	     .Theme_Inspection_Requested,
	     .Status_Bar_Inspect_Requested, .Status_Bar_Actions_Requested,
	     .Status_Bar_Activate_Segment_Requested,
	     .Gutter_Command_Requested,
	     .Project_Inspect_Active_Requested, .Project_Promote_Requested,
	     .Project_Unregister_Requested,
	     .Project_Find_File_Requested,
	     .Project_Switch_Buffer_Requested, .Project_Save_Buffers_Requested,
	     .Project_Close_Buffers_Requested, .Project_Refresh_Requested,
	     .Project_Command_Menu_Requested, .Describe_Project_Bindings_Requested,
	     .Recovery_Requested,
	     .Describe_Language_State_Requested, .Describe_Structural_State_Requested,
	     .Language_Diagnostics_Requested, .Next_Language_Diagnostic_Requested,
	     .Previous_Language_Diagnostic_Requested,
	     .Language_Service_Inspection_Requested, .Language_Service_Restart_Requested,
	     .Language_Interaction_Requested, .Package_Catalog_Interaction_Requested,
	     .Workspace_Add_Project_Requested, .Workspace_Remove_Project_Requested,
	     .Workspace_Unregister_Requested,
	     .Save_Location_Requested, .List_Locations_Requested, .Visit_Location_Requested,
	     .Store_Number_Requested, .Increment_Number_Requested, .Store_Text_Requested,
	     .Store_Region_Text_Requested, .Store_Position_Requested, .Insert_Slot_Requested,
	     .Store_Layout_Requested, .Visit_Slot_Requested, .Restore_Layout_Requested,
	     .Next_Location_Requested, .Previous_Location_Requested,
	     .Maksym_Command_Requested, .Darek_Command_Requested,
	     .Completion_Command_Requested, .Terminal_Command_Requested,
	     .Ksawery_Status_Requested, .Jan_Command_Requested:
		return {}, App_Failure{stage = .Command_Dispatch}
	case .Symbol_Navigator_Requested,
	     .Project_Search_Text_Requested, .Project_Search_Text_Regexp_Requested,
	     .Project_Search_Repeat_Requested:
		return {}, App_Failure{stage = .Command_Dispatch}
	case .Incremental_Search_Forward_Requested, .Incremental_Search_Backward_Requested,
	     .Incremental_Regexp_Search_Forward_Requested,
	     .Incremental_Regexp_Search_Backward_Requested,
	     .Search_Symbol_At_Point_Requested, .Search_Word_Requested,
	     .Search_Occur_Requested,
	     .Search_Highlight_Symbol_Requested, .Search_Highlight_Phrase_Requested,
	     .Search_Highlight_Regexp_Requested, .Search_Highlight_Lines_Requested,
	     .Search_Highlight_Remove_Requested,
	     .Search_Next_Occurrence_Requested, .Search_Previous_Occurrence_Requested:
		return {}, App_Failure{stage = .Command_Dispatch}
	case .Invalid:
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	unreachable()
}

@(private)
command_metadata_is_native :: proc(
	metadata: interaction.Command_Metadata,
	route: command.Native_Route,
) -> bool {
	decoded, ok := command.native_route_decode(metadata.route)
	return ok && decoded == route
}

@(private)
command_metadata_is_contextual :: proc(
	metadata: interaction.Command_Metadata,
	route: command.Contextual_Route,
) -> bool {
	decoded, ok := command.contextual_route_decode(metadata.route)
	return ok && decoded == route
}

@(private)
command_metadata_is_cancel :: proc(metadata: interaction.Command_Metadata) -> bool {
	return command_metadata_is_native(metadata, .Keyboard_Quit) ||
	       command_metadata_is_contextual(metadata, .Cancel)
}

@(private)
command_context_direct_profile_active :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.profile_activation == nil do return false
	active_profile, _, selected := interaction.profile_activation_selection(commands.profile_activation)
	if !selected do return false
	catalog, available := interaction.profile_activation_catalog(commands.profile_activation)
	if !available do return false
	for profile in catalog.profiles {
		if profile.identity == active_profile do return profile.name == "direct"
	}
	return false
}

@(private)
command_metadata_prompt_choice :: proc(metadata: interaction.Command_Metadata) -> u8 {
	route, ok := command.contextual_route_decode(metadata.route)
	if !ok {
		return 0
	}
	#partial switch route {
	case .Prompt_Choice_1: return 1
	case .Prompt_Choice_2: return 2
	case .Prompt_Choice_3: return 3
	case .Prompt_Choice_4: return 4
	case: return 0
	}
}

@(private)
command_context_is_keymap_inspection_command :: proc(route: interaction.Command_Route) -> bool {
	dispatch_class, _, ok := command.racket_route_decode(route)
	return ok && dispatch_class == .Keymap_Inspection
}

@(private)
command_context_is_structural_route :: proc(route: command.Native_Route) -> bool {
	return route == .Structural_Forward || route == .Structural_Backward ||
	       route == .Structural_Up || route == .Structural_Down ||
	       route == .Structural_Select || route == .Structural_Indent
}

@(private)
command_context_structural_operation :: proc(
	route: command.Native_Route,
) -> language.Structural_Operation {
	#partial switch route {
	case .Structural_Forward: return .Forward
	case .Structural_Backward: return .Backward
	case .Structural_Up: return .Up
	case .Structural_Down: return .Down
	case .Structural_Select: return .Select
	case .Structural_Indent: return .Indent
	case: return .Invalid
	}
}

@(private)
command_context_structural_language_diagnostic :: proc(
	commands: ^Command_Context,
	failure: language.Failure,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Language_Service,
		"Structural editing is unavailable",
		.Warning,
		fmt.bprintf(
			commands.feedback_content[:],
			"Structural command unavailable: %v (revision %d, limit %d, actual %d)",
			failure.code,
			failure.source_revision,
			failure.limit,
			failure.actual,
		),
	)
}

@(private)
command_context_structural_command_diagnostic :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Command,
		"Structural command was rejected",
		.Warning,
		fmt.bprintf(
			commands.feedback_content[:],
			"Structural command rejected: %v (analysis %v, structural %v)",
			failure.code,
			failure.language_code,
			failure.structural_code,
		),
	)
}

@(private)
command_context_contain_personal_command_failure :: proc(
	commands: ^Command_Context,
	dispatch: command.Racket_Dispatch_Class,
	failure: command.Failure_Context,
) -> bool {
	if commands == nil || dispatch != .Personal do return false
	if len(failure.diagnostic) > 0 {
		command_context_set_channel_diagnostic(commands, .Package, failure.diagnostic)
		return true
	}
	#partial switch failure.code {
	case .Command_Rejected:
		command_context_set_channel_diagnostic(commands, .Package, "Package command rejected the request")
	case .Racket_Exception:
		command_context_set_channel_diagnostic(commands, .Package, "Package command failed")
	case .Cancelled:
		command_context_set_channel_diagnostic(commands, .Package, "Package command cancelled")
	case .Region_Unavailable:
		command_context_set_channel_diagnostic(commands, .Package, "No active selection")
	case:
		command_context_set_channel_diagnostic(
			commands,
			.Package,
			"Package command is unavailable",
			.Warning,
			fmt.bprintf(
				commands.feedback_content[:],
				"Package command unavailable: %v",
				failure.code,
			),
		)
	}
	return true
}

@(private)
command_context_overlay :: proc(
	commands: ^Command_Context,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) -> (label, text: string, ok: bool) {
	if commands.prompt_workflow.mode == .Result_Edit {
		prompt_view, prompt_ok, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok do return "", "", false
		label = "Edit result text: "
		if commands.prompt_workflow.rejected do label = "Edit result text (invalid): "
		return label, prompt_view.text, true
	}
	if commands.prompt_workflow.mode == .Keymap_Sequence {
		label = "Describe key: "
		if commands.interaction_workflow.inspection_sequence.stroke_count == 0 {
			return label, "", true
		}
		notation, notation_ok := interaction.key_sequence_notation(
			commands.interaction_workflow.inspection_sequence,
			commands.overlay_text[:],
		)
		return label, notation, notation_ok
	}
	if commands.prompt_workflow.mode == .Keymap_Command || commands.prompt_workflow.mode == .Keymap_Map {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return "", "", false
		}
		label = "Where is command: " if commands.prompt_workflow.mode == .Keymap_Command else "Describe keymap ID: "
		if commands.prompt_workflow.rejected {
			label = "Where is command (unknown): " if commands.prompt_workflow.mode == .Keymap_Command else
			        "Describe keymap ID (invalid): "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Keyboard_Macro_Name ||
	   commands.prompt_workflow.mode == .Keyboard_Macro_Call {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		label = "Name keyboard macro: " if commands.prompt_workflow.mode == .Keyboard_Macro_Name else
		        "Call keyboard macro: "
		if commands.prompt_workflow.rejected {
			label = "Name keyboard macro (invalid): " if commands.prompt_workflow.mode == .Keyboard_Macro_Name else
			        "Call keyboard macro (unknown): "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Shell_Command ||
	   commands.prompt_workflow.mode == .Async_Shell_Command ||
	   commands.prompt_workflow.mode == .Compile_Command {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		label = "Shell command: "
		if commands.prompt_workflow.mode == .Async_Shell_Command {
			label = "Async shell command: "
		} else if commands.prompt_workflow.mode == .Compile_Command {
			label = "Compile command: "
		}
		if commands.prompt_workflow.rejected {
			label = "Shell command (invalid): "
			if commands.prompt_workflow.mode == .Async_Shell_Command {
				label = "Async shell command (invalid): "
			} else if commands.prompt_workflow.mode == .Compile_Command {
				label = "Compile command (invalid): "
			}
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Query_Replacement_Pattern ||
	   commands.prompt_workflow.mode == .Query_Replacement_Replacement {
		prompt_view, prompt_ok, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok {
			return "", "", false
		}
		if commands.prompt_workflow.mode == .Query_Replacement_Pattern {
			label = "Query replace regexp: " if commands.search.kind == .Regular_Expression else
			        "Query replace: "
			if commands.prompt_workflow.rejected && commands.search.kind == .Regular_Expression {
				label = fmt.bprintf(
					commands.overlay_label[:],
					"Query replace regexp (%v at %d): ",
					commands.search.diagnostic.kind,
					commands.search.diagnostic.byte_offset,
				)
			} else if commands.prompt_workflow.rejected {
				label = "Query replace (invalid): "
			}
			return label, prompt_view.text, true
		}
		label = "Replace regexp with: " if commands.search.kind == .Regular_Expression else
		        "Replace with: "
		return label, prompt_view.text, true
	}
	if commands.prompt_workflow.mode == .Query_Replacement_Response {
		state, state_ok, _ := editor_view.query_replacement_session_view(view_registry, view)
		if !state_ok || !state.present {
			return "", "", false
		}
		status := "Query replace"
		switch state.status {
		case .Pending:                status = "Pending query replace"
		case .Wrapped:                status = "Wrapped query replace"
		case .Recomputation_Required: status = "Stale query replace"
		case .Exhausted:              status = "Finished query replace"
		case .Inactive, .Awaiting_Response:
		}
		case_text := "smart"
		if state.effective_case == .Sensitive {
			case_text = "sensitive"
		} else if state.effective_case == .Insensitive {
			case_text = "insensitive"
		}
		label = fmt.bprintf(
			commands.overlay_label[:],
			"%s [%s; %d replaced, %d skipped] [y/SPC n/DEL ! . q/RET C-g]: ",
			status,
			case_text,
			state.replacements,
			state.skips,
		)
		text = fmt.bprintf(
			commands.overlay_text[:],
			"%s -> %s",
			state.pattern,
			state.replacement,
		)
		return label, text, true
	}
	if commands.prompt_workflow.mode == .Incremental_Search {
		prompt_view, prompt_ok, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok {
			return "", "", false
		}
		search_snapshot, search_ok, _ := editor_view.search_session_view(view_registry, view)
		if !search_ok {
			return "", "", false
		}
		status := "Search"
		regexp_search := commands.search.kind == .Regular_Expression
		if regexp_search {
			status = "Regexp"
		}
		case_text := "smart"
		if commands.search.policy.case_mode == .Sensitive {
			case_text = "sensitive"
		} else if commands.search.policy.case_mode == .Insensitive {
			case_text = "insensitive"
		}
		direction := commands.search.direction
		if search_snapshot.present {
			direction = search_snapshot.direction
			switch search_snapshot.status {
			case .Failing:
				status = "Failing Regexp" if regexp_search else "Failing Search"
			case .Pending:
				status = "Pending Regexp" if regexp_search else "Pending Search"
			case .Wrapped:
				status = "Wrapped Regexp" if regexp_search else "Wrapped Search"
			case .Inactive, .Active:
			}
			if commands.search.policy.case_mode == .Smart && search_snapshot.effective_case == .Sensitive {
				case_text = "smart/sensitive"
			} else if commands.search.policy.case_mode == .Smart && search_snapshot.effective_case == .Insensitive {
				case_text = "smart/insensitive"
			}
		}
		boundary_text := "any"
		if commands.search.policy.boundary_mode == .Word {
			boundary_text = "word"
		} else if commands.search.policy.boundary_mode == .Symbol {
			boundary_text = "symbol"
		}
		whitespace_text := "exact"
		if commands.search.policy.whitespace_mode == .Flexible {
			whitespace_text = "flex"
		}
		direction_text := "→"
		if direction == .Backward {
			direction_text = "←"
		}
		label = fmt.bprintf(
			commands.overlay_label[:],
			"%s %s [%s %s %s]: ",
			status,
			direction_text,
			case_text,
			boundary_text,
			whitespace_text,
		)
		if commands.prompt_workflow.rejected && commands.search.kind == .Regular_Expression {
			label = fmt.bprintf(
				commands.overlay_label[:],
				"%s %s (%v at %d) [%s %s %s]: ",
				status,
				direction_text,
				commands.search.diagnostic.kind,
				commands.search.diagnostic.byte_offset,
				case_text,
				boundary_text,
				whitespace_text,
			)
		} else if commands.prompt_workflow.rejected {
			label = fmt.bprintf(
				commands.overlay_label[:],
				"%s %s (invalid) [%s %s %s]: ",
				status,
				direction_text,
				case_text,
				boundary_text,
				whitespace_text,
			)
		}
		return label, prompt_view.text, true
	}
	if commands.prompt_workflow.mode == .Project_Search {
		prompt_view, prompt_ok, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !prompt_ok do return "", "", false
		label = "Project regexp search: " if commands.project_search_workflow.kind == .Regular_Expression else
		        "Project search: "
		if commands.prompt_workflow.rejected {
			label = "Project regexp search (invalid): " if commands.project_search_workflow.kind == .Regular_Expression else
			        "Project search (invalid): "
		}
		return label, prompt_view.text, true
	}
	if commands.prompt_workflow.mode == .Save_Path || commands.prompt_workflow.mode == .Exit_Save_Path ||
	   commands.prompt_workflow.mode == .Kill_Save_Path {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return "", "", false
		}
		label = "Save as: "
		if commands.prompt_workflow.rejected {
			label = "Save as (invalid): "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Write_File_Path ||
	   commands.prompt_workflow.mode == .Insert_File_Path ||
	   commands.prompt_workflow.mode == .Navigation_Target {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		if commands.prompt_workflow.mode == .Write_File_Path {
			label = "Write file: "
		} else if commands.prompt_workflow.mode == .Insert_File_Path {
			label = "Insert file: "
		} else {
			label = "Target: "
		}
		if commands.prompt_workflow.rejected {
			label = "Write file (invalid): " if commands.prompt_workflow.mode == .Write_File_Path else
			        "Insert file (invalid): " if commands.prompt_workflow.mode == .Insert_File_Path else
			        "Target (positive integer required): "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Marked_Kill_Choice {
		return "Marked buffer: ", "[s]ave [d]iscard [c]ancel", true
	}
	if commands.prompt_workflow.mode == .Project_Close_Choice {
		return "Project buffer: ", "[s]ave [d]iscard [c]ancel", true
	}
	if commands.prompt_workflow.mode == .Marked_Save_Path {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return "", "", false
		}
		label = "Save marked buffer as: "
		if commands.prompt_workflow.rejected {
			label = "Save marked buffer as (invalid): "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Find_File ||
	   commands.prompt_workflow.mode == .Find_File_Other_Pane ||
	   commands.prompt_workflow.mode == .Switch_To_Buffer ||
	   commands.prompt_workflow.mode == .Kill_Buffer {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return "", "", false
		}
		if commands.prompt_workflow.mode == .Find_File_Other_Pane {
			label = "Find file in other pane: "
		} else if commands.prompt_workflow.mode == .Find_File {
			label = "Find file: "
		} else if commands.prompt_workflow.mode == .Switch_To_Buffer {
			label = "Switch to buffer: "
		} else {
			label = "Kill buffer: "
		}
		if commands.prompt_workflow.rejected {
			if commands.prompt_workflow.mode == .Find_File_Other_Pane {
				label = "Find file in other pane (invalid): "
			} else if commands.prompt_workflow.mode == .Find_File {
				label = "Find file (invalid): "
			} else if commands.prompt_workflow.mode == .Switch_To_Buffer {
				label = "Switch to buffer (invalid): "
			} else {
				label = "Kill buffer (invalid): "
			}
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Project_Create_Directory ||
	   commands.prompt_workflow.mode == .Project_Promote_Name {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed {
			return "", "", false
		}
		if commands.prompt_workflow.mode == .Project_Create_Directory {
			label = "Open directory: "
		} else {
			label = "Promote Dir as: "
		}
		if commands.prompt_workflow.rejected {
			label = "Project directory (invalid): "
			if commands.prompt_workflow.mode == .Project_Promote_Name {
				label = "Project name (invalid): "
			}
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Terminal_Rename {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		label = "Terminal name (invalid): " if commands.prompt_workflow.rejected else "Rename terminal: "
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Named_Location_Name {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		label = "Location name (invalid): " if commands.prompt_workflow.rejected else "Save location as: "
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Named_Slot_Input {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		state := &commands.named_slot_workflow
		if state.phase == .Name {
			base := named_slot_operation_type_label(state.operation)
			label = fmt.bprintf(
				commands.overlay_label[:],
				"%s slot name%s: ",
				base,
				" (invalid)" if commands.prompt_workflow.rejected else "",
			)
		} else if state.operation == .Store_Number {
			label = "Integer (invalid): " if commands.prompt_workflow.rejected else "Integer value: "
		} else if state.operation == .Increment_Number {
			label = "Increment (invalid): " if commands.prompt_workflow.rejected else "Increment by: "
		} else {
			label = "Text (invalid): " if commands.prompt_workflow.rejected else "Text value: "
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Named_Slot_Confirmation {
		return "Replace existing slot with a different type? ", "[y]es [n]o", true
	}
	if commands.prompt_workflow.mode == .Package_Catalog_Input {
		view, viewed, _ := interaction.prompt_view(&commands.prompt_workflow.prompt)
		if !viewed do return "", "", false
		if commands.package_catalog_runtime_workflow == nil do return "", "", false
		label = package_catalog_runtime_input_label(commands.package_catalog_runtime_workflow.action)
		if commands.prompt_workflow.rejected {
			label = fmt.bprintf(commands.overlay_label[:], "%s(invalid) ", label)
		}
		return label, view.text, true
	}
	if commands.prompt_workflow.mode == .Package_Catalog_Confirmation {
		state := commands.package_catalog_runtime_workflow
		if state == nil || state.confirmation_length == 0 do return "", "", false
		value := fmt.bprintf(
			commands.overlay_label[:],
			"[y]es [n]o - %s",
			string(state.confirmation[:state.confirmation_length]),
		)
		return "Confirm: ", value, len(value) > 0
	}
	if commands.prompt_workflow.mode == .Last_Pane_Exit_Choice {
		return "Last pane. Exit Odra? ", "[y]es [n]o", true
	}
	if commands.prompt_workflow.mode == .Terminal_Exit_Choice {
		count := terminal_workflow_live_count(commands.terminal_workflow)
		label = fmt.bprintf(commands.overlay_label[:], "Exit and terminate %d live terminal%s? ", count, "s" if count != 1 else "")
		return label, "[y]es [n]o", true
	}
	if commands.prompt_workflow.mode == .Terminal_Kill_Choice {
		return "Terminate process and close terminal buffer? ", "[y]es [n]o", true
	}
	if commands.prompt_workflow.mode == .Kill_File_Discard_Choice {
		return "Discard changes and kill buffer? ", "[y]es [n]o", true
	}
	if commands.prompt_workflow.mode == .Kill_Unassociated_Choice {
		return "Modified buffer: ", "[s]ave [d]iscard [c]ancel", true
	}
	if commands.prompt_workflow.mode == .Exit_Choice {
		return "Save changes? ", "[s]ave [d]iscard [c]ancel", true
	}
	if commands.prompt_workflow.mode == .Dir_Abandonment_Choice {
		return "Add this Dir to Projects? ", "[y]es [n]o [c]ancel [d]on't ask again", true
	}
	if commands.diagnostic_length > 0 {
		return "", string(commands.diagnostic[:commands.diagnostic_length]), true
	}
	return command_context_global_context_overlay(commands)
}

@(private)
command_context_document_diagnostic :: proc(
	commands: ^Command_Context,
	label: string,
	failure: document.Failure_Context,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Save,
		"The file could not be saved",
		.Error,
		fmt.bprintf(
			commands.feedback_content[:],
			"%s: %v (publication: %v)",
			label,
			failure.code,
			failure.publication,
		),
		.Required,
		.History,
	)
}

@(private)
command_context_set_diagnostic :: proc(commands: ^Command_Context, message: string) {
	command_context_set_channel_diagnostic(commands, .Command, message)
}

@(private)
command_context_candidate_failure_diagnostic :: proc(
	commands: ^Command_Context,
	operation: string,
	failure: interaction.Candidate_Failure,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Command,
		"Candidate list could not be updated; prior results were preserved",
		.Warning,
		fmt.bprintf(
			commands.feedback_content[:],
			"%s failed: %v (session %d, source %d, limit %d, actual %d)",
			operation,
			failure.code,
			failure.session_generation,
			failure.source_generation,
			failure.limit,
			failure.actual,
		),
	)
}

@(private)
command_context_query_failure_diagnostic :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Command,
		"Query replacement could not be completed",
		.Error,
		fmt.bprintf(
			commands.feedback_content[:],
			"Query replace failed: %v (search: %v, view: %v)",
			failure.code,
			failure.search_code,
			failure.view_code,
		),
	)
}

@(private)
command_context_buffer_session_diagnostic :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Command,
		"Buffer operation could not be completed",
		.Error,
		fmt.bprintf(
			commands.feedback_content[:],
			"Buffer command failed: %v (session: %v, document: %v)",
			failure.code,
			failure.editor_session_code,
			failure.document_code,
		),
	)
}

@(private)
command_context_first_save_diagnostic :: proc(
	commands: ^Command_Context,
	failure: command.Failure_Context,
) {
	command_context_set_channel_diagnostic(
		commands,
		.Save,
		"The file could not be saved",
		.Error,
		fmt.bprintf(
			commands.feedback_content[:],
			"Save failed: %v",
			failure.document_code,
		),
		.Required,
		.History,
	)
}

@(private)
command_context_clear_exit :: proc(commands: ^Command_Context) {
	document_workflow_reset_exit(&commands.document_workflow)
	if commands != nil && commands.terminal_workflow != nil {
		commands.terminal_workflow.exit_confirmed = false
	}
}

@(private)
command_context_close :: proc(commands: ^Command_Context) -> (failure: App_Failure) {
	pointer_text_capture_clear(commands)
	popup_workflow_close(&commands.popup_workflow)
	popup_fallback_clear(&commands.popup_fallback)
	if completion_workflow_is_live(commands.completion_workflow) {
		completion_workflow_close(commands.completion_workflow)
	}
	if language_service_workflow_is_live(commands.language_service_workflow) {
		language_service_workflow_close(commands.language_service_workflow)
	}
	if syntax_workflow_is_live(commands.syntax_workflow) {
		closed, language_failure := syntax_workflow_close(commands.syntax_workflow)
		if !closed {
			failure = App_Failure{stage = .Language_Close, language = language_failure}
		}
	}
	if commands.ui_registry.state != nil && !commands.ui_registry.closed {
		closed, ui_failure := ui.registry_close(&commands.ui_registry)
		if !closed {
			failure = App_Failure{stage = .UI, ui = ui_failure}
		}
	}
	command_context_feedback_close(commands)
	if commands.presentation_profiles.state != nil && !commands.presentation_profiles.closed {
		closed, _ := ui.presentation_profile_registry_close(&commands.presentation_profiles)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .UI, ui = {operation = .Teardown, code = .Invalid_Registry}}
		}
	}
	if commands.theme_registry.state != nil && !commands.theme_registry.closed {
		closed, theme_failure := theme.theme_registry_close(&commands.theme_registry)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Theme_Close, theme = theme_failure}
		}
	}
	if commands.status_bar_registry.state != nil && !commands.status_bar_registry.closed {
		closed, status_failure := status_bar.registry_close(&commands.status_bar_registry)
		if !closed && failure.stage == .None {
			failure = App_Failure{stage = .Status, status_bar = {
				operation = .Close,
				code = .Invalid_Request,
				limit = status_failure.limit,
				actual = status_failure.actual,
			}}
		}
	}
	layout_failure := command_context_layout_close(commands)
	if layout_failure.stage != .None && failure.stage == .None {
		failure = layout_failure
	}
	if commands.terminal_workflow != nil && commands.terminal_workflow.initialized {
		closed, terminal_failure := terminal_workflow_close(commands.terminal_workflow)
		if !closed && failure.stage == .None {
			failure = app_terminal_workflow_failure(terminal_failure)
		}
	}
	command_context_end_prompt(commands)
	darek_workflow_close(commands)
	command_context_deactivate_context_map(commands, .Invalidated)
	interaction_workflow_reset(&commands.interaction_workflow)
	personal_candidate_workflow_reset(commands)
	candidate_ui_workflow_reset(&commands.candidate_ui)
	keymap_inspection_workflow_reset(&commands.keymap_inspection_workflow)
	language_state_workflow_reset(&commands.language_state_workflow)
	language_service_inspection_workflow_reset(&commands.language_service_inspection_workflow)
	language_interaction.workflow_reset(&commands.language_interaction_workflow)
	if commands.package_catalog_interaction_workflow != nil {
		package_catalog_interaction.workflow_reset(commands.package_catalog_interaction_workflow)
		free(commands.package_catalog_interaction_workflow, commands.persistent_allocator)
		commands.package_catalog_interaction_workflow = nil
	}
	if commands.package_catalog_runtime_workflow != nil {
		package_catalog_runtime_workflow_reset(commands.package_catalog_runtime_workflow)
		free(commands.package_catalog_runtime_workflow, commands.persistent_allocator)
		commands.package_catalog_runtime_workflow = nil
	}
	structural_state_workflow_reset(&commands.structural_state_workflow)
	if commands.structural_command_state != nil do commands.structural_command_state^ = {}
	commands.structural_capability_generation = 0
	theme_inspection_workflow_reset(&commands.theme_inspection_workflow)
	project_workflow_reset_transient(&commands.project_workflow)
	workspace_workflow_reset(&commands.workspace_workflow)
	named_location_workflow_reset(&commands.named_location_workflow)
	named_slot_workflow_reset(&commands.named_slot_workflow)
	project_search_workflow_close(&commands.project_search_workflow, commands.persistent_allocator)
	product_module_workflow_close(commands)
	if commands.location_history != nil {
		free(commands.location_history, commands.persistent_allocator)
		commands.location_history = nil
	}
	command_context_finish_rigid_indentation(commands, .Invalidated)
	if commands.rigid_indentation != nil {
		free(commands.rigid_indentation, commands.persistent_allocator)
		commands.rigid_indentation = nil
	}
	if commands.modal_repeat != nil {
		interaction.modal_repeat_clear(commands.modal_repeat)
		free(commands.modal_repeat, commands.persistent_allocator)
		commands.modal_repeat = nil
	}
	if commands.keyboard_macro != nil {
		interaction.keyboard_macro_clear(commands.keyboard_macro)
		free(commands.keyboard_macro, commands.persistent_allocator)
		commands.keyboard_macro = nil
	}
	command_context_candidate_history_flush(commands)
	project.candidate_history_close(&commands.project_workflow.candidate_history)
	document_workflow_reset_dir_abandonment(&commands.document_workflow)
	command_context_clear_exit(commands)
	inventory_workflow_reset(&commands.inventory_workflow)
	clipboard_workflow_reset(&commands.clipboard_workflow)
	command_context_structural_state_close(commands)
	return failure
}

@(private)
command_context_structural_state_init :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.structural_command_state != nil ||
	   commands.persistent_allocator.procedure == nil {
		return false
	}
	owner, allocation_error := new(command.Structural_Capability_State, commands.persistent_allocator)
	if allocation_error != nil do return false
	owner^ = {}
	commands.structural_command_state = owner
	return true
}

@(private)
command_context_structural_state_close :: proc(commands: ^Command_Context) {
	if commands == nil || commands.structural_command_state == nil do return
	free(commands.structural_command_state, commands.persistent_allocator)
	commands.structural_command_state = nil
}
