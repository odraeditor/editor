// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package text

import "base:runtime"
import "core:unicode/utf8"

@(private)
NODE_SLAB_CAPACITY :: 128
@(private)
CHUNK_SLAB_CAPACITY :: 64

/* Storage_Limits bounds text size, allocation, tree height, and reclamation work. */
Storage_Limits :: struct {
	text_bytes:          u64,
	persistent_bytes:    u64,
	temporary_bytes:     u64,
	tree_levels:         u32,
	reclaim_step_nodes:  u64,
	reclaim_queue_nodes: u64,
}

/* Storage_Failure_Code classifies expected rope failures. */
Storage_Failure_Code :: enum u8 {
	None,
	Invalid_Limits,
	Malformed_UTF8,
	Text_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Tree_Height_Limit,
	Reclaim_Queue_Limit,
	Work_Limit,
	Reference_Count_Overflow,
	Range_Error,
}

/* Storage_Failure reports an expected failure and its relevant bound. */
Storage_Failure :: struct {
	code:   Storage_Failure_Code,
	limit:  u64,
	actual: u64,
}

/*
Root is an opaque retained handle to one immutable rope version.
Each valid handle must eventually be passed by pointer to root_release exactly once.
*/
Root :: distinct [2]uintptr

/* Root_Stats reports root summaries, shape, storage, and deferred reclamation. */
Root_Stats :: struct {
	summary:             Summary,
	height:              u32,
	node_count:          u64,
	chunk_count:         u64,
	persistent_bytes:    u64,
	pending_reclamation: u64,
}

@(private)
Node_Kind :: enum u8 {
	Leaf,
	Internal,
}

@(private)
Chunk :: struct {
	pool_next: ^Chunk,
	used:      u32,
	bytes:     [LEAF_MAX_BYTES]byte,
}

@(private)
Node :: struct {
	pool_next:  ^Node,
	references: u32,
	kind:       Node_Kind,
	height:     u8,
	child_count: u8,
	summary:    Summary,
	chunk:      ^Chunk,
	children:   [INTERNAL_MAX_CHILDREN]^Node,
}

@(private)
Node_Slab :: struct {
	next:  ^Node_Slab,
	used:  u32,
	items: [NODE_SLAB_CAPACITY]Node,
}

@(private)
Chunk_Slab :: struct {
	next:  ^Chunk_Slab,
	used:  u32,
	items: [CHUNK_SLAB_CAPACITY]Chunk,
}

@(private)
Store :: struct {
	allocator:            runtime.Allocator,
	limits:               Storage_Limits,
	handle_count:         u32,
	persistent_bytes:     u64,
	node_count:           u64,
	chunk_count:          u64,
	node_slabs:           ^Node_Slab,
	chunk_slabs:          ^Chunk_Slab,
	free_nodes:           ^Node,
	free_chunks:          ^Chunk,
	reclaim_queue:        []^Node,
	reclaim_queue_length: u64,
}

@(private)
storage_limits_are_valid :: proc(limits: Storage_Limits) -> bool {
	return limits.text_bytes > 0 &&
	       limits.persistent_bytes > 0 &&
	       limits.temporary_bytes > 0 &&
	       limits.tree_levels > 0 &&
	       limits.tree_levels <= MAX_TREE_LEVELS &&
	       limits.reclaim_step_nodes > 0 &&
	       limits.reclaim_queue_nodes > 0 &&
	       limits.reclaim_step_nodes <= limits.reclaim_queue_nodes
}

