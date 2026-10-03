// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package text

import "core:testing"

/* Verifies that the production rope layout satisfies its structural contract. */
@(test)
default_layout_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, layout_is_valid(DEFAULT_LAYOUT))
	testing.expect_value(t, DEFAULT_LAYOUT.leaf_max_bytes, u64(4 * 1024))
	testing.expect_value(t, DEFAULT_LAYOUT.internal_max_children, u32(16))
	testing.expect_value(t, DEFAULT_LAYOUT.max_tree_levels, u32(8))
}

/* Verifies rejection of incoherent leaf, fanout, and tree-height bounds. */
@(test)
invalid_layouts_are_rejected :: proc(t: ^testing.T) {
	zero_leaf := DEFAULT_LAYOUT
	zero_leaf.leaf_target_bytes = 0

	overfull_target := DEFAULT_LAYOUT
	overfull_target.internal_target_children = INTERNAL_MAX_CHILDREN + 1

	zero_levels := DEFAULT_LAYOUT
	zero_levels.max_tree_levels = 0

	testing.expect(t, !layout_is_valid(zero_leaf))
	testing.expect(t, !layout_is_valid(overfull_target))
	testing.expect(t, !layout_is_valid(zero_levels))
}
