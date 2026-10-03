// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:strings"
import "core:testing"

/* Verifies inspection projection preserves notation, policy, source, and availability. */
@(test)
keymap_row_presents_protected_binding :: proc(t: ^testing.T) {
	definitions := base_command_definitions()
	for &definition in definitions {
		definition.interactive = true
		definition.provenance = Definition_Provenance {
			provider = "test",
			source = "keymap-inspection-view-test",
		}
	}
	registry: Command_Registry
	ready, registry_failure := command_registry_init(
		&registry,
		Registry_Generation(401),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "registry initialization failed: %v", registry_failure.code)
	if !ready {
		return
	}
	defer command_registry_close(&registry)

	bindings := [?]Layered_Binding_Definition {
		layered_binding('a', "cursor-previous-grapheme", .Bind),
	}
	maps := [?]Map_Definition {
		layered_map(81, "factory", .Factory_Fallback, 0, bindings[:]),
	}
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, publish_failure := profile_activation_replace(
		&activation,
		&registry,
		layered_profile(81, maps[:]),
		layered_active_context(81),
		&pending,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "profile activation failed: %v", publish_failure.code)
	if !published {
		return
	}
	inspection, inspected, inspect_failure := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = protected_control_sequence('g')},
		context.allocator,
	)
	testing.expectf(t, inspected, "inspection failed: %v", inspect_failure.code)
	if !inspected {
		return
	}
	defer inspection_result_close(&inspection)
	catalog, catalog_ok, catalog_failure := command_catalog_build(
		&registry,
		&activation.snapshot,
		Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	testing.expectf(t, catalog_ok, "catalog failed: %v", catalog_failure.code)
	if !catalog_ok {
		return
	}
	defer command_catalog_close(&catalog)

	row_storage: [MAX_KEYMAP_INSPECTION_ROW_BYTES]u8
	if len(inspection.records) == 1 {
		row := keymap_inspection_record_text(
			inspection.records[0],
			&inspection,
			&catalog,
			row_storage[:],
		)
		testing.expect(t, strings.contains(row, "C-g -> keyboard-quit"))
		testing.expect(t, strings.contains(row, "effective; available; protected"))
		testing.expect(t, strings.contains(row, "map protected-recovery@1"))
		testing.expect(t, strings.contains(row, "source native/factory recovery policy"))
		testing.expect(t, strings.contains(row, "protection-reason"))
	} else {
		testing.expect(t, false)
	}
}

/* Verifies shared UI rows present catalog, state policy, scope, selectors, and surfaces. */
@(test)
compatibility_rows_present_inspection :: proc(t: ^testing.T) {
	registry, ready := layered_test_registry(t, Registry_Generation(402), context.allocator)
	if !ready do return
	defer command_registry_close(&registry)
	fixture: Profile_Compatibility_Fixture
	profile_compatibility_fixture_prepare_buildable(&fixture)
	activation: Profile_Activation
	profile_activation_init(&activation)
	defer profile_activation_close(&activation)
	pending: Pending_State
	published, _ := profile_activation_replace_catalog(
		&activation,
		&registry,
		fixture.catalog,
		layered_active_context(1),
		&pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expect(t, published)
	if !published do return
	sentinel: u8
	catalog := Command_Catalog {
		registry_generation = Registry_Generation(402),
		state = rawptr(&sentinel),
	}
	compatibility, compatibility_ok, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Compatibility},
		context.allocator,
	)
	testing.expect(t, compatibility_ok)
	if !compatibility_ok do return
	defer inspection_result_close(&compatibility)
	found_catalog, found_inactive_profile, found_state, found_surface := false, false, false, false
	row_storage: [MAX_KEYMAP_INSPECTION_ROW_BYTES]u8
	for record in compatibility.records {
		row := keymap_inspection_record_text(record, &compatibility, &catalog, row_storage[:])
		switch record.kind {
		case .Catalog:
			found_catalog = strings.contains(row, "catalog 1 [effective]")
		case .Profile:
			if record.profile.id == Profile_ID(2) {
				found_inactive_profile = strings.contains(row, "profile synthetic 2@1 [inactive]")
			}
		case .State:
			if record.state.id == Interaction_State_ID(1) {
				found_state = strings.contains(row, "state direct-editing 1@1 [effective]") &&
					strings.contains(row, "text-input true")
			}
		case .Surface:
			found_surface = strings.contains(row, "surface extended-command 1@1")
		case .Invalid, .Binding, .Remap, .Map, .Snapshot, .Rejection:
		}
	}
	testing.expect(t, found_catalog && found_inactive_profile && found_state && found_surface)

	shared, shared_ok, _ := keymap_inspect(
		&registry,
		&activation,
		&pending,
		Inspection_Query{kind = .Sequence, sequence = scalar_sequence('b')},
		context.allocator,
	)
	testing.expect(t, shared_ok)
	if shared_ok {
		defer inspection_result_close(&shared)
		if len(shared.records) == 1 {
			row := keymap_inspection_record_text(shared.records[0], &shared, &catalog, row_storage[:])
			testing.expect(t, strings.contains(row, "scope shared-continuity"))
			testing.expect(t, strings.contains(row, "selectors 1/1,2/2"))
			testing.expect(t, strings.contains(row, "effects-admitted true"))
		}
	}
}
