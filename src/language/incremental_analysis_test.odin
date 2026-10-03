// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../transaction"
import "core:testing"

/* Verifies an exact normalized commit replaces only its confirmed base tree. */
@(test)
incremental_parse_replaces_current_revision :: proc(t: ^testing.T) {
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		301,
		"package demo\nvalue :: 1\n",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)

	base_snapshot: editor.Buffer_Snapshot
	base_open, _ := editor.buffer_snapshot_open(&buffer, &base_snapshot)
	testing.expect(t, base_open)
	if !base_open do return
	defer editor.buffer_snapshot_close(&base_snapshot)

	owner: Tree_Sitter_Owner
	owner_ok, _ := tree_sitter_owner_init(&owner, 1)
	testing.expect(t, owner_ok)
	if !owner_ok do return
	defer tree_sitter_owner_close(&owner)
	query_ok, _ := tree_sitter_owner_compile_odin_query(&owner, 1)
	testing.expect(t, query_ok)
	language := Language_Identity{id = 1, generation = 1}
	provider := Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	_, initial_ok, _ := tree_sitter_owner_parse_snapshot(
		&owner,
		&base_snapshot,
		language,
		provider,
		1,
		1,
	)
	testing.expect(t, initial_ok)

	start, _, _ := editor.buffer_position(&buffer, 22)
	end, _, _ := editor.buffer_position(&buffer, 23)
	change, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "42"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	result_snapshot: editor.Buffer_Snapshot
	result_open, _ := editor.buffer_snapshot_open(&buffer, &result_snapshot)
	testing.expect(t, result_open)
	if !result_open do return
	defer editor.buffer_snapshot_close(&result_snapshot)

	splices := [1]transaction.Normalized_Splice {{
		start = change.start,
		end = editor.Byte_Offset(u64(change.start) + change.removed_bytes),
		replacement_text = change.replacement_text,
		removed_text = "1",
	}}
	event := transaction.Commit_Event {
		buffer_id = change.buffer_id,
		base_revision = change.base_revision,
		result_revision = change.result_revision,
		splices = splices[:],
	}
	forged_splices := splices
	forged_splices[0].removed_text = "x"
	forged_event := event
	forged_event.splices = forged_splices[:]
	_, forged_ok, forged_failure := tree_sitter_owner_parse_incremental(
		&owner,
		&base_snapshot,
		&result_snapshot,
		forged_event,
		2,
	)
	testing.expect(t, !forged_ok)
	testing.expect_value(t, forged_failure.code, Failure_Code.Invalid_Transaction)
	failed_stats, failed_stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, failed_stats_ok)
	testing.expect_value(t, failed_stats.tree_generation, Tree_Generation(1))
	testing.expect(t, failed_stats.pending.refresh_requested)

	result, incremental_ok, incremental_failure := tree_sitter_owner_parse_incremental(
		&owner,
		&base_snapshot,
		&result_snapshot,
		event,
		2,
	)
	testing.expectf(t, incremental_ok, "incremental parse failed with %v", incremental_failure.code)
	testing.expect_value(t, result.source_revision, editor.Revision(1))
	testing.expect_value(t, result.tree_generation, Tree_Generation(2))

	_, stale_ok, stale_failure := tree_sitter_owner_parse_incremental(
		&owner,
		&base_snapshot,
		&result_snapshot,
		event,
		3,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Selection)
	stats, stats_ok, _ := tree_sitter_owner_stats(&owner)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.tree_generation, Tree_Generation(2))
	testing.expect(t, stats.pending.refresh_requested)
}
