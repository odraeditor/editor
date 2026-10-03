// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

/* MAX_AGENDA_BULK_TARGETS bounds one explicit agenda selection operation. */
MAX_AGENDA_BULK_TARGETS :: MAX_SEMANTIC_TARGETS

/* Agenda_Navigation identifies deterministic movement within one immutable result. */
Agenda_Navigation :: enum u8 {
	Invalid,
	First,
	Last,
	Next_Entry,
	Previous_Entry,
	Next_Date,
	Previous_Date,
}

/* Agenda_Source_Reveal is one exact source handoff for a document-backed row. */
Agenda_Source_Reveal :: struct {
	resource:         Resource_Identity,
	target:           Semantic_Target,
	source_revision:  u64,
	index_generation: u64,
}

/* Agenda_Edit_Operation identifies checked source mutations available from an agenda. */
Agenda_Edit_Operation :: enum u8 {
	Invalid,
	Task_State,
	Priority,
	Tags,
	Property,
	Schedule,
	Deadline,
	Effort,
	Clock_In,
	Clock_Out,
	Refile,
	Archive,
	Capture,
	Delete,
}

/* Agenda_Edit_Owner identifies the canonical planner that must prepare one mutation. */
Agenda_Edit_Owner :: enum u8 {
	Invalid,
	Task_Metadata,
	Time,
	Refile_Archive,
	Capture,
	Structured_Edit,
}

/* Agenda_Edit_Request binds one remote edit to an exact immutable agenda row. */
Agenda_Edit_Request :: struct {
	operation_id:             Operation_ID,
	index_generation:         u64,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	row:                      u32,
	operation:                Agenda_Edit_Operation,
}

/* Agenda_Edit_Plan carries an exact current target to its canonical mutation owner. */
Agenda_Edit_Plan :: struct {
	operation_id:        Operation_ID,
	operation:           Agenda_Edit_Operation,
	owner:               Agenda_Edit_Owner,
	resource:            Resource_Identity,
	target:              Semantic_Target,
	source_revision:     u64,
	index_generation:    u64,
	entry_index:         u32,
	source_index:        u32,
}

/* Agenda_Bulk_Mode selects one explicit multi-target publication policy. */
Agenda_Bulk_Mode :: enum u8 {
	Invalid,
	Atomic,
	Recoverable,
	Best_Effort,
}

/* Agenda_Bulk_State preserves every multi-target completion boundary. */
Agenda_Bulk_State :: enum u8 {
	Invalid,
	Prepared,
	Active,
	Completed,
	Partial,
	Cancelled,
	Failed,
	Recovery_Required,
}

/* Agenda_Bulk_Event is one stable-order public-owner outcome. */
Agenda_Bulk_Event :: enum u8 {
	Invalid,
	Target_Committed,
	Target_Rejected,
	Cancel,
}

/* Agenda_Bulk_Record is the pointer-free recovery authority for one selection. */
Agenda_Bulk_Record :: struct {
	operation_id: Operation_ID,
	mode:         Agenda_Bulk_Mode,
	state:        Agenda_Bulk_State,
	target_count: u32,
	next_target:  u32,
	committed:    u32,
	rejected:     u32,
	unattempted:  u32,
}

/* Agenda_Refresh_Reason prohibits refresh merely because a document opened. */
Agenda_Refresh_Reason :: enum u8 {
	Invalid,
	Explicit,
	Command,
	Configuration_Changed,
	Provider_Changed,
	Recovery,
}

/* Agenda_Refresh_Request binds discovery to the generation being replaced. */
Agenda_Refresh_Request :: struct {
	operation_id:             Operation_ID,
	reason:                   Agenda_Refresh_Reason,
	current_index_generation: u64,
	source_set:               Source_Set_ID,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	cancel_requested:         bool,
}

/* Agenda_Refresh_Handoff requests bounded source rediscovery without performing it. */
Agenda_Refresh_Handoff :: struct {
	operation_id:             Operation_ID,
	reason:                   Agenda_Refresh_Reason,
	replaces_index_generation: u64,
	source_set:               Source_Set_ID,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
}