/*
root_build creates an immutable UTF-8 rope using the persistent allocator.
Temporary arrays use temporary_allocator only during the call. The returned handle owns one
reference and must be released; failure returns an invalid root and releases partial storage.
*/
root_build :: proc(
	contents: string,
	limits: Storage_Limits,
	persistent_allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
) -> (root: Root, failure: Storage_Failure) {
	if !storage_limits_are_valid(limits) {
		return {}, Storage_Failure{code = .Invalid_Limits}
	}
	if persistent_allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, Storage_Failure{code = .Invalid_Limits}
	}

	text_bytes := u64(len(contents))
	if text_bytes > limits.text_bytes {
		return {}, Storage_Failure {
			code = .Text_Limit,
			limit = limits.text_bytes,
			actual = text_bytes,
		}
	}
	if !utf8.valid_string(contents) {
		return {}, Storage_Failure {
			code = .Malformed_UTF8,
			actual = text_bytes,
		}
	}

	store, store_failure := store_create(limits, persistent_allocator)
	if store_failure.code != .None {
		return {}, store_failure
	}

	leaf_count := count_leaf_chunks(contents)
	secondary_capacity := max(u64(1), divide_round_up(leaf_count, u64(INTERNAL_MAX_CHILDREN)))
	pointer_bytes := (leaf_count + secondary_capacity) * u64(size_of(^Node))
	if pointer_bytes > limits.temporary_bytes || leaf_count > u64(max(int)) || secondary_capacity > u64(max(int)) {
		store_destroy(store)
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = limits.temporary_bytes,
			actual = pointer_bytes,
		}
	}

	primary, primary_error := make([]^Node, int(leaf_count), temporary_allocator)
	if primary_error != nil {
		store_destroy(store)
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = limits.temporary_bytes,
			actual = pointer_bytes,
		}
	}
	defer delete(primary, temporary_allocator)

	secondary, secondary_error := make([]^Node, int(secondary_capacity), temporary_allocator)
	if secondary_error != nil {
		store_destroy(store)
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = limits.temporary_bytes,
			actual = pointer_bytes,
		}
	}
	defer delete(secondary, temporary_allocator)

	start := 0
	for leaf_index in 0 ..< len(primary) {
		end := min(len(contents), start + int(LEAF_MAX_BYTES))
		if end < len(contents) {
			for end > start && utf8_is_continuation(contents[end]) {
				end -= 1
			}
		}
		assert(end > start || len(contents) == 0)

		leaf, leaf_failure := leaf_create(store, contents[start:end])
		if leaf_failure.code != .None {
			store_destroy(store)
			return {}, leaf_failure
		}
		primary[leaf_index] = leaf
		start = end
	}
	assert(start == len(contents))

	current := primary
	next := secondary
	current_is_primary := true
	for len(current) > 1 {
		child_total := len(current)
		parent_count := 1
		if child_total > int(INTERNAL_MAX_CHILDREN) {
			parent_count = int(divide_round_up(u64(child_total), u64(INTERNAL_MAX_CHILDREN)))
		}
		if parent_count > len(next) {
			store_destroy(store)
			return {}, Storage_Failure {
				code = .Temporary_Memory_Limit,
				limit = limits.temporary_bytes,
				actual = pointer_bytes,
			}
		}

		base_children := child_total / parent_count
		extra_children := child_total % parent_count
		child_start := 0
		for parent_index in 0 ..< parent_count {
			child_count := base_children
			if parent_index < extra_children {
				child_count += 1
			}
			parent, parent_failure := internal_create(
				store,
				current[child_start:child_start + child_count],
			)
			if parent_failure.code != .None {
				store_destroy(store)
				return {}, parent_failure
			}
			next[parent_index] = parent
			child_start += child_count
		}
		assert(child_start == child_total)

		if current_is_primary {
			current = secondary[:parent_count]
			next = primary
		} else {
			current = primary[:parent_count]
			next = secondary
		}
		current_is_primary = !current_is_primary
	}

	root_node := current[0]
	if u32(root_node.height) > limits.tree_levels {
		store_destroy(store)
		return {}, Storage_Failure {
			code = .Tree_Height_Limit,
			limit = u64(limits.tree_levels),
			actual = u64(root_node.height),
		}
	}

	store.handle_count = 1
	return root_from(store, root_node), {}
}

/* root_is_valid reports whether a root contains a live store and node handle. */
root_is_valid :: proc(root: Root) -> bool {
	return root[0] != 0 && root[1] != 0
}

/*
root_retain acquires another handle to the same immutable version without copying text.
The returned handle must be released independently with root_release.
*/
root_retain :: proc(root: Root) -> (retained: Root, failure: Storage_Failure) {
	if !root_is_valid(root) {
		return {}, Storage_Failure{code = .Range_Error}
	}
	store := root_store(root)
	node := root_node(root)
	if store.handle_count == max(u32) || node.references == max(u32) {
		return {}, Storage_Failure{code = .Reference_Count_Overflow}
	}
	store.handle_count += 1
	node.references += 1
	return root, {}
}

/*
root_release consumes one valid root handle and performs a bounded reclamation step.
Releasing the final store handle drains all remaining reclamation before freeing the store.
*/
root_release :: proc(root: ^Root) {
	if root == nil || !root_is_valid(root^) {
		return
	}
	store := root_store(root^)
	node := root_node(root^)
	root^ = {}

	assert(store.handle_count > 0)
	assert(node.references > 0)
	store.handle_count -= 1
	node.references -= 1
	if node.references == 0 {
		reclaim_push(store, node)
	}

	if store.handle_count == 0 {
		for store.reclaim_queue_length > 0 {
			_ = reclaim_step(store, max(u64))
		}
		assert(store.node_count == 0)
		assert(store.chunk_count == 0)
		store_destroy(store)
		return
	}

	_ = reclaim_step(store, store.limits.reclaim_step_nodes)
}

/* root_maintain performs one bounded deferred-reclamation step and returns nodes reclaimed. */
root_maintain :: proc(root: Root) -> u64 {
	if !root_is_valid(root) {
		return 0
	}
	store := root_store(root)
	return reclaim_step(store, store.limits.reclaim_step_nodes)
}

/* root_stats returns summaries and store accounting for a valid root without allocation. */
root_stats :: proc(root: Root) -> (stats: Root_Stats, ok: bool) {
	if !root_is_valid(root) {
		return {}, false
	}
	store := root_store(root)
	node := root_node(root)
	return Root_Stats {
		summary = node.summary,
		height = u32(node.height),
		node_count = store.node_count,
		chunk_count = store.chunk_count,
		persistent_bytes = store.persistent_bytes,
		pending_reclamation = store.reclaim_queue_length,
	}, true
}

