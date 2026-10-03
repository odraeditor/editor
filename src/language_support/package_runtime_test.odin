// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_support

import "../extension"
import "../language"
import "../language_service"
import "core:fmt"
import "core:testing"

@(private = "file")
PACKAGE_RUST_SUPPORT :: `{"languages":[{"display-name":"Rust","filenames":[],"id":"rust","suffixes":[".rs"]}],"schema":1,"selections":[],"services":[{"command":["rust-package-server","--stdio"],"default":true,"display-name":"Rust Package Server","enabled":true,"environment":[{"key":"RUST_LOG","value":"warn"}],"features":["diagnostics","completion"],"id":"rust-package-server","initialization-options":{},"languages":["rust"],"root-markers":["Cargo.toml"],"settings":{}}]}`

@(private = "file")
PACKAGE_CONFLICT_A :: `{"languages":[],"schema":1,"selections":[],"services":[{"command":["package-a-ols"],"default":true,"display-name":"Package A OLS","enabled":true,"environment":[],"features":["diagnostics","completion"],"id":"ols","initialization-options":{},"languages":["odin"],"root-markers":[],"settings":{}}]}`

@(private = "file")
PACKAGE_CONFLICT_B :: `{"languages":[],"schema":1,"selections":[],"services":[{"command":["package-b-ols"],"default":true,"display-name":"Package B OLS","enabled":true,"environment":[],"features":["diagnostics","completion"],"id":"ols","initialization-options":{},"languages":["odin"],"root-markers":[],"settings":{}}]}`

@(private = "file")
PACKAGE_LANGUAGE_AND_SERVICE_FACETS := [2]extension.Contribution_Facet{
	.Language,
	.Language_Service,
}

@(private = "file")
PACKAGE_SERVICE_FACETS := [1]extension.Contribution_Facet{.Language_Service}

@(private = "file")
PACKAGE_RUST_LANGUAGES := [1]string{"rust"}

@(private = "file")
PACKAGE_ODIN_LANGUAGES := [1]string{"odin"}

@(private = "file")
PACKAGE_PLATFORMS := [1]extension.Package_Platform{.Linux}

@(private = "file")
PACKAGE_ARCHITECTURES := [1]extension.Package_Architecture{.X86_64}

@(private = "file")
PACKAGE_FULL_AUTHORITIES := [4]extension.Package_Authority{
	.Inspect,
	.Filesystem_Read,
	.Process,
	.Environment,
}

@(private = "file")
PACKAGE_PROCESS_AUTHORITIES := [3]extension.Package_Authority{
	.Inspect,
	.Filesystem_Read,
	.Process,
}

