// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/history"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

KIBIBYTE :: u64(1024)
MEBIBYTE :: u64(1024) * KIBIBYTE
GIBIBYTE :: u64(1024) * MEBIBYTE

CANDIDATE_GLOBAL_BYTES :: 512 * MEBIBYTE
CANDIDATE_GLOBAL_NODES :: u64(250_000)
CANDIDATE_INSPECTION_NODES :: 256
CANDIDATE_PRUNING_OPERATIONS :: 4_096
NAVIGATION_SAMPLES :: 1_024
ORDINARY_NAVIGATION_GATE_NS :: i64(2_000_000)
DEMANDING_NAVIGATION_GATE_NS :: i64(8_000_000)

Candidate_Node :: struct {
	id:                  u64,
	parent:              u64,
	first_child:         u64,
	next_sibling:        u64,
	preferred_child:     u64,
	transaction_id:      u64,
	undo_unit_id:        u64,
	buffer_id:           u64,
	base_revision:       u64,
	result_revision:     u64,
	first_record:        u64,
	record_count:        u32,
	flags:               u32,
	retained_bytes:      u64,
	initiating_view_id:  u64,
	initiating_cursor:   u64,
}

Candidate_Record :: struct {
	buffer_id:           u64,
	base_revision:       u64,
	result_revision:     u64,
	start:               u64,
	removed_offset:      u64,
	removed_bytes:       u64,
	inserted_offset:     u64,
	inserted_bytes:      u64,
	start_anchor:        u64,
	end_anchor:          u64,
}

Study_Profile :: struct {
	name:                string,
	nodes:               int,
	records:             int,
	payload_bytes:       u64,
	depth:               int,
	branches:            int,
	navigation_gate_ns:  i64,
	policy_gate_ns:      i64,
	expect_admission:    bool,
	policy_nodes:        int,
	policy_operations:   u64,
	expect_policy_apply: bool,
	store_id:            history.Store_ID,
}

main :: proc() {
	profiles := [?]Study_Profile {
		{
			name = "ordinary",
			nodes = 10_000,
			records = 10_031,
			payload_bytes = 16 * MEBIBYTE,
			depth = 4_096,
			branches = 8,
			navigation_gate_ns = ORDINARY_NAVIGATION_GATE_NS,
			policy_gate_ns = ORDINARY_NAVIGATION_GATE_NS,
			expect_admission = true,
			policy_nodes = 300,
			policy_operations = 300,
			expect_policy_apply = true,
			store_id = 1,
		},
		{
			name = "demanding",
			nodes = 100_000,
			records = 109_999,
			payload_bytes = 256 * MEBIBYTE,
			depth = 65_536,
			branches = 1_024,
			navigation_gate_ns = DEMANDING_NAVIGATION_GATE_NS,
			policy_gate_ns = DEMANDING_NAVIGATION_GATE_NS,
			expect_admission = true,
			policy_nodes = 1_024,
			policy_operations = 4_096,
			expect_policy_apply = true,
			store_id = 2,
		},
		{
			name = "stress",
			nodes = 1_000_000,
			records = 1_099_999,
			payload_bytes = 1 * GIBIBYTE,
			depth = 250_000,
			branches = 65_536,
			navigation_gate_ns = 0,
			policy_gate_ns = DEMANDING_NAVIGATION_GATE_NS,
			expect_admission = false,
			policy_nodes = 65_536,
			policy_operations = 64,
			expect_policy_apply = false,
			store_id = 3,
		},
	}

	passed := true
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	if !passed {
		os.exit(1)
	}
}

