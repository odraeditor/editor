// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../editor"
import "../result_set"

/* Active_Location_Source_Kind identifies the current owner of unified location movement. */
Active_Location_Source_Kind :: enum u8 {
	Invalid,
	Result_Set,
}

/* Active_Location_Source is one copied session-local navigation authority. */
Active_Location_Source :: struct {
	kind:       Active_Location_Source_Kind,
	set_id:     result_set.Result_Set_ID,
	generation: result_set.Result_Set_Generation,
	source:     result_set.Source_Descriptor,
}

/* session_result_source_activate makes one current result generation the unified source. */
session_result_source_activate :: proc(
	session: ^Session,
	handle: Session_Handle,
	set_id: result_set.Result_Set_ID,
) -> (Active_Location_Source, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return {}, false, resolved_failure
	view, viewed, _ := result_set.registry_view(&data.result_registry, set_id)
	if !viewed do return {}, false, session_failure(data, .Inspect, .Invalid_Entry)
	data.active_location_source = {
		kind = .Result_Set, set_id = set_id, generation = view.generation, source = view.source,
	}
	return data.active_location_source, true, {}
}

/* session_result_source_move changes selection only through the active source. */
session_result_source_move :: proc(
	session: ^Session,
	handle: Session_Handle,
	movement: result_set.Movement,
) -> (result_set.Result, result_set.Location, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return {}, {}, false, resolved_failure
	source := data.active_location_source
	if source.kind != .Result_Set do return {}, {}, false,
		session_failure(data, .Inspect, .Invalid_Visible_Target)
	result, moved, _ := result_set.registry_move(
		&data.result_registry, source.set_id, source.generation, movement)
	if !moved do return {}, {}, false, session_failure(data, .Inspect, .Invalid_Entry)
	view, viewed, _ := result_set.registry_view(&data.result_registry, source.set_id)
	if !viewed || !view.has_selection || int(view.selected_index) >= len(view.locations) do return {}, {}, false,
		session_failure(data, .Inspect, .Invalid_Entry)
	data.active_location_source.generation = view.generation
	return result, view.locations[view.selected_index], true, {}
}

/* session_active_location_source returns the copied current source. */
session_active_location_source :: proc(
	session: ^Session,
	handle: Session_Handle,
) -> (Active_Location_Source, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return {}, false, resolved_failure
	if data.active_location_source.kind == .Invalid do return {}, false, {}
	return data.active_location_source, true, {}
}

/* session_result_source_clear invalidates unified movement for one closed generation. */
session_result_source_clear :: proc(
	session: ^Session,
	handle: Session_Handle,
	set_id: result_set.Result_Set_ID,
	generation: result_set.Result_Set_Generation,
) -> (bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return false, resolved_failure
	source := data.active_location_source
	if source.kind == .Result_Set && source.set_id == set_id && source.generation == generation {
		data.active_location_source = {}
	}
	return true, {}
}

/* session_entry_for_buffer resolves one exact live entry without exposing registry storage. */
session_entry_for_buffer :: proc(
	session: ^Session,
	handle: Session_Handle,
	buffer_id: editor.Buffer_ID,
) -> (Entry_Handle, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return {}, false, resolved_failure
	if buffer_id == editor.Buffer_ID(0) do return {}, false, session_failure(data, .Inspect, .Invalid_Entry)
	for slot, index in data.slots {
		if !slot.live || slot.owner == nil do continue
		stats, stats_ok, _ := editor.buffer_stats(&slot.owner.buffer)
		if stats_ok && stats.buffer_id == buffer_id {
			return entry_handle(data, index), true, {}
		}
	}
	return {}, false, session_failure(data, .Inspect, .Invalid_Entry)
}
