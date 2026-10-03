// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

/* Verifies one owner creates, reports, and closes every foreign resource. */
@(test)
tree_sitter_owner_tracks_lifecycle :: proc(t: ^testing.T) {
	owner: Tree_Sitter_Owner
	ok, failure := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)

	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.lifecycle, Parser_Lifecycle.Ready)
	testing.expect_value(t, stats.grammar_abi, TREE_SITTER_ODIN_ABI)
	testing.expect(t, stats.has_cursor)
	testing.expect(t, !stats.has_query)
	testing.expect(t, !stats.has_tree)

	query_text: string = "(identifier) @variable"
	query := transmute([]u8)query_text
	query_ok, query_failure := tree_sitter_owner_compile_query(&owner, query, 1)
	testing.expect(t, query_ok)
	testing.expect_value(t, query_failure.code, Failure_Code.None)

	stats, stats_ok, _ = tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.has_query)
	testing.expect_value(t, stats.query_generation, Query_Generation(1))
	testing.expect_value(t, stats.query_bytes, u64(len(query)))
	testing.expect_value(t, stats.query_captures, u32(1))

	close_ok, close_failure := tree_sitter_owner_close(&owner)
	testing.expect(t, close_ok)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect(t, owner.state == nil)
	testing.expect(t, owner.closed)
}

/* Verifies an invalid query cannot replace the confirmed query generation. */
@(test)
query_rejection_preserves_confirmed_query :: proc(t: ^testing.T) {
	owner: Tree_Sitter_Owner
	ok, _ := tree_sitter_owner_init(&owner, 2)
	testing.expect(t, ok)
	defer tree_sitter_owner_close(&owner)

	valid_query_text: string = "(identifier) @variable"
	valid_query := transmute([]u8)valid_query_text
	query_ok, _ := tree_sitter_owner_compile_query(&owner, valid_query, 1)
	testing.expect(t, query_ok)

	invalid_query_text: string = "(not_an_odin_node) @invalid"
	invalid_query := transmute([]u8)invalid_query_text
	invalid_ok, failure := tree_sitter_owner_compile_query(&owner, invalid_query, 2)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Query)

	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.has_query)
	testing.expect_value(t, stats.query_generation, Query_Generation(1))
	testing.expect_value(t, stats.query_bytes, u64(len(valid_query)))
}

/* Verifies progress accounting, work limits, cancellation, and recovery. */
@(test)
tree_sitter_owner_tracks_progress :: proc(t: ^testing.T) {
	owner: Tree_Sitter_Owner
	ok, _ := tree_sitter_owner_init(&owner, 3)
	testing.expect(t, ok)
	defer tree_sitter_owner_close(&owner)

	options, progress_ok, _ := tree_sitter_owner_prepare_progress(&owner, INITIAL_WORK_BYTES)
	testing.expect(t, progress_ok)
	testing.expect(t, options.payload != nil)
	testing.expect(t, options.progress_callback != nil)

	foreign_state := Tree_Sitter_Parse_State {
		payload = options.payload,
		current_byte_offset = 1024,
	}
	testing.expect(t, !options.progress_callback(&foreign_state))

	cancel_ok, _ := tree_sitter_owner_request_cancel(&owner)
	testing.expect(t, cancel_ok)
	foreign_state.current_byte_offset = 2048
	testing.expect(t, options.progress_callback(&foreign_state))

	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.cancel_requested)
	testing.expect_value(t, stats.progress_checks, u64(2))
	testing.expect_value(t, stats.current_byte_offset, u32(2048))
	clear_ok, _ := tree_sitter_owner_clear_cancel(&owner)
	testing.expect(t, clear_ok)
}
