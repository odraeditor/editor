// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package text owns immutable persistent rope storage and bounded reclamation.
package text

/* LEAF_TARGET_BYTES is the preferred UTF-8 payload size for rope leaves. */
LEAF_TARGET_BYTES :: u64(4 * 1024)
/* LEAF_MAX_BYTES is the hard UTF-8 payload capacity of one rope leaf. */
LEAF_MAX_BYTES :: u64(4 * 1024)
/* INTERNAL_TARGET_CHILDREN is the preferred fanout of non-root internal nodes. */
INTERNAL_TARGET_CHILDREN :: u32(8)
/* INTERNAL_MAX_CHILDREN is the hard fanout limit of every internal node. */
INTERNAL_MAX_CHILDREN :: u32(16)
/* MAX_TREE_LEVELS is the supported maximum rope height. */
MAX_TREE_LEVELS :: u32(8)

/* Byte_Count is a checked summary of bytes below a rope node. */
Byte_Count :: distinct u64
/* Line_Feed_Count is a checked summary of line-feed bytes below a rope node. */
Line_Feed_Count :: distinct u64
/* Node_Count distinguishes structural counts from byte and line counts. */
Node_Count :: distinct u64

/* Summary stores text metrics composed from a node's descendants. */
Summary :: struct {
	byte_count:      Byte_Count,
	line_feed_count: Line_Feed_Count,
}

/* Line_Location identifies one logical line and its half-open byte ranges. */
Line_Location :: struct {
	line_index:    u64,
	start:         u64,
	content_end:   u64,
	next_start:    u64,
}

/* Layout describes leaf sizing, internal fanout, and the tree-height bound. */
Layout :: struct {
	leaf_target_bytes:        u64,
	leaf_max_bytes:           u64,
	internal_target_children: u32,
	internal_max_children:    u32,
	max_tree_levels:          u32,
}

/* DEFAULT_LAYOUT is the production rope shape used by storage and probes. */
DEFAULT_LAYOUT :: Layout {
	leaf_target_bytes = LEAF_TARGET_BYTES,
	leaf_max_bytes = LEAF_MAX_BYTES,
	internal_target_children = INTERNAL_TARGET_CHILDREN,
	internal_max_children = INTERNAL_MAX_CHILDREN,
	max_tree_levels = MAX_TREE_LEVELS,
}

/* layout_is_valid reports whether a layout has coherent positive bounds. */
layout_is_valid :: proc(layout: Layout) -> bool {
	return layout.leaf_target_bytes > 0 &&
	       layout.leaf_target_bytes <= layout.leaf_max_bytes &&
	       layout.internal_target_children >= 2 &&
	       layout.internal_target_children <= layout.internal_max_children &&
	       layout.max_tree_levels > 0
}
