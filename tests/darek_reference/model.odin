// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package darek_reference provides an independent oracle for Darek tree behavior.
package darek_reference

import "core:unicode/utf8"

MAX_NODES :: 32
MAX_LABEL_BYTES :: 64
MAX_DEPTH :: 8

Node_ID :: distinct u64

Node_Kind :: enum u8 {
	Invalid,
	Project,
	Directory,
	File,
}

Root_Mode :: enum u8 {
	Invalid,
	Exclusive_Project,
	Exclusive_Directory,
	Workspace,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Generation,
	Invalid_Node,
	Duplicate_Node,
	Missing_Parent,
	Depth_Limit,
	Node_Limit,
}

Definition :: struct {
	id:         Node_ID,
	parent:     Node_ID,
	kind:       Node_Kind,
	label:      string,
	expandable: bool,
	unavailable: bool,
}

Node :: struct {
	definition: Definition,
	expanded:   bool,
}

Model :: struct {
	nodes:               [MAX_NODES]Node,
	count:               int,
	generation:          u64,
	selected:            Node_ID,
	has_selection:       bool,
	panel_visible:       bool,
	panel_focused:       bool,
	ordinary_focus_live: bool,
	root_mode:           Root_Mode,
	workspace_generation: u64,
}

model_init :: proc() -> Model {
	return Model{ordinary_focus_live = true}
}

model_close :: proc(model: ^Model) {
	if model != nil {
		model^ = {}
	}
}

model_publish :: proc(
	model: ^Model,
	generation: u64,
	definitions: []Definition,
) -> (bool, Failure_Code) {
	mode := Root_Mode.Exclusive_Directory
	if len(definitions) > 0 && definitions[0].kind == .Project {
		mode = .Exclusive_Project
	}
	return model_publish_context(model, generation, mode, 0, definitions)
}

model_publish_workspace :: proc(
	model: ^Model,
	generation: u64,
	workspace_generation: u64,
	definitions: []Definition,
) -> (bool, Failure_Code) {
	if workspace_generation == 0 || len(definitions) == 0 {
		return false, .Invalid_Generation
	}
	root_count := 0
	for definition in definitions {
		if definition.parent == Node_ID(0) {
			if definition.kind != .Project {
				return false, .Invalid_Node
			}
			root_count += 1
		}
	}
	if root_count == 0 do return false, .Invalid_Node
	return model_publish_context(
		model, generation, .Workspace, workspace_generation, definitions,
	)
}

@(private)
model_publish_context :: proc(
	model: ^Model,
	generation: u64,
	root_mode: Root_Mode,
	workspace_generation: u64,
	definitions: []Definition,
) -> (bool, Failure_Code) {
	if model == nil {
		return false, .Invalid_Model
	}
	if root_mode == .Invalid ||
	   (root_mode == .Workspace) != (workspace_generation > 0) {
		return false, .Invalid_Generation
	}
	if generation == 0 || generation <= model.generation {
		return false, .Invalid_Generation
	}
	if len(definitions) > MAX_NODES {
		return false, .Node_Limit
	}
	candidate := model^
	candidate.count = 0
	candidate.generation = generation
	candidate.root_mode = root_mode
	candidate.workspace_generation = workspace_generation
	for definition, index in definitions {
		if !definition_valid(definition) {
			return false, .Invalid_Node
		}
		for previous in definitions[:index] {
			if previous.id == definition.id {
				return false, .Duplicate_Node
			}
		}
		if definition.parent != Node_ID(0) {
			parent := definition_find(definitions[:index], definition.parent)
			if parent < 0 {
				return false, .Missing_Parent
			}
			if definition_depth(definitions[:index + 1], index) > MAX_DEPTH {
				return false, .Depth_Limit
			}
			if definitions[parent].unavailable {
				return false, .Invalid_Node
			}
		}
		previous_index := model_find(model, definition.id)
		expanded := previous_index >= 0 && model.nodes[previous_index].expanded
		candidate.nodes[candidate.count] = Node {
			definition = definition,
			expanded = expanded && definition.expandable,
		}
		candidate.count += 1
	}
	for index in candidate.count ..< MAX_NODES {
		candidate.nodes[index] = {}
	}
	if candidate.has_selection &&
	   (!model_node_visible(&candidate, candidate.selected) ||
	    model_find(&candidate, candidate.selected) < 0) {
		candidate.has_selection = false
		candidate.selected = Node_ID(0)
	}
	if !candidate.has_selection {
		if first, present := model_visible_at(&candidate, 0); present {
			candidate.selected = first.definition.id
			candidate.has_selection = true
		}
	}
	if !model_validate(&candidate) {
		return false, .Invalid_Model
	}
	model^ = candidate
	return true, .None
}

