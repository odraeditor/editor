// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"
import "core:mem"
import "core:path/filepath"
import "core:testing"

@(private)
FIXTURE_LANGUAGES := [1]string{"fixture"}

@(private)
FIXTURE_ARGUMENTS := [1]string{"tests/fixtures/language-service-server.rkt"}

@(private)
FIXTURE_ROOT_MARKERS := [1]string{"fixture.json"}

@(private)
fixture_definition :: proc() -> Definition_Proposal {
	return Definition_Proposal{
		kind = .Programmable,
		name = "fixture-language-server",
		executable = "racket",
		arguments = FIXTURE_ARGUMENTS[:],
		root_policy = .Project_Membership,
		root_markers = FIXTURE_ROOT_MARKERS[:],
		languages = FIXTURE_LANGUAGES[:],
		initialization_options = `{}`,
		client_settings = `{}`,
		feature_policy = {},
		requested_capabilities = {
			.Initialize,
			.Shutdown,
			.Full_Synchronization,
			.Incremental_Synchronization,
			.Save_Notification,
		},
		preferred_encoding = .UTF_16,
		preferred_sync = .Incremental,
		limits = DEFAULT_LIMITS,
		deadlines = DEFAULT_DEADLINES,
		restart = DEFAULT_RESTART_POLICY,
	}
}

/* Verifies the maintained OLS definition is factory data selected through the generic registry. */
@(test)
factory_ols_uses_the_generic_registry_path :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, failure := provider_registry_init(
		&registry,
		Registry_Handle{id = Registry_ID(11), generation = Registry_Generation(13)},
	)
	testing.expectf(t, initialized, "registry init failed: %v", failure.code)
	if !initialized do return
	defer provider_registry_close(&registry)

	factory, registered, registration_failure := provider_registry_register_factory_ols(&registry)
	testing.expectf(t, registered, "factory registration failed: %v", registration_failure.code)
	view, viewed, view_failure := provider_registry_definition(&registry, factory)
	testing.expectf(t, viewed, "factory view failed: %v", view_failure.code)
	if viewed {
		testing.expect_value(t, view.provider.kind, Provider_Kind.Factory)
		testing.expect_value(t, view.provider.state, Provider_State.Selected)
		testing.expect_value(t, view.name, "ols")
		testing.expect_value(t, view.executable, "ols")
		testing.expect_value(t, view.root_policy, Root_Policy.Project_Membership)
		testing.expect_value(t, len(view.languages), 1)
		testing.expect_value(t, view.languages[0], "odin")
		testing.expect(t, .Completion in view.definition.requested_capabilities)
		testing.expect(t, .Diagnostics in view.feature_policy)
	}
	inspection, inspected := provider_registry_inspect(&registry)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.factory, factory)
	testing.expect_value(t, inspection.active, factory)
	testing.expect_value(t, inspection.usage.service_definitions, u32(1))
	resolved, discovered, discovery_failure := provider_registry_discover_executable(
		&registry,
		factory,
		Executable_Discovery{explicit_path = "/usr/sbin/ols"},
	)
	testing.expectf(t, discovered, "explicit factory discovery failed: %v", discovery_failure.code)
	if discovered {
		expected, expected_error := filepath.abs("/usr/sbin/ols", context.allocator)
		testing.expect(t, expected_error == nil)
		if expected_error == nil {
			testing.expect_value(t, resolved, expected)
			delete(expected)
		}
		delete(resolved)
	}
	registration, language_ready := language.factory_bundle_registration(
		language.FACTORY_ODIN_BUNDLE_IDENTITY,
	)
	testing.expect(t, language_ready)
	catalog: Service_Catalog
	catalog_ready, _ := service_catalog_init(
		&catalog,
		23,
		Registry_Handle{id = Registry_ID(11), generation = Registry_Generation(13)},
	)
	testing.expect(t, catalog_ready)
	if catalog_ready {
		defer service_catalog_close(&catalog)
		catalog_confirmed, catalog_failure := factory_ols_catalog_confirm(
			&catalog,
			factory,
			registration.language,
		)
		testing.expectf(t, catalog_confirmed, "factory catalog failed: %v", catalog_failure.code)
		trace, resolved_by_catalog, resolution_failure := service_catalog_resolve(
			&catalog,
			{
				language = registration.language,
				project_membership = "/work/project",
				resolved_root = "/work/project",
				project_trusted = true,
			},
		)
		testing.expectf(t, resolved_by_catalog, "factory resolution failed: %v", resolution_failure.code)
		testing.expect_value(t, trace.selected, factory)
	}
}

