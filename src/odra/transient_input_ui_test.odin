// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "../ui"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies every projected prompt mode binds its exact owner and generation. */
@(test)
prompt_interactions_project_exact_models :: proc(t: ^testing.T) {
	cases := []struct {
		mode: Prompt_Mode,
		kind: interaction.Prompt_Kind,
	} {
		{.Save_Path, .Text_Entry},
		{.Find_File, .Text_Entry},
		{.Find_File_Other_Pane, .Text_Entry},
		{.Switch_To_Buffer, .Text_Entry},
		{.Kill_Buffer, .Text_Entry},
		{.Project_Create_Directory, .Text_Entry},
		{.Project_Promote_Name, .Text_Entry},
		{.Dir_Abandonment_Choice, .Fixed_Choice},
		{.Kill_File_Discard_Choice, .Fixed_Choice},
		{.Kill_Unassociated_Choice, .Fixed_Choice},
		{.Kill_Save_Path, .Text_Entry},
		{.Marked_Kill_Choice, .Fixed_Choice},
		{.Project_Close_Choice, .Fixed_Choice},
		{.Marked_Save_Path, .Text_Entry},
		{.Last_Pane_Exit_Choice, .Fixed_Choice},
		{.Exit_Choice, .Fixed_Choice},
		{.Exit_Save_Path, .Text_Entry},
		{.Incremental_Search, .Text_Entry},
		{.Query_Replacement_Pattern, .Text_Entry},
		{.Query_Replacement_Replacement, .Text_Entry},
		{.Keymap_Sequence, .Invalid},
		{.Keymap_Command, .Text_Entry},
		{.Keymap_Map, .Text_Entry},
	}
	for test_case, index in cases {
		commands := Command_Context{persistent_allocator = context.allocator}
		began := prompt_workflow_begin_projection(&commands.prompt_workflow, test_case.mode)
		testing.expect(t, began)
		if !began do continue
		if test_case.kind != .Invalid {
			fixed_choices := prompt_save_discard_cancel_choices()
			choices := fixed_choices[:]
			if test_case.kind != .Fixed_Choice do choices = nil
			config := interaction.Prompt_Config {
				kind = test_case.kind,
				text_bytes_limit = 32 if test_case.kind == .Text_Entry else 0,
				choices = choices,
				allocator = context.allocator,
			}
			initialized, _ := interaction.prompt_init(&commands.prompt_workflow.prompt, config)
			testing.expect(t, initialized)
			if !initialized do continue
			if test_case.kind == .Text_Entry {
				_, append_failure := interaction.prompt_text_append(
					&commands.prompt_workflow.prompt,
					"λ",
				)
				testing.expect_value(t, append_failure.code, interaction.Prompt_Failure_Code.None)
			}
		}
		commands.prompt_workflow.rejected = index % 2 == 1
		registry: ui.Registry
		initialized, _ := ui.registry_init(&registry, ui.Registry_ID(index + 1))
		testing.expect(t, initialized)
		if !initialized {
			if commands.prompt_workflow.prompt.state != nil do _, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			continue
		}
		proposal, prepared, _ := ui.proposal_begin(&registry)
		_, style_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
		viewport_bytes := u32(1)
		if test_case.kind == .Text_Entry do viewport_bytes = 3
		input_view, projected, projection_failure := proposal_project_prompt_input(
			&proposal,
			&commands,
			Prompt_Input_Projection_Request {
				presentation_generation = 7,
				viewport_bytes = viewport_bytes,
			},
		)
		testing.expectf(t, projected, "prompt mode %v projection failed: %v", test_case.mode, projection_failure)
		if !projected {
			ui.proposal_abort(&proposal)
			ui.registry_close(&registry)
			if commands.prompt_workflow.prompt.state != nil do _, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
			continue
		}
		surface, surface_ok, _ := ui.proposal_add_surface(
			&proposal,
			ui.Surface_Descriptor {
				owner_id = ui.Owner_ID(prompt_mode_owner_id(test_case.mode)),
				view = input_view,
				focusable = true,
				visible = true,
				required_profile = 1,
				geometry = {height = 1, width = 80},
			},
		)
		node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
		root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
		root, published, publish_failure := ui.proposal_publish(
			&registry,
			&proposal,
			transient_input_test_renderer(),
		)
		testing.expectf(t, published, "prompt mode %v publish failed: %v", test_case.mode, publish_failure)
		if !published do ui.proposal_abort(&proposal)
		if published {
			snapshot, copied, _ := ui.registry_snapshot(
				&registry,
				root,
				transient_input_test_renderer(),
			)
			testing.expect(t, copied)
			if copied {
				state, state_ok := ui.snapshot_view(&snapshot)
				view := state.views[input_view.slot]
				projection := state.projections[view.projection.slot]
				value, value_ok := ui.snapshot_input_value(state, view)
				testing.expect(t, state_ok && value_ok)
				testing.expect_value(t, projection.model.owner_id, ui.Owner_ID(prompt_mode_owner_id(test_case.mode)))
				testing.expect_value(t, projection.model.model_id, ui.Model_ID(test_case.mode))
				testing.expect_value(t, projection.model.generation, commands.prompt_workflow.projection_generation)
				testing.expect_value(t, view.input.backing_generation, u64(commands.prompt_workflow.projection_generation))
				testing.expect_value(t, view.input.presentation_generation, u64(7))
				testing.expect_value(
					t,
					view.input.validation,
					ui.Input_Validation_State.Rejected if commands.prompt_workflow.rejected else ui.Input_Validation_State.Valid,
				)
				expected_value := "λ" if test_case.kind == .Text_Entry else ""
				testing.expect_value(t, value, expected_value)
				choices, choices_ok := ui.snapshot_input_choices(state, view)
				testing.expect(t, choices_ok)
				if test_case.kind == .Fixed_Choice {
					testing.expect_value(t, len(choices), 3)
					if len(choices) == 3 {
						name, name_ok := ui.snapshot_input_choice_name(state, choices[1])
						command_name, command_ok := prompt_input_choice_command(&commands, choices[1].action)
						testing.expect(t, name_ok && command_ok)
						testing.expect_value(t, name, "[d]iscard")
						testing.expect_value(t, command_name, "prompt-choice-2")
						stale := choices[1].action
						stale.generation += 1
						_, stale_ok := prompt_input_choice_command(&commands, stale)
						testing.expect(t, !stale_ok)
					}
				} else {
					testing.expect_value(t, len(choices), 0)
				}
				ui.snapshot_close(&snapshot)
			}
		}
		testing.expect(t, prepared && style_ok && surface_ok && node_ok && root_ok)
		ui.registry_close(&registry)
		if commands.prompt_workflow.prompt.state != nil do _, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
}

/* Verifies prompt projection generations are monotonic and nested states cannot project. */
@(test)
prompt_rejects_stale_search_state :: proc(t: ^testing.T) {
	state: Prompt_Workflow_State
	testing.expect(t, prompt_workflow_begin_projection(&state, .Save_Path))
	testing.expect_value(t, state.projection_generation, ui.Model_Generation(1))
	testing.expect(t, prompt_workflow_advance_projection(&state))
	testing.expect_value(t, state.projection_generation, ui.Model_Generation(2))
	testing.expect(t, !prompt_workflow_begin_projection(&state, .Find_File))
	state.mode = .None
	state.projection_generation = {}
	testing.expect(t, prompt_workflow_begin_projection(&state, .Find_File))
	testing.expect_value(t, state.projection_generation, ui.Model_Generation(3))
	testing.expect(t, !prompt_workflow_begin_projection(&state, .Incremental_Search))
	testing.expect_value(t, state.mode, Prompt_Mode.Find_File)
	state.mode = .None
	state.projection_generation = {}
	testing.expect(t, prompt_workflow_begin_projection(&state, .Incremental_Search))
	testing.expect_value(t, state.projection_generation, ui.Model_Generation(4))

	commands := Command_Context{prompt_workflow = {mode = .Find_File}}
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 99)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, projected, failure := proposal_project_prompt_input(
		&proposal,
		&commands,
		{presentation_generation = 1, viewport_bytes = 1},
	)
	testing.expect(t, prepared && !projected)
	testing.expect_value(t, failure.code, ui.Failure_Code.Invalid_View)
	ui.proposal_abort(&proposal)
}

