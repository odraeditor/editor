// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies Project candidates expose global scope and their authoritative root. */
@(test)
present_global_scope_and_authoritative_root :: proc(t: ^testing.T) {
	annotations := []Candidate_Annotation{{kind = .Project_Member, text = "/tmp/odra"}}
	view := Candidate_View {
		session_id = Candidate_Session_ID(1),
		session_generation = Candidate_Session_Generation(1),
		source_kind = .Projects,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		rows = []Candidate_Row{{
			identity = {kind = 11, primary = 1},
			label = "Odra",
			annotations = annotations,
			action = {kind = .Open_Project, owner_generation = 4, primary = 1},
			availability = .Available,
		}},
		has_selection = true,
	}
	prompt_storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	prompt, prompt_ok := candidate_prompt_label(view, prompt_storage[:])
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt, "Projects [global] 1/1 Open Project: ")
	size, size_ok := candidate_row_text_size(.Projects, view.rows[0])
	testing.expect(t, size_ok)
	row_storage: [64]u8
	row, row_ok := candidate_row_text_write(.Projects, view.rows[0], row_storage[:])
	testing.expect(t, row_ok)
	testing.expect_value(t, size, len(row))
	testing.expect_value(t, row, "Odra  [/tmp/odra]")
}
