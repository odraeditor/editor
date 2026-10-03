// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package theme

import "../ui"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies the maintained factory order, identities, and accepted backgrounds. */
@(test)
family_has_exact_daylight_order_and_backgrounds :: proc(t: ^testing.T) {
	styles := factory_style_matrix()
	proposals := factory_definition_proposals(&styles)
	identities := [?]string {
		WROCLAW_SUNRISE_IDENTITY,
		WROCLAW_MORNING_IDENTITY,
		WROCLAW_SUNSET_IDENTITY,
		WROCLAW_NIGHT_IDENTITY,
		TERMINAL_DEFAULT_IDENTITY,
	}
	backgrounds := [?]ui.SRGB_Color {
		rgb(0xB0, 0xDE, 0xF3),
		rgb(0xF7, 0xFD, 0xFD),
		rgb(0xF3, 0xEB, 0xDD),
		rgb(0x1A, 0x1B, 0x26),
		{},
	}
	for proposal, index in proposals {
		testing.expect_value(t, proposal.identity, identities[index])
		normal := proposal.styles[role_index(.Text_Normal)]
		if index < 4 {
			testing.expect(t, normal.background.present)
			testing.expect_value(t, normal.background.color, backgrounds[index])
			region := proposal.styles[role_index(.Text_Region)]
			testing.expect(t, region.background.present)
			testing.expect(t, region.background.color != normal.background.color)
			testing.expect(t, .Reverse not_in region.attributes)
			current := proposal.styles[role_index(.List_Current)]
			testing.expect(t, .Reverse not_in current.attributes)
			status := proposal.styles[role_index(.Status_Active)]
			identity := proposal.styles[role_index(.Status_Identity)]
			position := proposal.styles[role_index(.Status_Position)]
			alert := proposal.styles[role_index(.Status_Alert)]
			workspace := proposal.styles[role_index(.Status_Workspace)]
			project := proposal.styles[role_index(.Status_Project)]
			editing := proposal.styles[role_index(.Status_Editing_Context)]
			tree_project := proposal.styles[role_index(.Tree_Project)]
			tree_directory := proposal.styles[role_index(.Tree_Directory)]
			tree_source := proposal.styles[role_index(.Tree_File_Source)]
			tree_documentation := proposal.styles[role_index(.Tree_File_Documentation)]
			tree_configuration := proposal.styles[role_index(.Tree_File_Configuration)]
			tree_failure := proposal.styles[role_index(.Tree_Failure)]
			popup_background := proposal.styles[role_index(.Popup_Background)]
			popup_content := proposal.styles[role_index(.Popup_Content)]
			popup_border := proposal.styles[role_index(.Popup_Border)]
			popup_diagnostic := proposal.styles[role_index(.Popup_Diagnostic)]
			popup_unavailable := proposal.styles[role_index(.Popup_Unavailable)]
			testing.expect(t, .Reverse not_in status.attributes)
			testing.expect(t, .Bold in identity.attributes)
			testing.expect(t, .Dim not_in position.attributes)
			testing.expect(t, position.foreground != status.foreground)
			testing.expect(t, identity.foreground != status.foreground)
			testing.expect(t, alert.foreground != status.foreground)
			testing.expect(t, workspace.foreground != project.foreground)
			testing.expect(t, editing.foreground != status.foreground)
			testing.expect(t, tree_project.foreground != tree_directory.foreground)
			testing.expect(t, tree_source.foreground != tree_documentation.foreground)
			testing.expect(t, tree_configuration.foreground != tree_documentation.foreground)
			testing.expect(t, .Bold in tree_failure.attributes)
			testing.expect(t, popup_background.background != normal.background)
			testing.expect_value(t, popup_content.background, popup_background.background)
			testing.expect(t, .Bold in popup_border.attributes)
			testing.expect(t, .Underline in popup_diagnostic.attributes)
			testing.expect(t, .Dim in popup_unavailable.attributes)
		} else {
			testing.expect(t, !normal.background.present)
			testing.expect(t, .Reverse not_in proposal.styles[role_index(.Status_Active)].attributes)
			testing.expect(t, .Bold in proposal.styles[role_index(.Tree_Project)].attributes)
			testing.expect(t, .Dim in proposal.styles[role_index(.Tree_Inactive)].attributes)
			testing.expect(t, .Underline in proposal.styles[role_index(.Tree_Destructive)].attributes)
			testing.expect(t, .Bold in proposal.styles[role_index(.Popup_Border)].attributes)
			testing.expect(t, .Underline in proposal.styles[role_index(.Popup_Diagnostic)].attributes)
			testing.expect(t, .Dim in proposal.styles[role_index(.Popup_Unavailable)].attributes)
		}
	}
}

/* Verifies every maintained definition is complete, unique, valid, and legible. */
@(test)
theme_family_maintains_role_contrast :: proc(t: ^testing.T) {
	styles := factory_style_matrix()
	proposals := factory_definition_proposals(&styles)
	for proposal in proposals {
		valid, failure := definition_proposal_validate(proposal)
		testing.expectf(t, valid, "%s failed contract with %v", proposal.identity, failure.code)
		testing.expectf(
			t,
			factory_definition_contrast_is_valid(proposal),
			"%s failed maintained contrast",
			proposal.identity,
		)
		seen: [MAX_STYLES + 1]bool
		for style in proposal.styles {
			index := int(style.role)
			testing.expectf(t, !seen[index], "%s duplicated role %v", proposal.identity, style.role)
			seen[index] = true
		}
		for role in ui.Style_Role {
			if ui.style_role_is_valid(role) {
				testing.expectf(t, seen[int(role)], "%s omitted role %v", proposal.identity, role)
			}
		}
	}
}

