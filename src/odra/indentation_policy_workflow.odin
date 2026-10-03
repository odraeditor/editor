// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../document"
import "../editor"
import "../editor_session"
import "../indentation"
import "../interaction"
import "../project"
import editor_view "../view"

/* command_context_sync_indentation_policy resolves and copies policy into one active view. */
@(private)
command_context_sync_indentation_policy :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
) {
	if commands == nil || buffer == nil || view_registry == nil ||
	   commands.indentation_registry == nil || !commands.indentation_registry.initialized {
		return
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return
	resolution := indentation.Resolution_Context {
		profile_id = indentation.Profile_ID(1),
		buffer_id = u64(stats.buffer_id),
	}
	if profile, _, selected := interaction.profile_activation_selection(commands.profile_activation); selected {
		resolution.profile_id = indentation.Profile_ID(profile.id)
	}

	entry: editor_session.Entry_Borrow
	entry_ok := false
	if commands.session_owner != nil && commands.current_entry != (editor_session.Entry_Handle{}) {
		access, accessed, _ := editor_session.session_entry_access(
			commands.session_owner,
			commands.current_entry,
		)
		if accessed {
			entry, entry_ok, _ = editor_session.entry_access_borrow(access)
		}
	}
	if entry_ok && entry.buffer != buffer {
		entry_ok = false
	}
	if entry_ok && entry.has_document && entry.document != nil {
		status, status_ok, _ := document.document_status(entry.document)
		if status_ok && status.has_target do resolution.path = status.target_path
	}
	if entry_ok && commands.syntax_workflow != nil {
		association, associated, _ := syntax_workflow_entry_language_association(
			commands.syntax_workflow,
			entry,
		)
		if associated {
			resolution.language = string(
				association.language.name.bytes[:association.language.name.length],
			)
		}
	}
	if commands.session_owner != nil {
		active, active_ok, _ := editor_session.session_active_project(
			commands.session_owner,
			commands.session_handle,
		)
		if active_ok && active.active {
			scope, _, scoped, _ := editor_session.session_active_project_buffer_scope(
				commands.session_owner,
				commands.session_handle,
				active.descriptor.handle,
			)
			if scoped && scope == .Project_Owned {
				resolution.project = project.project_durable_id_text(&active.descriptor.durable_id)
				if len(resolution.project) == 0 {
					resolution.project = project.project_name_text(&active.descriptor.name)
				}
			}
		}
	}

	effective, resolved, _ := indentation.resolve(commands.indentation_registry, resolution)
	if !resolved do return
	_, _ = editor_view.set_indentation_policy(view_registry, view, effective)
}