/*
root_copy_range copies bytes starting at start into caller-owned destination storage.
The requested range must fit entirely within the root; the procedure does not allocate.
*/
root_copy_range :: proc(
	root: Root,
	start: u64,
	destination: []byte,
) -> (copied: u64, failure: Storage_Failure) {
	if !root_is_valid(root) {
		return 0, Storage_Failure{code = .Range_Error}
	}
	node := root_node(root)
	total_bytes := u64(node.summary.byte_count)
	if start > total_bytes || u64(len(destination)) > total_bytes - start {
		return 0, Storage_Failure {
			code = .Range_Error,
			limit = total_bytes,
			actual = start + u64(len(destination)),
		}
	}

	remaining := u64(len(destination))
	position := start
	for remaining > 0 {
		leaf, local_offset, found := locate_leaf(node, position)
		if !found {
			return copied, Storage_Failure{code = .Range_Error}
		}
		available := u64(leaf.chunk.used) - local_offset
		take := min(remaining, available)
		copy(
			destination[int(copied):int(copied + take)],
			leaf.chunk.bytes[int(local_offset):int(local_offset + take)],
		)
		copied += take
		position += take
		remaining -= take
	}
	return copied, {}
}

/* root_line_at_offset resolves the logical line containing one checked byte offset. */
root_line_at_offset :: proc(
	root: Root,
	offset: u64,
) -> (location: Line_Location, ok: bool) {
	if !root_is_valid(root) {
		return {}, false
	}
	node := root_node(root)
	total_bytes := u64(node.summary.byte_count)
	if offset > total_bytes {
		return {}, false
	}
	line_index, counted := node_line_feeds_before(node, offset)
	assert(counted)
	start, start_ok := node_line_start(node, line_index)
	assert(start_ok)
	next_start := total_bytes
	content_end := total_bytes
	if line_index < u64(node.summary.line_feed_count) {
		next_start, start_ok = node_line_start(node, line_index + 1)
		assert(start_ok && next_start > 0)
		content_end = next_start - 1
	}
	return Line_Location {
		line_index = line_index,
		start = start,
		content_end = content_end,
		next_start = next_start,
	}, true
}

/*
root_prepare_splice creates an immutable candidate with [start, end) replaced by UTF-8 text.
The base remains valid and may share unchanged nodes with the result. Temporary arrays live only
for the call; the returned root owns one reference and must be released independently.
*/
root_prepare_splice :: proc(
	base: Root,
	start, end: u64,
	replacement: string,
	temporary_allocator: runtime.Allocator,
	work_limit: u64,
) -> (prepared: Root, failure: Storage_Failure) {
	if !root_is_valid(base) || temporary_allocator.procedure == nil {
		return {}, Storage_Failure{code = .Invalid_Limits}
	}
	base_node := root_node(base)
	base_bytes := u64(base_node.summary.byte_count)
	if start > end || end > base_bytes {
		return {}, Storage_Failure {
			code = .Range_Error,
			limit = base_bytes,
			actual = end,
		}
	}
	if !utf8.valid_string(replacement) ||
	   !node_offset_is_boundary(base_node, start) ||
	   !node_offset_is_boundary(base_node, end) {
		return {}, Storage_Failure{code = .Malformed_UTF8}
	}
	if start == end && len(replacement) == 0 {
		return root_retain(base)
	}

	store := root_store(base)
	start_leaf, start_local, start_found := locate_leaf(base_node, start)
	end_leaf, end_local, end_found := locate_leaf(base_node, end)
	if start_found && end_found && start_leaf == end_leaf {
		leaf_result_bytes := start_local + u64(len(replacement)) + u64(start_leaf.chunk.used) - end_local
		if leaf_result_bytes <= LEAF_MAX_BYTES {
			return root_prepare_single_leaf_splice(
				base,
				start_leaf,
				start,
				start_local,
				end_local,
				replacement,
				work_limit,
			)
		}
	}

	stats, stats_ok := root_stats(base)
	assert(stats_ok)
	if stats.node_count == 0 || stats.node_count > u64(max(int)) {
		return {}, Storage_Failure {
			code = .Work_Limit,
			limit = work_limit,
			actual = stats.node_count,
		}
	}

	base_nodes, base_nodes_error := make([]^Node, int(stats.node_count), temporary_allocator)
	if base_nodes_error != nil {
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = store.limits.temporary_bytes,
			actual = stats.node_count * u64(size_of(^Node)),
		}
	}
	defer delete(base_nodes, temporary_allocator)
	base_leaf_count := 0
	visited := u64(0)
	if !flatten_leaves(base_node, base_nodes, &base_leaf_count, &visited, work_limit) {
		return {}, Storage_Failure {
			code = .Work_Limit,
			limit = work_limit,
			actual = visited,
		}
	}
	base_leaves := base_nodes[:base_leaf_count]

	replacement_leaf_capacity := divide_round_up(u64(len(replacement)), LEAF_MAX_BYTES - 3)
	output_capacity := u64(base_leaf_count) + replacement_leaf_capacity + 2
	if output_capacity > u64(max(int)) {
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = store.limits.temporary_bytes,
			actual = output_capacity * u64(size_of(^Node)),
		}
	}
	parent_capacity := max(u64(1), divide_round_up(output_capacity, u64(INTERNAL_MAX_CHILDREN)))
	temporary_pointers := stats.node_count + output_capacity + parent_capacity
	temporary_bytes := temporary_pointers * u64(size_of(^Node))
	if temporary_bytes > store.limits.temporary_bytes || parent_capacity > u64(max(int)) {
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = store.limits.temporary_bytes,
			actual = temporary_bytes,
		}
	}

	output_nodes, output_nodes_error := make([]^Node, int(output_capacity), temporary_allocator)
	if output_nodes_error != nil {
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = store.limits.temporary_bytes,
			actual = temporary_bytes,
		}
	}
	defer delete(output_nodes, temporary_allocator)
	parent_nodes, parent_nodes_error := make([]^Node, int(parent_capacity), temporary_allocator)
	if parent_nodes_error != nil {
		return {}, Storage_Failure {
			code = .Temporary_Memory_Limit,
			limit = store.limits.temporary_bytes,
			actual = temporary_bytes,
		}
	}
	defer delete(parent_nodes, temporary_allocator)
	output_count := 0
	created_work := visited

	failure = append_leaf_range(
		store,
		base_leaves,
		0,
		start,
		output_nodes,
		&output_count,
		&created_work,
		work_limit,
	)
	if failure.code != .None {
		release_owned_nodes(store, output_nodes[:output_count])
		return {}, failure
	}
	failure = append_replacement_leaves(
		store,
		replacement,
		output_nodes,
		&output_count,
		&created_work,
		work_limit,
	)
	if failure.code != .None {
		release_owned_nodes(store, output_nodes[:output_count])
		return {}, failure
	}
	failure = append_leaf_range(
		store,
		base_leaves,
		end,
		base_bytes,
		output_nodes,
		&output_count,
		&created_work,
		work_limit,
	)
	if failure.code != .None {
		release_owned_nodes(store, output_nodes[:output_count])
		return {}, failure
	}
	if output_count == 0 {
		empty, empty_failure := leaf_create(store, "")
		if empty_failure.code != .None {
			return {}, empty_failure
		}
		output_nodes[0] = empty
		output_count = 1
		created_work += 1
	}

	prepared_node, build_failure := tree_build_from_owned_leaves(
		store,
		output_nodes[:output_count],
		parent_nodes,
		&created_work,
		work_limit,
	)
	if build_failure.code != .None {
		return {}, build_failure
	}
	result_bytes := base_bytes - (end - start) + u64(len(replacement))
	if u64(prepared_node.summary.byte_count) != result_bytes || !node_validate_local(prepared_node) {
		release_owned_node(store, prepared_node)
		_ = reclaim_step(store, max(u64))
		panic("prepared rope failed summary validation")
	}
	if store.handle_count == max(u32) {
		release_owned_node(store, prepared_node)
		_ = reclaim_step(store, max(u64))
		return {}, Storage_Failure{code = .Reference_Count_Overflow}
	}
	store.handle_count += 1
	return root_from(store, prepared_node), {}
}