/* Agenda_Export_Format selects the downstream Jan export contract. */
Agenda_Export_Format :: enum u8 {
	Invalid,
	Text,
	HTML,
	Calendar,
	Provider,
}

/* Agenda_Export_Handoff binds export to one immutable query result. */
Agenda_Export_Handoff :: struct {
	operation_id:     Operation_ID,
	format:           Agenda_Export_Format,
	index_generation: u64,
	result_count:     u32,
	complete:         bool,
	truncated:        bool,
}

/* Agenda_Provider_Contribution describes one copied optional result family. */
Agenda_Provider_Contribution :: struct {
	identity:            string,
	provider_generation: Provider_Generation,
	kind:                Agenda_Entry_Kind,
	entry_count:         u32,
	available:           bool,
}

/* Planning_Recovery_Descriptor summarizes durable state without changing it. */
Planning_Recovery_Descriptor :: struct {
	record_count:      u32,
	valid_records:     u32,
	active_records:    u32,
	completed_records: u32,
	recovery_required: u32,
	malformed_records: u32,
}

/* agenda_navigation_resolve moves only within one exact immutable result. */
agenda_navigation_resolve :: proc(
	index: ^Agenda_Index,
	result: ^Agenda_Query_Result,
	current: u32,
	action: Agenda_Navigation,
) -> (u32, bool, Failure) {
	index_descriptor, indexed := agenda_index_descriptor(index)
	result_descriptor, queried := agenda_query_descriptor(result)
	if !indexed || !queried || action == .Invalid || result_descriptor.result_count == 0 ||
	   result_descriptor.index_generation != index_descriptor.generation ||
	   current >= result_descriptor.result_count {
		return current, false, agenda_workflow_failure(0, .Invalid_Request, .Agenda)
	}
	switch action {
	case .First:
		return 0, true, {}
	case .Last:
		return result_descriptor.result_count - 1, true, {}
	case .Next_Entry:
		if current + 1 >= result_descriptor.result_count do return current, true, {}
		return current + 1, true, {}
	case .Previous_Entry:
		if current == 0 do return current, true, {}
		return current - 1, true, {}
	case .Next_Date, .Previous_Date:
		current_time, found := agenda_result_time(index, result, current)
		if !found do return current, false, agenda_workflow_failure(0, .Unavailable, .Time)
		current_day := agenda_day(current_time)
		if action == .Next_Date {
			for position := current + 1; position < result_descriptor.result_count; position += 1 {
				value, available := agenda_result_time(index, result, position)
				if available && agenda_day(value) > current_day do return position, true, {}
			}
		} else {
			position := current
			for position > 0 {
				position -= 1
				value, available := agenda_result_time(index, result, position)
				if available && agenda_day(value) < current_day do return position, true, {}
			}
		}
		return current, true, {}
	case .Invalid:
	}
	return current, false, agenda_workflow_failure(0, .Invalid_Request, .Agenda)
}

/* agenda_source_reveal resolves one row back to its exact current document target. */
agenda_source_reveal :: proc(
	index: ^Agenda_Index,
	result: ^Agenda_Query_Result,
	row: u32,
) -> (Agenda_Source_Reveal, bool, Failure) {
	entry, source, index_generation, ok, failure := agenda_exact_document_row(index, result, row)
	if !ok do return {}, false, failure
	return {
		resource = source.resource,
		target = entry.target,
		source_revision = source.document_revision,
		index_generation = index_generation,
	}, true, {}
}

