// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"
import "../editor_session"
import "../interactive_session"
import "../project"

/* Terminal_Context_Purpose identifies the command policy requesting a working context. */
Terminal_Context_Purpose :: enum u8 {
	Invalid,
	Default,
	Here,
	Project,
}

/* Terminal_Context_Resolution distinguishes a resolved context from deliberate Project selection. */
Terminal_Context_Resolution :: enum u8 {
	Invalid,
	Resolved,
	Project_Selection_Required,
}

/* Terminal_Context_Source records the editor context that selected the directory. */
Terminal_Context_Source :: enum u8 {
	Invalid,
	Home,
	Resource,
	Project,
}

/* Terminal_Shell_Source records the configuration layer that selected the executable. */
Terminal_Shell_Source :: enum u8 {
	Invalid,
	Environment,
	Global,
	Workspace,
}

/* Terminal_Context_Scope owns the default-session identity boundary. */
Terminal_Context_Scope :: enum u8 {
	Invalid,
	Instance,
	Workspace,
}

/* Terminal_Context_Failure_Code identifies a rejected context without path prompting. */
Terminal_Context_Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Session,
	No_Directory,
	Invalid_Directory,
	No_Shell,
	Invalid_Shell,
}

/* Terminal_Context_Failure preserves the editor-session failure when inspection fails. */
Terminal_Context_Failure :: struct {
	code:    Terminal_Context_Failure_Code,
	session: editor_session.Failure_Context,
}

/* Terminal_Context_Request supplies policy without transferring borrowed configuration. */
Terminal_Context_Request :: struct {
	purpose:         Terminal_Context_Purpose,
	global_shell:    string,
	workspace_shell: string,
}

/* Terminal_Working_Context owns copied process inputs and optional editor provenance. */
Terminal_Working_Context :: struct {
	directory:        [interactive_session.MAX_DIRECTORY_BYTES]u8,
	directory_length: u16,
	shell:            [interactive_session.MAX_DIRECTORY_BYTES]u8,
	shell_length:     u16,
	source:           Terminal_Context_Source,
	shell_source:     Terminal_Shell_Source,
	scope:            Terminal_Context_Scope,
	workspace:        editor_session.Workspace_Descriptor,
	project:          project.Project_Handle,
}

/* terminal_context_resolve copies and validates one active editor working context. */
terminal_context_resolve :: proc(
	commands: ^Command_Context,
	request: Terminal_Context_Request,
) -> (resolved: Terminal_Working_Context, resolution: Terminal_Context_Resolution, failure: Terminal_Context_Failure) {
	if commands == nil || commands.session_owner == nil ||
	   request.purpose == .Invalid {
		return {}, .Invalid, {code = .Invalid_Request}
	}
	workspace, workspace_ok, workspace_failure := editor_session.session_active_workspace(
		commands.session_owner,
		commands.session_handle,
	)
	if !workspace_ok do return {}, .Invalid, {code = .Session, session = workspace_failure}
	resolved.scope = .Instance
	if workspace.active {
		resolved.scope = .Workspace
		resolved.workspace = workspace.descriptor
	}
	descriptors, descriptors_ok, descriptors_failure := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !descriptors_ok do return {}, .Invalid, {code = .Session, session = descriptors_failure}
	defer editor_session.descriptor_batch_close(&descriptors)
	resource_directory, resource_path := terminal_context_active_resource(descriptors.descriptors)

	active_project, project_ok, project_failure := editor_session.session_active_project(
		commands.session_owner,
		commands.session_handle,
	)
	if !project_ok do return {}, .Invalid, {code = .Session, session = project_failure}
	roots, roots_ok, roots_failure := editor_session.session_roots(
		commands.session_owner,
		commands.session_handle,
	)
	if !roots_ok do return {}, .Invalid, {code = .Session, session = roots_failure}
	defer editor_session.root_batch_close(&roots)
	active_handle := project.Project_Handle{}
	if active_project.active do active_handle = active_project.descriptor.handle
	project_directory, project_handle, project_resolution := terminal_context_select_project_root(
		roots.descriptors,
		resource_path,
		active_handle,
	)

	directory := ""
	source := Terminal_Context_Source.Invalid
	switch request.purpose {
	case .Here:
		directory = resource_directory
		source = .Resource
	case .Project:
		if project_resolution == .Project_Selection_Required {
			return {}, .Project_Selection_Required, {}
		}
		directory = project_directory
		source = .Project
		resolved.project = project_handle
	case .Default:
		if len(resource_directory) > 0 {
			directory = resource_directory
			source = .Resource
		} else if project_resolution == .Resolved {
			directory = project_directory
			source = .Project
			resolved.project = project_handle
		} else {
			directory = commands.home_directory
			source = .Home
		}
	case .Invalid:
		return {}, .Invalid, {code = .Invalid_Request}
	}
	if len(directory) == 0 do return {}, .Invalid, {code = .No_Directory}
	if !terminal_context_path_valid(directory) || !os.is_directory(directory) {
		return {}, .Invalid, {code = .Invalid_Directory}
	}
	global_shell := request.global_shell
	if len(global_shell) == 0 {
		global_shell = terminal_configuration_global_shell(commands.terminal_configuration)
	}
	workspace_shell := request.workspace_shell
	if workspace.active && len(workspace_shell) == 0 {
		workspace_settings, configured := terminal_configuration_workspace_settings(
			commands.terminal_configuration, workspace.descriptor.id,
		)
		if configured {
			workspace_shell = string(workspace_settings.shell[:workspace_settings.shell_length])
		}
	}
	shell, shell_source := terminal_context_select_shell(
		workspace.active,
		global_shell,
		workspace_shell,
	)
	if len(shell) == 0 do return {}, .Invalid, {code = .No_Shell}
	if !terminal_context_path_valid(shell) || !os.is_file(shell) {
		return {}, .Invalid, {code = .Invalid_Shell}
	}
	resolved.directory_length = u16(copy(resolved.directory[:], transmute([]u8)directory))
	resolved.shell_length = u16(copy(resolved.shell[:], transmute([]u8)shell))
	resolved.source = source
	resolved.shell_source = shell_source
	return resolved, .Resolved, {}
}

