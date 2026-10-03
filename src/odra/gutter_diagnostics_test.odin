// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../gutter"
import "../language_service"
import "core:testing"

@(test)
/* gutter_diagnostics_preserve_every_language_severity_as_semantic_presentation. */
diagnostics_map_all_language_severities :: proc(t: ^testing.T) {
	cases := []struct {
		severity: language_service.Diagnostic_Severity,
		role:     gutter.Semantic_Role,
		glyph:    string,
		fallback: string,
		priority: u16,
	} {
		{.Error, .Diagnostic_Error, "●", "E", 400},
		{.Warning, .Diagnostic_Warning, "▲", "W", 300},
		{.Information, .Diagnostic_Information, "●", "I", 200},
		{.Hint, .Diagnostic_Hint, "·", "H", 100},
	}
	for test_case in cases {
		role, glyph, fallback, priority := gutter_diagnostic_presentation(test_case.severity)
		testing.expect_value(t, role, test_case.role)
		testing.expect_value(t, glyph, test_case.glyph)
		testing.expect_value(t, fallback, test_case.fallback)
		testing.expect_value(t, priority, test_case.priority)
	}
}