/* Verifies a non-Odin data definition replaces factory OLS without core specialization. */
@(test)
fixture_replaces_factory_atomically :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(
		&registry,
		Registry_Handle{id = Registry_ID(17), generation = Registry_Generation(19)},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)
	factory, registered, _ := provider_registry_register_factory_ols(&registry)
	testing.expect(t, registered)

	fixture, replaced, failure := provider_registry_replace(
		&registry,
		factory,
		fixture_definition(),
		Executable_Discovery{search_path = "/usr/sbin"},
	)
	testing.expectf(t, replaced, "fixture replacement failed: %v", failure.code)
	view, viewed, _ := provider_registry_definition(&registry, fixture)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, view.provider.kind, Provider_Kind.Programmable)
		testing.expect_value(t, view.provider.state, Provider_State.Selected)
		testing.expect_value(t, view.languages[0], "fixture")
		testing.expect_value(t, view.root_markers[0], "fixture.json")
		expected, expected_error := filepath.abs("/usr/sbin/racket", context.allocator)
		testing.expect(t, expected_error == nil)
		if expected_error == nil {
			testing.expect_value(t, view.resolved_executable, expected)
			delete(expected)
		}
	}
	factory_view, factory_viewed, _ := provider_registry_definition(&registry, factory)
	testing.expect(t, factory_viewed)
	if factory_viewed do testing.expect_value(t, factory_view.provider.state, Provider_State.Confirmed)
}

/* Verifies discovery failure and stale replacement leave the prior selection unchanged. */
@(test)
failed_replacement_preserves_selection :: proc(t: ^testing.T) {
	registry: Provider_Registry
	initialized, _ := provider_registry_init(
		&registry,
		Registry_Handle{id = Registry_ID(23), generation = Registry_Generation(29)},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)
	factory, registered, _ := provider_registry_register_factory_ols(&registry)
	testing.expect(t, registered)
	before, _ := provider_registry_inspect(&registry)

	missing := fixture_definition()
	missing.executable = "not-present-language-server"
	_, replaced, failure := provider_registry_replace(
		&registry,
		factory,
		missing,
		Executable_Discovery{search_path = "/usr/sbin"},
	)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Executable_Not_Found)
	after, _ := provider_registry_inspect(&registry)
	testing.expect_value(t, after.active, factory)
	testing.expect_value(t, after.selection_generation, before.selection_generation)
	testing.expect_value(t, after.usage.service_definitions, before.usage.service_definitions)
	for _ in 0 ..< int(DEFAULT_LIMITS.service_definitions) + 1 {
		_, loop_replaced, _ := provider_registry_replace(
			&registry,
			factory,
			missing,
			Executable_Discovery{search_path = "/usr/sbin"},
		)
		testing.expect(t, !loop_replaced)
	}
	state := provider_registry_state(&registry)
	testing.expect(t, len(state.definitions) <= int(DEFAULT_LIMITS.service_definitions))

	_, stale_replaced, stale_failure := provider_registry_replace(
		&registry,
		Definition_Handle{},
		fixture_definition(),
		Executable_Discovery{search_path = "/usr/sbin"},
	)
	testing.expect(t, !stale_replaced)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
}

/* Verifies disable, factory restoration, and registry close release exact owned storage. */
@(test)
restores_factory_and_cleans_all_allocations :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Provider_Registry
	initialized, failure := provider_registry_init(
		&registry,
		Registry_Handle{id = Registry_ID(31), generation = Registry_Generation(37)},
		DEFAULT_LIMITS,
		allocator,
	)
	testing.expectf(t, initialized, "registry init failed: %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	factory, registered, _ := provider_registry_register_factory_ols(&registry)
	testing.expect(t, registered)
	view, viewed, _ := provider_registry_definition(&registry, factory)
	testing.expect(t, viewed)
	if viewed {
		disabled, disable_failure := provider_registry_disable(&registry, view.provider.handle)
		testing.expectf(t, disabled, "disable failed: %v", disable_failure.code)
	}
	restored, restore_failure := provider_registry_restore_factory(&registry)
	testing.expectf(t, restored, "restore failed: %v", restore_failure.code)
	inspection, _ := provider_registry_inspect(&registry)
	testing.expect_value(t, inspection.active, factory)
	provider_registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
