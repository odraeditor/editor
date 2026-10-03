// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:testing"

/* Verifies the selected resource and deadline policies remain internally valid. */
@(test)
selected_limits_and_deadlines_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, service_limits_valid(DEFAULT_LIMITS))
	testing.expect(t, deadline_policy_valid(DEFAULT_DEADLINES))
	testing.expect_value(t, DEFAULT_RESTART_POLICY.automatic_restarts, u8(1))
	testing.expect_value(t, DEFAULT_RESTART_POLICY.stability_ns, DEFAULT_DEADLINES.restart_stability_ns)
}

/* Verifies copied byte ranges cannot escape or omit their owner generation. */
@(test)
storage_ranges_require_generation :: proc(t: ^testing.T) {
	testing.expect(t, storage_range_valid(Storage_Range{}, 64))
	testing.expect(t, storage_range_valid(Storage_Range{storage_generation = 1, offset = 8, length = 56}, 64))
	testing.expect(t, !storage_range_valid(Storage_Range{offset = 8, length = 1}, 64))
	testing.expect(t, !storage_range_valid(Storage_Range{storage_generation = 1, offset = 63, length = 2}, 64))
	testing.expect(t, !storage_range_valid(Storage_Range{storage_generation = 1, offset = max(u64), length = 2}, max(u64)))
}

/* Verifies aggregate resource accounting rejects selected limit excess. */
@(test)
resource_usage_rejects_each_aggregate_excess :: proc(t: ^testing.T) {
	usage := Resource_Usage {
		service_definitions = 1,
		providers = 1,
		sessions = 1,
		documents = 1,
		outstanding_requests = 1,
		notifications = 1,
		queue_depth = 1,
		queue_bytes = 1,
		synchronization_changes = 1,
		synchronization_bytes = 1,
		diagnostics = 1,
		diagnostic_bytes = 1,
		candidates = 1,
		candidate_text_bytes = 1,
		standard_error_bytes = 1,
		retained_bytes = 1,
		temporary_bytes = 1,
		work_bytes = 1,
	}
	testing.expect(t, resource_usage_valid(usage, DEFAULT_LIMITS))
	usage.queue_depth = DEFAULT_LIMITS.queue_depth + 1
	testing.expect(t, !resource_usage_valid(usage, DEFAULT_LIMITS))
	usage.queue_depth = 1
	usage.retained_bytes = DEFAULT_LIMITS.retained_bytes + 1
	testing.expect(t, !resource_usage_valid(usage, DEFAULT_LIMITS))
}

/* Verifies zero-valued contract records remain inert and invalid identities. */
@(test)
contract_records_have_useful_zero_values :: proc(t: ^testing.T) {
	testing.expect_value(t, Service_Definition{}.handle.id, Definition_ID(0))
	testing.expect_value(t, Session_Descriptor{}.health, Health.Stopped)
	testing.expect_value(t, Process_Descriptor{}.state, Process_State.None)
	testing.expect_value(t, Transport_Descriptor{}.state, Transport_State.None)
	testing.expect_value(t, Failure_Context{}.code, Failure_Code.None)
}
