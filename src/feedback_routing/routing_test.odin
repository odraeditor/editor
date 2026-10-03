// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_routing

import "../feedback"
import "../ui"
import "core:strings"
import "core:testing"

/* Verifies the maintained policy is complete, ordered, protected, and inspectable. */
@(test)
factory_feedback_routing_is_valid :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	inspection, inspected, failure := registry_inspect(&registry)
	testing.expectf(t, inspected, "inspection failed with %v", failure.code)
	if inspected {
		testing.expect_value(t, inspection.stats.routes, u8(9))
		testing.expect_value(t, inspection.stats.destinations, u8(4))
		testing.expect_value(t, inspection.stats.projections, u8(4))
		testing.expect_value(t, inspection.configuration.routes[0].layer, Policy_Layer.Safety)
		testing.expect(t, inspection.configuration.routes[0].protected)
	}
	test_routing_registry_close(t, &registry)
}

/* Verifies ordinary progress resolves to compact root-edge status content. */
@(test)
progress_routes_to_compact_status :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	record := test_progress_record(1, 1, .Running)
	routed, ok, failure := registry_route_and_project(&registry, record, test_full_frontend())
	testing.expectf(t, ok, "routing failed with %v", failure.code)
	if ok {
		testing.expect_value(t, routed.projection_count, u8(1))
		projection := &routed.projections[0]
		testing.expect_value(t, projection.destination, FACTORY_STATUS_DESTINATION)
		testing.expect_value(t, projection.focus, Focus_Policy.None)
		testing.expect_value(t, projection.style_role, ui.Style_Role.Status_Active)
		testing.expect_value(t, projection_content(projection), "Build (2/4 compile)")
	}
	test_routing_registry_close(t, &registry)
}

/* Verifies warning notifications use focus-preserving floating presentation. */
@(test)
warnings_route_to_focus_preserving_notifications :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	record := test_notification_record(2, 1, .Warning, .Ordinary, .None)
	routed, ok, failure := registry_route_and_project(&registry, record, test_full_frontend())
	testing.expectf(t, ok, "routing failed with %v", failure.code)
	if ok {
		projection := &routed.projections[0]
		testing.expect_value(t, projection.destination, FACTORY_FLOATING_DESTINATION)
		testing.expect_value(t, projection.focus, Focus_Policy.Preserve)
		testing.expect_value(t, projection.style_role, ui.Style_Role.Diagnostic_Warning)
	}
	test_routing_registry_close(t, &registry)
}

/* Verifies frontend loss and compact geometry select one deduplicated status fallback. */
@(test)
unsupported_destinations_degrade_to_status :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	record := test_notification_record(3, 1, .Error, .Required, .History)
	frontend := test_full_frontend()
	frontend.capabilities = {.Cell_Geometry, .Clipping}
	frontend.overlap_available = false
	frontend.surface_available = false
	frontend.diagnostic_available = false
	frontend.rows = 2
	frontend.columns = 20
	routed, ok, failure := registry_route_and_project(&registry, record, frontend)
	testing.expectf(t, ok, "fallback routing failed with %v", failure.code)
	if ok {
		testing.expect_value(t, routed.projection_count, u8(1))
		testing.expect_value(t, routed.projections[0].destination, FACTORY_STATUS_DESTINATION)
		testing.expect(t, routed.projections[0].degraded)
		testing.expect_value(t, routed.projections[0].style_role, ui.Style_Role.Status_Alert)
	}
	test_routing_registry_close(t, &registry)
}

/* Verifies retained failures can project to diagnostic, history, and notification destinations. */
@(test)
retained_failures_have_complete_inspectable_routing :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	record := test_notification_record(4, 1, .Error, .Required, .History)
	routed, ok, failure := registry_route_and_project(&registry, record, test_full_frontend())
	testing.expectf(t, ok, "routing failed with %v", failure.code)
	if ok {
		testing.expect_value(t, routed.projection_count, u8(3))
		testing.expect(t, test_has_destination(routed, FACTORY_DIAGNOSTIC_DESTINATION))
		testing.expect(t, test_has_destination(routed, FACTORY_HISTORY_DESTINATION))
		testing.expect(t, test_has_destination(routed, FACTORY_FLOATING_DESTINATION))
	}
	test_routing_registry_close(t, &registry)
}

