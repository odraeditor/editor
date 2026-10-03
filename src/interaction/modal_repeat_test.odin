// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies semantic repeat retains bounded intent and publishes insert sessions atomically. */
@(test)
modal_repeat_retains_semantic_intent :: proc(t: ^testing.T) {
	state: Modal_Repeat_State
	base := Modal_Repeat_Record {
		kind = .Insert_Session,
		entry_operation = {registry_generation = 3, slot = 8, entry_generation = 1},
		profile = {id = 2, revision = 4},
		catalog_generation = 5,
		snapshot_generation = 6,
		count = 1,
	}
	testing.expect(t, modal_repeat_insert_begin(&state, base))
	_, available := modal_repeat_inspect(&state)
	testing.expect(t, !available)
	operation := Command_Handle{registry_generation = 3, slot = 9, entry_generation = 1}
	testing.expect(t, modal_repeat_insert_append(&state, operation, "one", false))
	testing.expect(t, modal_repeat_insert_append(&state, operation, " two", false))
	record, retained := modal_repeat_inspect(&state)
	testing.expect(t, retained)
	testing.expect_value(t, record.kind, Modal_Repeat_Kind.Insert_Session)
	testing.expect_value(t, modal_repeat_record_text(&record), "one two")
	testing.expect(t, modal_repeat_insert_finish(&state))

	operator := Modal_Repeat_Record {
		kind = .Operator,
		operation = {registry_generation = 3, slot = 10, entry_generation = 1},
		profile = {id = 2, revision = 4},
		catalog_generation = 5,
		snapshot_generation = 6,
		operator = .Delete,
		target = .Next_Word_Start,
		count = 2,
	}
	testing.expect(t, modal_repeat_record(&state, operator))
	record, retained = modal_repeat_inspect(&state)
	testing.expect(t, retained)
	testing.expect_value(t, record.operator, Modal_Operator_Kind.Delete)
	testing.expect_value(t, record.count, u64(2))
}

/* Verifies oversized inserted text cannot replace the last valid repeat record. */
@(test)
modal_repeat_rejects_oversized_insert_without_losing_record :: proc(t: ^testing.T) {
	state: Modal_Repeat_State
	operation := Command_Handle{registry_generation = 7, slot = 2, entry_generation = 1}
	record := Modal_Repeat_Record {
		kind = .Command,
		operation = operation,
		profile = {id = 2, revision = 4},
		catalog_generation = 5,
		snapshot_generation = 6,
		count = 1,
	}
	testing.expect(t, modal_repeat_record(&state, record))
	insert := record
	insert.kind = .Insert_Session
	insert.operation = {}
	testing.expect(t, modal_repeat_insert_begin(&state, insert))
	oversized: [MAX_MODAL_REPEAT_TEXT_BYTES + 1]u8
	testing.expect(t, !modal_repeat_insert_append(&state, operation, string(oversized[:]), false))
	retained, available := modal_repeat_inspect(&state)
	testing.expect(t, available)
	testing.expect_value(t, retained.kind, Modal_Repeat_Kind.Command)
}
