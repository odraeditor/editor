// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

import "../editor"
import "../gutter"
import "../indentation"
import "../search"
import "base:runtime"

/* registry_init initializes one zero-value editor-view registry. */
registry_init :: proc(
	registry: ^Registry,
	registry_id: Registry_ID,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if registry.state != nil || registry.closed || registry_id == Registry_ID(0) ||
	   allocator.procedure == nil {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	data, allocation_error := new(Registry_Data, allocator)
	if allocation_error != nil {
		return false, Failure_Context {
			code = .Persistent_Memory_Limit,
			registry_id = registry_id,
			limit = u64(size_of(Registry_Data)),
			actual = u64(size_of(Registry_Data)),
		}
	}
	data.state = .Ready
	data.registry_id = registry_id
	data.next_view_id = View_ID(1)
	data.allocator = allocator
	data.storage_bytes = u64(size_of(Registry_Data))
	registry.state = data
	return true, {}
}

/* registry_close closes an empty registry and makes its lifecycle terminal. */
registry_close :: proc(registry: ^Registry) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return false, registry_failure(registry, .Invalid_Registry)
	}
	if data.live_count != 0 {
		failure = registry_failure(registry, .Retained_Views)
		failure.limit = 0
		failure.actual = u64(data.live_count)
		return false, failure
	}
	data.state = .Closed
	allocator := data.allocator
	free(data, allocator)
	registry.state = nil
	registry.closed = true
	return true, {}
}

/* registry_stats returns current occupancy and exact owned registry storage. */
registry_stats :: proc(
	registry: ^Registry,
) -> (stats: Registry_Stats, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	return Registry_Stats {
		live_count = data.live_count,
		retained_count = data.retained_count,
		additional_count = data.additional_count,
		capacity = MAX_VIEWS,
		storage_bytes = data.storage_bytes,
	}, true, {}
}

/*
create establishes one retained primary presentation record for a buffer.
Failure releases partial resources and leaves the registry and buffer unchanged.
*/
create :: proc(
	registry: ^Registry,
	buffer: ^editor.Buffer,
	config := DEFAULT_CONFIG,
) -> (handle: View_Handle, ok: bool, failure: Failure_Context) {
	return create_presentation(registry, buffer, config, .Retained_Primary, nil)
}

/*
clone_additional copies point, viewport, layout, and gutter presentation into a
pane-owned record. Derived hidden ranges start empty and remain independent.
*/
clone_additional :: proc(
	registry: ^Registry,
	source: View_Handle,
) -> (handle: View_Handle, ok: bool, failure: Failure_Context) {
	source_slot, source_failure := resolve(registry, source)
	if source_failure.code != .None {
		return {}, false, source_failure
	}
	return create_presentation(
		registry,
		source_slot.buffer,
		Config {
			indentation_policy = source_slot.indentation_policy.policy,
			display_profile_id = source_slot.display_profile_id,
			gutter_policy = source_slot.gutter.policy,
		},
		.Additional,
		source_slot,
	)
}