/* terminal_context_directory borrows the copied directory for immediate process assembly. */
terminal_context_directory :: proc(ctx: ^Terminal_Working_Context) -> string {
	if ctx == nil do return ""
	return string(ctx.directory[:ctx.directory_length])
}

/* terminal_context_shell borrows the copied executable for immediate process assembly. */
terminal_context_shell :: proc(ctx: ^Terminal_Working_Context) -> string {
	if ctx == nil do return ""
	return string(ctx.shell[:ctx.shell_length])
}

@(private)
terminal_context_active_resource :: proc(
	descriptors: []editor_session.Entry_Descriptor,
) -> (directory, path: string) {
	for descriptor in descriptors {
		if !descriptor.active do continue
		if descriptor.kind == .Terminal {
			return descriptor.terminal.working_context, descriptor.terminal.working_context
		}
		if descriptor.kind == .Text && descriptor.association == .Document {
			return filepath.dir(descriptor.selection_label), descriptor.selection_label
		}
		return "", ""
	}
	return "", ""
}

@(private)
terminal_context_select_project_root :: proc(
	roots: []editor_session.Root_Descriptor,
	resource_path: string,
	active: project.Project_Handle,
) -> (directory: string, handle: project.Project_Handle, resolution: Terminal_Context_Resolution) {
	for root in roots {
		if root.kind != .Project || !terminal_context_path_contains(root.path, resource_path) do continue
		if len(root.path) > len(directory) {
			directory = root.path
			handle = root.project
		}
	}
	if len(directory) > 0 do return directory, handle, .Resolved
	active_count := 0
	for root in roots {
		if root.kind != .Project || root.project != active do continue
		active_count += 1
		directory = root.path
		handle = root.project
	}
	if active_count == 1 do return directory, handle, .Resolved
	return "", {}, .Project_Selection_Required
}

@(private)
terminal_context_select_shell :: proc(
	workspace_active: bool,
	global_shell, workspace_shell: string,
) -> (string, Terminal_Shell_Source) {
	if workspace_active && len(workspace_shell) > 0 do return workspace_shell, .Workspace
	if len(global_shell) > 0 do return global_shell, .Global
	return os.get_env("SHELL", context.temp_allocator), .Environment
}

@(private)
terminal_context_path_contains :: proc(root, candidate: string) -> bool {
	if len(root) == 0 || len(candidate) == 0 do return false
	if root == candidate do return true
	if root == "/" do return strings.has_prefix(candidate, "/")
	return len(candidate) > len(root) && strings.has_prefix(candidate, root) && candidate[len(root)] == '/'
}

@(private)
terminal_context_path_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= interactive_session.MAX_DIRECTORY_BYTES &&
	       value[0] == '/' && utf8.valid_string(value) && strings.index_byte(value, 0) < 0
}
