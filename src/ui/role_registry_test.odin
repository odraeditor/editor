// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

/* Verifies all accepted roles start on confirmed built-in fallbacks. */
@(test)
initializes_confirmed_builtin_fallbacks :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := role_registry_init(&registry, 41, 3)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer role_registry_close(&registry)

	for role_value in 1..=INITIAL_ROLE_COUNT {
		role := Role(role_value)
		scope, scoped, _ := role_registry_scope(&registry, role)
		provider, inspected, _ := role_registry_provider(&registry, scope.active)
		testing.expect(t, scoped && inspected)
		testing.expect_value(t, scope.active, scope.fallback)
		testing.expect_value(t, provider.kind, Role_Provider_Kind.Built_In)
		testing.expect_value(t, provider.state, Role_Provider_State.Confirmed)
		testing.expect(t, len(provider.name) > 0)
		testing.expect_value(t, provider.package_name, "odra")
	}
	stats, inspected, _ := role_registry_stats(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, stats.live_providers, u16(INITIAL_ROLE_COUNT))
	testing.expect_value(t, stats.package_providers, u16(0))
}

/* Verifies package registration is copied and cannot displace the fallback. */
@(test)
registers_inactive_package_provider :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := role_registry_init(&registry, 42, 7)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer role_registry_close(&registry)

	before, _, _ := role_registry_scope(&registry, .Startup)
	handle, registered, _ := role_registry_register_package(
		&registry,
		.Startup,
		"compact startup",
		"example/ui",
		{.Cell_Geometry, .Clipping, .Unicode_Profile},
	)
	provider, inspected, _ := role_registry_provider(&registry, handle)
	after, _, _ := role_registry_scope(&registry, .Startup)

	testing.expect(t, registered && inspected)
	testing.expect_value(t, provider.kind, Role_Provider_Kind.Package)
	testing.expect_value(t, provider.state, Role_Provider_State.Registered)
	testing.expect_value(t, provider.name, "compact startup")
	testing.expect_value(t, provider.package_name, "example/ui")
	testing.expect_value(t, before.active, after.active)
	testing.expect_value(t, after.active, after.fallback)
	testing.expect(t, after.registry_generation > before.registry_generation)

	_, duplicate, duplicate_failure := role_registry_register_package(
		&registry,
		.Startup,
		"compact startup",
		"example/ui",
		{},
	)
	testing.expect(t, !duplicate)
	testing.expect_value(t, duplicate_failure.code, Role_Failure_Code.Duplicate_Provider)
}

/* Verifies wrong-session and oversized providers reject without state changes. */
@(test)
rejects_invalid_provider_identity_and_text :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := role_registry_init(&registry, 43, 1)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer role_registry_close(&registry)

	scope, _, _ := role_registry_scope(&registry, .Buffer_Menu)
	wrong := scope.active
	wrong.session_generation += 1
	_, inspected, stale_failure := role_registry_provider(&registry, wrong)
	testing.expect(t, !inspected)
	testing.expect_value(t, stale_failure.code, Role_Failure_Code.Invalid_Session)

	oversized := make([]u8, MAX_ROLE_PROVIDER_NAME_BYTES + 1, context.temp_allocator)
	defer delete(oversized, context.temp_allocator)
	_, registered, limit_failure := role_registry_register_package(
		&registry,
		.Buffer_Menu,
		string(oversized),
		"example/ui",
		{},
	)
	testing.expect(t, !registered)
	testing.expect_value(t, limit_failure.code, Role_Failure_Code.Provider_Name_Limit)
	testing.expect_value(t, limit_failure.limit, u64(MAX_ROLE_PROVIDER_NAME_BYTES))
}

/* Verifies session teardown releases all role registry storage exactly once. */
@(test)
role_registry_teardown_releases_all_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	registry: Role_Registry
	initialized, _ := role_registry_init(&registry, 44, 1, allocator)
	_, registered, _ := role_registry_register_package(
		&registry,
		.Status,
		"minimal status",
		"example/ui",
		{.Cell_Geometry},
	)
	closed, _ := role_registry_close(&registry)
	retained := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, initialized && registered && closed)
	testing.expect_value(t, retained, i64(0))
	closed_again, _ := role_registry_close(&registry)
	testing.expect(t, !closed_again)
}

