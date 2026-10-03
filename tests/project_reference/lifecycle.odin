// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project_reference provides the independent Dir, Project, and Workspace lifecycle oracle.
package project_reference

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

Lifecycle_Project_Handle :: struct {
	id:         u64,
	generation: u64,
}

Lifecycle_Workspace_Handle :: struct {
	id:         u64,
	generation: u64,
}

Lifecycle_Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Value,
	Invalid_Path,
	Invalid_Project,
	Duplicate_Project,
	Duplicate_Project_Root,
	Invalid_Workspace,
	Duplicate_Workspace,
	Duplicate_Workspace_Member,
	Invalid_Workspace_Cardinality,
	Duplicate_Suppression,
	Project_Root,
	Capacity,
	Allocation,
}

Lifecycle_Failure :: struct {
	code:      Lifecycle_Failure_Code,
	project:   Lifecycle_Project_Handle,
	workspace: Lifecycle_Workspace_Handle,
}

Lifecycle_Policy :: struct {
	projects:              int,
	workspaces:            int,
	workspace_members:     int,
	promotion_suppressions: int,
}

Lifecycle_Project_Descriptor :: struct {
	handle: Lifecycle_Project_Handle,
	id:     string,
	name:   string,
	root:   string,
	trust:  Trust,
}

Lifecycle_Workspace_Descriptor :: struct {
	handle:  Lifecycle_Workspace_Handle,
	id:      string,
	name:    string,
	members: []Lifecycle_Project_Handle,
}

@(private)
Lifecycle_Project_Entry :: struct {
	descriptor: Lifecycle_Project_Descriptor,
	live:       bool,
}

@(private)
Lifecycle_Workspace_Entry :: struct {
	descriptor: Lifecycle_Workspace_Descriptor,
	live:       bool,
}

@(private)
Lifecycle_Suppression_Entry :: struct {
	path: string,
	live: bool,
}

Lifecycle_Model :: struct {
	projects:          []Lifecycle_Project_Entry,
	workspaces:        []Lifecycle_Workspace_Entry,
	suppressions:      []Lifecycle_Suppression_Entry,
	project_count:     int,
	workspace_count:   int,
	suppression_count: int,
	generation:        u64,
	policy:            Lifecycle_Policy,
	allocator:         runtime.Allocator,
}

Lifecycle_Legacy_Project :: struct {
	valid: bool,
	roots: []string,
}

Lifecycle_Migration_Summary :: struct {
	source_projects:   int,
	target_projects:   int,
	target_workspaces: int,
	rejected_sources:  int,
}

lifecycle_model_init :: proc(
	policy: Lifecycle_Policy,
	allocator := context.allocator,
) -> (model: Lifecycle_Model, ok: bool) {
	if policy.projects <= 0 || policy.workspaces <= 0 || policy.workspace_members < 1 ||
	   policy.workspace_members > policy.projects || policy.promotion_suppressions <= 0 ||
	   allocator.procedure == nil {
		return {}, false
	}
	projects, projects_error := make([]Lifecycle_Project_Entry, policy.projects, allocator)
	if projects_error != nil {
		return {}, false
	}
	workspaces, workspaces_error := make([]Lifecycle_Workspace_Entry, policy.workspaces, allocator)
	if workspaces_error != nil {
		delete(projects, allocator)
		return {}, false
	}
	suppressions, suppressions_error := make(
		[]Lifecycle_Suppression_Entry,
		policy.promotion_suppressions,
		allocator,
	)
	if suppressions_error != nil {
		delete(workspaces, allocator)
		delete(projects, allocator)
		return {}, false
	}
	return Lifecycle_Model {
		projects = projects,
		workspaces = workspaces,
		suppressions = suppressions,
		generation = 1,
		policy = policy,
		allocator = allocator,
	}, true
}

lifecycle_model_deinit :: proc(model: ^Lifecycle_Model) {
	if model == nil {
		return
	}
	for &entry in model.workspaces {
		if !entry.live {
			continue
		}
		lifecycle_workspace_entry_close(&entry, model.allocator)
	}
	for &entry in model.projects {
		if !entry.live {
			continue
		}
		lifecycle_project_entry_close(&entry, model.allocator)
	}
	for &entry in model.suppressions {
		if entry.live && len(entry.path) > 0 {
			delete(entry.path, model.allocator)
		}
	}
	if model.suppressions != nil do delete(model.suppressions, model.allocator)
	if model.workspaces != nil do delete(model.workspaces, model.allocator)
	if model.projects != nil do delete(model.projects, model.allocator)
	model^ = {}
}