/* rebind_additional moves one pane-owned presentation to another live buffer. */
/* rebind_additional adopts source layout and clears prior derived visibility. */
rebind_additional :: proc(
	registry: ^Registry,
	handle: View_Handle,
	source: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	target_slot, target_failure := resolve(registry, handle)
	if target_failure.code != .None {
		return false, target_failure
	}
	source_slot, source_failure := resolve(registry, source)
	if source_failure.code != .None {
		return false, source_failure
	}
	if target_slot.presentation_ownership != .Additional {
		return false, view_failure(registry, handle, .Additional_Required)
	}
	if handle == source {
		return true, {}
	}
	if !prepare_mutation(registry, handle, target_slot) {
		return false, mutation_failure(registry, handle, target_slot)
	}
	if target_slot.search_session.active || target_slot.query_replacement_session.active {
		return false, view_failure(registry, handle, .Active_Preparation)
	}
	close_ready, close_failure := validate_close(registry, handle)
	if !close_ready {
		return false, close_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(source_slot.buffer)
	if !stats_ok {
		return false, editor_failure_context(registry, handle, stats_failure)
	}
	anchor_stats, anchors_ok, anchors_failure := editor.buffer_anchor_stats(source_slot.buffer)
	if !anchors_ok {
		return false, editor_failure_context(registry, handle, anchors_failure)
	}
	if anchor_stats.capacity - anchor_stats.live_count < 2 {
		return false, editor_failure_context(
			registry,
			handle,
			editor.Failure_Context {
				code = .Anchor_Limit,
				buffer_id = stats.buffer_id,
				revision = stats.revision,
				limit = u64(anchor_stats.capacity),
				actual = u64(anchor_stats.live_count) + 2,
			},
		)
	}
	point, point_ok, point_failure := editor.buffer_anchor_resolve(
		source_slot.buffer,
		source_slot.stored_point,
	)
	if !point_ok {
		return false, editor_failure_context(registry, source, point_failure)
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_anchor_resolve(
		source_slot.buffer,
		source_slot.viewport_origin,
	)
	if !viewport_ok {
		return false, editor_failure_context(registry, source, viewport_failure)
	}
	new_point, point_created, point_create_failure := editor.buffer_anchor_create(
		source_slot.buffer,
		point,
		.Right,
		.Collapse,
	)
	if !point_created {
		return false, editor_failure_context(registry, handle, point_create_failure)
	}
	new_viewport, viewport_created, viewport_create_failure := editor.buffer_anchor_create(
		source_slot.buffer,
		viewport,
		.Left,
		.Collapse,
	)
	if !viewport_created {
		released, _ := editor.buffer_anchor_release(source_slot.buffer, &new_point)
		assert(released)
		return false, editor_failure_context(registry, handle, viewport_create_failure)
	}
	old_buffer := target_slot.buffer
	old_point := target_slot.stored_point
	old_viewport := target_slot.viewport_origin
	data := registry_data(registry)
	assert(data != nil)
	visibility_state_close(data, target_slot, old_buffer)
	viewport_released, viewport_release_failure := editor.buffer_anchor_release(
		old_buffer,
		&old_viewport,
	)
	if !viewport_released {
		point_released, _ := editor.buffer_anchor_release(source_slot.buffer, &new_point)
		viewport_rolled_back, _ := editor.buffer_anchor_release(source_slot.buffer, &new_viewport)
		assert(point_released && viewport_rolled_back)
		return false, editor_failure_context(registry, handle, viewport_release_failure)
	}
	point_released, point_release_failure := editor.buffer_anchor_release(old_buffer, &old_point)
	if !point_released {
		return false, editor_failure_context(registry, handle, point_release_failure)
	}
	target_slot.buffer = source_slot.buffer
	target_slot.buffer_id = stats.buffer_id
	target_slot.buffer_kind = stats.kind
	target_slot.stored_point = new_point
	target_slot.viewport_origin = new_viewport
	target_slot.desired_display_column = source_slot.desired_display_column
	target_slot.horizontal_display_column = source_slot.horizontal_display_column
	target_slot.indentation_policy = source_slot.indentation_policy
	target_slot.display_profile_id = source_slot.display_profile_id
	target_slot.terminal = terminal_view_state_for_clone(source_slot, stats.kind)
	target_slot.state_generation += 1
	return true, {}
}

@(private)
create_presentation :: proc(
	registry: ^Registry,
	buffer: ^editor.Buffer,
	config: Config,
	ownership: Presentation_Ownership,
	source: ^View_Slot,
) -> (handle: View_Handle, ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	if !config_is_valid(config) {
		return {}, false, registry_failure(registry, .Invalid_Config)
	}
	limit := u16(MAX_RETAINED_VIEWS)
	count := data.retained_count
	if ownership == .Additional {
		limit = u16(MAX_ADDITIONAL_VIEWS)
		count = data.additional_count
	}
	if (ownership != .Retained_Primary && ownership != .Additional) ||
	   count >= limit || data.live_count >= MAX_VIEWS || data.next_view_id == View_ID(0) {
		failure = registry_failure(registry, .Capacity_Limit)
		failure.limit = u64(limit)
		failure.actual = u64(count) + 1
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, {}, stats_failure)
	}
	if ownership == .Retained_Primary {
		for &existing in data.slots {
			if existing.live && existing.presentation_ownership == .Retained_Primary &&
			   existing.buffer_id == stats.buffer_id {
				failure = registry_failure(registry, .Retained_Primary_Exists)
				failure.actual = u64(stats.buffer_id)
				return {}, false, failure
			}
		}
	}
	anchor_stats, anchor_stats_ok, anchor_stats_failure := editor.buffer_anchor_stats(buffer)
	if !anchor_stats_ok {
		return {}, false, editor_failure_context(registry, {}, anchor_stats_failure)
	}
	available_anchors := anchor_stats.capacity - anchor_stats.live_count
	if available_anchors < 2 {
		return {}, false, editor_failure_context(
			registry,
			{},
			editor.Failure_Context {
				code = .Anchor_Limit,
				buffer_id = stats.buffer_id,
				revision = stats.revision,
				limit = u64(anchor_stats.capacity),
				actual = u64(anchor_stats.live_count) + 2,
			},
		)
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(buffer)
	if !selection_ok {
		return {}, false, editor_failure_context(registry, {}, selection_failure)
	}
	point := selection.point_position
	viewport_position, viewport_position_ok, viewport_position_failure := editor.buffer_position(
		buffer,
		editor.Byte_Offset(0),
	)
	if !viewport_position_ok {
		return {}, false, editor_failure_context(registry, {}, viewport_position_failure)
	}
	desired_column: u32
	horizontal_column: u32
	if source != nil {
		resolved_point, resolved_point_ok, resolved_point_failure := editor.buffer_anchor_resolve(
			buffer,
			source.stored_point,
		)
		if !resolved_point_ok {
			return {}, false, editor_failure_context(registry, {}, resolved_point_failure)
		}
		resolved_viewport, resolved_viewport_ok, resolved_viewport_failure := editor.buffer_anchor_resolve(
			buffer,
			source.viewport_origin,
		)
		if !resolved_viewport_ok {
			return {}, false, editor_failure_context(registry, {}, resolved_viewport_failure)
		}
		point = resolved_point
		viewport_position = resolved_viewport
		desired_column = source.desired_display_column
		horizontal_column = source.horizontal_display_column
	}
	stored_point, point_ok, point_failure := editor.buffer_anchor_create(
		buffer,
		point,
		.Right,
		.Collapse,
	)
	if !point_ok {
		return {}, false, editor_failure_context(registry, {}, point_failure)
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_anchor_create(
		buffer,
		viewport_position,
		.Left,
		.Collapse,
	)
	if !viewport_ok {
		point_released, _ := editor.buffer_anchor_release(buffer, &stored_point)
		assert(point_released)
		return {}, false, editor_failure_context(registry, {}, viewport_failure)
	}

	for &slot, slot_index in data.slots {
		if slot.live || slot.generation == max(u32) {
			continue
		}
		slot.generation += 1
		slot.buffer = buffer
		slot.buffer_id = stats.buffer_id
		slot.buffer_kind = stats.kind
		slot.view_id = data.next_view_id
		slot.state_generation = 1
		slot.stored_point = stored_point
		slot.desired_display_column = desired_column
		slot.viewport_origin = viewport
		slot.horizontal_display_column = horizontal_column
		slot.indentation_policy = indentation.DEFAULT_EFFECTIVE_POLICY
		slot.indentation_policy.policy = config.indentation_policy
		slot.display_profile_id = config.display_profile_id
		if source != nil {
			slot.indentation_policy = source.indentation_policy
			slot.gutter = source.gutter
		} else {
			slot.gutter = {
				policy = config.gutter_policy,
				generation = 1,
			}
		}
		slot.presentation_ownership = ownership
		slot.terminal = terminal_view_state_for_clone(source, stats.kind)
		slot.live = true
		data.live_count += 1
		if ownership == .Retained_Primary {
			data.retained_count += 1
		} else {
			data.additional_count += 1
		}
		data.next_view_id = View_ID(u64(data.next_view_id) + 1)
		return View_Handle {
			registry_id = data.registry_id,
			view_id = slot.view_id,
			slot = u16(slot_index),
			generation = slot.generation,
		}, true, {}
	}

	point_released, _ := editor.buffer_anchor_release(buffer, &stored_point)
	viewport_released, _ := editor.buffer_anchor_release(buffer, &viewport)
	assert(point_released)
	assert(viewport_released)
	failure = registry_failure(registry, .Capacity_Limit)
	failure.limit = MAX_VIEWS
	failure.actual = u64(data.live_count) + 1
	return {}, false, failure
}

/* validate_close proves that immediate close can release the complete view state. */
validate_close :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if slot.active_preparation {
		return false, view_failure(registry, handle, .Active_Preparation)
	}
	visibility_valid, visibility_failure := visibility_state_validate(slot)
	if !visibility_valid {
		return false, editor_failure_context(registry, handle, visibility_failure)
	}
	_, snapshot_ok, snapshot_failure := snapshot(registry, handle)
	if !snapshot_ok {
		return false, snapshot_failure
	}
	if !editor.buffer_is_live(slot.buffer) {
		return true, {}
	}
	stored, stored_ok, stored_failure := editor.buffer_anchor_resolve(slot.buffer, slot.stored_point)
	if !stored_ok {
		return false, editor_failure_context(registry, handle, stored_failure)
	}
	stored_ready, stored_ready_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, stored)
	if !stored_ready {
		return false, editor_failure_context(registry, handle, stored_ready_failure)
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_anchor_resolve(slot.buffer, slot.viewport_origin)
	if !viewport_ok {
		return false, editor_failure_context(registry, handle, viewport_failure)
	}
	viewport_ready, viewport_ready_failure :=
		editor.buffer_anchor_move(slot.buffer, slot.viewport_origin, viewport)
	if !viewport_ready {
		return false, editor_failure_context(registry, handle, viewport_ready_failure)
	}
	return true, {}
}

/*
close releases view-owned anchors and invalidates the supplied handle.
It never closes the associated buffer.
*/
close :: proc(
	registry: ^Registry,
	handle: ^View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	assert(registry != nil)
	if handle == nil {
		return false, registry_failure(registry, .Invalid_View)
	}
	slot, slot_failure := resolve(registry, handle^)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if slot.active_preparation {
		return false, view_failure(registry, handle^, .Active_Preparation)
	}
	if editor.buffer_is_live(slot.buffer) {
		data := registry_data(registry)
		assert(data != nil)
		visibility_state_close(data, slot, slot.buffer)
		search_released, search_failure := search_session_release(slot)
		if !search_released {
			return false, search_failure_context(registry, handle^, search_failure)
		}
		query_replacement_released, query_replacement_failure :=
			query_replacement_session_release(slot)
		if !query_replacement_released {
			return false, search_failure_context(
				registry,
				handle^,
				query_replacement_failure,
			)
		}
		viewport_released, viewport_failure := editor.buffer_anchor_release(
			slot.buffer,
			&slot.viewport_origin,
		)
		if !viewport_released {
			return false, editor_failure_context(registry, handle^, viewport_failure)
		}
		point_released, point_failure := editor.buffer_anchor_release(
			slot.buffer,
			&slot.stored_point,
		)
		if !point_released {
			return false, editor_failure_context(registry, handle^, point_failure)
		}
	}

	if !editor.buffer_is_live(slot.buffer) {
		data := registry_data(registry)
		assert(data != nil)
		visibility_state_close(data, slot, slot.buffer)
	}
	generation := slot.generation
	view_id := slot.view_id
	ownership := slot.presentation_ownership
	slot^ = View_Slot{generation = generation}
	data := registry_data(registry)
	assert(data != nil && data.live_count > 0)
	data.live_count -= 1
	if ownership == .Retained_Primary {
		assert(data.retained_count > 0)
		data.retained_count -= 1
	} else {
		assert(data.additional_count > 0)
		data.additional_count -= 1
	}
	handle^ = {}
	return true, Failure_Context {
		registry_id = data.registry_id,
		view_id = view_id,
		view_generation = generation,
	}
}

/* snapshot resolves every live anchor against one checked current buffer revision. */
snapshot :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (value: Snapshot, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return {}, false, editor_failure_context(registry, handle, stats_failure)
	}
	if stats.buffer_id != slot.buffer_id || stats.kind != slot.buffer_kind {
		return {}, false, editor_failure_context(
			registry,
			handle,
			editor.Failure_Context {
				code = .Wrong_Buffer_Kind if stats.buffer_id == slot.buffer_id else .Wrong_Buffer,
				buffer_id = stats.buffer_id,
				revision = stats.revision,
			},
		)
	}
	reconciled, reconcile_failure := visibility_reconcile(registry, handle, slot)
	if !reconciled {
		return {}, false, reconcile_failure
	}
	if slot.search_session.active && slot.search_session.source_revision != stats.revision {
		released, search_failure := search_session_release(slot)
		if !released {
			return {}, false, search_failure_context(registry, handle, search_failure)
		}
		if slot.state_generation == max(u64) {
			return {}, false, generation_failure(registry, handle)
		}
		slot.state_generation += 1
	}
	if slot.query_replacement_session.active &&
	   slot.query_replacement_session.source_revision != stats.revision {
		marked, query_replacement_failure := query_replacement_session_mark_stale(
			slot,
			stats.revision,
			stats.text_bytes,
		)
		if !marked {
			return {}, false, search_failure_context(
				registry,
				handle,
				query_replacement_failure,
			)
		}
		if slot.state_generation == max(u64) {
			return {}, false, generation_failure(registry, handle)
		}
		slot.state_generation += 1
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return {}, false, editor_failure_context(registry, handle, selection_failure)
	}
	stored_point, stored_point_ok, stored_point_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.stored_point,
	)
	if !stored_point_ok {
		return {}, false, editor_failure_context(registry, handle, stored_point_failure)
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.viewport_origin,
	)
	if !viewport_ok {
		return {}, false, editor_failure_context(registry, handle, viewport_failure)
	}
	mark := Mark_Snapshot {
		present = selection.mark.present,
		position = selection.mark.position,
	}
	assert(selection.point_position.revision == stats.revision)
	assert(stored_point.revision == stats.revision)
	assert(viewport.revision == stats.revision)
	assert(!selection.region_active || mark.present)
	return Snapshot {
		view_id = slot.view_id,
		view_generation = slot.generation,
		state_generation = slot.state_generation,
		selection_generation = selection.generation,
		buffer_id = slot.buffer_id,
		buffer_kind = slot.buffer_kind,
		revision = stats.revision,
		point_position = stored_point,
		effective_point_position = selection.point_position,
		mark = mark,
		region_active = selection.region_active,
		selection_shape = selection.shape,
		rectangle_column_policy = selection.rectangle_column_policy,
		overwrite_mode = slot.overwrite_mode,
		desired_display_column = slot.desired_display_column,
		viewport_origin_position = viewport,
		horizontal_display_column = slot.horizontal_display_column,
		indentation_policy = slot.indentation_policy,
		tab_width = slot.indentation_policy.policy.display_tab_width,
		display_profile_id = slot.display_profile_id,
		gutter = slot.gutter,
		presentation_ownership = slot.presentation_ownership,
		visibility_generation = slot.visibility.generation,
		hidden_range_count = u32(len(slot.visibility.ranges)),
		terminal = slot.terminal,
	}, true, {}
}

