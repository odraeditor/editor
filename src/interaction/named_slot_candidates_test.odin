// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Type-scoped named slot candidates omit their invariant value type. */
@(test)
present_name_and_global_scope :: proc(t: ^testing.T) {
	view := Candidate_View {
		session_id = Candidate_Session_ID(1),
		session_generation = Candidate_Session_Generation(1),
		source_kind = .Named_Slots,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		rows = []Candidate_Row{{
			identity = {kind = 14, primary = 1},
			label = "signature",
			action = {kind = .Select_Named_Slot, owner_generation = 4, primary = 1},
			availability = .Available,
		}},
		has_selection = true,
	}
	prompt_storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	prompt, prompt_ok := candidate_prompt_label(view, prompt_storage[:])
	testing.expect(t, prompt_ok)
	testing.expect_value(t, prompt, "Slots [global] 1/1 Select stored value: ")
	size, size_ok := candidate_row_text_size(.Named_Slots, view.rows[0])
	testing.expect(t, size_ok)
	row_storage: [64]u8
	row, row_ok := candidate_row_text_write(.Named_Slots, view.rows[0], row_storage[:])
	testing.expect(t, row_ok)
	testing.expect_value(t, size, len(row))
	testing.expect_value(t, row, "signature")
}

/* Named slot candidates render an available value preview without repeating its type. */
@(test)
named_slot_candidates_present_value_preview :: proc(t: ^testing.T) {
	annotations := []Candidate_Annotation{{kind = .Description, text = "make_task(\"Review\")"}}
	row := Candidate_Row {
		identity = {kind = 14, primary = 1},
		label = "signature",
		annotations = annotations,
		action = {kind = .Select_Named_Slot, owner_generation = 4, primary = 1},
		availability = .Available,
	}
	size, size_ok := candidate_row_text_size(.Named_Slots, row)
	testing.expect(t, size_ok)
	row_storage: [96]u8
	text, row_ok := candidate_row_text_write(.Named_Slots, row, row_storage[:])
	testing.expect(t, row_ok)
	testing.expect_value(t, size, len(text))
	testing.expect_value(t, text, "signature    make_task(\"Review\")")
}
