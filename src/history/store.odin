// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import editor_view "../view"
import "base:runtime"
import "core:unicode/utf8"

@(private)
Reservation_Kind :: enum u8 {
	Invalid,
	Record,
	Revision,
	Navigation,
}

@(private)
Stored_Edit :: struct {
	start:            editor.Byte_Offset,
	end:              editor.Byte_Offset,
	replacement_text: string,
	removed_text:     string,
}

@(private)
Record :: struct {
	id:                    Record_ID,
	unit_id:               Unit_ID,
	source_transaction_id: Source_Transaction_ID,
	source_undo_unit_id:   Source_Undo_Unit_ID,
	buffer_id:             editor.Buffer_ID,
	base_revision:         editor.Revision,
	result_revision:       editor.Revision,
	edits:                 []Stored_Edit,
	origin:                Record_Origin,
	origin_descriptor:     string,
	command:               string,
	cursor:                Cursor_Context,
	retained_bytes:        u64,
	payload_bytes:         u64,
}

@(private)
Grouping_State :: struct {
	kind:                   Grouping_Kind,
	view_id:                editor_view.View_ID,
	view_generation:        u32,
	continuity:             u64,
	last_event_sequence:    u64,
	last_milliseconds:      u64,
	semantic_start:         editor.Byte_Offset,
	semantic_boundary:      editor.Byte_Offset,
}

@(private)
Node :: struct {
	id:                Node_ID,
	unit_id:           Unit_ID,
	parent:            ^Node,
	first_child:       ^Node,
	next_sibling:      ^Node,
	preferred_child:   ^Node,
	creation_previous: ^Node,
	creation_next:     ^Node,
	records:           []^Record,
	grouping:          Grouping_State,
	creation_order:    u64,
	depth:             u64,
	child_count:       u64,
	link:              ^Link_State,
}

@(private)
Store_State :: struct {
	store_id:               Store_ID,
	history_id:             History_ID,
	buffer_id:              editor.Buffer_ID,
	current_revision:       editor.Revision,
	policy:                 Policy,
	policy_generation:      Policy_Generation,
	allocator:              runtime.Allocator,
	temporary_allocator:    runtime.Allocator,
	root:                   ^Node,
	active:                 ^Node,
	creation_head:          ^Node,
	creation_tail:          ^Node,
	next_node_slot:         u64,
	next_unit_id:           Unit_ID,
	next_record_id:         Record_ID,
	next_creation_order:    u64,
	buffer_retained_bytes:  u64,
	usage:                  Resource_Usage,
	pending_reservation:    bool,
}

@(private)
Reservation_State :: struct {
	kind:              Reservation_Kind,
	store:             ^Store_State,
	node:              ^Node,
	record:            ^Record,
	records:           []^Record,
	grouping:          Grouping_State,
	extends_active:    bool,
	source_node:       ^Node,
	target_node:       ^Node,
	navigation_kind:   Navigation_Kind,
	navigation_edits:  []Navigation_Edit,
	navigation_path:   []^Node,
	navigation_pivot:  int,
	expected_revision: editor.Revision,
}

/* store_is_valid reports whether a handle owns live history state. */
store_is_valid :: proc(store: ^Store) -> bool {
	return store != nil && store.state != nil
}

/* store_close_ready reports whether no reservation or linked unit blocks deterministic close. */
store_close_ready :: proc(store: ^Store) -> (ready: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.pending_reservation {
		return false, store_failure(state, .Invalid_State)
	}
	for node := state.creation_head; node != nil; node = node.creation_next {
		if node.link != nil {
			return false, store_failure(state, .Incomplete_Participant_Set)
		}
	}
	return true, {}
}

/* reservation_is_valid reports whether a handle owns one unpublished history update. */
reservation_is_valid :: proc(reservation: ^Reservation) -> bool {
	return reservation != nil && reservation.state != nil
}

/*
store_init creates one single-buffer history rooted at the supplied confirmed revision.
The caller keeps both allocators and the associated buffer identity valid until close.
*/
store_init :: proc(
	store: ^Store,
	store_id: Store_ID,
	buffer_id: editor.Buffer_ID,
	initial_revision: editor.Revision,
	allocators: Allocator_Set,
	policy := DEFAULT_POLICY,
) -> (ok: bool, failure: Failure_Context) {
	assert(store != nil)
	assert(store.state == nil, "history store is already initialized")
	if store_id == Store_ID(0) || buffer_id == editor.Buffer_ID(0) {
		return false, Failure_Context{code = .Invalid_Identity, store_id = store_id, buffer_id = buffer_id}
	}
	if policy_ok, policy_failure := policy_validate(policy); !policy_ok {
		return false, policy_failure
	}
	if allocators.persistent.procedure == nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, store_id = store_id}
	}
	if allocators.temporary.procedure == nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, store_id = store_id}
	}
	initial_bytes := u64(size_of(Store_State)) + u64(size_of(Node))
	if initial_bytes > policy.global_retained_bytes || u64(size_of(Node)) > policy.buffer_retained_bytes {
		return false, Failure_Context {
			code = .Retained_Bytes_Limit,
			store_id = store_id,
			maximum = policy.global_retained_bytes,
			actual = initial_bytes,
		}
	}
	state, state_error := new(Store_State, allocators.persistent)
	if state_error != nil {
		return false, Failure_Context{code = .Persistent_Memory_Limit, store_id = store_id}
	}
	root, root_error := new(Node, allocators.persistent)
	if root_error != nil {
		free(state, allocators.persistent)
		return false, Failure_Context{code = .Persistent_Memory_Limit, store_id = store_id}
	}
	root.id = Node_ID{history_id = History_ID(1), slot = 1, generation = 1}
	root.creation_order = 1
	state.store_id = store_id
	state.history_id = History_ID(1)
	state.buffer_id = buffer_id
	state.current_revision = initial_revision
	state.policy = policy
	state.policy_generation = Policy_Generation(1)
	state.allocator = allocators.persistent
	state.temporary_allocator = allocators.temporary
	state.root = root
	state.active = root
	state.creation_head = root
	state.creation_tail = root
	state.next_node_slot = 2
	state.next_unit_id = Unit_ID(1)
	state.next_record_id = Record_ID(1)
	state.next_creation_order = 2
	state.buffer_retained_bytes = u64(size_of(Node))
	state.usage.retained_bytes = initial_bytes
	state.usage.retained_nodes = 1
	store.state = state
	return true, {}
}

