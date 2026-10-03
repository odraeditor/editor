// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../document"
import "../editor_session"
import "../interaction"

/* Buffer_Session_Completion classifies one successful file or buffer selection. */
Buffer_Session_Completion :: enum u8 {
	Invalid,
	Opened,
	Reused,
	Created,
	Activated,
	Already_Active,
}

/* Buffer_Session_Context supplies checked session authority for one native command. */
Buffer_Session_Context :: struct {
	session:       ^editor_session.Session,
	handle:        editor_session.Session_Handle,
	command:       interaction.Command_Handle,
	configuration: editor_session.Entry_Configuration,
}

/* Buffer_Session_Result reports the selected entry and visible target. */
Buffer_Session_Result :: struct {
	completion: Buffer_Session_Completion,
	entry:      editor_session.Entry_Handle,
	visible:    editor_session.Visible_Target,
}

/* Buffer_Kill_Completion distinguishes dirty admission from completed graph release. */
Buffer_Kill_Completion :: enum u8 {
	Invalid,
	Discard_Required,
	Closed,
}

/* Buffer_Kill_Result reports one selected entry closure without borrowing released state. */
Buffer_Kill_Result :: struct {
	completion: Buffer_Kill_Completion,
	closure:    editor_session.Closure_Result,
}

/* buffer_session_find_file opens a local target or selects its existing canonical buffer. */
buffer_session_find_file :: proc(
	request: Buffer_Session_Context,
	path: string,
) -> (result: Buffer_Session_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   len(path) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	admission, admitted, session_failure := editor_session.session_open_path(
		request.session,
		editor_session.Open_Path_Request {
			session = request.handle,
			path = path,
			encoding = document.Encoding_Policy.UTF8,
			configuration = request.configuration,
		},
	)
	if !admitted {
		return {}, false, buffer_session_failure(request.command, session_failure)
	}
	completion := Buffer_Session_Completion.Opened
	if admission.outcome == .Reused {
		completion = .Reused
	}
	return Buffer_Session_Result {
		completion = completion,
		entry = admission.entry,
		visible = admission.visible,
	}, true, {}
}

/* buffer_session_switch_to_buffer selects an exact label or creates that unassociated name. */
buffer_session_switch_to_buffer :: proc(
	request: Buffer_Session_Context,
	selection_label: string,
) -> (result: Buffer_Session_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   len(selection_label) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	entry, found, find_failure := editor_session.session_find_label(
		request.session,
		request.handle,
		selection_label,
	)
	if find_failure.code != .None {
		return {}, false, buffer_session_failure(request.command, find_failure)
	}
	if found {
		activation, activated, activation_failure := editor_session.session_activate(
			request.session,
			entry,
		)
		if !activated {
			return {}, false, buffer_session_failure(request.command, activation_failure)
		}
		completion := Buffer_Session_Completion.Activated
		if !activation.changed {
			completion = .Already_Active
		}
		return Buffer_Session_Result {
			completion = completion,
			entry = activation.entry,
			visible = activation.visible,
		}, true, {}
	}
	admission, admitted, admission_failure := editor_session.session_create_buffer(
		request.session,
		editor_session.Create_Buffer_Request {
			session = request.handle,
			name = selection_label,
			configuration = request.configuration,
		},
	)
	if !admitted {
		return {}, false, buffer_session_failure(request.command, admission_failure)
	}
	return Buffer_Session_Result {
		completion = .Created,
		entry = admission.entry,
		visible = admission.visible,
	}, true, {}
}

/* buffer_session_kill_buffer resolves one exact label and applies checked close authority. */
buffer_session_kill_buffer :: proc(
	request: Buffer_Session_Context,
	selection_label: string,
	authority := editor_session.Close_Authority.Preserve_Modified,
) -> (result: Buffer_Kill_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   len(selection_label) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	entry, found, find_failure := editor_session.session_find_label(
		request.session,
		request.handle,
		selection_label,
	)
	if find_failure.code != .None {
		return {}, false, buffer_session_failure(request.command, find_failure)
	}
	if !found {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	closure, closed, close_failure := editor_session.session_close_buffer(
		request.session,
		editor_session.Close_Buffer_Request {
			entry = entry,
			authority = authority,
		},
	)
	if !closed {
		return {}, false, buffer_session_failure(request.command, close_failure)
	}
	completion := Buffer_Kill_Completion.Closed
	if closure.outcome == .Discard_Required {
		completion = .Discard_Required
	}
	return Buffer_Kill_Result {completion = completion, closure = closure}, true, {}
}

/* buffer_session_first_save associates, saves, and reindexes one unassociated buffer. */
buffer_session_first_save :: proc(
	request: Buffer_Session_Context,
	entry: editor_session.Entry_Handle,
	path: string,
) -> (result: editor_session.Associate_Save_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   !editor_session.entry_handle_is_valid(entry) || len(path) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	session_failure: editor_session.Failure_Context
	result, ok, session_failure = editor_session.session_associate_and_save(
		request.session,
		editor_session.Associate_Save_Request {
			entry = entry,
			path = path,
			limits = request.configuration.document_limits,
		},
	)
	if !ok {
		return result, false, buffer_session_failure(request.command, session_failure)
	}
	return result, true, {}
}

/* buffer_session_write_file saves one entry to a selected authoritative path. */
buffer_session_write_file :: proc(
	request: Buffer_Session_Context,
	entry: editor_session.Entry_Handle,
	path: string,
) -> (result: editor_session.Associate_Save_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   !editor_session.entry_handle_is_valid(entry) || len(path) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	session_failure: editor_session.Failure_Context
	result, ok, session_failure = editor_session.session_write_entry_to_path(
		request.session,
		editor_session.Associate_Save_Request {
			entry = entry,
			path = path,
			limits = request.configuration.document_limits,
		},
	)
	if !ok do return result, false, buffer_session_failure(request.command, session_failure)
	return result, true, {}
}

@(private)
buffer_session_failure :: proc(
	command: interaction.Command_Handle,
	failure: editor_session.Failure_Context,
) -> Failure_Context {
	code := Failure_Code.Editor_Session_Failure
	if failure.code == .Project_Scope {
		code = .Project_Scope_Required
	}
	return Failure_Context {
		code = code,
		command = command,
		editor_session_code = failure.code,
		project_code = failure.project_failure.code,
		document_code = failure.document_failure.code,
		editor_code = failure.editor_failure.code,
		view_code = failure.view_failure.code,
		history_code = failure.history_failure.code,
		minimum = failure.minimum,
		limit = failure.maximum,
		actual = failure.actual,
	}
}
