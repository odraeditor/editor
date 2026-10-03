// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package extension

import "core:testing"

@(private = "file")
PACKAGE_CONTRIBUTION_PAYLOAD :: `{"languages":[],"schema":1,"selections":[],"services":[]}`

@(private = "file")
PACKAGE_CONTRIBUTION_FACETS := [6]Contribution_Facet{
	.Language,
	.Language_Service,
	.Syntax,
	.Formatter,
	.Commands,
	.Theme,
}

@(private = "file")
PACKAGE_CONTRIBUTION_LANGUAGES := [2]string{"racket", "scheme"}

@(private = "file")
PACKAGE_CONTRIBUTION_PLATFORMS := [2]Package_Platform{.Linux, .Darwin}

@(private = "file")
PACKAGE_CONTRIBUTION_ARCHITECTURES := [2]Package_Architecture{.X86_64, .AArch64}

@(private = "file")
PACKAGE_CONTRIBUTION_AUTHORITIES := [4]Package_Authority{
	.Inspect,
	.Filesystem_Read,
	.Process,
	.Environment,
}

@(private = "file")
package_contribution_fixture :: proc() -> Package_Language_Support_Proposal {
	return {
		package_identity = "org.example.racket-tools",
		generation = 7,
		payload = transmute([]u8)(string(PACKAGE_CONTRIBUTION_PAYLOAD)),
		facets = PACKAGE_CONTRIBUTION_FACETS[:],
		affected_languages = PACKAGE_CONTRIBUTION_LANGUAGES[:],
		platforms = PACKAGE_CONTRIBUTION_PLATFORMS[:],
		architectures = PACKAGE_CONTRIBUTION_ARCHITECTURES[:],
		authorities = PACKAGE_CONTRIBUTION_AUTHORITIES[:],
		executable_artifact = "/packages/racket-tools/bin/server",
		provenance = "Fixture package catalog",
	}
}

/* Verifies one payload derives every transverse discovery dimension. */
@(test)
package_language_support_derives_transverse_facets :: proc(t: ^testing.T) {
	proposal := package_contribution_fixture()
	candidate, prepared, failure := package_language_support_prepare(proposal)
	testing.expectf(t, prepared, "package preparation failed: %v", failure.code)
	if !prepared do return
	defer testing.expect(t, package_language_support_close(&candidate))
	discovery, discovered := package_language_support_discovery(&candidate)
	testing.expect(t, discovered)
	testing.expect_value(t, package_identity_text_view(&discovery.package_identity), proposal.package_identity)
	testing.expect(t, .Language in discovery.facets)
	testing.expect(t, .Language_Service in discovery.facets)
	testing.expect(t, .Syntax in discovery.facets)
	testing.expect(t, .Formatter in discovery.facets)
	testing.expect(t, .Commands in discovery.facets)
	testing.expect(t, .Theme in discovery.facets)
	testing.expect(t, .Linux in discovery.platforms)
	testing.expect(t, .Darwin in discovery.platforms)
	testing.expect(t, .X86_64 in discovery.architectures)
	testing.expect(t, .AArch64 in discovery.architectures)
	testing.expect(t, .Inspect in discovery.authorities)
	testing.expect(t, .Process in discovery.authorities)
	testing.expect_value(t, discovery.affected_language_count, u8(2))
	testing.expect_value(t, language_identity_text_view(&discovery.affected_languages[0]), "racket")
	testing.expect_value(t, language_identity_text_view(&discovery.affected_languages[1]), "scheme")
	testing.expect_value(t, package_executable_artifact_view(&discovery), proposal.executable_artifact)
}

/* Verifies classification is independent from manifest list order. */
@(test)
package_language_support_classification_is_order_independent :: proc(t: ^testing.T) {
	first_proposal := package_contribution_fixture()
	second_proposal := package_contribution_fixture()
	second_proposal.facets = {.Theme, .Commands, .Formatter, .Syntax, .Language_Service, .Language}
	second_proposal.affected_languages = {"scheme", "racket"}
	second_proposal.platforms = {.Darwin, .Linux}
	second_proposal.architectures = {.AArch64, .X86_64}
	second_proposal.authorities = {.Environment, .Process, .Filesystem_Read, .Inspect}
	first, first_ok, _ := package_language_support_prepare(first_proposal)
	second, second_ok, _ := package_language_support_prepare(second_proposal)
	testing.expect(t, first_ok && second_ok)
	if !first_ok || !second_ok do return
	defer package_language_support_close(&first)
	defer package_language_support_close(&second)
	testing.expect_value(t, first.descriptor, second.descriptor)
}

/* Verifies discovery metadata cannot bypass package authority or structural bounds. */
@(test)
package_language_support_rejects_invalid_authority_and_metadata :: proc(t: ^testing.T) {
	proposal := package_contribution_fixture()
	proposal.authorities = {.Inspect, .Filesystem_Read}
	_, prepared, failure := package_language_support_prepare(proposal)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Package_Contribution_Failure_Code.Authority)

	proposal = package_contribution_fixture()
	proposal.facets = {.Language, .Language}
	_, prepared, failure = package_language_support_prepare(proposal)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Package_Contribution_Failure_Code.Facet)

	proposal = package_contribution_fixture()
	proposal.executable_artifact = "relative/server"
	_, prepared, failure = package_language_support_prepare(proposal)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Package_Contribution_Failure_Code.Executable_Artifact)
}