/* Verifies activation and removal publish complete package generations with fallback. */
@(test)
package_runtime_activation_and_removal_are_atomic :: proc(t: ^testing.T) {
	language_catalog: language.Language_Catalog
	registry: language_service.Provider_Registry
	service_catalog: language_service.Service_Catalog
	factory, ready := package_runtime_test_init(&language_catalog, &registry, &service_catalog)
	testing.expect(t, ready)
	if !ready do return
	defer language.language_catalog_close(&language_catalog)
	defer language_service.service_catalog_close(&service_catalog)
	defer language_service.provider_registry_close(&registry)

	contribution: extension.Package_Language_Support_Candidate
	source: Language_Support_Source_Candidate
	prepared := package_runtime_test_prepare_source(
		&contribution,
		&source,
		PACKAGE_RUST_SUPPORT,
		"org.example.rust",
		7,
		PACKAGE_LANGUAGE_AND_SERVICE_FACETS[:],
		PACKAGE_RUST_LANGUAGES[:],
		PACKAGE_FULL_AUTHORITIES[:],
		"/bin/true",
	)
	testing.expect(t, prepared)
	if !prepared do return
	defer extension.package_language_support_close(&contribution)
	defer source_candidate_close(&source)
	packages := [?]^Language_Support_Source_Candidate{&source}
	candidate, candidate_ok := runtime_catalog_prepare_with_packages(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)),
		2,
		packages[:],
	)
	testing.expect(t, candidate_ok)
	if !candidate_ok do return
	testing.expect(t, runtime_catalog_publish(&candidate, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&candidate, &registry))

	association, associated, _ := language.language_catalog_resolve(&language_catalog, "/work/main.rs")
	testing.expect(t, associated)
	if !associated do return
	resolution, resolved, _ := language_service.service_catalog_resolve(
		&service_catalog,
		{
			language = association.language,
			project_membership = "/work",
			resolved_root = "/work",
			project_trusted = true,
		},
	)
	testing.expect(t, resolved)
	if !resolved do return
	definition, viewed, _ := language_service.provider_registry_definition(&registry, resolution.selected)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, definition.package_artifact, "/bin/true")
		testing.expect_value(t, definition.executable, "rust-package-server")
		testing.expect_value(t, definition.provider.kind, language_service.Provider_Kind.Native)
	}
	inspection: language_service.Service_Catalog_Inspection
	inspected, _ := language_service.service_catalog_inspect(&service_catalog, &inspection)
	testing.expect(t, inspected)
	package_record_found := false
	if inspected {
		for &record in inspection.definitions[:inspection.definition_count] {
			if language_service.service_identity_text_view(&record.identity) == "rust-package-server" {
				package_record_found = true
				testing.expect_value(t, record.scope.source, language_service.Service_Contribution_Source.Package)
				testing.expect_value(t, language_service.service_scope_text_view(&record.scope.name), "org.example.rust")
				testing.expect_value(t, language_service.service_provenance_text_view(&record.provenance), "Package org.example.rust")
			}
		}
	}
	testing.expect(t, package_record_found)

	removal, removal_ok := runtime_catalog_prepare(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)),
		3,
	)
	testing.expect(t, removal_ok)
	if !removal_ok do return
	retired := runtime_catalog_candidate_retired_definitions(&removal)
	testing.expect_value(t, len(retired), 1)
	retired_definition := retired[0]
	testing.expect(t, runtime_catalog_publish(&removal, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&removal, &registry))
	association, associated, _ = language.language_catalog_resolve(&language_catalog, "/work/main.rs")
	testing.expect(t, associated)
	if associated {
		resolution, resolved, _ = language_service.service_catalog_resolve(
			&service_catalog,
			{
				language = association.language,
				project_membership = "/work",
				resolved_root = "/work",
				project_trusted = true,
			},
		)
		testing.expect(t, resolved)
		if resolved {
			definition, viewed, _ = language_service.provider_registry_definition(
				&registry,
				resolution.selected,
			)
			testing.expect(t, viewed)
			if viewed {
				testing.expect_value(
					t,
					definition.executable,
					language_service.FACTORY_RUST_ANALYZER_EXECUTABLE,
				)
			}
		}
	}
	discarded, _ := language_service.provider_registry_discard_definition(&registry, retired_definition)
	testing.expect(t, discarded)
}

/* Verifies equal package identities conflict symmetrically and retain factory fallback. */
@(test)
package_runtime_conflicts_and_order_are_deterministic :: proc(t: ^testing.T) {
	language_catalog: language.Language_Catalog
	registry: language_service.Provider_Registry
	service_catalog: language_service.Service_Catalog
	factory, ready := package_runtime_test_init(&language_catalog, &registry, &service_catalog)
	testing.expect(t, ready)
	if !ready do return
	defer language.language_catalog_close(&language_catalog)
	defer language_service.service_catalog_close(&service_catalog)
	defer language_service.provider_registry_close(&registry)

	contribution_a, contribution_b: extension.Package_Language_Support_Candidate
	source_a, source_b: Language_Support_Source_Candidate
	first_ok := package_runtime_test_prepare_source(
		&contribution_a,
		&source_a,
		PACKAGE_CONFLICT_A,
		"org.example.ols-a",
		11,
		PACKAGE_SERVICE_FACETS[:],
		PACKAGE_ODIN_LANGUAGES[:],
		PACKAGE_PROCESS_AUTHORITIES[:],
		"/bin/true",
	)
	second_ok := package_runtime_test_prepare_source(
		&contribution_b,
		&source_b,
		PACKAGE_CONFLICT_B,
		"org.example.ols-b",
		13,
		PACKAGE_SERVICE_FACETS[:],
		PACKAGE_ODIN_LANGUAGES[:],
		PACKAGE_PROCESS_AUTHORITIES[:],
		"/bin/true",
	)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return
	defer extension.package_language_support_close(&contribution_a)
	defer extension.package_language_support_close(&contribution_b)
	defer source_candidate_close(&source_a)
	defer source_candidate_close(&source_b)
	forward := [?]^Language_Support_Source_Candidate{&source_a, &source_b}
	first, first_prepared := runtime_catalog_prepare_with_packages(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)),
		2,
		forward[:],
	)
	testing.expect(t, first_prepared)
	if !first_prepared do return
	testing.expect(t, runtime_catalog_publish(&first, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&first, &registry))
	first_inspection: language_service.Service_Catalog_Inspection
	first_inspected, _ := language_service.service_catalog_inspect(
		&service_catalog,
		&first_inspection,
	)
	testing.expect(t, first_inspected)
	testing.expect_value(t, first_inspection.conflict_count, u16(1))
	testing.expect_value(t, first_inspection.participant_count, u16(2))

	reverse := [?]^Language_Support_Source_Candidate{&source_b, &source_a}
	second, second_prepared := runtime_catalog_prepare_with_packages(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)),
		3,
		reverse[:],
	)
	testing.expect(t, second_prepared)
	if !second_prepared do return
	testing.expect(t, runtime_catalog_publish(&second, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&second, &registry))
	second_inspection: language_service.Service_Catalog_Inspection
	second_inspected, _ := language_service.service_catalog_inspect(
		&service_catalog,
		&second_inspection,
	)
	testing.expect(t, second_inspected)
	testing.expect_value(t, second_inspection.conflict_count, first_inspection.conflict_count)
	testing.expect_value(t, second_inspection.participant_count, first_inspection.participant_count)
	testing.expect_value(t, second_inspection.conflicts[0].fallback, first_inspection.conflicts[0].fallback)

	odin, odin_ready, _ := language.language_catalog_resolve(&language_catalog, "/work/main.odin")
	testing.expect(t, odin_ready)
	if odin_ready {
		resolution, resolved, _ := language_service.service_catalog_resolve(
			&service_catalog,
			{
				language = odin.language,
				project_membership = "/work",
				resolved_root = "/work",
				project_trusted = true,
			},
		)
		testing.expect(t, resolved)
		testing.expect_value(t, resolution.selected, factory)
		testing.expect_value(t, resolution.conflicted, u16(2))
	}
}

