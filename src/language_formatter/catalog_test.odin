// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_formatter

import "../language"
import "core:testing"

@(private)
formatter_test_language :: proc(id: language.Language_ID) -> language.Language_Identity {
	value := language.Language_Identity {
		id = id,
		generation = 1,
		name = {length = 4},
	}
	copy(value.name.bytes[:4], "test")
	return value
}

@(private)
formatter_test_definition :: proc(
	identity: string,
	languages: []language.Language_Identity,
	source: Contribution_Source,
	scope_kind: Scope_Kind,
	scope := "",
	default_selection := false,
) -> Formatter_Proposal {
	return {
		identity = identity,
		name = identity,
		languages = languages,
		kind = .External,
		executable = "formatter",
		input_mode = .Standard_Input,
		output_mode = .Standard_Output,
		scopes = {.Document, .Range},
		root_policy = .Project_Membership,
		limits = DEFAULT_LIMITS,
		version_probe = {expected_exact = "formatter 1.0"},
		source = source,
		scope_kind = scope_kind,
		scope = scope,
		source_generation = 1,
		default_selection = default_selection,
		provenance = "formatter catalog test",
	}
}

/* Verifies Project selection is scoped, explicit, and higher precedence. */
@(test)
catalog_resolves_project_selection_only_inside_trusted_membership :: proc(t: ^testing.T) {
	odin := formatter_test_language(1)
	languages := [?]language.Language_Identity{odin}
	definitions := [?]Formatter_Proposal {
		formatter_test_definition("factory-format", languages[:], .Factory, .Global, "", true),
		formatter_test_definition("project-format", languages[:], .Project, .Project_Membership, "project-a"),
	}
	selections := [?]Selection_Proposal {{
		language = odin,
		formatter_identity = "project-format",
		source = .Project,
		scope_kind = .Project_Membership,
		scope = "project-a",
		source_generation = 1,
	}}
	catalog: Catalog
	initialized, _ := catalog_init(&catalog, 11)
	testing.expect(t, initialized)
	if !initialized do return
	defer catalog_close(&catalog)
	_, published, failure := catalog_publish(&catalog, {generation = 1, definitions = definitions[:], selections = selections[:]})
	testing.expectf(t, published, "catalog publication failed: %v", failure.code)

	project, resolved, _ := catalog_resolve(&catalog, {
		language = odin,
		project_membership = "project-a",
		project_trusted = true,
	})
	testing.expect(t, resolved)
	testing.expect_value(t, project.kind, Selection_Kind.Explicit_Project)
	selected, found, _ := catalog_definition(&catalog, project.formatter)
	testing.expect(t, found)
	testing.expect_value(t, text_view(&selected.identity), "project-format")

	factory, fallback, _ := catalog_resolve(&catalog, {language = odin})
	testing.expect(t, fallback)
	testing.expect_value(t, factory.kind, Selection_Kind.Unique_Default)
	selected, found, _ = catalog_definition(&catalog, factory.formatter)
	testing.expect(t, found)
	testing.expect_value(t, text_view(&selected.identity), "factory-format")
}

/* Verifies confirmed records own candidate text and reject stale replacement. */
@(test)
catalog_publication_is_copied_and_atomic :: proc(t: ^testing.T) {
	odin := formatter_test_language(1)
	languages := [?]language.Language_Identity{odin}
	identity_bytes := [?]u8{'o', 'd', 'i', 'n', '-', 'f', 'm', 't'}
	identity := string(identity_bytes[:])
	definitions := [?]Formatter_Proposal {
		formatter_test_definition(identity, languages[:], .Personal, .Global, "", true),
	}
	catalog: Catalog
	initialized, _ := catalog_init(&catalog, 13)
	testing.expect(t, initialized)
	if !initialized do return
	defer catalog_close(&catalog)
	_, published, _ := catalog_publish(&catalog, {generation = 1, definitions = definitions[:]})
	testing.expect(t, published)
	identity_bytes[0] = 'X'
	resolved, selected, _ := catalog_resolve(&catalog, {language = odin})
	testing.expect(t, selected)
	record, found, _ := catalog_definition(&catalog, resolved.formatter)
	testing.expect(t, found)
	testing.expect_value(t, text_view(&record.identity), "odin-fmt")

	_, replaced, failure := catalog_publish(&catalog, {generation = 1})
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Stale_Generation)
	inspection, inspected := catalog_inspect(&catalog)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.generation, Catalog_Generation(1))
	testing.expect_value(t, inspection.definitions, u16(1))
}

/* Verifies exact version evidence cannot silently accept a changed executable. */
@(test)
catalog_confirms_only_exact_executable_version :: proc(t: ^testing.T) {
	odin := formatter_test_language(1)
	languages := [?]language.Language_Identity{odin}
	definitions := [?]Formatter_Proposal {
		formatter_test_definition("odin-format", languages[:], .Factory, .Global, "", true),
	}
	catalog: Catalog
	initialized, _ := catalog_init(&catalog, 17)
	testing.expect(t, initialized)
	if !initialized do return
	defer catalog_close(&catalog)
	_, published, _ := catalog_publish(&catalog, {generation = 1, definitions = definitions[:]})
	testing.expect(t, published)
	selection, resolved, _ := catalog_resolve(&catalog, {language = odin})
	testing.expect(t, resolved)

	confirmed, failure := catalog_confirm_profile(
		&catalog,
		selection.formatter,
		1,
		.Available,
		"/usr/bin/formatter",
		"formatter 2.0",
		"controlled PATH",
	)
	testing.expect(t, !confirmed)
	testing.expect_value(t, failure.code, Failure_Code.Version_Mismatch)
	record, found, _ := catalog_definition(&catalog, selection.formatter)
	testing.expect(t, found)
	testing.expect_value(t, record.profile.availability, Availability.Changed)

	confirmed, failure = catalog_confirm_profile(
		&catalog,
		selection.formatter,
		2,
		.Available,
		"/usr/bin/formatter",
		"formatter 1.0",
		"controlled PATH",
	)
	testing.expectf(t, confirmed, "profile confirmation failed: %v", failure.code)
	record, found, _ = catalog_definition(&catalog, selection.formatter)
	testing.expect(t, found)
	testing.expect_value(t, record.profile.availability, Availability.Available)
	testing.expect_value(t, text_view(&record.profile.resolved), "/usr/bin/formatter")
}
