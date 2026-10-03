// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package layout_reference provides an independent fixed-array pane-tree oracle.
package layout_reference

MAX_PANES :: 128
MAX_NODES :: MAX_PANES * 2 - 1
MAX_DEPTH :: u16(32)
AREA_BALANCE_ORACLE_WORK_LIMIT :: u64(1_048_576)
CONTENT_ROWS :: i32(2)
STATUS_ROWS :: i32(2)
PANE_COLUMNS :: i32(8)

Arrangement :: enum u8 {
	Invalid,
	Above_Below,
	Left_Right,
}

Kind :: enum u8 {
	Invalid,
	Partition,
	Pane,
}

Rect :: struct {
	row:    i32,
	column: i32,
	height: i32,
	width:  i32,
}

Geometry :: struct {
	outer:     Rect,
	content:   Rect,
	status:    Rect,
	separator: Rect,
}

Node :: struct {
	live:          bool,
	kind:          Kind,
	id:            u64,
	parent:        int,
	depth:         u16,
	arrangement:   Arrangement,
	first:         int,
	second:        int,
	first_weight:  u64,
	second_weight: u64,
	pane_id:       u64,
	geometry:      Geometry,
}

Descriptor :: struct {
	kind:            Kind,
	id:              u64,
	parent_id:       u64,
	depth:           u16,
	arrangement:     Arrangement,
	first_id:        u64,
	second_id:       u64,
	first_weight:    u64,
	second_weight:   u64,
	pane_id:         u64,
	geometry:        Geometry,
	active:          bool,
	mru_rank:        u16,
}

Snapshot :: struct {
	root_id:        u64,
	active_pane_id: u64,
	node_count:     u16,
	pane_count:     u16,
	partition_count: u16,
	nodes:          [MAX_NODES]Descriptor,
}

Area_Balance_Score :: struct {
	pairwise_difference: u128,
	range:               u64,
	leaf_count:          u16,
	partition_count:     u16,
	first_spans:         [MAX_PANES - 1]u64,
}

Model :: struct {
	rows:            i32,
	columns:         i32,
	root:            int,
	active:          int,
	mru:             [MAX_PANES]int,
	mru_count:       u16,
	node_count:      u16,
	pane_count:      u16,
	partition_count: u16,
	next_node_id:    u64,
	next_pane_id:    u64,
	nodes:           [MAX_NODES]Node,
}

model_init :: proc(rows, columns: i32) -> (model: Model, ok: bool) {
	if rows < CONTENT_ROWS + STATUS_ROWS || columns < PANE_COLUMNS {
		return {}, false
	}
	model.rows = rows
	model.columns = columns
	model.root = 0
	model.active = 0
	model.mru[0] = 0
	model.mru_count = 1
	model.node_count = 1
	model.pane_count = 1
	model.next_node_id = 2
	model.next_pane_id = 2
	model.nodes[0] = Node{live = true, kind = .Pane, id = 1, parent = -1, pane_id = 1}
	return model, model_materialize(&model)
}

model_split :: proc(model: ^Model, arrangement: Arrangement) -> (pane_id: u64, ok: bool) {
	if !model_validate(model) || model.pane_count >= MAX_PANES ||
	   (arrangement != .Above_Below && arrangement != .Left_Right) {
		return 0, false
	}
	source_index := model.active
	source := model.nodes[source_index]
	if source.depth >= MAX_DEPTH {
		return 0, false
	}
	proposed := model^
	partition_index, partition_ok := model_allocate(&proposed)
	pane_index, pane_ok := model_allocate(&proposed)
	if !partition_ok || !pane_ok {
		return 0, false
	}
	proposed.nodes[partition_index] = Node {
		live = true,
		kind = .Partition,
		id = proposed.next_node_id,
		parent = source.parent,
		depth = source.depth,
		arrangement = arrangement,
		first = source_index,
		second = pane_index,
		first_weight = 1,
		second_weight = 1,
	}
	proposed.next_node_id += 1
	pane_id = proposed.next_pane_id
	proposed.nodes[pane_index] = Node {
		live = true,
		kind = .Pane,
		id = proposed.next_node_id,
		parent = partition_index,
		depth = source.depth + 1,
		pane_id = pane_id,
	}
	proposed.next_node_id += 1
	proposed.next_pane_id += 1
	proposed.nodes[source_index].parent = partition_index
	proposed.nodes[source_index].depth += 1
	if source_index == proposed.root {
		proposed.root = partition_index
	} else if !model_replace_child(&proposed, source.parent, source_index, partition_index) {
		return 0, false
	}
	proposed.mru[int(proposed.mru_count)] = pane_index
	proposed.mru_count += 1
	proposed.node_count += 2
	proposed.pane_count += 1
	proposed.partition_count += 1
	if !model_materialize(&proposed) || !model_validate(&proposed) {
		return 0, false
	}
	model^ = proposed
	return pane_id, true
}