/* agenda_edit_plan_prepare revalidates a row and routes mutation to its canonical owner. */
agenda_edit_plan_prepare :: proc(
	index: ^Agenda_Index,
	result: ^Agenda_Query_Result,
	request: Agenda_Edit_Request,
) -> (Agenda_Edit_Plan, bool, Failure) {
	if request.operation_id == Operation_ID(0) || request.operation == .Invalid {
		return {}, false, agenda_workflow_failure(request.operation_id, .Invalid_Request, .Agenda)
	}
	entry, source, index_generation, ok, failure := agenda_exact_document_row(index, result, request.row)
	if !ok {
		failure.operation_id = request.operation_id
		return {}, false, failure
	}
	if request.index_generation != index_generation ||
	   request.configuration_generation != source.configuration_generation ||
	   request.provider_generation != source.provider_generation {
		return {}, false, agenda_workflow_failure(request.operation_id, .Stale, .Generation)
	}
	owner := agenda_edit_owner(request.operation)
	if owner == .Invalid {
		return {}, false, agenda_workflow_failure(request.operation_id, .Invalid_Request, .Agenda)
	}
	return {
		operation_id = request.operation_id,
		operation = request.operation,
		owner = owner,
		resource = source.resource,
		target = entry.target,
		source_revision = source.document_revision,
		index_generation = index_generation,
		entry_index = agenda_result_entry_index(result, request.row),
		source_index = entry.source_index,
	}, true, {}
}

/* agenda_bulk_plan_prepare validates the full selection before publishing any plan. */
agenda_bulk_plan_prepare :: proc(
	index: ^Agenda_Index,
	result: ^Agenda_Query_Result,
	requests: []Agenda_Edit_Request,
	mode: Agenda_Bulk_Mode,
	output: []Agenda_Edit_Plan,
) -> (Agenda_Bulk_Record, bool, Failure) {
	if mode == .Invalid || len(requests) == 0 {
		return {}, false, agenda_workflow_failure(0, .Invalid_Request, .Agenda)
	}
	if len(requests) > int(MAX_AGENDA_BULK_TARGETS) || len(output) < len(requests) {
		failure := agenda_workflow_failure(0, .Limited, .Limit)
		failure.limit = u64(min(len(output), int(MAX_AGENDA_BULK_TARGETS)))
		failure.actual = u64(len(requests))
		return {}, false, failure
	}
	operation_id := requests[0].operation_id
	for request, index_in_selection in requests {
		if request.operation_id != operation_id {
			return {}, false, agenda_workflow_failure(operation_id, .Conflict, .Agenda)
		}
		_, valid, failure := agenda_edit_plan_prepare(index, result, request)
		if !valid {
			failure.actual = u64(index_in_selection)
			return {}, false, failure
		}
	}
	for request, index_in_selection in requests {
		plan, _, _ := agenda_edit_plan_prepare(index, result, request)
		output[index_in_selection] = plan
	}
	return {
		operation_id = operation_id,
		mode = mode,
		state = .Prepared,
		target_count = u32(len(requests)),
	}, true, {}
}

/* agenda_bulk_advance retains every committed, rejected, and unattempted target count. */
agenda_bulk_advance :: proc(
	record: Agenda_Bulk_Record,
	event: Agenda_Bulk_Event,
) -> (Agenda_Bulk_Record, bool, Failure) {
	if !agenda_bulk_record_is_valid(record) || event == .Invalid ||
	   record.state != .Prepared && record.state != .Active {
		return record, false, agenda_workflow_failure(record.operation_id, .Conflict, .Agenda)
	}
	next := record
	if event == .Cancel {
		next.state = .Cancelled
		next.unattempted = next.target_count - next.next_target
		failure := agenda_workflow_failure(record.operation_id, .Cancelled, .Agenda)
		failure.committed = next.committed
		failure.unattempted = next.unattempted
		return next, true, failure
	}
	if event == .Target_Committed {
		next.committed += 1
		next.next_target += 1
		next.state = .Active
		if next.next_target == next.target_count do next.state = .Completed
		return next, true, {}
	}
	next.rejected += 1
	next.next_target += 1
	switch next.mode {
	case .Atomic:
		next.unattempted = next.target_count - next.next_target
		next.state = .Failed if next.committed == 0 else .Recovery_Required
	case .Recoverable:
		next.unattempted = next.target_count - next.next_target
		next.state = .Failed if next.committed == 0 else .Recovery_Required
	case .Best_Effort:
		next.state = .Active
		if next.next_target == next.target_count do next.state = .Partial
	case .Invalid:
	}
	failure := agenda_workflow_failure(record.operation_id, .Partial, .Agenda)
	if next.state == .Recovery_Required do failure.code = .Recovery_Required
	failure.committed = next.committed
	failure.unattempted = next.unattempted
	return next, true, failure
}