/* store_stats returns bounded ownership, revision, active topology, and accounting state. */
store_stats :: proc(store: ^Store) -> (stats: Store_Stats, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	active_parent := Node_ID{}
	if state.active.parent != nil {
		active_parent = state.active.parent.id
	}
	preferred_child := Node_ID{}
	if state.active.preferred_child != nil {
		preferred_child = state.active.preferred_child.id
	}
	return Store_Stats {
		store_id = state.store_id,
		history_id = state.history_id,
		buffer_id = state.buffer_id,
		current_revision = state.current_revision,
		active_node = state.active.id,
		active_parent = active_parent,
		active_preferred_child = preferred_child,
		active_child_count = state.active.child_count,
		active_record_count = u64(len(state.active.records)),
		active_payload_bytes = node_payload_bytes(state.active),
		active_grouping_kind = state.active.grouping.kind,
		policy_generation = state.policy_generation,
		usage = state.usage,
	}, true, {}
}

/*
record_reserve copies one complete immutable record before its transaction can publish.
Success owns all payload storage until commit, abort, pruning, or store close.
*/
record_reserve :: proc(
	store: ^Store,
	reservation: ^Reservation,
	input: Record_Input,
) -> (ok: bool, failure: Failure_Context) {
	assert(reservation != nil)
	assert(reservation.state == nil, "history reservation is already initialized")
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.pending_reservation {
		return false, store_failure(state, .Invalid_State)
	}
	input_valid, input_failure := record_input_validate(state, input)
	if !input_valid {
		return false, input_failure
	}
	extends_active, next_grouping := grouping_join_plan(state, input)
	record, record_ok, record_failure := record_clone(state, input)
	if !record_ok {
		return false, record_failure
	}
	record_count := 1
	if extends_active {
		record_count = len(state.active.records) + 1
	}
	records, records_error := make([]^Record, record_count, state.allocator)
	if records_error != nil {
		record_release(record, state.allocator)
		return false, store_failure(state, .Persistent_Memory_Limit)
	}
	if extends_active {
		copy(records, state.active.records)
	}
	records[record_count - 1] = record

	node: ^Node
	if extends_active {
		node = state.active
	} else {
		node_error: runtime.Allocator_Error
		node, node_error = new(Node, state.allocator)
		if node_error != nil {
			delete(records, state.allocator)
			record_release(record, state.allocator)
			return false, store_failure(state, .Persistent_Memory_Limit)
		}
	}
	reservation_state, reservation_error := new(Reservation_State, state.temporary_allocator)
	if reservation_error != nil {
		if !extends_active {
			free(node, state.allocator)
		}
		delete(records, state.allocator)
		record_release(record, state.allocator)
		return false, store_failure(state, .Temporary_Memory_Limit)
	}

	retained_bytes := record.retained_bytes + u64(size_of(^Record))
	if !extends_active {
		retained_bytes += u64(size_of(Node))
	}
	global_bytes, global_ok := checked_add_u64(state.usage.retained_bytes, retained_bytes)
	buffer_bytes, buffer_ok := checked_add_u64(state.buffer_retained_bytes, retained_bytes)
	additional_nodes := u64(0) if extends_active else u64(1)
	global_nodes, nodes_ok := checked_add_u64(state.usage.retained_nodes, additional_nodes)
	if !global_ok || global_bytes > state.policy.global_retained_bytes {
		reservation_prepare_release(reservation_state, node, records, record, state, extends_active)
		return false, store_limit_failure(state, .Retained_Bytes_Limit, state.policy.global_retained_bytes, global_bytes)
	}
	if !buffer_ok || buffer_bytes > state.policy.buffer_retained_bytes {
		reservation_prepare_release(reservation_state, node, records, record, state, extends_active)
		return false, store_limit_failure(state, .Retained_Bytes_Limit, state.policy.buffer_retained_bytes, buffer_bytes)
	}
	if !nodes_ok || global_nodes > state.policy.global_nodes || global_nodes > state.policy.buffer_nodes {
		reservation_prepare_release(reservation_state, node, records, record, state, extends_active)
		return false, store_limit_failure(state, .Node_Limit, min(state.policy.global_nodes, state.policy.buffer_nodes), global_nodes)
	}
	if !extends_active && state.active.child_count >= state.policy.sibling_branches {
		reservation_prepare_release(reservation_state, node, records, record, state, extends_active)
		return false, store_limit_failure(state, .Branch_Limit, state.policy.sibling_branches, state.active.child_count + 1)
	}
	if !extends_active && state.active.depth >= state.policy.retained_depth {
		reservation_prepare_release(reservation_state, node, records, record, state, extends_active)
		return false, store_limit_failure(state, .Depth_Limit, state.policy.retained_depth, state.active.depth + 1)
	}

	if !extends_active {
		node.id = Node_ID {
			history_id = state.history_id,
			slot = state.next_node_slot,
			generation = 1,
		}
		node.unit_id = state.next_unit_id
		node.records = records
		node.grouping = grouping_state_for_new(input)
		node.creation_order = state.next_creation_order
		node.depth = state.active.depth + 1
		state.next_node_slot += 1
		state.next_unit_id = Unit_ID(u64(state.next_unit_id) + 1)
		state.next_creation_order += 1
	}
	record.id = state.next_record_id
	record.unit_id = node.unit_id
	state.next_record_id = Record_ID(u64(state.next_record_id) + 1)
	reservation_state.kind = .Record
	reservation_state.store = state
	reservation_state.node = node
	reservation_state.record = record
	reservation_state.records = records
	reservation_state.grouping = next_grouping if extends_active else node.grouping
	reservation_state.extends_active = extends_active
	reservation_state.expected_revision = input.result_revision
	state.pending_reservation = true
	reservation.state = reservation_state
	return true, {}
}