model_focus :: proc(model: ^Model, pane_id: u64) -> bool {
	target, found := model_find_pane(model, pane_id)
	if !found {
		return false
	}
	model.active = target
	index := 0
	for candidate, candidate_index in model.mru[:model.mru_count] {
		if candidate == target {
			index = candidate_index
			break
		}
	}
	for index > 0 {
		model.mru[index] = model.mru[index - 1]
		index -= 1
	}
	model.mru[0] = target
	return model_validate(model)
}

model_resize_active :: proc(model: ^Model, arrangement: Arrangement, delta: i32) -> bool {
	if !model_validate(model) ||
	   (arrangement != .Above_Below && arrangement != .Left_Right) ||
	   (delta != -1 && delta != 1) {
		return false
	}
	proposed := model^
	if !model_materialize(&proposed) {
		return false
	}
	child := proposed.active
	target := proposed.nodes[child].parent
	for target >= 0 && proposed.nodes[target].arrangement != arrangement {
		child = target
		target = proposed.nodes[target].parent
	}
	if target < 0 {
		return false
	}
	partition := &proposed.nodes[target]
	first_span := proposed.nodes[partition.first].geometry.outer.height
	second_span := proposed.nodes[partition.second].geometry.outer.height
	if arrangement == .Left_Right {
		first_span = proposed.nodes[partition.first].geometry.outer.width
		second_span = proposed.nodes[partition.second].geometry.outer.width
	}
	first_delta := i64(delta)
	if child == partition.second {
		first_delta = -first_delta
	} else if child != partition.first {
		return false
	}
	new_first := i64(first_span) + first_delta
	new_second := i64(second_span) - first_delta
	minimums: [MAX_NODES]Minimum
	_, minimum_ok := model_minimum(&proposed, proposed.root, &minimums)
	if !minimum_ok {
		return false
	}
	first_floor := minimums[partition.first].rows
	second_floor := minimums[partition.second].rows
	if arrangement == .Left_Right {
		first_floor = minimums[partition.first].columns
		second_floor = minimums[partition.second].columns
	}
	if new_first < i64(first_floor) || new_second < i64(second_floor) {
		return false
	}
	partition.first_weight = u64(new_first)
	partition.second_weight = u64(new_second)
	if !model_materialize(&proposed) || !model_validate(&proposed) {
		return false
	}
	model^ = proposed
	return true
}

/* model_balance_dimensions independently derives one topology-preserving dimensional balance. */
model_balance_dimensions :: proc(model: ^Model) -> bool {
	if !model_validate(model) {
		return false
	}
	proposed := model^
	units: [MAX_NODES]Balance_Units
	_, measured := model_balance_measure(&proposed, proposed.root, &units)
	if !measured || !model_balance_set_weights(&proposed, proposed.root, &units) ||
	   !model_materialize(&proposed) || !model_balance_persist_spans(&proposed, proposed.root) ||
	   !model_validate(&proposed) {
		return false
	}
	model^ = proposed
	return true
}

/* model_balance_areas_exact exhaustively selects the exact area objective for bounded trees. */
model_balance_areas_exact :: proc(
	model: ^Model,
	work_limit := AREA_BALANCE_ORACLE_WORK_LIMIT,
) -> (score: Area_Balance_Score, work: u64, ok: bool) {
	if !model_validate(model) || work_limit == 0 {
		return {}, 0, false
	}
	proposed := model^
	search := Area_Balance_Search {
		candidate = &proposed,
		work_limit = work_limit,
	}
	model_area_collect_partitions(&proposed, proposed.root, &search)
	if search.partition_count != proposed.partition_count {
		return {}, 0, false
	}
	if search.partition_count == 0 {
		score, ok = model_area_score(&proposed)
		if ok {
			model^ = proposed
		}
		return score, 1, ok
	}
	model_area_search(&search, 0)
	if search.exhausted || !search.have_best {
		return {}, search.work, false
	}
	model^ = search.best
	return search.best_score, search.work, true
}

