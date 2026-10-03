// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../jan_computation"
import "core:testing"

/* Verifies computation records remain fixed, bounded, and generation explicit. */
@(test)
jan_computation_records_are_pointer_free_and_checked :: proc(t: ^testing.T) {
	testing.expect(t, jan_computation_record_layout_is_valid())
	record := Jan_Computation_Command_Record {
		scope = {schema_version = JAN_COMPUTATION_SCHEMA_VERSION, operation_id = 9,
		         configuration_generation = 3, adapter_generation = 4, policy_generation = 5,
		         document_id = 6, source_revision = 7, analysis_generation = 8,
		         baseline_generation = 1, invocation = u64(jan_computation.Invocation_Context.Interactive)},
		command = u64(Jan_Computation_Command.Execute),
		target_count = 1,
		payload_bytes = 12,
	}
	testing.expect(t, jan_computation_command_record_is_valid(record))
	record.scope.policy_generation = 0
	testing.expect(t, !jan_computation_command_record_is_valid(record))
	record.scope.policy_generation = 5
	record.command = u64(Jan_Computation_Command.Batch)
	record.batch_mode = u64(jan_computation.Batch_Mode.Atomic)
	testing.expect(t, jan_computation_command_record_is_valid(record))
}

/* Verifies atomic summaries and capability records reject inconsistent state. */
@(test)
jan_computation_records_validate_batch_and_availability :: proc(t: ^testing.T) {
	outcomes := []Jan_Computation_Outcome_Record {
		{operation_id = 1, state = u64(jan_computation.Batch_Target_State.Completed), byte_count = 8, row_count = 1},
		{operation_id = 2, state = u64(jan_computation.Batch_Target_State.Rejected),
		 failure_code = u64(jan_computation.Failure_Code.Evaluation)},
	}
	header := Jan_Computation_Batch_Header_Record {
		schema_version = JAN_COMPUTATION_SCHEMA_VERSION,
		batch_id = 3,
		mode = u64(jan_computation.Batch_Mode.Atomic),
		target_count = 2,
		executed = 1,
		rejected = 1,
		output_bytes = 8,
		result_rows = 1,
	}
	testing.expect(t, jan_computation_batch_records_are_valid(header, outcomes))
	header.published = 1
	testing.expect(t, !jan_computation_batch_records_are_valid(header, outcomes))
	availability := Jan_Computation_Availability_Record {
		capability = u64(jan_computation.Capability.Execution),
		class = u64(jan_computation.Availability_Class.Factory_Adapter),
		state = u64(jan_computation.Availability_State.Available),
		adapter_generation = 7,
	}
	testing.expect(t, jan_computation_availability_record_is_valid(availability))
	availability.adapter_generation = 0
	testing.expect(t, !jan_computation_availability_record_is_valid(availability))
}
