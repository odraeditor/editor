// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* PACKAGE_CATALOG_COMMAND_COUNT is the stable public catalog operation set. */
PACKAGE_CATALOG_COMMAND_COUNT :: 22

/* package_catalog_command_definitions returns package-family-neutral commands. */
package_catalog_command_definitions :: proc() -> [PACKAGE_CATALOG_COMMAND_COUNT]interaction.Command_Definition {
	return {
		package_catalog_command_definition(.Package_Catalog_List, "package-catalog-list", "List explicitly configured catalogs and their confirmed refresh state."),
		package_catalog_command_definition(.Package_Catalog_Add, "package-catalog-add", "Confirm and add one exact package catalog identity and trust reference."),
		package_catalog_command_definition(.Package_Catalog_Disable, "package-catalog-disable", "Disable one configured package catalog without changing installed packages."),
		package_catalog_command_definition(.Package_Catalog_Remove, "package-catalog-remove", "Remove one configured package catalog without changing installed packages."),
		package_catalog_command_definition(.Package_Catalog_Refresh, "package-catalog-refresh", "Refresh selected catalog discovery state through configured endpoints."),
		package_catalog_command_definition(.Package_Catalog_Search, "package-catalog-search", "Search confirmed package catalog snapshots with curator attribution."),
		package_catalog_command_definition(.Package_Catalog_Describe, "package-catalog-describe", "Inspect one catalog or package without collapsing trust dimensions."),
		package_catalog_command_definition(.Package_Manual_Acquire, "package-manual-acquire", "Resolve and confirm one exact manual package source."),
		package_catalog_command_definition(.Package_Advisory_List, "package-advisory-list", "List retained advisory evidence and effective local responses."),
		package_catalog_command_definition(.Package_Curator_Validate, "package-curator-validate", "Validate curator records without granting curation authority."),
		package_catalog_command_definition(.Package_Catalog_Doctor, "package-catalog-doctor", "Diagnose catalog identity, endpoints, snapshots, failures, and recovery."),
		package_catalog_command_definition(.Package_List, "package-list", "List installed package releases and their exact lifecycle states."),
		package_catalog_command_definition(.Package_Discover, "package-discover", "Find human-readable package release candidates in confirmed catalogs."),
		package_catalog_command_definition(.Package_Describe, "package-describe", "Inspect package provenance, authority, lifecycle, operation, and failure state."),
		package_catalog_command_definition(.Package_Install, "package-install", "Install one exact selected package release without activating it."),
		package_catalog_command_definition(.Package_Enable, "package-enable", "Confirm authority and activate one installed package release."),
		package_catalog_command_definition(.Package_Disable, "package-disable", "Deactivate one package while preserving installed content."),
		package_catalog_command_definition(.Package_Update, "package-update", "Activate one installed update while retaining the prior release for rollback."),
		package_catalog_command_definition(.Package_Rollback, "package-rollback", "Restore the retained prior confirmed package release."),
		package_catalog_command_definition(.Package_Remove, "package-remove", "Remove one inactive package release after dependency checks."),
		package_catalog_command_definition(.Package_Cleanup, "package-cleanup", "Delete only unreachable editor-owned package content."),
		package_catalog_command_definition(.Package_Doctor, "package-doctor", "Diagnose installed package state, recovery, authority, and activation."),
	}
}

@(private)
package_catalog_command_definition :: proc(
	route: Native_Route,
	name, description: string,
) -> interaction.Command_Definition {
	definition := native_definition(route, name, {.Lifecycle}, description, {})
	definition.provenance = interaction.Definition_Provenance {
		provider = "odra-package-catalog",
		source = "src/command/package_catalog_commands.odin",
	}
	return definition
}
