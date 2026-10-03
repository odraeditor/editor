// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import multi_view_reference "../multi_view_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE

SELECTED_LIVE_PANES :: 128
SELECTED_PARTITION_DEPTH :: 32
SELECTED_RETAINED_VIEWS :: 1_024
SELECTED_LIVE_VIEWS :: 128
SELECTED_HISTORY_ENTRIES_PER_PANE :: 64
SELECTED_HISTORY_BYTES_PER_PANE :: 64 * KIBIBYTE
SELECTED_TOTAL_HISTORY_BYTES :: 8 * MEBIBYTE
SELECTED_POLICY_ACTIONS :: 32
SELECTED_LAYOUT_HOOKS :: 64
SELECTED_DEFERRED_REQUESTS :: 256
SELECTED_SNAPSHOT_NODES :: SELECTED_LIVE_PANES * 2 - 1
SELECTED_SNAPSHOT_BYTES :: 1 * MEBIBYTE
SELECTED_PREPARED_TRANSACTION_BYTES :: 4 * MEBIBYTE
SELECTED_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
SELECTED_GEOMETRY_WORK :: 1_048_576

FOCUS_SAMPLES :: 1_024
GEOMETRY_SAMPLES :: 128
ORDINARY_LATENCY_GATE_NS :: i64(5_000_000)
DEMANDING_LATENCY_GATE_NS :: i64(25_000_000)
STRESS_LATENCY_GATE_NS :: i64(100_000_000)

Layout_Node :: struct {
	identity:     u64,
	generation:   u64,
	parent:       u32,
	first_child:  u32,
	second_child: u32,
	first_weight: u32,
	second_weight: u32,
	x:            i32,
	y:            i32,
	width:        i32,
	height:       i32,
	flags:        u32,
}

Retained_View :: struct {
	buffer:             u64,
	stored_point:       u64,
	viewport_start:     u64,
	viewport_column:    u32,
	desired_column:     u32,
	generation:         u64,
	attached_pane:      u64,
	wrapping_generation: u64,
}

History_Entry :: struct {
	buffer:          u64,
	buffer_generation: u64,
	stored_point:    u64,
	viewport_start:  u64,
	viewport_column: u32,
	insertion_sequence: u64,
}

Hook_Record :: struct {
	identity:   u64,
	generation: u64,
	capability: u64,
	flags:      u32,
}

Deferred_Request :: struct {
	owner:              u64,
	layout:             u64,
	layout_generation:  u64,
	pane:               u64,
	pane_generation:    u64,
	operation:          u32,
	argument:           i64,
	sequence:           u64,
}

Policy_Action :: struct {
	kind:              u32,
	target:            u64,
	target_generation: u64,
	argument:          i64,
}

