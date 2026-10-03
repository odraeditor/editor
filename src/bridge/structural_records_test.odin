// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:testing"

/* Verifies structural ABI records remain fixed, pointer-free, and quota checked. */
@(test)
structural_record_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, structural_record_layout_is_valid())

	target_bytes, target_ok := structural_target_record_bytes(32)
	testing.expect(t, target_ok)
	testing.expect_value(t, target_bytes, STRUCTURAL_TARGET_RECORD_BYTES + 32)
	_, target_ok = structural_target_record_bytes(MAX_STRUCTURAL_TARGET_TEXT_BYTES + 1)
	testing.expect(t, !target_ok)

	plan_bytes, plan_ok := structural_plan_record_bytes(12)
	testing.expect(t, plan_ok)
	testing.expect_value(
		t,
		plan_bytes,
		STRUCTURAL_PLAN_RECORD_BYTES + 12 * STRUCTURAL_INDENT_EDIT_RECORD_BYTES,
	)
	_, plan_ok = structural_plan_record_bytes(MAX_STRUCTURAL_PLAN_EDITS + 1)
	testing.expect(t, !plan_ok)

	diagnostic_bytes, diagnostic_ok := structural_diagnostic_record_bytes(64)
	testing.expect(t, diagnostic_ok)
	testing.expect_value(t, diagnostic_bytes, STRUCTURAL_DIAGNOSTIC_RECORD_BYTES + 64)
	_, diagnostic_ok = structural_diagnostic_record_bytes(MAX_STRUCTURAL_DIAGNOSTIC_BYTES + 1)
	testing.expect(t, !diagnostic_ok)

	inspection_bytes, inspection_ok := structural_inspection_record_bytes(12, 32, 64)
	testing.expect(t, inspection_ok)
	testing.expect_value(
		t,
		inspection_bytes,
		STRUCTURAL_SCOPE_RECORD_BYTES + STRUCTURAL_TARGET_RECORD_BYTES +
			STRUCTURAL_PLAN_RECORD_BYTES + 12 * STRUCTURAL_INDENT_EDIT_RECORD_BYTES +
			STRUCTURAL_OUTCOME_RECORD_BYTES + STRUCTURAL_USAGE_RECORD_BYTES +
			STRUCTURAL_DIAGNOSTIC_RECORD_BYTES + 32 + 64,
	)
	_, inspection_ok = structural_inspection_record_bytes(
		MAX_STRUCTURAL_PLAN_EDITS + 1, 0, 0,
	)
	testing.expect(t, !inspection_ok)
	maximum_bytes, maximum_ok := structural_inspection_record_bytes(
		MAX_STRUCTURAL_PLAN_EDITS,
		MAX_STRUCTURAL_TARGET_TEXT_BYTES,
		MAX_STRUCTURAL_DIAGNOSTIC_BYTES,
	)
	testing.expect(t, maximum_ok)
	testing.expect(t, maximum_bytes <= MAX_STRUCTURAL_INSPECTION_BYTES)
}

/* Verifies the native manifest publishes the complete ordered structural family. */
@(test)
schema_publishes_structural_records :: proc(t: ^testing.T) {
	structural_entries: u64
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Structural do continue
		structural_entries += 1
		testing.expect_value(t, entry.item, structural_entries)
	}
	testing.expect_value(t, structural_entries, u64(30))
}

/* Verifies structural operation and access identifiers remain complete and ordered. */
@(test)
structural_records_publish_full_sets :: proc(t: ^testing.T) {
	operations := [?]Structural_Capability_Operation {
		.Scope,
		.Inspect,
		.Forward,
		.Backward,
		.Up,
		.Down,
		.Select,
		.Indent,
		.Definition,
	}
	for operation, index in operations {
		testing.expect_value(t, i32(operation), i32(index + 1))
	}
	access := [?]Structural_Capability_Access {
		.Inspect,
		.Forward,
		.Backward,
		.Up,
		.Down,
		.Select,
		.Indent,
		.Definition,
	}
	for permission, index in access {
		testing.expect_value(t, u64(permission), u64(index + 1))
	}
}