/* Verifies payload contents cannot use authority absent from the manifest. */
@(test)
package_runtime_requires_declared_environment_authority :: proc(t: ^testing.T) {
	contribution: extension.Package_Language_Support_Candidate
	source: Language_Support_Source_Candidate
	prepared := package_runtime_test_prepare_source(
		&contribution,
		&source,
		PACKAGE_RUST_SUPPORT,
		"org.example.denied",
		17,
		PACKAGE_LANGUAGE_AND_SERVICE_FACETS[:],
		PACKAGE_RUST_LANGUAGES[:],
		PACKAGE_PROCESS_AUTHORITIES[:],
		"/bin/true",
	)
	testing.expect(t, !prepared)
	if contribution.live do testing.expect(t, extension.package_language_support_close(&contribution))
	testing.expect(t, !source.live)
}

@(private = "file")
package_runtime_test_prepare_source :: proc(
	contribution: ^extension.Package_Language_Support_Candidate,
	source: ^Language_Support_Source_Candidate,
	payload, identity: string,
	generation: u64,
	facets: []extension.Contribution_Facet,
	languages: []string,
	authorities: []extension.Package_Authority,
	executable_artifact: string,
) -> bool {
	prepared: bool
	failure: extension.Package_Contribution_Failure
	provenance := fmt.aprintf("Package %s", identity, allocator = context.temp_allocator)
	contribution^, prepared, failure = extension.package_language_support_prepare(
		{
			package_identity = identity,
			generation = extension.Package_Generation(generation),
			payload = transmute([]u8)payload,
			facets = facets,
			affected_languages = languages,
			platforms = PACKAGE_PLATFORMS[:],
			architectures = PACKAGE_ARCHITECTURES[:],
			authorities = authorities,
			executable_artifact = executable_artifact,
			provenance = provenance,
		},
	)
	_ = failure
	if !prepared do return false
	source^, prepared = package_source_prepare(contribution)
	return prepared
}

@(private = "file")
package_runtime_test_init :: proc(
	language_catalog: ^language.Language_Catalog,
	registry: ^language_service.Provider_Registry,
	service_catalog: ^language_service.Service_Catalog,
) -> (language_service.Definition_Handle, bool) {
	language_ready, _ := language.language_catalog_init(language_catalog, 271)
	if !language_ready do return {}, false
	_, languages_confirmed, _ := language.factory_bundle_catalog_confirm(language_catalog)
	if !languages_confirmed do return {}, false
	registry_ready, _ := language_service.provider_registry_init(
		registry,
		{id = 273, generation = 1},
	)
	if !registry_ready do return {}, false
	factory, factory_ready, _ := language_service.provider_registry_register_factory_ols(registry)
	if !factory_ready do return {}, false
	service_ready, _ := language_service.service_catalog_init(
		service_catalog,
		279,
		{id = 273, generation = 1},
	)
	if !service_ready do return {}, false
	odin, odin_ready, _ := language.language_catalog_resolve(language_catalog, "/work/main.odin")
	if !odin_ready do return {}, false
	catalog_ready, _ := language_service.factory_ols_catalog_confirm(
		service_catalog,
		factory,
		odin.language,
	)
	return factory, catalog_ready
}
