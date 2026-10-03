// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

/* JAN_COMPUTATION_SCHEMA_VERSION identifies the copied Computable Documents ABI. */
JAN_COMPUTATION_SCHEMA_VERSION :: u64(1)
/* JAN_COMPUTATION_SCOPE_RECORD_BYTES is one exact computation scope. */
JAN_COMPUTATION_SCOPE_RECORD_BYTES :: u64(96)
/* JAN_COMPUTATION_COMMAND_RECORD_BYTES is one copied command request. */
JAN_COMPUTATION_COMMAND_RECORD_BYTES :: u64(144)
/* JAN_COMPUTATION_TARGET_RECORD_BYTES is one exact executable target. */
JAN_COMPUTATION_TARGET_RECORD_BYTES :: u64(64)
/* JAN_COMPUTATION_BATCH_HEADER_BYTES precedes deterministic target outcomes. */
JAN_COMPUTATION_BATCH_HEADER_BYTES :: u64(96)
/* JAN_COMPUTATION_OUTCOME_RECORD_BYTES is one batch target outcome. */
JAN_COMPUTATION_OUTCOME_RECORD_BYTES :: u64(48)
/* JAN_COMPUTATION_AVAILABILITY_RECORD_BYTES is one capability transition. */
JAN_COMPUTATION_AVAILABILITY_RECORD_BYTES :: u64(40)
/* JAN_COMPUTATION_FAILURE_RECORD_BYTES is one attributable contained failure. */
JAN_COMPUTATION_FAILURE_RECORD_BYTES :: u64(64)
/* JAN_COMPUTATION_MAX_EXECUTABLE_TARGETS bounds one copied computation batch. */
JAN_COMPUTATION_MAX_EXECUTABLE_TARGETS :: u64(4_096)
/* JAN_COMPUTATION_MAX_OUTPUT_BYTES bounds output from one computation. */
JAN_COMPUTATION_MAX_OUTPUT_BYTES :: u64(64 * 1_024 * 1_024)
/* JAN_COMPUTATION_MAX_RETAINED_OUTPUT_BYTES bounds retained computation output. */
JAN_COMPUTATION_MAX_RETAINED_OUTPUT_BYTES :: u64(256 * 1_024 * 1_024)
/* JAN_COMPUTATION_MAX_CACHE_BYTES bounds the copied computation cache. */
JAN_COMPUTATION_MAX_CACHE_BYTES :: u64(256 * 1_024 * 1_024)
/* JAN_COMPUTATION_MAX_RESULT_ROWS bounds structured result projection. */
JAN_COMPUTATION_MAX_RESULT_ROWS :: u64(16_384)

@(private)
JAN_COMPUTATION_INVOCATION_EXPORT :: u64(3)
@(private)
JAN_COMPUTATION_BATCH_MODE_ATOMIC :: u64(1)
@(private)
JAN_COMPUTATION_BATCH_MODE_BEST_EFFORT :: u64(2)
@(private)
JAN_COMPUTATION_TARGET_STATE_CANCELLED :: u64(6)
@(private)
JAN_COMPUTATION_CAPABILITY_BATCH :: u64(11)
@(private)
JAN_COMPUTATION_AVAILABILITY_CLASS_CONFIGURED_PROVIDER :: u64(3)
@(private)
JAN_COMPUTATION_AVAILABILITY_CLASS_FACTORY_ADAPTER :: u64(2)
@(private)
JAN_COMPUTATION_AVAILABILITY_STATE_AVAILABLE :: u64(2)
@(private)
JAN_COMPUTATION_AVAILABILITY_STATE_UNAVAILABLE :: u64(3)

/* Jan_Computation_Command identifies copied computation request families. */
Jan_Computation_Command :: enum u64 {
	Invalid,
	Formula,
	Plot,
	Execute,
	Result,
	Session,
	Cache,
	Source_Edit,
	Noweb,
	Tangle,
	Batch,
	Inspect,
}