@(private)
terminal_view_state_for_clone :: proc(
	source: ^View_Slot,
	kind: editor.Buffer_Kind,
) -> Terminal_View_State {
	if kind != .Terminal_Projection {
		return {}
	}
	state := Terminal_View_State {
		attached = true,
		viewport = Terminal_Viewport{follow_tail = true},
	}
	if source != nil && source.buffer_kind == .Terminal_Projection {
		state.viewport = source.terminal.viewport
		state.geometry = source.terminal.geometry
	}
	return state
}

/* toggle_overwrite_mode changes only the selected view's direct text-input policy. */
toggle_overwrite_mode :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (enabled: bool, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, false, mutation_failure(registry, handle, slot)
	}
	slot.overwrite_mode = !slot.overwrite_mode
	slot.state_generation += 1
	return slot.overwrite_mode, true, {}
}

/* transient_state returns copied lifecycle state without exposing retained interaction storage. */
transient_state :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (state: Transient_State, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	return Transient_State {
		active_preparation = slot.active_preparation,
		search = slot.search_session.active,
		query_replacement = slot.query_replacement_session.active,
	}, true, {}
}

@(private)
search_failure_context :: proc(
	registry: ^Registry,
	handle: View_Handle,
	search_failure: search.Failure,
) -> Failure_Context {
	failure := view_failure(registry, handle, .Search_Failure)
	failure.search_failure = search_failure
	return failure
}

