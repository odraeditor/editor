// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package text

import "core:testing"

/* Verifies UTF-8 preservation and exact byte and line summaries. */
@(test)
roots_preserve_utf8_and_checked_summaries :: proc(t: ^testing.T) {
	fixtures := [?]struct {
		name:     string,
		contents: string,
	} {
		{"empty", ""},
		{"ascii-lines", "alpha\nbeta\n"},
		{"multilingual", "Zażółć gęślą jaźń. Καλημέρα. こんにちは。\n"},
		{"combining-marks", "Cafe\u0301 nai\u0308ve\n"},
		{"emoji-sequences", "editor 🧭 family 👨‍👩‍👧‍👦 flag 🇵🇱\n"},
	}

	for fixture in fixtures {
		root, failure := root_build(
			fixture.contents,
			test_storage_limits(),
			context.allocator,
			context.temp_allocator,
		)
		testing.expectf(t, failure.code == .None, "%s rope failed with %v", fixture.name, failure.code)
		if failure.code != .None {
			continue
		}

		stats, stats_ok := root_stats(root)
		testing.expectf(t, stats_ok, "%s rope returned no statistics", fixture.name)
		testing.expectf(t, u64(stats.summary.byte_count) == u64(len(fixture.contents)), "%s rope counted the wrong bytes", fixture.name)
		testing.expectf(t, u64(stats.summary.line_feed_count) == count_line_feeds(fixture.contents), "%s rope counted the wrong lines", fixture.name)
		testing.expectf(t, validate_test_node(t, root_node(root), true), "%s rope violated node invariants", fixture.name)

		observed := make([]byte, len(fixture.contents))
		copied, copy_failure := root_copy_range(root, 0, observed)
		testing.expectf(t, copy_failure.code == .None, "%s rope copy failed with %v", fixture.name, copy_failure.code)
		testing.expectf(t, copied == u64(len(fixture.contents)), "%s rope copied the wrong byte count", fixture.name)
		testing.expectf(t, string(observed) == fixture.contents, "%s rope changed copied text", fixture.name)
		delete(observed)
		root_release(&root)
		testing.expectf(t, !root_is_valid(root), "%s rope remained valid after release", fixture.name)
	}
}

/* Verifies that leaf chunking never splits a UTF-8 code point. */
@(test)
chunking_keeps_code_points_across_leaves :: proc(t: ^testing.T) {
	prefix := make([]byte, int(LEAF_MAX_BYTES) - 1)
	defer delete(prefix)
	for &value in prefix {
		value = 'a'
	}
	contents_bytes := make([]byte, len(prefix) + len("🙂omega"))
	defer delete(contents_bytes)
	copy(contents_bytes, prefix)
	copy(contents_bytes[len(prefix):], "🙂omega")
	contents := string(contents_bytes)

	root, failure := root_build(
		contents,
		test_storage_limits(),
		context.allocator,
		context.temp_allocator,
	)
	testing.expect_value(t, failure.code, Storage_Failure_Code.None)
	if failure.code != .None {
		return
	}
	defer root_release(&root)

	stats, stats_ok := root_stats(root)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.chunk_count, u64(2))
	testing.expect(t, validate_test_node(t, root_node(root), true))

	observed := make([]byte, len(contents))
	defer delete(observed)
	_, copy_failure := root_copy_range(root, 0, observed)
	testing.expect_value(t, copy_failure.code, Storage_Failure_Code.None)
	testing.expect_value(t, string(observed), contents)
}

/* Verifies shared storage lifetime across independently retained root handles. */
@(test)
retained_roots_share_storage_until_last_release :: proc(t: ^testing.T) {
	contents := "persistent🙂root\n"
	root, failure := root_build(
		contents,
		test_storage_limits(),
		context.allocator,
		context.temp_allocator,
	)
	testing.expect_value(t, failure.code, Storage_Failure_Code.None)
	if failure.code != .None {
		return
	}

	retained, retain_failure := root_retain(root)
	testing.expect_value(t, retain_failure.code, Storage_Failure_Code.None)
	root_release(&root)
	testing.expect(t, !root_is_valid(root))
	testing.expect(t, root_is_valid(retained))

	observed: [64]byte
	copied, copy_failure := root_copy_range(retained, 0, observed[:len(contents)])
	testing.expect_value(t, copy_failure.code, Storage_Failure_Code.None)
	testing.expect_value(t, copied, u64(len(contents)))
	testing.expect_value(t, string(observed[:len(contents)]), contents)
	root_release(&retained)
	testing.expect(t, !root_is_valid(retained))
}

/* Verifies balance and fanout bounds below every published root. */
@(test)
published_non_root_nodes_respect_balance_bounds :: proc(t: ^testing.T) {
	contents := make([]byte, 100_000)
	defer delete(contents)
	for index in 0 ..< len(contents) {
		contents[index] = 'a' if index % 79 != 78 else '\n'
	}

	root, failure := root_build(
		string(contents),
		test_storage_limits(),
		context.allocator,
		context.temp_allocator,
	)
	testing.expect_value(t, failure.code, Storage_Failure_Code.None)
	if failure.code != .None {
		return
	}
	defer root_release(&root)

	stats, stats_ok := root_stats(root)
	testing.expect(t, stats_ok)
	testing.expect(t, stats.height <= MAX_TREE_LEVELS)
	testing.expect(t, validate_test_node(t, root_node(root), true))
}

