// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../theme"
import "../ui"
import "base:runtime"
import "core:testing"

/* Verifies the application resolves the exact active session definition into each UI root. */
@(test)
theme_selection_drives_ui :: proc(t: ^testing.T) {
	commands: Command_Context
	initialized, _ := theme.theme_registry_init_factory(&commands.theme_registry, 901)
	testing.expect(t, initialized)
	if !initialized do return
	defer theme.theme_registry_close(&commands.theme_registry)

	initial, initial_ok, _ := command_context_theme_definition(&commands)
	selection, selected, _ := theme.theme_registry_selection(&commands.theme_registry)
	profile := session_theme_test_renderer()
	commands.renderer_profile = profile
	transition_ready, transition_failure := command_context_theme_transition_begin(
		&commands,
		.Baseline,
		selection,
	)
	transition_valid, validation_failure := command_context_theme_transition_validate(
		&commands,
		profile,
	)
	baseline, baseline_ok, _ := command_context_theme_definition(&commands)
	before_commit, before_commit_ok, _ := theme.theme_registry_selection(&commands.theme_registry)
	testing.expect(
		t,
		initial_ok && selected && transition_ready && transition_valid && baseline_ok &&
			before_commit_ok,
	)
	testing.expect_value(t, transition_failure.stage, App_Stage.None)
	testing.expect_value(t, validation_failure.stage, App_Stage.None)
	testing.expect_value(
		t,
		theme.theme_name_string(&initial.descriptor.identity),
		theme.WROCLAW_NIGHT_IDENTITY,
	)
	testing.expect_value(t, before_commit.active, selection.active)
	testing.expect_value(t, baseline.descriptor.handle, selection.baseline)
	testing.expect_value(
		t,
		theme.theme_name_string(&baseline.descriptor.identity),
		theme.TERMINAL_DEFAULT_IDENTITY,
	)

	ui_registry: ui.Registry
	ui_initialized, _ := ui.registry_init(&ui_registry, 902)
	testing.expect(t, ui_initialized)
	if !ui_initialized do return
	defer ui.registry_close(&ui_registry)
	proposal, prepared, _ := ui.proposal_begin(&ui_registry)
	testing.expect(t, prepared)
	if !prepared do return
	resolved, resolve_failure := proposal_resolve_session_theme(&proposal, &commands)
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.stage, App_Stage.None)
	items := []ui.List_Item_Definition {{
		id = 1,
		text = "Theme",
		action = {owner_id = 1, action_id = 1, generation = 1},
	}}
	view, view_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {
				presentation_generation = 1,
				selection_owner = .View,
				current_item = 0,
				viewport_items = 1,
			},
		},
		items,
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 1, width = 16},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(&ui_registry, &proposal, profile)
	testing.expect(t, view_ok && surface_ok && node_ok && root_ok && published)
	if !published do return
	commands.ui_root = root
	baseline_selection, baseline_selected, baseline_failure :=
		command_context_theme_transition_commit(&commands)
	testing.expect(t, baseline_selected)
	testing.expect_value(t, baseline_failure.stage, App_Stage.None)
	testing.expect_value(t, baseline_selection.active, selection.baseline)
	snapshot, copied, _ := ui.registry_snapshot(&ui_registry, root, profile)
	testing.expect(t, copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	snapshot_view, viewed := ui.snapshot_view(&snapshot)
	testing.expect(t, viewed)
	testing.expect_value(t, len(snapshot_view.styles), theme.CURRENT_STYLE_ROLE_COUNT)
	for style in snapshot_view.styles {
		testing.expect(t, !style.foreground.present && !style.background.present)
	}
	rollback_ready, rollback_failure := command_context_theme_transition_begin(
		&commands,
		.Restore,
		baseline_selection,
	)
	testing.expect(t, rollback_ready)
	testing.expect_value(t, rollback_failure.stage, App_Stage.None)
	command_context_theme_transition_abort(&commands)
	after_abort, after_abort_ok, _ := theme.theme_registry_selection(&commands.theme_registry)
	testing.expect(t, after_abort_ok)
	testing.expect_value(t, after_abort, baseline_selection)
}