/* set_point synchronizes view stored point and buffer effective point. */
set_point :: proc(
	registry: ^Registry,
	handle: View_Handle,
	position: editor.Position,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	moved, move_failure := editor.buffer_selection_set_point(slot.buffer, position)
	if !moved {
		return false, editor_failure_context(registry, handle, move_failure)
	}
	stored, stored_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, position)
	assert(stored && stored_failure.code == .None)
	slot.state_generation += 1
	return true, {}
}

/* move_point updates stored/effective point, desired column, and shared region state. */
move_point :: proc(
	registry: ^Registry,
	handle: View_Handle,
	position: editor.Position,
	desired_display_column: u32,
	region_action := Point_Movement_Region_Action.Deactivate,
) -> (ok: bool, failure: Failure_Context) {
	if region_action != .Preserve && region_action != .Deactivate && region_action != .Activate {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	selection_action := editor.Selection_Region_Action.Preserve
	switch region_action {
	case .Activate:
		selection_action = .Activate
	case .Deactivate:
		selection_action = .Deactivate
	case .Preserve:
	case .Invalid:
		unreachable()
	}
	moved, move_failure := editor.buffer_selection_move(slot.buffer, position, selection_action)
	if !moved {
		return false, editor_failure_context(registry, handle, move_failure)
	}
	stored, stored_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, position)
	assert(stored && stored_failure.code == .None)
	slot.desired_display_column = desired_display_column
	slot.state_generation += 1
	return true, {}
}

