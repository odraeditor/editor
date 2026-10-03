// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/editor"
import "../../src/history"
import "../../src/transaction"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"

RANDOM_SEED :: u64(0x6f64726168697374)
GENERATED_OPERATIONS :: 384
PRUNING_BRANCHES :: 40
MAX_MODEL_NODES :: 1_024
MAX_MODEL_TEXT_BYTES :: 256

Model_Node :: struct {
	text:      [MAX_MODEL_TEXT_BYTES]byte,
	length:    int,
	parent:    int,
	preferred: int,
	real_id:   history.Node_ID,
}

Model :: struct {
	nodes:      [MAX_MODEL_NODES]Model_Node,
	node_count: int,
	active:     int,
}

main :: proc() {
	if !run_generated_history() {
		os.exit(1)
	}
}

run_generated_history :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(900),
		"seed",
		editor.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !initialized {
		fmt.eprintf("fuzz=history phase=buffer-init failure=%v\n", init_failure.code)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	store: history.Store
	policy := history.DEFAULT_POLICY
	policy.guaranteed_recent_units = history.MIN_RECENT_UNITS
	store_ok, store_failure := history.store_init(
		&store,
		history.Store_ID(1),
		editor.Buffer_ID(900),
		editor.Revision(0),
		history.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		policy,
	)
	if !store_ok {
		fmt.eprintf("fuzz=history phase=store-init failure=%v\n", store_failure.code)
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	model, model_error := new(Model)
	if model_error != nil {
		history.store_close(&store)
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	defer free(model)
	model.node_count = 1
	initial_stats, _, _ := history.store_stats(&store)
	model.nodes[0].real_id = initial_stats.active_node
	copy(model.nodes[0].text[:], "seed")
	model.nodes[0].length = len("seed")
	identity := u64(1)
	random := RANDOM_SEED
	passed := true
	for operation in 0 ..< GENERATED_OPERATIONS {
		value := next_random(&random)
		choice := value % 100
		if choice < 45 && model.node_count < MAX_MODEL_NODES {
			active := &model.nodes[model.active]
			delete_operation := value % 4 == 0 && active.length > 0
			start := int((value >> 8) % u64(active.length + 1))
			end := start
			replacement: [1]byte
			replacement_text := ""
			if delete_operation {
				if start == active.length {
					start -= 1
				}
				end = start + 1
			} else if active.length < MAX_MODEL_TEXT_BYTES {
				replacement[0] = byte('a' + (value >> 16) % 26)
				replacement_text = string(replacement[:])
			} else {
				continue
			}
			if !apply_real_edit(&buffer, &store, allocator, &identity, start, end, replacement_text) {
				fmt.eprintf("fuzz=history operation=%d kind=edit status=failed\n", operation)
				passed = false
				break
			}
			model_apply_edit(model, start, end, replacement_text)
			created_stats, _, _ := history.store_stats(&store)
			model.nodes[model.active].real_id = created_stats.active_node
		} else if choice < 65 {
			model_applied := model_undo(model)
			result, navigation_ok := apply_real_navigation(&buffer, &store, allocator, &identity, .Undo)
			if !navigation_ok || (model_applied && result.outcome != .Applied) ||
			   (!model_applied && result.outcome != .At_Root) {
				fmt.eprintf("fuzz=history operation=%d kind=undo outcome=%v model_applied=%v\n", operation, result.outcome, model_applied)
				passed = false
				break
			}
		} else if choice < 82 {
			model_applied := model_redo(model)
			result, navigation_ok := apply_real_navigation(&buffer, &store, allocator, &identity, .Redo)
			if !navigation_ok || (model_applied && result.outcome != .Applied) ||
			   (!model_applied && result.outcome != .No_Child) {
				fmt.eprintf("fuzz=history operation=%d kind=redo outcome=%v model_applied=%v\n", operation, result.outcome, model_applied)
				passed = false
				break
			}
		} else {
			target := int((value >> 24) % u64(model.node_count))
			stats, stats_ok, _ := history.store_stats(&store)
			if !stats_ok {
				passed = false
				break
			}
			result, navigation_ok, navigation_failure := transaction.transaction_history_navigate(
				&store,
				&buffer,
				.Select_Branch,
				transaction.Transaction_ID(identity),
				transaction.Undo_Unit_ID(identity),
				transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
				active_node = stats.active_node,
				target_node = model.nodes[target].real_id,
				policy_generation = stats.policy_generation,
				analysis_operations = history.DEFAULT_INSPECTION_NODES,
			)
			identity += 1
			if !navigation_ok || (target != model.active && result.outcome != .Applied) ||
			   (target == model.active && result.outcome != .Already_Active) {
				fmt.eprintf(
					"fuzz=history operation=%d kind=select target=%d outcome=%v failure=%v\n",
					operation,
					target,
					result.outcome,
					navigation_failure.code,
				)
				passed = false
				break
			}
			model.active = target
		}
		if !buffer_matches_model(&buffer, model) {
			fmt.eprintf("fuzz=history operation=%d phase=compare status=mismatch\n", operation)
			passed = false
			break
		}
	}

	if passed {
		for model.active != 0 {
			model_undo(model)
			_, navigation_ok := apply_real_navigation(&buffer, &store, allocator, &identity, .Undo)
			if !navigation_ok {
				passed = false
				break
			}
		}
	}
	if passed {
		for branch in 0 ..< PRUNING_BRANCHES {
			replacement := [1]byte{byte('A' + branch % 26)}
			if !apply_real_edit(&buffer, &store, allocator, &identity, 0, 0, string(replacement[:])) {
				passed = false
				break
			}
			model_apply_edit(model, 0, 0, string(replacement[:]))
			created_stats, _, _ := history.store_stats(&store)
			model.nodes[model.active].real_id = created_stats.active_node
			model_undo(model)
			_, navigation_ok := apply_real_navigation(&buffer, &store, allocator, &identity, .Undo)
			if !navigation_ok || !buffer_matches_model(&buffer, model) {
				passed = false
				break
			}
		}
	}
	pruned := u64(0)
	if passed {
		prune_ok: bool
		prune_failure: history.Failure_Context
		pruned, prune_ok, prune_failure = history.store_prune(&store, policy.pruning_operations)
		if !prune_ok || prune_failure.code != .None || pruned == 0 || !buffer_matches_model(&buffer, model) {
			fmt.eprintf("fuzz=history phase=prune failure=%v pruned=%d\n", prune_failure.code, pruned)
			passed = false
		}
	}
	stats, stats_ok, _ := history.store_stats(&store)
	if !stats_ok {
		passed = false
	}
	store_closed, _ := history.store_close(&store)
	buffer_closed, _ := editor.buffer_close(&buffer)
	cleanup_bytes := tracking.current_memory_allocated
	cleanup_ok := store_closed && buffer_closed && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	passed = passed && cleanup_ok
	fmt.printf(
		"fuzz=history seed=%d operations=%d model_nodes=%d retained_nodes=%d pruned=%d cleanup_bytes=%d status=%s\n",
		RANDOM_SEED,
		GENERATED_OPERATIONS,
		model.node_count,
		stats.usage.retained_nodes,
		pruned,
		cleanup_bytes,
		"pass" if passed else "fail",
	)
	return passed
}

apply_real_edit :: proc(
	buffer: ^editor.Buffer,
	store: ^history.Store,
	allocator: runtime.Allocator,
	identity: ^u64,
	start_offset, end_offset: int,
	replacement: string,
) -> bool {
	start, start_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(start_offset))
	end, end_ok, _ := editor.buffer_position(buffer, editor.Byte_Offset(end_offset))
	if !start_ok || !end_ok {
		return false
	}
	root: transaction.Transaction
	started, _ := transaction.transaction_begin(
		&root,
		transaction.Transaction_ID(identity^),
		transaction.Undo_Unit_ID(identity^),
		buffer,
		transaction.Origin{kind = .Built_In, descriptor = "history-fuzz"},
		"generated-edit",
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	identity^ += 1
	if !started {
		return false
	}
	applied, _ := transaction.transaction_apply_batch(
		&root,
		[]transaction.Base_Splice {{start = start, end = end, replacement = replacement}},
	)
	tracked, _ := transaction.transaction_track_history(&root, store)
	validated, _ := transaction.transaction_validate(&root)
	_, committed, _ := transaction.transaction_commit(&root)
	closed, _ := transaction.transaction_close(&root)
	return applied && tracked && validated && committed && closed
}

apply_real_navigation :: proc(
	buffer: ^editor.Buffer,
	store: ^history.Store,
	allocator: runtime.Allocator,
	identity: ^u64,
	kind: history.Navigation_Kind,
) -> (history.Navigation_Result, bool) {
	result, ok, _ := transaction.transaction_history_navigate(
		store,
		buffer,
		kind,
		transaction.Transaction_ID(identity^),
		transaction.Undo_Unit_ID(identity^),
		transaction.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	identity^ += 1
	return result, ok
}

model_apply_edit :: proc(model: ^Model, start, end: int, replacement: string) {
	assert(model.node_count < MAX_MODEL_NODES)
	parent_index := model.active
	parent := &model.nodes[parent_index]
	node_index := model.node_count
	node := &model.nodes[node_index]
	prefix := start
	suffix := parent.length - end
	copy(node.text[:prefix], parent.text[:prefix])
	copy(node.text[prefix:prefix + len(replacement)], replacement)
	copy(
		node.text[prefix + len(replacement):prefix + len(replacement) + suffix],
		parent.text[end:parent.length],
	)
	node.length = prefix + len(replacement) + suffix
	node.parent = parent_index
	parent.preferred = node_index
	model.active = node_index
	model.node_count += 1
}

model_undo :: proc(model: ^Model) -> bool {
	if model.active == 0 {
		return false
	}
	source := model.active
	parent := model.nodes[source].parent
	model.nodes[parent].preferred = source
	model.active = parent
	return true
}

model_redo :: proc(model: ^Model) -> bool {
	preferred := model.nodes[model.active].preferred
	if preferred == 0 {
		return false
	}
	model.active = preferred
	return true
}

buffer_matches_model :: proc(buffer: ^editor.Buffer, model: ^Model) -> bool {
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || stats.text_bytes > MAX_MODEL_TEXT_BYTES {
		return false
	}
	observed: [MAX_MODEL_TEXT_BYTES]byte
	copied, inspected, _ := editor.buffer_inspect(
		buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(stats.text_bytes),
		observed[:],
	)
	expected := &model.nodes[model.active]
	return inspected && int(copied) == expected.length &&
	       bytes_equal(observed[:int(copied)], expected.text[:expected.length])
}

bytes_equal :: proc(left, right: []byte) -> bool {
	if len(left) != len(right) {
		return false
	}
	for value, index in left {
		if value != right[index] {
			return false
		}
	}
	return true
}

next_random :: proc(state: ^u64) -> u64 {
	value := state^
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	state^ = value
	return value
}
