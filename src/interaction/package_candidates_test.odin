// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Package results identify themselves independently from catalog registrations. */
@(test)
package_candidates_have_a_package_prompt :: proc(t: ^testing.T) {
	rows := [2]Candidate_Row {
		{label = "odra.rot13@0.1.0"},
		{label = "odra.rot13@0.1.1"},
	}
	view := Candidate_View {
		session_id = 1,
		session_generation = 1,
		source_kind = .Packages,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		rows = rows[:],
		selected_row = 0,
		has_selection = true,
	}
	storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	label, ok := candidate_prompt_label(view, storage[:])
	testing.expect(t, ok)
	testing.expect_value(t, label, "Packages 1/2 Search: ")
}