/* model_area_score computes the exact lexicographic leaf-area objective. */
model_area_score :: proc(model: ^Model) -> (score: Area_Balance_Score, ok: bool) {
	if !model_validate(model) || !model_materialize(model) {
		return {}, false
	}
	areas: [MAX_PANES]u64
	count: int
	if !model_area_collect(model, model.root, &areas, &count) || count != int(model.pane_count) {
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
	score.leaf_count = u16(count)
	model_area_collect_spans(model, model.root, &score)
	return score, score.partition_count == model.partition_count
}

model_close_active :: proc(model: ^Model) -> bool {
	if !model_validate(model) || model.pane_count == 1 {
		return false
	}
	proposed := model^
	target := proposed.active
	parent_index := proposed.nodes[target].parent
	if parent_index < 0 || proposed.nodes[parent_index].kind != .Partition {
		return false
	}
	parent := proposed.nodes[parent_index]
	sibling := parent.first
	if sibling == target {
		sibling = parent.second
	} else if parent.second != target {
		return false
	}
	if parent_index == proposed.root {
		proposed.root = sibling
	} else if !model_replace_child(&proposed, parent.parent, parent_index, sibling) {
		return false
	}
	proposed.nodes[sibling].parent = parent.parent
	if !model_decrement_depth(&proposed, sibling) {
		return false
	}
	proposed.nodes[target] = {}
	proposed.nodes[parent_index] = {}
	write: int
	for candidate in proposed.mru[:proposed.mru_count] {
		if candidate != target {
			proposed.mru[write] = candidate
			write += 1
		}
	}
	for index in write ..< int(proposed.mru_count) {
		proposed.mru[index] = 0
	}
	proposed.mru_count = u16(write)
	proposed.active = proposed.mru[0]
	proposed.node_count -= 2
	proposed.pane_count -= 1
	proposed.partition_count -= 1
	if !model_materialize(&proposed) || !model_validate(&proposed) {
		return false
	}
	model^ = proposed
	return true
}

model_keep_only :: proc(model: ^Model) -> bool {
	if !model_validate(model) {
		return false
	}
	if model.pane_count == 1 {
		return true
	}
	retained := model.nodes[model.active]
	active := model.active
	model.nodes = {}
	retained.parent = -1
	retained.depth = 0
	retained.geometry = {}
	model.nodes[active] = retained
	model.root = active
	model.mru = {}
	model.mru[0] = active
	model.mru_count = 1
	model.node_count = 1
	model.pane_count = 1
	model.partition_count = 0
	return model_materialize(model) && model_validate(model)
}

model_pane_ids :: proc(model: ^Model, output: ^[MAX_PANES]u64) -> int {
	count: int
	for &node in model.nodes {
		if node.live && node.kind == .Pane {
			output[count] = node.pane_id
			count += 1
		}
	}
	return count
}

@(private)
Area_Balance_Search :: struct {
	candidate:       ^Model,
	partitions:      [MAX_PANES - 1]int,
	partition_count: u16,
	work:            u64,
	work_limit:      u64,
	exhausted:       bool,
	have_best:       bool,
	best_score:      Area_Balance_Score,
	best:            Model,
}

@(private)
model_area_collect_partitions :: proc(model: ^Model, index: int, search: ^Area_Balance_Search) {
	node := &model.nodes[index]
	if node.kind != .Partition {
		return
	}
	search.partitions[int(search.partition_count)] = index
	search.partition_count += 1
	model_area_collect_partitions(model, node.first, search)
	model_area_collect_partitions(model, node.second, search)
}

@(private)
model_area_search :: proc(search: ^Area_Balance_Search, depth: int) {
	if search.exhausted {
		return
	}
	if depth == int(search.partition_count) {
		score, scored := model_area_score(search.candidate)
		if scored && (!search.have_best || model_area_score_better(score, search.best_score)) {
			search.best_score = score
			search.best = search.candidate^
			search.have_best = true
		}
		return
	}
	if !model_materialize(search.candidate) {
		return
	}
	minimums: [MAX_NODES]Minimum
	_, minimum_ok := model_minimum(search.candidate, search.candidate.root, &minimums)
	if !minimum_ok {
		return
	}
	partition_index := search.partitions[depth]
	partition := &search.candidate.nodes[partition_index]
	axis := partition.geometry.outer.height
	first_floor := minimums[partition.first].rows
	second_floor := minimums[partition.second].rows
	if partition.arrangement == .Left_Right {
		axis = partition.geometry.outer.width - 1
		first_floor = minimums[partition.first].columns
		second_floor = minimums[partition.second].columns
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
		model_area_search(search, depth + 1)
		if search.exhausted {
			return
		}
	}
}

@(private)
model_area_collect :: proc(
	model: ^Model,
	index: int,
	areas: ^[MAX_PANES]u64,
	count: ^int,
) -> bool {
	node := &model.nodes[index]
	if node.kind == .Pane {
		if node.geometry.outer.height <= 0 || node.geometry.outer.width <= 0 {
			return false
		}
		area := u128(node.geometry.outer.height) * u128(node.geometry.outer.width)
		if area > u128(max(u64)) {
			return false
		}
		areas[count^] = u64(area)
		count^ += 1
		return true
	}
	return node.kind == .Partition &&
	       model_area_collect(model, node.first, areas, count) &&
	       model_area_collect(model, node.second, areas, count)
}

@(private)
model_area_collect_spans :: proc(model: ^Model, index: int, score: ^Area_Balance_Score) {
	node := &model.nodes[index]
	if node.kind != .Partition {
		return
	}
	score.first_spans[int(score.partition_count)] = node.first_weight
	score.partition_count += 1
	model_area_collect_spans(model, node.first, score)
	model_area_collect_spans(model, node.second, score)
}

@(private)
model_area_score_better :: proc(candidate, current: Area_Balance_Score) -> bool {
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

@(private)
Balance_Units :: struct {
	rows:    u64,
	columns: u64,
}

@(private)
model_balance_measure :: proc(
	model: ^Model,
	index: int,
	units: ^[MAX_NODES]Balance_Units,
) -> (Balance_Units, bool) {
	if index < 0 || index >= MAX_NODES || !model.nodes[index].live {
		return {}, false
	}
	node := &model.nodes[index]
	if node.kind == .Pane {
		units[index] = Balance_Units{rows = 1, columns = 1}
		return units[index], true
	}
	if node.kind != .Partition {
		return {}, false
	}
	first, first_ok := model_balance_measure(model, node.first, units)
	second, second_ok := model_balance_measure(model, node.second, units)
	if !first_ok || !second_ok {
		return {}, false
	}
	result: Balance_Units
	if node.arrangement == .Above_Below {
		if first.rows > max(u64) - second.rows {
			return {}, false
		}
		result = Balance_Units {
			rows = first.rows + second.rows,
			columns = max(first.columns, second.columns),
		}
	} else if node.arrangement == .Left_Right {
		if first.columns > max(u64) - second.columns {
			return {}, false
		}
		result = Balance_Units {
			rows = max(first.rows, second.rows),
			columns = first.columns + second.columns,
		}
	} else {
		return {}, false
	}
	units[index] = result
	return result, true
}

@(private)
model_balance_set_weights :: proc(
	model: ^Model,
	index: int,
	units: ^[MAX_NODES]Balance_Units,
) -> bool {
	if index < 0 || index >= MAX_NODES || !model.nodes[index].live {
		return false
	}
	node := &model.nodes[index]
	if node.kind == .Pane {
		return true
	}
	if node.kind != .Partition {
		return false
	}
	first := units[node.first]
	second := units[node.second]
	if node.arrangement == .Above_Below {
		node.first_weight = first.rows
		node.second_weight = second.rows
	} else if node.arrangement == .Left_Right {
		node.first_weight = first.columns
		node.second_weight = second.columns
	} else {
		return false
	}
	return model_balance_set_weights(model, node.first, units) &&
	       model_balance_set_weights(model, node.second, units)
}

@(private)
model_balance_persist_spans :: proc(model: ^Model, index: int) -> bool {
	if index < 0 || index >= MAX_NODES || !model.nodes[index].live {
		return false
	}
	node := &model.nodes[index]
	if node.kind == .Pane {
		return true
	}
	if node.kind != .Partition {
		return false
	}
	first := &model.nodes[node.first]
	second := &model.nodes[node.second]
	first_span := first.geometry.outer.height
	second_span := second.geometry.outer.height
	if node.arrangement == .Left_Right {
		first_span = first.geometry.outer.width
		second_span = second.geometry.outer.width
	}
	if first_span <= 0 || second_span <= 0 {
		return false
	}
	node.first_weight = u64(first_span)
	node.second_weight = u64(second_span)
	return model_balance_persist_spans(model, node.first) &&
	       model_balance_persist_spans(model, node.second)
}

model_snapshot :: proc(model: ^Model) -> (snapshot: Snapshot, ok: bool) {
	if !model_validate(model) {
		return {}, false
	}
	snapshot.root_id = model.nodes[model.root].id
	snapshot.active_pane_id = model.nodes[model.active].pane_id
	snapshot.node_count = model.node_count
	snapshot.pane_count = model.pane_count
	snapshot.partition_count = model.partition_count
	index: int
	model_copy_node(model, model.root, &snapshot, &index)
	return snapshot, index == int(model.node_count)
}

model_validate :: proc(model: ^Model) -> bool {
	if model == nil || model.node_count == 0 || model.pane_count == 0 ||
	   model.node_count != model.pane_count + model.partition_count ||
	   model.mru_count != model.pane_count || model.root < 0 || model.root >= MAX_NODES {
		return false
	}
	seen: [MAX_NODES]bool
	nodes, panes, partitions: u16
	if !model_validate_node(model, model.root, -1, 0, &seen, &nodes, &panes, &partitions) ||
	   nodes != model.node_count || panes != model.pane_count || partitions != model.partition_count {
		return false
	}
	if model.active < 0 || model.active >= MAX_NODES || !seen[model.active] ||
	   model.nodes[model.active].kind != .Pane {
		return false
	}
	for candidate, index in model.mru[:model.mru_count] {
		if candidate < 0 || candidate >= MAX_NODES || !seen[candidate] ||
		   model.nodes[candidate].kind != .Pane {
			return false
		}
		for previous in model.mru[:index] {
			if previous == candidate {
				return false
			}
		}
	}
	return true
}

@(private)
Minimum :: struct {
	rows:    i32,
	columns: i32,
}

@(private)
model_materialize :: proc(model: ^Model) -> bool {
	minimums: [MAX_NODES]Minimum
	minimum, minimum_ok := model_minimum(model, model.root, &minimums)
	root := Rect{height = model.rows, width = model.columns}
	if !minimum_ok || root.height < minimum.rows || root.width < minimum.columns {
		return false
	}
	for &node in model.nodes {
		if node.live {
			node.geometry = {}
		}
	}
	return model_assign(model, model.root, root, &minimums)
}

@(private)
model_minimum :: proc(model: ^Model, index: int, minimums: ^[MAX_NODES]Minimum) -> (Minimum, bool) {
	if index < 0 || index >= MAX_NODES || !model.nodes[index].live {
		return {}, false
	}
	node := &model.nodes[index]
	if node.kind == .Pane {
		minimum := Minimum{rows = CONTENT_ROWS + STATUS_ROWS, columns = PANE_COLUMNS}
		minimums[index] = minimum
		return minimum, true
	}
	first, first_ok := model_minimum(model, node.first, minimums)
	second, second_ok := model_minimum(model, node.second, minimums)
	if !first_ok || !second_ok {
		return {}, false
	}
	minimum: Minimum
	if node.arrangement == .Above_Below {
		minimum = Minimum{rows = first.rows + second.rows, columns = max(first.columns, second.columns)}
	} else if node.arrangement == .Left_Right {
		minimum = Minimum{rows = max(first.rows, second.rows), columns = first.columns + 1 + second.columns}
	} else {
		return {}, false
	}
	minimums[index] = minimum
	return minimum, true
}

@(private)
model_assign :: proc(model: ^Model, index: int, rect: Rect, minimums: ^[MAX_NODES]Minimum) -> bool {
	node := &model.nodes[index]
	node.geometry.outer = rect
	if node.kind == .Pane {
		node.geometry.content = Rect {
			row = rect.row,
			column = rect.column,
			height = rect.height - STATUS_ROWS,
			width = rect.width,
		}
		node.geometry.status = Rect {
			row = rect.row + rect.height - STATUS_ROWS,
			column = rect.column,
			height = STATUS_ROWS,
			width = rect.width,
		}
		return true
	}
	axis := rect.height
	first_floor := minimums[node.first].rows
	second_floor := minimums[node.second].rows
	if node.arrangement == .Left_Right {
		axis = rect.width - 1
		first_floor = minimums[node.first].columns
		second_floor = minimums[node.second].columns
	}
	if axis < first_floor + second_floor {
		return false
	}
	total := u128(node.first_weight) + u128(node.second_weight)
	first_span := i32((u128(axis) * u128(node.first_weight)) / total)
	second_span := axis - first_span
	if first_span < first_floor {
		first_span = first_floor
		second_span = axis - first_span
	} else if second_span < second_floor {
		second_span = second_floor
		first_span = axis - second_span
	}
	first_rect, second_rect: Rect
	if node.arrangement == .Above_Below {
		first_rect = Rect{row = rect.row, column = rect.column, height = first_span, width = rect.width}
		second_rect = Rect {
			row = rect.row + first_span,
			column = rect.column,
			height = second_span,
			width = rect.width,
		}
	} else {
		first_rect = Rect{row = rect.row, column = rect.column, height = rect.height, width = first_span}
		node.geometry.separator = Rect {
			row = rect.row,
			column = rect.column + first_span,
			height = rect.height,
			width = 1,
		}
		second_rect = Rect {
			row = rect.row,
			column = rect.column + first_span + 1,
			height = rect.height,
			width = second_span,
		}
	}
	return model_assign(model, node.first, first_rect, minimums) &&
	       model_assign(model, node.second, second_rect, minimums)
}

@(private)
model_allocate :: proc(model: ^Model) -> (int, bool) {
	for &node, index in model.nodes {
		if !node.live {
			node.live = true
			return index, true
		}
	}
	return -1, false
}

@(private)
model_replace_child :: proc(model: ^Model, parent, old_child, new_child: int) -> bool {
	if parent < 0 || parent >= MAX_NODES || model.nodes[parent].kind != .Partition {
		return false
	}
	if model.nodes[parent].first == old_child {
		model.nodes[parent].first = new_child
		return true
	}
	if model.nodes[parent].second == old_child {
		model.nodes[parent].second = new_child
		return true
	}
	return false
}

@(private)
model_decrement_depth :: proc(model: ^Model, index: int) -> bool {
	if index < 0 || index >= MAX_NODES || !model.nodes[index].live || model.nodes[index].depth == 0 {
		return false
	}
	model.nodes[index].depth -= 1
	if model.nodes[index].kind == .Pane {
		return true
	}
	return model_decrement_depth(model, model.nodes[index].first) &&
	       model_decrement_depth(model, model.nodes[index].second)
}

@(private)
model_find_pane :: proc(model: ^Model, pane_id: u64) -> (int, bool) {
	for &node, index in model.nodes {
		if node.live && node.kind == .Pane && node.pane_id == pane_id {
			return index, true
		}
	}
	return -1, false
}

@(private)
model_validate_node :: proc(
	model: ^Model,
	index, parent: int,
	depth: u16,
	seen: ^[MAX_NODES]bool,
	nodes, panes, partitions: ^u16,
) -> bool {
	if index < 0 || index >= MAX_NODES || seen[index] || !model.nodes[index].live {
		return false
	}
	node := &model.nodes[index]
	if node.parent != parent || node.depth != depth || node.id == 0 || depth > MAX_DEPTH {
		return false
	}
	seen[index] = true
	nodes^ += 1
	if node.kind == .Pane {
		panes^ += 1
		return node.pane_id != 0
	}
	if node.kind != .Partition || node.first_weight == 0 || node.second_weight == 0 {
		return false
	}
	partitions^ += 1
	return model_validate_node(model, node.first, index, depth + 1, seen, nodes, panes, partitions) &&
	       model_validate_node(model, node.second, index, depth + 1, seen, nodes, panes, partitions)
}

@(private)
model_copy_node :: proc(model: ^Model, node_index: int, snapshot: ^Snapshot, index: ^int) {
	node := model.nodes[node_index]
	descriptor := &snapshot.nodes[index^]
	index^ += 1
	descriptor.kind = node.kind
	descriptor.id = node.id
	descriptor.depth = node.depth
	descriptor.arrangement = node.arrangement
	descriptor.first_weight = node.first_weight
	descriptor.second_weight = node.second_weight
	descriptor.pane_id = node.pane_id
	descriptor.geometry = node.geometry
	descriptor.active = node_index == model.active
	if node.parent >= 0 {
		descriptor.parent_id = model.nodes[node.parent].id
	}
	for candidate, rank in model.mru[:model.mru_count] {
		if candidate == node_index {
			descriptor.mru_rank = u16(rank)
			break
		}
	}
	if node.kind == .Partition {
		descriptor.first_id = model.nodes[node.first].id
		descriptor.second_id = model.nodes[node.second].id
		model_copy_node(model, node.first, snapshot, index)
		model_copy_node(model, node.second, snapshot, index)
	}
}