@(private)
root_prepare_single_leaf_splice :: proc(
	base: Root,
	target: ^Node,
	target_offset, start, end: u64,
	replacement: string,
	work_limit: u64,
) -> (prepared: Root, failure: Storage_Failure) {
	assert(target != nil && target.kind == .Leaf)
	assert(start <= end && end <= u64(target.chunk.used))
	result_length := start + u64(len(replacement)) + u64(target.chunk.used) - end
	assert(result_length <= LEAF_MAX_BYTES)

	contents: [LEAF_MAX_BYTES]byte
	offset := 0
	offset += copy(contents[offset:], target.chunk.bytes[:int(start)])
	offset += copy(contents[offset:], replacement)
	offset += copy(contents[offset:], target.chunk.bytes[int(end):target.chunk.used])
	assert(offset == int(result_length))

	store := root_store(base)
	replacement_leaf, leaf_failure := leaf_create(store, string(contents[:offset]))
	if leaf_failure.code != .None {
		return {}, leaf_failure
	}
	work := u64(1)
	prepared_node, path_failure := path_copy_replace_leaf(
		store,
		root_node(base),
		target,
		target_offset,
		replacement_leaf,
		&work,
		work_limit,
	)
	if path_failure.code != .None {
		return {}, path_failure
	}
	if !node_validate_local(prepared_node) {
		release_owned_node(store, prepared_node)
		_ = reclaim_step(store, max(u64))
		panic("path-copied rope failed summary validation")
	}
	if store.handle_count == max(u32) {
		release_owned_node(store, prepared_node)
		_ = reclaim_step(store, max(u64))
		return {}, Storage_Failure{code = .Reference_Count_Overflow}
	}
	store.handle_count += 1
	return root_from(store, prepared_node), {}
}

