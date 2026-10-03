// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

import "../editor"
import "../editor_session"
import "../view"

/* display_policy_is_valid checks one complete copied strategy. */
display_policy_is_valid :: proc(policy: Display_Policy) -> bool {
	if policy.action_count == 0 || policy.action_count > MAX_DISPLAY_POLICY_ACTIONS ||
	   policy.split_height_threshold <= 0 || policy.split_width_threshold <= 0 {
		return false
	}
	seen: [6]bool
	actions := policy.actions
	for action in actions[:policy.action_count] {
		index := int(action.kind)
		if action.kind == .Invalid || action.kind > .Reuse_Most_Recent || seen[index] {
			return false
		}
		seen[index] = true
	}
	for action in actions[policy.action_count:] {
		if action != (Display_Action{}) {
			return false
		}
	}
	return true
}

/* registry_display_policy_snapshot copies one exact configured generation. */
registry_display_policy_snapshot :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
) -> (snapshot: Display_Policy_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Inspect_Display_Policy)
	if resolved.code != .None {
		return {}, false, resolved
	}
	return Display_Policy_Snapshot {
		layout = current_layout_handle(data),
		generation = data.display_policy_generation,
		policy = data.display_policy,
	}, true, {}
}

/* registry_display_policy_replace atomically activates one complete copied strategy. */
registry_display_policy_replace :: proc(
	registry: ^Registry,
	request: Display_Policy_Replacement_Request,
) -> (snapshot: Display_Policy_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, request.layout, .Configure_Display_Policy)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if request.expected_generation == Display_Policy_Generation(0) ||
	   request.expected_generation != data.display_policy_generation {
		failure = data_failure(data, .Configure_Display_Policy, .Stale_Display_Policy)
		failure.display_policy_generation = data.display_policy_generation
		failure.actual = u64(request.expected_generation)
		return {}, false, failure
	}
	if !display_policy_is_valid(request.policy) {
		failure = data_failure(data, .Configure_Display_Policy, .Invalid_Display_Policy)
		failure.maximum = MAX_DISPLAY_POLICY_ACTIONS
		failure.actual = u64(request.policy.action_count)
		return {}, false, failure
	}
	if data.display_policy_generation == Display_Policy_Generation(max(u64)) {
		return {}, false, data_failure(data, .Configure_Display_Policy, .Generation_Limit)
	}
	data.display_policy = request.policy
	data.display_policy_generation = Display_Policy_Generation(u64(data.display_policy_generation) + 1)
	return Display_Policy_Snapshot {
		layout = current_layout_handle(data),
		generation = data.display_policy_generation,
		policy = data.display_policy,
	}, true, {}
}

/* registry_display_request issues one current checked other-pane intent. */
registry_display_request :: proc(
	registry: ^Registry,
	expected: Layout_Handle,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) -> (request: Display_Request, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, expected, .Request_Display)
	if resolved.code != .None {
		return {}, false, resolved
	}
	buffer_id, live := display_request_entry_buffer(data, session, entry)
	if !live {
		return {}, false, data_failure(data, .Request_Display, .Invalid_Display_Request)
	}
	if data.next_display_request_id == Display_Request_ID(max(u64)) {
		return {}, false, data_failure(data, .Request_Display, .Generation_Limit)
	}
	request = Display_Request {
		request_id = data.next_display_request_id,
		layout = current_layout_handle(data),
		entry = entry,
		buffer_id = buffer_id,
		active_pane = pane_handle(data, data.active),
		other_pane = true,
	}
	data.next_display_request_id = Display_Request_ID(u64(data.next_display_request_id) + 1)
	return request, true, {}
}

