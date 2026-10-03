// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:mem"
import "core:testing"

@(private="file")
presentation_profile_test_definition :: proc(
	name_value: string,
	kind: Presentation_Profile_Kind,
	fallback: Presentation_Profile_Handle,
	required := Renderer_Capabilities{.Cell_Geometry, .Clipping},
) -> Presentation_Profile_Definition {
	name, _ := presentation_profile_text(name_value)
	source, _ := presentation_profile_text("test/package")
	return {
		name = name,
		source = source,
		kind = kind,
		role = .Contextual_Information,
		mappings = {
			0 = {slot = .Background, style_role = .Popup_Background},
			1 = {slot = .Border, style_role = .Popup_Border},
			2 = {slot = .Content, style_role = .Popup_Content},
			3 = {slot = .Unavailable, style_role = .Popup_Unavailable},
			4 = {slot = .Attention, style_role = .Popup_Diagnostic},
		},
		mapping_count = 5,
		margin_columns = 1,
		border = .Single,
		bounds = {
			minimum_rows = 3,
			minimum_columns = 18,
			preferred_rows = 5,
			preferred_columns = 56,
			maximum_rows = 8,
			maximum_columns = 80,
		},
		clipping = .Clip,
		popup_fallback = .Compact_Feedback,
		degradation = .Portable_Border,
		required_capabilities = required,
		fallback = fallback,
		configurable = true,
	}
}

/* Verifies initialization publishes complete maintained factory profiles. */
@(test)
initializes_contextual_factory :: proc(t: ^testing.T) {
	registry: Presentation_Profile_Registry
	initialized, _ := presentation_profile_registry_init(&registry, 71)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer presentation_profile_registry_close(&registry)

	scope, scoped, _ := presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	record, recorded, _ := presentation_profile_registry_record(&registry, scope.factory)
	interactive, interactive_ok, _ := presentation_profile_registry_scope(
		&registry,
		.Interactive_Candidates,
	)
	inspection, inspected, _ := presentation_profile_registry_inspect(&registry)

	testing.expect(t, scoped && recorded && interactive_ok && inspected)
	testing.expect_value(t, scope.selected, scope.factory)
	testing.expect_value(t, interactive.selected, interactive.factory)
	testing.expect_value(t, record.definition.kind, Presentation_Profile_Kind.Factory)
	testing.expect_value(
		t,
		presentation_profile_text_view(&record.definition.name),
		"contextual-information",
	)
	testing.expect_value(t, inspection.profile_count, u16(2))
	testing.expect_value(t, inspection.stats.live_profiles, u16(2))
	testing.expect_value(t, inspection.stats.factory_profiles, u16(2))
	testing.expect(t, inspection.stats.retained_bytes > 0)
}

/* Verifies copied registration, compatible selection, fallback, and restoration. */
@(test)
selects_and_restores_profiles :: proc(t: ^testing.T) {
	registry: Presentation_Profile_Registry
	initialized, _ := presentation_profile_registry_init(&registry, 72)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer presentation_profile_registry_close(&registry)

	initial, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	definition := presentation_profile_test_definition("compact", .Package, initial.factory)
	registered, added, _ := presentation_profile_registry_register(&registry, definition)
	definition.mappings[2].style_role = .Popup_Diagnostic
	after_registration, _, _ := presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	selected, selected_ok, _ := presentation_profile_registry_select(
		&registry,
		after_registration,
		registered.handle,
		test_renderer(),
	)
	stored, stored_ok, _ := presentation_profile_registry_record(&registry, registered.handle)
	restored, restored_ok, _ := presentation_profile_registry_restore(
		&registry,
		selected.scope,
		test_renderer(),
	)

	testing.expect(t, added && selected_ok && stored_ok && restored_ok)
	testing.expect_value(t, selected.selected, registered.handle)
	testing.expect(t, selected.changed && !selected.fallback_selected)
	testing.expect_value(t, stored.definition.mappings[2].style_role, Style_Role.Popup_Content)
	testing.expect_value(t, restored.selected, initial.factory)

	incompatible := presentation_profile_test_definition(
		"overlap",
		.Package,
		initial.factory,
		{.Cell_Geometry, .Clipping, .Popup_Overlap},
	)
	overlap, overlap_added, _ := presentation_profile_registry_register(&registry, incompatible)
	current, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	fallback, fallback_ok, _ := presentation_profile_registry_select(
		&registry,
		current,
		overlap.handle,
		test_renderer(),
	)
	testing.expect(t, overlap_added && fallback_ok && fallback.fallback_selected)
	testing.expect_value(t, fallback.selected, initial.factory)
	testing.expect_value(t, fallback.fallback_depth, u8(1))
}