run_profile :: proc(profile: Study_Profile) -> bool {
	node_bytes := u64(profile.nodes) * u64(size_of(Candidate_Node))
	record_bytes := u64(profile.records) * u64(size_of(Candidate_Record))
	required_bytes := node_bytes + record_bytes + profile.payload_bytes
	admitted := required_bytes <= CANDIDATE_GLOBAL_BYTES &&
	            u64(profile.nodes) <= CANDIDATE_GLOBAL_NODES
	if admitted != profile.expect_admission {
		fmt.eprintf(
			"study=history profile=%s phase=admission expected=%v actual=%v required_bytes=%d byte_limit=%d nodes=%d node_limit=%d\n",
			profile.name,
			profile.expect_admission,
			admitted,
			required_bytes,
			CANDIDATE_GLOBAL_BYTES,
			profile.nodes,
			CANDIDATE_GLOBAL_NODES,
		)
		return false
	}
	if !admitted {
		fmt.printf(
			"study=history profile=%s admitted=false required_bytes=%d byte_limit=%d nodes=%d node_limit=%d reason=bounded-policy-rejection\n",
			profile.name,
			required_bytes,
			CANDIDATE_GLOBAL_BYTES,
			profile.nodes,
			CANDIDATE_GLOBAL_NODES,
		)
		return run_live_policy_profile(profile)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	nodes, node_error := make([]Candidate_Node, profile.nodes, allocator)
	if node_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=history profile=%s phase=node-allocation\n", profile.name)
		return false
	}
	records, record_error := make([]Candidate_Record, profile.records, allocator)
	if record_error != nil {
		delete(nodes, allocator)
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=history profile=%s phase=record-allocation\n", profile.name)
		return false
	}
	payload, payload_error := make([]byte, int(profile.payload_bytes), allocator)
	if payload_error != nil {
		delete(records, allocator)
		delete(nodes, allocator)
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=history profile=%s phase=payload-allocation\n", profile.name)
		return false
	}

	initialize_nodes(nodes, profile.depth, profile.branches)
	initialize_records(records, profile.nodes, profile.payload_bytes)
	touch_payload(payload)
	accounting_exact := tracking.current_memory_allocated == i64(required_bytes)
	navigation_p99_ns, inspection_ns, checksum := measure_navigation(nodes)
	pruning_started := time.tick_now()
	pruned, prune_checksum := prune_candidate(nodes, CANDIDATE_PRUNING_OPERATIONS, 32)
	pruning_ns := time.duration_nanoseconds(time.tick_since(pruning_started))
	checksum ~= prune_checksum
	within_gate := navigation_p99_ns <= profile.navigation_gate_ns

	peak_bytes := tracking.peak_memory_allocated
	delete(payload, allocator)
	delete(records, allocator)
	delete(nodes, allocator)
	cleanup_exact := tracking.current_memory_allocated == 0
	mem.tracking_allocator_destroy(&tracking)

	fmt.printf(
		"study=history profile=%s admitted=true nodes=%d records=%d depth=%d branches=%d node_size=%d record_size=%d required_bytes=%d peak_bytes=%d accounting_exact=%v navigation_p99_ns=%d navigation_gate_ns=%d inspection_nodes=%d inspection_ns=%d pruned=%d pruning_ns=%d cleanup_exact=%v checksum=%d\n",
		profile.name,
		profile.nodes,
		profile.records,
		profile.depth,
		profile.branches,
		size_of(Candidate_Node),
		size_of(Candidate_Record),
		required_bytes,
		peak_bytes,
		accounting_exact,
		navigation_p99_ns,
		profile.navigation_gate_ns,
		min(CANDIDATE_INSPECTION_NODES, profile.nodes),
		inspection_ns,
		pruned,
		pruning_ns,
		cleanup_exact,
		checksum,
	)
	return accounting_exact && cleanup_exact && within_gate &&
	       run_live_policy_profile(profile)
}

