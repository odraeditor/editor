// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "core:unicode/utf8"

/* JAN_PLANNING_SCHEMA_VERSION identifies the copied Planning and Agenda ABI. */
JAN_PLANNING_SCHEMA_VERSION :: u64(1)
/* JAN_PLANNING_SCOPE_RECORD_BYTES is one exact operation scope. */
JAN_PLANNING_SCOPE_RECORD_BYTES :: u64(88)
/* JAN_PLANNING_COMMAND_RECORD_BYTES is one copied command request. */
JAN_PLANNING_COMMAND_RECORD_BYTES :: u64(136)
/* JAN_PLANNING_TARGET_RECORD_BYTES is one exact semantic target reference. */
JAN_PLANNING_TARGET_RECORD_BYTES :: u64(80)
/* JAN_PLANNING_AGENDA_HEADER_BYTES precedes copied sources and rows. */
JAN_PLANNING_AGENDA_HEADER_BYTES :: u64(112)
/* JAN_PLANNING_SOURCE_RECORD_BYTES is one inspectable source outcome. */
JAN_PLANNING_SOURCE_RECORD_BYTES :: u64(96)
/* JAN_PLANNING_ROW_RECORD_BYTES is one agenda presentation row. */
JAN_PLANNING_ROW_RECORD_BYTES :: u64(96)
/* JAN_PLANNING_OUTCOME_RECORD_BYTES is one bulk publication summary. */
JAN_PLANNING_OUTCOME_RECORD_BYTES :: u64(64)
/* JAN_PLANNING_RECOVERY_RECORD_BYTES is one durable recovery summary. */
JAN_PLANNING_RECOVERY_RECORD_BYTES :: u64(56)
/* JAN_PLANNING_AVAILABILITY_RECORD_BYTES is one capability state. */
JAN_PLANNING_AVAILABILITY_RECORD_BYTES :: u64(40)
/* JAN_PLANNING_FAILURE_RECORD_BYTES is one contained failure. */
JAN_PLANNING_FAILURE_RECORD_BYTES :: u64(64)
/* JAN_PLANNING_MAX_SEMANTIC_TARGETS bounds one copied planning request. */
JAN_PLANNING_MAX_SEMANTIC_TARGETS :: u64(4_096)
/* JAN_PLANNING_MAX_SOURCE_DOCUMENTS bounds one copied agenda source generation. */
JAN_PLANNING_MAX_SOURCE_DOCUMENTS :: u64(1_024)
/* JAN_PLANNING_MAX_AGENDA_ENTRIES bounds one copied agenda result. */
JAN_PLANNING_MAX_AGENDA_ENTRIES :: u64(65_536)
/* JAN_PLANNING_MAX_COPIED_TEXT_BYTES bounds copied agenda text. */
JAN_PLANNING_MAX_COPIED_TEXT_BYTES :: u64(16 * 1_024 * 1_024)
/* JAN_PLANNING_MAX_DERIVED_STATE_BYTES bounds one copied agenda generation. */
JAN_PLANNING_MAX_DERIVED_STATE_BYTES :: u64(64 * 1_024 * 1_024)
/* JAN_PLANNING_MAX_IDENTITY_BYTES bounds one copied identity. */
JAN_PLANNING_MAX_IDENTITY_BYTES :: u64(96)
/* JAN_PLANNING_MAX_LABEL_BYTES bounds one copied display label. */
JAN_PLANNING_MAX_LABEL_BYTES :: u64(128)
/* JAN_PLANNING_MAX_RESOURCE_BYTES bounds one copied resource locator. */
JAN_PLANNING_MAX_RESOURCE_BYTES :: u64(4 * 1_024)

@(private)
Jan_Planning_Source_Kind :: enum u64 {
	Invalid,
	File,
	Directory,
	Project,
	Workspace,
	Provider,
}

@(private)
Jan_Planning_Source_State :: enum u64 {
	Invalid,
	Confirmed,
	Stale,
	Unavailable,
	Failed,
}

@(private)
Jan_Planning_Entry_Kind :: enum u64 {
	Invalid,
	Document,
	Diary,
	Calendar,
	Anniversary,
	Reminder,
	Extension,
}

