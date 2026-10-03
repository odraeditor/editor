// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_support

import "../language"
import "../language_service"
import "core:strings"
import "core:testing"

RUNTIME_CATALOG_FIXTURE :: `{"languages":[{"display-name":"Rust","filenames":[],"id":"rust","suffixes":[".rs"]}],"schema":1,"selections":[],"services":[{"command":["/bin/true","--stdio"],"default":true,"display-name":"Rust Fixture","enabled":true,"environment":[{"key":"RUST_FIXTURE_TOKEN","value":"redacted-value"}],"features":["diagnostics","completion"],"id":"rust-fixture","initialization-options":{"profile":"test"},"languages":["rust"],"root-markers":["Cargo.toml"],"settings":{"fixture":{"enabled":true}}}]}`
RUNTIME_CATALOG_CHANGED_FIXTURE :: `{"languages":[{"display-name":"Rust","filenames":[],"id":"rust","suffixes":[".rs"]}],"schema":1,"selections":[],"services":[{"command":["/bin/true","--stdio"],"default":true,"display-name":"Rust Fixture","enabled":true,"environment":[{"key":"RUST_FIXTURE_TOKEN","value":"redacted-value"}],"features":["diagnostics","completion"],"id":"rust-fixture","initialization-options":{"profile":"test"},"languages":["rust"],"root-markers":["Cargo.toml"],"settings":{"fixture":{"enabled":false}}}]}`

/* Verifies abandoning a prepared publication restores exact registry accounting. */
@(test)
runtime_catalog_abandonment_rolls_back_definitions :: proc(t: ^testing.T) {
	language_catalog: language.Language_Catalog
	registry: language_service.Provider_Registry
	service_catalog: language_service.Service_Catalog
	factory, ready := runtime_catalog_test_init(
		&language_catalog,
		&registry,
		&service_catalog,
	)
	testing.expect(t, ready)
	if !ready do return
	defer language.language_catalog_close(&language_catalog)
	defer language_service.service_catalog_close(&service_catalog)
	defer language_service.provider_registry_close(&registry)
	before_registry, registry_ok := language_service.provider_registry_inspect(&registry)
	before_languages, languages_ok, _ := language.language_catalog_inspect(&language_catalog)
	before_services: language_service.Service_Catalog_Inspection
	services_ok, _ := language_service.service_catalog_inspect(
		&service_catalog,
		&before_services,
	)
	testing.expect(t, registry_ok && languages_ok && services_ok)

	candidate, prepared := runtime_catalog_prepare(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(RUNTIME_CATALOG_FIXTURE)),
		2,
	)
	testing.expect(t, prepared)
	if !prepared do return
	prepared_registry, prepared_ok := language_service.provider_registry_inspect(&registry)
	testing.expect(t, prepared_ok)
	testing.expect(t, candidate.new_definition_count > 0)
	testing.expect_value(
		t,
		prepared_registry.usage.service_definitions,
		before_registry.usage.service_definitions + u32(candidate.new_definition_count),
	)
	testing.expect(t, runtime_catalog_candidate_close(&candidate, &registry))
	after_registry, after_ok := language_service.provider_registry_inspect(&registry)
	after_languages, after_languages_ok, _ := language.language_catalog_inspect(&language_catalog)
	after_services: language_service.Service_Catalog_Inspection
	after_services_ok, _ := language_service.service_catalog_inspect(
		&service_catalog,
		&after_services,
	)
	testing.expect(t, after_ok && after_languages_ok && after_services_ok)
	testing.expect_value(t, after_registry.usage, before_registry.usage)
	testing.expect_value(t, after_languages.catalog_generation, before_languages.catalog_generation)
	testing.expect_value(t, after_services.catalog_generation, before_services.catalog_generation)
}