run_live_policy_profile :: proc(profile: Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	policy := history.DEFAULT_POLICY
	policy.sibling_branches = u64(profile.policy_nodes)
	policy.guaranteed_recent_units = history.MIN_RECENT_UNITS
	store: history.Store
	initialized, init_failure := history.store_init(
		&store,
		profile.store_id,
		editor.Buffer_ID(u64(profile.store_id)),
		editor.Revision(0),
		history.Allocator_Set{
			persistent = allocator,
			temporary = context.temp_allocator,
		},
		policy,
	)
	if !initialized {
		fmt.eprintf(
			"study=history-policy profile=%s phase=init failure=%v\n",
			profile.name,
			init_failure.code,
		)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	revision := editor.Revision(0)
	buffer_id := editor.Buffer_ID(u64(profile.store_id))
	built := true
	for identity in 1 ..= profile.policy_nodes {
		if !append_policy_branch(&store, buffer_id, u64(identity), &revision) {
			built = false
			break
		}
	}
	if !built {
		history.store_close(&store)
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf(
			"study=history-policy profile=%s phase=build nodes=%d\n",
			profile.name,
			profile.policy_nodes,
		)
		return false
	}

	before, before_ok, _ := history.store_policy_inspect(&store)
	before_stats, before_stats_ok, _ := history.store_stats(&store)
	inspection_started := time.tick_now()
	inspection, inspection_ok, inspection_failure := history.store_inspect(
		&store,
		history.Inspection_Request {
			buffer_id = before_stats.buffer_id,
			current_revision = before_stats.current_revision,
			active_node = before_stats.active_node,
			policy_generation = before_stats.policy_generation,
			result_limit = min(history.DEFAULT_INSPECTION_NODES, before_stats.active_child_count),
			traversal_limit = min(history.DEFAULT_INSPECTION_NODES, before_stats.active_child_count),
		},
		allocator,
	)
	inspection_live_ns := time.duration_nanoseconds(time.tick_since(inspection_started))
	branch_ns := i64(0)
	selective_ns := i64(0)
	branch_selective_ok := inspection_ok && inspection_failure.code == .None &&
		len(inspection.children) > 0
	if branch_selective_ok {
		target := inspection.children[0]
		branch_started := time.tick_now()
		branch_plan, branch_result, branch_ok, branch_failure := history.navigation_prepare(
			&store,
			history.Navigation_Request {
				kind = .Select_Branch,
				buffer_id = before_stats.buffer_id,
				current_revision = before_stats.current_revision,
				active_node = before_stats.active_node,
				target_node = target.id,
				policy_generation = before_stats.policy_generation,
				analysis_operations = history.DEFAULT_INSPECTION_NODES,
			},
		)
		branch_ns = time.duration_nanoseconds(time.tick_since(branch_started))
		branch_selective_ok = branch_ok && branch_failure.code == .None &&
			branch_result.outcome == .Applied
		if branch_selective_ok {
			revision = editor.Revision(u64(revision) + 1)
			history.navigation_commit_reserved(&branch_plan, revision)
			active, _, _ := history.store_stats(&store)
			selective_started := time.tick_now()
			selective, selective_ok, selective_failure := history.selective_prepare(
				&store,
				history.Selective_Request {
					buffer_id = active.buffer_id,
					current_revision = active.current_revision,
					active_node = active.active_node,
					target_unit = target.unit_id,
					policy_generation = active.policy_generation,
					analysis_operations = history.MIN_SELECTIVE_OPERATIONS,
				},
			)
			selective_ns = time.duration_nanoseconds(time.tick_since(selective_started))
			branch_selective_ok = selective_ok && selective_failure.code == .None
			if selective_ok {
				history.selective_plan_release(&selective)
			}
			undo, preliminary, undo_ok, _ := history.navigation_prepare(
				&store,
				history.Navigation_Request {
					kind = .Undo,
					buffer_id = active.buffer_id,
					current_revision = active.current_revision,
				},
			)
			if undo_ok && preliminary.outcome == .Applied {
				revision = editor.Revision(u64(revision) + 1)
				history.navigation_commit_reserved(&undo, revision)
			} else {
				branch_selective_ok = false
			}
		}
	}
	history.inspection_release(&inspection, allocator)
	cancelled_policy := before.policy
	cancelled_policy.inspection_nodes = min(
		history.MAX_INSPECTION_NODES,
		cancelled_policy.inspection_nodes + 1,
	)
	cancellation_started := time.tick_now()
	_, cancelled_ok, cancellation_failure := history.store_policy_replace(
		&store,
		history.Policy_Replacement_Request{
			expected_generation = before.policy_generation,
			policy = cancelled_policy,
			operation_limit = profile.policy_operations,
			cancelled = true,
		},
	)
	cancellation_ns := time.duration_nanoseconds(time.tick_since(cancellation_started))
	after_cancellation, cancellation_inspected, _ := history.store_policy_inspect(&store)
	cancellation_preserved := before_ok && cancellation_inspected && !cancelled_ok &&
		cancellation_failure.code == .Cancelled && after_cancellation == before

	lowered_policy := before.policy
	lowered_policy.buffer_nodes = history.MIN_BUFFER_NODES
	lowered_policy.guaranteed_recent_units = history.MIN_RECENT_UNITS
	lowered_policy.retained_depth = history.MIN_RETAINED_DEPTH
	lowered_policy.pruning_operations = max(
		history.MIN_PRUNING_OPERATIONS,
		profile.policy_operations,
	)
	replacement_started := time.tick_now()
	replaced, replacement_ok, replacement_failure := history.store_policy_replace(
		&store,
		history.Policy_Replacement_Request{
			expected_generation = before.policy_generation,
			policy = lowered_policy,
			operation_limit = profile.policy_operations,
		},
	)
	replacement_ns := time.duration_nanoseconds(time.tick_since(replacement_started))
	replacement_within_gate := replacement_ns <= profile.policy_gate_ns
	after, after_ok, _ := history.store_policy_inspect(&store)
	after_stats, after_stats_ok, _ := history.store_stats(&store)
	active_preserved := before_stats_ok && after_stats_ok &&
		after_stats.active_node == before_stats.active_node
	protected_window_ok := after.usage.retained_nodes >=
		history.MIN_RECENT_UNITS + 1
	expected_pruned := u64(profile.policy_nodes + 1) - history.MIN_BUFFER_NODES
	policy_result_ok := false
	if profile.expect_policy_apply {
		policy_result_ok = replacement_ok && replacement_failure.code == .None &&
			replaced.pruned_nodes == expected_pruned &&
			after.policy_generation == history.Policy_Generation(2) &&
			after.usage.retained_nodes == history.MIN_BUFFER_NODES &&
			active_preserved && protected_window_ok
	} else {
		policy_result_ok = !replacement_ok &&
			replacement_failure.code == .Policy_Retention_Blocked &&
			after == before && active_preserved && protected_window_ok
	}

	peak_bytes := tracking.peak_memory_allocated
	closed, close_failure := history.store_close(&store)
	cleanup_bytes := tracking.current_memory_allocated
	cleanup_ok := closed && close_failure.code == .None && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=history-policy profile=%s nodes=%d operations=%d inspection_ns=%d branch_ns=%d selective_ns=%d branch_selective_ok=%v applied=%v failure=%v generation=%d retained_nodes=%d pruned=%d cancellation_ns=%d cancellation_preserved=%v replacement_ns=%d replacement_gate_ns=%d replacement_within_gate=%v active_preserved=%v protected_recent=%d protected_window_ok=%v peak_bytes=%d cleanup_bytes=%d\n",
		profile.name,
		profile.policy_nodes + 1,
		profile.policy_operations,
		inspection_live_ns,
		branch_ns,
		selective_ns,
		branch_selective_ok,
		replacement_ok,
		replacement_failure.code,
		u64(after.policy_generation),
		after.usage.retained_nodes,
		replaced.pruned_nodes,
		cancellation_ns,
		cancellation_preserved,
		replacement_ns,
		profile.policy_gate_ns,
		replacement_within_gate,
		active_preserved,
		history.MIN_RECENT_UNITS,
		protected_window_ok,
		peak_bytes,
		cleanup_bytes,
	)
	return after_ok && branch_selective_ok &&
	       inspection_live_ns <= profile.policy_gate_ns &&
	       branch_ns <= profile.policy_gate_ns && selective_ns <= profile.policy_gate_ns &&
	       cancellation_preserved && policy_result_ok &&
	       replacement_within_gate && cleanup_ok
}

