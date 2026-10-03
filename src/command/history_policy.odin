// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../history"
import "../hosting"

/*
history_policy_apply_racket_configuration inspects one live native policy,
runs the current Racket configuration over its copy, and atomically replaces it.
*/
history_policy_apply_racket_configuration :: proc(
	runtime: ^hosting.Runtime,
	registry: ^bridge.History_Policy_Capability_Registry,
	capability: bridge.History_Policy_Capability,
) -> (result: history.Policy_Replacement_Result, ok: bool, failure: Failure_Context) {
	snapshot, inspected, inspect_failure := bridge.history_policy_capability_inspect(
		registry,
		capability,
	)
	if !inspected {
		return {}, false, bridge_failure_context({}, inspect_failure)
	}
	candidate, configured, configure_failure := hosting.runtime_history_policy_exchange(
		runtime,
		history_policy_hosting_record(snapshot),
	)
	if !configured {
		return {}, false, hosting_failure_context({}, configure_failure)
	}
	policy := history_policy_from_hosting_record(candidate)
	replace_failure: bridge.Failure_Context
	result, ok, replace_failure = bridge.history_policy_capability_replace(
		registry,
		capability,
		history.Policy_Replacement_Request{
			expected_generation = history.Policy_Generation(candidate.generation),
			policy = policy,
			operation_limit = policy.pruning_operations,
		},
	)
	if !ok {
		return {}, false, bridge_failure_context({}, replace_failure)
	}
	return result, true, {}
}

@(private)
history_policy_hosting_record :: proc(
	snapshot: history.Policy_Snapshot,
) -> hosting.History_Policy_Record {
	policy := snapshot.policy
	return hosting.History_Policy_Record{
		generation = u64(snapshot.policy_generation),
		fields = {
			policy.global_retained_bytes,
			policy.buffer_retained_bytes,
			policy.global_nodes,
			policy.buffer_nodes,
			policy.guaranteed_recent_units,
			policy.retained_depth,
			policy.sibling_branches,
			policy.records_per_unit,
			policy.payload_bytes_per_unit,
			policy.multibuffer_participants,
			policy.selective_operations,
			policy.inspection_nodes,
			policy.pruning_operations,
		},
	}
}

@(private)
history_policy_from_hosting_record :: proc(
	record: hosting.History_Policy_Record,
) -> history.Policy {
	return history.Policy{
		global_retained_bytes = record.fields[0],
		buffer_retained_bytes = record.fields[1],
		global_nodes = record.fields[2],
		buffer_nodes = record.fields[3],
		guaranteed_recent_units = record.fields[4],
		retained_depth = record.fields[5],
		sibling_branches = record.fields[6],
		records_per_unit = record.fields[7],
		payload_bytes_per_unit = record.fields[8],
		multibuffer_participants = record.fields[9],
		selective_operations = record.fields[10],
		inspection_nodes = record.fields[11],
		pruning_operations = record.fields[12],
	}
}