/* Verifies routed prompt changes advance the exact projected interaction generation. */
@(test)
prompt_input_routing_advances_changed_generation :: proc(t: ^testing.T) {
	commands: Command_Context
	testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, .Keymap_Sequence))
	result, failure := dispatch_prompt(
		&commands,
		nil,
		nil,
		{},
		{},
		{width_cells = 80, height_rows = 24},
	)
	testing.expect(t, result.changed && failure.stage == .None)
	testing.expect(t, commands.prompt_workflow.rejected)
	testing.expect_value(t, commands.prompt_workflow.projection_generation, ui.Model_Generation(2))
}

/* Verifies prompt focus capture releases once to its checked root return target. */
@(test)
prompt_focus_capture_releases_on_owner_close :: proc(t: ^testing.T) {
	commands := Command_Context{persistent_allocator = context.allocator}
	registry, registry_ok, registry_failure := command_context_ui_registry(&commands)
	testing.expectf(t, registry_ok, "prompt registry init failed: %v", registry_failure)
	if !registry_ok do return
	defer if commands.ui_registry.state != nil do ui.registry_close(&commands.ui_registry)
	proposal, prepared, _ := ui.proposal_begin(registry)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
	input, input_ok, _ := ui.proposal_project_input(
		&proposal,
		ui.Input_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			presentation_generation = 1,
			backing_generation = 1,
			viewport_bytes = 1,
			validation = .Valid,
		},
		"",
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = input,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 1, width = 80},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(registry, &proposal, transient_input_test_renderer())
	commands.ui_root = root
	testing.expect(t, prepared && style_ok && input_ok && surface_ok && node_ok && root_ok && published)
	if !published do return
	testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, .Keymap_Sequence))
	capture_failure := command_context_capture_prompt_focus(&commands, surface)
	focus, focused, _ := ui.registry_focus(registry)
	testing.expect(t, capture_failure.stage == .None && focused && focus.captured)
	testing.expect_value(t, focus.target, surface)
	command_context_end_prompt(&commands)
	restored, restored_ok, _ := ui.registry_focus(registry)
	testing.expect(t, restored_ok && !restored.captured)
	testing.expect_value(t, restored.target, surface)
	testing.expect(t, !commands.prompt_workflow.focus_captured)
}