/* revision_reserve prepares a fresh revision with no text record or history node. */
revision_reserve :: proc(
	store: ^Store,
	reservation: ^Reservation,
	base_revision, result_revision: editor.Revision,
) -> (ok: bool, failure: Failure_Context) {
	assert(reservation != nil)
	assert(reservation.state == nil, "history reservation is already initialized")
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return false, state_failure
	}
	if state.pending_reservation {
		return false, store_failure(state, .Invalid_State)
	}
	if base_revision != state.current_revision || u64(result_revision) != u64(base_revision) + 1 {
		return false, store_revision_failure(state, base_revision)
	}
	reserved, reservation_error := new(Reservation_State, state.temporary_allocator)
	if reservation_error != nil {
		return false, store_failure(state, .Temporary_Memory_Limit)
	}
	reserved.kind = .Revision
	reserved.store = state
	reserved.expected_revision = result_revision
	state.pending_reservation = true
	reservation.state = reserved
	return true, {}
}

/*
reservation_commit_reserved finalizes an already reserved record after canonical publication.
It performs no allocation and accepts only the exact predicted fresh revision.
*/
reservation_commit_reserved :: proc(reservation: ^Reservation, result_revision: editor.Revision) {
	assert(reservation_is_valid(reservation))
	reserved := (^Reservation_State)(reservation.state)
	assert(reserved.kind == .Record || reserved.kind == .Revision)
	assert(reserved.store != nil && reserved.store.pending_reservation)
	assert(result_revision == reserved.expected_revision)
	state := reserved.store
	if reserved.kind == .Revision {
		state.current_revision = result_revision
		state.pending_reservation = false
		reservation.state = nil
		free(reserved, state.temporary_allocator)
		return
	}
	if reserved.extends_active {
		node := reserved.node
		assert(node == state.active && len(reserved.records) == len(node.records) + 1)
		previous_records := node.records
		node.records = reserved.records
		node.grouping = reserved.grouping
		state.current_revision = result_revision
		retained_bytes := reserved.record.retained_bytes + u64(size_of(^Record))
		state.buffer_retained_bytes += retained_bytes
		state.usage.retained_bytes += retained_bytes
		state.usage.retained_records += 1
		state.usage.retained_payload_bytes += reserved.record.payload_bytes
		delete(previous_records, state.allocator)
		state.pending_reservation = false
		reservation.state = nil
		free(reserved, state.temporary_allocator)
		return
	}
	node := reserved.node
	parent := state.active
	node.parent = parent
	node.next_sibling = parent.first_child
	parent.first_child = node
	parent.preferred_child = node
	parent.child_count += 1
	node.creation_previous = state.creation_tail
	state.creation_tail.creation_next = node
	state.creation_tail = node
	state.active = node
	state.current_revision = result_revision
	retained_bytes := reserved.record.retained_bytes + u64(size_of(^Record)) + u64(size_of(Node))
	state.buffer_retained_bytes += retained_bytes
	state.usage.retained_bytes += retained_bytes
	state.usage.retained_nodes += 1
	state.usage.retained_records += 1
	state.usage.retained_payload_bytes += reserved.record.payload_bytes
	state.pending_reservation = false
	reservation.state = nil
	free(reserved, state.temporary_allocator)
}