@(private)
path_copy_replace_leaf :: proc(
	store: ^Store,
	node: ^Node,
	target: ^Node,
	target_offset: u64,
	replacement: ^Node,
	work: ^u64,
	work_limit: u64,
) -> (copied: ^Node, failure: Storage_Failure) {
	if node.kind == .Leaf {
		assert(node == target)
		return replacement, {}
	}
	if work^ >= work_limit {
		release_owned_node(store, replacement)
		_ = reclaim_step(store, max(u64))
		return nil, Storage_Failure {
			code = .Work_Limit,
			limit = work_limit,
			actual = work^ + 1,
		}
	}

	children: [INTERNAL_MAX_CHILDREN]^Node
	target_child := -1
	child_offset := target_offset
	for child_index in 0 ..< int(node.child_count) {
		child := node.children[child_index]
		child_bytes := u64(child.summary.byte_count)
		is_last := child_index == int(node.child_count) - 1
		if child_offset < child_bytes || is_last {
			target_child = child_index
			break
		}
		child_offset -= child_bytes
	}
	assert(target_child >= 0)

	child_copy, child_failure := path_copy_replace_leaf(
		store,
		node.children[target_child],
		target,
		child_offset,
		replacement,
		work,
		work_limit,
	)
	if child_failure.code != .None {
		return nil, child_failure
	}
	children[target_child] = child_copy

	for child_index in 0 ..< int(node.child_count) {
		if child_index == target_child {
			continue
		}
		child := node.children[child_index]
		if child.references == max(u32) {
			release_owned_nodes(store, children[:node.child_count])
			return nil, Storage_Failure{code = .Reference_Count_Overflow}
		}
		child.references += 1
		children[child_index] = child
	}

	parent, parent_failure := internal_create(store, children[:node.child_count])
	if parent_failure.code != .None {
		release_owned_nodes(store, children[:node.child_count])
		return nil, parent_failure
	}
	work^ += 1
	return parent, {}
}

@(private)
root_from :: proc(store: ^Store, node: ^Node) -> Root {
	return Root{uintptr(store), uintptr(node)}
}

@(private)
root_store :: proc(root: Root) -> ^Store {
	return (^Store)(rawptr(root[0]))
}

@(private)
root_node :: proc(root: Root) -> ^Node {
	return (^Node)(rawptr(root[1]))
}

@(private)
flatten_leaves :: proc(
	node: ^Node,
	destination: []^Node,
	leaf_count: ^int,
	visited: ^u64,
	work_limit: u64,
) -> bool {
	visited^ += 1
	if visited^ > work_limit {
		return false
	}
	if node.kind == .Leaf {
		if leaf_count^ >= len(destination) {
			return false
		}
		destination[leaf_count^] = node
		leaf_count^ += 1
		return true
	}
	for child_index in 0 ..< int(node.child_count) {
		if !flatten_leaves(node.children[child_index], destination, leaf_count, visited, work_limit) {
			return false
		}
	}
	return true
}

@(private)
append_leaf_range :: proc(
	store: ^Store,
	leaves: []^Node,
	start, end: u64,
	destination: []^Node,
	destination_count: ^int,
	work: ^u64,
	work_limit: u64,
) -> (failure: Storage_Failure) {
	if start == end {
		return {}
	}
	position := u64(0)
	for leaf in leaves {
		leaf_bytes := u64(leaf.summary.byte_count)
		leaf_start := position
		leaf_end := position + leaf_bytes
		position = leaf_end
		if leaf_end <= start || leaf_start >= end {
			continue
		}

		range_start := max(start, leaf_start) - leaf_start
		range_end := min(end, leaf_end) - leaf_start
		if range_start == 0 && range_end == leaf_bytes {
			if leaf.references == max(u32) {
				return Storage_Failure{code = .Reference_Count_Overflow}
			}
			leaf.references += 1
			destination[destination_count^] = leaf
			destination_count^ += 1
			continue
		}

		if work^ >= work_limit {
			return Storage_Failure {
				code = .Work_Limit,
				limit = work_limit,
				actual = work^ + 1,
			}
		}
		fragment := string(leaf.chunk.bytes[int(range_start):int(range_end)])
		new_leaf, leaf_failure := leaf_create(store, fragment)
		if leaf_failure.code != .None {
			return leaf_failure
		}
		work^ += 1
		destination[destination_count^] = new_leaf
		destination_count^ += 1
	}
	return {}
}

@(private)
append_replacement_leaves :: proc(
	store: ^Store,
	replacement: string,
	destination: []^Node,
	destination_count: ^int,
	work: ^u64,
	work_limit: u64,
) -> (failure: Storage_Failure) {
	start := 0
	for start < len(replacement) {
		end := min(len(replacement), start + int(LEAF_MAX_BYTES))
		if end < len(replacement) {
			for end > start && utf8_is_continuation(replacement[end]) {
				end -= 1
			}
		}
		assert(end > start)
		if work^ >= work_limit {
			return Storage_Failure {
				code = .Work_Limit,
				limit = work_limit,
				actual = work^ + 1,
			}
		}
		leaf, leaf_failure := leaf_create(store, replacement[start:end])
		if leaf_failure.code != .None {
			return leaf_failure
		}
		work^ += 1
		destination[destination_count^] = leaf
		destination_count^ += 1
		start = end
	}
	return {}
}