/* Verifies transient input reserves one root-edge row without overlapping its base surface. */
@(test)
composition_reserves_root_edge :: proc(t: ^testing.T) {
	commands := Command_Context{persistent_allocator = context.allocator}
	choices := prompt_save_discard_cancel_choices()
	prompt_ok, _ := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Fixed_Choice,
			choices = choices[:],
			allocator = context.allocator,
		},
	)
	testing.expect(t, prompt_ok)
	if !prompt_ok do return
	defer if commands.prompt_workflow.prompt.state != nil do _, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, .Exit_Choice))

	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 100)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, status_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
	_, rejected_ok, _ := ui.proposal_add_style(&proposal, .Diagnostic_Rejected)
	items := []ui.List_Item_Definition {{id = 1, text = "base", action = {owner_id = 1, action_id = 1, generation = 1}}}
	list, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View, current_item = 0, viewport_items = 4},
		},
		items,
	)
	base_surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 80},
		},
	)
	base_node, node_ok, _ := ui.proposal_add_surface_node(&proposal, base_surface)
	composition, composed, compose_failure := proposal_compose_transient_input(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 80, height_rows = 5},
		1,
	)
	testing.expectf(t, composed, "transient composition failed: %v", compose_failure)
	if !composed {
		ui.proposal_abort(&proposal)
		return
	}
	root, published, publish_failure := ui.proposal_publish(
		&registry,
		&proposal,
		transient_input_test_renderer(),
	)
	testing.expectf(t, published, "transient publish failed: %v", publish_failure)
	if published {
		captured, _ := ui.registry_capture_focus(&registry, composition.input_surface)
		snapshot, copied, _ := ui.registry_snapshot(&registry, root, transient_input_test_renderer())
		testing.expect(t, captured && copied)
		if copied {
			state, state_ok := ui.snapshot_view(&snapshot)
			input_surface := state.surfaces[composition.input_surface.slot]
			base := state.surfaces[base_surface.slot]
			testing.expect(t, state_ok)
			testing.expect_value(t, base.geometry.height, i32(4))
			testing.expect_value(t, input_surface.geometry.row, i32(4))
			testing.expect_value(t, input_surface.geometry.height, i32(1))
			testing.expect_value(t, len(state.status_regions), 1)
			if len(state.status_regions) == 1 {
				testing.expect_value(t, state.status_regions[0].placement, ui.Status_Placement.Root_Edge)
				testing.expect_value(t, state.status_regions[0].geometry.row, i32(4))
			}
			ui.snapshot_close(&snapshot)
		}
	}
	testing.expect(t, prepared && normal_ok && current_ok && status_ok && rejected_ok &&
		list_ok && surface_ok && node_ok)
}