model_toggle_panel :: proc(model: ^Model) -> bool {
	if !model_validate(model) {
		return false
	}
	model.panel_visible = !model.panel_visible
	if !model.panel_visible {
		model.panel_focused = false
	}
	return true
}

model_toggle_focus :: proc(model: ^Model) -> bool {
	if !model_validate(model) {
		return false
	}
	if !model.panel_visible {
		model.panel_visible = true
		model.panel_focused = true
		return true
	}
	if model.panel_focused {
		if !model.ordinary_focus_live {
			return false
		}
		model.panel_focused = false
		return true
	}
	model.panel_focused = true
	return true
}

model_toggle_selected :: proc(model: ^Model) -> bool {
	if !model_validate(model) || !model.has_selection {
		return false
	}
	index := model_find(model, model.selected)
	if index < 0 || !model.nodes[index].definition.expandable {
		return false
	}
	model.nodes[index].expanded = !model.nodes[index].expanded
	return true
}

model_move_visible :: proc(model: ^Model, delta: int) -> bool {
	if !model_validate(model) || !model.has_selection || delta == 0 {
		return false
	}
	current := model_visible_index(model, model.selected)
	if current < 0 {
		return false
	}
	next := current + delta
	if next < 0 {
		return false
	}
	node, present := model_visible_at(model, next)
	if !present {
		return false
	}
	model.selected = node.definition.id
	return true
}

model_move_sibling :: proc(model: ^Model, delta: int) -> bool {
	if !model_validate(model) || !model.has_selection || delta == 0 {
		return false
	}
	selected_index := model_find(model, model.selected)
	if selected_index < 0 {
		return false
	}
	selected := model.nodes[selected_index]
	step := 1 if delta > 0 else -1
	remaining := delta if delta > 0 else -delta
	index := selected_index + step
	for index >= 0 && index < model.count {
		candidate := model.nodes[index]
		if candidate.definition.parent == selected.definition.parent &&
		   model_node_visible(model, candidate.definition.id) {
			remaining -= 1
			if remaining == 0 {
				model.selected = candidate.definition.id
				return true
			}
		}
		index += step
	}
	return false
}

model_move_parent :: proc(model: ^Model) -> bool {
	if !model_validate(model) || !model.has_selection {
		return false
	}
	index := model_find(model, model.selected)
	if index < 0 || model.nodes[index].definition.parent == Node_ID(0) {
		return false
	}
	model.selected = model.nodes[index].definition.parent
	return true
}

model_visible_count :: proc(model: ^Model) -> int {
	if model == nil {
		return 0
	}
	count: int
	for node in model.nodes[:model.count] {
		if model_node_visible(model, node.definition.id) {
			count += 1
		}
	}
	return count
}