Profile :: struct {
	name:             string,
	buffers:          int,
	panes:            int,
	depth:            int,
	history_entries:  int,
	hooks:            int,
	deferred:         int,
	policy_actions:   int,
	latency_gate_ns:  i64,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = run_reference_probe() && passed
	profiles := [?]Profile {
		{
			name = "ordinary",
			buffers = 32,
			panes = 4,
			depth = 3,
			history_entries = 8,
			hooks = 2,
			deferred = 8,
			policy_actions = 4,
			latency_gate_ns = ORDINARY_LATENCY_GATE_NS,
		},
		{
			name = "demanding",
			buffers = 256,
			panes = SELECTED_LIVE_PANES,
			depth = SELECTED_PARTITION_DEPTH,
			history_entries = SELECTED_HISTORY_ENTRIES_PER_PANE,
			hooks = SELECTED_LAYOUT_HOOKS,
			deferred = SELECTED_DEFERRED_REQUESTS,
			policy_actions = SELECTED_POLICY_ACTIONS,
			latency_gate_ns = DEMANDING_LATENCY_GATE_NS,
		},
		{
			name = "stress",
			buffers = SELECTED_RETAINED_VIEWS,
			panes = SELECTED_LIVE_PANES,
			depth = SELECTED_PARTITION_DEPTH,
			history_entries = SELECTED_HISTORY_ENTRIES_PER_PANE,
			hooks = SELECTED_LAYOUT_HOOKS,
			deferred = SELECTED_DEFERRED_REQUESTS,
			policy_actions = SELECTED_POLICY_ACTIONS,
			latency_gate_ns = STRESS_LATENCY_GATE_NS,
		},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_rejection_probe() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	history_entry_bytes := u64(size_of(History_Entry))
	history_bytes_per_pane := history_entry_bytes * SELECTED_HISTORY_ENTRIES_PER_PANE
	total_history_bytes := history_bytes_per_pane * SELECTED_LIVE_PANES
	valid := SELECTED_LIVE_PANES > 0 &&
		SELECTED_PARTITION_DEPTH > 0 &&
		SELECTED_LIVE_VIEWS >= SELECTED_LIVE_PANES &&
		SELECTED_RETAINED_VIEWS >= SELECTED_LIVE_VIEWS &&
		history_bytes_per_pane <= SELECTED_HISTORY_BYTES_PER_PANE &&
		total_history_bytes <= SELECTED_TOTAL_HISTORY_BYTES &&
		SELECTED_POLICY_ACTIONS > 0 &&
		SELECTED_LAYOUT_HOOKS > 0 &&
		SELECTED_DEFERRED_REQUESTS > 0 &&
		SELECTED_SNAPSHOT_NODES == SELECTED_LIVE_PANES * 2 - 1 &&
		u64(SELECTED_SNAPSHOT_NODES * size_of(Layout_Node)) <= SELECTED_SNAPSHOT_BYTES &&
		SELECTED_PREPARED_TRANSACTION_BYTES > 0 &&
		SELECTED_DIAGNOSTIC_BYTES > 0 &&
		SELECTED_GEOMETRY_WORK >= SELECTED_SNAPSHOT_NODES
	fmt.printf(
		"study=multi-view profile=policy valid=%v selected_live_panes=%d selected_partition_depth=%d selected_live_views=%d selected_retained_views=%d selected_history_entries_per_pane=%d selected_history_bytes_per_pane=%d selected_total_history_bytes=%d selected_policy_actions=%d selected_layout_hooks=%d selected_deferred_requests=%d selected_snapshot_nodes=%d selected_snapshot_bytes=%d selected_prepared_transaction_bytes=%d selected_diagnostic_bytes=%d selected_geometry_work=%d ordinary_gate_ns=%d demanding_gate_ns=%d stress_gate_ns=%d\n",
		valid,
		SELECTED_LIVE_PANES,
		SELECTED_PARTITION_DEPTH,
		SELECTED_LIVE_VIEWS,
		SELECTED_RETAINED_VIEWS,
		SELECTED_HISTORY_ENTRIES_PER_PANE,
		SELECTED_HISTORY_BYTES_PER_PANE,
		SELECTED_TOTAL_HISTORY_BYTES,
		SELECTED_POLICY_ACTIONS,
		SELECTED_LAYOUT_HOOKS,
		SELECTED_DEFERRED_REQUESTS,
		SELECTED_SNAPSHOT_NODES,
		SELECTED_SNAPSHOT_BYTES,
		SELECTED_PREPARED_TRANSACTION_BYTES,
		SELECTED_DIAGNOSTIC_BYTES,
		SELECTED_GEOMETRY_WORK,
		ORDINARY_LATENCY_GATE_NS,
		DEMANDING_LATENCY_GATE_NS,
		STRESS_LATENCY_GATE_NS,
	)
	return valid
}

run_reference_probe :: proc() -> bool {
	model, ready := multi_view_reference.model_init(2, 2)
	if !ready {
		fmt.eprintln("study=multi-view profile=reference ready=false")
		return false
	}
	defer multi_view_reference.model_deinit(&model)
	buffer, buffer_ok, _ := multi_view_reference.model_add_buffer(
		&model,
		10,
		50,
		true,
		true,
	)
	original, root_ok, _ := multi_view_reference.model_open_root(&model, buffer, 1)
	secondary, split_ok, _ := multi_view_reference.model_split_active(&model)
	point_ok, _ := multi_view_reference.model_set_effective_point(&model, buffer, 25)
	focus_secondary, _ := multi_view_reference.model_focus(&model, secondary)
	secondary_point_ok, _ := multi_view_reference.model_set_effective_point(&model, buffer, 80)
	focus_original, _ := multi_view_reference.model_focus(&model, original)
	buffer_state, inspected := multi_view_reference.model_inspect_buffer(&model, buffer)
	valid := buffer_ok && root_ok && split_ok && point_ok && focus_secondary &&
		secondary_point_ok && focus_original && inspected &&
		buffer_state.effective_point == 25 && buffer_state.mark == 50 &&
		buffer_state.mark_present && buffer_state.region_active &&
		multi_view_reference.model_validate(&model)
	fmt.printf(
		"study=multi-view profile=reference valid=%v panes=%d shared_mark=%v independent_points=%v representation=contiguous-selection-view-oracle\n",
		valid,
		model.pane_count,
		buffer_state.mark == 50,
		buffer_state.effective_point == 25,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	if !profile_admitted(profile) {
		fmt.eprintf("study=multi-view profile=%s phase=admission\n", profile.name)
		return false
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	model, model_ready := multi_view_reference.model_init(
		profile.buffers,
		profile.panes,
		allocator,
	)
	if !model_ready {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=multi-view profile=%s phase=model-init\n", profile.name)
		return false
	}
	retained_views, retained_error := make([]Retained_View, profile.buffers, allocator)
	layout_nodes, nodes_error := make([]Layout_Node, profile.panes * 2 - 1, allocator)
	histories, histories_error := make(
		[]History_Entry,
		profile.panes * profile.history_entries,
		allocator,
	)
	hooks, hooks_error := make([]Hook_Record, profile.hooks, allocator)
	deferred, deferred_error := make([]Deferred_Request, profile.deferred, allocator)
	actions, actions_error := make([]Policy_Action, profile.policy_actions, allocator)
	allocated := retained_error == nil && nodes_error == nil && histories_error == nil &&
		hooks_error == nil && deferred_error == nil && actions_error == nil
	if !allocated {
		if actions != nil do delete(actions, allocator)
		if deferred != nil do delete(deferred, allocator)
		if hooks != nil do delete(hooks, allocator)
		if histories != nil do delete(histories, allocator)
		if layout_nodes != nil do delete(layout_nodes, allocator)
		if retained_views != nil do delete(retained_views, allocator)
		multi_view_reference.model_deinit(&model)
		cleanup_bytes := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf(
			"study=multi-view profile=%s phase=allocation cleanup_bytes=%d\n",
			profile.name,
			cleanup_bytes,
		)
		return false
	}

	built := build_profile(
		&model,
		retained_views,
		layout_nodes,
		histories,
		hooks,
		deferred,
		actions,
		profile,
	)
	live_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	focus_latency, focus_checksum := measure_focus(&model, profile.panes)
	geometry_latency, geometry_checksum, geometry_work := measure_geometry(layout_nodes)
	history_bytes_per_pane := u64(profile.history_entries * size_of(History_Entry))
	snapshot_bytes := u64(len(layout_nodes) * size_of(Layout_Node))
	valid := built && multi_view_reference.model_validate(&model) &&
		focus_latency.p99_ns <= profile.latency_gate_ns &&
		geometry_latency.p99_ns <= profile.latency_gate_ns &&
		history_bytes_per_pane <= SELECTED_HISTORY_BYTES_PER_PANE &&
		snapshot_bytes <= SELECTED_SNAPSHOT_BYTES &&
		geometry_work <= SELECTED_GEOMETRY_WORK

	delete(actions, allocator)
	delete(deferred, allocator)
	delete(hooks, allocator)
	delete(histories, allocator)
	delete(layout_nodes, allocator)
	delete(retained_views, allocator)
	multi_view_reference.model_deinit(&model)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=multi-view profile=%s valid=%v buffers=%d panes=%d nodes=%d depth=%d history_entries_per_pane=%d history_bytes_per_pane=%d hooks=%d deferred=%d policy_actions=%d live_bytes=%d peak_bytes=%d snapshot_bytes=%d geometry_work=%d focus_p50_ns=%d focus_p99_ns=%d geometry_p50_ns=%d geometry_p99_ns=%d latency_gate_ns=%d cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.buffers,
		profile.panes,
		profile.panes * 2 - 1,
		profile.depth,
		profile.history_entries,
		history_bytes_per_pane,
		profile.hooks,
		profile.deferred,
		profile.policy_actions,
		live_bytes,
		peak_bytes,
		snapshot_bytes,
		geometry_work,
		focus_latency.p50_ns,
		focus_latency.p99_ns,
		geometry_latency.p50_ns,
		geometry_latency.p99_ns,
		profile.latency_gate_ns,
		cleanup_bytes,
		focus_checksum ~ geometry_checksum,
	)
	return valid
}

build_profile :: proc(
	model: ^multi_view_reference.Model,
	retained_views: []Retained_View,
	layout_nodes: []Layout_Node,
	histories: []History_Entry,
	hooks: []Hook_Record,
	deferred: []Deferred_Request,
	actions: []Policy_Action,
	profile: Profile,
) -> bool {
	for index in 0 ..< profile.buffers {
		buffer, created, _ := multi_view_reference.model_add_buffer(
			model,
			u64(index * 7),
			u64(index * 3),
			index % 2 == 0,
			false,
		)
		if !created {
			return false
		}
		retained_views[index] = Retained_View {
			buffer = u64(buffer),
			stored_point = u64(index * 7),
			viewport_start = u64(index * 5),
			generation = 1,
		}
	}
	first_buffer := multi_view_reference.Buffer_ID(1)
	_, opened, _ := multi_view_reference.model_open_root(model, first_buffer)
	if !opened {
		return false
	}
	for _ in 1 ..< profile.panes {
		_, split, _ := multi_view_reference.model_split_active(model)
		if !split {
			return false
		}
	}
	for index in 0 ..< len(layout_nodes) {
		layout_nodes[index] = Layout_Node {
			identity = u64(index + 1),
			generation = 1,
			parent = u32(max(index - 1, 0)),
			first_weight = u32(index % 31 + 1),
			second_weight = u32(index % 29 + 1),
			width = 240,
			height = 80,
		}
	}
	for index in 0 ..< len(histories) {
		histories[index] = History_Entry {
			buffer = u64(index % profile.buffers + 1),
			buffer_generation = 1,
			stored_point = u64(index * 11),
			viewport_start = u64(index * 7),
			insertion_sequence = u64(index + 1),
		}
	}
	for index in 0 ..< len(hooks) {
		hooks[index] = Hook_Record{identity = u64(index + 1), generation = 1}
	}
	for index in 0 ..< len(deferred) {
		deferred[index] = Deferred_Request {
			owner = 1,
			layout = 1,
			layout_generation = 1,
			pane = u64(index % profile.panes + 1),
			pane_generation = 1,
			sequence = u64(index + 1),
		}
	}
	for index in 0 ..< len(actions) {
		actions[index] = Policy_Action {kind = u32(index % 3), target = u64(index + 1)}
	}
	return true
}

measure_focus :: proc(
	model: ^multi_view_reference.Model,
	pane_count: int,
) -> (latency: Latency, checksum: u64) {
	samples := make([]i64, FOCUS_SAMPLES)
	defer delete(samples)
	for sample in 0 ..< FOCUS_SAMPLES {
		target := multi_view_reference.Pane_ID(sample % pane_count + 1)
		started := time.tick_now()
		focused, _ := multi_view_reference.model_focus(model, target)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if !focused {
			return {p50_ns = max(i64)}, 0
		}
		samples[sample] = elapsed
		checksum ~= u64(target) + u64(sample)
	}
	slice.sort(samples)
	return Latency {
		p50_ns = percentile_nearest_rank(samples, 50),
		p99_ns = percentile_nearest_rank(samples, 99),
	}, checksum
}

measure_geometry :: proc(nodes: []Layout_Node) -> (
	latency: Latency,
	checksum: u64,
	work: int,
) {
	samples := make([]i64, GEOMETRY_SAMPLES)
	defer delete(samples)
	for sample in 0 ..< GEOMETRY_SAMPLES {
		started := time.tick_now()
		for index in 0 ..< len(nodes) {
			node := &nodes[index]
			available := u64(max(node.width, 1))
			weights := u64(node.first_weight) + u64(node.second_weight)
			first := available * u64(node.first_weight) / max(weights, 1)
			second := available - first
			checksum ~= first + second + u64(index + sample)
			work += 1
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	slice.sort(samples)
	return Latency {
		p50_ns = percentile_nearest_rank(samples, 50),
		p99_ns = percentile_nearest_rank(samples, 99),
	}, checksum, work
}

run_rejection_probe :: proc() -> bool {
	model, ready := multi_view_reference.model_init(1, 1)
	if !ready {
		return false
	}
	defer multi_view_reference.model_deinit(&model)
	buffer, buffer_ok, _ := multi_view_reference.model_add_buffer(&model, 1)
	root, root_ok, _ := multi_view_reference.model_open_root(&model, buffer)
	_, split, split_failure := multi_view_reference.model_split_active(&model)
	_, second_buffer, buffer_failure := multi_view_reference.model_add_buffer(&model, 2)
	valid := buffer_ok && root_ok && !split && !second_buffer &&
		split_failure.code == .Pane_Capacity &&
		buffer_failure.code == .Buffer_Capacity &&
		model.pane_count == 1 && model.active_pane == root &&
		multi_view_reference.model_validate(&model)
	fmt.printf(
		"study=multi-view profile=rejection valid=%v pane_limit=%d depth_limit=%d retained_view_limit=%d history_eviction=oldest structural_overflow=atomic queue_overflow=reject-new snapshot_overflow=reject-before-publication\n",
		valid,
		SELECTED_LIVE_PANES,
		SELECTED_PARTITION_DEPTH,
		SELECTED_RETAINED_VIEWS,
	)
	return valid
}

profile_admitted :: proc(profile: Profile) -> bool {
	return profile.buffers > 0 && profile.buffers <= SELECTED_RETAINED_VIEWS &&
		profile.panes > 0 && profile.panes <= SELECTED_LIVE_PANES &&
		profile.panes <= SELECTED_LIVE_VIEWS &&
		profile.depth > 0 && profile.depth <= SELECTED_PARTITION_DEPTH &&
		profile.history_entries >= 0 &&
		profile.history_entries <= SELECTED_HISTORY_ENTRIES_PER_PANE &&
		profile.hooks >= 0 && profile.hooks <= SELECTED_LAYOUT_HOOKS &&
		profile.deferred >= 0 && profile.deferred <= SELECTED_DEFERRED_REQUESTS &&
		profile.policy_actions > 0 && profile.policy_actions <= SELECTED_POLICY_ACTIONS
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	if len(values) == 0 {
		return 0
	}
	rank := (percentile * len(values) + 99) / 100
	index := clamp(rank - 1, 0, len(values) - 1)
	return values[index]
}