/* Verifies replacement is atomic, follows factory roots, and rejects stale input. */
@(test)
replaces_exact_generations :: proc(t: ^testing.T) {
	registry: Presentation_Profile_Registry
	initialized, _ := presentation_profile_registry_init(&registry, 73)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer presentation_profile_registry_close(&registry)

	initial, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	package_definition := presentation_profile_test_definition("package", .Package, initial.factory)
	package_record, registered, _ := presentation_profile_registry_register(
		&registry,
		package_definition,
	)
	registered_scope, _, _ := presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	selected, selected_ok, _ := presentation_profile_registry_select(
		&registry,
		registered_scope,
		package_record.handle,
		test_renderer(),
	)
	replacement_definition := package_record.definition
	replacement_definition.padding_columns = 1
	replacement, replacement_scope, replaced, _ := presentation_profile_registry_replace(
		&registry,
		selected.scope,
		package_record.handle,
		replacement_definition,
	)
	_, stale_ok, stale_failure := presentation_profile_registry_record(
		&registry,
		package_record.handle,
	)

	testing.expect(t, registered && selected_ok && replaced && !stale_ok)
	testing.expect_value(t, replacement.handle.profile_id, package_record.handle.profile_id)
	testing.expect_value(
		t,
		replacement.handle.profile_generation,
		package_record.handle.profile_generation + 1,
	)
	testing.expect_value(t, replacement_scope.selected, replacement.handle)
	testing.expect_value(t, stale_failure.code, Presentation_Profile_Failure_Code.Stale_Profile)

	invalid := replacement.definition
	invalid.mapping_count = 1
	before_failure := replacement_scope
	_, _, invalid_ok, invalid_failure := presentation_profile_registry_replace(
		&registry,
		before_failure,
		replacement.handle,
		invalid,
	)
	after_failure, _, _ := presentation_profile_registry_scope(
		&registry,
		.Contextual_Information,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(
		t,
		invalid_failure.code,
		Presentation_Profile_Failure_Code.Missing_Required_Slot,
	)
	testing.expect_value(t, after_failure, before_failure)
}

/* Verifies fallback cycles, protected disable, teardown, and rejection inspection. */
@(test)
contains_fallback_and_teardown_failures :: proc(t: ^testing.T) {
	registry: Presentation_Profile_Registry
	initialized, _ := presentation_profile_registry_init(&registry, 74)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer presentation_profile_registry_close(&registry)

	initial, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	first_definition := presentation_profile_test_definition("first", .Package, initial.factory)
	first, first_ok, _ := presentation_profile_registry_register(&registry, first_definition)
	second_definition := presentation_profile_test_definition("second", .Personal, first.handle)
	second, second_ok, _ := presentation_profile_registry_register(&registry, second_definition)
	current, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	cycle := first.definition
	cycle.fallback = second.handle
	_, _, cycle_ok, cycle_failure := presentation_profile_registry_replace(
		&registry,
		current,
		first.handle,
		cycle,
	)
	after_cycle, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	disabled, disable_failure := presentation_profile_registry_disable(&registry, after_cycle)
	inspection, inspected, _ := presentation_profile_registry_inspect(&registry)

	testing.expect(t, first_ok && second_ok && !cycle_ok && !disabled && inspected)
	testing.expect_value(t, cycle_failure.code, Presentation_Profile_Failure_Code.Fallback_Cycle)
	testing.expect_value(t, disable_failure.code, Presentation_Profile_Failure_Code.Protected_Role)
	testing.expect_value(
		t,
		inspection.last_rejection.code,
		Presentation_Profile_Failure_Code.Protected_Role,
	)

	_, dependent_ok, dependent_failure := presentation_profile_registry_teardown(
		&registry,
		after_cycle,
		first.handle,
	)
	testing.expect(t, !dependent_ok)
	testing.expect_value(
		t,
		dependent_failure.code,
		Presentation_Profile_Failure_Code.Invalid_Fallback,
	)
	unchanged, _, _ := presentation_profile_registry_scope(&registry, .Contextual_Information)
	second_scope, second_removed, _ := presentation_profile_registry_teardown(
		&registry,
		unchanged,
		second.handle,
	)
	_, first_removed, _ := presentation_profile_registry_teardown(
		&registry,
		second_scope,
		first.handle,
	)
	testing.expect(t, second_removed && first_removed)
}

/* Verifies the registry allocates once and releases retained storage exactly once. */
@(test)
releases_storage_exactly_once :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	registry: Presentation_Profile_Registry
	initialized, _ := presentation_profile_registry_init(
		&registry,
		75,
		DEFAULT_PRESENTATION_PROFILE_LIMITS,
		allocator,
	)
	retained := tracking.current_memory_allocated
	closed, _ := presentation_profile_registry_close(&registry)
	remaining := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	testing.expect(t, initialized && retained > 0 && closed)
	testing.expect_value(t, remaining, i64(0))
	closed_again, _ := presentation_profile_registry_close(&registry)
	testing.expect(t, !closed_again)
}