@(private)
tree_build_from_owned_leaves :: proc(
	store: ^Store,
	leaves: []^Node,
	parent_buffer: []^Node,
	work: ^u64,
	work_limit: u64,
) -> (root: ^Node, failure: Storage_Failure) {
	assert(len(leaves) > 0)
	if len(leaves) == 1 {
		return leaves[0], {}
	}

	current := leaves
	next := parent_buffer
	current_is_leaves := true
	for len(current) > 1 {
		child_total := len(current)
		parent_count := 1
		if child_total > int(INTERNAL_MAX_CHILDREN) {
			parent_count = int(divide_round_up(u64(child_total), u64(INTERNAL_MAX_CHILDREN)))
		}
		if parent_count > len(next) {
			release_owned_nodes(store, current)
			return nil, Storage_Failure{code = .Temporary_Memory_Limit}
		}

		base_children := child_total / parent_count
		extra_children := child_total % parent_count
		child_start := 0
		created_parents := 0
		for parent_index in 0 ..< parent_count {
			if work^ >= work_limit {
				release_owned_nodes(store, current[child_start:])
				release_owned_nodes(store, next[:created_parents])
				return nil, Storage_Failure {
					code = .Work_Limit,
					limit = work_limit,
					actual = work^ + 1,
				}
			}
			child_count := base_children
			if parent_index < extra_children {
				child_count += 1
			}
			parent, parent_failure := internal_create(
				store,
				current[child_start:child_start + child_count],
			)
			if parent_failure.code != .None {
				release_owned_nodes(store, current[child_start:])
				release_owned_nodes(store, next[:created_parents])
				return nil, parent_failure
			}
			for child_index in child_start ..< child_start + child_count {
				current[child_index] = nil
			}
			next[parent_index] = parent
			created_parents += 1
			child_start += child_count
			work^ += 1
		}

		if current_is_leaves {
			current = parent_buffer[:parent_count]
			next = leaves
		} else {
			current = leaves[:parent_count]
			next = parent_buffer
		}
		current_is_leaves = !current_is_leaves
	}
	return current[0], {}
}

@(private)
release_owned_nodes :: proc(store: ^Store, nodes: []^Node) {
	for node in nodes {
		if node != nil {
			release_owned_node(store, node)
		}
	}
	_ = reclaim_step(store, max(u64))
}

@(private)
release_owned_node :: proc(store: ^Store, node: ^Node) {
	assert(node != nil && node.references > 0)
	node.references -= 1
	if node.references == 0 {
		reclaim_push(store, node)
	}
}

@(private)
node_offset_is_boundary :: proc(root: ^Node, offset: u64) -> bool {
	if offset == 0 || offset == u64(root.summary.byte_count) {
		return true
	}
	leaf, local_offset, found := locate_leaf(root, offset)
	return found && local_offset < u64(leaf.chunk.used) &&
	       !utf8_is_continuation(leaf.chunk.bytes[local_offset])
}

@(private)
node_validate_local :: proc(node: ^Node) -> bool {
	if node == nil || node.references == 0 {
		return false
	}
	if node.kind == .Leaf {
		if node.height != 1 || node.chunk == nil || node.chunk.used > u32(LEAF_MAX_BYTES) {
			return false
		}
		contents := string(node.chunk.bytes[:node.chunk.used])
		return utf8.valid_string(contents) &&
		       u64(node.summary.byte_count) == u64(node.chunk.used) &&
		       u64(node.summary.line_feed_count) == count_line_feeds(contents)
	}
	if node.child_count < 2 || node.child_count > u8(INTERNAL_MAX_CHILDREN) {
		return false
	}
	summary: Summary
	for child_index in 0 ..< int(node.child_count) {
		child := node.children[child_index]
		if child == nil || child.references == 0 || u32(child.height) + 1 != u32(node.height) {
			return false
		}
		child_bytes := u64(child.summary.byte_count)
		child_lines := u64(child.summary.line_feed_count)
		if child_bytes > max(u64) - u64(summary.byte_count) ||
		   child_lines > max(u64) - u64(summary.line_feed_count) {
			return false
		}
		summary.byte_count = Byte_Count(u64(summary.byte_count) + child_bytes)
		summary.line_feed_count = Line_Feed_Count(u64(summary.line_feed_count) + child_lines)
	}
	return summary == node.summary
}

@(private)
node_validate :: proc(node: ^Node) -> bool {
	if !node_validate_local(node) {
		return false
	}
	if node.kind == .Leaf {
		return true
	}
	for child_index in 0 ..< int(node.child_count) {
		child := node.children[child_index]
		if !node_validate(child) {
			return false
		}
	}
	return true
}

@(private)
store_create :: proc(
	limits: Storage_Limits,
	allocator: runtime.Allocator,
) -> (store: ^Store, failure: Storage_Failure) {
	initial_bytes := u64(size_of(Store)) + limits.reclaim_queue_nodes * u64(size_of(^Node))
	if initial_bytes > limits.persistent_bytes || limits.reclaim_queue_nodes > u64(max(int)) {
		return nil, Storage_Failure {
			code = .Persistent_Memory_Limit,
			limit = limits.persistent_bytes,
			actual = initial_bytes,
		}
	}

	created_store, allocation_error := new(Store, allocator)
	if allocation_error != nil {
		return nil, Storage_Failure {
			code = .Persistent_Memory_Limit,
			limit = limits.persistent_bytes,
		}
	}
	created_store.allocator = allocator
	created_store.limits = limits
	created_store.persistent_bytes = u64(size_of(Store))

	queue, queue_error := make([]^Node, int(limits.reclaim_queue_nodes), allocator)
	if queue_error != nil {
		free(created_store, allocator)
		return nil, Storage_Failure {
			code = .Persistent_Memory_Limit,
			limit = limits.persistent_bytes,
			actual = initial_bytes,
		}
	}
	created_store.reclaim_queue = queue
	created_store.persistent_bytes = initial_bytes
	return created_store, {}
}

