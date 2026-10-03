// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

/* Verifies every accepted Computable Documents ceiling independently. */
@(test)
computation_contracts_fix_resource_limits :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	invalid := DEFAULT_LIMITS
	invalid.table_cells = MAX_TABLE_CELLS + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.formula_dependencies = MAX_FORMULA_DEPENDENCIES + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.active_sessions = MAX_ACTIVE_SESSIONS + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.elapsed_milliseconds = 0
	testing.expect(t, !limits_are_valid(invalid))
}

/* Verifies exact scopes, targets, and explicit requests reject stale candidates. */
@(test)
computation_contracts_require_exact_requests :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	target := computation_test_target(scope)
	request := Request {
		operation_id = 1,
		kind = .Execute,
		scope = scope,
		targets = []Semantic_Target{target},
		limits = DEFAULT_LIMITS,
		invocation = .Interactive,
		effects = {.Child_Process},
	}
	testing.expect(t, request_is_valid(request))
	request.targets[0].range.scope.source_revision += 1
	testing.expect(t, !request_is_valid(request))
	request.targets[0] = target
	request.scope.policy_generation = 0
	testing.expect(t, !request_is_valid(request))
}

/* Verifies typed results, sessions, cache keys, extraction, and batch accounting. */
@(test)
computation_contracts_validate_lifecycle_records :: proc(t: ^testing.T) {
	result := Typed_Result_Descriptor {
		operation_id = 3,
		type = .Table,
		collection = .Value,
		format = .Table,
		handling = .Replace,
		row_count = 12,
		byte_count = 512,
		complete = true,
	}
	testing.expect(t, typed_result_descriptor_is_valid(result))
	session := Session_Record {
		schema_version = COMPUTATION_SCHEMA_VERSION,
		session_id = 5,
		adapter_generation = 7,
		policy_generation = 11,
		source_revision = 13,
		state = .Active,
	}
	testing.expect(t, session_record_is_valid(session))
	key := Cache_Key{adapter_generation = 7, policy_generation = 11}
	key.source_digest[0] = 1
	key.argument_digest[0] = 2
	key.input_digest[0] = 3
	key.reference_digest[0] = 4
	key.environment_digest[0] = 5
	key.adapter_identity_digest[0] = 6
	key.adapter_version_digest[0] = 7
	key.cache_policy_digest[0] = 8
	testing.expect(t, cache_key_is_valid(key))
	scope := computation_test_scope()
	testing.expect(t, extraction_descriptor_is_valid({
		operation_id = 17,
		scope = scope,
		target_count = 2,
		resource_count = 1,
		byte_count = 128,
		complete = true,
	}))
	testing.expect(t, batch_descriptor_is_valid({
		batch_id = 19,
		mode = .Atomic,
		target_count = 4,
		completed = 4,
	}))
}

/* Verifies every computation family is declared exactly once. */
@(test)
computation_contracts_declare_inventory :: proc(t: ^testing.T) {
	records := computation_capability_declarations()
	seen: bit_set[Capability]
	for record in records {
		testing.expect(t, record.capability > .Invalid && record.capability <= .Batch)
		testing.expect_value(t, record.state, Availability_State.Declared)
		testing.expect(t, record.capability not_in seen)
		seen += {record.capability}
	}
	testing.expect_value(t, len(records), 11)
	testing.expect(t, .Formulas in seen && .Execution in seen && .Tangling in seen)
}