/* Jan_Computation_Scope_Record binds copied values to exact domain generations. */
Jan_Computation_Scope_Record :: struct {
	schema_version:           u64,
	operation_id:             u64,
	configuration_generation: u64,
	adapter_generation:       u64,
	policy_generation:        u64,
	document_id:              u64,
	source_revision:          u64,
	analysis_generation:      u64,
	baseline_generation:      u64,
	invocation:               u64,
	effects:                  u64,
	reserved:                 u64,
}

/* Jan_Computation_Command_Record carries one exact bounded request. */
Jan_Computation_Command_Record :: struct {
	scope:         Jan_Computation_Scope_Record,
	command:       u64,
	target_count:  u64,
	batch_mode:    u64,
	payload_bytes: u64,
	flags:         u64,
	reserved:      u64,
}

/* Jan_Computation_Target_Record copies one exact source target. */
Jan_Computation_Target_Record :: struct {
	operation_id:    u64,
	node_id:         u64,
	node_kind:       u64,
	start:           u64,
	end:             u64,
	source_revision: u64,
	document_id:     u64,
	reserved:        u64,
}

/* Jan_Computation_Batch_Header_Record summarizes deterministic execution and publication. */
Jan_Computation_Batch_Header_Record :: struct {
	schema_version: u64,
	batch_id:       u64,
	mode:           u64,
	target_count:   u64,
	executed:       u64,
	cache_hits:     u64,
	published:      u64,
	rejected:       u64,
	unattempted:    u64,
	cancelled:      u64,
	output_bytes:   u64,
	result_rows:    u64,
}

/* Jan_Computation_Outcome_Record copies one exact target outcome. */
Jan_Computation_Outcome_Record :: struct {
	operation_id: u64,
	state:        u64,
	failure_code: u64,
	byte_count:   u64,
	row_count:    u64,
	reserved:     u64,
}

/* Jan_Computation_Availability_Record copies one capability state. */
Jan_Computation_Availability_Record :: struct {
	capability:         u64,
	class:              u64,
	state:              u64,
	adapter_generation: u64,
	reserved:           u64,
}

/* Jan_Computation_Failure_Record copies one bounded attributable failure. */
Jan_Computation_Failure_Record :: struct {
	operation_id: u64,
	kind:         u64,
	code:         u64,
	field:        u64,
	limit:        u64,
	actual:       u64,
	committed:    u64,
	unattempted:  u64,
}

/* jan_computation_command_record_is_valid rejects stale or over-limit requests. */
jan_computation_command_record_is_valid :: proc(record: Jan_Computation_Command_Record) -> bool {
	scope := record.scope
	if scope.schema_version != JAN_COMPUTATION_SCHEMA_VERSION || scope.operation_id == 0 ||
	   scope.configuration_generation == 0 || scope.adapter_generation == 0 || scope.policy_generation == 0 ||
	   scope.document_id == 0 || scope.source_revision == 0 || scope.analysis_generation == 0 ||
	   scope.baseline_generation == 0 || scope.invocation == 0 ||
	   scope.invocation > JAN_COMPUTATION_INVOCATION_EXPORT || scope.reserved != 0 ||
	   record.command <= u64(Jan_Computation_Command.Invalid) ||
	   record.command > u64(Jan_Computation_Command.Inspect) ||
	   record.target_count > JAN_COMPUTATION_MAX_EXECUTABLE_TARGETS ||
	   record.payload_bytes > JAN_COMPUTATION_MAX_OUTPUT_BYTES || record.reserved != 0 {
		return false
	}
	command := Jan_Computation_Command(record.command)
	targetless := command == .Session || command == .Cache || command == .Inspect
	if !targetless && record.target_count == 0 do return false
	if command == .Batch {
		return record.batch_mode > 0 &&
		       record.batch_mode <= JAN_COMPUTATION_BATCH_MODE_BEST_EFFORT
	}
	return record.batch_mode == 0
}

