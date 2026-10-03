// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package history

import "../editor"
import "base:runtime"
import "core:slice"

@(private)
Link_State :: struct {
	id:                    Link_ID,
	source_transaction_id: Source_Transaction_ID,
	source_undo_unit_id:   Source_Undo_Unit_ID,
	participants:          []Link_Participant_State,
	owner:                 ^Store_State,
	allocator:             runtime.Allocator,
	retained_bytes:        u64,
	live_nodes:            u64,
}

@(private)
Link_Participant_State :: struct {
	store:           ^Store_State,
	node:            ^Node,
	base_revision:   editor.Revision,
	result_revision: editor.Revision,
}

@(private)
Multibuffer_Record_Seed :: struct {
	input: Multibuffer_Record_Input,
	state: ^Store_State,
}

@(private)
Multibuffer_Reservation_State :: struct {
	link:         ^Link_State,
	reservations: []Reservation,
	allocator:    runtime.Allocator,
}

@(private)
Multibuffer_Navigation_State :: struct {
	plans:     []Navigation_Plan,
	buffers:   []Multibuffer_Navigation_Buffer,
	allocator: runtime.Allocator,
}

@(private)
Multibuffer_Selective_State :: struct {
	plans:     []Selective_Plan,
	buffers:   []Multibuffer_Navigation_Buffer,
	allocator: runtime.Allocator,
}

/* multibuffer_reservation_is_valid reports whether a complete unpublished set is owned. */
multibuffer_reservation_is_valid :: proc(reservation: ^Multibuffer_Reservation) -> bool {
	return reservation != nil && reservation.state != nil
}