/* Verifies a user suppression route cannot hide attention-level feedback. */
@(test)
protected_feedback_survives_visible_suppression :: proc(t: ^testing.T) {
	configuration := factory_configuration(1, test_profile())
	configuration.routes[8].resolution = .Continue
	name, _ := text_copy("suppress-information")
	configuration.routes[9] = {
		id = 10, generation = 1, name = name, layer = .User, order = 0, enabled = true,
		matcher = {match_class = true, class = .Information},
		resolution = .Suppress_Visible,
	}
	configuration.route_count = 10
	registry: Registry
	ready, failure := registry_init(&registry, 2, configuration)
	testing.expectf(t, ready, "registry init failed with %v", failure.code)
	if !ready do return
	ordinary := test_notification_record(5, 1, .Information, .Ordinary, .None)
	resolution, resolved, _ := registry_resolve(&registry, ordinary, test_full_frontend())
	testing.expect(t, resolved)
	testing.expect(t, resolution.suppressed)
	testing.expect_value(t, resolution.destination_count, u8(0))
	attention := test_notification_record(6, 1, .Information, .Required, .None)
	resolution, resolved, _ = registry_resolve(&registry, attention, test_full_frontend())
	testing.expect(t, resolved)
	testing.expect(t, !resolution.suppressed)
	testing.expect(t, resolution.destination_count > 0)
	test_routing_registry_close(t, &registry)
}

/* Verifies rejected reload keeps the exact previous route generation active. */
@(test)
invalid_reload_preserves_last_valid_configuration :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	invalid := factory_configuration(2, test_profile())
	invalid.destinations[0].fallback = FACTORY_FLOATING_DESTINATION
	reloaded, failure := registry_reload(&registry, 1, invalid)
	testing.expect(t, !reloaded)
	testing.expect_value(t, failure.code, Failure_Code.Fallback_Cycle)
	inspection, inspected, _ := registry_inspect(&registry)
	testing.expect(t, inspected)
	if inspected {
		testing.expect_value(t, inspection.stats.configuration, Configuration_Generation(1))
		testing.expect_value(t, inspection.last_rejection.code, Failure_Code.Fallback_Cycle)
	}
	record := test_progress_record(7, 1, .Running)
	_, resolved, _ := registry_resolve(&registry, record, test_full_frontend())
	testing.expect(t, resolved)
	test_routing_registry_close(t, &registry)
}

/* Verifies projection truncation remains textual and deterministic in monochrome. */
@(test)
projection_truncates_without_losing_textual_severity :: proc(t: ^testing.T) {
	configuration := factory_configuration(1, test_profile())
	destination := configuration.destinations[1]
	destination.content_bytes = 32
	definition := configuration.projections[1]
	record := test_notification_record(8, 1, .Error, .Ordinary, .None)
	record.message = strings.repeat("detail ", 20)
	defer delete_string(record.message)
	frontend := test_full_frontend()
	frontend.color = .Monochrome
	projection, projected, failure := project_record(record, destination, definition, frontend)
	testing.expectf(t, projected, "projection failed with %v", failure.code)
	if projected {
		content := projection_content(&projection)
		testing.expect(t, strings.has_prefix(content, "[error] "))
		testing.expect(t, strings.has_suffix(content, "..."))
		testing.expect_value(t, len(content), 32)
	}
}

/* Verifies visible generations replace atomically and stale replay is rejected. */
@(test)
presentation_cache_replaces_and_dismisses_exact_items :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	first_record := test_notification_record(9, 1, .Warning, .Ordinary, .None)
	first, routed, _ := registry_route_and_project(&registry, first_record, test_full_frontend())
	testing.expect(t, routed)
	cache: Presentation_Cache
	applied, failure := presentation_apply(&cache, first)
	testing.expectf(t, applied, "first apply failed with %v", failure.code)
	second_record := test_notification_record(9, 2, .Warning, .Ordinary, .None)
	second_record.title = "Updated"
	second, second_routed, _ := registry_route_and_project(&registry, second_record, test_full_frontend())
	testing.expect(t, second_routed)
	applied, failure = presentation_apply(&cache, second)
	testing.expectf(t, applied, "replacement failed with %v", failure.code)
	testing.expect_value(t, cache.item_count, u8(1))
	testing.expect_value(t, cache.items[0].record_generation, feedback.Record_Generation(2))
	applied, failure = presentation_apply(&cache, first)
	testing.expect(t, !applied)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	dismissed, dismiss_failure := presentation_dismiss(&cache, 9, FACTORY_FLOATING_DESTINATION, .Explicit)
	testing.expectf(t, dismissed, "dismiss failed with %v", dismiss_failure.code)
	testing.expect_value(t, cache.item_count, u8(0))
	test_routing_registry_close(t, &registry)
}

