// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../language_interaction"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import "../layout"
import "../project"
import "../status_bar"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

@(private)
Status_Bar_Session_Context :: struct {
	project:          editor_session.Active_Project_Snapshot,
	workspace:        editor_session.Active_Workspace_Snapshot,
	project_buffers:  editor_session.Project_Buffer_Batch,
	roots:            editor_session.Root_Batch,
	project_observed: bool,
	roots_observed:   bool,
}

@(private)
status_bar_session_context_prepare :: proc(
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
) -> (observation: Status_Bar_Session_Context, ok: bool) {
	if session_owner == nil do return {}, false
	active_project, project_ok, _ := editor_session.session_active_project(session_owner, session_handle)
	if !project_ok do return {}, false
	active_workspace, workspace_ok, _ := editor_session.session_active_workspace(session_owner, session_handle)
	if !workspace_ok do return {}, false
	observation.project = active_project
	observation.workspace = active_workspace
	roots, roots_ok, _ := editor_session.session_roots(session_owner, session_handle)
	if !roots_ok do return {}, false
	observation.roots = roots
	observation.roots_observed = true
	if active_project.active {
		classified, classified_ok, _ := editor_session.session_classify_project_buffers(
			session_owner,
			session_handle,
			active_project.descriptor.handle,
			context.temp_allocator,
		)
		if !classified_ok do return {}, false
		observation.project_buffers = classified
		observation.project_observed = true
	}
	return observation, true
}

@(private)
status_bar_session_context_close :: proc(observation: ^Status_Bar_Session_Context) {
	if observation == nil do return
	if observation.project_observed {
		editor_session.project_buffer_batch_close(&observation.project_buffers)
	}
	if observation.roots_observed {
		editor_session.root_batch_close(&observation.roots)
	}
	observation^ = {}
}

@(private)
command_context_global_context_overlay :: proc(
	commands: ^Command_Context,
) -> (label, text: string, ok: bool) {
	if commands == nil || commands.session_owner == nil {
		return "", "", false
	}
	active_project, project_ok, _ := editor_session.session_active_project(
		commands.session_owner,
		commands.session_handle,
	)
	if !project_ok do return "", "", false
	active_workspace, workspace_ok, _ := editor_session.session_active_workspace(
		commands.session_owner,
		commands.session_handle,
	)
	if !workspace_ok do return "", "", false

	path := ""
	access, access_ok, _ := editor_session.session_active_entry_access(
		commands.session_owner,
		commands.session_handle,
	)
	if access_ok {
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if borrowed && entry.has_document && entry.document != nil {
			status, inspected, _ := document.document_status(entry.document)
			if inspected && status.has_target do path = status.target_path
		}
	}

	cursor := 0
	part_count := 0
	if active_workspace.active {
		workspace_name := editor_session.workspace_name_text(&active_workspace.descriptor.name)
		part := fmt.bprintf(commands.overlay_text[cursor:], "Workspace: %s", workspace_name)
		cursor += len(part)
		part_count += 1
	}
	if active_project.active {
		separator := " · " if part_count > 0 else ""
		project_name := project.project_name_text(&active_project.descriptor.name)
		part := fmt.bprintf(commands.overlay_text[cursor:], "%sProject: %s", separator, project_name)
		cursor += len(part)
		part_count += 1
	}
	if len(path) > 0 {
		separator := " · " if part_count > 0 else ""
		directory := filepath.base(filepath.dir(path))
		filename := filepath.base(path)
		part := fmt.bprintf(commands.overlay_text[cursor:], "%s%s/%s", separator, directory, filename)
		cursor += len(part)
		part_count += 1
	}
	if part_count == 0 do return "", "", false
	return "", string(commands.overlay_text[:cursor]), true
}

@(private)
status_bar_buffer_labels :: proc(
	descriptor: editor_session.Entry_Descriptor,
	session_context: ^Status_Bar_Session_Context,
) -> (label, contextual: string) {
	label = descriptor.selection_label
	if descriptor.association != .Document do return
	label = filepath.base(descriptor.selection_label)
	if session_context == nil || !session_context.project.active || !session_context.roots_observed {
		return
	}
	project_handle := session_context.project.descriptor.handle
	for root in session_context.roots.descriptors {
		if root.kind != .Project || root.project != project_handle do continue
		path := descriptor.selection_label
		if !strings.has_prefix(path, root.path) || len(path) <= len(root.path) ||
		   path[len(root.path)] != '/' {
			continue
		}
		relative := path[len(root.path) + 1:]
		directory := filepath.dir(relative)
		if directory != "." && directory != "/" &&
		   len(directory) < status_bar.MAX_SEGMENT_TEXT_BYTES {
			contextual = directory
		}
		return
	}
	return
}

