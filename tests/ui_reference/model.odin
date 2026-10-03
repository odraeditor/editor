// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package ui_reference provides an independent fixed-array oracle for logical
// UI publication, focus, selection, replacement, and teardown behavior.
package ui_reference

MAX_SURFACES :: 16
MAX_NODES :: MAX_SURFACES * 2 - 1
MAX_STATUS_REGIONS :: 8
MAX_POPUPS :: 1

Handle :: struct {
	id:         u16,
	generation: u64,
}

View_Kind :: enum u8 {
	Invalid,
	Text,
	List,
	Tree,
	Input,
}

Selection_Owner :: enum u8 {
	None,
	Model,
	View,
}

Composition_Kind :: enum u8 {
	Invalid,
	Surface,
	Split,
}

Orientation :: enum u8 {
	Invalid,
	Above_Below,
	Left_Right,
}

Status_Placement :: enum u8 {
	Invalid,
	Attached,
	Root_Edge,
}

Popup_Anchor_Kind :: enum u8 {
	Invalid,
	Cursor,
	Logical_Text,
	Gutter_Marker,
	Surface,
}

Popup_Behavior :: enum u8 {
	Invalid,
	Informational,
	Interactive,
}

Popup :: struct {
	id:                  u16,
	generation:          u64,
	owner_id:            u64,
	owner_generation:    u64,
	anchor_kind:         Popup_Anchor_Kind,
	anchor_surface_id:   u16,
	anchor_generation:   u64,
	content_surface_id:  u16,
	content_generation:  u64,
	behavior:            Popup_Behavior,
	live:                bool,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Proposal,
	Invalid_Handle,
	Invalid_State,
	Invalid_View,
	Capacity,
	Stale_Generation,
	Focus_Unavailable,
}

Failure :: struct {
	code:   Failure_Code,
	handle: Handle,
}

Surface :: struct {
	id:              u16,
	view:            View_Kind,
	focusable:       bool,
	available:       bool,
	selection_owner: Selection_Owner,
	model_current:   i32,
	view_current:    i32,
	live:            bool,
}

Composition_Node :: struct {
	id:          u16,
	kind:        Composition_Kind,
	surface_id:  u16,
	first:       u16,
	second:      u16,
	orientation: Orientation,
	live:        bool,
}

Status_Region :: struct {
	id:         u16,
	placement:  Status_Placement,
	surface_id: u16,
	rows:       u16,
	live:       bool,
}

Proposal :: struct {
	expected_generation: u64,
	surfaces:            [MAX_SURFACES]Surface,
	nodes:               [MAX_NODES]Composition_Node,
	status_regions:      [MAX_STATUS_REGIONS]Status_Region,
	popups:              [MAX_POPUPS]Popup,
	surface_count:       u16,
	node_count:          u16,
	status_count:        u16,
	popup_count:         u16,
	root_node:           u16,
	focus_surface:       u16,
}