/* reservation_abort releases one unpublished record or navigation plan without topology change. */
reservation_abort :: proc(reservation: ^Reservation) -> (ok: bool, failure: Failure_Context) {
	if !reservation_is_valid(reservation) {
		return false, Failure_Context{code = .Invalid_State}
	}
	reserved := (^Reservation_State)(reservation.state)
	state := reserved.store
	if state == nil || !state.pending_reservation {
		return false, Failure_Context{code = .Invalid_State}
	}
	if reserved.kind == .Record {
		if !reserved.extends_active {
			free(reserved.node, state.allocator)
		}
		delete(reserved.records, state.allocator)
		record_release(reserved.record, state.allocator)
	} else if reserved.kind == .Navigation {
		if reserved.navigation_edits != nil {
			delete(reserved.navigation_edits, state.temporary_allocator)
		}
		if reserved.navigation_path != nil {
			delete(reserved.navigation_path, state.temporary_allocator)
		}
	}
	state.pending_reservation = false
	reservation.state = nil
	free(reserved, state.temporary_allocator)
	return true, {}
}

/*
navigation_prepare reserves the bounded coordinates for ordinary undo or redo.
At-root and absent-child outcomes are successful no-op alternatives with no reservation.
*/
navigation_prepare :: proc(
	store: ^Store,
	request: Navigation_Request,
) -> (plan: Navigation_Plan, result: Navigation_Result, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, {}, false, state_failure
	}
	if state.pending_reservation {
		return {}, {}, false, store_failure(state, .Invalid_State)
	}
	if request.buffer_id != state.buffer_id {
		return {}, {}, false, store_failure(state, .Wrong_Buffer)
	}
	if request.current_revision != state.current_revision {
		return {}, {}, false, store_revision_failure(state, request.current_revision)
	}
	if node_id_is_valid(request.active_node) && request.active_node != state.active.id {
		failure = store_failure(state, .Stale_Generation)
		failure.node_id = request.active_node
		return {}, {}, false, failure
	}
	if request.kind == .Select_Branch {
		return branch_navigation_prepare(state, request)
	}

	target: ^Node
	source := state.active
	switch request.kind {
	case .Undo:
		if source == state.root {
			return {}, Navigation_Result {
				outcome = .At_Root,
				active_node = source.id,
				result_revision = state.current_revision,
				policy_generation = state.policy_generation,
			}, true, {}
		}
		target = source.parent
	case .Redo:
		target = source.preferred_child
		if target == nil {
			outcome := Navigation_Outcome.No_Child
			if source.child_count > 0 {
				outcome = .Branch_Choice_Required
			}
			return {}, Navigation_Result {
				outcome = outcome,
				active_node = source.id,
				result_revision = state.current_revision,
				policy_generation = state.policy_generation,
			}, true, {}
		}
	case .Invalid, .Select_Branch, .Selective_Undo:
		return {}, {}, false, store_failure(state, .Invalid_State)
	}

	records := source.records
	if request.kind == .Redo {
		records = target.records
	}
	if len(records) == 0 {
		return {}, {}, false, store_failure(state, .Missing_Payload)
	}
	edit_count := 0
	for record in records {
		if record == nil {
			return {}, {}, false, store_failure(state, .Missing_Payload)
		}
		if len(record.edits) > max(int) - edit_count {
			return {}, {}, false, store_failure(state, .Work_Limit)
		}
		edit_count += len(record.edits)
	}
	edits, edit_error := make([]Navigation_Edit, edit_count, state.temporary_allocator)
	if edit_error != nil {
		return {}, {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	prepared := navigation_unit_edits_prepare(edits, records, request.kind)
	if !prepared {
		delete(edits, state.temporary_allocator)
		return {}, {}, false, store_failure(state, .Missing_Payload)
	}
	reserved, reservation_error := new(Reservation_State, state.temporary_allocator)
	if reservation_error != nil {
		delete(edits, state.temporary_allocator)
		return {}, {}, false, store_failure(state, .Temporary_Memory_Limit)
	}
	reserved.kind = .Navigation
	reserved.store = state
	reserved.source_node = source
	reserved.target_node = target
	reserved.navigation_kind = request.kind
	reserved.navigation_edits = edits
	reserved.expected_revision = editor.Revision(u64(state.current_revision) + 1)
	state.pending_reservation = true
	plan = Navigation_Plan {
		reservation = Reservation{state = reserved},
		kind = request.kind,
		source_node = source.id,
		target_node = target.id,
		edits = edits,
		cursor = navigation_cursor_restore(records, request.kind),
	}
	return plan, Navigation_Result {
		outcome = .Applied,
		active_node = source.id,
		result_revision = state.current_revision,
		policy_generation = state.policy_generation,
	}, true, {}
}

/* navigation_commit_reserved moves activity after its exact text transition publishes. */
navigation_commit_reserved :: proc(plan: ^Navigation_Plan, result_revision: editor.Revision) -> Navigation_Result {
	assert(plan != nil && reservation_is_valid(&plan.reservation))
	reserved := (^Reservation_State)(plan.reservation.state)
	assert(reserved.kind == .Navigation)
	assert(reserved.store != nil && reserved.store.pending_reservation)
	assert(result_revision == reserved.expected_revision)
	state := reserved.store
	if reserved.navigation_kind == .Undo {
		reserved.target_node.preferred_child = reserved.source_node
	} else if reserved.navigation_kind == .Select_Branch {
		assert(len(reserved.navigation_path) > 1)
		for index in 0 ..< reserved.navigation_pivot {
			parent := reserved.navigation_path[index + 1]
			parent.preferred_child = reserved.navigation_path[index]
		}
		for index in reserved.navigation_pivot ..< len(reserved.navigation_path) - 1 {
			parent := reserved.navigation_path[index]
			parent.preferred_child = reserved.navigation_path[index + 1]
		}
	}
	state.active = reserved.target_node
	state.current_revision = result_revision
	delete(reserved.navigation_edits, state.temporary_allocator)
	if reserved.navigation_path != nil {
		delete(reserved.navigation_path, state.temporary_allocator)
	}
	state.pending_reservation = false
	plan.reservation.state = nil
	plan.edits = nil
	result := Navigation_Result {
		outcome = .Applied,
		active_node = state.active.id,
		result_revision = result_revision,
		policy_generation = state.policy_generation,
	}
	free(reserved, state.temporary_allocator)
	return result
}

/* navigation_abort releases one unpublished navigation plan without moving activity. */
navigation_abort :: proc(plan: ^Navigation_Plan) -> (ok: bool, failure: Failure_Context) {
	if plan == nil {
		return false, Failure_Context{code = .Invalid_State}
	}
	ok, failure = reservation_abort(&plan.reservation)
	if ok {
		plan.edits = nil
	}
	return
}

/*
store_prune removes complete inactive leaf units within one explicit work budget.
It preserves the root, active ancestry, and the configured recent creation window.
*/
store_prune :: proc(store: ^Store, operation_limit: u64) -> (pruned: u64, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return 0, false, state_failure
	}
	if state.pending_reservation {
		return 0, false, store_failure(state, .Invalid_State)
	}
	limit := min(operation_limit, state.policy.pruning_operations)
	protected_order := u64(0)
	if state.next_creation_order > state.policy.guaranteed_recent_units {
		protected_order = state.next_creation_order - state.policy.guaranteed_recent_units
	}
	node := state.creation_head
	for node != nil && pruned < limit {
		next := node.creation_next
		if node != state.root && node != state.active && node.child_count == 0 &&
		   node.link == nil && node.creation_order < protected_order {
			node_detach_leaf(node)
			creation_detach(state, node)
			node_release_accounted(state, node)
			pruned += 1
		}
		node = next
	}
	state.usage.pruning_operations += pruned
	return pruned, true, {}
}

