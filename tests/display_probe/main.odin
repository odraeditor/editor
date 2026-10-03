// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/display"
import "core:fmt"
import "core:os"

main :: proc() {
	geometries := [?]display.Viewport_Constraints{
		display.Viewport_Constraints{width_cells = 80, height_rows = 24},
		display.Viewport_Constraints{width_cells = 160, height_rows = 50},
		display.Viewport_Constraints{width_cells = 240, height_rows = 80},
	}
	passed := true
	for geometry in geometries {
		cell_count := geometry.width_cells * geometry.height_rows
		estimate, ok, failure := display.representation_estimate(
			geometry,
			min(u64(cell_count) * 4, display.OPERATING_SOURCE_BYTES),
			u64(cell_count) * 4,
			geometry.height_rows * 3,
			cell_count + geometry.height_rows,
			geometry.height_rows * 4,
		)
		if !ok {
			fmt.eprintf(
				"probe=display-representation width=%d height=%d failure=%v\n",
				geometry.width_cells,
				geometry.height_rows,
				failure.code,
			)
			passed = false
			continue
		}
		fmt.printf(
			"probe=display-representation width=%d height=%d rows=%d runs=%d boundaries=%d checkpoints=%d text_bytes=%d row_bytes=%d run_bytes=%d boundary_bytes=%d checkpoint_bytes=%d retained_bytes=%d\n",
			geometry.width_cells,
			geometry.height_rows,
			estimate.row_count,
			estimate.run_count,
			estimate.boundary_count,
			estimate.checkpoint_count,
			estimate.accounting.text_bytes,
			estimate.accounting.row_bytes,
			estimate.accounting.run_bytes,
			estimate.accounting.boundary_bytes,
			estimate.accounting.checkpoint_bytes,
			estimate.accounting.retained_bytes,
		)
	}
	fmt.printf(
		"probe=display-type-layout run_bytes=%d boundary_bytes=%d row_bytes=%d checkpoint_bytes=%d key_bytes=%d\n",
		size_of(display.Text_Run),
		size_of(display.Boundary_Map),
		size_of(display.Display_Row),
		size_of(display.Line_Checkpoint),
		size_of(display.Snapshot_Key),
	)
	if !passed {
		os.exit(1)
	}
}