@(private)
status_bar_programmable_definitions :: proc(
	commands: ^Command_Context,
) -> (definitions: [status_bar.MAX_PROGRAMMABLE_SEGMENTS]status_bar.Segment_Definition, count: int, ok: bool) {
	if commands == nil do return {}, 0, false
	inspection, inspected, _ := status_bar.registry_inspect(&commands.status_bar_registry)
	if !inspected || inspection.usage.segments > status_bar.MAX_PROGRAMMABLE_SEGMENTS {
		return {}, 0, false
	}
	for index: u16 = 0; index < inspection.usage.segments; index += 1 {
		segment, found, _ := status_bar.registry_segment_at(&commands.status_bar_registry, index)
		if !found do return {}, 0, false
		definitions[count] = segment.definition
		count += 1
	}
	return definitions, count, true
}

@(private)
status_bar_factory_actions :: proc(
	commands: ^Command_Context,
	observation: status_bar.Context_Observation,
) -> status_bar.Factory_Actions {
	if commands == nil || commands.registry == nil do return {}
	actions: status_bar.Factory_Actions
	actions.buffer_identity = status_bar_command_reference(commands.registry, "list-buffers")
	if observation.project.present {
		actions.project = status_bar_command_reference(commands.registry, "project-command-menu")
		actions.project_inspection = status_bar_command_reference(commands.registry, "describe-project")
	}
	if observation.language.present {
		actions.editing_context = status_bar_command_reference(commands.registry, "describe-language-state")
	}
	if observation.diagnostics.present {
		diagnostics := status_bar_command_reference(commands.registry, "list-language-diagnostics")
		actions.alert = diagnostics
		actions.editing_context_secondary = diagnostics
	}
	return actions
}

@(private)
status_bar_command_reference :: proc(
	registry: ^interaction.Command_Registry,
	name: string,
) -> status_bar.Command_Reference {
	handle, found, _ := interaction.command_lookup(registry, name)
	if !found do return {}
	return {
		registry_generation = u64(handle.registry_generation),
		slot = handle.slot,
		entry_generation = handle.entry_generation,
	}
}

