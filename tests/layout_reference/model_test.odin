// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout_reference

import "core:testing"

/* Ensures the independent model preserves topology, geometry, and MRU state. */
@(test)
model_keeps_topology_geometry_mru :: proc(t: ^testing.T) {
	model, ready := model_init(24, 80)
	testing.expect(t, ready)
	if !ready {
		return
	}
	second, second_ok := model_split(&model, .Above_Below)
	focused := model_focus(&model, second)
	third, third_ok := model_split(&model, .Left_Right)
	snapshot, snapshot_ok := model_snapshot(&model)
	testing.expect(t, second_ok && focused && third_ok && snapshot_ok)
	testing.expect_value(t, snapshot.node_count, u16(5))
	testing.expect_value(t, snapshot.pane_count, u16(3))
	testing.expect_value(t, snapshot.active_pane_id, second)
	testing.expect_value(t, snapshot.nodes[0].geometry.outer, Rect{height = 24, width = 80})
	testing.expect_value(t, snapshot.nodes[1].geometry.outer, Rect{height = 12, width = 80})
	testing.expect_value(t, snapshot.nodes[2].geometry.outer, Rect{row = 12, height = 12, width = 80})
	testing.expect_value(t, snapshot.nodes[2].geometry.separator.width, i32(1))
	testing.expect(t, third != 0)
	closed := model_close_active(&model)
	after_close, after_close_ok := model_snapshot(&model)
	testing.expect(t, closed && after_close_ok)
	testing.expect_value(t, after_close.pane_count, u16(2))
	kept := model_keep_only(&model)
	after_keep, after_keep_ok := model_snapshot(&model)
	testing.expect(t, kept && after_keep_ok)
	testing.expect_value(t, after_keep.node_count, u16(1))
	testing.expect_value(t, after_keep.nodes[0].geometry.outer, Rect{height = 24, width = 80})
}
