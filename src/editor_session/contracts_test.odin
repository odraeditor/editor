// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "core:testing"

/* Verifies the measured defaults and both valid policy extremes. */
@(test)
test_default_policy_and_validated_extremes :: proc(t: ^testing.T) {
	default_ok, default_failure := policy_validate(DEFAULT_POLICY)
	testing.expect(t, default_ok)
	testing.expect_value(t, default_failure.code, Failure_Code.None)

	minimum := Policy {
		live_buffers = MIN_LIVE_BUFFERS,
		live_documents = MIN_LIVE_DOCUMENTS,
		aggregate_text_bytes = MIN_AGGREGATE_TEXT_BYTES,
		name_bytes = MIN_NAME_BYTES,
		retained_label_bytes = MIN_RETAINED_LABEL_BYTES,
		descriptor_batch = MIN_DESCRIPTOR_BATCH,
		inventory_marks = MIN_INVENTORY_MARKS,
		capabilities = MIN_CAPABILITIES,
		prepared_operations = MIN_PREPARED_OPERATIONS,
		detach_participants = MIN_DETACH_PARTICIPANTS,
		cleanup_entries_per_turn = MIN_CLEANUP_ENTRIES_PER_TURN,
		session_roots = MIN_SESSION_ROOTS,
		root_path_bytes = MIN_ROOT_PATH_BYTES,
	}
	minimum_ok, minimum_failure := policy_validate(minimum)
	testing.expect(t, minimum_ok)
	testing.expect_value(t, minimum_failure.code, Failure_Code.None)

	maximum := Policy {
		live_buffers = MAX_LIVE_BUFFERS,
		live_documents = MAX_LIVE_DOCUMENTS,
		aggregate_text_bytes = MAX_AGGREGATE_TEXT_BYTES,
		name_bytes = MAX_NAME_BYTES,
		retained_label_bytes = MAX_RETAINED_LABEL_BYTES,
		descriptor_batch = MAX_DESCRIPTOR_BATCH,
		inventory_marks = MAX_INVENTORY_MARKS,
		capabilities = MAX_CAPABILITIES,
		prepared_operations = MAX_PREPARED_OPERATIONS,
		detach_participants = MAX_DETACH_PARTICIPANTS,
		cleanup_entries_per_turn = MAX_CLEANUP_ENTRIES_PER_TURN,
		session_roots = MAX_SESSION_ROOTS,
		root_path_bytes = MAX_ROOT_PATH_BYTES,
	}
	maximum_ok, maximum_failure := policy_validate(maximum)
	testing.expect(t, maximum_ok)
	testing.expect_value(t, maximum_failure.code, Failure_Code.None)
}

/* Distinguishes invalid policy classes. */
@(test)
policy_rejects_range_and_relationship_failures :: proc(t: ^testing.T) {
	invalid_range := DEFAULT_POLICY
	invalid_range.live_buffers = MIN_LIVE_BUFFERS - 1
	range_ok, range_failure := policy_validate(invalid_range)
	testing.expect(t, !range_ok)
	testing.expect_value(t, range_failure.code, Failure_Code.Policy_Range)
	testing.expect_value(t, range_failure.field, Policy_Field.Live_Buffers)

	invalid_relationship := DEFAULT_POLICY
	invalid_relationship.live_documents = DEFAULT_LIVE_BUFFERS + 1
	relationship_ok, relationship_failure := policy_validate(invalid_relationship)
	testing.expect(t, !relationship_ok)
	testing.expect_value(t, relationship_failure.code, Failure_Code.Policy_Relationship)
	testing.expect_value(t, relationship_failure.field, Policy_Field.Live_Documents)
}

/* Ensures checked identities reject zero generations. */
@(test)
checked_handle_shapes_reject_zero_generations :: proc(t: ^testing.T) {
	session := Session_Handle {
		session_id = Session_ID(7),
		generation = Session_Generation(11),
	}
	registry := Registry_Handle {
		session = session,
		generation = Registry_Generation(13),
	}
	entry := Entry_Handle {
		registry = registry,
		entry_id = Entry_ID(17),
		slot = 0,
		generation = 1,
	}
	root := Root_Handle {
		session = session,
		id = Root_ID(19),
		generation = Root_Generation(23),
	}

	testing.expect(t, session_handle_is_valid(session))
	testing.expect(t, registry_handle_is_valid(registry))
	testing.expect(t, entry_handle_is_valid(entry))
	testing.expect(t, root_handle_is_valid(root))

	entry.generation = 0
	testing.expect(t, !entry_handle_is_valid(entry))
	root.generation = Root_Generation(0)
	testing.expect(t, !root_handle_is_valid(root))
	registry.generation = Registry_Generation(0)
	testing.expect(t, !registry_handle_is_valid(registry))
	session.generation = Session_Generation(0)
	testing.expect(t, !session_handle_is_valid(session))
}
