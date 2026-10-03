// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:os"
import "core:testing"

/* ODRA_EXTERNAL_BUNDLE_GRAMMAR selects the conformance fixture grammar artifact. */
ODRA_EXTERNAL_BUNDLE_GRAMMAR :: #config(
	ODRA_EXTERNAL_BUNDLE_GRAMMAR,
	"../../.build/syntax-provider-fixture/libtree-sitter-odin.so",
)

/* ODRA_EXTERNAL_BUNDLE_QUERY selects the conformance fixture highlight query. */
ODRA_EXTERNAL_BUNDLE_QUERY :: #config(
	ODRA_EXTERNAL_BUNDLE_QUERY,
	"../../tests/language_bundle_fixture/queries/highlights.scm",
)

/* Verifies a non-Factory language loads syntax from verified external artifacts. */
@(test)
external_bundle_conformance_loads_uncompiled_language :: proc(t: ^testing.T) {
	grammar, grammar_error := os.read_entire_file(ODRA_EXTERNAL_BUNDLE_GRAMMAR, context.allocator)
	testing.expect(t, grammar_error == nil)
	if grammar_error != nil do return
	defer delete(grammar)
	query, query_error := os.read_entire_file(ODRA_EXTERNAL_BUNDLE_QUERY, context.allocator)
	testing.expect(t, query_error == nil)
	if query_error != nil do return
	defer delete(query)

	language_name: Language_Name
	copy(language_name.bytes[:], "quill")
	language_name.length = 5
	queries := [1]Syntax_Query_Artifact_Proposal {{
		kind = .Highlights,
		path = ODRA_EXTERNAL_BUNDLE_QUERY,
		digest = syntax_bytes_digest(query),
		size = u64(len(query)),
		generation = 1,
	}}
	mappings := [1]Syntax_Capture_Mapping_Proposal {{
		capture = "variable",
		role = .Variable,
		precedence = 100,
	}}
	proposal := Syntax_Provider_Proposal {
		identity = "quill.syntax",
		language = {id = 10, generation = 1, name = language_name},
		grammar = {
			path = ODRA_EXTERNAL_BUNDLE_GRAMMAR,
			digest = syntax_bytes_digest(grammar),
			size = u64(len(grammar)),
			platform = .Linux,
			architecture = .X86_64,
			entrypoint = "tree_sitter_odin",
			minimum_abi = 13,
			maximum_abi = 15,
			minimum_language_version = 13,
			maximum_language_version = 15,
		},
		queries = queries[:],
		mappings = mappings[:],
		resources = {
			query_bytes = MAX_QUERY_BYTES,
			captures = MAX_CAPTURES,
			spans = MAX_SYNTAX_SPANS,
			temporary_bytes = MAX_TEMPORARY_BYTES,
			work_bytes = REFRESH_WORK_BYTES,
		},
		authority = {
			trusted_publisher = true,
			trusted_source = true,
			user_confirmed = true,
			native_grammar_grant = true,
		},
	}
	record, prepared, failure := syntax_provider_prepare(proposal)
	testing.expectf(t, prepared, "external provider preparation failed with %v", failure.code)
	if !prepared do return
	runtime: Syntax_Provider_Runtime
	loaded, load_failure := syntax_provider_load(&runtime, &record, 1)
	testing.expectf(t, loaded, "external provider load failed with %v", load_failure.code)
	if !loaded do return
	defer syntax_provider_close(&runtime)
	compiled, compile_failure := syntax_provider_compile_queries(&runtime)
	testing.expectf(t, compiled, "external query compile failed with %v", compile_failure.code)
	if !compiled do return

	contents := "package quill\nmain :: proc() { value := 1 }\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		1401,
		contents,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	provider := Provider_Handle {
		registry_id = 41,
		language_id = record.language.id,
		provider_id = 1,
		provider_generation = 1,
	}
	_, parsed, parse_failure := tree_sitter_owner_parse_snapshot(
		&runtime.owner,
		&snapshot,
		record.language,
		provider,
		1,
		1,
	)
	testing.expectf(t, parsed, "external source parse failed with %v", parse_failure.code)
	if !parsed do return
	result, queried, query_failure := tree_sitter_owner_query_spans(
		&runtime.owner,
		&snapshot,
		0,
		u64(len(contents)),
		0,
		1,
	)
	testing.expectf(t, queried, "external syntax query failed with %v", query_failure.code)
	if !queried do return
	defer syntax_query_result_close(&result)
	testing.expect(t, len(result.spans) > 0)
	for span in result.spans {
		testing.expect_value(t, span.role, Syntax_Role.Variable)
		testing.expect_value(t, span.provider, provider)
	}

	tampered := record
	tampered.grammar.digest[0] = tampered.grammar.digest[0] ~ 0xff
	replacement, replacement_failure := syntax_provider_replace(&runtime, &tampered, 2)
	testing.expect(t, !replacement)
	testing.expect_value(t, replacement_failure.code, Failure_Code.Artifact_Digest_Mismatch)
	inspection, inspected := syntax_provider_inspect(&runtime)
	testing.expect(t, inspected && inspection.parser_ready)
}
