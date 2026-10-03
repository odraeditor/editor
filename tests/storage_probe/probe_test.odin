// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package storage_probe

import "../../src/editor"
import "core:testing"

MIB :: u64(1024 * 1024)
GIB :: u64(1024) * MIB

/* Guards the planned tree shape for a hundred-mebibyte document. */
@(test)
hundred_mebibytes_fit_the_planned_shape :: proc(t: ^testing.T) {
	probe, ok := probe_build_uniform(100 * MIB)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer probe_deinit(&probe)

	testing.expect_value(t, len(probe.leaves), 25_600)
	testing.expect_value(t, probe_tree_levels(&probe), u64(5))
	testing.expect(t, probe_validate_summaries(&probe))
	testing.expect(t, probe_estimated_persistent_bytes(&probe) <= 135 * MIB)
}

/* Guards the height and memory ceilings for a one-gibibyte document. */
@(test)
one_gib_stays_within_limits :: proc(t: ^testing.T) {
	probe, ok := probe_build_uniform(GIB)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer probe_deinit(&probe)

	testing.expect(t, probe_tree_levels(&probe) <= 8)
	testing.expect(t, probe_estimated_persistent_bytes(&probe) <= editor.MAX_PERSISTENT_BYTES)
	testing.expect(t, probe_validate_summaries(&probe))
}

/* Ensures summaries locate text boundaries without unbounded traversal depth. */
@(test)
summaries_locate_boundaries_with_bounded_depth :: proc(t: ^testing.T) {
	probe, ok := probe_build_uniform(100 * MIB)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer probe_deinit(&probe)

	offsets := [?]u64{0, 1, 4_095, 4_096, 50 * MIB, 100 * MIB}
	for offset in offsets {
		_, _, visits, locate_ok := probe_locate(&probe, offset)
		testing.expectf(t, locate_ok, "offset %d was not located", offset)
		testing.expect(t, visits <= 8)
	}
}

/* Guards the measured work budget for representative splice shapes. */
@(test)
splice_shape_remains_inside_the_work_budget :: proc(t: ^testing.T) {
	probe, ok := probe_build_uniform(100 * MIB)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer probe_deinit(&probe)

	localized, localized_ok := probe_splice_cost(&probe, 50 * MIB, 50 * MIB, 64)
	testing.expect(t, localized_ok)
	testing.expect_value(t, localized.split_path_nodes, u64(10))
	testing.expect_value(t, localized.concatenate_nodes, u64(8))
	testing.expect(t, localized.total_node_work < 64)

	large, large_ok := probe_splice_cost(&probe, 25 * MIB, 75 * MIB, MIB)
	testing.expect(t, large_ok)
	testing.expect(t, large.total_node_work <= editor.MAX_SPLICE_NODES)
}
