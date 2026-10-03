// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "../ui"
import "core:testing"

@(private)
UI_Role_Command_Probe :: struct {
	calls:    u16,
	role:     ui.Role,
	provider: ui.Role_Provider_Handle,
	command:  [ui.MAX_ROLE_COMMAND_NAME_BYTES]u8,
	command_bytes: u16,
}

/* Verifies real Racket role inspection, replacement, containment, and cleanup. */
verify_racket_ui_role_capability :: proc(t: ^testing.T, runtime: ^hosting.Runtime) {
	ui_registry: ui.Registry
	registry_ready, _ := ui.registry_init(&ui_registry, 91)
	testing.expect(t, registry_ready)
	if !registry_ready {
		return
	}
	defer ui.registry_close(&ui_registry)
	root, published := publish_ui_role_test_root(&ui_registry)
	testing.expect(t, published)
	if !published {
		return
	}

	roles: ui.Role_Registry
	roles_ready, _ := ui.role_registry_init(&roles, 91, 1)
	testing.expect(t, roles_ready)
	if !roles_ready {
		return
	}
	inspected, inspect_ok, inspect_failure := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		6,
	)
	testing.expectf(t, inspect_ok, "UI role inspection failed: %v", inspect_failure.code)
	testing.expect_value(t, inspected.calls, u16(ui.INITIAL_ROLE_COUNT * 2))
	stats, stats_ok, _ := ui.role_registry_stats(&roles)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.live_providers, u16(ui.INITIAL_ROLE_COUNT))
	closed, _ := ui.role_registry_close(&roles)
	testing.expect(t, closed)

	roles_ready, _ = ui.role_registry_init(&roles, 92, 1)
	testing.expect(t, roles_ready)
	command_probe: UI_Role_Command_Probe
	fixture, fixture_ok, fixture_failure := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		7,
		ui_role_test_command,
		&command_probe,
	)
	testing.expectf(t, fixture_ok, "UI role fixture failed: %v", fixture_failure.code)
	testing.expect_value(t, fixture.role, ui.Role.Startup)
	testing.expect_value(t, fixture.scope.active, fixture.scope.fallback)
	testing.expect_value(t, command_probe.calls, u16(1))
	testing.expect_value(t, command_probe.role, ui.Role.Startup)
	testing.expect_value(t, string(command_probe.command[:command_probe.command_bytes]), "open")
	stats, stats_ok, _ = ui.role_registry_stats(&roles)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.package_providers, u16(0))
	closed, _ = ui.role_registry_close(&roles)
	testing.expect(t, closed)

	roles_ready, _ = ui.role_registry_init(&roles, 93, 1)
	testing.expect(t, roles_ready)
	_, stale_ok, stale_failure := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		8,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, ui.Role_Failure_Code.Stale_Scope)
	stats, _, _ = ui.role_registry_stats(&roles)
	testing.expect_value(t, stats.package_providers, u16(0))
	closed, _ = ui.role_registry_close(&roles)
	testing.expect(t, closed)

	roles_ready, _ = ui.role_registry_init(&roles, 94, 1)
	testing.expect(t, roles_ready)
	_, exception_ok, _ := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		10,
	)
	testing.expect(t, !exception_ok)
	startup, startup_ok, _ := ui.role_registry_scope(&roles, .Startup)
	testing.expect(t, startup_ok)
	testing.expect_value(t, startup.active, startup.fallback)
	stats, _, _ = ui.role_registry_stats(&roles)
	testing.expect_value(t, stats.package_providers, u16(1))
	closed, _ = ui.role_registry_close(&roles)
	testing.expect(t, closed)

	roles_ready, _ = ui.role_registry_init(&roles, 95, 1)
	testing.expect(t, roles_ready)
	_, budget_ok, budget_failure := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		11,
		ui_role_test_command,
		&command_probe,
	)
	testing.expect(t, !budget_ok)
	testing.expect_value(t, budget_failure.code, ui.Role_Failure_Code.Callback_Budget)
	startup, _, _ = ui.role_registry_scope(&roles, .Startup)
	testing.expect_value(t, startup.active, startup.fallback)
	closed, _ = ui.role_registry_close(&roles)
	testing.expect(t, closed)

	roles_ready, _ = ui.role_registry_init(&roles, 95, 2)
	testing.expect(t, roles_ready)
	restarted, restart_ok, restart_failure := racket_ui_role_turn(
		runtime,
		&roles,
		&ui_registry,
		ui_role_test_renderer(),
		6,
	)
	testing.expectf(t, restart_ok, "UI role session restart failed: %v", restart_failure.code)
	testing.expect_value(t, restarted.calls, u16(ui.INITIAL_ROLE_COUNT * 2))
	stats, stats_ok, _ = ui.role_registry_stats(&roles)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.session_generation, ui.Role_Session_Generation(2))
	testing.expect_value(t, stats.package_providers, u16(0))
	closed, _ = ui.role_registry_close(&roles)
	testing.expect(t, closed)
	testing.expect(t, root.generation != ui.Root_Generation(0))
}

@(private)
ui_role_test_command :: proc(
	user_data: rawptr,
	role: ui.Role,
	provider: ui.Role_Provider_Handle,
	command_name: string,
) -> bool {
	probe := (^UI_Role_Command_Probe)(user_data)
	if probe == nil || len(command_name) > len(probe.command) {
		return false
	}
	probe.calls += 1
	probe.role = role
	probe.provider = provider
	probe.command_bytes = u16(copy(probe.command[:], command_name))
	return true
}

@(private)
publish_ui_role_test_root :: proc(registry: ^ui.Registry) -> (root: ui.Root_Handle, ok: bool) {
	proposal, prepared, _ := ui.proposal_begin(registry)
	if !prepared {
		return {}, false
	}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	projection, projection_ok, _ := ui.proposal_add_projection(
		&proposal,
		ui.Model_Reference{owner_id = 1, model_id = 1, generation = 1},
		64,
	)
	view, view_ok, _ := ui.proposal_add_view(
		&proposal,
		ui.Visual_View_Descriptor{kind = .Text_View, projection = projection},
	)
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	published: bool
	root, published, _ = ui.proposal_publish(registry, &proposal, ui_role_test_renderer())
	return root, style_ok && projection_ok && view_ok && surface_ok && node_ok &&
		root_ok && published
}

@(private)
ui_role_test_renderer :: proc() -> ui.Renderer_Profile {
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
