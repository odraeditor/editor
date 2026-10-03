// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

/* Verifies every logical and role failure has a precise stable diagnostic. */
@(test)
failure_taxonomies_have_complete_diagnostics :: proc(t: ^testing.T) {
	for code in Failure_Code {
		diagnostic := failure_code_diagnostic(code)
		if code == .None {
			testing.expect_value(t, diagnostic, "")
		} else {
			testing.expect(t, len(diagnostic) > 0)
			testing.expect(t, diagnostic != "unknown UI failure")
		}
	}
	for code in Role_Failure_Code {
		diagnostic := role_failure_code_diagnostic(code)
		if code == .None {
			testing.expect_value(t, diagnostic, "")
		} else {
			testing.expect(t, len(diagnostic) > 0)
			testing.expect(t, diagnostic != "unknown UI role failure")
		}
	}
}