/* set_mark changes the buffer-owned mark and optionally activates its region. */
set_mark :: proc(
	registry: ^Registry,
	handle: View_Handle,
	position: editor.Position,
	activate := true,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	marked, mark_failure := editor.buffer_selection_set_mark(slot.buffer, position, activate)
	if !marked {
		return false, editor_failure_context(registry, handle, mark_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* select_range atomically stores mark at start, point at end, and activates the region. */
select_range :: proc(
	registry: ^Registry,
	handle: View_Handle,
	start, end: editor.Position,
	desired_display_column: u32,
	shape := editor.Selection_Shape.Linear,
	column_policy := editor.Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	reserved_mark: editor.Anchor
	reserved: ^editor.Anchor
	if !selection.mark.present {
		created: bool
		create_failure: editor.Failure_Context
		reserved_mark, created, create_failure = editor.buffer_anchor_create(
			slot.buffer,
			start,
			.Left,
			.Collapse,
		)
		if !created {
			return false, editor_failure_context(registry, handle, create_failure)
		}
		reserved = &reserved_mark
	}
	published, publish_failure := editor.buffer_selection_publish_reserved(
		slot.buffer,
		end,
		.Activate,
		.Position,
		start,
		reserved,
		shape,
		column_policy,
	)
	if !published {
		if reserved_mark.buffer_id != editor.Buffer_ID(0) {
			released, _ := editor.buffer_anchor_release(slot.buffer, &reserved_mark)
			assert(released)
		}
		return false, editor_failure_context(registry, handle, publish_failure)
	}
	stored, stored_failure := editor.buffer_anchor_move(slot.buffer, slot.stored_point, end)
	assert(stored && stored_failure.code == .None)
	slot.desired_display_column = desired_display_column
	slot.state_generation += 1
	return true, {}
}

/* set_selection_shape changes one active canonical region's projection shape. */
set_selection_shape :: proc(
	registry: ^Registry,
	handle: View_Handle,
	shape: editor.Selection_Shape,
	column_policy := editor.Rectangle_Column_Policy.Grapheme,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None do return false, slot_failure
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	changed, change_failure := editor.buffer_selection_set_shape(
		slot.buffer, shape, column_policy,
	)
	if !changed do return false, editor_failure_context(registry, handle, change_failure)
	slot.state_generation += 1
	return true, {}
}

/* set_region_active changes buffer activation without moving point or mark. */
set_region_active :: proc(
	registry: ^Registry,
	handle: View_Handle,
	active: bool,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	if active && !selection.mark.present {
		return false, view_failure(registry, handle, .Missing_Mark)
	}
	if selection.region_active == active {
		return true, {}
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	changed, change_failure := editor.buffer_selection_set_region_active(slot.buffer, active)
	if !changed {
		return false, editor_failure_context(registry, handle, change_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* exchange_point_and_mark swaps buffer endpoints and synchronizes this view's point. */
exchange_point_and_mark :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	if !selection.mark.present {
		return false, view_failure(registry, handle, .Missing_Mark)
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	exchanged, exchange_failure := editor.buffer_selection_exchange(slot.buffer)
	if !exchanged {
		return false, editor_failure_context(registry, handle, exchange_failure)
	}
	updated, updated_ok, updated_failure := editor.buffer_selection_snapshot(slot.buffer)
	assert(updated_ok && updated_failure.code == .None)
	stored, stored_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.stored_point,
		updated.point_position,
	)
	assert(stored && stored_failure.code == .None)
	slot.state_generation += 1
	return true, {}
}

/* clear_mark releases the buffer-owned mark and deactivates the region. */
clear_mark :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	if !selection.mark.present {
		return true, {}
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	cleared, clear_failure := editor.buffer_selection_clear_mark(slot.buffer)
	if !cleared {
		return false, editor_failure_context(registry, handle, clear_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* set_viewport updates logical origin and horizontal display-column offset. */
set_viewport :: proc(
	registry: ^Registry,
	handle: View_Handle,
	origin: editor.Position,
	horizontal_display_column: u32,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	moved, move_failure := editor.buffer_anchor_move(slot.buffer, slot.viewport_origin, origin)
	if !moved {
		return false, editor_failure_context(registry, handle, move_failure)
	}
	slot.horizontal_display_column = horizontal_display_column
	slot.state_generation += 1
	return true, {}
}

/* restore_presentation installs copied pane-local point and viewport state. */
restore_presentation :: proc(
	registry: ^Registry,
	handle: View_Handle,
	stored_byte_offset: editor.Byte_Offset,
	viewport_byte_offset: editor.Byte_Offset,
	horizontal_display_column: u32,
	desired_display_column: u32,
	synchronize_effective_point := false,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(slot.buffer)
	if !stats_ok {
		return false, editor_failure_context(registry, handle, stats_failure)
	}
	point_offset := min(u64(stored_byte_offset), stats.text_bytes)
	viewport_offset := min(u64(viewport_byte_offset), stats.text_bytes)
	point, point_ok, point_failure := editor.buffer_position(
		slot.buffer,
		editor.Byte_Offset(point_offset),
	)
	if !point_ok {
		return false, editor_failure_context(registry, handle, point_failure)
	}
	viewport, viewport_ok, viewport_failure := editor.buffer_position(
		slot.buffer,
		editor.Byte_Offset(viewport_offset),
	)
	if !viewport_ok {
		return false, editor_failure_context(registry, handle, viewport_failure)
	}
	previous_point, previous_point_ok, previous_point_failure := editor.buffer_anchor_resolve(
		slot.buffer,
		slot.stored_point,
	)
	if !previous_point_ok {
		return false, editor_failure_context(registry, handle, previous_point_failure)
	}
	previous_viewport, previous_viewport_ok, previous_viewport_failure :=
		editor.buffer_anchor_resolve(slot.buffer, slot.viewport_origin)
	if !previous_viewport_ok {
		return false, editor_failure_context(registry, handle, previous_viewport_failure)
	}
	point_moved, point_move_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.stored_point,
		point,
	)
	if !point_moved {
		return false, editor_failure_context(registry, handle, point_move_failure)
	}
	viewport_moved, viewport_move_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.viewport_origin,
		viewport,
	)
	if !viewport_moved {
		rolled_back, _ := editor.buffer_anchor_move(slot.buffer, slot.stored_point, previous_point)
		assert(rolled_back)
		return false, editor_failure_context(registry, handle, viewport_move_failure)
	}
	if synchronize_effective_point {
		effective_moved, effective_failure := editor.buffer_selection_set_point(slot.buffer, point)
		if !effective_moved {
			point_rolled_back, _ := editor.buffer_anchor_move(
				slot.buffer,
				slot.stored_point,
				previous_point,
			)
			viewport_rolled_back, _ := editor.buffer_anchor_move(
				slot.buffer,
				slot.viewport_origin,
				previous_viewport,
			)
			assert(point_rolled_back && viewport_rolled_back)
			return false, editor_failure_context(registry, handle, effective_failure)
		}
	}
	slot.horizontal_display_column = horizontal_display_column
	slot.desired_display_column = desired_display_column
	slot.state_generation += 1
	return true, {}
}

/* store_effective_point copies the buffer's effective point into one view record. */
store_effective_point :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(slot.buffer)
	if !selection_ok {
		return false, editor_failure_context(registry, handle, selection_failure)
	}
	moved, move_failure := editor.buffer_anchor_move(
		slot.buffer,
		slot.stored_point,
		selection.point_position,
	)
	if !moved {
		return false, editor_failure_context(registry, handle, move_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* restore_stored_point installs one view's point as the buffer's effective point. */
restore_stored_point :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	stored, stored_ok, stored_failure := editor.buffer_anchor_resolve(slot.buffer, slot.stored_point)
	if !stored_ok {
		return false, editor_failure_context(registry, handle, stored_failure)
	}
	moved, move_failure := editor.buffer_selection_set_point(slot.buffer, stored)
	if !moved {
		return false, editor_failure_context(registry, handle, move_failure)
	}
	slot.state_generation += 1
	return true, {}
}

/* transfer_focus atomically stores the outgoing point and restores the incoming point. */
transfer_focus :: proc(
	registry: ^Registry,
	outgoing_handle: View_Handle,
	incoming_handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	outgoing, outgoing_failure := resolve(registry, outgoing_handle)
	if outgoing_failure.code != .None {
		return false, outgoing_failure
	}
	incoming, incoming_failure := resolve(registry, incoming_handle)
	if incoming_failure.code != .None {
		return false, incoming_failure
	}
	if outgoing_handle == incoming_handle {
		return true, {}
	}
	if !prepare_mutation(registry, outgoing_handle, outgoing) {
		return false, mutation_failure(registry, outgoing_handle, outgoing)
	}
	if !prepare_mutation(registry, incoming_handle, incoming) {
		return false, mutation_failure(registry, incoming_handle, incoming)
	}
	outgoing_selection, outgoing_selection_ok, outgoing_selection_failure :=
		editor.buffer_selection_snapshot(outgoing.buffer)
	if !outgoing_selection_ok {
		return false, editor_failure_context(registry, outgoing_handle, outgoing_selection_failure)
	}
	previous_outgoing, previous_outgoing_ok, previous_outgoing_failure :=
		editor.buffer_anchor_resolve(outgoing.buffer, outgoing.stored_point)
	if !previous_outgoing_ok {
		return false, editor_failure_context(registry, outgoing_handle, previous_outgoing_failure)
	}
	incoming_point, incoming_point_ok, incoming_point_failure :=
		editor.buffer_anchor_resolve(incoming.buffer, incoming.stored_point)
	if !incoming_point_ok {
		return false, editor_failure_context(registry, incoming_handle, incoming_point_failure)
	}
	stored, store_failure := editor.buffer_anchor_move(
		outgoing.buffer,
		outgoing.stored_point,
		outgoing_selection.point_position,
	)
	if !stored {
		return false, editor_failure_context(registry, outgoing_handle, store_failure)
	}
	restored, restore_failure := editor.buffer_selection_set_point(incoming.buffer, incoming_point)
	if !restored {
		rolled_back, _ := editor.buffer_anchor_move(
			outgoing.buffer,
			outgoing.stored_point,
			previous_outgoing,
		)
		assert(rolled_back)
		return false, editor_failure_context(registry, incoming_handle, restore_failure)
	}
	outgoing.state_generation += 1
	incoming.state_generation += 1
	return true, {}
}

/* set_layout_policy records resolved view-local movement and display policy. */
set_layout_policy :: proc(
	registry: ^Registry,
	handle: View_Handle,
	desired_display_column: u32,
	tab_width: u16,
	display_profile_id: Display_Profile_ID,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if tab_width == 0 || tab_width > MAX_TAB_WIDTH ||
	   display_profile_id == Display_Profile_ID(0) {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	slot.desired_display_column = desired_display_column
	slot.indentation_policy.policy.indent_width = tab_width
	slot.indentation_policy.policy.display_tab_width = tab_width
	slot.indentation_policy.scope = .Buffer_Local
	slot.indentation_policy.matcher_kind = .Buffer
	slot.indentation_policy.source_generation = slot.state_generation + 1
	slot.indentation_policy.profile_id = indentation.Profile_ID(display_profile_id)
	slot.display_profile_id = display_profile_id
	slot.state_generation += 1
	return true, {}
}

/* set_indentation_policy replaces one view's copied effective indentation policy. */
set_indentation_policy :: proc(
	registry: ^Registry,
	handle: View_Handle,
	policy: indentation.Effective_Policy,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !indentation.effective_policy_is_valid(policy) {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	if slot.indentation_policy == policy {
		return true, {}
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	slot.indentation_policy = policy
	slot.state_generation += 1
	return true, {}
}

/* set_gutter_policy replaces only one live view's checked presentation policy. */
set_gutter_policy :: proc(
	registry: ^Registry,
	handle: View_Handle,
	policy: gutter.Factory_Policy,
	overrides_default := true,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !gutter.factory_policy_is_valid(policy) {
		return false, view_failure(registry, handle, .Invalid_Config)
	}
	if slot.gutter.policy == policy && slot.gutter.overrides_default == overrides_default {
		return true, {}
	}
	if !prepare_mutation(registry, handle, slot) || slot.gutter.generation == max(u64) {
		return false, mutation_failure(registry, handle, slot)
	}
	slot.gutter.policy = policy
	slot.gutter.generation += 1
	slot.gutter.overrides_default = overrides_default
	slot.state_generation += 1
	return true, {}
}

@(private)
resolve :: proc(registry: ^Registry, handle: View_Handle) -> (^View_Slot, Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return nil, registry_failure(registry, .Invalid_Registry)
	}
	if handle.registry_id != data.registry_id {
		return nil, view_failure(registry, handle, .Wrong_Registry)
	}
	if handle.view_id == View_ID(0) || handle.generation == 0 || int(handle.slot) >= MAX_VIEWS {
		return nil, view_failure(registry, handle, .Invalid_View)
	}
	slot := &data.slots[int(handle.slot)]
	if !slot.live || slot.view_id != handle.view_id || slot.generation != handle.generation {
		return nil, view_failure(registry, handle, .Stale_View)
	}
	return slot, {}
}

@(private)
prepare_mutation :: proc(registry: ^Registry, handle: View_Handle, slot: ^View_Slot) -> bool {
	assert(registry != nil && slot != nil)
	assert(slot.live && slot.view_id == handle.view_id)
	return !slot.active_preparation && slot.state_generation != max(u64)
}

@(private)
mutation_failure :: proc(
	registry: ^Registry,
	handle: View_Handle,
	slot: ^View_Slot,
) -> Failure_Context {
	assert(slot != nil)
	if slot.active_preparation {
		return view_failure(registry, handle, .Active_Preparation)
	}
	return generation_failure(registry, handle)
}

@(private)
config_is_valid :: proc(config: Config) -> bool {
	return indentation.policy_is_valid(config.indentation_policy) &&
	       config.display_profile_id != Display_Profile_ID(0) &&
	       gutter.factory_policy_is_valid(config.gutter_policy)
}

@(private)
registry_failure :: proc(registry: ^Registry, code: Failure_Code) -> Failure_Context {
	registry_id: Registry_ID
	data := registry_data(registry)
	if data != nil {
		registry_id = data.registry_id
	}
	return Failure_Context{code = code, registry_id = registry_id}
}

@(private)
view_failure :: proc(
	registry: ^Registry,
	handle: View_Handle,
	code: Failure_Code,
) -> Failure_Context {
	registry_id: Registry_ID
	data := registry_data(registry)
	if data != nil {
		registry_id = data.registry_id
	}
	return Failure_Context {
		code = code,
		registry_id = registry_id,
		view_id = handle.view_id,
		view_generation = handle.generation,
	}
}

@(private)
registry_data :: proc(registry: ^Registry) -> ^Registry_Data {
	if registry == nil || registry.state == nil {
		return nil
	}
	return (^Registry_Data)(registry.state)
}

@(private)
generation_failure :: proc(registry: ^Registry, handle: View_Handle) -> Failure_Context {
	failure := view_failure(registry, handle, .State_Generation_Limit)
	failure.limit = max(u64)
	failure.actual = max(u64)
	return failure
}

@(private)
editor_failure_context :: proc(
	registry: ^Registry,
	handle: View_Handle,
	editor_failure: editor.Failure_Context,
) -> Failure_Context {
	failure := view_failure(registry, handle, .Editor_Failure)
	failure.editor_failure = editor_failure
	return failure
}