/* registry_display_policy_factory_proposal copies the current factory/configured ordering. */
registry_display_policy_factory_proposal :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	request: Display_Request,
) -> (proposal: Display_Policy_Proposal, ok: bool, failure: Failure_Context) {
	data, request_failure := display_request_validate(registry, session, request, .Propose_Display)
	if request_failure.code != .None {
		return {}, false, request_failure
	}
	proposal = Display_Policy_Proposal {
		request = request,
		policy_generation = data.display_policy_generation,
		eligibility = {
			exclude_active = true,
			exclude_dedicated = true,
			require_live_buffer = true,
			require_current_layout = true,
			automatic_reuse_only = true,
		},
		action_count = data.display_policy.action_count,
		actions = data.display_policy.actions,
		split_height_threshold = data.display_policy.split_height_threshold,
		split_width_threshold = data.display_policy.split_width_threshold,
	}
	return proposal, true, {}
}

/* registry_display_policy_proposal_validate rechecks a copied factory or Racket proposal. */
registry_display_policy_proposal_validate :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	proposal: Display_Policy_Proposal,
) -> (ok: bool, failure: Failure_Context) {
	data, request_failure := display_request_validate(registry, session, proposal.request, .Propose_Display)
	if request_failure.code != .None {
		return false, request_failure
	}
	if proposal.policy_generation == Display_Policy_Generation(0) ||
	   proposal.policy_generation != data.display_policy_generation {
		failure = data_failure(data, .Propose_Display, .Stale_Display_Policy)
		failure.display_request_id = proposal.request.request_id
		failure.display_policy_generation = data.display_policy_generation
		failure.actual = u64(proposal.policy_generation)
		return false, failure
	}
	if proposal.eligibility != (Display_Eligibility {
		exclude_active = true,
		exclude_dedicated = true,
		require_live_buffer = true,
		require_current_layout = true,
		automatic_reuse_only = true,
	}) {
		return false, data_failure(data, .Propose_Display, .Invalid_Display_Policy)
	}
	policy := Display_Policy {
		action_count = proposal.action_count,
		actions = proposal.actions,
		split_height_threshold = proposal.split_height_threshold,
		split_width_threshold = proposal.split_width_threshold,
	}
	if !display_policy_is_valid(policy) {
		failure = data_failure(data, .Propose_Display, .Invalid_Display_Action)
		failure.maximum = MAX_DISPLAY_POLICY_ACTIONS
		failure.actual = u64(proposal.action_count)
		return false, failure
	}
	return true, {}
}

@(private)
display_request_validate :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	request: Display_Request,
	operation: Operation,
) -> (data: ^Registry_Data, failure: Failure_Context) {
	resolved_data, resolved := resolve_layout(registry, request.layout, operation)
	if resolved.code != .None {
		if resolved.code == .Stale_Layout {
			resolved.code = .Stale_Display_Request
		}
		resolved.display_request_id = request.request_id
		return nil, resolved
	}
	if request.request_id == Display_Request_ID(0) || !request.other_pane ||
	   request.active_pane != pane_handle(resolved_data, resolved_data.active) {
		failure = data_failure(resolved_data, operation, .Invalid_Display_Request)
		failure.display_request_id = request.request_id
		return nil, failure
	}
	buffer_id, live := display_request_entry_buffer(resolved_data, session, request.entry)
	if !live || buffer_id != request.buffer_id {
		failure = data_failure(resolved_data, operation, .Stale_Display_Request)
		failure.display_request_id = request.request_id
		return nil, failure
	}
	return resolved_data, {}
}

@(private)
display_request_entry_buffer :: proc(
	data: ^Registry_Data,
	session: ^editor_session.Session,
	entry: editor_session.Entry_Handle,
) -> (editor.Buffer_ID, bool) {
	if data == nil || session == nil || !editor_session.entry_handle_is_valid(entry) ||
	   !entry_session_matches(data, entry) {
		return {}, false
	}
	access, accessed, _ := editor_session.session_entry_access(session, entry)
	if !accessed {
		return {}, false
	}
	borrow, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed || borrow.view_registry != data.view_registry {
		return {}, false
	}
	stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
	if !stats_ok {
		return {}, false
	}
	return stats.buffer_id, true
}