/* Verifies command diagnostics publish as semantic root-edge status without an input. */
@(test)
diagnostic_publishes_status :: proc(t: ^testing.T) {
	commands: Command_Context
	command_context_set_diagnostic(&commands, "Command rejected")
	content_rows, rows_ok := transient_input_content_rows(
		&commands,
		{width_cells = 80, height_rows = 5},
	)
	testing.expect(t, rows_ok)
	testing.expect_value(t, content_rows, u32(4))

	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 103)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, diagnostic_ok, _ := ui.proposal_add_style(&proposal, .Diagnostic_Normal, {.Bold})
	items := []ui.List_Item_Definition {{id = 1, text = "base", action = {owner_id = 1, action_id = 1, generation = 1}}}
	list, list_ok, list_failure := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View, viewport_items = 4},
		},
		items,
	)
	testing.expectf(t, list_ok, "diagnostic base list failed: %v", list_failure)
	base_surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 80},
		},
	)
	testing.expectf(t, surface_ok, "diagnostic base surface failed: %v", surface_failure)
	base_node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, base_surface)
	testing.expectf(t, node_ok, "diagnostic base node failed: %v", node_failure)
	composed, compose_failure := proposal_compose_command_feedback(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 80, height_rows = 5},
	)
	testing.expectf(t, composed, "diagnostic composition failed: %v", compose_failure)
	root, published, publish_failure := ui.proposal_publish(
		&registry,
		&proposal,
		transient_input_test_renderer(),
	)
	testing.expectf(t, published, "diagnostic publish failed: %v", publish_failure)
	if published {
		snapshot, copied, _ := ui.registry_snapshot(&registry, root, transient_input_test_renderer())
		testing.expect(t, copied)
		if copied {
			state, state_ok := ui.snapshot_view(&snapshot)
			testing.expect(t, state_ok)
			testing.expect_value(t, len(state.status_regions), 1)
			if len(state.status_regions) == 1 {
				status := state.status_regions[0]
				content, content_ok := ui.snapshot_status_content(state, status)
				testing.expect(t, content_ok)
				testing.expect_value(t, content, "Command rejected")
				testing.expect_value(t, status.style_role, ui.Style_Role.Diagnostic_Normal)
				testing.expect_value(t, status.geometry.row, i32(4))
				testing.expect(t, status.active)
			}
			testing.expect_value(t, state.focus.target, base_surface)
			ui.snapshot_close(&snapshot)
		}
	}
	testing.expect(t, prepared && normal_ok && current_ok && diagnostic_ok && list_ok && surface_ok && node_ok)
}

