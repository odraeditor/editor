// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "core:mem"
import "core:testing"

/* test_definition returns one complete role proposal for package tests. */
test_definition :: proc(name_value: string, role: Role, kind := Implementation_Kind.Package) -> Implementation_Definition {
	name, _ := name_copy(name_value)
	source, _ := name_copy("test/package")
	return {
		name = name,
		source = source,
		role = role,
		kind = kind,
		capabilities = factory_capabilities(role),
	}
}

/* Verifies initialization publishes one complete selected factory composition. */
@(test)
registry_initializes_factory_composition :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 71)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	scope, scoped, _ := registry_scope(&registry)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, scoped && inspected && scope.enabled)
	testing.expect_value(t, inspection.implementation_count, u16(3))
	testing.expect_value(t, inspection.stats.factory_implementations, u16(3))
	for selection in scope.selections {
		testing.expect_value(t, selection.selected, selection.factory)
	}
}

/* Verifies role selection and restoration preserve a complete composition. */
@(test)
completion_registry_selects_and_restores_role :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 72)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	provider, registered, _ := registry_register(&registry, test_definition("alternate", .Provider))
	after_register, _, _ := registry_scope(&registry)
	selected, selected_ok, _ := registry_select(&registry, after_register, provider.handle)
	restored, restored_ok, _ := registry_restore(&registry, selected)

	testing.expect(t, registered && selected_ok && restored_ok)
	testing.expect_value(t, selected.selections[0].selected, provider.handle)
	testing.expect_value(t, restored.selections[0].selected, restored.selections[0].factory)
	for index in 1 ..< MAX_COMPLETION_ROLES {
		testing.expect_value(t, selected.selections[index], after_register.selections[index])
	}
}

/* Verifies replacement invalidates stale handles and updates an active selection atomically. */
@(test)
completion_registry_replaces_exact_generation :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 73)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	policy, registered, _ := registry_register(&registry, test_definition("policy", .Policy))
	after_register, _, _ := registry_scope(&registry)
	selected, selected_ok, _ := registry_select(&registry, after_register, policy.handle)
	replacement_definition := policy.definition
	replacement_definition.capabilities += {.Incomplete}
	replacement, replaced_scope, replaced, _ := registry_replace(
		&registry,
		selected,
		policy.handle,
		replacement_definition,
	)
	_, stale_ok, stale_failure := registry_record(&registry, policy.handle)

	testing.expect(t, registered && selected_ok && replaced && !stale_ok)
	testing.expect_value(t, replacement.handle.implementation_generation, Implementation_Generation(2))
	testing.expect_value(t, replaced_scope.selections[1].selected, replacement.handle)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Implementation)
}

/* Verifies duplicates and stale scopes fail without changing the selected composition. */
@(test)
registry_contains_registration_failures :: proc(t: ^testing.T) {
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 74)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)

	definition := test_definition("presentation", .Presentation)
	record, registered, _ := registry_register(&registry, definition)
	_, duplicate_ok, duplicate_failure := registry_register(&registry, definition)
	current, _, _ := registry_scope(&registry)
	stale := current
	stale.registry_generation -= 1
	_, stale_ok, stale_failure := registry_select(&registry, stale, record.handle)
	after, _, _ := registry_scope(&registry)

	testing.expect(t, registered && !duplicate_ok && !stale_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Implementation)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Scope)
	testing.expect_value(t, after, current)
}

/* Verifies checked disable and teardown retain no registry allocation. */
@(test)
registry_disables_and_releases_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Role_Registry
	initialized, _ := registry_init(&registry, 75, DEFAULT_LIMITS, allocator)
	scope, scoped, _ := registry_scope(&registry)
	disabled, disabled_ok, _ := registry_disable(&registry, scope)
	closed, _ := registry_close(&registry)

	testing.expect(t, initialized && scoped && disabled_ok && !disabled.enabled && closed)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
