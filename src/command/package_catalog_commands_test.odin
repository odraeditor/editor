// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Verifies every package catalog operation has stable native metadata. */
@(test)
package_catalog_operations_have_stable_semantic_commands :: proc(t: ^testing.T) {
	names := [?]string {
		"package-catalog-list",
		"package-catalog-add",
		"package-catalog-disable",
		"package-catalog-remove",
		"package-catalog-refresh",
		"package-catalog-search",
		"package-catalog-describe",
		"package-manual-acquire",
		"package-advisory-list",
		"package-curator-validate",
		"package-catalog-doctor",
		"package-list",
		"package-discover",
		"package-describe",
		"package-install",
		"package-enable",
		"package-disable",
		"package-update",
		"package-rollback",
		"package-remove",
		"package-cleanup",
		"package-doctor",
	}
	definitions := native_command_definitions()
	routes: [PACKAGE_CATALOG_COMMAND_COUNT]Native_Route
	for name, index in names {
		definition, found := package_catalog_test_definition(definitions[:], name)
		testing.expectf(t, found, "missing package catalog command %s", name)
		if !found do continue
		testing.expect_value(t, definition.effects, interaction.Command_Effects{.Lifecycle})
		testing.expect_value(t, definition.requirements, interaction.Command_Requirements{})
		testing.expect_value(t, definition.provenance.provider, "odra-package-catalog")
		testing.expect_value(t, definition.provenance.source, "src/command/package_catalog_commands.odin")
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Native)
		testing.expect(t, definition.interactive)
		route, decoded := native_route_decode(definition.route)
		testing.expect(t, decoded)
		routes[index] = route
	}
	for route, index in routes {
		for other, other_index in routes {
			if index != other_index do testing.expect(t, route != other)
		}
	}
}

@(private)
package_catalog_test_definition :: proc(
	definitions: []interaction.Command_Definition,
	name: string,
) -> (interaction.Command_Definition, bool) {
	for definition in definitions {
		if definition.name == name do return definition, true
	}
	return {}, false
}
