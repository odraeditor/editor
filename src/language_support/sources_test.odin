// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_support

import "../language_service"
import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies maintained support uses the shared complete-source normalizer. */
@(test)
factory_support_source_normalizes :: proc(t: ^testing.T) {
	candidate, prepared := factory_source_prepare()
	testing.expect(t, prepared)
	if !prepared do return
	defer testing.expect(t, source_candidate_close(&candidate))
	languages, services, selections, counted := source_counts(&candidate)
	testing.expect(t, counted)
	testing.expect_value(t, languages, 9)
	testing.expect_value(t, services, 7)
	testing.expect_value(t, selections, 0)
	odin, viewed := source_language(&candidate, 0)
	testing.expect(t, viewed)
	testing.expect_value(t, odin.identity, "odin")
	javascript, javascript_viewed := source_language(&candidate, 5)
	typescript, typescript_viewed := source_language(&candidate, 6)
	html, html_viewed := source_language(&candidate, 7)
	css, css_viewed := source_language(&candidate, 8)
	testing.expect(t, javascript_viewed && typescript_viewed && html_viewed && css_viewed)
	if javascript_viewed do testing.expect_value(t, javascript.identity, "javascript")
	if typescript_viewed do testing.expect_value(t, typescript.identity, "typescript")
	if html_viewed do testing.expect_value(t, html.identity, "html")
	if css_viewed do testing.expect_value(t, css.identity, "css")
	ols, service_viewed := source_service(&candidate, 0)
	testing.expect(t, service_viewed)
	testing.expect_value(t, ols.identity, "ols")
	testing.expect_value(t, ols.source, language_service.Service_Contribution_Source.Factory)
	racket_server, racket_viewed := source_service(&candidate, 1)
	testing.expect(t, racket_viewed)
	if racket_viewed {
		testing.expect_value(t, racket_server.identity, language_service.FACTORY_RACKET_LANGUAGE_SERVER_IDENTITY)
		testing.expect_value(t, racket_server.command[0], "racket")
		testing.expect_value(t, racket_server.command[1], "-l")
		testing.expect_value(t, racket_server.command[2], "racket-langserver")
		testing.expect_value(t, racket_server.languages[0], "racket")
		testing.expect_value(t, racket_server.root_markers[0], "info.rkt")
		testing.expect_value(t, racket_server.feature_count, u8(11))
		testing.expect_value(t, racket_server.features[0], language_service.Service_Feature.Diagnostics)
		testing.expect_value(t, racket_server.features[1], language_service.Service_Feature.Completion)
	}
	go_server, go_viewed := source_service(&candidate, 2)
	testing.expect(t, go_viewed)
	if go_viewed {
		testing.expect_value(t, go_server.identity, language_service.FACTORY_GOPLS_IDENTITY)
		testing.expect_value(t, go_server.command[0], language_service.FACTORY_GOPLS_EXECUTABLE)
		testing.expect_value(t, go_server.command[1], "serve")
		testing.expect_value(t, go_server.languages[0], "go")
		testing.expect_value(t, go_server.root_markers[0], "go.work")
		testing.expect_value(t, go_server.root_markers[1], "go.mod")
		testing.expect_value(t, go_server.feature_count, u8(11))
	}
	rust_server, rust_viewed := source_service(&candidate, 3)
	testing.expect(t, rust_viewed)
	if rust_viewed {
		testing.expect_value(t, rust_server.identity, language_service.FACTORY_RUST_ANALYZER_IDENTITY)
		testing.expect_value(t, rust_server.command[0], language_service.FACTORY_RUST_ANALYZER_EXECUTABLE)
		testing.expect_value(t, rust_server.languages[0], "rust")
		testing.expect_value(t, rust_server.root_markers[0], "Cargo.toml")
		testing.expect_value(t, rust_server.feature_count, u8(11))
	}
	typescript_server, typescript_server_viewed := source_service(&candidate, 4)
	testing.expect(t, typescript_server_viewed)
	if typescript_server_viewed {
		testing.expect_value(t, typescript_server.identity, language_service.FACTORY_TYPESCRIPT_LANGUAGE_SERVER_IDENTITY)
		testing.expect_value(t, typescript_server.command[0], language_service.FACTORY_TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE)
		testing.expect_value(t, typescript_server.command[1], "--stdio")
		testing.expect_value(t, typescript_server.language_count, u8(2))
		testing.expect_value(t, typescript_server.languages[0], "javascript")
		testing.expect_value(t, typescript_server.languages[1], "typescript")
	}
	html_server, html_server_viewed := source_service(&candidate, 5)
	css_server, css_server_viewed := source_service(&candidate, 6)
	testing.expect(t, html_server_viewed && css_server_viewed)
	if html_server_viewed {
		testing.expect_value(t, html_server.identity, language_service.FACTORY_HTML_LANGUAGE_SERVER_IDENTITY)
		testing.expect_value(t, html_server.languages[0], "html")
	}
	if css_server_viewed {
		testing.expect_value(t, css_server.identity, language_service.FACTORY_CSS_LANGUAGE_SERVER_IDENTITY)
		testing.expect_value(t, css_server.languages[0], "css")
	}
}