/* Verifies unavailable popup overlap reuses bounded shared root-edge feedback. */
@(test)
popup_fallback_reuses_status :: proc(t: ^testing.T) {
	commands: Command_Context
	prepared_fallback := popup_fallback_prepare(
		&commands.popup_fallback,
		2_200,
		1,
		"Expected an operand near the current marker",
		.Popup_Unavailable,
	)
	defer popup_fallback_clear(&commands.popup_fallback)
	content_rows, rows_ok := transient_input_content_rows(
		&commands,
		{width_cells = 12, height_rows = 3},
	)
	registry: ui.Registry
	initialized, _ := ui.registry_init(&registry, 104)
	testing.expect(t, initialized)
	if !initialized do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, unavailable_ok, _ := ui.proposal_add_style(&proposal, .Popup_Unavailable, {.Dim})
	items := []ui.List_Item_Definition {{
		id = 1,
		text = "base",
		action = {owner_id = 1, action_id = 1, generation = 1},
	}}
	list, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View, viewport_items = 2},
		},
		items,
	)
	base_surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 2, width = 12},
		},
	)
	base_node, node_ok, _ := ui.proposal_add_surface_node(&proposal, base_surface)
	composed, compose_failure := proposal_compose_command_feedback(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 12, height_rows = 3},
	)
	testing.expectf(t, composed, "popup fallback composition failed: %v", compose_failure)
	root, published, publish_failure := ui.proposal_publish(
		&registry,
		&proposal,
		transient_input_test_renderer(),
	)
	testing.expectf(t, published, "popup fallback publish failed: %v", publish_failure)
	if published {
		snapshot, copied, _ := ui.registry_snapshot(&registry, root, transient_input_test_renderer())
		testing.expect(t, copied)
		if copied {
			state, viewed := ui.snapshot_view(&snapshot)
			testing.expect(t, viewed)
			testing.expect_value(t, len(state.status_regions), 1)
			if len(state.status_regions) == 1 {
				status := state.status_regions[0]
				content, content_ok := ui.snapshot_status_content(state, status)
				testing.expect(t, content_ok)
				testing.expect_value(t, content, "Expected an operand near the current marker")
				testing.expect_value(t, status.style_role, ui.Style_Role.Popup_Unavailable)
				testing.expect_value(t, status.geometry.width, i32(12))
			}
			testing.expect_value(t, state.focus.target, base_surface)
			ui.snapshot_close(&snapshot)
		}
	}
	unsupported := transient_input_test_renderer()
	unsupported.capabilities -= {.Popup_Overlap}
	insufficient := transient_input_test_renderer()
	insufficient.max_rows = 2
	insufficient.max_cells = u64(insufficient.max_rows) * u64(insufficient.max_columns)
	bounds := ui.Popup_Dimension_Bounds {
		minimum_rows = 3,
		minimum_columns = 8,
		preferred_rows = 4,
		preferred_columns = 20,
		maximum_rows = 8,
		maximum_columns = 40,
	}
	testing.expect(t, popup_fallback_required(unsupported, bounds))
	testing.expect(t, popup_fallback_required(insufficient, bounds))
	testing.expect(t, !popup_fallback_required(transient_input_test_renderer(), bounds))
	testing.expect_value(t, content_rows, u32(2))
	testing.expect(
		t,
		prepared_fallback && rows_ok && prepared && normal_ok && current_ok &&
		unavailable_ok && list_ok && surface_ok && node_ok,
	)
}

/* Verifies fallback replacement is atomic and retained content is released exactly once. */
@(test)
popup_fallback_keeps_last_content :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	state: Popup_Fallback_State
	first := popup_fallback_prepare(&state, 3_100, 1, "first", .Popup_Content, allocator)
	first_bytes := tracking.current_memory_allocated
	failing := Transient_Input_Failing_Allocator{backing = allocator}
	rejected := !popup_fallback_prepare(
		&state,
		3_100,
		2,
		"rejected",
		.Popup_Diagnostic,
		transient_input_failing_allocator(&failing),
	)
	retained, retained_role, retained_ok := popup_fallback_view(&state)
	replaced := popup_fallback_prepare(
		&state,
		3_100,
		2,
		"second",
		.Popup_Diagnostic,
		allocator,
	)
	second, second_role, second_ok := popup_fallback_view(&state)
	popup_fallback_clear(&state)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, first && rejected && retained_ok && replaced && second_ok)
	testing.expect_value(t, first_bytes, i64(5))
	testing.expect_value(t, retained, "first")
	testing.expect_value(t, retained_role, ui.Style_Role.Popup_Content)
	testing.expect_value(t, second, "second")
	testing.expect_value(t, second_role, ui.Style_Role.Popup_Diagnostic)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

