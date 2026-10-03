// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

/* JAN_OUTPUT_BRIDGE_SCHEMA_VERSION identifies copied Output and Integration records. */
JAN_OUTPUT_BRIDGE_SCHEMA_VERSION :: u64(1)

/* JAN_OUTPUT_SCOPE_RECORD_BYTES is the fixed copied scope-record size. */
JAN_OUTPUT_SCOPE_RECORD_BYTES :: u64(size_of(Jan_Output_Scope_Record))
/* JAN_OUTPUT_COMMAND_RECORD_BYTES is the fixed copied command-record size. */
JAN_OUTPUT_COMMAND_RECORD_BYTES :: u64(size_of(Jan_Output_Command_Record))
/* JAN_OUTPUT_MANIFEST_RECORD_BYTES is the fixed copied manifest-record size. */
JAN_OUTPUT_MANIFEST_RECORD_BYTES :: u64(size_of(Jan_Output_Manifest_Record))
/* JAN_OUTPUT_OUTCOME_RECORD_BYTES is the fixed copied outcome-record size. */
JAN_OUTPUT_OUTCOME_RECORD_BYTES :: u64(size_of(Jan_Output_Outcome_Record))
/* JAN_OUTPUT_AVAILABILITY_RECORD_BYTES is the fixed copied availability-record size. */
JAN_OUTPUT_AVAILABILITY_RECORD_BYTES :: u64(size_of(Jan_Output_Availability_Record))
/* JAN_OUTPUT_FAILURE_RECORD_BYTES is the fixed copied failure-record size. */
JAN_OUTPUT_FAILURE_RECORD_BYTES :: u64(size_of(Jan_Output_Failure_Record))
/* JAN_OUTPUT_MAX_MANIFEST_ENTRIES bounds one copied output manifest. */
JAN_OUTPUT_MAX_MANIFEST_ENTRIES :: u64(65_536)
/* JAN_OUTPUT_MAX_OUTPUT_BYTES bounds one copied output generation. */
JAN_OUTPUT_MAX_OUTPUT_BYTES :: u64(256 * 1_024 * 1_024)
/* JAN_OUTPUT_MAX_CACHE_BYTES bounds retained output cache state. */
JAN_OUTPUT_MAX_CACHE_BYTES :: u64(512 * 1_024 * 1_024)
/* JAN_OUTPUT_MAX_PUBLICATION_TARGETS bounds one publication request. */
JAN_OUTPUT_MAX_PUBLICATION_TARGETS :: u64(4_096)

@(private)
JAN_OUTPUT_SCOPE_AGENDA :: u64(5)
@(private)
JAN_OUTPUT_CAPABILITY_EXTENSIONS :: u64(17)
@(private)
JAN_OUTPUT_AVAILABILITY_CLASS_FACTORY_NATIVE :: u64(1)
@(private)
JAN_OUTPUT_AVAILABILITY_CLASS_CONFIGURED_PROVIDER :: u64(3)
@(private)
JAN_OUTPUT_AVAILABILITY_STATE_AVAILABLE :: u64(2)
@(private)
JAN_OUTPUT_AVAILABILITY_STATE_UNAVAILABLE :: u64(3)

/* Jan_Output_Command identifies one copied semantic command family. */
Jan_Output_Command :: enum u64 {
	Invalid,
	Export,
	Citation,
	Publish,
	Protocol,
	Protect,
	Synchronize,
	Extend,
	Inspect,
}

/* Jan_Output_Scope_Record copies one exact document and provider generation. */
Jan_Output_Scope_Record :: struct {
	schema_version:           u64,
	operation_id:             u64,
	configuration_generation: u64,
	backend_generation:       u64,
	filter_generation:        u64,
	provider_generation:      u64,
	document_id:              u64,
	source_revision:          u64,
	analysis_generation:      u64,
	baseline_generation:      u64,
	source_bytes:             u64,
	reserved:                 u64,
}

/* Jan_Output_Command_Record carries one exact bounded output request. */
Jan_Output_Command_Record :: struct {
	scope:          Jan_Output_Scope_Record,
	command:        u64,
	selection_kind: u64,
	target_count:   u64,
	payload_bytes:  u64,
	flags:          u64,
	reserved:       u64,
}

/* Jan_Output_Manifest_Record summarizes one exact publication or synchronization manifest. */
Jan_Output_Manifest_Record :: struct {
	schema_version: u64,
	manifest_id:    u64,
	entry_count:    u64,
	prepared:       u64,
	published:      u64,
	reused:         u64,
	failed:         u64,
	unattempted:    u64,
	output_bytes:   u64,
	complete:       u64,
	reserved:       u64,
}