@(private)
status_bar_observe_pane_context :: proc(
	commands: ^Command_Context,
	session_context: ^Status_Bar_Session_Context,
	entry: editor_session.Entry_Borrow,
	descriptor: editor_session.Entry_Descriptor,
	node: layout.Node_Descriptor,
	stats: editor.Buffer_Stats,
	presentation: status_bar.Generation,
	service: Language_Service_Visible_Observation,
) -> (observation: status_bar.Context_Observation, ok: bool) {
	if commands == nil || session_context == nil || presentation == status_bar.Generation(0) ||
	   descriptor.graph.buffer_id != stats.buffer_id || node.buffer_id != stats.buffer_id ||
	   node.pane.pane_id == layout.Pane_ID(0) || node.pane.slot_generation == 0 {
		return {}, false
	}
	observation = status_bar.Context_Observation {
		generation = presentation,
		buffer_identity = u64(stats.buffer_id),
		buffer_revision = u64(stats.revision),
		pane_identity = u64(node.pane.pane_id),
		pane_generation = u64(node.pane.slot_generation),
	}
	profile, interaction_state, interaction_ok := interaction.profile_activation_selection(
		commands.profile_activation,
	)
	if interaction_ok {
		catalog, catalog_ok := interaction.profile_activation_catalog(commands.profile_activation)
		if !catalog_ok do return {}, false
		profile_name := ""
		for candidate in catalog.profiles do if candidate.identity == profile {
			profile_name = candidate.name
			break
		}
		if profile_name == "modal" {
			profile_label, profile_label_ok := status_bar.context_label_copy(profile_name)
			state_label, state_label_ok := status_bar.context_label_copy(interaction_state.name)
			if !profile_label_ok || !state_label_ok do return {}, false
			observation.interaction = {
				present = true,
				stamp = status_bar_context_stamp(
					observation,
					u64(profile.id),
					u64(commands.profile_activation.generation),
				),
				profile = profile_label,
				state = state_label,
				modal = true,
			}
		}
	}

	if entry.has_document && entry.document != nil {
		document_status, inspected, _ := document.document_status(entry.document)
		if !inspected || document_status.buffer_id != stats.buffer_id do return {}, false
		encoding := ""
		switch document_status.encoding {
		case .UTF8: encoding = "UTF-8 LF"
		case .Invalid: return {}, false
		}
		encoding_label, encoding_ok := status_bar.context_label_copy(encoding)
		if !encoding_ok do return {}, false
		stamp := status_bar_context_stamp(
			observation,
			u64(document_status.document_id),
			max(u64(document_status.document_id), 1),
		)
		observation.document = {present = true, stamp = stamp, encoding = encoding_label}
	}

	if service.present {
		stamp := status_bar_context_stamp(
			observation,
			service.binding_identity,
			service.diagnostic_generation,
		)
		if service.errors > 0 || service.warnings > 0 {
			observation.diagnostics = {
				present = true,
				stamp = stamp,
				errors = service.errors,
				warnings = service.warnings,
			}
		}
	}

	language_inspection, _, _, language_ok := syntax_workflow_inspect_buffer(
		commands.syntax_workflow,
		entry.buffer,
	)
	language_context := language_service_workflow_project_language_context(
		language_inspection,
		language_ok,
		service,
	)
	if language_context.present {
		identity := language_context.language
		language_name := string(identity.name.bytes[:identity.name.length])
		language_label, label_ok := status_bar.context_label_copy(language_name)
		if !label_ok do return {}, false
		service_health := status_bar.Language_Service_Health.None
		operation_health := status_bar.Language_Operation_Health.None
		switch language_context.service_health {
		case .None:         service_health = .None
		case .Initializing: service_health = .Initializing
		case .Active:       service_health = .Active
		case .Failed:       service_health = .Failed
		}
		if operation, operation_present := language_interaction.workflow_snapshot(
			&commands.language_interaction_workflow,
		); operation_present {
			switch operation.health {
			case .Busy:   operation_health = .Busy
			case .Failed: operation_health = .Failed
			case .Idle:
			}
		}
		observation.language = {
			present = true,
			stamp = status_bar_context_stamp(
				observation,
				u64(identity.id),
				language_context.owner_generation,
			),
			name = language_label,
			service_health = service_health,
			operation_health = operation_health,
		}
	}

	project_owned := false
	if session_context.project.active && session_context.project_observed {
		for candidate in session_context.project_buffers.descriptors {
			if candidate.graph.entry == descriptor.graph.entry {
				project_owned = candidate.scope == .Project_Owned
				break
			}
		}
		if project_owned {
			handle := session_context.project.descriptor.handle
			project_name, name_ok := status_bar.context_label_copy(
				project.project_name_text(&session_context.project.descriptor.name),
			)
			if !name_ok do return {}, false
			observation.project = {
				present = true,
				stamp = status_bar_context_stamp(
					observation,
					u64(handle.id),
					u64(handle.generation),
				),
				name = project_name,
			}
		}
	}

	if session_context.workspace.active && project_owned {
		workspace := session_context.workspace.descriptor
		workspace_name, name_ok := status_bar.context_label_copy(
			editor_session.workspace_name_text(&workspace.name),
		)
		if !name_ok do return {}, false
		observation.workspace = {
			present = true,
			stamp = status_bar_context_stamp(
				observation,
				u64(workspace.root_set),
				workspace.generation,
			),
			name = workspace_name,
		}
	}

	policy := status_bar.Pane_Policy.Ordinary
	switch node.dedication {
	case .None: policy = .Ordinary
	case .Soft: policy = .Soft_Dedicated
	case .Hard: policy = .Hard_Dedicated
	}
	if policy != .Ordinary {
		observation.pane = {
			present = true,
			stamp = status_bar_context_stamp(
				observation,
				u64(node.pane.pane_id),
				u64(node.pane.slot_generation),
			),
			policy = policy,
		}
	}
	return observation, status_bar.context_observation_validate(observation, presentation)
}

@(private)
status_bar_context_stamp :: proc(
	observation: status_bar.Context_Observation,
	owner_identity: u64,
	owner_generation: u64,
) -> status_bar.Source_Stamp {
	return status_bar.Source_Stamp {
		presentation = observation.generation,
		buffer_identity = observation.buffer_identity,
		buffer_revision = observation.buffer_revision,
		pane_identity = observation.pane_identity,
		pane_generation = observation.pane_generation,
		owner_identity = owner_identity,
		owner_generation = owner_generation,
	}
}