/* registry_display_buffer selects and publishes one non-active destination without focusing it. */
registry_display_buffer :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	proposal: Display_Policy_Proposal,
) -> (result: Display_Result, ok: bool, failure: Failure_Context) {
	valid, validation_failure := registry_display_policy_proposal_validate(registry, session, proposal)
	if !valid {
		return {}, false, validation_failure
	}
	data := registry_data(registry)
	assert(data != nil)
	actions := proposal.actions
	for action in actions[:proposal.action_count] {
		switch action.kind {
		case .Invalid:
			return {}, false, data_failure(data, .Display_Buffer, .Invalid_Display_Action)
		case .Reuse_Same_Buffer:
			pane, found := display_existing_pane(data, proposal.request.buffer_id, true, false)
			if found {
				return display_reuse_pane(registry, session, proposal, pane, action.kind)
			}
		case .Split_Below:
			active := resolve_node(data, data.active)
			assert(active != nil)
			if active.geometry.outer.height >= proposal.split_height_threshold &&
			   display_split_shape_admissible(data, data.active, .Above_Below) {
				return display_split_buffer(registry, session, proposal, .Above_Below, action.kind)
			}
		case .Split_Right:
			active := resolve_node(data, data.active)
			assert(active != nil)
			if active.geometry.outer.width >= proposal.split_width_threshold &&
			   display_split_shape_admissible(data, data.active, .Left_Right) {
				return display_split_buffer(registry, session, proposal, .Left_Right, action.kind)
			}
		case .Reuse_Least_Recent:
			pane, found := display_existing_pane(data, {}, false, true)
			if found {
				return display_reuse_pane(registry, session, proposal, pane, action.kind)
			}
		case .Reuse_Most_Recent:
			pane, found := display_existing_pane(data, {}, false, false)
			if found {
				return display_reuse_pane(registry, session, proposal, pane, action.kind)
			}
		}
	}
	failure = data_failure(data, .Display_Buffer, .No_Other_Pane)
	failure.display_request_id = proposal.request.request_id
	return {}, false, failure
}

@(private)
display_existing_pane :: proc(
	data: ^Registry_Data,
	buffer_id: editor.Buffer_ID,
	require_buffer: bool,
	least_recent: bool,
) -> (Pane_Handle, bool) {
	if least_recent {
		for index := int(data.mru_count) - 1; index >= 0; index -= 1 {
			ref := data.mru[index]
			if ref == data.active {
				continue
			}
			slot := resolve_node(data, ref)
			if slot != nil && slot.kind == .Pane && slot.dedication == .None &&
			   (!require_buffer || slot.buffer_id == buffer_id) {
				return pane_handle(data, ref), true
			}
		}
		return {}, false
	}
	for ref in data.mru[:data.mru_count] {
		if ref == data.active {
			continue
		}
		slot := resolve_node(data, ref)
		if slot != nil && slot.kind == .Pane && slot.dedication == .None &&
		   (!require_buffer || slot.buffer_id == buffer_id) {
			return pane_handle(data, ref), true
		}
	}
	return {}, false
}

@(private)
display_reuse_pane :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	proposal: Display_Policy_Proposal,
	pane: Pane_Handle,
	action: Display_Action_Kind,
) -> (Display_Result, bool, Failure_Context) {
	replaced, ok, failure := registry_replace_pane_buffer(
		registry,
		pane,
		session,
		proposal.request.entry,
	)
	if !ok {
		failure.operation = .Display_Buffer
		failure.display_request_id = proposal.request.request_id
		return {}, false, failure
	}
	return Display_Result {
		layout = replaced.layout,
		pane = replaced.pane,
		entry = replaced.entry,
		view = replaced.view,
		action = action,
		changed = replaced.changed,
	}, true, {}
}