/* Verifies personal, package, and trusted Project inputs keep source scope. */
@(test)
support_sources_preserve_scope :: proc(t: ^testing.T) {
	payload := transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION))
	personal, personal_ok := personal_source_prepare(payload, 2)
	testing.expect(t, personal_ok)
	if personal_ok {
		testing.expect_value(t, personal.descriptor.source, language_service.Service_Contribution_Source.Personal)
		testing.expect(t, source_candidate_close(&personal))
	}
	packaged_candidate, package_ok := package_fixture_prepare(
		payload,
		"fixture.racket",
		3,
	)
	testing.expect(t, package_ok)
	if package_ok {
		testing.expect_value(t, packaged_candidate.descriptor.scope, "fixture.racket")
		testing.expect(t, source_candidate_close(&packaged_candidate))
	}
	project, project_ok := project_source_prepare(payload, "/work", 4, true)
	testing.expect(t, project_ok)
	if project_ok {
		testing.expect_value(t, project.descriptor.scope_kind, language_service.Service_Scope_Kind.Project_Membership)
		testing.expect(t, source_candidate_close(&project))
	}
	_, untrusted := project_source_prepare(payload, "/work", 4, false)
	testing.expect(t, !untrusted)
}

/* Verifies one prepared source is a complete replacement, not a field patch. */
@(test)
support_source_replacement_is_complete :: proc(t: ^testing.T) {
	first, first_ok := personal_source_prepare(
		transmute([]u8)(string(FACTORY_LANGUAGE_SUPPORT_CONFIGURATION)),
		2,
	)
	second, second_ok := personal_source_prepare(
		transmute([]u8)(string(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)),
		3,
	)
	testing.expect(t, first_ok)
	testing.expect(t, second_ok)
	if !first_ok || !second_ok do return
	defer source_candidate_close(&first)
	defer source_candidate_close(&second)
	first_languages, first_services, _, _ := source_counts(&first)
	second_languages, second_services, _, _ := source_counts(&second)
	testing.expect_value(t, first_languages, 9)
	testing.expect_value(t, first_services, 7)
	testing.expect_value(t, second_languages, 0)
	testing.expect_value(t, second_services, 0)
}

/* Verifies allocation faults and ordinary close retain no source storage. */
@(test)
support_source_faults_clean_up_exactly :: proc(t: ^testing.T) {
	baseline_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&baseline_tracking, context.allocator)
	counting := Source_Test_Failing_Allocator {
		backing = mem.tracking_allocator(&baseline_tracking),
		fail_after = max(u64),
	}
	baseline, baseline_ok := factory_source_prepare(source_test_failing_allocator(&counting))
	testing.expect(t, baseline_ok)
	if baseline_ok do testing.expect(t, source_candidate_close(&baseline))
	allocation_attempts := counting.successful_allocations
	baseline_retained := baseline_tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&baseline_tracking)
	testing.expect_value(t, baseline_retained, i64(0))

	for fail_after in 0 ..< int(allocation_attempts) {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Source_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		candidate, prepared := factory_source_prepare(source_test_failing_allocator(&failing))
		if prepared do testing.expect(t, source_candidate_close(&candidate))
		retained := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		testing.expect_value(t, retained, i64(0))
	}
}

@(private = "file")
Source_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
source_test_failing_allocator :: proc(data: ^Source_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = source_test_failing_allocator_proc, data = data}
}

@(private = "file")
source_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Source_Test_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
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
