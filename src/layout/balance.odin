// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

@(private)
Dimension_Units :: struct {
	rows:    u64,
	columns: u64,
}

/* registry_balance_panes balances visible leaf dimensions without changing topology. */
registry_balance_panes :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
) -> (result: Balance_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Balance_Dimensions)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if data.geometry_state == .Insufficient {
		return {}, false, data_failure(data, .Balance_Dimensions, .Semantic_Insufficient)
	}
	if data.partition_count == 0 {
		return Balance_Result {
			layout = current_layout_handle(data),
			active_pane = pane_handle(data, data.active),
		}, true, {}
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Balance_Dimensions)
	}
	proposed, prepared := prepared_state_copy(data, .Balance_Dimensions)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	units: [MAX_NODES]Dimension_Units
	work: u64
	_, measured, measure_failure := balance_measure(proposed, proposed.root, &units, &work)
	if !measured {
		return {}, false, measure_failure
	}
	weighted, weight_failure := balance_set_unit_weights(proposed, proposed.root, &units, &work)
	if !weighted {
		return {}, false, weight_failure
	}
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.Operating,
		.Balance_Dimensions,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	if work > proposed.policy.geometry_work - proposed.geometry_work {
		return {}, false, data_failure(data, .Balance_Dimensions, .Geometry_Work_Limit)
	}
	work += proposed.geometry_work
	persisted, persist_failure := balance_persist_spans(proposed, proposed.root, &work)
	if !persisted {
		return {}, false, persist_failure
	}
	proposed.geometry_work = work
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	if balance_weights_equal(data, proposed) {
		return Balance_Result {
			layout = current_layout_handle(data),
			active_pane = pane_handle(data, data.active),
		}, true, {}
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Balance_Dimensions, .Generation_Limit)
	}
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	result = Balance_Result {
		layout = current_layout_handle(proposed),
		active_pane = pane_handle(proposed, proposed.active),
		changed = true,
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
balance_measure :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	units: ^[MAX_NODES]Dimension_Units,
	work: ^u64,
) -> (Dimension_Units, bool, Failure_Context) {
	if !consume_geometry_work(data, work) {
		return {}, false, data_failure(data, .Balance_Dimensions, .Geometry_Work_Limit)
	}
	slot := resolve_node(data, ref)
	if slot == nil {
		return {}, false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	if slot.kind == .Pane {
		units[int(ref.slot)] = Dimension_Units{rows = 1, columns = 1}
		return units[int(ref.slot)], true, {}
	}
	first, first_ok, first_failure := balance_measure(data, slot.first, units, work)
	if !first_ok {
		return {}, false, first_failure
	}
	second, second_ok, second_failure := balance_measure(data, slot.second, units, work)
	if !second_ok {
		return {}, false, second_failure
	}
	result: Dimension_Units
	if slot.arrangement == .Above_Below {
		if first.rows > max(u64) - second.rows {
			return {}, false, data_failure(data, .Balance_Dimensions, .Checked_Integer_Overflow)
		}
		result = Dimension_Units {
			rows = first.rows + second.rows,
			columns = max(first.columns, second.columns),
		}
	} else if slot.arrangement == .Left_Right {
		if first.columns > max(u64) - second.columns {
			return {}, false, data_failure(data, .Balance_Dimensions, .Checked_Integer_Overflow)
		}
		result = Dimension_Units {
			rows = max(first.rows, second.rows),
			columns = first.columns + second.columns,
		}
	} else {
		return {}, false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	units[int(ref.slot)] = result
	return result, true, {}
}

@(private)
balance_set_unit_weights :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	units: ^[MAX_NODES]Dimension_Units,
	work: ^u64,
) -> (bool, Failure_Context) {
	if !consume_geometry_work(data, work) {
		return false, data_failure(data, .Balance_Dimensions, .Geometry_Work_Limit)
	}
	slot := resolve_node(data, ref)
	if slot == nil {
		return false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	if slot.kind == .Pane {
		return true, {}
	}
	first := units[int(slot.first.slot)]
	second := units[int(slot.second.slot)]
	if slot.arrangement == .Above_Below {
		slot.first_weight = first.rows
		slot.second_weight = second.rows
	} else if slot.arrangement == .Left_Right {
		slot.first_weight = first.columns
		slot.second_weight = second.columns
	} else {
		return false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	first_ok, first_failure := balance_set_unit_weights(data, slot.first, units, work)
	if !first_ok {
		return false, first_failure
	}
	return balance_set_unit_weights(data, slot.second, units, work)
}

@(private)
balance_persist_spans :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	work: ^u64,
) -> (bool, Failure_Context) {
	if !consume_geometry_work(data, work) {
		return false, data_failure(data, .Balance_Dimensions, .Geometry_Work_Limit)
	}
	slot := resolve_node(data, ref)
	if slot == nil {
		return false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	if slot.kind == .Pane {
		return true, {}
	}
	first := resolve_node(data, slot.first)
	second := resolve_node(data, slot.second)
	if first == nil || second == nil {
		return false, data_failure(data, .Balance_Dimensions, .Invalid_Topology)
	}
	first_span := first.geometry.outer.height
	second_span := second.geometry.outer.height
	if slot.arrangement == .Left_Right {
		first_span = first.geometry.outer.width
		second_span = second.geometry.outer.width
	}
	if first_span <= 0 || second_span <= 0 {
		return false, data_failure(data, .Balance_Dimensions, .Invalid_Geometry)
	}
	slot.first_weight = u64(first_span)
	slot.second_weight = u64(second_span)
	first_ok, first_failure := balance_persist_spans(data, slot.first, work)
	if !first_ok {
		return false, first_failure
	}
	return balance_persist_spans(data, slot.second, work)
}

@(private)
balance_weights_equal :: proc(first, second: ^Registry_Data) -> bool {
	for &slot, index in first.nodes {
		if slot.live && slot.kind == .Partition &&
		   (slot.first_weight != second.nodes[index].first_weight ||
		    slot.second_weight != second.nodes[index].second_weight) {
			return false
		}
	}
	return true
}