/* Verifies public support publishes atomically and reuses unchanged profiles. */
@(test)
runtime_catalog_publication_reuses_unchanged_profiles :: proc(t: ^testing.T) {
	language_catalog: language.Language_Catalog
	registry: language_service.Provider_Registry
	service_catalog: language_service.Service_Catalog
	factory, ready := runtime_catalog_test_init(
		&language_catalog,
		&registry,
		&service_catalog,
	)
	testing.expect(t, ready)
	if !ready do return
	defer language.language_catalog_close(&language_catalog)
	defer language_service.service_catalog_close(&service_catalog)
	defer language_service.provider_registry_close(&registry)

	first, first_prepared := runtime_catalog_prepare(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(RUNTIME_CATALOG_FIXTURE)),
		2,
	)
	testing.expect(t, first_prepared)
	if !first_prepared do return
	testing.expect(t, runtime_catalog_publish(&first, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&first, &registry))

	association, associated, _ := language.language_catalog_resolve(
		&language_catalog,
		"/work/main.rs",
	)
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
	definition, viewed, _ := language_service.provider_registry_definition(
		&registry,
		resolution.selected,
	)
	testing.expect(t, viewed)
	if !viewed do return
	testing.expect_value(t, definition.executable, "/bin/true")
	testing.expect_value(t, definition.arguments[0], "--stdio")
	testing.expect_value(t, definition.environment[0], "RUST_FIXTURE_TOKEN=redacted-value")
	testing.expect(t, strings.contains(definition.initialization_options, `"profile":"test"`))
	testing.expect(t, strings.contains(definition.client_settings, `"enabled":true`))
	testing.expect(t, language_service.Service_Feature.Diagnostics in definition.feature_policy)
	testing.expect(t, language_service.Service_Feature.Completion in definition.feature_policy)
	first_handle := resolution.selected
	racket_association, racket_associated, _ := language.language_catalog_resolve(
		&language_catalog,
		"/work/main.rkt",
	)
	testing.expect(t, racket_associated)
	if racket_associated {
		racket_resolution, racket_resolved, _ := language_service.service_catalog_resolve(
			&service_catalog,
			{
				language = racket_association.language,
				project_membership = "/work",
				resolved_root = "/work",
				project_trusted = true,
			},
		)
		testing.expect(t, racket_resolved)
		if racket_resolved {
			racket_definition, racket_viewed, _ := language_service.provider_registry_definition(
				&registry,
				racket_resolution.selected,
			)
			testing.expect(t, racket_viewed)
			if racket_viewed {
				testing.expect_value(t, racket_definition.executable, "racket")
				testing.expect_value(t, racket_definition.arguments[0], "-l")
				testing.expect_value(t, racket_definition.arguments[1], "racket-langserver")
				testing.expect_value(t, racket_definition.root_markers[0], "info.rkt")
			}
		}
	}
	go_association, go_associated, _ := language.language_catalog_resolve(
		&language_catalog,
		"/work/main.go",
	)
	testing.expect(t, go_associated)
	if go_associated {
		go_resolution, go_resolved, _ := language_service.service_catalog_resolve(
			&service_catalog,
			{
				language = go_association.language,
				project_membership = "/work",
				resolved_root = "/work",
				project_trusted = true,
			},
		)
		testing.expect(t, go_resolved)
		if go_resolved {
			go_definition, go_viewed, _ := language_service.provider_registry_definition(
				&registry,
				go_resolution.selected,
			)
			testing.expect(t, go_viewed)
			if go_viewed {
				testing.expect_value(t, go_definition.executable, "gopls")
				testing.expect_value(t, go_definition.arguments[0], "serve")
				testing.expect_value(t, go_definition.root_markers[0], "go.work")
				testing.expect_value(t, go_definition.root_markers[1], "go.mod")
				testing.expect(t, language_service.Service_Feature.Completion in go_definition.feature_policy)
				testing.expect(t, language_service.Service_Feature.Formatting in go_definition.feature_policy)
			}
		}
	}

	second, second_prepared := runtime_catalog_prepare(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(RUNTIME_CATALOG_FIXTURE)),
		3,
	)
	testing.expect(t, second_prepared)
	if !second_prepared do return
	testing.expect_value(t, len(runtime_catalog_candidate_retired_definitions(&second)), 0)
	testing.expect(t, runtime_catalog_publish(&second, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&second, &registry))
	association, associated, _ = language.language_catalog_resolve(
		&language_catalog,
		"/work/main.rs",
	)
	testing.expect(t, associated)
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
	testing.expect_value(t, resolution.selected, first_handle)

	changed, changed_prepared := runtime_catalog_prepare(
		&language_catalog,
		&registry,
		&service_catalog,
		factory,
		transmute([]u8)(string(RUNTIME_CATALOG_CHANGED_FIXTURE)),
		4,
	)
	testing.expect(t, changed_prepared)
	if !changed_prepared do return
	retired := runtime_catalog_candidate_retired_definitions(&changed)
	testing.expect_value(t, len(retired), 1)
	testing.expect_value(t, retired[0], first_handle)
	testing.expect(t, runtime_catalog_publish(&changed, &language_catalog, &service_catalog))
	testing.expect(t, runtime_catalog_candidate_close(&changed, &registry))
	association, associated, _ = language.language_catalog_resolve(
		&language_catalog,
		"/work/main.rs",
	)
	testing.expect(t, associated)
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
	testing.expect(t, resolution.selected != first_handle)
	discarded, _ := language_service.provider_registry_discard_definition(
		&registry,
		first_handle,
	)
	testing.expect(t, discarded)
	_, old_present, _ := language_service.provider_registry_definition(&registry, first_handle)
	testing.expect(t, !old_present)
}

@(private = "file")
runtime_catalog_test_init :: proc(
	language_catalog: ^language.Language_Catalog,
	registry: ^language_service.Provider_Registry,
	service_catalog: ^language_service.Service_Catalog,
) -> (language_service.Definition_Handle, bool) {
	language_ready, _ := language.language_catalog_init(language_catalog, 71)
	if !language_ready do return {}, false
	_, languages_confirmed, _ := language.factory_bundle_catalog_confirm(language_catalog)
	if !languages_confirmed do return {}, false
	registry_ready, _ := language_service.provider_registry_init(
		registry,
		{id = 73, generation = 1},
	)
	if !registry_ready do return {}, false
	factory, factory_ready, _ := language_service.provider_registry_register_factory_ols(registry)
	if !factory_ready do return {}, false
	service_ready, _ := language_service.service_catalog_init(
		service_catalog,
		79,
		{id = 73, generation = 1},
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