/* store_close releases every retained node, payload, and store allocation. */
store_close :: proc(store: ^Store) -> (ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return false, state_failure
	}
	if ready, ready_failure := store_close_ready(store); !ready {
		return false, ready_failure
	}
	allocator := state.allocator
	node := state.creation_head
	for node != nil {
		next := node.creation_next
		node_records_release(node, allocator)
		free(node, allocator)
		node = next
	}
	store.state = nil
	free(state, allocator)
	return true, {}
}

@(private)
store_live_state :: proc(store: ^Store) -> (^Store_State, Failure_Context) {
	if !store_is_valid(store) {
		return nil, Failure_Context{code = .Invalid_State}
	}
	return (^Store_State)(store.state), {}
}

@(private)
record_input_validate :: proc(state: ^Store_State, input: Record_Input) -> (bool, Failure_Context) {
	if input.source_transaction_id == Source_Transaction_ID(0) ||
	   input.source_undo_unit_id == Source_Undo_Unit_ID(0) {
		return false, store_failure(state, .Invalid_Identity)
	}
	if input.buffer_id != state.buffer_id {
		return false, store_failure(state, .Wrong_Buffer)
	}
	if input.base_revision != state.current_revision ||
	   u64(input.result_revision) != u64(input.base_revision) + 1 {
		return false, store_revision_failure(state, input.base_revision)
	}
	if len(input.edits) == 0 || u64(len(input.edits)) > state.policy.records_per_unit {
		return false, store_limit_failure(state, .Record_Limit, state.policy.records_per_unit, u64(len(input.edits)))
	}
	if input.origin == .Invalid || !utf8.valid_string(input.origin_descriptor) ||
	   u64(len(input.origin_descriptor)) > MAX_ORIGIN_BYTES {
		return false, store_limit_failure(state, .Record_Limit, MAX_ORIGIN_BYTES, u64(len(input.origin_descriptor)))
	}
	if !utf8.valid_string(input.command) || u64(len(input.command)) > MAX_COMMAND_BYTES {
		return false, store_limit_failure(state, .Record_Limit, MAX_COMMAND_BYTES, u64(len(input.command)))
	}
	payload_bytes := u64(0)
	for edit in input.edits {
		if edit.start > edit.end || !utf8.valid_string(edit.replacement_text) || !utf8.valid_string(edit.removed_text) {
			return false, store_failure(state, .Missing_Payload)
		}
		operation_bytes, operation_ok := checked_add_u64(u64(len(edit.replacement_text)), u64(len(edit.removed_text)))
		payload_ok: bool
		payload_bytes, payload_ok = checked_add_u64(payload_bytes, operation_bytes)
		if !operation_ok || !payload_ok || payload_bytes > state.policy.payload_bytes_per_unit {
			return false, store_limit_failure(state, .Retained_Bytes_Limit, state.policy.payload_bytes_per_unit, payload_bytes)
		}
	}
	if input.grouping.kind == .Typing_Insert || input.grouping.kind == .Typing_Backspace ||
	   input.grouping.kind == .Query_Replacement {
		if input.origin != .Built_In || input.grouping.view_id == editor_view.View_ID(0) ||
		   input.grouping.view_generation == 0 || input.grouping.continuity == 0 ||
		   input.grouping.event_sequence == 0 {
			return false, store_failure(state, .Invalid_State)
		}
		if input.grouping.kind != .Query_Replacement {
			if len(input.edits) != 1 {
				return false, store_failure(state, .Invalid_State)
			}
			edit := input.edits[0]
			if input.grouping.kind == .Typing_Insert &&
			   (edit.start != edit.end || len(edit.replacement_text) == 0 || len(edit.removed_text) != 0) {
				return false, store_failure(state, .Invalid_State)
			}
			if input.grouping.kind == .Typing_Backspace &&
			   (edit.start >= edit.end || len(edit.replacement_text) != 0 || len(edit.removed_text) == 0) {
				return false, store_failure(state, .Invalid_State)
			}
		}
	}
	if input.cursor.present {
		if input.cursor.view.view_id == editor_view.View_ID(0) || input.cursor.view.generation == 0 ||
		   input.cursor.buffer_id != input.buffer_id || input.cursor.base_revision != input.base_revision ||
		   input.cursor.result_revision != input.result_revision ||
		   (input.cursor.before_region_active && !input.cursor.before_mark_present) ||
		   (input.cursor.after_region_active && !input.cursor.after_mark_present) {
			return false, store_failure(state, .Invalid_State)
		}
	}
	return true, {}
}