/* Verifies the complete transient root preserves Unicode, focus, accounting, and cleanup. */
@(test)
input_root_keeps_focus_accounting :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	commands := Command_Context{persistent_allocator = allocator}
	prompt_ok, _ := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 32,
			allocator = allocator,
		},
	)
	testing.expect(t, prompt_ok)
	if !prompt_ok {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	empty, empty_ok := prompt_input_value(&commands)
	testing.expect(t, !empty_ok)
	testing.expect_value(t, empty, "")
	testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, .Save_Path))
	empty, empty_ok = prompt_input_value(&commands)
	testing.expect(t, empty_ok)
	testing.expect_value(t, empty, "")
	_, append_failure := interaction.prompt_text_append(&commands.prompt_workflow.prompt, "λ界🙂")
	testing.expect_value(t, append_failure.code, interaction.Prompt_Failure_Code.None)

	registry: ui.Registry
	initialized, _ := ui.registry_init(
		&registry,
		101,
		ui.DEFAULT_RESOURCE_LIMITS,
		allocator,
	)
	testing.expect(t, initialized)
	if !initialized {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, status_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
	_, rejected_ok, _ := ui.proposal_add_style(&proposal, .Diagnostic_Rejected)
	items := []ui.List_Item_Definition {{id = 1, text = "base", action = {owner_id = 1, action_id = 1, generation = 1}}}
	list, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View, viewport_items = 4},
		},
		items,
	)
	base_surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 40},
		},
	)
	base_node, node_ok, _ := ui.proposal_add_surface_node(&proposal, base_surface)
	composition, composed, compose_failure := proposal_compose_transient_input(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 40, height_rows = 5},
		1,
	)
	testing.expectf(t, composed, "transient root composition failed: %v", compose_failure)
	root, published, publish_failure := ui.proposal_publish(
		&registry,
		&proposal,
		transient_input_test_renderer(),
	)
	testing.expectf(t, published, "transient root publish failed: %v", publish_failure)
	captured, _ := ui.registry_capture_focus(&registry, composition.input_surface)
	snapshot, copied, snapshot_failure := ui.registry_snapshot(
		&registry,
		root,
		transient_input_test_renderer(),
		allocator,
	)
	testing.expectf(t, copied, "transient root snapshot failed: %v", snapshot_failure)
	if copied {
		state, state_ok := ui.snapshot_view(&snapshot)
		input_surface := state.surfaces[composition.input_surface.slot]
		input_view := state.views[input_surface.view.slot]
		value, value_ok := ui.snapshot_input_value(state, input_view)
		status, status_text_ok := ui.snapshot_status_content(state, state.status_regions[0])
		testing.expect(t, state_ok && value_ok && status_text_ok)
		testing.expect_value(t, value, "λ界🙂")
		testing.expect_value(t, input_view.input.cursor_offset, u32(9))
		testing.expect_value(t, status, "Save as: ")
		testing.expect_value(t, state.focus.target, composition.input_surface)
		testing.expect_value(t, state.focus.return_target, base_surface)
		testing.expect_value(t, state.accounting.input_bytes, u32(9))
		testing.expect_value(t, state.accounting.fixed_choices, u16(0))
		ui.snapshot_close(&snapshot)
	}
	return_surface, released, _ := ui.registry_release_focus(&registry)
	closed, _ := ui.registry_close(&registry)
	prompt_closed, _ := interaction.prompt_close(&commands.prompt_workflow.prompt)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, prepared && normal_ok && current_ok && status_ok && rejected_ok &&
		list_ok && surface_ok && node_ok && composed && published && captured && copied &&
		released && closed && prompt_closed)
	testing.expect_value(t, return_surface, base_surface)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

