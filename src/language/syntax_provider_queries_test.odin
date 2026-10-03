// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:os"
import "core:testing"

@(test)
/* syntax_provider_queries_compile_verified_data_and_normalize_captures verifies query compilation. */
syntax_provider_queries_compile_verified_data_and_normalize_captures :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	runtime: Syntax_Provider_Runtime
	loaded, _ := syntax_provider_load(&runtime, &record, 1)
	testing.expect(t, loaded)
	defer syntax_provider_close(&runtime)

	compiled, failure := syntax_provider_compile_queries(&runtime)
	testing.expect(t, compiled)
	testing.expect_value(t, failure.code, Failure_Code.None)
	inspection, inspected := syntax_provider_inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.query_bytes, record.queries[0].size)

	mapping, mapped := syntax_provider_capture_mapping(&record, "function")
	testing.expect(t, mapped)
	testing.expect_value(t, mapping.role, Syntax_Role.Function)
	mapping, mapped = syntax_provider_capture_mapping(&record, "function.call.member")
	testing.expect(t, mapped)
	testing.expect_value(t, mapping.structural_role, Syntax_Structural_Role.Definition)
	_, mapped = syntax_provider_capture_mapping(&record, "unknown.capture")
	testing.expect(t, !mapped)
}

@(test)
/* syntax_provider_query_failure_preserves_compiled_state verifies atomic query replacement. */
syntax_provider_query_failure_preserves_compiled_state :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	runtime: Syntax_Provider_Runtime
	loaded, _ := syntax_provider_load(&runtime, &record, 1)
	testing.expect(t, loaded)
	defer syntax_provider_close(&runtime)
	compiled, _ := syntax_provider_compile_queries(&runtime)
	testing.expect(t, compiled)
	confirmed_bytes := runtime.query_bytes

	malformed_bytes, read_error := os.read_entire_file(ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(malformed_bytes)
	runtime.record.queries[0].path = syntax_artifact_path_copy(ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY)
	runtime.record.queries[0].digest = syntax_bytes_digest(malformed_bytes)
	runtime.record.queries[0].size = u64(len(malformed_bytes))
	failure: Failure
	compiled, failure = syntax_provider_compile_queries(&runtime)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Query)
	testing.expect_value(t, runtime.query_bytes, confirmed_bytes)
	stats, inspected, _ := tree_sitter_owner_stats(&runtime.owner)
	testing.expect(t, inspected && stats.has_query)
}

@(test)
/* syntax_provider_queries_enforce_resource_and_cancellation_limits verifies bounded compilation. */
syntax_provider_queries_enforce_resource_and_cancellation_limits :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	runtime: Syntax_Provider_Runtime
	loaded, _ := syntax_provider_load(&runtime, &record, 1)
	testing.expect(t, loaded)
	defer syntax_provider_close(&runtime)

	runtime.record.resources.query_bytes = runtime.record.queries[0].size - 1
	compiled, failure := syntax_provider_compile_queries(&runtime)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, Failure_Code.Artifact_Size_Mismatch)

	runtime.record.resources.query_bytes = MAX_QUERY_BYTES
	cancelled := true
	compiled, failure = syntax_provider_compile_queries(
		&runtime,
		context.allocator,
		Syntax_Provider_Cancellation {user_data = &cancelled, check = syntax_provider_test_cancelled},
	)
	testing.expect(t, !compiled)
	testing.expect_value(t, failure.code, Failure_Code.Cancelled)
}

@(test)
/* syntax_provider_queries_publish_generic_semantics_and_structure verifies normalized output. */
syntax_provider_queries_publish_generic_semantics_and_structure :: proc(t: ^testing.T) {
	record := syntax_provider_loader_test_record(t)
	runtime: Syntax_Provider_Runtime
	loaded, _ := syntax_provider_load(&runtime, &record, 1)
	testing.expect(t, loaded)
	if !loaded do return
	defer syntax_provider_close(&runtime)
	compiled, _ := syntax_provider_compile_queries(&runtime)
	testing.expect(t, compiled)
	if !compiled do return

	contents := "package demo\nmain :: proc() {}\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		801,
		contents,
		editor.Allocator_Set {persistent = context.allocator, temporary = context.temp_allocator},
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
		registry_id = 9,
		language_id = record.language.id,
		provider_id = 7,
		provider_generation = 1,
	}
	_, parsed, _ := tree_sitter_owner_parse_snapshot(
		&runtime.owner,
		&snapshot,
		record.language,
		provider,
		1,
		1,
	)
	testing.expect(t, parsed)
	first, queried, failure := tree_sitter_owner_query_spans(
		&runtime.owner,
		&snapshot,
		0,
		u64(len(contents)),
		0,
		1,
	)
	testing.expectf(t, queried, "generic query failed with %v", failure.code)
	if !queried do return
	testing.expect(t, len(first.spans) > 0 && len(first.structures) > 0)
	for span in first.spans do testing.expect_value(t, span.role, Syntax_Role.Function)
	for projection in first.structures {
		testing.expect_value(t, projection.role, Syntax_Structural_Role.Definition)
		testing.expect_value(t, projection.provider, provider)
		testing.expect_value(t, projection.source_revision, editor.Revision(0))
	}
	testing.expect_value(t, first.snapshot.structural_count, u32(len(first.structures)))
	syntax_query_result_close(&first)

	runtime.record.mappings[0].role = .Constructor
	runtime.record.mappings[0].structural_role = .Declaration
	runtime.record.mappings[0].precedence = 201
	runtime.record.queries[0].generation = 2
	compiled, _ = syntax_provider_compile_queries(&runtime)
	testing.expect(t, compiled)
	provider.provider_generation = 2
	_, parsed, _ = tree_sitter_owner_parse_snapshot(
		&runtime.owner,
		&snapshot,
		record.language,
		provider,
		2,
		2,
	)
	testing.expect(t, parsed)
	second: Syntax_Query_Result
	second, queried, failure = tree_sitter_owner_query_spans(
		&runtime.owner,
		&snapshot,
		0,
		u64(len(contents)),
		0,
		2,
	)
	testing.expectf(t, queried, "replacement query failed with %v", failure.code)
	if !queried do return
	defer syntax_query_result_close(&second)
	for span in second.spans {
		testing.expect_value(t, span.role, Syntax_Role.Constructor)
		testing.expect_value(t, span.provider, provider)
	}
	for projection in second.structures {
		testing.expect_value(t, projection.role, Syntax_Structural_Role.Declaration)
		testing.expect_value(t, projection.provider, provider)
	}
}