model_validate :: proc(model: ^Model) -> bool {
	if model == nil || model.count < 0 || model.count > MAX_NODES {
		return false
	}
	if model.generation == 0 {
		return model.count == 0 && !model.has_selection &&
		       model.selected == Node_ID(0) && !model.panel_visible &&
		       !model.panel_focused && model.root_mode == .Invalid &&
		       model.workspace_generation == 0
	}
	if model.root_mode == .Invalid ||
	   (model.root_mode == .Workspace) != (model.workspace_generation > 0) {
		return false
	}
	for node, index in model.nodes[:model.count] {
		if !definition_valid(node.definition) ||
		   (!node.definition.expandable && node.expanded) {
			return false
		}
		for previous in model.nodes[:index] {
			if previous.definition.id == node.definition.id {
				return false
			}
		}
		if node.definition.parent != Node_ID(0) {
			parent := model_find_prefix(model, node.definition.parent, index)
			if parent < 0 || model.nodes[parent].definition.unavailable ||
			   definition_depth_nodes(model.nodes[:index + 1], index) > MAX_DEPTH {
				return false
			}
		} else if model.root_mode == .Workspace && node.definition.kind != .Project {
			return false
		}
	}
	if model.panel_focused && !model.panel_visible {
		return false
	}
	if model.count == 0 {
		return !model.has_selection && model.selected == Node_ID(0)
	}
	return model.has_selection && model_find(model, model.selected) >= 0 &&
	       model_node_visible(model, model.selected)
}

@(private)
definition_valid :: proc(definition: Definition) -> bool {
	if definition.id == Node_ID(0) || definition.kind == .Invalid ||
	   len(definition.label) == 0 || len(definition.label) > MAX_LABEL_BYTES ||
	   !utf8.valid_string(definition.label) {
		return false
	}
	if definition.kind == .File && definition.expandable {
		return false
	}
	if definition.unavailable && (definition.kind != .Project || definition.expandable) {
		return false
	}
	return true
}

@(private)
definition_find :: proc(definitions: []Definition, id: Node_ID) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

@(private)
definition_depth :: proc(definitions: []Definition, index: int) -> int {
	depth := 0
	parent := definitions[index].parent
	for parent != Node_ID(0) {
		depth += 1
		parent_index := definition_find(definitions[:index], parent)
		if parent_index < 0 {
			return MAX_DEPTH + 1
		}
		parent = definitions[parent_index].parent
	}
	return depth
}

@(private)
definition_depth_nodes :: proc(nodes: []Node, index: int) -> int {
	depth := 0
	parent := nodes[index].definition.parent
	for parent != Node_ID(0) {
		depth += 1
		parent_index := -1
		for candidate, candidate_index in nodes[:index] {
		if candidate.definition.id == parent {
				parent_index = candidate_index
				break
			}
		}
		if parent_index < 0 {
			return MAX_DEPTH + 1
		}
		parent = nodes[parent_index].definition.parent
	}
	return depth
}

@(private)
model_find :: proc(model: ^Model, id: Node_ID) -> int {
	if model == nil {
		return -1
	}
	for node, index in model.nodes[:model.count] {
		if node.definition.id == id {
			return index
		}
	}
	return -1
}

@(private)
model_find_prefix :: proc(model: ^Model, id: Node_ID, end: int) -> int {
	for node, index in model.nodes[:end] {
		if node.definition.id == id {
			return index
		}
	}
	return -1
}

@(private)
model_node_visible :: proc(model: ^Model, id: Node_ID) -> bool {
	index := model_find(model, id)
	if index < 0 {
		return false
	}
	parent := model.nodes[index].definition.parent
	for parent != Node_ID(0) {
		parent_index := model_find(model, parent)
		if parent_index < 0 || !model.nodes[parent_index].expanded {
			return false
		}
		parent = model.nodes[parent_index].definition.parent
	}
	return true
}

@(private)
model_visible_at :: proc(model: ^Model, target: int) -> (Node, bool) {
	if model == nil || target < 0 {
		return {}, false
	}
	visible_index: int
	for node in model.nodes[:model.count] {
		if !model_node_visible(model, node.definition.id) {
			continue
		}
		if visible_index == target {
			return node, true
		}
		visible_index += 1
	}
	return {}, false
}

@(private)
model_visible_index :: proc(model: ^Model, id: Node_ID) -> int {
	visible_index: int
	for node in model.nodes[:model.count] {
		if !model_node_visible(model, node.definition.id) {
			continue
		}
		if node.definition.id == id {
			return visible_index
		}
		visible_index += 1
	}
	return -1
}
