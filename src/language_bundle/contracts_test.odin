// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_bundle

import "core:mem"
import "core:testing"

test_version :: Bundle_Version_Proposal{major = 1}
test_target :: Bundle_Target{platform = .Linux, architecture = .X86_64}

Test_Fixture :: struct {
	targets:        [1]Bundle_Target,
	dependency_facets: [1]Bundle_Contribution_Kind,
	dependencies:   [1]Bundle_Dependency_Proposal,
	artifact_targets: [1]Bundle_Target,
	artifacts:      [1]Bundle_Artifact_Proposal,
	languages:      [1]string,
	artifact_references: [1]string,
	dependency_references: [1]string,
	contribution_authorities: [1]Bundle_Authority,
	contributions:  [1]Bundle_Contribution_Proposal,
	authorities:    [1]Bundle_Authority,
}

test_proposal :: proc(fixture: ^Test_Fixture, provenance := "test provenance") -> Bundle_Proposal {
	fixture.targets = {test_target}
	fixture.dependency_facets = {.Service}
	fixture.dependencies = {{
		identity = "org.example.runtime",
		minimum = test_version,
		maximum = {major = 2},
		facets = fixture.dependency_facets[:],
	}}
	fixture.artifact_targets = {test_target}
	fixture.artifacts = {{
		identity = "grammar",
		kind = .Tree_Sitter_Grammar,
		path = "lib/language.so",
		targets = fixture.artifact_targets[:],
		authority = .Native_Grammar,
	}}
	fixture.languages = {"example"}
	fixture.artifact_references = {"grammar"}
	fixture.dependency_references = {"org.example.runtime"}
	fixture.contribution_authorities = {.Native_Grammar}
	fixture.contributions = {{
		kind = .Syntax_Provider,
		identity = "example-syntax",
		languages = fixture.languages[:],
		artifacts = fixture.artifact_references[:],
		dependencies = fixture.dependency_references[:],
		authorities = fixture.contribution_authorities[:],
	}}
	fixture.authorities = {.Native_Grammar}
	return Bundle_Proposal {
		format_version = BUNDLE_FORMAT_VERSION,
		identity = "org.example.language",
		display_name = "Example Language",
		version = test_version,
		api_range = {minimum = test_version, maximum = {major = 2}},
		description = "Example language support bundle.",
		publisher = "org.example",
		source = "catalog.example",
		provenance = provenance,
		targets = fixture.targets[:],
		dependencies = fixture.dependencies[:],
		authorities = fixture.authorities[:],
		contributions = fixture.contributions[:],
		artifacts = fixture.artifacts[:],
	}
}

/* Verifies native preparation copies borrowed bundle metadata and records. */
@(test)
bundle_contracts_copy_complete_candidate :: proc(t: ^testing.T) {
	fixture: Test_Fixture
	provenance: [18]u8
	copy(provenance[:], "mutable provenance")
	proposal := test_proposal(&fixture, string(provenance[:]))
	candidate, prepared, failure := bundle_candidate_prepare(proposal)
	testing.expectf(t, prepared, "candidate preparation failed with %v", failure.code)
	if !prepared do return
	bundle, present := bundle_candidate_bundle(&candidate)
	testing.expect(t, present)
	provenance[0] = 'M'
	testing.expect_value(t, provenance_text_view(&bundle.provenance), "mutable provenance")
	testing.expect_value(t, identity_text_view(&bundle.identity), "org.example.language")
	testing.expect(t, bundle_api_compatible(bundle, {major = 1, minor = 4}))
	artifact, artifact_present := bundle_candidate_artifact(&candidate, 0)
	testing.expect(t, artifact_present)
	testing.expect_value(t, path_text_view(&artifact.path), "lib/language.so")
	closed, close_failure := bundle_candidate_close(&candidate)
	testing.expectf(t, closed, "candidate cleanup failed with %v", close_failure.code)
}

/* Verifies unresolved contribution references never produce a native candidate. */
@(test)
bundle_contracts_reject_unknown_references :: proc(t: ^testing.T) {
	fixture: Test_Fixture
	proposal := test_proposal(&fixture)
	proposal.contributions[0].artifacts = {"missing"}
	candidate, prepared, failure := bundle_candidate_prepare(proposal)
	testing.expect(t, !prepared)
	testing.expect_value(t, candidate.state, rawptr(nil))
	testing.expect_value(t, failure.code, Bundle_Failure_Code.Unknown_Reference)
}

/* Verifies one admitted candidate releases its complete copied state exactly. */
@(test)
bundle_contracts_cleanup_is_exact :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	fixture: Test_Fixture
	candidate, prepared, failure := bundle_candidate_prepare(test_proposal(&fixture), allocator)
	testing.expectf(t, prepared, "candidate preparation failed with %v", failure.code)
	if prepared {
		closed, _ := bundle_candidate_close(&candidate)
		testing.expect(t, closed)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies target pairs and dependency ranges are structural boundaries. */
@(test)
bundle_contracts_reject_invalid_bounds :: proc(t: ^testing.T) {
	target_fixture: Test_Fixture
	invalid_target := test_proposal(&target_fixture)
	target_fixture.targets = {Bundle_Target{}}
	_, target_prepared, target_failure := bundle_candidate_prepare(invalid_target)
	testing.expect(t, !target_prepared)
	testing.expect_value(t, target_failure.field, Bundle_Field.Targets)
	range_fixture: Test_Fixture
	invalid_range := test_proposal(&range_fixture)
	invalid_range.dependencies[0].minimum = {major = 3}
	_, range_prepared, range_failure := bundle_candidate_prepare(invalid_range)
	testing.expect(t, !range_prepared)
	testing.expect_value(t, range_failure.field, Bundle_Field.Dependencies)
}
