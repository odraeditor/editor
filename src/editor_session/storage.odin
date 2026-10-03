// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "../editor"
import "../history"
import "../project"
import "../result_set"
import "../search"
import editor_view "../view"
import "base:runtime"

@(private)
INVALID_SLOT :: -1

@(private)
Entry_Owner :: struct {
	kind:               Entry_Kind,
	buffer:             editor.Buffer,
	history_store:      history.Store,
	document:           document.Document,
	primary_view:       editor_view.View_Handle,
	selection_label:    string,
	normalized_path:    string,
	terminal_context:   string,
	association:        Association_Kind,
	terminal_ref:       Terminal_Session_Ref,
	terminal_lifecycle: Terminal_Lifecycle,
	reservation:        Graph_Reservation,
	buffer_live:        bool,
	history_live:       bool,
	document_live:      bool,
	primary_view_live:  bool,
}

@(private)
Entry_Slot :: struct {
	owner:               ^Entry_Owner,
	entry_id:            Entry_ID,
	generation:          u32,
	activation_sequence: Activation_Sequence,
	previous_mru:        int,
	next_mru:            int,
	reserved:            bool,
	live:                bool,
}

@(private)
Root_Owner :: struct {
	handle:  Root_Handle,
	kind:    Root_Kind,
	path:    string,
	dir:     project.Dir_Handle,
	project: project.Project_Handle,
}

@(private)
Workspace_Owner :: struct {
	id:            Workspace_ID,
	generation:    u64,
	name:          Workspace_Name,
	root_set:      Root_Set_Generation,
	project_count: u32,
}

@(private)
Workspace_Project_Owner :: struct {
	registry:       project.Registry,
	handle:         project.Project_Handle,
	registry_bytes: u64,
}

@(private)
Search_History_Entry :: struct {
	kind:    search.Pattern_Kind,
	pattern: []u8,
	policy:  search.Policy,
}

@(private)
Search_History_Navigation :: struct {
	active:      bool,
	kind:        search.Pattern_Kind,
	cursor:      int,
	in_progress: []u8,
}

@(private)
Session_Data :: struct {
	handle:             Session_Handle,
	registry:           Registry_Handle,
	policy:             Policy,
	usage:              Resource_Usage,
	slots:              []Entry_Slot,
	label_index:        map[string]int,
	path_index:         map[string]int,
	view_registry:      editor_view.Registry,
	project_registry:   project.Registry,
	result_registry:    result_set.Registry,
	active_location_source: Active_Location_Source,
	project_policy:     project.Policy,
	project_owner:      project.Owner_Handle,
	primary_project:    project.Project_Handle,
	active_project:     project.Project_Handle,
	project_registry_bytes: u64,
	roots:              []Root_Owner,
	root_generation:    Root_Set_Generation,
	next_root_id:       Root_ID,
	root_path_bytes:    u64,
	root_registry_bytes: u64,
	active_workspace:   Workspace_Owner,
	workspace_projects: []Workspace_Project_Owner,
	workspace_project_registry_bytes: u64,
	search_history_entries: []Search_History_Entry,
	search_history_count:   int,
	search_history_bytes:   u64,
	search_history_navigation: Search_History_Navigation,
	mru_head:           int,
	mru_tail:           int,
	next_entry_id:      Entry_ID,
	next_activation:    Activation_Sequence,
	next_buffer_id:     editor.Buffer_ID,
	next_store_id:      history.Store_ID,
	next_document_id:   document.Document_ID,
	visible:            Visible_Target,
	reserved_documents: u32,
	detached_entries:   u32,
	allocator:          runtime.Allocator,
	temporary_allocator: runtime.Allocator,
}

@(private)
Workspace_Activation_State :: struct {
	owner:     Workspace_Owner,
	projects:  []Workspace_Project_Owner,
	roots:     []Root_Proposal,
	paths:     []u8,
	allocator: runtime.Allocator,
}

@(private)
Prepared_Entry_State :: struct {
	session: ^Session_Data,
	owner:   ^Entry_Owner,
	handle:  Entry_Handle,
	slot:    int,
}

@(private)
Detached_Entry_State :: struct {
	session: ^Session_Data,
	owner:   ^Entry_Owner,
	result:  Detachment_Result,
}

@(private)
Descriptor_Batch_State :: struct {
	descriptors: []Entry_Descriptor,
	labels:      []u8,
	allocator:   runtime.Allocator,
}

@(private)
Project_Buffer_Batch_State :: struct {
	descriptors: []Project_Buffer_Descriptor,
	paths:       []u8,
	memberships: []project.Membership_Handle,
	allocator:   runtime.Allocator,
}

