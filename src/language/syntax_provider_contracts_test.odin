// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

@(test)
/* syntax_provider_contract_copies_bounded_manifest_data verifies proposal ownership. */
syntax_provider_contract_copies_bounded_manifest_data :: proc(t: ^testing.T) {
	fixture: Syntax_Provider_Test_Fixture
	syntax_provider_test_fixture_init(&fixture)
	proposal := fixture.proposal
	record, ok, failure := syntax_provider_prepare(proposal)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, syntax_provider_text_view(&record.identity), "org.odra.odin-syntax")
	testing.expect_value(t, syntax_artifact_path_view(&record.grammar.path), "/store/grammar.so")
	testing.expect_value(t, syntax_entrypoint_view(&record.grammar.entrypoint), "tree_sitter_odin")
	testing.expect_value(t, record.query_count, u8(1))
	testing.expect_value(t, record.mapping_count, u16(1))
	testing.expect_value(t, syntax_capture_name_view(&record.mappings[0].capture), "function")
	testing.expect(t, syntax_native_authority_granted(record.authority))

	proposal.identity = "mutated"
	proposal.queries[0].path = "/mutated"
	testing.expect_value(t, syntax_provider_text_view(&record.identity), "org.odra.odin-syntax")
	testing.expect_value(t, syntax_artifact_path_view(&record.queries[0].path), "/store/highlights.scm")
}

@(test)
/* syntax_provider_contract_rejects_unsafe_and_ambiguous_inputs verifies contract rejection. */
syntax_provider_contract_rejects_unsafe_and_ambiguous_inputs :: proc(t: ^testing.T) {
	fixture: Syntax_Provider_Test_Fixture
	syntax_provider_test_fixture_init(&fixture)
	proposal := fixture.proposal
	proposal.grammar.path = "relative/grammar.so"
	_, ok, failure := syntax_provider_prepare(proposal)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Grammar_Artifact)

	syntax_provider_test_fixture_init(&fixture)
	proposal = fixture.proposal
	duplicate_queries := [2]Syntax_Query_Artifact_Proposal {proposal.queries[0], proposal.queries[0]}
	proposal.queries = duplicate_queries[:]
	_, ok, failure = syntax_provider_prepare(proposal)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Duplicate_Query_Kind)

	syntax_provider_test_fixture_init(&fixture)
	proposal = fixture.proposal
	duplicate_mappings := [2]Syntax_Capture_Mapping_Proposal {proposal.mappings[0], proposal.mappings[0]}
	proposal.mappings = duplicate_mappings[:]
	_, ok, failure = syntax_provider_prepare(proposal)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Duplicate_Capture_Mapping)
}

@(test)
/* syntax_provider_authority_requires_factory_or_complete_trust verifies the native trust boundary. */
syntax_provider_authority_requires_factory_or_complete_trust :: proc(t: ^testing.T) {
	testing.expect(t, syntax_native_authority_granted(Syntax_Native_Authority {
		factory_artifact = true,
		native_grammar_grant = true,
	}))
	testing.expect(t, syntax_native_authority_granted(Syntax_Native_Authority {
		trusted_publisher = true,
		trusted_source = true,
		user_confirmed = true,
		native_grammar_grant = true,
	}))
	testing.expect(t, !syntax_native_authority_granted(Syntax_Native_Authority {
		trusted_publisher = true,
		trusted_source = true,
		native_grammar_grant = true,
	}))
}

/* Syntax_Provider_Test_Fixture owns reusable provider proposal test data. */
Syntax_Provider_Test_Fixture :: struct {
	proposal: Syntax_Provider_Proposal,
	queries:  [1]Syntax_Query_Artifact_Proposal,
	mappings: [1]Syntax_Capture_Mapping_Proposal,
}

/* syntax_provider_test_fixture_init resets one fixture to a valid baseline. */
syntax_provider_test_fixture_init :: proc(fixture: ^Syntax_Provider_Test_Fixture) {
	fixture^ = {}
	digest: [32]u8
	digest[0] = 1
	fixture.queries[0] = {
		kind = .Highlights,
		path = "/store/highlights.scm",
		digest = digest,
		size = 42,
		generation = 1,
	}
	fixture.mappings[0] = {
		capture = "function",
		role = .Function,
		structural_role = .Definition,
		precedence = 100,
	}
	language_name: Language_Name
	copy(language_name.bytes[:], "odin")
	language_name.length = 4
	fixture.proposal = Syntax_Provider_Proposal {
		identity = "org.odra.odin-syntax",
		language = Language_Identity {id = 1, generation = 1, name = language_name},
		grammar = {
			path = "/store/grammar.so",
			digest = digest,
			size = 1024,
			platform = .Linux,
			architecture = .X86_64,
			entrypoint = "tree_sitter_odin",
			minimum_abi = 13,
			maximum_abi = 15,
			minimum_language_version = 13,
			maximum_language_version = 15,
		},
		queries = fixture.queries[:],
		mappings = fixture.mappings[:],
		resources = {
			query_bytes = MAX_QUERY_BYTES,
			captures = MAX_CAPTURES,
			spans = MAX_SYNTAX_SPANS,
			temporary_bytes = MAX_TEMPORARY_BYTES,
			work_bytes = REFRESH_WORK_BYTES,
		},
		authority = {factory_artifact = true, native_grammar_grant = true},
	}
}