/* Verifies height-limit failure and reference-count overflow handling. */
@(test)
construction_rejects_height_and_overflow :: proc(t: ^testing.T) {
	contents := make([]byte, int(LEAF_MAX_BYTES) + 1)
	defer delete(contents)
	for &value in contents {
		value = 'a'
	}
	limits := test_storage_limits()
	limits.tree_levels = 1
	height_root, height_failure := root_build(
		string(contents),
		limits,
		context.allocator,
		context.temp_allocator,
	)
	testing.expect(t, !root_is_valid(height_root))
	testing.expect_value(t, height_failure.code, Storage_Failure_Code.Tree_Height_Limit)

	root, build_failure := root_build(
		"root",
		test_storage_limits(),
		context.allocator,
		context.temp_allocator,
	)
	testing.expect_value(t, build_failure.code, Storage_Failure_Code.None)
	if build_failure.code != .None {
		return
	}
	node := root_node(root)
	node.references = max(u32)
	_, retain_failure := root_retain(root)
	testing.expect_value(t, retain_failure.code, Storage_Failure_Code.Reference_Count_Overflow)
	node.references = 1
	root_release(&root)
}

/* Verifies structural sharing while the base and prepared roots remain independent. */
@(test)
splices_share_leaves_and_keep_base :: proc(t: ^testing.T) {
	contents := make([]byte, 100_000)
	defer delete(contents)
	for index in 0 ..< len(contents) {
		contents[index] = 'a' if index % 97 != 96 else '\n'
	}
	base, build_failure := root_build(
		string(contents),
		test_storage_limits(),
		context.allocator,
		context.temp_allocator,
	)
	testing.expect_value(t, build_failure.code, Storage_Failure_Code.None)
	if build_failure.code != .None {
		return
	}
	defer root_release(&base)

	prepared, prepare_failure := root_prepare_splice(
		base,
		49_999,
		50_001,
		"🙂",
		context.temp_allocator,
		262_144,
	)
	testing.expect_value(t, prepare_failure.code, Storage_Failure_Code.None)
	if prepare_failure.code != .None {
		return
	}
	defer root_release(&prepared)
	testing.expect(t, node_validate(root_node(prepared)))

	base_nodes: [128]^Node
	prepared_nodes: [128]^Node
	base_leaf_count := 0
	prepared_leaf_count := 0
	base_visits := u64(0)
	prepared_visits := u64(0)
	testing.expect(t, flatten_leaves(root_node(base), base_nodes[:], &base_leaf_count, &base_visits, 262_144))
	testing.expect(t, flatten_leaves(root_node(prepared), prepared_nodes[:], &prepared_leaf_count, &prepared_visits, 262_144))
	shared_leaves := 0
	for base_leaf in base_nodes[:base_leaf_count] {
		for prepared_leaf in prepared_nodes[:prepared_leaf_count] {
			if base_leaf == prepared_leaf {
				shared_leaves += 1
				break
			}
		}
	}
	testing.expect(t, shared_leaves >= base_leaf_count - 2)

	base_observed := make([]byte, len(contents))
	defer delete(base_observed)
	_, base_copy_failure := root_copy_range(base, 0, base_observed)
	testing.expect_value(t, base_copy_failure.code, Storage_Failure_Code.None)
	testing.expect_value(t, string(base_observed), string(contents))

	expected := make([]byte, len(contents) - 2 + len("🙂"))
	defer delete(expected)
	copy(expected[:49_999], contents[:49_999])
	copy(expected[49_999:49_999 + len("🙂")], "🙂")
	copy(expected[49_999 + len("🙂"):], contents[50_001:])
	prepared_observed := make([]byte, len(expected))
	defer delete(prepared_observed)
	_, prepared_copy_failure := root_copy_range(prepared, 0, prepared_observed)
	testing.expect_value(t, prepared_copy_failure.code, Storage_Failure_Code.None)
	testing.expect_value(t, string(prepared_observed), string(expected))
}

@(private)
test_storage_limits :: proc() -> Storage_Limits {
	return Storage_Limits {
		text_bytes = 1024 * 1024,
		persistent_bytes = 16 * 1024 * 1024,
		temporary_bytes = 4 * 1024 * 1024,
		tree_levels = MAX_TREE_LEVELS,
		reclaim_step_nodes = 4_096,
		reclaim_queue_nodes = 4_096,
	}
}

@(private)
validate_test_node :: proc(t: ^testing.T, node: ^Node, is_root: bool) -> bool {
	if node == nil || node.references == 0 {
		testing.expect(t, false)
		return false
	}

	if node.kind == .Leaf {
		valid := node.height == 1 &&
		         node.child_count == 0 &&
		         node.chunk != nil &&
		         node.chunk.used <= u32(LEAF_MAX_BYTES) &&
		         u64(node.summary.byte_count) == u64(node.chunk.used)
		testing.expect(t, valid)
		return valid
	}

	child_count := int(node.child_count)
	valid := child_count >= 2 && child_count <= int(INTERNAL_MAX_CHILDREN)
	if !is_root {
		valid = valid && child_count >= int(INTERNAL_TARGET_CHILDREN)
	}

	summary: Summary
	for child_index in 0 ..< child_count {
		child := node.children[child_index]
		valid = validate_test_node(t, child, false) && valid
		valid = valid && u32(child.height) + 1 == u32(node.height)
		summary.byte_count = Byte_Count(u64(summary.byte_count) + u64(child.summary.byte_count))
		summary.line_feed_count = Line_Feed_Count(
			u64(summary.line_feed_count) + u64(child.summary.line_feed_count),
		)
	}
	valid = valid && summary == node.summary
	testing.expect(t, valid)
	return valid
}
