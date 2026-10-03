// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies exact scope, selection, limits, and destination boundaries. */
@(test)
output_contracts_require_exact_bounded_values :: proc(t: ^testing.T) {
	scope := output_test_scope()
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	testing.expect(t, scope_is_valid(scope))
	testing.expect(t, selection_is_valid(output_test_selection(scope), scope))
	testing.expect(t, destination_is_valid({kind = .Preview}))
	testing.expect(t, destination_is_valid({kind = .Resource, resource_id = 7, expected_revision = 9}))
	testing.expect(t, projection_policy_is_valid({contents = true, contents_depth = 3}))
	testing.expect(t, diagnostic_record_is_valid({severity = .Warning, field = .Include,
		source_start = 4, source_end = 8, message_bytes = 12}, scope))
	invalid_limits := DEFAULT_LIMITS
	invalid_limits.normalized_nodes = MAX_NORMALIZED_NODES + 1
	testing.expect(t, !limits_are_valid(invalid_limits))
	stale := output_test_selection(scope)
	stale.range.scope.source_revision += 1
	testing.expect(t, !selection_is_valid(stale, scope))
	testing.expect(t, !destination_is_valid({kind = .Resource, resource_id = 7}))
	testing.expect(t, !projection_policy_is_valid({contents = true}))
}

/* Verifies copied trees, output descriptors, and durable records stay bounded. */
@(test)
output_contract_records_reject_partial_or_stale_shapes :: proc(t: ^testing.T) {
	scope := output_test_scope()
	tree := Normalized_Tree {scope = scope, node_count = 4, link_count = 1, byte_count = 64, complete = true}
	tree.digest[0] = 1
	testing.expect(t, normalized_tree_is_valid(tree))
	tree.complete = false
	testing.expect(t, !normalized_tree_is_valid(tree))
	descriptor := Output_Descriptor {operation_id = 3, backend_generation = scope.backend_generation,
		filter_generation = scope.filter_generation, output_bytes = 64, diagnostic_count = 1,
		resource_count = 1, complete = true}
	testing.expect(t, output_descriptor_is_valid(descriptor))
	descriptor.output_bytes = MAX_OUTPUT_BYTES + 1
	testing.expect(t, !output_descriptor_is_valid(descriptor))
	manifest := Publication_Manifest_Record {schema_version = OUTPUT_SCHEMA_VERSION, manifest_id = 5,
		operation_id = 3, configuration_generation = scope.configuration_generation,
		backend_generation = scope.backend_generation, filter_generation = scope.filter_generation,
		entry_count = 2, target_count = 1, state = .Candidate}
	testing.expect(t, publication_manifest_is_valid(manifest))
	manifest.state = .Invalid
	testing.expect(t, !publication_manifest_is_valid(manifest))
}

/* Verifies external families remain bounded, explicit, and non-authorizing. */
@(test)
output_external_contracts_are_explicit_and_recoverable :: proc(t: ^testing.T) {
	protocol := Protocol_Request {operation_id = 7, provider_generation = 11, payload_bytes = 512, explicit = true}
	testing.expect(t, protocol_request_is_valid(protocol))
	protocol.explicit = false
	testing.expect(t, !protocol_request_is_valid(protocol))
	synchronization := Synchronization_Manifest_Record {schema_version = OUTPUT_SCHEMA_VERSION,
		manifest_id = 13, provider_generation = 17, entry_count = 4, conflict_count = 1, state = .Conflicted}
	testing.expect(t, synchronization_manifest_is_valid(synchronization))
	synchronization.conflict_count = 5
	testing.expect(t, !synchronization_manifest_is_valid(synchronization))
	extension := Extension_Record {identity = "custom-html", class = .Configured_Provider,
		provider_generation = 19, resource_count = 2, available = true}
	testing.expect(t, extension_record_is_valid(extension))
}

/* Verifies the complete capability inventory has stable ownership classes. */
@(test)
output_capabilities_are_complete_and_declarative :: proc(t: ^testing.T) {
	records := output_capability_declarations()
	testing.expect_value(t, len(records), 17)
	for record, index in records {
		testing.expect(t, record.capability != .Invalid)
		testing.expect(t, record.class != .Invalid)
		testing.expect_value(t, record.state, Availability_State.Declared)
		for prior in records[:index] do testing.expect(t, prior.capability != record.capability)
	}
}