/* Verifies destination capacity, priority, and frontend-loss cleanup stay bounded. */
@(test)
presentation_capacity_and_frontend_loss_are_deterministic :: proc(t: ^testing.T) {
	registry, ready := test_routing_registry(t)
	if !ready do return
	cache: Presentation_Cache
	for offset in 0 ..< 5 {
		record := test_notification_record(feedback.Record_ID(20 + offset), 1, .Warning, .Ordinary, .None)
		routed, resolved, _ := registry_route_and_project(&registry, record, test_full_frontend())
		testing.expect(t, resolved)
		applied, failure := presentation_apply(&cache, routed)
		testing.expectf(t, applied, "capacity apply failed with %v", failure.code)
	}
	testing.expect_value(t, cache.item_count, u8(4))
	testing.expect(t, presentation_find(&cache, 20, FACTORY_FLOATING_DESTINATION) < 0)
	attention := test_notification_record(30, 1, .Error, .Required, .None)
	routed, resolved, _ := registry_route_and_project(&registry, attention, test_full_frontend())
	testing.expect(t, resolved)
	applied, failure := presentation_apply(&cache, routed)
	testing.expectf(t, applied, "priority apply failed with %v", failure.code)
	testing.expect(t, presentation_find(&cache, 30, FACTORY_FLOATING_DESTINATION) >= 0)
	testing.expect(t, presentation_find(&cache, 30, FACTORY_DIAGNOSTIC_DESTINATION) >= 0)
	removed := presentation_frontend_lost(&cache)
	testing.expect_value(t, removed, u64(5))
	testing.expect_value(t, cache.item_count, u8(0))
	test_routing_registry_close(t, &registry)
}

@(private)
test_routing_registry :: proc(t: ^testing.T) -> (registry: Registry, ready: bool) {
	failure: Failure
	ready, failure = registry_init(&registry, 1, factory_configuration(1, test_profile()))
	testing.expectf(t, ready, "registry init failed with %v", failure.code)
	return registry, ready
}

@(private)
test_routing_registry_close :: proc(t: ^testing.T, registry: ^Registry) {
	closed, failure := registry_close(registry)
	testing.expectf(t, closed, "registry close failed with %v", failure.code)
}

@(private)
test_profile :: proc() -> ui.Presentation_Profile_Handle {
	return {registry_id = 1, role = .Contextual_Information, profile_id = 1, profile_generation = 1}
}

@(private)
test_full_frontend :: proc() -> Frontend_Context {
	return {
		profile = 1,
		capabilities = {.Cell_Geometry, .Clipping, .Semantic_Attributes, .Atomic_Generation, .Popup_Overlap},
		color = .True_Color,
		rows = 24,
		columns = 100,
		status_available = true,
		overlap_available = true,
		surface_available = true,
		diagnostic_available = true,
	}
}

@(private)
test_notification_record :: proc(id: feedback.Record_ID, generation: feedback.Record_Generation, severity: feedback.Severity, attention: feedback.Attention, retention: feedback.Retention_Policy) -> feedback.Record {
	class := feedback.Semantic_Class.Information
	if severity == .Error do class = .Error
	if severity == .Warning do class = .Warning
	return {
		id = id,
		generation = generation,
		source = {id = 1, generation = feedback.Source_Generation(generation)},
		kind = .Notification,
		class = class,
		severity = severity,
		attention = attention,
		lifecycle = .Retained,
		retention = retention,
		visibility = .Public,
		title = "Operation result",
		message = "The operation produced a result.",
	}
}

@(private)
test_progress_record :: proc(id: feedback.Record_ID, generation: feedback.Record_Generation, state: feedback.Progress_State) -> feedback.Record {
	return {
		id = id,
		generation = generation,
		source = {id = 2, generation = feedback.Source_Generation(generation)},
		kind = .Progress,
		class = .Progress,
		severity = .Information,
		attention = .Ordinary,
		lifecycle = .Retained,
		retention = .None,
		visibility = .Public,
		title = "Build",
		progress = {state = state, measurement = .Determinate, current = 2, total = 4, phase = "compile"},
	}
}

@(private)
test_has_destination :: proc(routed: Routed_Presentation, destination: Destination_ID) -> bool {
	for index in 0 ..< int(routed.projection_count) {
		if routed.projections[index].destination == destination do return true
	}
	return false
}

@(private)
delete_string :: proc(value: string) {
	if len(value) > 0 do delete(value)
}