/* agenda_refresh_prepare creates an explicit rediscovery handoff and never contacts providers. */
agenda_refresh_prepare :: proc(request: Agenda_Refresh_Request) -> (Agenda_Refresh_Handoff, bool, Failure) {
	if request.operation_id == Operation_ID(0) || request.reason == .Invalid ||
	   request.current_index_generation == 0 || request.source_set == Source_Set_ID(0) ||
	   request.configuration_generation == Configuration_Generation(0) ||
	   request.provider_generation == Provider_Generation(0) {
		return {}, false, agenda_workflow_failure(request.operation_id, .Invalid_Request, .Agenda)
	}
	if request.cancel_requested {
		return {}, false, agenda_workflow_failure(request.operation_id, .Cancelled, .Agenda)
	}
	return {
		operation_id = request.operation_id,
		reason = request.reason,
		replaces_index_generation = request.current_index_generation,
		source_set = request.source_set,
		configuration_generation = request.configuration_generation,
		provider_generation = request.provider_generation,
	}, true, {}
}

/* agenda_export_prepare hands immutable result identity to the later Jan export owner. */
agenda_export_prepare :: proc(
	operation_id: Operation_ID,
	format: Agenda_Export_Format,
	result: ^Agenda_Query_Result,
) -> (Agenda_Export_Handoff, bool, Failure) {
	descriptor, ok := agenda_query_descriptor(result)
	if operation_id == Operation_ID(0) || format == .Invalid || !ok {
		return {}, false, agenda_workflow_failure(operation_id, .Invalid_Request, .Agenda)
	}
	return {
		operation_id = operation_id,
		format = format,
		index_generation = descriptor.index_generation,
		result_count = descriptor.result_count,
		complete = descriptor.complete,
		truncated = descriptor.truncated,
	}, true, {}
}

/* agenda_provider_contribution_is_valid checks one isolated typed provider declaration. */
agenda_provider_contribution_is_valid :: proc(value: Agenda_Provider_Contribution) -> bool {
	return configuration_text_is_valid(value.identity, MAX_IDENTITY_BYTES) &&
	       value.provider_generation != Provider_Generation(0) &&
	       value.kind >= .Diary && value.kind <= .Extension &&
	       value.entry_count <= MAX_AGENDA_ENTRIES
}

/* planning_recovery_inspect validates durable records and reports unresolved state. */
planning_recovery_inspect :: proc(
	clocks: []Active_Clock_Record,
	refiles: []Refile_Publication_Record,
	attachments: []Attachment_Workflow_Record,
	bulk: []Agenda_Bulk_Record,
) -> Planning_Recovery_Descriptor {
	descriptor: Planning_Recovery_Descriptor
	descriptor.record_count = u32(len(clocks) + len(refiles) + len(attachments) + len(bulk))
	for record in clocks {
		if !active_clock_record_is_valid(record) {
			descriptor.malformed_records += 1
			continue
		}
		descriptor.valid_records += 1
		switch record.recovery_state {
		case .Active: descriptor.active_records += 1
		case .Recovery_Required: descriptor.recovery_required += 1
		case .Resolved: descriptor.completed_records += 1
		case .Invalid:
		}
	}
	for record in refiles {
		if !refile_publication_record_is_valid(record) {
			descriptor.malformed_records += 1
			continue
		}
		descriptor.valid_records += 1
		switch record.state {
		case .Prepared, .Destination_Committed: descriptor.active_records += 1
		case .Recovery_Required: descriptor.recovery_required += 1
		case .Completed, .Cancelled, .Failed, .Rolled_Back: descriptor.completed_records += 1
		case .Invalid:
		}
	}
	for record in attachments {
		if record.operation_id == Operation_ID(0) || record.action == .Invalid || record.state == .Invalid {
			descriptor.malformed_records += 1
			continue
		}
		descriptor.valid_records += 1
		switch record.state {
		case .Prepared, .Resource_Committed, .Repository_Pending: descriptor.active_records += 1
		case .Recovery_Required: descriptor.recovery_required += 1
		case .Completed, .Cancelled, .Failed, .Rolled_Back: descriptor.completed_records += 1
		case .Invalid:
		}
	}
	for record in bulk {
		if !agenda_bulk_record_is_valid(record) {
			descriptor.malformed_records += 1
			continue
		}
		descriptor.valid_records += 1
		switch record.state {
		case .Prepared, .Active: descriptor.active_records += 1
		case .Recovery_Required: descriptor.recovery_required += 1
		case .Completed, .Partial, .Cancelled, .Failed: descriptor.completed_records += 1
		case .Invalid:
		}
	}
	return descriptor
}