@(private)
store_destroy :: proc(store: ^Store) {
	if store == nil {
		return
	}
	allocator := store.allocator

	node_slab := store.node_slabs
	for node_slab != nil {
		next := node_slab.next
		free(node_slab, allocator)
		node_slab = next
	}

	chunk_slab := store.chunk_slabs
	for chunk_slab != nil {
		next := chunk_slab.next
		free(chunk_slab, allocator)
		chunk_slab = next
	}

	if store.reclaim_queue != nil {
		delete(store.reclaim_queue, allocator)
	}
	free(store, allocator)
}

@(private)
store_reserve :: proc(store: ^Store, bytes: u64) -> (failure: Storage_Failure) {
	if bytes > max(u64) - store.persistent_bytes {
		return Storage_Failure {
			code = .Persistent_Memory_Limit,
			limit = store.limits.persistent_bytes,
			actual = max(u64),
		}
	}
	actual := store.persistent_bytes + bytes
	if actual > store.limits.persistent_bytes {
		return Storage_Failure {
			code = .Persistent_Memory_Limit,
			limit = store.limits.persistent_bytes,
			actual = actual,
		}
	}
	return {}
}

@(private)
node_take :: proc(store: ^Store) -> (node: ^Node, failure: Storage_Failure) {
	if store.free_nodes != nil {
		node = store.free_nodes
		store.free_nodes = node.pool_next
		node^ = {}
		store.node_count += 1
		return node, {}
	}

	if store.node_slabs == nil || store.node_slabs.used == NODE_SLAB_CAPACITY {
		failure = store_reserve(store, u64(size_of(Node_Slab)))
		if failure.code != .None {
			return nil, failure
		}
		slab, allocation_error := new(Node_Slab, store.allocator)
		if allocation_error != nil {
			return nil, Storage_Failure {
				code = .Persistent_Memory_Limit,
				limit = store.limits.persistent_bytes,
			}
		}
		slab.next = store.node_slabs
		store.node_slabs = slab
		store.persistent_bytes += u64(size_of(Node_Slab))
	}

	slab := store.node_slabs
	node = &slab.items[slab.used]
	slab.used += 1
	store.node_count += 1
	return node, {}
}

@(private)
chunk_take :: proc(store: ^Store) -> (chunk: ^Chunk, failure: Storage_Failure) {
	if store.free_chunks != nil {
		chunk = store.free_chunks
		store.free_chunks = chunk.pool_next
		chunk^ = {}
		store.chunk_count += 1
		return chunk, {}
	}

	if store.chunk_slabs == nil || store.chunk_slabs.used == CHUNK_SLAB_CAPACITY {
		failure = store_reserve(store, u64(size_of(Chunk_Slab)))
		if failure.code != .None {
			return nil, failure
		}
		slab, allocation_error := new(Chunk_Slab, store.allocator)
		if allocation_error != nil {
			return nil, Storage_Failure {
				code = .Persistent_Memory_Limit,
				limit = store.limits.persistent_bytes,
			}
		}
		slab.next = store.chunk_slabs
		store.chunk_slabs = slab
		store.persistent_bytes += u64(size_of(Chunk_Slab))
	}

	slab := store.chunk_slabs
	chunk = &slab.items[slab.used]
	slab.used += 1
	store.chunk_count += 1
	return chunk, {}
}

@(private)
leaf_create :: proc(store: ^Store, contents: string) -> (^Node, Storage_Failure) {
	assert(len(contents) <= int(LEAF_MAX_BYTES))
	chunk, chunk_failure := chunk_take(store)
	if chunk_failure.code != .None {
		return nil, chunk_failure
	}
	node, node_failure := node_take(store)
	if node_failure.code != .None {
		chunk.pool_next = store.free_chunks
		store.free_chunks = chunk
		store.chunk_count -= 1
		return nil, node_failure
	}

	chunk.used = u32(len(contents))
	copy(chunk.bytes[:len(contents)], transmute([]byte)contents)
	node.references = 1
	node.kind = .Leaf
	node.height = 1
	node.summary = Summary {
		byte_count = Byte_Count(len(contents)),
		line_feed_count = Line_Feed_Count(count_line_feeds(contents)),
	}
	node.chunk = chunk
	return node, {}
}

@(private)
internal_create :: proc(store: ^Store, children: []^Node) -> (^Node, Storage_Failure) {
	assert(len(children) >= 2)
	assert(len(children) <= int(INTERNAL_MAX_CHILDREN))
	node, failure := node_take(store)
	if failure.code != .None {
		return nil, failure
	}

	height := u32(children[0].height) + 1
	if height > store.limits.tree_levels {
		node.pool_next = store.free_nodes
		store.free_nodes = node
		store.node_count -= 1
		return nil, Storage_Failure {
			code = .Tree_Height_Limit,
			limit = u64(store.limits.tree_levels),
			actual = u64(height),
		}
	}

	summary: Summary
	for child, child_index in children {
		assert(child != nil)
		assert(u32(child.height) + 1 == height)
		child_bytes := u64(child.summary.byte_count)
		child_lines := u64(child.summary.line_feed_count)
		if child_bytes > max(u64) - u64(summary.byte_count) ||
		   child_lines > max(u64) - u64(summary.line_feed_count) {
			node.pool_next = store.free_nodes
			store.free_nodes = node
			store.node_count -= 1
			return nil, Storage_Failure{code = .Text_Limit}
		}
		summary.byte_count = Byte_Count(u64(summary.byte_count) + child_bytes)
		summary.line_feed_count = Line_Feed_Count(u64(summary.line_feed_count) + child_lines)
		node.children[child_index] = child
	}

	node.references = 1
	node.kind = .Internal
	node.height = u8(height)
	node.child_count = u8(len(children))
	node.summary = summary
	return node, {}
}