@(private)
Jan_Planning_Bulk_Mode :: enum u64 {
	Invalid,
	Atomic,
	Recoverable,
	Best_Effort,
}

@(private)
Jan_Planning_Failure_Code :: enum u64 {
	None,
	Invalid_Request,
	Invalid_Target,
	Stale,
	Unavailable,
}

/* Jan_Planning_Command identifies copied Planning and Agenda request families. */
Jan_Planning_Command :: enum u64 {
	Invalid,
	Task,
	Metadata,
	Time,
	Clock,
	Timer,
	Refile,
	Archive,
	Capture,
	Attachment,
	Feed,
	Agenda_Open,
	Agenda_Refresh,
	Agenda_Navigate,
	Agenda_Reveal,
	Agenda_Edit,
	Agenda_Bulk_Edit,
	Agenda_Export,
	Inspect,
}

/* Jan_Planning_Scope_Record binds copied values to exact domain generations. */
Jan_Planning_Scope_Record :: struct {
	schema_version:          u64,
	operation_id:            u64,
	index_generation:        u64,
	configuration_generation: u64,
	provider_generation:     u64,
	source_set:              u64,
	document_id:             u64,
	source_revision:         u64,
	analysis_generation:     u64,
	baseline_generation:     u64,
	reserved:                u64,
}

/* Jan_Planning_Command_Record carries one exact request and bounded payload size. */
Jan_Planning_Command_Record :: struct {
	scope:        Jan_Planning_Scope_Record,
	command:      u64,
	row:          u64,
	target_count: u64,
	bulk_mode:    u64,
	payload_bytes: u64,
	reserved:     u64,
}

/* Jan_Planning_Target_Record copies one revision-bound source target. */
Jan_Planning_Target_Record :: struct {
	node_id:          u64,
	node_kind:        u64,
	start:            u64,
	end:              u64,
	source_revision:  u64,
	resource_provider: u64,
	resource_offset:  u64,
	resource_bytes:   u64,
	entry_index:      u64,
	source_index:     u64,
}

/* Jan_Planning_Agenda_Header_Record describes one immutable copied result. */
Jan_Planning_Agenda_Header_Record :: struct {
	schema_version:      u64,
	record_bytes:        u64,
	index_generation:    u64,
	query_operation_id:  u64,
	source_count:        u64,
	row_count:           u64,
	matched_count:       u64,
	stale_sources:       u64,
	unavailable_sources: u64,
	failed_sources:      u64,
	complete:            u64,
	truncated:           u64,
	text_bytes:          u64,
	reserved:            u64,
}

/* Jan_Planning_Source_Record copies source health and text offsets. */
Jan_Planning_Source_Record :: struct {
	kind:                u64,
	state:               u64,
	failure_code:        u64,
	document_revision:   u64,
	durable_version:     u64,
	provider_generation: u64,
	identity_offset:     u64,
	identity_bytes:      u64,
	resource_offset:     u64,
	resource_bytes:      u64,
	entry_offset:        u64,
	entry_count:         u64,
}

/* Jan_Planning_Row_Record copies row identity, target, and presentation offsets. */
Jan_Planning_Row_Record :: struct {
	entry_index:       u64,
	source_index:      u64,
	entry_kind:       u64,
	has_target:       u64,
	target_index:     u64,
	group_offset:     u64,
	group_bytes:      u64,
	prefix_offset:    u64,
	prefix_bytes:     u64,
	time_grid:        u64,
	row_truncated:    u64,
	reserved:         u64,
}

/* Jan_Planning_Outcome_Record reports every bulk target class. */
Jan_Planning_Outcome_Record :: struct {
	operation_id: u64,
	mode:         u64,
	state:        u64,
	target_count: u64,
	committed:    u64,
	rejected:     u64,
	unattempted:  u64,
	next_target:  u64,
}

/* Jan_Planning_Recovery_Record copies durable recovery accounting. */
Jan_Planning_Recovery_Record :: struct {
	record_count:      u64,
	valid_records:     u64,
	active_records:    u64,
	completed_records: u64,
	recovery_required: u64,
	malformed_records: u64,
	reserved:          u64,
}