proposal_add_popup :: proc(
	proposal: ^Proposal,
	popup: Popup,
) -> (popup_id: u16, ok: bool, failure: Failure) {
	if proposal == nil {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	if proposal.popup_count >= MAX_POPUPS {
		return 0, false, Failure{code = .Capacity}
	}
	entry := popup
	entry.id = proposal.popup_count + 1
	entry.live = true
	if !proposal_popup_valid(proposal, entry) {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	proposal.popups[proposal.popup_count] = entry
	proposal.popup_count += 1
	return entry.id, true, {}
}

Focus_Capture :: struct {
	active:        bool,
	target:        Handle,
	return_target: Handle,
}

Model :: struct {
	active:      Proposal,
	generation:  u64,
	root_active: bool,
	focus:       Handle,
	capture:     Focus_Capture,
}

proposal_init :: proc(expected_generation: u64) -> Proposal {
	return Proposal{expected_generation = expected_generation}
}

proposal_add_surface :: proc(
	proposal: ^Proposal,
	view: View_Kind,
	focusable := true,
	selection_owner := Selection_Owner.None,
) -> (surface_id, node_id: u16, ok: bool, failure: Failure) {
	if proposal == nil {
		return 0, 0, false, Failure{code = .Invalid_Proposal}
	}
	if proposal.surface_count >= MAX_SURFACES || proposal.node_count >= MAX_NODES {
		return 0, 0, false, Failure{code = .Capacity}
	}
	if !view_contract_valid(view, selection_owner) {
		return 0, 0, false, Failure{code = .Invalid_View}
	}
	surface_id = proposal.surface_count + 1
	node_id = proposal.node_count + 1
	proposal.surfaces[proposal.surface_count] = Surface {
		id = surface_id,
		view = view,
		focusable = focusable,
		available = true,
		selection_owner = selection_owner,
		model_current = -1,
		view_current = -1,
		live = true,
	}
	proposal.nodes[proposal.node_count] = Composition_Node {
		id = node_id,
		kind = .Surface,
		surface_id = surface_id,
		live = true,
	}
	proposal.surface_count += 1
	proposal.node_count += 1
	return surface_id, node_id, true, {}
}

proposal_add_popup_surface :: proc(
	proposal: ^Proposal,
	view: View_Kind,
) -> (surface_id: u16, ok: bool, failure: Failure) {
	if proposal == nil {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	if proposal.surface_count >= MAX_SURFACES {
		return 0, false, Failure{code = .Capacity}
	}
	if !view_contract_valid(view, .None) {
		return 0, false, Failure{code = .Invalid_View}
	}
	surface_id = proposal.surface_count + 1
	proposal.surfaces[proposal.surface_count] = Surface {
		id = surface_id,
		view = view,
		focusable = false,
		available = true,
		selection_owner = .None,
		model_current = -1,
		view_current = -1,
		live = true,
	}
	proposal.surface_count += 1
	return surface_id, true, {}
}

proposal_add_split :: proc(
	proposal: ^Proposal,
	first, second: u16,
	orientation: Orientation,
) -> (node_id: u16, ok: bool, failure: Failure) {
	if proposal == nil {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	if proposal.node_count >= MAX_NODES {
		return 0, false, Failure{code = .Capacity}
	}
	if first == second || !proposal_node_exists(proposal, first) ||
	   !proposal_node_exists(proposal, second) ||
	   (orientation != .Above_Below && orientation != .Left_Right) {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	node_id = proposal.node_count + 1
	proposal.nodes[proposal.node_count] = Composition_Node {
		id = node_id,
		kind = .Split,
		first = first,
		second = second,
		orientation = orientation,
		live = true,
	}
	proposal.node_count += 1
	return node_id, true, {}
}

proposal_add_status :: proc(
	proposal: ^Proposal,
	placement: Status_Placement,
	surface_id: u16,
	rows: u16 = 1,
) -> (status_id: u16, ok: bool, failure: Failure) {
	if proposal == nil {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	if proposal.status_count >= MAX_STATUS_REGIONS {
		return 0, false, Failure{code = .Capacity}
	}
	valid_placement := (placement == .Attached && proposal_surface_exists(proposal, surface_id)) ||
		(placement == .Root_Edge && surface_id == 0)
	if !valid_placement || rows == 0 {
		return 0, false, Failure{code = .Invalid_Proposal}
	}
	status_id = proposal.status_count + 1
	proposal.status_regions[proposal.status_count] = Status_Region {
		id = status_id,
		placement = placement,
		surface_id = surface_id,
		rows = rows,
		live = true,
	}
	proposal.status_count += 1
	return status_id, true, {}
}

proposal_set_root :: proc(
	proposal: ^Proposal,
	root_node, focus_surface: u16,
) -> (ok: bool, failure: Failure) {
	if proposal == nil || !proposal_node_exists(proposal, root_node) ||
	   !proposal_surface_focusable(proposal, focus_surface) {
		return false, Failure{code = .Invalid_Proposal}
	}
	proposal.root_node = root_node
	proposal.focus_surface = focus_surface
	return true, {}
}

proposal_validate :: proc(proposal: ^Proposal) -> bool {
	if proposal == nil || proposal.surface_count == 0 || proposal.node_count == 0 ||
	   proposal.surface_count > MAX_SURFACES || proposal.node_count > MAX_NODES ||
	   proposal.status_count > MAX_STATUS_REGIONS ||
	   proposal.popup_count > MAX_POPUPS ||
	   !proposal_node_exists(proposal, proposal.root_node) ||
	   !proposal_surface_focusable(proposal, proposal.focus_surface) {
		return false
	}

	for index in 0 ..< int(proposal.surface_count) {
		surface := proposal.surfaces[index]
		if !surface.live || surface.id != u16(index + 1) ||
		   !view_contract_valid(surface.view, surface.selection_owner) {
			return false
		}
	}

	root_edge_count := 0
	for index in 0 ..< int(proposal.status_count) {
		status := proposal.status_regions[index]
		if !status.live || status.id != u16(index + 1) || status.rows == 0 {
			return false
		}
		switch status.placement {
		case .Attached:
			if !proposal_surface_exists(proposal, status.surface_id) {
				return false
			}
		case .Root_Edge:
			if status.surface_id != 0 {
				return false
			}
			root_edge_count += 1
		case .Invalid:
			return false
		}
	}
	if root_edge_count > 1 {
		return false
	}

	popup_surface_references: [MAX_SURFACES]u16
	for index in 0 ..< int(proposal.popup_count) {
		popup := proposal.popups[index]
		if !popup.live || popup.id != u16(index + 1) ||
		   !proposal_popup_valid(proposal, popup) {
			return false
		}
		popup_surface_references[popup.content_surface_id - 1] += 1
	}

	visited: [MAX_NODES]bool
	surface_references: [MAX_SURFACES]u16
	if !proposal_visit_node(proposal, proposal.root_node, &visited, &surface_references) {
		return false
	}
	for index in 0 ..< int(proposal.node_count) {
		if !visited[index] {
			return false
		}
	}
	for index in 0 ..< int(proposal.surface_count) {
		if popup_surface_references[index] > 1 ||
		   (popup_surface_references[index] == 1 && surface_references[index] != 0) ||
		   (popup_surface_references[index] == 0 && surface_references[index] != 1) {
			return false
		}
	}
	return true
}

model_publish :: proc(
	model: ^Model,
	proposal: ^Proposal,
) -> (generation: u64, ok: bool, failure: Failure) {
	if model == nil {
		return 0, false, Failure{code = .Invalid_Model}
	}
	if proposal == nil || proposal.expected_generation != model.generation {
		return model.generation, false, Failure{code = .Stale_Generation}
	}
	if !proposal_validate(proposal) {
		return model.generation, false, Failure{code = .Invalid_Proposal}
	}

	next_generation := model.generation + 1
	model.active = proposal^
	model.generation = next_generation
	model.root_active = true
	model.focus = Handle{id = proposal.focus_surface, generation = next_generation}
	model.capture = {}
	return next_generation, true, {}
}

model_focus_surface :: proc(
	model: ^Model,
	handle: Handle,
) -> (ok: bool, failure: Failure) {
	surface, valid := model_surface(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	if !surface.focusable || !surface.available || model.capture.active {
		return false, Failure{code = .Focus_Unavailable, handle = handle}
	}
	model.focus = handle
	return true, {}
}

model_capture_focus :: proc(
	model: ^Model,
	target: Handle,
) -> (ok: bool, failure: Failure) {
	surface, valid := model_surface(model, target)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = target}
	}
	if model.capture.active || surface.view != .Input || !surface.focusable ||
	   !surface.available {
		return false, Failure{code = .Focus_Unavailable, handle = target}
	}
	model.capture = Focus_Capture {
		active = true,
		target = target,
		return_target = model.focus,
	}
	model.focus = target
	return true, {}
}

model_release_focus :: proc(model: ^Model) -> (focus: Handle, ok: bool, failure: Failure) {
	if !model_ready(model) || !model.capture.active {
		return {}, false, Failure{code = .Invalid_State}
	}
	return_target := model.capture.return_target
	model.capture = {}
	if model_surface_focusable(model, return_target) {
		model.focus = return_target
		return model.focus, true, {}
	}
	fallback, found := model_first_focusable(model)
	if !found {
		return {}, false, Failure{code = .Focus_Unavailable}
	}
	model.focus = fallback
	return model.focus, true, {}
}

model_set_surface_available :: proc(
	model: ^Model,
	handle: Handle,
	available: bool,
) -> (ok: bool, failure: Failure) {
	surface, valid := model_surface(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	if !available && model.focus == handle &&
	   (!model.capture.active || model.capture.target == handle) {
		return false, Failure{code = .Focus_Unavailable, handle = handle}
	}
	surface.available = available
	return true, {}
}

model_select_list_item :: proc(
	model: ^Model,
	handle: Handle,
	item: i32,
) -> (ok: bool, failure: Failure) {
	surface, valid := model_surface(model, handle)
	if !valid {
		return false, Failure{code = .Invalid_Handle, handle = handle}
	}
	if surface.view != .List || item < 0 {
		return false, Failure{code = .Invalid_View, handle = handle}
	}
	switch surface.selection_owner {
	case .Model:
		surface.model_current = item
	case .View:
		surface.view_current = item
	case .None:
		return false, Failure{code = .Invalid_View, handle = handle}
	}
	return true, {}
}

model_surface_handle :: proc(model: ^Model, id: u16) -> (handle: Handle, ok: bool) {
	if !model_ready(model) || !proposal_surface_exists(&model.active, id) {
		return {}, false
	}
	return Handle{id = id, generation = model.generation}, true
}

model_inspect_surface :: proc(
	model: ^Model,
	handle: Handle,
) -> (surface: Surface, ok: bool) {
	entry, valid := model_surface(model, handle)
	if !valid {
		return {}, false
	}
	return entry^, true
}

model_popup_handle :: proc(model: ^Model, id: u16) -> (handle: Handle, ok: bool) {
	if !model_ready(model) || id == 0 || id > model.active.popup_count ||
	   !model.active.popups[id - 1].live {
		return {}, false
	}
	return Handle{id = id, generation = model.generation}, true
}

model_inspect_popup :: proc(
	model: ^Model,
	handle: Handle,
) -> (popup: Popup, ok: bool) {
	if !model_ready(model) || handle.generation != model.generation ||
	   handle.id == 0 || handle.id > model.active.popup_count {
		return {}, false
	}
	entry := model.active.popups[handle.id - 1]
	if !entry.live {
		return {}, false
	}
	return entry, true
}

model_teardown :: proc(model: ^Model) -> bool {
	if model == nil || !model.root_active {
		return false
	}
	model.generation += 1
	model.active = {}
	model.root_active = false
	model.focus = {}
	model.capture = {}
	return true
}

model_validate :: proc(model: ^Model) -> bool {
	if !model_ready(model) {
		return false
	}
	structural := model.active
	if proposal_surface_exists(&structural, structural.focus_surface) {
		structural.surfaces[structural.focus_surface - 1].available = true
	}
	if !proposal_validate(&structural) || !model_surface_focusable(model, model.focus) {
		return false
	}
	if model.capture.active {
		target, target_ok := model_surface(model, model.capture.target)
		if !target_ok || target.view != .Input || model.focus != model.capture.target {
			return false
		}
	}
	return true
}

@(private)
model_ready :: proc(model: ^Model) -> bool {
	return model != nil && model.root_active && model.generation > 0
}

@(private)
view_contract_valid :: proc(view: View_Kind, owner: Selection_Owner) -> bool {
	switch view {
	case .Text, .Input:
		return owner == .None
	case .List, .Tree:
		return owner == .Model || owner == .View
	case .Invalid:
		return false
	}
	return false
}

@(private)
proposal_surface_exists :: proc(proposal: ^Proposal, id: u16) -> bool {
	return proposal != nil && id > 0 && id <= proposal.surface_count &&
		proposal.surfaces[id - 1].live && proposal.surfaces[id - 1].id == id
}

@(private)
proposal_surface_focusable :: proc(proposal: ^Proposal, id: u16) -> bool {
	return proposal_surface_exists(proposal, id) &&
		proposal.surfaces[id - 1].focusable && proposal.surfaces[id - 1].available
}

@(private)
proposal_node_exists :: proc(proposal: ^Proposal, id: u16) -> bool {
	return proposal != nil && id > 0 && id <= proposal.node_count &&
		proposal.nodes[id - 1].live && proposal.nodes[id - 1].id == id
}

@(private)
proposal_popup_valid :: proc(proposal: ^Proposal, popup: Popup) -> bool {
	return popup.generation > 0 && popup.owner_id > 0 && popup.owner_generation > 0 &&
		popup.anchor_kind != .Invalid && popup.anchor_generation > 0 &&
		proposal_surface_exists(proposal, popup.anchor_surface_id) &&
		proposal_surface_exists(proposal, popup.content_surface_id) &&
		popup.anchor_surface_id != popup.content_surface_id &&
		!proposal.surfaces[popup.content_surface_id - 1].focusable &&
		popup.content_generation > 0 && popup.behavior == .Informational
}

@(private)
proposal_visit_node :: proc(
	proposal: ^Proposal,
	id: u16,
	visited: ^[MAX_NODES]bool,
	surface_references: ^[MAX_SURFACES]u16,
) -> bool {
	if !proposal_node_exists(proposal, id) || visited[id - 1] {
		return false
	}
	visited[id - 1] = true
	node := proposal.nodes[id - 1]
	switch node.kind {
	case .Surface:
		if !proposal_surface_exists(proposal, node.surface_id) || node.first != 0 ||
		   node.second != 0 || node.orientation != .Invalid {
			return false
		}
		surface_references[node.surface_id - 1] += 1
		return true
	case .Split:
		if node.surface_id != 0 || node.first == node.second ||
		   (node.orientation != .Above_Below && node.orientation != .Left_Right) {
			return false
		}
		return proposal_visit_node(proposal, node.first, visited, surface_references) &&
			proposal_visit_node(proposal, node.second, visited, surface_references)
	case .Invalid:
		return false
	}
	return false
}

@(private)
model_surface :: proc(model: ^Model, handle: Handle) -> (surface: ^Surface, ok: bool) {
	if !model_ready(model) || handle.generation != model.generation ||
	   !proposal_surface_exists(&model.active, handle.id) {
		return nil, false
	}
	return &model.active.surfaces[handle.id - 1], true
}

@(private)
model_surface_focusable :: proc(model: ^Model, handle: Handle) -> bool {
	surface, valid := model_surface(model, handle)
	return valid && surface.focusable && surface.available
}

@(private)
model_first_focusable :: proc(model: ^Model) -> (handle: Handle, ok: bool) {
	if !model_ready(model) {
		return {}, false
	}
	for surface in model.active.surfaces[:model.active.surface_count] {
		if surface.live && surface.focusable && surface.available {
			return Handle{id = surface.id, generation = model.generation}, true
		}
	}
	return {}, false
}