append_policy_branch :: proc(
	store: ^history.Store,
	buffer_id: editor.Buffer_ID,
	identity: u64,
	revision: ^editor.Revision,
) -> bool {
	result_revision := editor.Revision(u64(revision^) + 1)
	edits := [1]history.Edit_Payload{{
		start = 0,
		end = 0,
		replacement_text = "x",
	}}
	reservation: history.Reservation
	reserved, _ := history.record_reserve(
		store,
		&reservation,
		history.Record_Input{
			source_transaction_id = history.Source_Transaction_ID(identity),
			source_undo_unit_id = history.Source_Undo_Unit_ID(identity),
			buffer_id = buffer_id,
			base_revision = revision^,
			result_revision = result_revision,
			edits = edits[:],
			origin = .Built_In,
			origin_descriptor = "history-resource-study",
			command = "policy-branch",
		},
	)
	if !reserved {
		return false
	}
	history.reservation_commit_reserved(&reservation, result_revision)
	undo, preliminary, prepared, _ := history.navigation_prepare(
		store,
		history.Navigation_Request{
			kind = .Undo,
			buffer_id = buffer_id,
			current_revision = result_revision,
		},
	)
	if !prepared || preliminary.outcome != .Applied {
		return false
	}
	revision^ = editor.Revision(u64(result_revision) + 1)
	history.navigation_commit_reserved(&undo, revision^)
	return true
}