@(private)
grouping_join_plan :: proc(state: ^Store_State, input: Record_Input) -> (bool, Grouping_State) {
	active := state.active
	if active == state.root || active.child_count != 0 || len(active.records) == 0 ||
	   input.grouping.kind == .Invalid || input.grouping.kind == .Independent {
		return false, {}
	}
	group := active.grouping
	if input.origin != .Built_In || input.grouping.view_id != group.view_id ||
	   input.grouping.view_generation != group.view_generation ||
	   input.grouping.continuity != group.continuity ||
	   u64(len(active.records)) >= state.policy.records_per_unit {
		return false, {}
	}
	if active.grouping.kind == .Query_Replacement {
		if input.grouping.kind != .Query_Replacement ||
		   input.grouping.event_sequence <= group.last_event_sequence {
			return false, {}
		}
		active_payload, payload_ok := checked_add_u64(
			node_payload_bytes(active),
			record_input_payload_bytes(input),
		)
		if !payload_ok || active_payload > state.policy.payload_bytes_per_unit {
			return false, {}
		}
		group.last_event_sequence = input.grouping.event_sequence
		group.last_milliseconds = input.grouping.monotonic_milliseconds
		return true, group
	}
	if active.grouping.kind != .Typing_Insert ||
	   input.grouping.event_sequence != group.last_event_sequence + 1 ||
	   input.grouping.monotonic_milliseconds < group.last_milliseconds ||
	   input.grouping.monotonic_milliseconds - group.last_milliseconds > DEFAULT_TYPING_GROUP_IDLE_MILLISECONDS {
		return false, {}
	}
	edit := input.edits[0]
	if input.grouping.kind == .Typing_Insert {
		if edit.start != group.semantic_boundary || edit.end != group.semantic_boundary {
			return false, {}
		}
		group.semantic_boundary = editor.Byte_Offset(u64(group.semantic_boundary) + u64(len(edit.replacement_text)))
	} else if input.grouping.kind == .Typing_Backspace {
		if edit.end != group.semantic_boundary || edit.start < group.semantic_start {
			return false, {}
		}
		group.semantic_boundary = edit.start
	} else {
		return false, {}
	}
	active_payload, payload_ok := checked_add_u64(node_payload_bytes(active), record_input_payload_bytes(input))
	if !payload_ok || active_payload > state.policy.payload_bytes_per_unit {
		return false, {}
	}
	group.last_event_sequence = input.grouping.event_sequence
	group.last_milliseconds = input.grouping.monotonic_milliseconds
	return true, group
}

@(private)
grouping_state_for_new :: proc(input: Record_Input) -> Grouping_State {
	if input.grouping.kind == .Query_Replacement {
		return Grouping_State {
			kind = .Query_Replacement,
			view_id = input.grouping.view_id,
			view_generation = input.grouping.view_generation,
			continuity = input.grouping.continuity,
			last_event_sequence = input.grouping.event_sequence,
			last_milliseconds = input.grouping.monotonic_milliseconds,
		}
	}
	if input.grouping.kind != .Typing_Insert || len(input.edits) != 1 {
		return {}
	}
	edit := input.edits[0]
	return Grouping_State {
		kind = .Typing_Insert,
		view_id = input.grouping.view_id,
		view_generation = input.grouping.view_generation,
		continuity = input.grouping.continuity,
		last_event_sequence = input.grouping.event_sequence,
		last_milliseconds = input.grouping.monotonic_milliseconds,
		semantic_start = edit.start,
		semantic_boundary = editor.Byte_Offset(u64(edit.start) + u64(len(edit.replacement_text))),
	}
}

@(private)
record_input_payload_bytes :: proc(input: Record_Input) -> u64 {
	total := u64(0)
	for edit in input.edits {
		total += u64(len(edit.replacement_text) + len(edit.removed_text))
	}
	return total
}

@(private)
node_payload_bytes :: proc(node: ^Node) -> u64 {
	if node == nil {
		return 0
	}
	total := u64(0)
	for record in node.records {
		if record != nil {
			total += record.payload_bytes
		}
	}
	return total
}

