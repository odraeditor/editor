// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package storage_probe

import "../../src/text"
import "base:runtime"

MAX_PROBE_LEVELS :: 8

Leaf :: struct {
	summary: text.Summary,
	used:    u32,
	capacity: u32,
}

Node :: struct {
	summary:     text.Summary,
	first_child: u32,
	child_count: u16,
}

Probe :: struct {
	leaves:      [dynamic]Leaf,
	levels:      [MAX_PROBE_LEVELS][dynamic]Node,
	level_count: int,
	text_bytes:  u64,
	allocator:   runtime.Allocator,
}

Splice_Cost :: struct {
	start_path_visits:  u64,
	end_path_visits:    u64,
	replacement_leaves: u64,
	split_path_nodes:   u64,
	concatenate_nodes:  u64,
	total_node_work:    u64,
}

probe_build_uniform :: proc(
	text_bytes: u64,
	line_stride := u64(80),
	layout := text.DEFAULT_LAYOUT,
	allocator := context.allocator,
) -> (probe: Probe, ok: bool) {
	if !text.layout_is_valid(layout) || layout.max_tree_levels > MAX_PROBE_LEVELS {
		return {}, false
	}
	if line_stride == 0 {
		return {}, false
	}

	leaf_count := max(u64(1), divide_round_up(text_bytes, layout.leaf_target_bytes))
	if leaf_count > u64(max(u32)) {
		return {}, false
	}

	probe = Probe {
		leaves = make([dynamic]Leaf, int(leaf_count), int(leaf_count), allocator),
		text_bytes = text_bytes,
		allocator = allocator,
	}

	for leaf_index in 0 ..< len(probe.leaves) {
		start := u64(leaf_index) * layout.leaf_target_bytes
		end := min(text_bytes, start + layout.leaf_target_bytes)
		used := end - start
		probe.leaves[leaf_index] = Leaf {
			summary = text.Summary {
				byte_count = text.Byte_Count(used),
				line_feed_count = text.Line_Feed_Count(end / line_stride - start / line_stride),
			},
			used = u32(used),
			capacity = u32(layout.leaf_max_bytes),
		}
	}

	child_count := leaf_count
	for child_count > 1 {
		if probe.level_count >= int(layout.max_tree_levels) - 1 {
			probe_deinit(&probe)
			return {}, false
		}

		parent_count := divide_round_up(child_count, u64(layout.internal_max_children))
		level_index := probe.level_count
		probe.levels[level_index] = make(
			[dynamic]Node,
			int(parent_count),
			int(parent_count),
			allocator,
		)

		for parent_index in 0 ..< int(parent_count) {
			first_child := u64(parent_index) * u64(layout.internal_max_children)
			children := min(
				u64(layout.internal_max_children),
				child_count - first_child,
			)
			summary, summary_ok := children_summary(
				&probe,
				level_index,
				int(first_child),
				int(children),
			)
			if !summary_ok {
				probe_deinit(&probe)
				return {}, false
			}
			probe.levels[level_index][parent_index] = Node {
				summary = summary,
				first_child = u32(first_child),
				child_count = u16(children),
			}
		}

		probe.level_count += 1
		child_count = parent_count
	}

	return probe, true
}

probe_deinit :: proc(probe: ^Probe) {
	for level_index in 0 ..< probe.level_count {
		if probe.levels[level_index] != nil {
			delete(probe.levels[level_index])
		}
	}
	if probe.leaves != nil {
		delete(probe.leaves)
	}
	probe^ = {}
}

probe_tree_levels :: proc(probe: ^Probe) -> u64 {
	return u64(probe.level_count + 1)
}

probe_node_count :: proc(probe: ^Probe) -> u64 {
	count := u64(len(probe.leaves))
	for level_index in 0 ..< probe.level_count {
		count += u64(len(probe.levels[level_index]))
	}
	return count
}

probe_estimated_persistent_bytes :: proc(probe: ^Probe) -> u64 {
	leaf_storage := u64(len(probe.leaves)) * (u64(size_of(Leaf)) + text.LEAF_MAX_BYTES)
	internal_storage := u64(0)
	for level_index in 0 ..< probe.level_count {
		internal_storage += u64(len(probe.levels[level_index])) * u64(size_of(Node))
	}
	return leaf_storage + internal_storage
}