initialize_nodes :: proc(nodes: []Candidate_Node, depth, branches: int) {
	for index in 0 ..< len(nodes) {
		parent := max(0, index - 1)
		preferred_child := min(len(nodes) - 1, index + 1)
		nodes[index] = Candidate_Node {
			id = u64(index + 1),
			parent = u64(parent),
			preferred_child = u64(preferred_child),
			transaction_id = u64(index + 1),
			undo_unit_id = u64(index + 1),
			buffer_id = 1,
			base_revision = u64(index),
			result_revision = u64(index + 1),
			first_record = u64(index),
			record_count = 1,
			retained_bytes = u64(size_of(Candidate_Node)),
			initiating_view_id = 1,
			initiating_cursor = u64(index),
		}
	}
	for branch in 1 ..< min(branches, len(nodes)) {
		index := branch * max(1, len(nodes) / max(1, branches))
		if index >= len(nodes) {
			break
		}
		nodes[index].parent = u64(max(0, index - min(depth, index)))
		nodes[index].next_sibling = u64(max(0, index - 1))
	}
}

initialize_records :: proc(records: []Candidate_Record, node_count: int, payload_bytes: u64) {
	for index in 0 ..< len(records) {
		payload_offset := u64(index) % max(u64(1), payload_bytes)
		records[index] = Candidate_Record {
			buffer_id = 1,
			base_revision = u64(index % node_count),
			result_revision = u64(index % node_count + 1),
			start = u64(index),
			removed_offset = payload_offset,
			removed_bytes = 1,
			inserted_offset = payload_offset,
			inserted_bytes = 1,
			start_anchor = u64(index * 2 + 1),
			end_anchor = u64(index * 2 + 2),
		}
	}
}

touch_payload :: proc(payload: []byte) {
	for index := 0; index < len(payload); index += 4_096 {
		payload[index] = byte(index % 251)
	}
	if len(payload) > 0 {
		payload[len(payload) - 1] = 1
	}
}

measure_navigation :: proc(nodes: []Candidate_Node) -> (navigation_p99_ns, inspection_ns: i64, checksum: u64) {
	latencies := make([]i64, NAVIGATION_SAMPLES)
	defer delete(latencies)
	active := len(nodes) - 1
	for sample in 0 ..< NAVIGATION_SAMPLES {
		started := time.tick_now()
		parent := int(nodes[active].parent)
		child := int(nodes[parent].preferred_child)
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum ~= (nodes[parent].id ~ nodes[child].id)
		active = max(1, parent)
	}
	slice.sort(latencies)
	p99_index := (NAVIGATION_SAMPLES * 99 + 99) / 100 - 1

	inspection_started := time.tick_now()
	inspection_count := min(CANDIDATE_INSPECTION_NODES, len(nodes))
	inspection_index := len(nodes) - 1
	for _ in 0 ..< inspection_count {
		checksum ~= nodes[inspection_index].id
		inspection_index = int(nodes[inspection_index].parent)
	}
	inspection_ns = time.duration_nanoseconds(time.tick_since(inspection_started))
	return latencies[p99_index], inspection_ns, checksum
}

prune_candidate :: proc(nodes: []Candidate_Node, operation_limit, protected_recent: int) -> (pruned: int, checksum: u64) {
	prunable := max(0, len(nodes) - protected_recent)
	pruned = min(operation_limit, prunable)
	for index in 0 ..< pruned {
		nodes[index].flags |= 1
		checksum ~= nodes[index].id
	}
	return
}