/* Verifies fixed-choice labels contain the exact projected alternatives once. */
@(test)
fixed_choices_project_labels_once :: proc(t: ^testing.T) {
	cases := []struct {
		mode:     Prompt_Mode,
		choices:  u8,
		expected: string,
	} {
		{.Kill_File_Discard_Choice, 2, "Discard changes and kill buffer? [y]es [n]o "},
		{.Kill_Unassociated_Choice, 1, "Modified buffer: [s]ave [d]iscard [c]ancel "},
		{.Marked_Kill_Choice, 1, "Marked buffer: [s]ave [d]iscard [c]ancel "},
		{.Project_Close_Choice, 1, "Project buffer: [s]ave [d]iscard [c]ancel "},
		{.Last_Pane_Exit_Choice, 2, "Last pane. Exit Odra? [y]es [n]o "},
		{.Exit_Choice, 1, "Save changes? [s]ave [d]iscard [c]ancel "},
		{.Dir_Abandonment_Choice, 4, "Add this Dir to Projects? [y]es [n]o [c]ancel [d]on't ask again "},
	}
	for test_case in cases {
		commands := Command_Context{persistent_allocator = context.allocator}
		save_choices := prompt_save_discard_cancel_choices()
		yes_no_choices := prompt_yes_no_choices()
		yes_no_cancel_choices := prompt_yes_no_cancel_choices()
		dir_abandonment_choices := prompt_dir_abandonment_choices()
		choices := save_choices[:]
		if test_case.choices == 2 do choices = yes_no_choices[:]
		if test_case.choices == 3 do choices = yes_no_cancel_choices[:]
		if test_case.choices == 4 do choices = dir_abandonment_choices[:]
		initialized, _ := interaction.prompt_init(
			&commands.prompt_workflow.prompt,
			interaction.Prompt_Config {
				kind = .Fixed_Choice,
				choices = choices,
				allocator = context.allocator,
			},
		)
		testing.expect(t, initialized)
		if !initialized do continue
		testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, test_case.mode))
		label, labeled := prompt_input_status_label(&commands)
		testing.expect(t, labeled)
		testing.expect_value(t, label, test_case.expected)
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
	}
}

/* Verifies geometry bounds and allocation faults reject without publishing partial state. */
@(test)
composition_rejects_bounds_and_alloc :: proc(t: ^testing.T) {
	commands := Command_Context{persistent_allocator = context.allocator}
	initialized, _ := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = 32,
			allocator = context.allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer interaction.prompt_close(&commands.prompt_workflow.prompt)
	testing.expect(t, prompt_workflow_begin_projection(&commands.prompt_workflow, .Save_Path))
	_, _ = interaction.prompt_text_append(&commands.prompt_workflow.prompt, "value")
	_, short_ok := transient_input_content_rows(&commands, {width_cells = 80, height_rows = 1})
	testing.expect(t, !short_ok)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Transient_Input_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(
		&registry,
		102,
		ui.DEFAULT_RESOURCE_LIMITS,
		transient_input_failing_allocator(&failing),
	)
	testing.expect(t, registry_ok)
	if !registry_ok {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current)
	_, status_ok, _ := ui.proposal_add_style(&proposal, .Status_Active)
	_, rejected_ok, _ := ui.proposal_add_style(&proposal, .Diagnostic_Rejected)
	items := []ui.List_Item_Definition {{id = 1, text = "base", action = {owner_id = 1, action_id = 1, generation = 1}}}
	list, list_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {presentation_generation = 1, selection_owner = .View, viewport_items = 4},
		},
		items,
	)
	base_surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = list,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 4, width = 80},
		},
	)
	base_node, node_ok, _ := ui.proposal_add_surface_node(&proposal, base_surface)
	_, narrow_ok, narrow_failure := proposal_compose_transient_input(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 1, height_rows = 5},
		1,
	)
	testing.expect(t, !narrow_ok)
	testing.expect_value(t, narrow_failure.code, ui.Failure_Code.Invalid_Layout)
	failing.fail_after = failing.successful_allocations
	_, allocation_ok, allocation_failure := proposal_compose_transient_input(
		&proposal,
		&commands,
		base_node,
		base_surface,
		{width_cells = 80, height_rows = 5},
		1,
	)
	testing.expect(t, !allocation_ok)
	testing.expect_value(t, allocation_failure.code, ui.Failure_Code.Allocation)
	failing.fail_after = max(u64)
	aborted := ui.proposal_abort(&proposal)
	_, root_ok, _ := ui.registry_handle(&registry)
	closed, _ := ui.registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, prepared && normal_ok && current_ok && status_ok && rejected_ok &&
		list_ok && surface_ok && node_ok && aborted && !root_ok && closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(private)
transient_input_test_renderer :: proc() -> ui.Renderer_Profile {
	return ui.Renderer_Profile {
		id = 1,
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
			.Popup_Overlap,
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}

@(private)
Transient_Input_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
transient_input_failing_allocator :: proc(data: ^Transient_Input_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = transient_input_failing_allocator_proc, data = data}
}

@(private)
transient_input_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Transient_Input_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