/* Jan_Planning_Availability_Record copies one capability transition. */
Jan_Planning_Availability_Record :: struct {
	capability:          u64,
	class:               u64,
	state:               u64,
	provider_generation: u64,
	reserved:            u64,
}

/* Jan_Planning_Failure_Record copies one attributable contained failure. */
Jan_Planning_Failure_Record :: struct {
	operation_id: u64,
	kind:         u64,
	code:         u64,
	field:        u64,
	limit:        u64,
	actual:       u64,
	committed:    u64,
	unattempted:  u64,
}

/* jan_planning_command_record_is_valid rejects stale or oversized copied requests. */
jan_planning_command_record_is_valid :: proc(record: Jan_Planning_Command_Record) -> bool {
	scope := record.scope
	if scope.schema_version != JAN_PLANNING_SCHEMA_VERSION || scope.operation_id == 0 ||
	   scope.configuration_generation == 0 || scope.provider_generation == 0 ||
	   scope.source_set == 0 || scope.reserved != 0 ||
	   record.command <= u64(Jan_Planning_Command.Invalid) ||
	   record.command > u64(Jan_Planning_Command.Inspect) ||
	   record.target_count > JAN_PLANNING_MAX_SEMANTIC_TARGETS ||
	   record.payload_bytes > JAN_PLANNING_MAX_COPIED_TEXT_BYTES || record.reserved != 0 {
		return false
	}
	bulk := record.command == u64(Jan_Planning_Command.Agenda_Bulk_Edit)
	return bulk == (record.bulk_mode > 0) &&
	       record.bulk_mode <= u64(Jan_Planning_Bulk_Mode.Best_Effort)
}

/* jan_planning_agenda_record_bytes validates copied agenda quotas. */
jan_planning_agenda_record_bytes :: proc(
	source_count, row_count, target_count, text_bytes: u64,
) -> (u64, bool) {
	if source_count > JAN_PLANNING_MAX_SOURCE_DOCUMENTS ||
	   row_count > JAN_PLANNING_MAX_AGENDA_ENTRIES ||
	   target_count > JAN_PLANNING_MAX_SEMANTIC_TARGETS ||
	   text_bytes > JAN_PLANNING_MAX_COPIED_TEXT_BYTES {
		return 0, false
	}
	bytes := JAN_PLANNING_AGENDA_HEADER_BYTES +
	         source_count * JAN_PLANNING_SOURCE_RECORD_BYTES +
	         row_count * JAN_PLANNING_ROW_RECORD_BYTES +
	         target_count * JAN_PLANNING_TARGET_RECORD_BYTES + text_bytes
	return bytes, bytes <= JAN_PLANNING_MAX_DERIVED_STATE_BYTES
}

