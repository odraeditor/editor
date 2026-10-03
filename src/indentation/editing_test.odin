// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

import "core:testing"

/* Verifies smart Backspace removes one complete or partial leading unit. */
@(test)
smart_backspace_uses_logical_boundaries :: proc(t: ^testing.T) {
	policy := Policy{representation = .Spaces, indent_width = 4, display_tab_width = 8}
	cases := []struct {
	prefix:   string,
	start:    int,
	semantic: bool,
	} {
		{"        ", 4, true},
		{"      ", 4, true},
		{"\t  ", 1, true},
		{"\t", 0, true},
		{"  value", 0, false},
		{"", 0, false},
	}
	for test_case in cases {
		plan, planned := smart_backspace_plan(test_case.prefix, policy)
		testing.expect(t, planned)
		testing.expect_value(t, plan.semantic, test_case.semantic)
		if plan.semantic {
			testing.expect_value(t, plan.start, test_case.start)
			testing.expect_value(t, plan.end, len(test_case.prefix))
		}
	}
}

/* Verifies normalization changes leading indentation and preserves interior whitespace. */
@(test)
normalization_is_leading_and_bidirectional :: proc(t: ^testing.T) {
	policy := Policy{representation = .Spaces, indent_width = 4, display_tab_width = 8}
	source := "\talpha  beta\n      gamma\n  delta\n"
	spaces :: "    alpha  beta\n      gamma\n  delta\n"
	indentation_test_expect_normalization(t, source, policy, .Spaces, spaces)
	indentation_test_expect_normalization(t, spaces, policy, .Tabs, "\talpha  beta\n\t  gamma\n  delta\n")
}

/* Verifies normalization reports exact no-op and output accounting. */
@(test)
normalization_reports_no_op_exactly :: proc(t: ^testing.T) {
	policy := Policy{representation = .Tabs, indent_width = 2, display_tab_width = 8}
	source := "\talpha\n\tb eta\n"
	measurement, measured := normalization_measure(source, policy, .Tabs)
	testing.expect(t, measured)
	testing.expect(t, !measurement.changed)
	testing.expect_value(t, measurement.required_bytes, u64(len(source)))
	indentation_test_expect_normalization(t, source, policy, .Tabs, source)
}

@(private)
indentation_test_expect_normalization :: proc(
	t: ^testing.T,
	source: string,
	policy: Policy,
	target: Normalization_Target,
	expected: string,
) {
	measurement, measured := normalization_measure(source, policy, target)
	testing.expect(t, measured)
	if !measured do return
	output: [256]u8
	testing.expect(t, measurement.required_bytes <= len(output))
	if measurement.required_bytes > len(output) do return
	written, _, normalized := normalize_leading(source, output[:], policy, target)
	testing.expect(t, normalized)
	if normalized do testing.expect_value(t, string(output[:written]), expected)
}
