// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

@(private)
diff_contract_test_target :: proc() -> Diff_Unit_Target {
	return {
		path = {generation = Observation_Generation(7), path = Path_ID(3)},
		source = Diff_Source_ID(11),
		layer = .Working_Tree,
		unit = Diff_Unit_ID(2),
	}
}

/* Verifies measured defaults form one valid bounded diff envelope. */
@(test)
diff_contract_defaults_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, diff_limits_are_valid(DEFAULT_DIFF_LIMITS))
	testing.expect_value(t, DEFAULT_DIFF_LIMITS.units, u32(512))
	testing.expect_value(t, DEFAULT_DIFF_LIMITS.line_bytes, u64(64 * KIBIBYTE))
	testing.expect_value(t, DEFAULT_DIFF_LIMITS.patch_bytes, u64(512 * KIBIBYTE))
	testing.expect_value(t, DEFAULT_DIFF_LIMITS.temporary_bytes, u64(4 * MEBIBYTE))

	invalid := DEFAULT_DIFF_LIMITS
	invalid.units = MAX_DIFF_UNITS + 1
	testing.expect(t, !diff_limits_are_valid(invalid))
	invalid = DEFAULT_DIFF_LIMITS
	invalid.line_bytes = invalid.patch_bytes + 1
	testing.expect(t, !diff_limits_are_valid(invalid))
}

/* Verifies detail states map only complete tracked comparisons to diff layers. */
@(test)
diff_contract_layers_reject_unsupported_detail :: proc(t: ^testing.T) {
	working_tree, working_tree_ok := diff_layer_for_detail_kind(.Unstaged)
	index, index_ok := diff_layer_for_detail_kind(.Staged)
	_, untracked_ok := diff_layer_for_detail_kind(.Untracked)
	_, unmerged_ok := diff_layer_for_detail_kind(.Unmerged)
	testing.expect(t, working_tree_ok && index_ok)
	testing.expect_value(t, working_tree, Diff_Layer.Working_Tree)
	testing.expect_value(t, index, Diff_Layer.Index)
	testing.expect(t, !untracked_ok && !unmerged_ok)
}

/* Verifies hunk and line descriptors require exact semantic and storage identities. */
@(test)
diff_contract_descriptors_reject_incomplete_authority :: proc(t: ^testing.T) {
	target := diff_contract_test_target()
	unit := Diff_Unit_Descriptor {
		target = target,
		old_start = 3,
		old_count = 2,
		new_start = 3,
		new_count = 2,
		line_count = 3,
		presentation = {offset = 4, length = 20},
		patch = {offset = 8, length = 40},
	}
	testing.expect(t, diff_unit_descriptor_is_valid(unit, 24, 48))
	unit.target.source = Diff_Source_ID(0)
	testing.expect(t, !diff_unit_descriptor_is_valid(unit, 24, 48))
	unit.target = target
	testing.expect(t, !diff_unit_descriptor_is_valid(unit, 23, 48))

	line := Diff_Line_Descriptor {
		unit = target,
		kind = .Addition,
		ordinal = 1,
		new_line = 3,
		text = {offset = 0, length = 4},
	}
	testing.expect(t, diff_line_descriptor_is_valid(line, 4))
	line.old_line = 3
	testing.expect(t, !diff_line_descriptor_is_valid(line, 4))
}

/* Verifies document descriptors remain exact, nonempty, and within limits. */
@(test)
diff_contract_document_descriptor_is_bounded :: proc(t: ^testing.T) {
	descriptor := Diff_Document_Descriptor {
		path = {generation = Observation_Generation(7), path = Path_ID(3)},
		source = Diff_Source_ID(11),
		layer = .Working_Tree,
		unit_count = 2,
		line_count = 7,
		presentation_bytes = 120,
		patch_bytes = 180,
	}
	testing.expect(t, diff_document_descriptor_is_valid(descriptor))
	descriptor.unit_count = DEFAULT_DIFF_LIMITS.units + 1
	testing.expect(t, !diff_document_descriptor_is_valid(descriptor))
	descriptor.unit_count = 2
	descriptor.patch_bytes = DEFAULT_DIFF_LIMITS.patch_bytes + 1
	testing.expect(t, !diff_document_descriptor_is_valid(descriptor))
}
