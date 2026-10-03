// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:os"
import "core:testing"

/* ODRA_SYNTAX_PROVIDER_FIXTURE selects the loader test grammar artifact. */
ODRA_SYNTAX_PROVIDER_FIXTURE :: #config(
	ODRA_SYNTAX_PROVIDER_FIXTURE,
	"../../.build/syntax-provider-fixture/libtree-sitter-odin.so",
)

/* ODRA_SYNTAX_PROVIDER_FIXTURE_LINK selects the rejected symbolic-link fixture. */
ODRA_SYNTAX_PROVIDER_FIXTURE_LINK :: #config(
	ODRA_SYNTAX_PROVIDER_FIXTURE_LINK,
	"../../.build/syntax-provider-fixture/libtree-sitter-odin-link.so",
)

/* ODRA_SYNTAX_PROVIDER_QUERY selects the loader test highlight query. */
ODRA_SYNTAX_PROVIDER_QUERY :: #config(
	ODRA_SYNTAX_PROVIDER_QUERY,
	"../../third_party/tree-sitter-odin/1.3.0/queries/highlights.scm",
)

/* ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY selects malformed query test data. */
ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY :: #config(
	ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY,
	"../../tests/syntax_provider_fixture/malformed.scm",
)

@(test)
/* syntax_provider_loader_verifies_and_owns_dynamic_grammar verifies native ownership. */
syntax_provider_loader_verifies_and_owns_dynamic_grammar :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	runtime: Syntax_Provider_Runtime
	loaded, failure := syntax_provider_load(&runtime, &record, 1)
	testing.expect(t, loaded)
	testing.expect_value(t, failure.code, Failure_Code.None)
	inspection, inspected := syntax_provider_inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Syntax_Provider_Status.Loaded)
	testing.expect(t, inspection.parser_ready)
	testing.expect(t, inspection.library_owned)
	testing.expect_value(t, inspection.grammar_abi, u32(14))

	closed, close_failure := syntax_provider_close(&runtime)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	inspection, inspected = syntax_provider_inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Syntax_Provider_Status.Closed)
	testing.expect(t, !inspection.library_owned)
}

@(test)
/* syntax_provider_loader_rejects_authority_target_integrity_symbol_and_versions verifies loader boundaries. */
syntax_provider_loader_rejects_authority_target_integrity_symbol_and_versions :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)

	unauthorized := record
	unauthorized.authority = {}
	syntax_provider_expect_load_failure(t, &unauthorized, .Native_Grammar_Unauthorized)

	unsupported := record
	unsupported.grammar.architecture = .Aarch64
	syntax_provider_expect_load_failure(t, &unsupported, .Unsupported_Platform)

	tampered := record
	tampered.grammar.digest[0] = tampered.grammar.digest[0] ~ 0xff
	syntax_provider_expect_load_failure(t, &tampered, .Artifact_Digest_Mismatch)

	missing_symbol := record
	missing_symbol.grammar.entrypoint = syntax_entrypoint_copy("tree_sitter_missing")
	syntax_provider_expect_load_failure(t, &missing_symbol, .Grammar_Symbol_Missing)

	wrong_abi := record
	wrong_abi.grammar.minimum_abi = 15
	syntax_provider_expect_load_failure(t, &wrong_abi, .Grammar_ABI_Incompatible)

	wrong_language_version := record
	wrong_language_version.grammar.minimum_language_version = 15
	syntax_provider_expect_load_failure(t, &wrong_language_version, .Grammar_Language_Version_Incompatible)
}

@(test)
/* syntax_provider_loader_preserves_active_runtime_on_failed_replacement verifies atomic replacement. */
syntax_provider_loader_preserves_active_runtime_on_failed_replacement :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	active: Syntax_Provider_Runtime
	loaded, _ := syntax_provider_load(&active, &record, 1)
	testing.expect(t, loaded)

	rejected := record
	rejected.grammar.digest[1] = rejected.grammar.digest[1] ~ 0xff
	replaced, failure := syntax_provider_replace(&active, &rejected, 2)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.code, Failure_Code.Artifact_Digest_Mismatch)
	inspection, inspected := syntax_provider_inspect(&active)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Syntax_Provider_Status.Loaded)
	testing.expect(t, inspection.parser_ready && inspection.library_owned)

	replaced, failure = syntax_provider_replace(&active, &record, 2)
	testing.expect(t, replaced)
	testing.expect_value(t, failure.code, Failure_Code.None)
	inspection, inspected = syntax_provider_inspect(&active)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Syntax_Provider_Status.Loaded)
	_, _ = syntax_provider_close(&active)
}