/* Jan_Output_Outcome_Record copies one exact output outcome. */
Jan_Output_Outcome_Record :: struct {
	operation_id: u64,
	state:        u64,
	failure_code: u64,
	byte_count:   u64,
	resource_count: u64,
	reserved:     u64,
}

/* Jan_Output_Availability_Record copies one explicit capability state. */
Jan_Output_Availability_Record :: struct {
	capability:         u64,
	class:              u64,
	state:              u64,
	provider_generation: u64,
	reserved:           u64,
}

/* Jan_Output_Failure_Record copies one bounded attributable failure. */
Jan_Output_Failure_Record :: struct {
	operation_id: u64,
	kind:         u64,
	code:         u64,
	field:        u64,
	limit:        u64,
	actual:       u64,
	committed:    u64,
	reserved:     u64,
}

/* jan_output_command_record_is_valid rejects stale or over-limit requests. */
jan_output_command_record_is_valid :: proc(record: Jan_Output_Command_Record) -> bool {
	scope := record.scope
	return scope.schema_version == JAN_OUTPUT_BRIDGE_SCHEMA_VERSION &&
	       scope.operation_id != 0 && scope.configuration_generation != 0 &&
	       scope.backend_generation != 0 && scope.filter_generation != 0 &&
	       scope.provider_generation != 0 && scope.document_id != 0 &&
	       scope.source_revision != 0 && scope.analysis_generation != 0 &&
	       scope.baseline_generation != 0 && scope.reserved == 0 &&
	       record.command > u64(Jan_Output_Command.Invalid) &&
	       record.command <= u64(Jan_Output_Command.Inspect) &&
	       record.selection_kind > 0 &&
	       record.selection_kind <= JAN_OUTPUT_SCOPE_AGENDA &&
	       record.target_count <= JAN_OUTPUT_MAX_PUBLICATION_TARGETS &&
	       record.payload_bytes <= JAN_OUTPUT_MAX_OUTPUT_BYTES && record.reserved == 0
}

/* jan_output_manifest_record_is_valid checks exact complete accounting. */
jan_output_manifest_record_is_valid :: proc(record: Jan_Output_Manifest_Record) -> bool {
	return record.schema_version == JAN_OUTPUT_BRIDGE_SCHEMA_VERSION && record.manifest_id != 0 &&
	       record.entry_count > 0 && record.entry_count <= JAN_OUTPUT_MAX_MANIFEST_ENTRIES &&
	       record.prepared == record.entry_count &&
	       record.published + record.reused + record.failed + record.unattempted == record.entry_count &&
	       record.output_bytes <= JAN_OUTPUT_MAX_OUTPUT_BYTES && record.complete <= 1 && record.reserved == 0
}

/* jan_output_availability_record_is_valid checks copied capability state. */
jan_output_availability_record_is_valid :: proc(record: Jan_Output_Availability_Record) -> bool {
	if record.capability == 0 || record.capability > JAN_OUTPUT_CAPABILITY_EXTENSIONS ||
	   record.class == 0 || record.class > JAN_OUTPUT_AVAILABILITY_CLASS_CONFIGURED_PROVIDER ||
	   record.state == 0 || record.state > JAN_OUTPUT_AVAILABILITY_STATE_UNAVAILABLE ||
	   record.reserved != 0 {
		return false
	}
	if record.class == JAN_OUTPUT_AVAILABILITY_CLASS_FACTORY_NATIVE {
		return record.state == JAN_OUTPUT_AVAILABILITY_STATE_AVAILABLE && record.provider_generation == 0
	}
	return record.state != JAN_OUTPUT_AVAILABILITY_STATE_AVAILABLE || record.provider_generation != 0
}

/* jan_output_record_layout_is_valid verifies the fixed copied ABI. */
jan_output_record_layout_is_valid :: proc() -> bool {
	return JAN_OUTPUT_SCOPE_RECORD_BYTES == 96 && JAN_OUTPUT_COMMAND_RECORD_BYTES == 144 &&
	       JAN_OUTPUT_MANIFEST_RECORD_BYTES == 88 && JAN_OUTPUT_OUTCOME_RECORD_BYTES == 48 &&
	       JAN_OUTPUT_AVAILABILITY_RECORD_BYTES == 40 && JAN_OUTPUT_FAILURE_RECORD_BYTES == 64
}
