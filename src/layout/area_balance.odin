// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

@(private)
Area_Balance_Score :: struct {
	pairwise_difference: u128,
	range:               u64,
	partition_count:     u16,
	first_spans:         [MAX_PARTITIONS]u64,
}

@(private)
Area_Balance_Search :: struct {
	data:             ^Registry_Data,
	partitions:       [MAX_PARTITIONS]Node_Ref,
	partition_count:  u16,
	minimums:         [MAX_NODES]Minimum,
	work:             u64,
	work_limit:       u64,
	exhausted:        bool,
	failed:           bool,
	failure:          Failure_Context,
	have_best:        bool,
	best_score:       Area_Balance_Score,
	best_first:       [MAX_NODES]u64,
	best_second:      [MAX_NODES]u64,
}

/* registry_balance_pane_areas minimizes exact final leaf-area imbalance. */
registry_balance_pane_areas :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
) -> (result: Balance_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Balance_Areas)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if data.geometry_state == .Insufficient {
		return {}, false, data_failure(data, .Balance_Areas, .Semantic_Insufficient)
	}
	if data.partition_count == 0 {
		return Balance_Result {
			layout = current_layout_handle(data),
			active_pane = pane_handle(data, data.active),
		}, true, {}
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Balance_Areas)
	}
	proposed, prepared := prepared_state_copy(data, .Balance_Areas)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	search := Area_Balance_Search {
		data = proposed,
		work_limit = proposed.policy.geometry_work,
	}
	area_balance_collect_partitions(proposed, proposed.root, &search)
	if search.partition_count != proposed.partition_count {
		return {}, false, data_failure(data, .Balance_Areas, .Invalid_Topology)
	}
	minimum_work: u64
	_, minimum_ok, minimum_failure := compute_minimum(
		proposed,
		proposed.root,
		true,
		&search.minimums,
		&minimum_work,
		.Balance_Areas,
	)
	if !minimum_ok {
		return {}, false, minimum_failure
	}
	area_balance_search(&search, 0)
	if search.failed {
		return {}, false, search.failure
	}
	if search.exhausted || !search.have_best {
		failure = data_failure(data, .Balance_Areas, .Geometry_Work_Limit)
		failure.maximum = search.work_limit
		failure.actual = search.work + 1
		return {}, false, failure
	}
	for ref in search.partitions[:search.partition_count] {
		slot := resolve_node(proposed, ref)
		if slot == nil || search.best_first[int(ref.slot)] == 0 ||
		   search.best_second[int(ref.slot)] == 0 {
			return {}, false, data_failure(data, .Balance_Areas, .Invalid_Topology)
		}
		slot.first_weight = search.best_first[int(ref.slot)]
		slot.second_weight = search.best_second[int(ref.slot)]
	}
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.Operating,
		.Balance_Areas,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	if search.work > proposed.policy.geometry_work - proposed.geometry_work {
		failure = data_failure(data, .Balance_Areas, .Geometry_Work_Limit)
		failure.maximum = proposed.policy.geometry_work
		failure.actual = search.work + proposed.geometry_work
		return {}, false, failure
	}
	proposed.geometry_work += search.work
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Balance_Areas, .Invalid_Topology)
	}
	if balance_weights_equal(data, proposed) {
		return Balance_Result {
			layout = current_layout_handle(data),
			active_pane = pane_handle(data, data.active),
		}, true, {}
	}
	if data.generation == Layout_Generation(max(u64)) {
		return {}, false, data_failure(data, .Balance_Areas, .Generation_Limit)
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
area_balance_collect_partitions :: proc(
	data: ^Registry_Data,
	ref: Node_Ref,
	search: ^Area_Balance_Search,
) {
	slot := resolve_node(data, ref)
	if slot == nil || slot.kind != .Partition {
		return
	}
	search.partitions[int(search.partition_count)] = ref
	search.partition_count += 1
	area_balance_collect_partitions(data, slot.first, search)
	area_balance_collect_partitions(data, slot.second, search)
}

@(private)
area_balance_search :: proc(search: ^Area_Balance_Search, depth: int) {
	if search.exhausted || search.failed {
		return
	}
	if depth == int(search.partition_count) {
		materialized, failure := geometry_materialize_data(
			search.data,
			search.data.geometry_request,
			.Operating,
			.Balance_Areas,
			false,
		)
		if !materialized {
			search.failed = true
			search.failure = failure
			return
		}
		score, scored := area_balance_score(search.data, search.partitions[:search.partition_count])
		if !scored {
			search.failed = true
			search.failure = data_failure(search.data, .Balance_Areas, .Checked_Integer_Overflow)
			return
		}
		if !search.have_best || area_balance_score_better(score, search.best_score) {
			search.best_score = score
			search.have_best = true
			for ref in search.partitions[:search.partition_count] {
				slot := resolve_node(search.data, ref)
				if slot == nil {
					search.failed = true
					search.failure = data_failure(search.data, .Balance_Areas, .Invalid_Topology)
					return
				}
				search.best_first[int(ref.slot)] = slot.first_weight
				search.best_second[int(ref.slot)] = slot.second_weight
			}
		}
		return
	}
	materialized, failure := geometry_materialize_data(
		search.data,
		search.data.geometry_request,
		.Operating,
		.Balance_Areas,
		false,
	)
	if !materialized {
		search.failed = true
		search.failure = failure
		return
	}
	ref := search.partitions[depth]
	partition := resolve_node(search.data, ref)
	if partition == nil || partition.kind != .Partition {
		search.failed = true
		search.failure = data_failure(search.data, .Balance_Areas, .Invalid_Topology)
		return
	}
	axis := partition.geometry.outer.height
	first_floor := search.minimums[int(partition.first.slot)].rows
	second_floor := search.minimums[int(partition.second.slot)].rows
	if partition.arrangement == .Left_Right {
		axis = partition.geometry.outer.width - 1
		first_floor = search.minimums[int(partition.first.slot)].columns
		second_floor = search.minimums[int(partition.second.slot)].columns
	}
	maximum_first := axis - second_floor
	for first_span := first_floor; first_span <= maximum_first; first_span += 1 {
		if search.work == search.work_limit {
			search.exhausted = true
			return
		}
		search.work += 1
		partition.first_weight = u64(first_span)
		partition.second_weight = u64(axis - first_span)
		area_balance_search(search, depth + 1)
		if search.exhausted || search.failed {
			return
		}
	}
}

@(private)
area_balance_score :: proc(
	data: ^Registry_Data,
	partitions: []Node_Ref,
) -> (score: Area_Balance_Score, ok: bool) {
	areas: [MAX_LIVE_PANES]u64
	count: int
	for &slot in data.nodes {
		if slot.live && slot.kind == .Pane {
			area := rect_area(slot.geometry.outer)
			if area == 0 {
				return {}, false
			}
			areas[count] = area
			count += 1
		}
	}
	if count != int(data.pane_count) {
		return {}, false
	}
	minimum_area := max(u64)
	maximum_area: u64
	for area in areas[:count] {
		minimum_area = min(minimum_area, area)
		maximum_area = max(maximum_area, area)
	}
	for first_index in 0 ..< count {
		for second_index in first_index + 1 ..< count {
			first := areas[first_index]
			second := areas[second_index]
			difference := first - second if first >= second else second - first
			if score.pairwise_difference > max(u128) - u128(difference) {
				return {}, false
			}
			score.pairwise_difference += u128(difference)
		}
	}
	score.range = maximum_area - minimum_area
	for ref, index in partitions {
		slot := resolve_node(data, ref)
		if slot == nil || slot.kind != .Partition {
			return {}, false
		}
		score.first_spans[index] = slot.first_weight
		score.partition_count += 1
	}
	return score, true
}

@(private)
area_balance_score_better :: proc(candidate, current: Area_Balance_Score) -> bool {
	if candidate.pairwise_difference != current.pairwise_difference {
		return candidate.pairwise_difference < current.pairwise_difference
	}
	if candidate.range != current.range {
		return candidate.range < current.range
	}
	for index in 0 ..< int(candidate.partition_count) {
		if candidate.first_spans[index] != current.first_spans[index] {
			return candidate.first_spans[index] < current.first_spans[index]
		}
	}
	return false
}
