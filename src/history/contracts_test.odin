// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "core:testing"

/* Verifies that the measured production history policy satisfies every constraint. */
@(test)
policy_defaults_are_valid :: proc(t: ^testing.T) {
	ok, failure := policy_validate(DEFAULT_POLICY)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
}

/* Verifies that the complete proposed minimum and maximum envelopes are admissible. */
@(test)
policy_admits_safe_envelope_boundaries :: proc(t: ^testing.T) {
	minimum := Policy {
		global_retained_bytes = MIN_GLOBAL_RETAINED_BYTES,
		buffer_retained_bytes = MIN_BUFFER_RETAINED_BYTES,
		global_nodes = MIN_GLOBAL_NODES,
		buffer_nodes = MIN_BUFFER_NODES,
		guaranteed_recent_units = MIN_RECENT_UNITS,
		retained_depth = MIN_RETAINED_DEPTH,
		sibling_branches = MIN_SIBLING_BRANCHES,
		records_per_unit = MIN_RECORDS_PER_UNIT,
		payload_bytes_per_unit = MIN_PAYLOAD_BYTES_PER_UNIT,
		multibuffer_participants = MIN_MULTIBUFFER_PARTICIPANTS,
		selective_operations = MIN_SELECTIVE_OPERATIONS,
		inspection_nodes = MIN_INSPECTION_NODES,
		pruning_operations = MIN_PRUNING_OPERATIONS,
	}
	minimum_ok, _ := policy_validate(minimum)
	testing.expect(t, minimum_ok)

	maximum := Policy {
		global_retained_bytes = MAX_GLOBAL_RETAINED_BYTES,
		buffer_retained_bytes = MAX_BUFFER_RETAINED_BYTES,
		global_nodes = MAX_GLOBAL_NODES,
		buffer_nodes = MAX_GLOBAL_NODES,
		guaranteed_recent_units = MAX_RECENT_UNITS,
		retained_depth = MAX_RETAINED_DEPTH,
		sibling_branches = MAX_SIBLING_BRANCHES,
		records_per_unit = MAX_RECORDS_PER_UNIT,
		payload_bytes_per_unit = MAX_PAYLOAD_BYTES_PER_UNIT,
		multibuffer_participants = MAX_MULTIBUFFER_PARTICIPANTS,
		selective_operations = MAX_SELECTIVE_OPERATIONS,
		inspection_nodes = MAX_INSPECTION_NODES,
		pruning_operations = MAX_PRUNING_OPERATIONS,
	}
	maximum_ok, _ := policy_validate(maximum)
	testing.expect(t, maximum_ok)
}

/* Verifies structured rejection for isolated ranges and cross-field relationships. */
@(test)
policy_rejects_range_and_relationship_failures :: proc(t: ^testing.T) {
	below_minimum := DEFAULT_POLICY
	below_minimum.global_retained_bytes = MIN_GLOBAL_RETAINED_BYTES - 1
	below_ok, below_failure := policy_validate(below_minimum)
	testing.expect(t, !below_ok)
	testing.expect_value(t, below_failure.code, Failure_Code.Policy_Range)
	testing.expect_value(t, below_failure.field, Policy_Field.Global_Retained_Bytes)
	testing.expect_value(t, below_failure.minimum, MIN_GLOBAL_RETAINED_BYTES)

	above_global := DEFAULT_POLICY
	above_global.buffer_retained_bytes = above_global.global_retained_bytes + 1
	relationship_ok, relationship_failure := policy_validate(above_global)
	testing.expect(t, !relationship_ok)
	testing.expect_value(t, relationship_failure.code, Failure_Code.Policy_Relationship)
	testing.expect_value(t, relationship_failure.field, Policy_Field.Buffer_Retained_Bytes)

	insufficient_records := DEFAULT_POLICY
	insufficient_records.records_per_unit = 100
	insufficient_records.multibuffer_participants = 101
	participant_ok, participant_failure := policy_validate(insufficient_records)
	testing.expect(t, !participant_ok)
	testing.expect_value(t, participant_failure.code, Failure_Code.Policy_Relationship)
	testing.expect_value(t, participant_failure.field, Policy_Field.Multibuffer_Participants)
}

/* Verifies that checked node identities require store-relative generation data. */
@(test)
node_identity_requires_complete_generation :: proc(t: ^testing.T) {
	valid := Node_ID{history_id = History_ID(1), slot = 1, generation = 1}
	testing.expect(t, node_id_is_valid(valid))
	testing.expect(t, !node_id_is_valid(Node_ID{}))
	testing.expect(t, !node_id_is_valid(Node_ID{history_id = History_ID(1), slot = 1}))
}