@(test)
/* syntax_provider_loader_contains_missing_size_cancellation_and_allocation_failures verifies contained failures. */
syntax_provider_loader_contains_missing_size_cancellation_and_allocation_failures :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	missing := record
	missing.grammar.path = syntax_artifact_path_copy("/definitely/missing/odra-grammar.so")
	syntax_provider_expect_load_failure(t, &missing, .Artifact_Missing)

	wrong_size := record
	wrong_size.grammar.size += 1
	syntax_provider_expect_load_failure(t, &wrong_size, .Artifact_Size_Mismatch)

	linked := record
	linked.grammar.path = syntax_artifact_path_copy(ODRA_SYNTAX_PROVIDER_FIXTURE_LINK)
	syntax_provider_expect_load_failure(t, &linked, .Artifact_Missing)

	cancelled := true
	runtime: Syntax_Provider_Runtime
	loaded, failure := syntax_provider_load(
		&runtime,
		&record,
		1,
		context.allocator,
		Syntax_Provider_Cancellation {user_data = &cancelled, check = syntax_provider_test_cancelled},
	)
	testing.expect(t, !loaded)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)

	failing := Tree_Sitter_Test_Failing_Allocator {backing = context.allocator, fail_after = 0}
	runtime = {}
	loaded, failure = syntax_provider_load(
		&runtime,
		&record,
		1,
		tree_sitter_test_failing_allocator(&failing),
	)
	testing.expect(t, !loaded)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
}

@(test)
/* syntax_provider_reload_and_cleanup_are_exact verifies repeated native cleanup. */
syntax_provider_reload_and_cleanup_are_exact :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	for generation in 1 ..= 8 {
		runtime: Syntax_Provider_Runtime
		loaded, _ := syntax_provider_load(&runtime, &record, Parser_Generation(generation))
		testing.expect(t, loaded)
		compiled, _ := syntax_provider_compile_queries(&runtime)
		testing.expect(t, compiled)
		closed, failure := syntax_provider_close(&runtime)
		testing.expect(t, closed)
		testing.expect_value(t, failure.code, Failure_Code.None)
		inspection, inspected := syntax_provider_inspect(&runtime)
		testing.expect(t, inspected)
		testing.expect_value(t, inspection.status, Syntax_Provider_Status.Closed)
		testing.expect(t, !inspection.library_owned && !inspection.parser_ready)
	}
}

/* syntax_provider_test_cancelled reads the loader fixture cancellation flag. */
syntax_provider_test_cancelled :: proc "odin" (user_data: rawptr) -> bool {
	return user_data != nil && (cast(^bool)user_data)^
}

/* syntax_provider_expect_load_failure verifies one exact contained loader failure. */
syntax_provider_expect_load_failure :: proc(
	t: ^testing.T,
	record: ^Syntax_Provider_Record,
	expected: Failure_Code,
) {
	runtime: Syntax_Provider_Runtime
	loaded, failure := syntax_provider_load(&runtime, record, 1)
	testing.expect(t, !loaded)
	testing.expect_value(t, failure.code, expected)
	inspection, inspected := syntax_provider_inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.status, Syntax_Provider_Status.Failed)
	testing.expect(t, !inspection.library_owned)
}

/* syntax_provider_loader_test_record prepares a record from the built fixtures. */
syntax_provider_loader_test_record :: proc(t: ^testing.T) -> Syntax_Provider_Record {
	bytes, read_error := os.read_entire_file(ODRA_SYNTAX_PROVIDER_FIXTURE, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(bytes)
	fixture: Syntax_Provider_Test_Fixture
	syntax_provider_test_fixture_init(&fixture)
	fixture.proposal.grammar.path = ODRA_SYNTAX_PROVIDER_FIXTURE
	fixture.proposal.grammar.digest = syntax_bytes_digest(bytes)
	fixture.proposal.grammar.size = u64(len(bytes))
	query_bytes, query_error := os.read_entire_file(ODRA_SYNTAX_PROVIDER_QUERY, context.allocator)
	testing.expect(t, query_error == nil)
	defer delete(query_bytes)
	fixture.queries[0].path = ODRA_SYNTAX_PROVIDER_QUERY
	fixture.queries[0].digest = syntax_bytes_digest(query_bytes)
	fixture.queries[0].size = u64(len(query_bytes))
	record, prepared, failure := syntax_provider_prepare(fixture.proposal)
	testing.expect(t, prepared)
	testing.expect_value(t, failure.code, Failure_Code.None)
	return record
}