/* Verifies malformed factory colors and style bounds reject before bootstrap. */
@(test)
factory_family_rejects_invalid_colors_and_limits :: proc(t: ^testing.T) {
	styles := factory_style_matrix()
	proposals := factory_definition_proposals(&styles)
	styles[0][role_index(.Text_Normal)].foreground = {
		present = false,
		color = rgb(1, 2, 3),
	}
	_, invalid_color := definition_proposal_validate(proposals[0])
	testing.expect_value(t, invalid_color.code, Failure_Code.Invalid_Style)

	styles = factory_style_matrix()
	proposals = factory_definition_proposals(&styles)
	proposals[0].styles = proposals[0].styles[:CURRENT_STYLE_ROLE_COUNT - 1]
	registry: Registry
	initialized, incomplete := theme_registry_init(
		&registry,
		41,
		proposals[:],
		WROCLAW_NIGHT_IDENTITY,
		TERMINAL_DEFAULT_IDENTITY,
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, incomplete.code, Failure_Code.Incomplete_Style_Roles)
}

/* Verifies duplicate identities and live-definition limits preserve selection. */
@(test)
registry_rejects_duplicate :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := theme_registry_init_factory(&registry, 44)
	testing.expect(t, initialized)
	defer theme_registry_close(&registry)
	before, _, _ := theme_registry_selection(&registry)
	custom_styles := factory_style_matrix()[0]
	duplicate := Definition_Proposal {
		identity = WROCLAW_NIGHT_IDENTITY,
		display_name = "Duplicate Night",
		provider_name = "racket-test",
		provenance = "src/theme/factory_test.odin",
		styles = custom_styles[:],
	}
	_, duplicate_ok, duplicate_failure := theme_registry_propose(
		&registry, before.registry_generation, duplicate,
	)
	after_duplicate, _, _ := theme_registry_selection(&registry)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Definition)
	testing.expect_value(t, after_duplicate, before)

	limits := DEFAULT_RESOURCE_LIMITS
	limits.definitions = FACTORY_DEFINITION_COUNT
	limited: Registry
	limited_ok, _ := theme_registry_init_factory(&limited, 45, limits)
	testing.expect(t, limited_ok)
	defer theme_registry_close(&limited)
	limited_before, _, _ := theme_registry_selection(&limited)
	duplicate.identity = "capacity-theme"
	duplicate.display_name = "Capacity Theme"
	_, capacity_ok, capacity_failure := theme_registry_propose(
		&limited, limited_before.registry_generation, duplicate,
	)
	limited_after, _, _ := theme_registry_selection(&limited)
	testing.expect(t, !capacity_ok)
	testing.expect_value(t, capacity_failure.code, Failure_Code.Definition_Limit)
	testing.expect_value(t, limited_after, limited_before)
}

/* Verifies factory bootstrap, fallback, accounting, allocation fault, and teardown. */
@(test)
registry_lifecycle_is_exact_and_leak_free :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	initialized, failure := theme_registry_init_factory(
		&registry, 42, DEFAULT_RESOURCE_LIMITS, allocator,
	)
	testing.expectf(t, initialized, "factory init failed with %v", failure.code)
	selection, selected, _ := theme_registry_selection(&registry)
	inspection, inspected, _ := theme_registry_inspect(&registry)
	night, night_found, _ := theme_registry_definition_by_name(&registry, WROCLAW_NIGHT_IDENTITY)
	baseline, baseline_found, _ := theme_registry_definition_by_name(
		&registry, TERMINAL_DEFAULT_IDENTITY,
	)
	testing.expect(t, selected && inspected && night_found && baseline_found)
	testing.expect_value(t, selection.active, night.descriptor.handle)
	testing.expect_value(t, selection.fallback, night.descriptor.handle)
	testing.expect_value(t, selection.baseline, baseline.descriptor.handle)
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.definitions, u16(FACTORY_DEFINITION_COUNT))
	closed, _ := theme_registry_close(&registry)
	testing.expect(t, closed)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	_, reopened, closed_failure := theme_registry_selection(&registry)
	testing.expect(t, !reopened)
	testing.expect_value(t, closed_failure.code, Failure_Code.Closed_Registry)
	mem.tracking_allocator_destroy(&tracking)

	fault_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&fault_tracking, context.allocator)
	failing := Factory_Failing_Allocator {
		backing = mem.tracking_allocator(&fault_tracking),
		fail_after = 0,
	}
	faulted_registry: Registry
	_, allocation_failure := theme_registry_init_factory(
		&faulted_registry,
		43,
		DEFAULT_RESOURCE_LIMITS,
		factory_failing_allocator(&failing),
	)
	testing.expect_value(t, allocation_failure.code, Failure_Code.Allocation)
	testing.expect_value(t, fault_tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&fault_tracking)
}

@(private)
Factory_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
factory_failing_allocator :: proc(data: ^Factory_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = factory_failing_allocator_proc, data = data}
}

@(private)
factory_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Factory_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
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