@(private)
navigation_cursor_restore :: proc(records: []^Record, kind: Navigation_Kind) -> Cursor_Restore {
	if len(records) == 0 {
		return {}
	}
	record := records[0]
	if kind == .Redo {
		record = records[len(records) - 1]
	}
	if record == nil || !record.cursor.present {
		return {}
	}
	offset := record.cursor.before_byte_offset
	desired := record.cursor.before_desired_column
	mark_present := record.cursor.before_mark_present
	mark_offset := record.cursor.before_mark_offset
	region_active := record.cursor.before_region_active
	selection_shape := record.cursor.before_selection_shape
	rectangle_column_policy := record.cursor.before_rectangle_column_policy
	if kind == .Redo {
		offset = record.cursor.after_byte_offset
		desired = record.cursor.after_desired_column
		mark_present = record.cursor.after_mark_present
		mark_offset = record.cursor.after_mark_offset
		region_active = record.cursor.after_region_active
		selection_shape = record.cursor.after_selection_shape
		rectangle_column_policy = record.cursor.after_rectangle_column_policy
	}
	return Cursor_Restore {
		present = true,
		initiating_view = record.cursor.view,
		buffer_id = record.cursor.buffer_id,
		byte_offset = offset,
		desired_display_column = desired,
		mark_present = mark_present,
		mark_offset = mark_offset,
		region_active = region_active,
		selection_shape = selection_shape,
		rectangle_column_policy = rectangle_column_policy,
	}
}

@(private)
record_clone :: proc(state: ^Store_State, input: Record_Input) -> (^Record, bool, Failure_Context) {
	record, record_error := new(Record, state.allocator)
	if record_error != nil {
		return nil, false, store_failure(state, .Persistent_Memory_Limit)
	}
	edits, edit_error := make([]Stored_Edit, len(input.edits), state.allocator)
	if edit_error != nil {
		free(record, state.allocator)
		return nil, false, store_failure(state, .Persistent_Memory_Limit)
	}
	record.edits = edits
	for edit, index in input.edits {
		replacement, replacement_error := clone_string(edit.replacement_text, state.allocator)
		if replacement_error != nil {
			record_release(record, state.allocator)
			return nil, false, store_failure(state, .Persistent_Memory_Limit)
		}
		removed, removed_error := clone_string(edit.removed_text, state.allocator)
		if removed_error != nil {
			delete_string(replacement, state.allocator)
			record_release(record, state.allocator)
			return nil, false, store_failure(state, .Persistent_Memory_Limit)
		}
		record.edits[index] = Stored_Edit {
			start = edit.start,
			end = edit.end,
			replacement_text = replacement,
			removed_text = removed,
		}
		record.payload_bytes += u64(len(replacement) + len(removed))
	}
	origin, origin_error := clone_string(input.origin_descriptor, state.allocator)
	if origin_error != nil {
		record_release(record, state.allocator)
		return nil, false, store_failure(state, .Persistent_Memory_Limit)
	}
	record.origin_descriptor = origin
	command, command_error := clone_string(input.command, state.allocator)
	if command_error != nil {
		record_release(record, state.allocator)
		return nil, false, store_failure(state, .Persistent_Memory_Limit)
	}
	record.command = command
	record.source_transaction_id = input.source_transaction_id
	record.source_undo_unit_id = input.source_undo_unit_id
	record.buffer_id = input.buffer_id
	record.base_revision = input.base_revision
	record.result_revision = input.result_revision
	record.origin = input.origin
	record.cursor = input.cursor
	record.retained_bytes = u64(size_of(Record)) +
	                        u64(len(edits)) * u64(size_of(Stored_Edit)) +
	                        record.payload_bytes +
	                        u64(len(origin) + len(command))
	return record, true, {}
}

@(private)
record_release :: proc(record: ^Record, allocator: runtime.Allocator) {
	if record == nil {
		return
	}
	for edit in record.edits {
		delete_string(edit.replacement_text, allocator)
		delete_string(edit.removed_text, allocator)
	}
	if record.edits != nil {
		delete(record.edits, allocator)
	}
	delete_string(record.origin_descriptor, allocator)
	delete_string(record.command, allocator)
	free(record, allocator)
}

@(private)
reservation_prepare_release :: proc(
	reserved: ^Reservation_State,
	node: ^Node,
	records: []^Record,
	record: ^Record,
	state: ^Store_State,
	extends_active: bool,
) {
	free(reserved, state.temporary_allocator)
	if !extends_active {
		free(node, state.allocator)
	}
	delete(records, state.allocator)
	record_release(record, state.allocator)
}

@(private)
navigation_unit_edits_prepare :: proc(destination: []Navigation_Edit, records: []^Record, kind: Navigation_Kind) -> bool {
	offset := 0
	if kind == .Redo {
		for record in records {
			segment := destination[offset:offset + len(record.edits)]
			if !navigation_record_edits_prepare(segment, record.edits, kind) {
				return false
			}
			offset += len(record.edits)
		}
	} else if kind == .Undo {
		for record_index := len(records) - 1; record_index >= 0; record_index -= 1 {
			record := records[record_index]
			segment := destination[offset:offset + len(record.edits)]
			if !navigation_record_edits_prepare(segment, record.edits, kind) {
				return false
			}
			offset += len(record.edits)
		}
	} else {
		return false
	}
	return offset == len(destination)
}

