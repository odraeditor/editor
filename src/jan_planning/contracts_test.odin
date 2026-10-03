// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:testing"

/* Verifies every accepted Planning and Agenda resource ceiling independently. */
@(test)
planning_contracts_fix_resource_limits :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	invalid := DEFAULT_LIMITS
	invalid.semantic_targets = MAX_SEMANTIC_TARGETS + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.source_documents = MAX_SOURCE_DOCUMENTS + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.agenda_entries = MAX_AGENDA_ENTRIES + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.derived_state_bytes = MAX_DERIVED_STATE_BYTES + 1
	testing.expect(t, !limits_are_valid(invalid))
}

/* Verifies every Planning family has one declaration and final operational state. */
@(test)
planning_contracts_declare_inventory :: proc(t: ^testing.T) {
	records := planning_capability_declarations()
	seen: bit_set[Capability]
	for record in records {
		testing.expect(t, record.capability > .Invalid && record.capability <= .Agenda)
		testing.expect_value(t, record.state, Availability_State.Declared)
		testing.expect(t, record.capability not_in seen)
		seen += {record.capability}
	}
	testing.expect_value(t, len(records), 8)
	testing.expect(t, .Tasks in seen && .Time in seen && .Agenda in seen)
	available := planning_capability_availability(17, true, false)
	for record in available {
		if record.capability == .Feeds {
			testing.expect_value(t, record.state, Availability_State.Unavailable)
			testing.expect_value(t, record.provider_generation, Provider_Generation(17))
		} else {
			testing.expect_value(t, record.state, Availability_State.Available)
		}
	}
}

/* Verifies exact scopes, targets, and request bounds reject stale candidates. */
@(test)
planning_contracts_require_exact_requests :: proc(t: ^testing.T) {
	scope := planning_test_scope()
	target := planning_test_target(scope)
	request := Request {
		operation_id = 1,
		kind = .Task,
		scope = scope,
		targets = []Semantic_Target{target},
		limits = DEFAULT_LIMITS,
	}
	testing.expect(t, request_is_valid(request))
	request.targets[0].range.scope.source_revision += 1
	testing.expect(t, !request_is_valid(request))
	request.targets[0] = target
	request.scope.configuration_generation = 0
	testing.expect(t, !request_is_valid(request))
}