/* Verifies package confirmation, activation, rollback, and teardown stay atomic. */
@(test)
package_activation_preserves_confirmed_fallback :: proc(t: ^testing.T) {
	ui_registry: Registry
	ui_ready, _ := registry_init(&ui_registry, 51)
	root, published := publish_single_text_root(&ui_registry, {})
	testing.expect(t, ui_ready && published)
	if !ui_ready || !published {
		return
	}
	defer registry_close(&ui_registry)

	roles: Role_Registry
	roles_ready, _ := role_registry_init(&roles, 51, 1)
	testing.expect(t, roles_ready)
	if !roles_ready {
		return
	}
	defer role_registry_close(&roles)

	registered, added, _ := role_registry_register_package(
		&roles,
		.Startup,
		"compact startup",
		"example/ui",
		{.Cell_Geometry, .Clipping, .Unicode_Profile, .Atomic_Generation},
	)
	initial, _, _ := role_registry_scope(&roles, .Startup)
	confirmed, confirmed_ok, _ := role_registry_confirm_package(
		&roles,
		&ui_registry,
		Role_Provider_Proposal {
			expected_scope = initial,
			provider = registered,
			expected_root = root,
			renderer = test_renderer(),
			proposal_bytes = 128,
			callback_budget = 32,
			command_name = "open",
		},
	)
	after_confirmation, _, _ := role_registry_scope(&roles, .Startup)
	provider, inspected, _ := role_registry_provider(&roles, confirmed)
	testing.expect_value(t, provider.state, Role_Provider_State.Confirmed)
	testing.expect_value(t, provider.confirmed_root, root.generation)
	testing.expect_value(t, provider.proposal_bytes, u64(128))
	testing.expect_value(t, provider.callback_budget, u16(32))
	testing.expect_value(t, provider.command_name, "open")
	activated, active_ok, _ := role_registry_activate_package(
		&roles,
		&ui_registry,
		after_confirmation,
		confirmed,
		test_renderer(),
	)
	rolled_back, rollback_ok, _ := role_registry_rollback(&roles, activated.scope)
	closed, teardown_ok, _ := role_registry_teardown_package(
		&roles,
		rolled_back.scope,
		confirmed,
	)

	testing.expect(
		t,
		added && confirmed_ok && inspected && active_ok && rollback_ok && teardown_ok,
	)
	testing.expect_value(t, initial.active, initial.fallback)
	testing.expect_value(t, after_confirmation.active, initial.active)
	testing.expect_value(t, activated.provider, confirmed)
	testing.expect(t, activated.changed)
	testing.expect_value(t, rolled_back.provider, initial.fallback)
	testing.expect(t, rolled_back.fallback_selected)
	testing.expect_value(t, closed.scope.active, initial.fallback)
}

/* Verifies invalid package effects and budgets preserve the active provider. */
@(test)
rejects_bad_package_proposal_before_activation :: proc(t: ^testing.T) {
	ui_registry: Registry
	ui_ready, _ := registry_init(&ui_registry, 52)
	root, published := publish_single_text_root(&ui_registry, {})
	testing.expect(t, ui_ready && published)
	if !ui_ready || !published {
		return
	}
	defer registry_close(&ui_registry)

	roles: Role_Registry
	roles_ready, _ := role_registry_init(&roles, 52, 1)
	testing.expect(t, roles_ready)
	if !roles_ready {
		return
	}
	defer role_registry_close(&roles)

	registered, added, _ := role_registry_register_package(
		&roles,
		.Status,
		"package status",
		"example/ui",
		{.Cell_Geometry},
	)
	initial, _, _ := role_registry_scope(&roles, .Status)
	proposal := Role_Provider_Proposal {
		expected_scope = initial,
		provider = registered,
		expected_root = root,
		renderer = test_renderer(),
		proposal_bytes = 64,
		callback_budget = 8,
		changes_focus = true,
		command_name = "refresh",
	}
	_, replaced, focus_failure := role_registry_confirm_package(
		&roles,
		&ui_registry,
		proposal,
	)
	proposal.changes_focus = false
	proposal.changes_layout = true
	_, replaced_layout, layout_failure := role_registry_confirm_package(
		&roles,
		&ui_registry,
		proposal,
	)
	proposal.changes_layout = false
	proposal.callback_budget = 0
	_, replaced_budget, budget_failure := role_registry_confirm_package(
		&roles,
		&ui_registry,
		proposal,
	)
	after, _, _ := role_registry_scope(&roles, .Status)
	provider, inspected, _ := role_registry_provider(&roles, registered)

	testing.expect(t, added && !replaced && !replaced_layout && !replaced_budget && inspected)
	testing.expect_value(t, focus_failure.code, Role_Failure_Code.Focus_Effect)
	testing.expect_value(t, layout_failure.code, Role_Failure_Code.Layout_Effect)
	testing.expect_value(t, budget_failure.code, Role_Failure_Code.Callback_Budget)
	testing.expect_value(t, after, initial)
	testing.expect_value(t, provider.state, Role_Provider_State.Registered)
}