/* jan_computation_batch_records_are_valid checks complete exact outcome accounting. */
jan_computation_batch_records_are_valid :: proc(
	header: Jan_Computation_Batch_Header_Record,
	outcomes: []Jan_Computation_Outcome_Record,
) -> bool {
	if header.schema_version != JAN_COMPUTATION_SCHEMA_VERSION || header.batch_id == 0 ||
	   header.mode == 0 ||
	   header.mode > JAN_COMPUTATION_BATCH_MODE_BEST_EFFORT ||
	   header.target_count == 0 || header.target_count != u64(len(outcomes)) ||
	   header.target_count > JAN_COMPUTATION_MAX_EXECUTABLE_TARGETS || header.cancelled > 1 ||
	   header.executed + header.cache_hits + header.rejected + header.unattempted != header.target_count ||
	   header.published > header.executed + header.cache_hits ||
	   header.output_bytes > JAN_COMPUTATION_MAX_RETAINED_OUTPUT_BYTES ||
	   header.result_rows > JAN_COMPUTATION_MAX_RESULT_ROWS * header.target_count {
		return false
	}
	if header.mode == JAN_COMPUTATION_BATCH_MODE_ATOMIC &&
	   (header.rejected > 0 || header.unattempted > 0 || header.cancelled == 1) && header.published != 0 {
		return false
	}
	for outcome in outcomes {
		if outcome.operation_id == 0 || outcome.state == 0 ||
		   outcome.state > JAN_COMPUTATION_TARGET_STATE_CANCELLED ||
		   outcome.byte_count > JAN_COMPUTATION_MAX_OUTPUT_BYTES ||
		   outcome.row_count > JAN_COMPUTATION_MAX_RESULT_ROWS || outcome.reserved != 0 {
			return false
		}
	}
	return true
}

/* jan_computation_availability_record_is_valid checks copied capability state. */
jan_computation_availability_record_is_valid :: proc(record: Jan_Computation_Availability_Record) -> bool {
	if record.capability == 0 || record.capability > JAN_COMPUTATION_CAPABILITY_BATCH ||
	   record.class == 0 || record.class > JAN_COMPUTATION_AVAILABILITY_CLASS_CONFIGURED_PROVIDER ||
	   record.state == 0 || record.state > JAN_COMPUTATION_AVAILABILITY_STATE_UNAVAILABLE ||
	   record.reserved != 0 {
		return false
	}
	return (record.class != JAN_COMPUTATION_AVAILABILITY_CLASS_FACTORY_ADAPTER && record.adapter_generation == 0) ||
	       (record.class == JAN_COMPUTATION_AVAILABILITY_CLASS_FACTORY_ADAPTER &&
	        (record.state != JAN_COMPUTATION_AVAILABILITY_STATE_AVAILABLE || record.adapter_generation != 0))
}

/* jan_computation_record_layout_is_valid verifies the fixed copied ABI. */
jan_computation_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Jan_Computation_Scope_Record)) == JAN_COMPUTATION_SCOPE_RECORD_BYTES &&
	       u64(size_of(Jan_Computation_Command_Record)) == JAN_COMPUTATION_COMMAND_RECORD_BYTES &&
	       u64(size_of(Jan_Computation_Target_Record)) == JAN_COMPUTATION_TARGET_RECORD_BYTES &&
	       u64(size_of(Jan_Computation_Batch_Header_Record)) == JAN_COMPUTATION_BATCH_HEADER_BYTES &&
	       u64(size_of(Jan_Computation_Outcome_Record)) == JAN_COMPUTATION_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Jan_Computation_Availability_Record)) == JAN_COMPUTATION_AVAILABILITY_RECORD_BYTES &&
	       u64(size_of(Jan_Computation_Failure_Record)) == JAN_COMPUTATION_FAILURE_RECORD_BYTES
}
