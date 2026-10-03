// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:testing"

/* Verifies immutable snapshot parsing publishes one exact Odin revision. */
@(test)
tree_sitter_parses_exact_immutable_odin_revision :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		91,
		"package demo\nmain :: proc() { value := 42 }\n",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)

	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	start, _, _ := editor.buffer_position(&buffer, 8)
	end, _, _ := editor.buffer_position(&buffer, 12)
	_, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "changed"},
		context.temp_allocator,
	)
	testing.expect(t, published)

	owner: Tree_Sitter_Owner
	owner_ok, _ := tree_sitter_owner_init(&owner, 11)
	testing.expect(t, owner_ok)
	if !owner_ok do return
	defer tree_sitter_owner_close(&owner)
	query_ok, query_failure := tree_sitter_owner_compile_odin_query(&owner, 13)
	testing.expectf(t, query_ok, "query failed with %v", query_failure.code)

	language := Language_Identity{id = 1, generation = 1}
	provider := Provider_Handle {
		registry_id = 1,
		language_id = language.id,
		provider_id = 1,
		provider_generation = 1,
	}
	parsed, parse_ok, parse_failure := tree_sitter_owner_parse_snapshot(
		&owner,
		&snapshot,
		language,
		provider,
		1,
		17,
	)
	testing.expectf(t, parse_ok, "parse failed with %v", parse_failure.code)
	testing.expect_value(t, parsed.buffer_id, editor.Buffer_ID(91))
	testing.expect_value(t, parsed.source_revision, editor.Revision(0))
	testing.expect_value(t, parsed.parser_generation, Parser_Generation(11))
	testing.expect_value(t, parsed.tree_generation, Tree_Generation(17))
	testing.expect_value(t, parsed.query_generation, Query_Generation(13))
	testing.expect_value(t, parsed.status, Analysis_Status.Current)
	testing.expect(t, parsed.usage.retained_source_bytes > 0)

	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.has_tree)
	testing.expect(t, stats.has_query)
}

/* Verifies the factory highlight query maps every declared capture explicitly. */
@(test)
highlight_query_maps_every_capture :: proc(t: ^testing.T) {
	owner: Tree_Sitter_Owner
	ok, _ := tree_sitter_owner_init(&owner, 21)
	testing.expect(t, ok)
	if !ok do return
	defer tree_sitter_owner_close(&owner)

	query_ok, failure := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expectf(t, query_ok, "factory query failed with %v at %v", failure.code, failure.actual)
	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.query_captures > 0)
	unknown_query_text: string = "(identifier) @not-an-odra-capture"
	unknown_ok, unknown_failure := tree_sitter_owner_compile_query(
		&owner,
		transmute([]u8)unknown_query_text,
		2,
	)
	testing.expect(t, !unknown_ok)
	testing.expect_value(t, unknown_failure.code, Failure_Code.Invalid_Capture_Mapping)
	confirmed_stats, confirmed_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, confirmed_ok)
	testing.expect_value(t, confirmed_stats.query_generation, Query_Generation(1))

	ignored, ignored_known := odin_capture_mapping("spell")
	testing.expect(t, ignored_known && ignored.ignored)
	_, unknown_known := odin_capture_mapping("not-an-odra-capture")
	testing.expect(t, !unknown_known)
}
