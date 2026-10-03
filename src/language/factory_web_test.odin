// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../transaction"
import "core:strings"
import "core:testing"

/* Verifies a Unicode TSX edit matches a clean parse of the resulting revision. */
@(test)
factory_web_incremental_tsx_matches_full_parse :: proc(t: ^testing.T) {
	base := "const View = (): JSX.Element => <main title=\"héllo\">λ</main>;\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer, 940, base,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	base_snapshot: editor.Buffer_Snapshot
	base_opened, _ := editor.buffer_snapshot_open(&buffer, &base_snapshot)
	testing.expect(t, base_opened)
	if !base_opened do return
	defer editor.buffer_snapshot_close(&base_snapshot)
	identity := factory_bundle_language_identity(FACTORY_TYPESCRIPT_LANGUAGE_ID, "typescript")
	provider := Provider_Handle {
		registry_id = 1, language_id = FACTORY_TYPESCRIPT_LANGUAGE_ID,
		provider_id = 1, provider_generation = 1,
	}
	incremental_owner: Tree_Sitter_Owner
	owner_ready, _ := tree_sitter_owner_init_factory(
		&incremental_owner, FACTORY_TYPESCRIPT_TSX_IDENTITY, 1,
	)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer tree_sitter_owner_close(&incremental_owner)
	query_ready, _ := tree_sitter_owner_compile_factory_query(
		&incremental_owner, FACTORY_TYPESCRIPT_TSX_IDENTITY, 1,
	)
	testing.expect(t, query_ready)
	_, parsed, _ := tree_sitter_owner_parse_snapshot(
		&incremental_owner, &base_snapshot, identity, provider, 1, 1,
	)
	testing.expect(t, parsed)
	offset := strings.index(base, "héllo")
	testing.expect(t, offset >= 0)
	if offset < 0 do return
	start, start_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(offset))
	end, end_ok, _ := editor.buffer_position(&buffer, editor.Byte_Offset(offset + len("héllo")))
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	change, _, published, _ := editor.buffer_splice(
		&buffer,
		{start = start, end = end, replacement = "hello λ"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	if !published do return
	result_snapshot: editor.Buffer_Snapshot
	result_opened, _ := editor.buffer_snapshot_open(&buffer, &result_snapshot)
	testing.expect(t, result_opened)
	if !result_opened do return
	defer editor.buffer_snapshot_close(&result_snapshot)
	splices := [1]transaction.Normalized_Splice {{
		start = change.start,
		end = editor.Byte_Offset(u64(change.start) + change.removed_bytes),
		replacement_text = change.replacement_text,
		removed_text = "héllo",
	}}
	event := transaction.Commit_Event {
		buffer_id = change.buffer_id,
		base_revision = change.base_revision,
		result_revision = change.result_revision,
		splices = splices[:],
	}
	_, incrementally_parsed, failure := tree_sitter_owner_parse_incremental(
		&incremental_owner, &base_snapshot, &result_snapshot, event, 2,
	)
	testing.expectf(t, incrementally_parsed, "TSX incremental parse failed with %v", failure.code)
	if !incrementally_parsed do return
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&result_snapshot)
	testing.expect(t, stats_ok)
	if !stats_ok do return
	incremental, incremental_ok, _ := tree_sitter_owner_query_spans(
		&incremental_owner, &result_snapshot, 0, stats.text_bytes, 0, 1,
	)
	testing.expect(t, incremental_ok)
	if !incremental_ok do return
	defer syntax_query_result_close(&incremental)
	full_owner: Tree_Sitter_Owner
	full_ready, _ := tree_sitter_owner_init_factory(&full_owner, FACTORY_TYPESCRIPT_TSX_IDENTITY, 2)
	testing.expect(t, full_ready)
	if !full_ready do return
	defer tree_sitter_owner_close(&full_owner)
	full_query_ready, _ := tree_sitter_owner_compile_factory_query(
		&full_owner, FACTORY_TYPESCRIPT_TSX_IDENTITY, 1,
	)
	testing.expect(t, full_query_ready)
	_, full_parsed, _ := tree_sitter_owner_parse_snapshot(
		&full_owner, &result_snapshot, identity, provider, 1, 1,
	)
	testing.expect(t, full_parsed)
	full, full_ok, _ := tree_sitter_owner_query_spans(
		&full_owner, &result_snapshot, 0, stats.text_bytes, 0, 1,
	)
	testing.expect(t, full_ok)
	if !full_ok do return
	defer syntax_query_result_close(&full)
	testing.expect_value(t, len(incremental.spans), len(full.spans))
	for span, index in incremental.spans {
		testing.expect_value(t, span.start, full.spans[index].start)
		testing.expect_value(t, span.end, full.spans[index].end)
		testing.expect_value(t, span.role, full.spans[index].role)
	}
}

/* Verifies a large HTML container retains bounded embedded-region analysis. */
@(test)
factory_web_large_html_injections_are_bounded :: proc(t: ^testing.T) {
	SOURCE_BYTES :: 512 * 1024
	source, allocation_error := make([]u8, SOURCE_BYTES, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(source)
	for index in 0 ..< len(source) do source[index] = ' '
	tail := "<script>const ready = true;</script><style>main { color: red; }</style>\n"
	copy(source[len(source) - len(tail):], transmute([]u8)(tail))
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer, 941, string(source),
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
	owner: Tree_Sitter_Owner
	owner_ready, _ := tree_sitter_owner_init_factory(&owner, FACTORY_HTML_BUNDLE_IDENTITY, 1)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer tree_sitter_owner_close(&owner)
	query_ready, _ := tree_sitter_owner_compile_factory_query(&owner, FACTORY_HTML_BUNDLE_IDENTITY, 1)
	testing.expect(t, query_ready)
	identity := factory_bundle_language_identity(FACTORY_HTML_LANGUAGE_ID, "html")
	provider := Provider_Handle {
		registry_id = 1, language_id = FACTORY_HTML_LANGUAGE_ID,
		provider_id = 1, provider_generation = 1,
	}
	analysis, parsed, failure := tree_sitter_owner_parse_snapshot(
		&owner, &snapshot, identity, provider, 1, 1,
	)
	testing.expectf(t, parsed, "large HTML parse failed with %v", failure.code)
	if !parsed do return
	testing.expect_value(t, analysis.usage.retained_source_bytes, u64(SOURCE_BYTES))
	testing.expect(t, analysis.usage.retained_source_bytes < MAX_ANALYZED_SOURCE_BYTES)
	injections, queried, _ := tree_sitter_owner_query_factory_injections(&owner, &snapshot)
	testing.expect(t, queried)
	testing.expect_value(t, injections.count, u16(2))
}
