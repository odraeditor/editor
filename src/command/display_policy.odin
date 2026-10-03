// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../layout"

/*
display_policy_apply_racket_configuration inspects one live native policy,
runs the current Racket configuration over its copy, and atomically replaces it.
*/
display_policy_apply_racket_configuration :: proc(
	runtime: ^hosting.Runtime,
	registry: ^bridge.Display_Policy_Capability_Registry,
	capability: bridge.Display_Policy_Capability,
) -> (snapshot: layout.Display_Policy_Snapshot, ok: bool, failure: Failure_Context) {
	current, inspected, inspect_failure := bridge.display_policy_capability_inspect(
		registry,
		capability,
	)
	if !inspected {
		return {}, false, bridge_failure_context({}, inspect_failure)
	}
	candidate, configured, configure_failure := hosting.runtime_display_policy_exchange(
		runtime,
		display_policy_hosting_record(current),
	)
	if !configured {
		return {}, false, hosting_failure_context({}, configure_failure)
	}
	policy := display_policy_from_hosting_record(candidate)
	replace_failure: bridge.Failure_Context
	snapshot, ok, replace_failure = bridge.display_policy_capability_replace(
		registry,
		capability,
		layout.Display_Policy_Generation(candidate.generation),
		policy,
	)
	if !ok {
		return {}, false, bridge_failure_context({}, replace_failure)
	}
	return snapshot, true, {}
}

@(private)
display_policy_hosting_record :: proc(
	snapshot: layout.Display_Policy_Snapshot,
) -> hosting.Display_Policy_Record {
	record := hosting.Display_Policy_Record {
		generation = u64(snapshot.generation),
		action_count = u64(snapshot.policy.action_count),
		split_height_threshold = u64(snapshot.policy.split_height_threshold),
		split_width_threshold = u64(snapshot.policy.split_width_threshold),
	}
	for action, index in snapshot.policy.actions {
		record.actions[index] = u64(action.kind)
	}
	return record
}

@(private)
display_policy_from_hosting_record :: proc(
	record: hosting.Display_Policy_Record,
) -> layout.Display_Policy {
	action_count := u16(record.action_count)
	if record.action_count > u64(max(u16)) {
		action_count = max(u16)
	}
	height := i32(record.split_height_threshold)
	if record.split_height_threshold > u64(max(i32)) {
		height = min(i32)
	}
	width := i32(record.split_width_threshold)
	if record.split_width_threshold > u64(max(i32)) {
		width = min(i32)
	}
	policy := layout.Display_Policy {
		action_count = action_count,
		split_height_threshold = height,
		split_width_threshold = width,
	}
	for action, index in record.actions {
		policy.actions[index].kind = layout.Display_Action_Kind(action)
	}
	return policy
}