@(private)
navigation_record_edits_prepare :: proc(destination: []Navigation_Edit, stored: []Stored_Edit, kind: Navigation_Kind) -> bool {
	if len(destination) != len(stored) {
		return false
	}
	inserted_before := u64(0)
	removed_before := u64(0)
	for edit, index in stored {
		if kind == .Redo {
			destination[len(stored) - 1 - index] = Navigation_Edit {
				start = edit.start,
				end = edit.end,
				replacement = edit.replacement_text,
			}
			continue
		}
		base_with_insertions, base_ok := checked_add_u64(u64(edit.start), inserted_before)
		if !base_ok || base_with_insertions < removed_before {
			return false
		}
		result_start := base_with_insertions - removed_before
		result_end, end_ok := checked_add_u64(result_start, u64(len(edit.replacement_text)))
		if !end_ok {
			return false
		}
		destination[index] = Navigation_Edit {
			start = editor.Byte_Offset(result_start),
			end = editor.Byte_Offset(result_end),
			replacement = edit.removed_text,
		}
		inserted_ok, removed_ok: bool
		inserted_before, inserted_ok = checked_add_u64(inserted_before, u64(len(edit.replacement_text)))
		removed_before, removed_ok = checked_add_u64(removed_before, u64(edit.end) - u64(edit.start))
		if !inserted_ok || !removed_ok {
			return false
		}
	}
	if kind == .Undo {
		for left, right := 0, len(destination) - 1; left < right; left, right = left + 1, right - 1 {
			destination[left], destination[right] = destination[right], destination[left]
		}
	}
	return true
}

@(private)
node_accounted_storage :: proc(node: ^Node) -> (retained_bytes, payload_bytes: u64) {
	assert(node != nil && len(node.records) > 0)
	retained_bytes = u64(size_of(Node)) + u64(len(node.records)) * u64(size_of(^Record))
	for record in node.records {
		assert(record != nil)
		retained_bytes += record.retained_bytes
		payload_bytes += record.payload_bytes
	}
	return
}

@(private)
node_detach_leaf :: proc(node: ^Node) {
	assert(node != nil && node.parent != nil && node.child_count == 0)
	parent := node.parent
	previous: ^Node
	child := parent.first_child
	for child != nil && child != node {
		previous = child
		child = child.next_sibling
	}
	assert(child == node)
	if previous == nil {
		parent.first_child = node.next_sibling
	} else {
		previous.next_sibling = node.next_sibling
	}
	parent.child_count -= 1
	if parent.preferred_child == node {
		parent.preferred_child = parent.first_child
	}
	node.parent = nil
	node.next_sibling = nil
}

@(private)
creation_detach :: proc(state: ^Store_State, node: ^Node) {
	if node.creation_previous != nil {
		node.creation_previous.creation_next = node.creation_next
	} else {
		state.creation_head = node.creation_next
	}
	if node.creation_next != nil {
		node.creation_next.creation_previous = node.creation_previous
	} else {
		state.creation_tail = node.creation_previous
	}
}

@(private)
node_release_accounted :: proc(state: ^Store_State, node: ^Node) {
	assert(node != nil && len(node.records) > 0)
	assert(node.link == nil, "linked history nodes require complete-set pruning")
	retained_bytes, payload_bytes := node_accounted_storage(node)
	state.buffer_retained_bytes -= retained_bytes
	state.usage.retained_bytes -= retained_bytes
	state.usage.retained_nodes -= 1
	state.usage.retained_records -= u64(len(node.records))
	state.usage.retained_payload_bytes -= payload_bytes
	node_records_release(node, state.allocator)
	free(node, state.allocator)
}

@(private)
node_records_release :: proc(node: ^Node, allocator: runtime.Allocator) {
	if node == nil {
		return
	}
	for record in node.records {
		record_release(record, allocator)
	}
	if node.records != nil {
		delete(node.records, allocator)
		node.records = nil
	}
}

@(private)
store_failure :: proc(state: ^Store_State, code: Failure_Code) -> Failure_Context {
	return Failure_Context {
		code = code,
		store_id = state.store_id,
		history_id = state.history_id,
		buffer_id = state.buffer_id,
		revision = state.current_revision,
		policy_generation = state.policy_generation,
	}
}

@(private)
store_limit_failure :: proc(state: ^Store_State, code: Failure_Code, limit, actual: u64) -> Failure_Context {
	failure := store_failure(state, code)
	failure.maximum = limit
	failure.actual = actual
	return failure
}

@(private)
store_revision_failure :: proc(state: ^Store_State, actual: editor.Revision) -> Failure_Context {
	failure := store_failure(state, .Stale_Revision)
	failure.actual = u64(actual)
	return failure
}

@(private)
clone_string :: proc(contents: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	if len(contents) == 0 {
		return "", nil
	}
	bytes, allocation_error := make([]byte, len(contents), allocator)
	if allocation_error != nil {
		return "", allocation_error
	}
	copy(bytes, contents)
	return string(bytes), nil
}

@(private)
delete_string :: proc(contents: string, allocator: runtime.Allocator) {
	if len(contents) > 0 {
		delete(contents, allocator)
	}
}

@(private)
checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left {
		return 0, false
	}
	return left + right, true
}
