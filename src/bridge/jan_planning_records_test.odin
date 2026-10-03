// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../jan_planning"
import "core:testing"

/* Verifies Planning records remain fixed, bounded, and generation explicit. */
@(test)
jan_planning_records_are_pointer_free_and_checked :: proc(t: ^testing.T) {
	testing.expect(t, jan_planning_record_layout_is_valid())
	command := Jan_Planning_Command_Record {
		scope = {
			schema_version = JAN_PLANNING_SCHEMA_VERSION,
			operation_id = 9,
			index_generation = 7,
			configuration_generation = 3,
			provider_generation = 4,
			source_set = 2,
			document_id = 6,
			source_revision = 11,
			analysis_generation = 5,
			baseline_generation = 1,
		},
		command = u64(Jan_Planning_Command.Agenda_Edit),
		target_count = 1,
		payload_bytes = 12,
	}
	testing.expect(t, jan_planning_command_record_is_valid(command))
	command.scope.configuration_generation = 0
	testing.expect(t, !jan_planning_command_record_is_valid(command))
	_, within_limits := jan_planning_agenda_record_bytes(2, 5, 2, 128)
	testing.expect(t, within_limits)
	_, within_limits = jan_planning_agenda_record_bytes(2, u64(jan_planning.MAX_AGENDA_ENTRIES) + 1, 2, 128)
	testing.expect(t, !within_limits)
}

/* Verifies complete copied agenda batches reject stale counts and malformed ranges. */
@(test)
jan_planning_agenda_records_validate_complete_batches :: proc(t: ^testing.T) {
	text_value := "source/tmp/example.orggroupTODO"
	text := transmute([]u8)text_value
	sources := [?]Jan_Planning_Source_Record{{
		kind = u64(jan_planning.Source_Kind.File),
		state = u64(jan_planning.Agenda_Source_State.Confirmed),
		document_revision = 11,
		provider_generation = 4,
		identity_offset = 0,
		identity_bytes = 6,
		resource_offset = 6,
		resource_bytes = 16,
		entry_count = 1,
	}}
	targets := [?]Jan_Planning_Target_Record{{
		node_id = 3,
		node_kind = 2,
		start = 0,
		end = 12,
		source_revision = 11,
		resource_provider = 1,
		resource_offset = 6,
		resource_bytes = 16,
	}}
	rows := [?]Jan_Planning_Row_Record{{
		entry_index = 0,
		source_index = 0,
		entry_kind = u64(jan_planning.Agenda_Entry_Kind.Document),
		has_target = 1,
		target_index = 0,
		group_offset = 22,
		group_bytes = 5,
		prefix_offset = 27,
		prefix_bytes = 4,
	}}
	header := Jan_Planning_Agenda_Header_Record {
		schema_version = JAN_PLANNING_SCHEMA_VERSION,
		index_generation = 7,
		query_operation_id = 9,
		source_count = 1,
		row_count = 1,
		matched_count = 1,
		complete = 1,
		text_bytes = u64(len(text)),
	}
	header.record_bytes, _ = jan_planning_agenda_record_bytes(1, 1, 1, header.text_bytes)
	testing.expect(t, jan_planning_agenda_records_validate(header, sources[:], rows[:], targets[:], text))
	header.row_count = 2
	testing.expect(t, !jan_planning_agenda_records_validate(header, sources[:], rows[:], targets[:], text))
}
