// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:strings"
import "core:testing"

@(private)
PLOT_TEST_POINTS := [2]Plot_Point{{label = "Q1", value = 10}, {label = "Q2", value = -20}}

@(private)
plot_test_snapshot :: proc() -> Plot_Snapshot {
	digest: [32]u8
	digest[0] = 1
	return {
		operation_id = 71,
		scope = computation_test_scope(),
		table_id = 41,
		digest = digest,
		title = "Quarterly totals",
		x_label = "Quarter",
		y_label = "Value",
		points = PLOT_TEST_POINTS[:],
	}
}

/* Verifies copied values render deterministic bounded text plots. */
@(test)
text_plot_uses_copied_snapshot_values :: proc(t: ^testing.T) {
	snapshot := plot_test_snapshot()
	output: [1_024]u8
	text, ok, failure := render_text_plot(snapshot, 10, output[:])
	testing.expectf(t, ok, "text plot failed with %v", failure.code)
	testing.expect(t, strings.contains(text, "Quarterly totals\n"))
	testing.expect(t, strings.contains(text, "Q1 +#####\n"))
	testing.expect(t, strings.contains(text, "Q2 -##########\n"))
	_, ok, failure = render_text_plot(snapshot, MAX_TEXT_PLOT_WIDTH + 1, output[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Request)
}

/* Verifies Gnuplot adaptation is a bounded copied-data handoff without execution. */
@(test)
gnuplot_adaptation_requires_exact_bounds :: proc(t: ^testing.T) {
	snapshot := plot_test_snapshot()
	output, copied := plot_output_copy(3, "plots/quarterly.svg")
	testing.expect(t, copied)
	request, ok, failure := gnuplot_request_prepare(snapshot, 5, .Svg, output, 800, 600, 512)
	testing.expectf(t, ok, "Gnuplot request failed with %v", failure.code)
	testing.expect_value(t, request.point_count, u32(2))
	testing.expect_value(t, request.snapshot_digest, snapshot.digest)
	limited := DEFAULT_LIMITS
	limited.output_bytes = 128
	_, ok, _ = gnuplot_request_prepare(snapshot, 5, .Svg, output, 800, 600, 512, limited)
	testing.expect(t, !ok)
}