@(private)
agenda_exact_document_row :: proc(
	index: ^Agenda_Index,
	result: ^Agenda_Query_Result,
	row: u32,
) -> (Agenda_Entry_Record, Agenda_Source_Record, u64, bool, Failure) {
	index_descriptor, indexed := agenda_index_descriptor(index)
	result_descriptor, queried := agenda_query_descriptor(result)
	if !indexed || !queried || result_descriptor.index_generation != index_descriptor.generation ||
	   row >= result_descriptor.result_count {
		return {}, {}, 0, false, agenda_workflow_failure(0, .Stale, .Generation)
	}
	result_row, row_found := agenda_query_row(result, int(row))
	if !row_found do return {}, {}, 0, false, agenda_workflow_failure(0, .Invalid_Target, .Target)
	entry, entry_found := agenda_index_entry(index, int(result_row.entry_index))
	if !entry_found || entry.kind != .Document || !entry.has_target {
		return {}, {}, 0, false, agenda_workflow_failure(0, .Unavailable, .Target)
	}
	source, source_found := agenda_index_source(index, int(entry.source_index))
	if !source_found || source.state != .Confirmed || source.document_revision == 0 ||
	   source.document_revision != u64(entry.target.range.scope.source_revision) {
		return {}, {}, 0, false, agenda_workflow_failure(0, .Stale, .Target)
	}
	return entry, source, index_descriptor.generation, true, {}
}

@(private)
agenda_result_entry_index :: proc(result: ^Agenda_Query_Result, row: u32) -> u32 {
	value, ok := agenda_query_row(result, int(row))
	if !ok do return 0
	return value.entry_index
}

@(private)
agenda_result_time :: proc(index: ^Agenda_Index, result: ^Agenda_Query_Result, row: u32) -> (i64, bool) {
	result_row, row_found := agenda_query_row(result, int(row))
	if !row_found do return 0, false
	entry, entry_found := agenda_index_entry(index, int(result_row.entry_index))
	if !entry_found do return 0, false
	if entry.timestamp != 0 do return entry.timestamp, true
	if entry.scheduled != 0 do return entry.scheduled, true
	if entry.deadline != 0 do return entry.deadline, true
	return 0, false
}

@(private)
agenda_day :: proc(value: i64) -> i64 {
	day := value / 86_400
	if value < 0 && value % 86_400 != 0 do day -= 1
	return day
}

@(private)
agenda_edit_owner :: proc(operation: Agenda_Edit_Operation) -> Agenda_Edit_Owner {
	switch operation {
	case .Task_State, .Priority, .Tags, .Property:
		return .Task_Metadata
	case .Schedule, .Deadline, .Effort, .Clock_In, .Clock_Out:
		return .Time
	case .Refile, .Archive:
		return .Refile_Archive
	case .Capture:
		return .Capture
	case .Delete:
		return .Structured_Edit
	case .Invalid:
		return .Invalid
	}
	return .Invalid
}

@(private)
agenda_bulk_record_is_valid :: proc(record: Agenda_Bulk_Record) -> bool {
	return record.operation_id != Operation_ID(0) && record.mode != .Invalid &&
	       record.state != .Invalid && record.target_count > 0 &&
	       record.target_count <= MAX_AGENDA_BULK_TARGETS &&
	       record.next_target <= record.target_count &&
	       record.committed + record.rejected <= record.next_target &&
	       record.unattempted <= record.target_count - record.next_target
}

@(private)
agenda_workflow_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Agenda, code = code, field = field}
}