@(private)
display_split_shape_admissible :: proc(
	data: ^Registry_Data,
	source_ref: Node_Ref,
	arrangement: Arrangement,
) -> bool {
	if data == nil || data.geometry_state != .Operating || data.pane_count >= data.policy.live_panes ||
	   data.node_count > data.policy.snapshot_nodes - 2 {
		return false
	}
	source := resolve_node(data, source_ref)
	if source == nil || source.kind != .Pane || source.depth >= data.policy.partition_depth {
		return false
	}
	if arrangement == .Above_Below {
		minimum := (data.policy.operating_content_rows + PANE_STATUS_ROWS) * 2
		return source.geometry.outer.height >= minimum
	}
	if arrangement == .Left_Right {
		minimum := data.policy.operating_columns * 2 + 1
		return source.geometry.outer.width >= minimum
	}
	return false
}

@(private)
display_split_buffer :: proc(
	registry: ^Registry,
	session: ^editor_session.Session,
	proposal: Display_Policy_Proposal,
	arrangement: Arrangement,
	action: Display_Action_Kind,
) -> (result: Display_Result, ok: bool, failure: Failure_Context) {
	data, request_failure := display_request_validate(registry, session, proposal.request, .Display_Buffer)
	if request_failure.code != .None {
		return {}, false, request_failure
	}
	source_slot, source_ref, source_failure := resolve_pane(data, proposal.request.active_pane, .Display_Buffer)
	if source_failure.code != .None || source_ref != data.active ||
	   !display_split_shape_admissible(data, source_ref, arrangement) {
		return {}, false, data_failure(data, .Display_Buffer, .No_Other_Pane)
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Display_Buffer)
	}
	if data.generation == Layout_Generation(max(u64)) ||
	   data.next_node_id > Node_ID(max(u64) - 2) || data.next_pane_id == Pane_ID(max(u64)) {
		return {}, false, data_failure(data, .Display_Buffer, .Generation_Limit)
	}
	incoming_access, incoming_ok, incoming_failure := editor_session.session_entry_access(
		session,
		proposal.request.entry,
	)
	if !incoming_ok {
		return {}, false, layout_session_failure(data, .Display_Buffer, incoming_failure)
	}
	incoming, borrowed, borrow_failure := editor_session.entry_access_borrow(incoming_access)
	if !borrowed || incoming.view_registry != data.view_registry {
		if !borrowed {
			return {}, false, layout_session_failure(data, .Display_Buffer, borrow_failure)
		}
		return {}, false, data_failure(data, .Display_Buffer, .Invalid_Display_Request)
	}
	incoming_stats, stats_ok, stats_failure := editor.buffer_stats(incoming.buffer)
	if !stats_ok || incoming_stats.buffer_id != proposal.request.buffer_id {
		failure = data_failure(data, .Display_Buffer, .Invalid_Display_Request)
		if !stats_ok {
			failure.session_failure = editor_session.Failure_Context {
				code = .Editor_Failure,
				operation = .Inspect,
				entry = proposal.request.entry,
				editor_failure = stats_failure,
			}
		}
		return {}, false, failure
	}
	proposed, prepared := prepared_state_copy(data, .Display_Buffer)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	partition_ref, partition_ok := allocate_node(proposed)
	new_pane_ref, new_pane_ok := allocate_node(proposed)
	if !partition_ok || !new_pane_ok {
		return {}, false, data_failure(data, .Display_Buffer, .Pane_Limit)
	}
	partition_generation := proposed.nodes[int(partition_ref.slot)].generation
	new_pane_generation := proposed.nodes[int(new_pane_ref.slot)].generation
	previous_parent := source_slot.parent
	previous_depth := source_slot.depth
	proposed.nodes[int(partition_ref.slot)] = Node_Slot {
		live = true,
		kind = .Partition,
		node_id = proposed.next_node_id,
		generation = partition_generation,
		parent = previous_parent,
		depth = previous_depth,
		arrangement = arrangement,
		first = source_ref,
		second = new_pane_ref,
		first_weight = 1,
		second_weight = 1,
	}
	proposed.next_node_id = Node_ID(u64(proposed.next_node_id) + 1)
	proposed.nodes[int(new_pane_ref.slot)] = Node_Slot {
		live = true,
		kind = .Pane,
		node_id = proposed.next_node_id,
		generation = new_pane_generation,
		parent = partition_ref,
		depth = previous_depth + 1,
		pane_id = proposed.next_pane_id,
		view = source_slot.view,
		buffer_id = source_slot.buffer_id,
		entry = source_slot.entry,
		history = source_slot.history,
		history_count = source_slot.history_count,
		history_generation = source_slot.history_generation,
	}
	proposed.next_node_id = Node_ID(u64(proposed.next_node_id) + 1)
	proposed.next_pane_id = Pane_ID(u64(proposed.next_pane_id) + 1)
	proposed.nodes[int(source_ref.slot)].parent = partition_ref
	proposed.nodes[int(source_ref.slot)].depth = previous_depth + 1
	if source_ref == proposed.root {
		proposed.root = partition_ref
	} else if !replace_child(proposed, previous_parent, source_ref, partition_ref) {
		return {}, false, data_failure(data, .Display_Buffer, .Invalid_Parent)
	}
	proposed.mru[int(proposed.mru_count)] = new_pane_ref
	proposed.mru_count += 1
	proposed.node_count += 2
	proposed.pane_count += 1
	proposed.partition_count += 1
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	materialized, materialize_failure := geometry_materialize_data(
		proposed,
		proposed.geometry_request,
		.Operating,
		.Display_Buffer,
		false,
	)
	if !materialized {
		return {}, false, materialize_failure
	}
	created_view, created_ok, created_failure := view.clone_additional(data.view_registry, source_slot.view)
	if !created_ok {
		return {}, false, layout_view_failure(data, .Display_Buffer, created_failure)
	}
	published_view := false
	defer {
		if !published_view {
			closed, _ := view.close(data.view_registry, &created_view)
			assert(closed)
		}
	}
	if source_slot.buffer_id != incoming_stats.buffer_id {
		rebound, rebound_failure := view.rebind_additional(
			data.view_registry,
			created_view,
			incoming.primary_view,
		)
		if !rebound {
			return {}, false, layout_view_failure(data, .Display_Buffer, rebound_failure)
		}
	}
	incoming_snapshot, incoming_snapshot_ok, incoming_snapshot_failure := view.snapshot(
		data.view_registry,
		created_view,
	)
	if !incoming_snapshot_ok {
		return {}, false, layout_view_failure(data, .Display_Buffer, incoming_snapshot_failure)
	}
	new_slot := resolve_node(proposed, new_pane_ref)
	assert(new_slot != nil)
	state := pane_buffer_state_from_view(proposal.request.entry, incoming_snapshot)
	if restored, has_restored := pane_history_state_for_buffer(new_slot, incoming_stats.buffer_id); has_restored {
		state, incoming_snapshot_ok = pane_buffer_state_normalize(
			restored,
			proposal.request.entry,
			incoming.buffer,
		)
		if !incoming_snapshot_ok {
			return {}, false, data_failure(data, .Display_Buffer, .Invalid_Buffer_State)
		}
		restored_ok, restore_failure := view.restore_presentation(
			data.view_registry,
			created_view,
			state.stored_point.byte_offset,
			state.viewport_start.byte_offset,
			state.horizontal_display_column,
			state.desired_display_column,
		)
		if !restored_ok {
			return {}, false, layout_view_failure(data, .Display_Buffer, restore_failure)
		}
	}
	new_slot.entry = proposal.request.entry
	new_slot.buffer_id = incoming_stats.buffer_id
	new_slot.view = created_view
	pane_history_touch(proposed, new_slot, state)
	buffer_list_touch(proposed, proposal.request.entry, incoming_stats.buffer_id)
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Display_Buffer, .Invalid_Topology)
	}
	result = Display_Result {
		layout = current_layout_handle(proposed),
		pane = pane_handle(proposed, new_pane_ref),
		entry = proposal.request.entry,
		view = created_view,
		action = action,
		created = true,
		changed = true,
	}
	registry_publish(registry, proposed)
	published_view = true
	return result, true, {}
}