probe_validate_summaries :: proc(probe: ^Probe) -> bool {
	if len(probe.leaves) == 0 {
		return false
	}

	for level_index in 0 ..< probe.level_count {
		for node in probe.levels[level_index] {
			summary, ok := children_summary(
				probe,
				level_index,
				int(node.first_child),
				int(node.child_count),
			)
			if !ok || summary != node.summary {
				return false
			}
		}
	}

	root_summary := probe_root_summary(probe)
	return u64(root_summary.byte_count) == probe.text_bytes
}

probe_locate :: proc(
	probe: ^Probe,
	byte_offset: u64,
) -> (leaf_index: int, local_offset: u32, path_visits: u64, ok: bool) {
	if byte_offset > probe.text_bytes || len(probe.leaves) == 0 {
		return 0, 0, 0, false
	}
	if probe.level_count == 0 {
		return 0, u32(byte_offset), 1, true
	}

	remaining := byte_offset
	child_index := 0
	for level_index := probe.level_count - 1; level_index >= 0; level_index -= 1 {
		node := probe.levels[level_index][child_index]
		path_visits += 1
		selected := -1
		for child_offset in 0 ..< int(node.child_count) {
			candidate := int(node.first_child) + child_offset
			child_summary := child_summary_at(probe, level_index, candidate)
			child_bytes := u64(child_summary.byte_count)
			is_last := child_offset == int(node.child_count) - 1
			if remaining < child_bytes || is_last {
				selected = candidate
				break
			}
			remaining -= child_bytes
		}
		if selected < 0 {
			return 0, 0, path_visits, false
		}
		child_index = selected
	}

	path_visits += 1
	leaf := probe.leaves[child_index]
	if remaining > u64(leaf.used) {
		return 0, 0, path_visits, false
	}
	return child_index, u32(remaining), path_visits, true
}

probe_splice_cost :: proc(
	probe: ^Probe,
	start: u64,
	end: u64,
	replacement_bytes: u64,
) -> (cost: Splice_Cost, ok: bool) {
	if start > end || end > probe.text_bytes {
		return {}, false
	}

	_, _, start_visits, start_ok := probe_locate(probe, start)
	_, _, end_visits, end_ok := probe_locate(probe, end)
	if !start_ok || !end_ok {
		return {}, false
	}

	replacement_leaves := divide_round_up(replacement_bytes, text.LEAF_TARGET_BYTES)
	split_path_nodes := start_visits + end_visits
	concatenate_nodes := u64(probe.level_count) * 2
	return Splice_Cost {
		start_path_visits = start_visits,
		end_path_visits = end_visits,
		replacement_leaves = replacement_leaves,
		split_path_nodes = split_path_nodes,
		concatenate_nodes = concatenate_nodes,
		total_node_work = split_path_nodes + replacement_leaves + concatenate_nodes,
	}, true
}

@(private)
divide_round_up :: proc(value, divisor: u64) -> u64 {
	assert(divisor > 0)
	return value / divisor + (1 if value % divisor != 0 else 0)
}

@(private)
children_summary :: proc(
	probe: ^Probe,
	level_index: int,
	first_child: int,
	child_count: int,
) -> (summary: text.Summary, ok: bool) {
	if first_child < 0 || child_count <= 0 {
		return {}, false
	}

	for child_offset in 0 ..< child_count {
		child_index := first_child + child_offset
		child := child_summary_at(probe, level_index, child_index)
		byte_count := u64(summary.byte_count)
		line_count := u64(summary.line_feed_count)
		child_bytes := u64(child.byte_count)
		child_lines := u64(child.line_feed_count)
		if byte_count > max(u64) - child_bytes || line_count > max(u64) - child_lines {
			return {}, false
		}
		summary.byte_count = text.Byte_Count(byte_count + child_bytes)
		summary.line_feed_count = text.Line_Feed_Count(line_count + child_lines)
	}
	return summary, true
}

@(private)
child_summary_at :: proc(probe: ^Probe, level_index, child_index: int) -> text.Summary {
	if level_index == 0 {
		return probe.leaves[child_index].summary
	}
	return probe.levels[level_index - 1][child_index].summary
}

@(private)
probe_root_summary :: proc(probe: ^Probe) -> text.Summary {
	if probe.level_count == 0 {
		return probe.leaves[0].summary
	}
	return probe.levels[probe.level_count - 1][0].summary
}