/* jan_planning_agenda_records_validate checks counts, ranges, flags, and text. */
jan_planning_agenda_records_validate :: proc(
	header: Jan_Planning_Agenda_Header_Record,
	sources: []Jan_Planning_Source_Record,
	rows: []Jan_Planning_Row_Record,
	targets: []Jan_Planning_Target_Record,
	text: []u8,
) -> bool {
	if header.schema_version != JAN_PLANNING_SCHEMA_VERSION || header.index_generation == 0 ||
	   header.query_operation_id == 0 || header.complete > 1 || header.truncated > 1 ||
	   header.reserved != 0 || header.source_count != u64(len(sources)) ||
	   header.row_count != u64(len(rows)) || header.text_bytes != u64(len(text)) {
		return false
	}
	expected, ok := jan_planning_agenda_record_bytes(
		header.source_count, header.row_count, u64(len(targets)), header.text_bytes,
	)
	if !ok || header.record_bytes != expected || header.matched_count < header.row_count do return false
	for source in sources {
		if source.kind == 0 || source.kind > u64(Jan_Planning_Source_Kind.Provider) ||
		   source.state == 0 || source.state > u64(Jan_Planning_Source_State.Failed) ||
		   !jan_planning_record_text_is_valid(text, source.identity_offset, source.identity_bytes, JAN_PLANNING_MAX_IDENTITY_BYTES) ||
		   !jan_planning_record_text_is_valid(text, source.resource_offset, source.resource_bytes, JAN_PLANNING_MAX_RESOURCE_BYTES) ||
		   source.entry_offset > JAN_PLANNING_MAX_AGENDA_ENTRIES ||
		   source.entry_count > JAN_PLANNING_MAX_AGENDA_ENTRIES - source.entry_offset ||
		   !jan_planning_source_health_record_is_valid(source) {
			return false
		}
	}
	for row in rows {
		if row.entry_index >= JAN_PLANNING_MAX_AGENDA_ENTRIES ||
		   row.source_index >= header.source_count || row.entry_kind == 0 ||
		   row.entry_kind > u64(Jan_Planning_Entry_Kind.Extension) || row.has_target > 1 ||
		   row.time_grid > 1 || row.row_truncated > 1 || row.reserved != 0 ||
		   !jan_planning_record_optional_text_is_valid(text, row.group_offset, row.group_bytes, JAN_PLANNING_MAX_LABEL_BYTES) ||
		   !jan_planning_record_optional_text_is_valid(text, row.prefix_offset, row.prefix_bytes, JAN_PLANNING_MAX_LABEL_BYTES) ||
		   row.has_target == 1 && row.target_index >= u64(len(targets)) {
			return false
		}
	}
	for target in targets {
		if target.node_id == 0 || target.node_kind == 0 || target.start >= target.end ||
		   target.source_revision == 0 || target.resource_provider == 0 ||
		   !jan_planning_record_text_is_valid(text, target.resource_offset, target.resource_bytes, JAN_PLANNING_MAX_RESOURCE_BYTES) {
			return false
		}
	}
	return true
}

@(private)
jan_planning_source_health_record_is_valid :: proc(source: Jan_Planning_Source_Record) -> bool {
	state := Jan_Planning_Source_State(source.state)
	switch state {
	case .Confirmed:
		return source.failure_code == u64(Jan_Planning_Failure_Code.None) &&
		       (source.document_revision != 0 || source.durable_version != 0)
	case .Stale:
		return source.failure_code == u64(Jan_Planning_Failure_Code.Stale) && source.entry_count == 0
	case .Unavailable:
		return source.failure_code == u64(Jan_Planning_Failure_Code.Unavailable) && source.entry_count == 0
	case .Failed:
		return source.failure_code != u64(Jan_Planning_Failure_Code.None) && source.entry_count == 0
	case .Invalid:
		return false
	}
	return false
}

/* jan_planning_record_layout_is_valid verifies every fixed pointer-free width. */
jan_planning_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Jan_Planning_Scope_Record)) == JAN_PLANNING_SCOPE_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Command_Record)) == JAN_PLANNING_COMMAND_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Target_Record)) == JAN_PLANNING_TARGET_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Agenda_Header_Record)) == JAN_PLANNING_AGENDA_HEADER_BYTES &&
	       u64(size_of(Jan_Planning_Source_Record)) == JAN_PLANNING_SOURCE_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Row_Record)) == JAN_PLANNING_ROW_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Outcome_Record)) == JAN_PLANNING_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Recovery_Record)) == JAN_PLANNING_RECOVERY_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Availability_Record)) == JAN_PLANNING_AVAILABILITY_RECORD_BYTES &&
	       u64(size_of(Jan_Planning_Failure_Record)) == JAN_PLANNING_FAILURE_RECORD_BYTES
}

@(private)
jan_planning_record_text_is_valid :: proc(text: []u8, offset, count, limit: u64) -> bool {
	return count > 0 && count <= limit && offset <= u64(len(text)) &&
	       count <= u64(len(text)) - offset &&
	       utf8.valid_string(string(text[int(offset):int(offset + count)]))
}

@(private)
jan_planning_record_optional_text_is_valid :: proc(text: []u8, offset, count, limit: u64) -> bool {
	return count == 0 && offset == 0 || jan_planning_record_text_is_valid(text, offset, count, limit)
}