/*
multibuffer_record_reserve copies and links one deterministic complete participant set.
Every record, node, participant entry, and link is owned before this procedure succeeds.
*/
multibuffer_record_reserve :: proc(
	reservation: ^Multibuffer_Reservation,
	inputs: []Multibuffer_Record_Input,
) -> (ok: bool, failure: Failure_Context) {
	assert(reservation != nil)
	assert(reservation.state == nil, "multibuffer history reservation is already initialized")
	if len(inputs) == 0 {
		return false, Failure_Context{code = .Incomplete_Participant_Set}
	}

	first_store, first_failure := store_live_state(inputs[0].store)
	if first_failure.code != .None {
		return false, first_failure
	}
	seeds, seed_error := make([]Multibuffer_Record_Seed, len(inputs), first_store.temporary_allocator)
	if seed_error != nil {
		return false, store_failure(first_store, .Temporary_Memory_Limit)
	}
	defer delete(seeds, first_store.temporary_allocator)
	for input, index in inputs {
		state, state_failure := store_live_state(input.store)
		if state_failure.code != .None {
			return false, state_failure
		}
		seeds[index] = Multibuffer_Record_Seed{input = input, state = state}
	}
	slice.sort_by(seeds, multibuffer_record_seed_less)

	shared_transaction := seeds[0].input.record.source_transaction_id
	shared_undo := seeds[0].input.record.source_undo_unit_id
	if shared_transaction == Source_Transaction_ID(0) || shared_undo == Source_Undo_Unit_ID(0) {
		return false, store_failure(seeds[0].state, .Invalid_Identity)
	}
	for seed, index in seeds {
		if u64(len(seeds)) > seed.state.policy.multibuffer_participants {
			return false, store_limit_failure(
				seed.state,
				.Participant_Limit,
				seed.state.policy.multibuffer_participants,
				u64(len(seeds)),
			)
		}
		if seed.input.record.source_transaction_id != shared_transaction ||
		   seed.input.record.source_undo_unit_id != shared_undo {
			return false, store_failure(seed.state, .Divergent_Participant)
		}
		if seed.input.record.buffer_id != seed.state.buffer_id {
			return false, store_failure(seed.state, .Wrong_Buffer)
		}
		if index > 0 && seeds[index - 1].state.buffer_id == seed.state.buffer_id {
			return false, store_failure(seed.state, .Incomplete_Participant_Set)
		}
	}

	owner := seeds[0].state
	reserved, reservation_error := make([]Reservation, len(seeds), owner.temporary_allocator)
	if reservation_error != nil {
		return false, store_failure(owner, .Temporary_Memory_Limit)
	}
	link, link_error := new(Link_State, owner.allocator)
	if link_error != nil {
		delete(reserved, owner.temporary_allocator)
		return false, store_failure(owner, .Persistent_Memory_Limit)
	}
	participants, participant_error := make([]Link_Participant_State, len(seeds), owner.allocator)
	if participant_error != nil {
		free(link, owner.allocator)
		delete(reserved, owner.temporary_allocator)
		return false, store_failure(owner, .Persistent_Memory_Limit)
	}
	link_bytes := u64(size_of(Link_State)) + u64(len(participants)) * u64(size_of(Link_Participant_State))
	projected_bytes, projected_ok := checked_add_u64(owner.usage.retained_bytes, link_bytes)
	if !projected_ok || projected_bytes > owner.policy.global_retained_bytes {
		delete(participants, owner.allocator)
		free(link, owner.allocator)
		delete(reserved, owner.temporary_allocator)
		return false, store_limit_failure(owner, .Retained_Bytes_Limit, owner.policy.global_retained_bytes, projected_bytes)
	}

	link.id = Link_ID(shared_undo)
	link.source_transaction_id = shared_transaction
	link.source_undo_unit_id = shared_undo
	link.participants = participants
	link.owner = owner
	link.allocator = owner.allocator
	link.retained_bytes = link_bytes
	for seed, index in seeds {
		record := seed.input.record
		record.grouping.kind = .Independent
		record_ok, record_failure := record_reserve(seed.input.store, &reserved[index], record)
		if !record_ok {
			multibuffer_reserved_records_abort(reserved[:index])
			delete(participants, owner.allocator)
			free(link, owner.allocator)
			delete(reserved, owner.temporary_allocator)
			return false, record_failure
		}
		reserved_state := (^Reservation_State)(reserved[index].state)
		assert(!reserved_state.extends_active)
		reserved_state.node.link = link
		participants[index] = Link_Participant_State {
			store = seed.state,
			node = reserved_state.node,
			base_revision = record.base_revision,
			result_revision = record.result_revision,
		}
	}
	owner_reserved := (^Reservation_State)(reserved[0].state)
	owner_record_bytes := owner_reserved.record.retained_bytes + u64(size_of(^Record)) + u64(size_of(Node))
	projected_bytes, projected_ok = checked_add_u64(projected_bytes, owner_record_bytes)
	if !projected_ok || projected_bytes > owner.policy.global_retained_bytes {
		multibuffer_reserved_records_abort(reserved)
		delete(participants, owner.allocator)
		free(link, owner.allocator)
		delete(reserved, owner.temporary_allocator)
		return false, store_limit_failure(owner, .Retained_Bytes_Limit, owner.policy.global_retained_bytes, projected_bytes)
	}

	state, state_error := new(Multibuffer_Reservation_State, owner.temporary_allocator)
	if state_error != nil {
		multibuffer_reserved_records_abort(reserved)
		delete(participants, owner.allocator)
		free(link, owner.allocator)
		delete(reserved, owner.temporary_allocator)
		return false, store_failure(owner, .Temporary_Memory_Limit)
	}
	state.link = link
	state.reservations = reserved
	state.allocator = owner.temporary_allocator
	reservation.state = state
	return true, {}
}

/* multibuffer_reservation_commit_reserved finalizes every linked node without allocation. */
multibuffer_reservation_commit_reserved :: proc(
	reservation: ^Multibuffer_Reservation,
) {
	assert(multibuffer_reservation_is_valid(reservation))
	state := (^Multibuffer_Reservation_State)(reservation.state)
	for &record, index in state.reservations {
		reservation_commit_reserved(&record, state.link.participants[index].result_revision)
	}
	state.link.live_nodes = u64(len(state.link.participants))
	state.link.owner.usage.retained_bytes += state.link.retained_bytes
	state.link.owner.usage.retained_links += 1
	allocator := state.allocator
	delete(state.reservations, allocator)
	reservation.state = nil
	free(state, allocator)
}

/* multibuffer_reservation_abort releases every unpublished participant and link. */
multibuffer_reservation_abort :: proc(
	reservation: ^Multibuffer_Reservation,
) -> (ok: bool, failure: Failure_Context) {
	if !multibuffer_reservation_is_valid(reservation) {
		return false, Failure_Context{code = .Invalid_State}
	}
	state := (^Multibuffer_Reservation_State)(reservation.state)
	for &record in state.reservations {
		reserved := (^Reservation_State)(record.state)
		reserved.node.link = nil
	}
	multibuffer_reserved_records_abort(state.reservations)
	delete(state.link.participants, state.link.allocator)
	free(state.link, state.link.allocator)
	allocator := state.allocator
	delete(state.reservations, allocator)
	reservation.state = nil
	free(state, allocator)
	return true, {}
}