@(private)
Root_Batch_State :: struct {
	descriptors: []Root_Descriptor,
	paths:       []u8,
	allocator:   runtime.Allocator,
}

@(private)
Search_History_Batch_State :: struct {
	descriptors: []Search_History_Descriptor,
	patterns:    []u8,
	allocator:   runtime.Allocator,
}

@(private)
session_data :: proc(session: ^Session) -> ^Session_Data {
	if session == nil || session.state == nil || session.closed {
		return nil
	}
	return (^Session_Data)(session.state)
}

@(private)
prepared_entry_state :: proc(prepared: ^Prepared_Entry) -> ^Prepared_Entry_State {
	if prepared == nil || prepared.state == nil {
		return nil
	}
	return (^Prepared_Entry_State)(prepared.state)
}

@(private)
detached_entry_state :: proc(detached: ^Detached_Entry) -> ^Detached_Entry_State {
	if detached == nil || detached.state == nil {
		return nil
	}
	return (^Detached_Entry_State)(detached.state)
}

@(private)
session_failure :: proc(data: ^Session_Data, operation: Operation, code: Failure_Code) -> Failure_Context {
	failure := Failure_Context {
		code = code,
		operation = operation,
	}
	if data != nil {
		failure.session = data.handle
		failure.registry = data.registry
	}
	return failure
}

@(private)
resolve_session :: proc(
	session: ^Session,
	handle: Session_Handle,
	operation: Operation,
) -> (data: ^Session_Data, failure: Failure_Context) {
	data = session_data(session)
	if data == nil {
		return nil, Failure_Context{code = .Invalid_Session, operation = operation}
	}
	if handle.session_id != data.handle.session_id {
		return nil, session_failure(data, operation, .Wrong_Session)
	}
	if handle.generation != data.handle.generation {
		return nil, session_failure(data, operation, .Stale_Session)
	}
	return data, {}
}

@(private)
resolve_entry :: proc(
	data: ^Session_Data,
	handle: Entry_Handle,
	operation: Operation,
) -> (slot: ^Entry_Slot, slot_index: int, failure: Failure_Context) {
	if !entry_handle_is_valid(handle) {
		return nil, INVALID_SLOT, session_failure(data, operation, .Invalid_Entry)
	}
	if handle.registry.session != data.handle {
		return nil, INVALID_SLOT, session_failure(data, operation, .Wrong_Session)
	}
	if handle.registry.generation != data.registry.generation {
		return nil, INVALID_SLOT, session_failure(data, operation, .Stale_Registry)
	}
	if handle.slot >= u32(len(data.slots)) {
		return nil, INVALID_SLOT, session_failure(data, operation, .Invalid_Entry)
	}
	slot_index = int(handle.slot)
	slot = &data.slots[slot_index]
	if !slot.live || slot.entry_id != handle.entry_id || slot.generation != handle.generation {
		failure = session_failure(data, operation, .Stale_Entry)
		failure.entry = handle
		return nil, INVALID_SLOT, failure
	}
	return slot, slot_index, {}
}

@(private)
entry_handle :: proc(data: ^Session_Data, slot_index: int) -> Entry_Handle {
	slot := &data.slots[slot_index]
	return Entry_Handle {
		registry = data.registry,
		entry_id = slot.entry_id,
		slot = u32(slot_index),
		generation = slot.generation,
	}
}

@(private)
visible_from_slot :: proc(data: ^Session_Data, slot_index: int) -> Visible_Target {
	slot := &data.slots[slot_index]
	return Visible_Target {
		kind = .Primary_View,
		entry = entry_handle(data, slot_index),
		primary_view = slot.owner.primary_view,
	}
}

@(private)
owner_graph :: proc(owner: ^Entry_Owner, handle: Entry_Handle) -> Object_Graph_Identity {
	buffer_stats, buffer_ok, _ := editor.buffer_stats(&owner.buffer)
	history_stats, history_ok, _ := history.store_stats(&owner.history_store)
	document_id := document.Document_ID(0)
	if owner.document_live {
		status, status_ok, _ := document.document_status(&owner.document)
		if status_ok {
			document_id = status.document_id
		}
	}
	assert(buffer_ok && history_ok)
	return Object_Graph_Identity {
		entry = handle,
		kind = owner.kind,
		buffer_id = buffer_stats.buffer_id,
		history_id = history_stats.history_id,
		primary_view = owner.primary_view,
		has_document = owner.document_live,
		document_id = document_id,
	}
}