/* Verifies stale transitions reject and an active failed provider restores fallback. */
@(test)
theme_failure_restores_factory :: proc(t: ^testing.T) {
	commands: Command_Context
	initialized, _ := theme.theme_registry_init_factory(&commands.theme_registry, 903)
	testing.expect(t, initialized)
	if !initialized do return
	defer theme.theme_registry_close(&commands.theme_registry)
	commands.renderer_profile = session_theme_test_renderer()
	initial, selected, _ := theme.theme_registry_selection(&commands.theme_registry)
	styles := theme.factory_fallback_styles()
	proposal := theme.Definition_Proposal {
		identity = "application-test",
		display_name = "Application Test",
		provider_name = "application-test-provider",
		provenance = "src/odra/theme_styles_test.odin",
		styles = styles[:],
	}
	proposed, proposed_ok, _ := theme.theme_registry_propose(
		&commands.theme_registry,
		initial.registry_generation,
		proposal,
	)
	proposal_scope, proposal_scope_ok, _ := theme.theme_registry_selection(&commands.theme_registry)
	confirmed, confirmed_ok, _ := theme.theme_registry_confirm(
		&commands.theme_registry,
		proposal_scope.registry_generation,
		proposed,
	)
	confirmation_scope, confirmation_scope_ok, _ := theme.theme_registry_selection(
		&commands.theme_registry,
	)
	active, active_ok, _ := theme.theme_registry_select(
		&commands.theme_registry,
		confirmation_scope,
		confirmed,
	)
	provider := theme.Provider_Handle {
		registry_id = confirmed.registry_id,
		provider_id = confirmed.provider_id,
		provider_generation = confirmed.provider_generation,
	}
	stale_ok, stale_failure := command_context_theme_transition_begin(
		&commands,
		.Fail_Provider,
		initial,
		provider = provider,
	)
	transition_ready, transition_failure := command_context_theme_transition_begin(
		&commands,
		.Fail_Provider,
		active,
		provider = provider,
	)
	pending, pending_ok, _ := command_context_theme_definition(&commands)
	testing.expect(
		t,
		selected && proposed_ok && proposal_scope_ok && confirmed_ok &&
			confirmation_scope_ok && active_ok && !stale_ok && transition_ready && pending_ok,
	)
	testing.expect_value(t, stale_failure.theme.code, theme.Failure_Code.Stale_Selection)
	testing.expect_value(t, transition_failure.stage, App_Stage.None)
	testing.expect_value(t, pending.descriptor.handle, active.fallback)
	command_context_theme_transition_abort(&commands)
	after_abort, after_abort_ok, _ := theme.theme_registry_selection(&commands.theme_registry)
	testing.expect(t, after_abort_ok)
	testing.expect_value(t, after_abort, active)

	restarted, _ := command_context_theme_transition_begin(
		&commands,
		.Fail_Provider,
		after_abort,
		provider = provider,
	)
	fallback, committed, commit_failure := command_context_theme_transition_commit(&commands)
	testing.expect(t, restarted && committed)
	testing.expect_value(t, commit_failure.stage, App_Stage.None)
	testing.expect_value(t, fallback.active, active.fallback)
	testing.expect_value(t, fallback.state, theme.Selection_State.Fallback_After_Failure)
}

