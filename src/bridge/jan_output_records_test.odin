// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../jan_output"
import "core:testing"

/* Verifies output records remain fixed, bounded, and generation explicit. */
@(test)
jan_output_records_are_pointer_free_and_checked :: proc(t: ^testing.T) {
	testing.expect(t, jan_output_record_layout_is_valid())
	record := Jan_Output_Command_Record {
		scope = {schema_version = JAN_OUTPUT_BRIDGE_SCHEMA_VERSION, operation_id = 9,
		         configuration_generation = 3, backend_generation = 4, filter_generation = 5,
		         provider_generation = 6, document_id = 7, source_revision = 8,
		         analysis_generation = 9, baseline_generation = 1, source_bytes = 128},
		command = u64(Jan_Output_Command.Export),
		selection_kind = u64(jan_output.Export_Scope_Kind.Document),
		target_count = 1,
		payload_bytes = 12,
	}
	testing.expect(t, jan_output_command_record_is_valid(record))
	record.scope.provider_generation = 0
	testing.expect(t, !jan_output_command_record_is_valid(record))
}

/* Verifies publication accounting and capability availability reject ambiguity. */
@(test)
jan_output_records_validate_manifests_and_availability :: proc(t: ^testing.T) {
	manifest := Jan_Output_Manifest_Record {
		schema_version = JAN_OUTPUT_BRIDGE_SCHEMA_VERSION,
		manifest_id = 3,
		entry_count = 2,
		prepared = 2,
		published = 1,
		reused = 1,
		output_bytes = 32,
		complete = 1,
	}
	testing.expect(t, jan_output_manifest_record_is_valid(manifest))
	manifest.failed = 1
	testing.expect(t, !jan_output_manifest_record_is_valid(manifest))
	availability := Jan_Output_Availability_Record {
		capability = u64(jan_output.Capability.Publishing),
		class = u64(jan_output.Availability_Class.Configured_Provider),
		state = u64(jan_output.Availability_State.Unavailable),
	}
	testing.expect(t, jan_output_availability_record_is_valid(availability))
	availability.state = u64(jan_output.Availability_State.Available)
	testing.expect(t, !jan_output_availability_record_is_valid(availability))
}
