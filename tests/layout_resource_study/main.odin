// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import editor "../../src/editor"
import layout "../../src/layout"
import view "../../src/view"
import "core:fmt"
import "core:os"

main :: proc() {
	buffer: editor.Buffer
	buffer_ok, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(31_001),
		"layout-resource-study",
		editor.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	views: view.Registry
	views_ok, _ := view.registry_init(&views, view.Registry_ID(31_001), context.allocator)
	root_view, root_ok, _ := view.create(&views, &buffer)
	registry: layout.Registry
	registry_ok, _ := layout.registry_init(
		&registry,
		layout.Owner_ID(31_001),
		layout.Layout_ID(31_001),
		&views,
		root_view,
		layout.Geometry_Request{rows = 768, columns = 2_048},
	)
	if !buffer_ok || !views_ok || !root_ok || !registry_ok {
		fmt.println("layout_resource_study status=setup_failed")
		os.exit(1)
	}
	for split_index in 0 ..< layout.MAX_LIVE_PANES - 1 {
		handle, _, _ := layout.registry_handle(&registry)
		snapshot, snapshot_ok, _ := layout.registry_snapshot(&registry, handle)
		if !snapshot_ok {
			fmt.println("layout_resource_study status=snapshot_failed")
			os.exit(1)
		}
		target := shallowest_pane(&snapshot)
		active := snapshot.active_pane
		if target.pane_id != active.pane_id {
			focused, focus_ok, _ := layout.registry_focus(&registry, target)
			if !focus_ok {
				fmt.println("layout_resource_study status=focus_failed")
				os.exit(1)
			}
			active = focused.active
		}
		split_ok: bool
		if split_index & 1 == 0 {
			_, split_ok, _ = layout.registry_split_below(&registry, active)
		} else {
			_, split_ok, _ = layout.registry_split_right(&registry, active)
		}
		if !split_ok {
			fmt.printf("layout_resource_study status=split_failed index=%d\n", split_index)
			os.exit(1)
		}
	}
	handle, _, _ := layout.registry_handle(&registry)
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&registry, handle)
	stats, stats_ok, _ := layout.registry_stats(&registry)
	view_stats, view_stats_ok, _ := view.registry_stats(&views)
	maximum_depth: u16
	for node in snapshot.nodes[:snapshot.node_count] {
		maximum_depth = max(maximum_depth, node.depth)
	}
	_, overflow_ok, overflow_failure := layout.registry_split_right(&registry, snapshot.active_pane)
	passed := snapshot_ok && stats_ok && view_stats_ok &&
	          snapshot.pane_count == layout.MAX_LIVE_PANES &&
	          snapshot.node_count == layout.MAX_NODES &&
	          maximum_depth <= layout.MAX_PARTITION_DEPTH &&
	          stats.storage_bytes <= layout.MAX_PREPARED_TRANSACTION_BYTES &&
	          stats.geometry_work <= layout.MAX_GEOMETRY_WORK &&
	          u64(size_of(layout.Snapshot)) <= layout.MAX_SNAPSHOT_BYTES &&
	          view_stats.live_count == layout.MAX_LIVE_PANES &&
	          !overflow_ok && overflow_failure.code == .Pane_Limit
	fmt.printf(
		"layout_resource_study panes=%d nodes=%d depth=%d storage_bytes=%d snapshot_bytes=%d geometry_work=%d status=%s\n",
		snapshot.pane_count,
		snapshot.node_count,
		maximum_depth,
		stats.storage_bytes,
		size_of(layout.Snapshot),
		stats.geometry_work,
		passed ? "pass" : "fail",
	)
	layout_closed, _ := layout.registry_close(&registry)
	root_closed, _ := view.close(&views, &root_view)
	views_closed, _ := view.registry_close(&views)
	buffer_closed, _ := editor.buffer_close(&buffer)
	if !passed || !layout_closed || !root_closed || !views_closed || !buffer_closed {
		os.exit(1)
	}
}

shallowest_pane :: proc(snapshot: ^layout.Snapshot) -> layout.Pane_Handle {
	selected: layout.Pane_Handle
	selected_depth := max(u16)
	for node in snapshot.nodes[:snapshot.node_count] {
		if node.kind == .Pane && node.depth < selected_depth {
			selected = node.pane
			selected_depth = node.depth
		}
	}
	return selected
}