/* Verifies every factory definition publishes all roles for every renderer profile. */
@(test)
factory_themes_publish_ui_roots :: proc(t: ^testing.T) {
	commands: Command_Context
	theme_initialized, _ := theme.theme_registry_init_factory(&commands.theme_registry, 904)
	testing.expect(t, theme_initialized)
	if !theme_initialized do return
	defer theme.theme_registry_close(&commands.theme_registry)
	ui_initialized, _ := ui.registry_init(&commands.ui_registry, 905)
	testing.expect(t, ui_initialized)
	if !ui_initialized do return
	defer ui.registry_close(&commands.ui_registry)
	identities := []string {
		theme.WROCLAW_SUNRISE_IDENTITY,
		theme.WROCLAW_MORNING_IDENTITY,
		theme.WROCLAW_SUNSET_IDENTITY,
		theme.WROCLAW_NIGHT_IDENTITY,
		theme.TERMINAL_DEFAULT_IDENTITY,
	}
	model_generation := u64(1)
	for identity in identities {
		definition, found, _ := theme.theme_registry_definition_by_name(
			&commands.theme_registry,
			identity,
		)
		testing.expect(t, found)
		if !found do continue
		selection, selected, _ := theme.theme_registry_selection(&commands.theme_registry)
		selection, selected, _ = theme.theme_registry_select(
			&commands.theme_registry,
			selection,
			definition.descriptor.handle,
		)
		testing.expect(t, selected)
		if !selected do continue
		definition, found, _ = theme.theme_registry_definition(
			&commands.theme_registry,
			selection.active,
		)
		testing.expect(t, found)
		if !found do continue
		for capability_value in int(ui.Renderer_Color_Capability.Monochrome) ..=
		                             int(ui.Renderer_Color_Capability.True_Color) {
			profile := session_theme_test_renderer()
			profile.id = ui.Renderer_Profile_ID(model_generation)
			profile.color = ui.Renderer_Color_Capability(capability_value)
			commands.renderer_profile = profile
			proposal, prepared, _ := ui.proposal_begin(&commands.ui_registry, commands.ui_root)
			testing.expect(t, prepared)
			if !prepared do continue
			resolved, resolve_failure := proposal_resolve_session_theme(&proposal, &commands)
			testing.expect(t, resolved)
			testing.expect_value(t, resolve_failure.stage, App_Stage.None)
			if !resolved {
				ui.proposal_abort(&proposal)
				continue
			}
			items := []ui.List_Item_Definition {{
				id = 1,
				text = identity,
				action = {owner_id = 1, action_id = 1, generation = 1},
			}}
			view, view_ok, _ := ui.proposal_project_list_view(
				&proposal,
				ui.List_Projection_Request {
					model = {owner_id = 1, model_id = 1, generation = ui.Model_Generation(model_generation)},
					position = {
						presentation_generation = model_generation,
						selection_owner = .View,
						current_item = 0,
						viewport_items = 1,
					},
				},
				items,
			)
			surface, surface_ok, _ := ui.proposal_add_surface(
				&proposal,
				ui.Surface_Descriptor {
					owner_id = 1,
					view = view,
					focusable = true,
					visible = true,
					required_profile = profile.id,
					geometry = {height = 1, width = 32},
				},
			)
			node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
			root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
			root, published, _ := ui.proposal_publish(&commands.ui_registry, &proposal, profile)
			testing.expect(t, view_ok && surface_ok && node_ok && root_ok && published)
			if !published do continue
			commands.ui_root = root
			snapshot, copied, _ := ui.registry_snapshot(&commands.ui_registry, root, profile)
			testing.expect(t, copied)
			if !copied do continue
			snapshot_view, viewed := ui.snapshot_view(&snapshot)
			testing.expect(t, viewed)
			testing.expect_value(t, len(snapshot_view.styles), theme.CURRENT_STYLE_ROLE_COUNT)
			testing.expect_value(
				t,
				snapshot_view.accounting.style_bytes,
				u64(theme.CURRENT_STYLE_ROLE_COUNT * size_of(ui.Style_Descriptor)),
			)
			for style, index in snapshot_view.styles {
				expected := definition.styles[index]
				testing.expect_value(t, style.role, expected.role)
				testing.expect_value(t, style.foreground, expected.foreground)
				testing.expect_value(t, style.background, expected.background)
				testing.expect_value(t, style.attributes, expected.attributes)
			}
			ui.snapshot_close(&snapshot)
			model_generation += 1
		}
	}
	_, stale_ok, stale_failure := ui.proposal_begin(&commands.ui_registry, {})
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, ui.Failure_Code.Stale_Root)
	mismatched := commands.renderer_profile
	mismatched.id += 1
	_, compatible, compatibility_failure := ui.registry_snapshot(
		&commands.ui_registry,
		commands.ui_root,
		mismatched,
	)
	testing.expect(t, !compatible)
	testing.expect_value(t, compatibility_failure.code, ui.Failure_Code.Renderer_Incompatible)
	faulted: ui.Registry
	_, allocation_failure := ui.registry_init(
		&faulted,
		906,
		allocator = runtime.Allocator{},
	)
	testing.expect_value(t, allocation_failure.code, ui.Failure_Code.Allocation)
}

@(private)
session_theme_test_renderer :: proc() -> ui.Renderer_Profile {
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
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}
