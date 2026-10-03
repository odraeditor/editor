// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

/* registry_resize_pane moves the active pane's nearest compatible divider by one cell. */
registry_resize_pane :: proc(
	registry: ^Registry,
	target: Pane_Handle,
	arrangement: Arrangement,
	delta: i32,
) -> (result: Resize_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, target.layout, .Resize)
	if resolved.code != .None {
		return {}, false, resolved
	}
	_, target_ref, target_failure := resolve_pane(data, target, .Resize)
	if target_failure.code != .None {
		return {}, false, target_failure
	}
	if target_ref != data.active {
		failure = resize_failure(data, target, .Invalid_Pane)
		return {}, false, failure
	}
	if (arrangement != .Above_Below && arrangement != .Left_Right) ||
	   (delta != -1 && delta != 1) {
		failure = resize_failure(data, target, .Invalid_Geometry)
		return {}, false, failure
	}
	if data.geometry_state == .Insufficient {
		failure = resize_failure(data, target, .Semantic_Insufficient)
		return {}, false, failure
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Resize)
	}
	if data.generation == Layout_Generation(max(u64)) {
		failure = resize_failure(data, target, .Generation_Limit)
		return {}, false, failure
	}
	proposed, prepared := prepared_state_copy(data, .Resize)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	child_ref := target_ref
	child := resolve_node(proposed, child_ref)
	assert(child != nil)
	partition_ref := child.parent
	partition := resolve_node(proposed, partition_ref)
	for partition != nil && partition.arrangement != arrangement {
		child_ref = partition_ref
		partition_ref = partition.parent
		partition = resolve_node(proposed, partition_ref)
	}
	if partition == nil {
		failure = resize_failure(data, target, .No_Compatible_Divider)
		return {}, false, failure
	}
	first := resolve_node(proposed, partition.first)
	second := resolve_node(proposed, partition.second)
	if first == nil || second == nil {
		failure = resize_failure(data, target, .Invalid_Topology)
		return {}, false, failure
	}
	first_span := first.geometry.outer.height
	second_span := second.geometry.outer.height
	if arrangement == .Left_Right {
		first_span = first.geometry.outer.width
		second_span = second.geometry.outer.width
	}
	first_delta := i64(delta)
	if child_ref == partition.second {
		first_delta = -first_delta
	} else if child_ref != partition.first {
		failure = resize_failure(data, target, .Invalid_Parent)
		return {}, false, failure
	}
	new_first := i64(first_span) + first_delta
	new_second := i64(second_span) - first_delta
	if new_first > i64(max(i32)) || new_second > i64(max(i32)) {
		failure = resize_failure(data, target, .Checked_Integer_Overflow)
		return {}, false, failure
	}
	if new_first <= 0 || new_second <= 0 {
		failure = resize_failure(data, target, .Operating_Minimum)
		return {}, false, failure
	}
	partition.first_weight = u64(new_first)
	partition.second_weight = u64(new_second)
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.Operating,
		.Resize,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	first = resolve_node(proposed, partition.first)
	second = resolve_node(proposed, partition.second)
	actual_first := first.geometry.outer.height
	actual_second := second.geometry.outer.height
	if arrangement == .Left_Right {
		actual_first = first.geometry.outer.width
		actual_second = second.geometry.outer.width
	}
	if actual_first != i32(new_first) || actual_second != i32(new_second) {
		failure = resize_failure(data, target, .Operating_Minimum)
		return {}, false, failure
	}
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	if !validate_layout_state(proposed) {
		failure = resize_failure(data, target, .Invalid_Topology)
		return {}, false, failure
	}
	partition_id := partition.node_id
	result = Resize_Result {
		layout = current_layout_handle(proposed),
		pane = pane_handle(proposed, target_ref),
		partition_id = partition_id,
		arrangement = arrangement,
		delta = delta,
		first_span = i32(new_first),
		second_span = i32(new_second),
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
resize_failure :: proc(
	data: ^Registry_Data,
	pane: Pane_Handle,
	code: Failure_Code,
) -> Failure_Context {
	failure := data_failure(data, .Resize, code)
	failure.pane = pane
	return failure
}