@(private)
reclaim_push :: proc(store: ^Store, node: ^Node) {
	assert(store.reclaim_queue_length < u64(len(store.reclaim_queue)), "reclamation queue exhausted")
	store.reclaim_queue[store.reclaim_queue_length] = node
	store.reclaim_queue_length += 1
}

@(private)
reclaim_step :: proc(store: ^Store, limit: u64) -> u64 {
	reclaimed := u64(0)
	for reclaimed < limit && store.reclaim_queue_length > 0 {
		store.reclaim_queue_length -= 1
		node := store.reclaim_queue[store.reclaim_queue_length]
		store.reclaim_queue[store.reclaim_queue_length] = nil
		assert(node.references == 0)

		if node.kind == .Internal {
			for child_index in 0 ..< int(node.child_count) {
				child := node.children[child_index]
				assert(child != nil)
				assert(child.references > 0)
				child.references -= 1
				if child.references == 0 {
					reclaim_push(store, child)
				}
			}
		} else {
			assert(node.chunk != nil)
			node.chunk.pool_next = store.free_chunks
			store.free_chunks = node.chunk
			store.chunk_count -= 1
		}

		node^ = {}
		node.pool_next = store.free_nodes
		store.free_nodes = node
		store.node_count -= 1
		reclaimed += 1
	}
	return reclaimed
}

@(private)
locate_leaf :: proc(root: ^Node, offset: u64) -> (leaf: ^Node, local_offset: u64, ok: bool) {
	if root == nil || offset > u64(root.summary.byte_count) {
		return nil, 0, false
	}
	node := root
	remaining := offset
	for node.kind == .Internal {
		selected: ^Node
		for child_index in 0 ..< int(node.child_count) {
			child := node.children[child_index]
			child_bytes := u64(child.summary.byte_count)
			is_last := child_index == int(node.child_count) - 1
			if remaining < child_bytes || is_last {
				selected = child
				break
			}
			remaining -= child_bytes
		}
		if selected == nil {
			return nil, 0, false
		}
		node = selected
	}
	if remaining > u64(node.chunk.used) {
		return nil, 0, false
	}
	return node, remaining, true
}

@(private)
node_line_feeds_before :: proc(node: ^Node, offset: u64) -> (count: u64, ok: bool) {
	if node == nil || offset > u64(node.summary.byte_count) {
		return 0, false
	}
	if node.kind == .Leaf {
		return count_line_feeds(string(node.chunk.bytes[:int(offset)])), true
	}
	remaining := offset
	for child_index in 0 ..< int(node.child_count) {
		child := node.children[child_index]
		child_bytes := u64(child.summary.byte_count)
		if remaining >= child_bytes {
			count += u64(child.summary.line_feed_count)
			remaining -= child_bytes
			if remaining == 0 {
				return count, true
			}
			continue
		}
		child_count, child_ok := node_line_feeds_before(child, remaining)
		return count + child_count, child_ok
	}
	return count, remaining == 0
}

@(private)
node_line_start :: proc(node: ^Node, line_index: u64) -> (offset: u64, ok: bool) {
	if node == nil || line_index > u64(node.summary.line_feed_count) {
		return 0, false
	}
	if line_index == 0 {
		return 0, true
	}
	if node.kind == .Leaf {
		remaining := line_index
		for byte_value, byte_index in node.chunk.bytes[:node.chunk.used] {
			if byte_value != '\n' {
				continue
			}
			remaining -= 1
			if remaining == 0 {
				return u64(byte_index) + 1, true
			}
		}
		return 0, false
	}
	remaining := line_index
	base_offset: u64
	for child_index in 0 ..< int(node.child_count) {
		child := node.children[child_index]
		child_lines := u64(child.summary.line_feed_count)
		if remaining > child_lines {
			remaining -= child_lines
			base_offset += u64(child.summary.byte_count)
			continue
		}
		child_offset, child_ok := node_line_start(child, remaining)
		return base_offset + child_offset, child_ok
	}
	return 0, false
}

@(private)
count_line_feeds :: proc(contents: string) -> u64 {
	count := u64(0)
	for value in transmute([]byte)contents {
		if value == '\n' {
			count += 1
		}
	}
	return count
}

@(private)
count_leaf_chunks :: proc(contents: string) -> u64 {
	if len(contents) == 0 {
		return 1
	}

	count := u64(0)
	start := 0
	for start < len(contents) {
		end := min(len(contents), start + int(LEAF_MAX_BYTES))
		if end < len(contents) {
			for end > start && utf8_is_continuation(contents[end]) {
				end -= 1
			}
		}
		assert(end > start)
		start = end
		count += 1
	}
	return count
}

@(private)
utf8_is_continuation :: proc(value: byte) -> bool {
	return value & 0xc0 == 0x80
}

@(private)
divide_round_up :: proc(value, divisor: u64) -> u64 {
	assert(divisor > 0)
	return value / divisor + (1 if value % divisor != 0 else 0)
}