lifecycle_promote :: proc(
	model: ^Lifecycle_Model,
	id, name, root: string,
	trust: Trust = .Untrusted,
) -> (handle: Lifecycle_Project_Handle, ok: bool, failure: Lifecycle_Failure) {
	if !lifecycle_model_ready(model) {
		return {}, false, Lifecycle_Failure{code = .Invalid_Model}
	}
	if !lifecycle_text_valid(id) || !lifecycle_text_valid(name) {
		return {}, false, Lifecycle_Failure{code = .Invalid_Value}
	}
	if !lifecycle_path_valid(root) {
		return {}, false, Lifecycle_Failure{code = .Invalid_Path}
	}
	for entry in model.projects {
		if !entry.live {
			continue
		}
		if entry.descriptor.id == id {
			return {}, false, Lifecycle_Failure{code = .Duplicate_Project}
		}
		if entry.descriptor.root == root {
			return {}, false, Lifecycle_Failure{code = .Duplicate_Project_Root}
		}
	}
	for index in 0 ..< len(model.projects) {
		entry := &model.projects[index]
		if entry.live {
			continue
		}
		owned_id, id_error := strings.clone(id, model.allocator)
		if id_error != nil {
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		owned_name, name_error := strings.clone(name, model.allocator)
		if name_error != nil {
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		owned_root, root_error := strings.clone(root, model.allocator)
		if root_error != nil {
			delete(owned_name, model.allocator)
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		generation := entry.descriptor.handle.generation + 1
		if generation == 0 {
			delete(owned_root, model.allocator)
			delete(owned_name, model.allocator)
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Capacity}
		}
		handle = Lifecycle_Project_Handle{id = u64(index + 1), generation = generation}
		entry^ = Lifecycle_Project_Entry {
			descriptor = {
				handle = handle,
				id = owned_id,
				name = owned_name,
				root = owned_root,
				trust = trust,
			},
			live = true,
		}
		model.project_count += 1
		model.generation += 1
		return handle, true, {}
	}
	return {}, false, Lifecycle_Failure{code = .Capacity}
}

lifecycle_project_by_root :: proc(
	model: ^Lifecycle_Model,
	root: string,
) -> (descriptor: Lifecycle_Project_Descriptor, ok: bool) {
	if !lifecycle_model_ready(model) || !lifecycle_path_valid(root) {
		return {}, false
	}
	for entry in model.projects {
		if entry.live && entry.descriptor.root == root {
			return entry.descriptor, true
		}
	}
	return {}, false
}

lifecycle_project_descriptor :: proc(
	model: ^Lifecycle_Model,
	handle: Lifecycle_Project_Handle,
) -> (descriptor: Lifecycle_Project_Descriptor, ok: bool) {
	entry, found := lifecycle_project_entry(model, handle)
	if !found {
		return {}, false
	}
	return entry.descriptor, true
}

lifecycle_suppress :: proc(
	model: ^Lifecycle_Model,
	root: string,
) -> (ok: bool, failure: Lifecycle_Failure) {
	if !lifecycle_model_ready(model) {
		return false, Lifecycle_Failure{code = .Invalid_Model}
	}
	if !lifecycle_path_valid(root) {
		return false, Lifecycle_Failure{code = .Invalid_Path}
	}
	_, project_exists := lifecycle_project_by_root(model, root)
	if project_exists {
		return false, Lifecycle_Failure{code = .Project_Root}
	}
	for entry in model.suppressions {
		if entry.live && entry.path == root {
			return false, Lifecycle_Failure{code = .Duplicate_Suppression}
		}
	}
	for &entry in model.suppressions {
		if entry.live {
			continue
		}
		owned, allocation_error := strings.clone(root, model.allocator)
		if allocation_error != nil {
			return false, Lifecycle_Failure{code = .Allocation}
		}
		entry = Lifecycle_Suppression_Entry{path = owned, live = true}
		model.suppression_count += 1
		model.generation += 1
		return true, {}
	}
	return false, Lifecycle_Failure{code = .Capacity}
}

lifecycle_unsuppress :: proc(model: ^Lifecycle_Model, root: string) -> bool {
	if !lifecycle_model_ready(model) || !lifecycle_path_valid(root) {
		return false
	}
	for &entry in model.suppressions {
		if !entry.live || entry.path != root {
			continue
		}
		delete(entry.path, model.allocator)
		entry = {}
		model.suppression_count -= 1
		model.generation += 1
		return true
	}
	return false
}

lifecycle_suppressed :: proc(model: ^Lifecycle_Model, root: string) -> bool {
	if !lifecycle_model_ready(model) || !lifecycle_path_valid(root) {
		return false
	}
	for entry in model.suppressions {
		if entry.live && entry.path == root {
			return true
		}
	}
	return false
}

lifecycle_workspace_create :: proc(
	model: ^Lifecycle_Model,
	id, name: string,
	members: []Lifecycle_Project_Handle,
) -> (handle: Lifecycle_Workspace_Handle, ok: bool, failure: Lifecycle_Failure) {
	if !lifecycle_model_ready(model) {
		return {}, false, Lifecycle_Failure{code = .Invalid_Model}
	}
	if !lifecycle_text_valid(id) || !lifecycle_text_valid(name) {
		return {}, false, Lifecycle_Failure{code = .Invalid_Value}
	}
	if len(members) < 1 || len(members) > model.policy.workspace_members {
		return {}, false, Lifecycle_Failure{code = .Invalid_Workspace_Cardinality}
	}
	for entry in model.workspaces {
		if entry.live && (entry.descriptor.id == id || entry.descriptor.name == name) {
			return {}, false, Lifecycle_Failure{code = .Duplicate_Workspace}
		}
	}
	for left_index in 0 ..< len(members) {
		if _, valid := lifecycle_project_entry(model, members[left_index]); !valid {
			return {}, false, Lifecycle_Failure{
				code = .Invalid_Project,
				project = members[left_index],
			}
		}
		for right_index in left_index + 1 ..< len(members) {
			if members[left_index] == members[right_index] {
				return {}, false, Lifecycle_Failure{
					code = .Duplicate_Workspace_Member,
					project = members[left_index],
				}
			}
		}
	}
	for index in 0 ..< len(model.workspaces) {
		entry := &model.workspaces[index]
		if entry.live {
			continue
		}
		owned_id, id_error := strings.clone(id, model.allocator)
		if id_error != nil {
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		owned_name, name_error := strings.clone(name, model.allocator)
		if name_error != nil {
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		owned_members, members_error := make([]Lifecycle_Project_Handle, len(members), model.allocator)
		if members_error != nil {
			delete(owned_name, model.allocator)
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Allocation}
		}
		copy(owned_members, members)
		generation := entry.descriptor.handle.generation + 1
		if generation == 0 {
			delete(owned_members, model.allocator)
			delete(owned_name, model.allocator)
			delete(owned_id, model.allocator)
			return {}, false, Lifecycle_Failure{code = .Capacity}
		}
		handle = Lifecycle_Workspace_Handle{id = u64(index + 1), generation = generation}
		entry^ = Lifecycle_Workspace_Entry {
			descriptor = {
				handle = handle,
				id = owned_id,
				name = owned_name,
				members = owned_members,
			},
			live = true,
		}
		model.workspace_count += 1
		model.generation += 1
		return handle, true, {}
	}
	return {}, false, Lifecycle_Failure{code = .Capacity}
}

lifecycle_workspace_descriptor :: proc(
	model: ^Lifecycle_Model,
	handle: Lifecycle_Workspace_Handle,
) -> (descriptor: Lifecycle_Workspace_Descriptor, ok: bool) {
	entry, found := lifecycle_workspace_entry(model, handle)
	if !found {
		return {}, false
	}
	return entry.descriptor, true
}

lifecycle_plan_migration :: proc(
	sources: []Lifecycle_Legacy_Project,
	project_limit, workspace_limit: int,
) -> (summary: Lifecycle_Migration_Summary, ok: bool) {
	if project_limit <= 0 || workspace_limit <= 0 {
		return {}, false
	}
	summary.source_projects = len(sources)
	for source_index in 0 ..< len(sources) {
		source := sources[source_index]
		if !source.valid || len(source.roots) == 0 {
			summary.rejected_sources += 1
			continue
		}
		if !lifecycle_legacy_source_valid(source) {
			summary.rejected_sources += 1
			continue
		}
		if len(source.roots) > 1 {
			summary.target_workspaces += 1
		}
		for root_index in 0 ..< len(source.roots) {
			root := source.roots[root_index]
			seen := false
			for previous_source_index in 0 ..= source_index {
				previous := sources[previous_source_index]
				limit := len(previous.roots)
				if previous_source_index == source_index {
					limit = root_index
				}
				for previous_root_index in 0 ..< limit {
					if lifecycle_legacy_source_valid(previous) &&
					   previous.roots[previous_root_index] == root {
						seen = true
						break
					}
				}
				if seen do break
			}
			if !seen {
				summary.target_projects += 1
			}
		}
	}
	return summary,
	       summary.target_projects <= project_limit &&
	       summary.target_workspaces <= workspace_limit
}

lifecycle_model_validate :: proc(model: ^Lifecycle_Model) -> bool {
	if !lifecycle_model_ready(model) || model.generation == 0 {
		return false
	}
	projects := 0
	for left_index in 0 ..< len(model.projects) {
		left := model.projects[left_index]
		if !left.live {
			continue
		}
		projects += 1
		if left.descriptor.handle.id != u64(left_index + 1) ||
		   left.descriptor.handle.generation == 0 || !lifecycle_text_valid(left.descriptor.id) ||
		   !lifecycle_text_valid(left.descriptor.name) || !lifecycle_path_valid(left.descriptor.root) {
			return false
		}
		for right_index in left_index + 1 ..< len(model.projects) {
			right := model.projects[right_index]
			if right.live &&
			   (left.descriptor.id == right.descriptor.id || left.descriptor.root == right.descriptor.root) {
				return false
			}
		}
	}
	workspaces := 0
	for left_index in 0 ..< len(model.workspaces) {
		left := model.workspaces[left_index]
		if !left.live {
			continue
		}
		workspaces += 1
		if left.descriptor.handle.id != u64(left_index + 1) ||
		   left.descriptor.handle.generation == 0 || !lifecycle_text_valid(left.descriptor.id) ||
		   !lifecycle_text_valid(left.descriptor.name) || len(left.descriptor.members) < 1 ||
		   len(left.descriptor.members) > model.policy.workspace_members {
			return false
		}
		for member_index in 0 ..< len(left.descriptor.members) {
			if _, valid := lifecycle_project_entry(model, left.descriptor.members[member_index]); !valid {
				return false
			}
			for other_index in member_index + 1 ..< len(left.descriptor.members) {
				if left.descriptor.members[member_index] == left.descriptor.members[other_index] {
					return false
				}
			}
		}
		for right_index in left_index + 1 ..< len(model.workspaces) {
			right := model.workspaces[right_index]
			if right.live &&
			   (left.descriptor.id == right.descriptor.id || left.descriptor.name == right.descriptor.name) {
				return false
			}
		}
	}
	suppressions := 0
	for left_index in 0 ..< len(model.suppressions) {
		left := model.suppressions[left_index]
		if !left.live {
			continue
		}
		suppressions += 1
		if !lifecycle_path_valid(left.path) {
			return false
		}
		if _, promoted := lifecycle_project_by_root(model, left.path); promoted {
			return false
		}
		for right_index in left_index + 1 ..< len(model.suppressions) {
			right := model.suppressions[right_index]
			if right.live && left.path == right.path {
				return false
			}
		}
	}
	return projects == model.project_count && workspaces == model.workspace_count &&
	       suppressions == model.suppression_count
}

@(private)
lifecycle_model_ready :: proc(model: ^Lifecycle_Model) -> bool {
	return model != nil && model.projects != nil && model.workspaces != nil &&
	       model.suppressions != nil && model.allocator.procedure != nil
}

@(private)
lifecycle_project_entry :: proc(
	model: ^Lifecycle_Model,
	handle: Lifecycle_Project_Handle,
) -> (^Lifecycle_Project_Entry, bool) {
	if !lifecycle_model_ready(model) || handle.id == 0 || handle.generation == 0 ||
	   handle.id > u64(len(model.projects)) {
		return nil, false
	}
	entry := &model.projects[int(handle.id - 1)]
	return entry, entry.live && entry.descriptor.handle == handle
}

@(private)
lifecycle_workspace_entry :: proc(
	model: ^Lifecycle_Model,
	handle: Lifecycle_Workspace_Handle,
) -> (^Lifecycle_Workspace_Entry, bool) {
	if !lifecycle_model_ready(model) || handle.id == 0 || handle.generation == 0 ||
	   handle.id > u64(len(model.workspaces)) {
		return nil, false
	}
	entry := &model.workspaces[int(handle.id - 1)]
	return entry, entry.live && entry.descriptor.handle == handle
}

@(private)
lifecycle_project_entry_close :: proc(entry: ^Lifecycle_Project_Entry, allocator: runtime.Allocator) {
	if len(entry.descriptor.root) > 0 do delete(entry.descriptor.root, allocator)
	if len(entry.descriptor.name) > 0 do delete(entry.descriptor.name, allocator)
	if len(entry.descriptor.id) > 0 do delete(entry.descriptor.id, allocator)
	entry^ = {}
}

@(private)
lifecycle_workspace_entry_close :: proc(entry: ^Lifecycle_Workspace_Entry, allocator: runtime.Allocator) {
	if entry.descriptor.members != nil do delete(entry.descriptor.members, allocator)
	if len(entry.descriptor.name) > 0 do delete(entry.descriptor.name, allocator)
	if len(entry.descriptor.id) > 0 do delete(entry.descriptor.id, allocator)
	entry^ = {}
}

@(private)
lifecycle_text_valid :: proc(value: string) -> bool {
	return len(value) > 0 && utf8.valid_string(value) && strings.index_byte(value, 0) < 0
}

@(private)
lifecycle_path_valid :: proc(value: string) -> bool {
	return lifecycle_text_valid(value) && value[0] == '/'
}

@(private)
lifecycle_legacy_source_valid :: proc(source: Lifecycle_Legacy_Project) -> bool {
	if !source.valid || len(source.roots) == 0 {
		return false
	}
	for root in source.roots {
		if !lifecycle_path_valid(root) {
			return false
		}
	}
	return true
}