/*
multibuffer_navigation_prepare validates and reserves one complete linked traversal.
No participant moves until the caller publishes every prepared text transition.
*/
multibuffer_navigation_prepare :: proc(
	stores: []^Store,
	request: Multibuffer_Navigation_Request,
) -> (plan: Multibuffer_Navigation_Plan, ok: bool, failure: Failure_Context) {
	if len(stores) == 0 ||
	   (request.kind != .Undo && request.kind != .Redo && request.kind != .Select_Branch) {
		return {}, false, Failure_Context{code = .Invalid_State}
	}
	first, first_failure := store_live_state(stores[0])
	if first_failure.code != .None {
		return {}, false, first_failure
	}
	link := multibuffer_navigation_link(first, request)
	if link == nil {
		code := Failure_Code.Divergent_Participant
		if request.kind == .Undo && first.active == first.root {
			code = .At_Retained_Root
		} else if request.kind == .Redo && first.active.preferred_child == nil {
			code = .No_Redo_Child
		}
		return {}, false, store_failure(first, code)
	}
	if len(stores) != len(link.participants) {
		return {}, false, store_failure(first, .Incomplete_Participant_Set)
	}
	for participant in link.participants {
		if !multibuffer_store_set_contains(stores, participant.store) {
			return {}, false, store_failure(first, .Incomplete_Participant_Set)
		}
	}

	plans, plan_error := make([]Navigation_Plan, len(link.participants), first.temporary_allocator)
	if plan_error != nil {
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	buffers, buffer_error := make(
		[]Multibuffer_Navigation_Buffer,
		len(link.participants),
		first.temporary_allocator,
	)
	if buffer_error != nil {
		delete(plans, first.temporary_allocator)
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	for participant, index in link.participants {
		state := participant.store
		if state.pending_reservation || !multibuffer_navigation_participant_matches(state, participant, request.kind) {
			multibuffer_navigation_plans_abort(plans[:index])
			delete(buffers, first.temporary_allocator)
			delete(plans, first.temporary_allocator)
			return {}, false, store_failure(state, .Divergent_Participant)
		}
		target := Node_ID{}
		if request.kind == .Select_Branch {
			target = participant.node.id
		}
		store_handle := Store{state = state}
		participant_plan, preliminary, prepared, prepare_failure := navigation_prepare(
			&store_handle,
			Navigation_Request {
				kind = request.kind,
				buffer_id = state.buffer_id,
				current_revision = state.current_revision,
				active_node = state.active.id,
				target_node = target,
				policy_generation = state.policy_generation,
				analysis_operations = state.policy.inspection_nodes,
			},
		)
		if !prepared || preliminary.outcome != .Applied {
			multibuffer_navigation_plans_abort(plans[:index])
			delete(buffers, first.temporary_allocator)
			delete(plans, first.temporary_allocator)
			if prepare_failure.code == .None {
				prepare_failure = store_failure(state, .Divergent_Participant)
			}
			return {}, false, prepare_failure
		}
		plans[index] = participant_plan
		buffers[index] = Multibuffer_Navigation_Buffer {
			buffer_id = state.buffer_id,
			edits = plans[index].edits,
		}
	}
	navigation_state, state_error := new(Multibuffer_Navigation_State, first.temporary_allocator)
	if state_error != nil {
		multibuffer_navigation_plans_abort(plans)
		delete(buffers, first.temporary_allocator)
		delete(plans, first.temporary_allocator)
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	navigation_state.plans = plans
	navigation_state.buffers = buffers
	navigation_state.allocator = first.temporary_allocator
	return Multibuffer_Navigation_Plan {
		state = navigation_state,
		kind = request.kind,
		link_id = link.id,
		buffers = buffers,
	}, true, {}
}

/* multibuffer_navigation_commit_reserved moves every participant after publication. */
multibuffer_navigation_commit_reserved :: proc(plan: ^Multibuffer_Navigation_Plan) {
	assert(plan != nil && plan.state != nil)
	state := (^Multibuffer_Navigation_State)(plan.state)
	for &participant_plan in state.plans {
		reserved := (^Reservation_State)(participant_plan.reservation.state)
		navigation_commit_reserved(&participant_plan, reserved.expected_revision)
	}
	allocator := state.allocator
	delete(state.buffers, allocator)
	delete(state.plans, allocator)
	plan^ = {}
	free(state, allocator)
}

/* multibuffer_navigation_abort releases every participant plan without topology change. */
multibuffer_navigation_abort :: proc(
	plan: ^Multibuffer_Navigation_Plan,
) -> (ok: bool, failure: Failure_Context) {
	if plan == nil || plan.state == nil {
		return false, Failure_Context{code = .Invalid_State}
	}
	state := (^Multibuffer_Navigation_State)(plan.state)
	multibuffer_navigation_plans_abort(state.plans)
	allocator := state.allocator
	delete(state.buffers, allocator)
	delete(state.plans, allocator)
	plan^ = {}
	free(state, allocator)
	return true, {}
}

/* multibuffer_selective_prepare proves one complete linked compensation or changes nothing. */
multibuffer_selective_prepare :: proc(
	stores: []^Store,
	request: Multibuffer_Selective_Request,
) -> (plan: Multibuffer_Selective_Plan, ok: bool, failure: Failure_Context) {
	if len(stores) == 0 || request.target_link_id == Link_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Identity}
	}
	first, first_failure := store_live_state(stores[0])
	if first_failure.code != .None {
		return {}, false, first_failure
	}
	link := multibuffer_link_find(first, request.target_link_id)
	if link == nil {
		return {}, false, store_failure(first, .Stale_Generation)
	}
	if len(stores) != len(link.participants) {
		return {}, false, store_failure(first, .Incomplete_Participant_Set)
	}
	for participant in link.participants {
		if !multibuffer_store_set_contains(stores, participant.store) {
			return {}, false, store_failure(first, .Incomplete_Participant_Set)
		}
	}
	plans, plan_error := make([]Selective_Plan, len(link.participants), first.temporary_allocator)
	if plan_error != nil {
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	buffers, buffer_error := make(
		[]Multibuffer_Navigation_Buffer,
		len(link.participants),
		first.temporary_allocator,
	)
	if buffer_error != nil {
		delete(plans, first.temporary_allocator)
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	for participant, index in link.participants {
		state := participant.store
		if state.pending_reservation || !node_is_descendant_or_self(state.active, participant.node) {
			multibuffer_selective_plans_release(plans[:index])
			delete(buffers, first.temporary_allocator)
			delete(plans, first.temporary_allocator)
			return {}, false, store_failure(state, .Divergent_Participant)
		}
		plans[index], ok, failure = selective_prepare(
			&Store{state = state},
			Selective_Request {
				buffer_id = state.buffer_id,
				current_revision = state.current_revision,
				active_node = state.active.id,
				target_unit = participant.node.unit_id,
				policy_generation = state.policy_generation,
				analysis_operations = request.analysis_operations,
				cancelled = request.cancelled,
			},
		)
		if !ok {
			multibuffer_selective_plans_release(plans[:index])
			delete(buffers, first.temporary_allocator)
			delete(plans, first.temporary_allocator)
			return {}, false, failure
		}
		buffers[index] = Multibuffer_Navigation_Buffer {
			buffer_id = state.buffer_id,
			edits = plans[index].edits,
		}
	}
	selective_state, state_error := new(Multibuffer_Selective_State, first.temporary_allocator)
	if state_error != nil {
		multibuffer_selective_plans_release(plans)
		delete(buffers, first.temporary_allocator)
		delete(plans, first.temporary_allocator)
		return {}, false, store_failure(first, .Temporary_Memory_Limit)
	}
	selective_state.plans = plans
	selective_state.buffers = buffers
	selective_state.allocator = first.temporary_allocator
	return Multibuffer_Selective_Plan {
		state = selective_state,
		link_id = link.id,
		buffers = buffers,
	}, true, {}
}

/* multibuffer_selective_plan_release releases a complete unpublished compensation proof. */
multibuffer_selective_plan_release :: proc(plan: ^Multibuffer_Selective_Plan) {
	if plan == nil || plan.state == nil {
		return
	}
	state := (^Multibuffer_Selective_State)(plan.state)
	multibuffer_selective_plans_release(state.plans)
	allocator := state.allocator
	delete(state.buffers, allocator)
	delete(state.plans, allocator)
	plan^ = {}
	free(state, allocator)
}

/* link_inspect copies one complete link into caller-owned participant storage. */
link_inspect :: proc(
	store: ^Store,
	node_id: Node_ID,
	destination: []Link_Participant,
) -> (projection: Link_Projection, ok: bool, failure: Failure_Context) {
	state, state_failure := store_live_state(store)
	if state_failure.code != .None {
		return {}, false, state_failure
	}
	node := store_node_find(state, node_id)
	if node == nil || node.link == nil {
		return {}, false, store_failure(state, .Invalid_Identity)
	}
	link := node.link
	if len(destination) < len(link.participants) {
		return {}, false, store_limit_failure(state, .Inspection_Limit, u64(len(destination)), u64(len(link.participants)))
	}
	for participant, index in link.participants {
		destination[index] = Link_Participant {
			store_id = participant.store.store_id,
			history_id = participant.store.history_id,
			buffer_id = participant.store.buffer_id,
			node_id = participant.node.id,
			base_revision = participant.base_revision,
			result_revision = participant.result_revision,
		}
	}
	return Link_Projection {
		id = link.id,
		source_transaction_id = link.source_transaction_id,
		source_undo_unit_id = link.source_undo_unit_id,
		participants = destination[:len(link.participants)],
	}, true, {}
}

/* multibuffer_stores_close validates complete links, detaches them, and closes every store. */
multibuffer_stores_close :: proc(stores: []^Store) -> (ok: bool, failure: Failure_Context) {
	if len(stores) == 0 {
		return false, Failure_Context{code = .Incomplete_Participant_Set}
	}
	first, first_failure := store_live_state(stores[0])
	if first_failure.code != .None {
		return false, first_failure
	}
	states, state_error := make([]^Store_State, len(stores), first.temporary_allocator)
	if state_error != nil {
		return false, store_failure(first, .Temporary_Memory_Limit)
	}
	defer delete(states, first.temporary_allocator)
	for store, index in stores {
		state, state_failure := store_live_state(store)
		if state_failure.code != .None {
			return false, state_failure
		}
		if state.pending_reservation {
			return false, store_failure(state, .Invalid_State)
		}
		states[index] = state
	}
	slice.sort_by(states, multibuffer_store_state_less)
	for index in 1 ..< len(states) {
		if states[index - 1].buffer_id == states[index].buffer_id {
			return false, store_failure(states[index], .Incomplete_Participant_Set)
		}
	}
	validated_links, links_error := make(map[^Link_State]bool, len(stores), first.temporary_allocator)
	if links_error != nil {
		return false, store_failure(first, .Temporary_Memory_Limit)
	}
	defer delete(validated_links)
	for state in states {
		for node := state.creation_head; node != nil; node = node.creation_next {
			if node.link == nil || validated_links[node.link] {
				continue
			}
			if len(node.link.participants) != len(states) {
				return false, store_failure(state, .Incomplete_Participant_Set)
			}
			for participant, index in node.link.participants {
				if participant.store != states[index] {
					return false, store_failure(state, .Incomplete_Participant_Set)
				}
			}
			validated_links[node.link] = true
		}
	}
	for store in stores {
		state := (^Store_State)(store.state)
		for node := state.creation_head; node != nil; node = node.creation_next {
			node_link_release(node)
		}
	}
	for store in stores {
		closed, close_failure := store_close(store)
		assert(closed && close_failure.code == .None)
	}
	return true, {}
}

/*
multibuffer_prune removes eligible linked leaf nodes only as one complete participant set.
The operation returns zero without mutation when no linked unit is outside every recent window.
*/
multibuffer_prune :: proc(
	stores: []^Store,
	operation_limit: u64,
) -> (pruned_participants: u64, ok: bool, failure: Failure_Context) {
	if len(stores) == 0 {
		return 0, false, Failure_Context{code = .Incomplete_Participant_Set}
	}
	first, first_failure := store_live_state(stores[0])
	if first_failure.code != .None {
		return 0, false, first_failure
	}
	for node := first.creation_head; node != nil; node = node.creation_next {
		link := node.link
		if link == nil || u64(len(link.participants)) > operation_limit {
			continue
		}
		eligible := true
		for participant in link.participants {
			state := participant.store
			if !multibuffer_store_set_contains(stores, state) {
				return 0, false, store_failure(first, .Incomplete_Participant_Set)
			}
			protected_order := u64(0)
			if state.next_creation_order > state.policy.guaranteed_recent_units {
				protected_order = state.next_creation_order - state.policy.guaranteed_recent_units
			}
			if state.pending_reservation || participant.node == state.root ||
			   participant.node == state.active || participant.node.child_count != 0 ||
			   participant.node.link != link || participant.node.creation_order >= protected_order ||
			   u64(len(link.participants)) > state.policy.pruning_operations {
				eligible = false
				break
			}
		}
		if !eligible {
			continue
		}
		for participant in link.participants {
			node_detach_leaf(participant.node)
			creation_detach(participant.store, participant.node)
		}
		for participant in link.participants {
			participant.node.link = nil
		}
		for participant in link.participants {
			participant.store.usage.pruning_operations += 1
			node_release_accounted(participant.store, participant.node)
		}
		participant_count := u64(len(link.participants))
		link.owner.usage.retained_bytes -= link.retained_bytes
		link.owner.usage.retained_links -= 1
		delete(link.participants, link.allocator)
		free(link, link.allocator)
		return participant_count, true, {}
	}
	return 0, true, {}
}

@(private)
multibuffer_record_seed_less :: proc(left, right: Multibuffer_Record_Seed) -> bool {
	return u64(left.state.buffer_id) < u64(right.state.buffer_id)
}

@(private)
multibuffer_store_state_less :: proc(left, right: ^Store_State) -> bool {
	return u64(left.buffer_id) < u64(right.buffer_id)
}

@(private)
multibuffer_reserved_records_abort :: proc(reservations: []Reservation) {
	for &reservation in reservations {
		if reservation_is_valid(&reservation) {
			reserved := (^Reservation_State)(reservation.state)
			reserved.node.link = nil
			aborted, failure := reservation_abort(&reservation)
			assert(aborted && failure.code == .None)
		}
	}
}

@(private)
multibuffer_store_set_contains :: proc(stores: []^Store, target: ^Store_State) -> bool {
	for store in stores {
		if store != nil && store.state == target {
			return true
		}
	}
	return false
}

@(private)
node_link_release :: proc(node: ^Node) {
	if node == nil || node.link == nil {
		return
	}
	link := node.link
	node.link = nil
	assert(link.live_nodes > 0)
	link.live_nodes -= 1
	if link.live_nodes != 0 {
		return
	}
	link.owner.usage.retained_bytes -= link.retained_bytes
	link.owner.usage.retained_links -= 1
	delete(link.participants, link.allocator)
	free(link, link.allocator)
}

@(private)
multibuffer_navigation_link :: proc(
	state: ^Store_State,
	request: Multibuffer_Navigation_Request,
) -> ^Link_State {
	switch request.kind {
	case .Undo:
		return state.active.link
	case .Redo:
		if state.active.preferred_child != nil {
			return state.active.preferred_child.link
		}
	case .Select_Branch:
		return multibuffer_link_find(state, request.target_link_id)
	case .Invalid, .Selective_Undo:
	}
	return nil
}

@(private)
multibuffer_link_find :: proc(state: ^Store_State, id: Link_ID) -> ^Link_State {
	if id == Link_ID(0) {
		return nil
	}
	for node := state.creation_head; node != nil; node = node.creation_next {
		if node.link != nil && node.link.id == id {
			return node.link
		}
	}
	return nil
}

@(private)
multibuffer_navigation_participant_matches :: proc(
	state: ^Store_State,
	participant: Link_Participant_State,
	kind: Navigation_Kind,
) -> bool {
	switch kind {
	case .Undo:
		return state.active == participant.node
	case .Redo:
		return state.active.preferred_child == participant.node
	case .Select_Branch:
		return node_is_descendant_or_self(participant.node, state.root)
	case .Invalid, .Selective_Undo:
		return false
	}
	return false
}

@(private)
multibuffer_navigation_plans_abort :: proc(plans: []Navigation_Plan) {
	for &plan in plans {
		if reservation_is_valid(&plan.reservation) {
			aborted, failure := navigation_abort(&plan)
			assert(aborted && failure.code == .None)
		}
	}
}

@(private)
multibuffer_selective_plans_release :: proc(plans: []Selective_Plan) {
	for &plan in plans {
		selective_plan_release(&plan)
	}
}

@(private)
store_node_find :: proc(state: ^Store_State, id: Node_ID) -> ^Node {
	for node := state.creation_head; node != nil; node = node.creation_next {
		if node.id == id {
			return node
		}
	}
	return nil
}
