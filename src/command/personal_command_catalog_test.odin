// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Verifies admitted personal commands retain route identity and visible provenance. */
@(test)
personal_routes_are_catalogued :: proc(t: ^testing.T) {
	personal := [?]interaction.Command_Definition {{
		name = "personal-normalize-heading",
		route = racket_route(.Personal, 1),
		implementation = .Racket,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = {.Buffer, .View, .Text_Mutation},
		description = "Normalize the current heading.",
		interactive = true,
		requirements = {.Active_Buffer},
		provenance = {
			provider = "personal",
			source = "modules/text.rkt",
			location = "7:3",
		},
	}}
	registry: interaction.Command_Registry
	ready, registry_failure := built_in_command_registry_init(
		&registry,
		interaction.Registry_Generation(801),
		context.allocator,
		racket_definitions = personal[:],
	)
	testing.expectf(t, ready, "registry initialization failed: %v", registry_failure.code)
	if !ready {
		return
	}
	defer interaction.command_registry_close(&registry)

	handle, found, lookup_failure := interaction.command_lookup(
		&registry,
		"personal-normalize-heading",
	)
	testing.expectf(t, found, "personal command lookup failed: %v", lookup_failure.code)
	if !found {
		return
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(&registry, handle)
	testing.expectf(t, metadata_ok, "personal command metadata failed: %v", metadata_failure.code)
	if metadata_ok {
		dispatch_class, operation, decoded := racket_route_decode(metadata.route)
		testing.expect(t, decoded)
		testing.expect_value(t, dispatch_class, Racket_Dispatch_Class.Personal)
		testing.expect_value(t, operation, u16(1))
		testing.expect_value(t, metadata.provenance.provider, "personal")
		testing.expect_value(t, metadata.provenance.source, "modules/text.rkt")
		testing.expect_value(t, metadata.provenance.location, "7:3")
	}

	snapshot: interaction.Resolution_Snapshot
	snapshot_ready, snapshot_failure := interaction.snapshot_compile(
		&snapshot,
		&registry,
		interaction.Snapshot_Generation(801),
		interaction.Keymap_Definition {
			registry_generation = interaction.Registry_Generation(801),
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, snapshot_ready, "snapshot initialization failed: %v", snapshot_failure.code)
	if !snapshot_ready {
		return
	}
	defer interaction.snapshot_close(&snapshot)

	catalog, catalog_ready, catalog_failure := interaction.command_catalog_build(
		&registry,
		&snapshot,
		interaction.Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	testing.expectf(t, catalog_ready, "command catalog failed: %v", catalog_failure.code)
	if !catalog_ready {
		return
	}
	defer interaction.command_catalog_close(&catalog)

	visible := false
	for entry in catalog.entries {
		if entry.metadata.name != "personal-normalize-heading" {
			continue
		}
		visible = true
		testing.expect_value(t, entry.availability, interaction.Command_Availability.Available)
		testing.expect_value(t, entry.metadata.provenance.provider, "personal")
		testing.expect_value(t, entry.metadata.provenance.source, "modules/text.rkt")
		testing.expect_value(t, entry.metadata.provenance.location, "7:3")
	}
	testing.expect(t, visible)
}
