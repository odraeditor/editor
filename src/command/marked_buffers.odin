// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../document"
import "../editor_session"

/* Marked_Kill_Decision records resolved dirty authority for one marked kill. */
Marked_Kill_Decision :: enum u8 {
	None,
	Save,
	Discard,
	Cancel,
}

/* Marked_Entry_Decision supplies one checked save path or kill decision. */
Marked_Entry_Decision :: struct {
	entry: editor_session.Entry_Handle,
	kind:  Marked_Kill_Decision,
	path:  string,
}

/* Marked_Execution_Outcome classifies complete, pending, cancelled, and failed batches. */
Marked_Execution_Outcome :: enum u8 {
	Invalid,
	Completed,
	Decision_Required,
	Cancelled,
	Failed,
}

/* Marked_Execution_Result reports truthful completed and pending external effects. */
Marked_Execution_Result :: struct {
	outcome:         Marked_Execution_Outcome,
	completed_saves: u32,
	pending_saves:   u32,
	completed_kills: u32,
	pending_kills:   u32,
	decision_entry:  editor_session.Entry_Handle,
	failed_entry:    editor_session.Entry_Handle,
}

/* Buffer_Mark_Kind names one semantic Buffer Menu batch operation. */
Buffer_Mark_Kind :: enum u8 {
	Invalid,
	Save,
	Kill,
}

/* Buffer_Marked_Entry is one copied semantic mark for an exact buffer entry. */
Buffer_Marked_Entry :: struct {
	entry: editor_session.Entry_Handle,
	kind:  Buffer_Mark_Kind,
}

/* Buffer_Marked_Execution_Context supplies checked session authority without presentation ownership. */
Buffer_Marked_Execution_Context :: struct {
	buffer_session: Buffer_Session_Context,
	decisions:      []Marked_Entry_Decision,
}

/* buffer_session_execute_buffer_marks executes one copied semantic Buffer Menu mark set. */
buffer_session_execute_buffer_marks :: proc(
	request: Buffer_Marked_Execution_Context,
	marks: []Buffer_Marked_Entry,
) -> (result: Marked_Execution_Result, ok: bool, failure: Failure_Context) {
	if !buffer_marked_execution_request_is_valid(request, marks) {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.buffer_session.command,
		}
	}
	for marked in marks {
		if marked.kind == .Save {
			result.pending_saves += 1
		} else if marked.kind == .Kill {
			result.pending_kills += 1
		} else {
			return {}, false, Failure_Context {
				code = .Invalid_Request,
				command = request.buffer_session.command,
			}
		}
	}
	for marked in marks {
		if marked.kind != .Save {
			continue
		}
		decision, decision_found := marked_entry_decision_find(request.decisions, marked.entry)
		path := ""
		if decision_found {
			if decision.kind == .Cancel {
				result.outcome = .Cancelled
				result.decision_entry = marked.entry
				return result, true, {}
			}
			path = decision.path
		}
		save, saved, save_failure := buffer_session_save_entry(
			request.buffer_session,
			marked.entry,
			path,
		)
		_ = save
		if !saved {
			if save_failure.code == .Invalid_Request && !decision_found {
				result.outcome = .Decision_Required
				result.decision_entry = marked.entry
				return result, true, {}
			}
			result.outcome = .Failed
			result.failed_entry = marked.entry
			return result, false, save_failure
		}
		result.completed_saves += 1
		result.pending_saves -= 1
	}
	for marked in marks {
		if marked.kind != .Kill {
			continue
		}
		assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
			request.buffer_session.session,
			marked.entry,
		)
		if !assessed {
			result.outcome = .Failed
			result.failed_entry = marked.entry
			return result, false, buffer_session_failure(request.buffer_session.command, assess_failure)
		}
		if !assessment.modified {
			continue
		}
		decision, found := marked_entry_decision_find(request.decisions, marked.entry)
		if !found || decision.kind == .None {
			result.outcome = .Decision_Required
			result.decision_entry = marked.entry
			return result, true, {}
		}
		if decision.kind == .Cancel {
			result.outcome = .Cancelled
			result.decision_entry = marked.entry
			return result, true, {}
		}
		if decision.kind == .Save {
			_, saved, save_failure := buffer_session_save_entry(
				request.buffer_session,
				marked.entry,
				decision.path,
			)
			if !saved {
				result.outcome = .Failed
				result.failed_entry = marked.entry
				return result, false, save_failure
			}
			result.completed_saves += 1
		}
	}
	if result.pending_kills > 0 {
		close_requests, close_requests_error := make(
			[]editor_session.Close_Buffer_Request,
			int(result.pending_kills),
			context.temp_allocator,
		)
		if close_requests_error != nil {
			result.outcome = .Failed
			return result, false, Failure_Context {
				code = .Temporary_Memory_Limit,
				command = request.buffer_session.command,
			}
		}
		defer delete(close_requests, context.temp_allocator)
		index := 0
		for marked in marks {
			if marked.kind != .Kill {
				continue
			}
			authority := editor_session.Close_Authority.Preserve_Modified
			assessment, assessed, assess_failure := editor_session.session_assess_buffer_close(
				request.buffer_session.session,
				marked.entry,
			)
			if !assessed {
				result.outcome = .Failed
				result.failed_entry = marked.entry
				return result, false, buffer_session_failure(request.buffer_session.command, assess_failure)
			}
			if assessment.modified {
				decision, found := marked_entry_decision_find(request.decisions, marked.entry)
				if !found || decision.kind != .Discard {
					result.outcome = .Failed
					result.failed_entry = marked.entry
					return result, false, Failure_Context {
						code = .Invalid_Request,
						command = request.buffer_session.command,
					}
				}
				authority = .Discard_Modified
			}
			close_requests[index] = editor_session.Close_Buffer_Request {
				entry = marked.entry,
				authority = authority,
			}
			index += 1
		}
		closed_set, closed, close_failure := editor_session.session_close_buffer_set(
			request.buffer_session.session,
			close_requests,
		)
		if !closed {
			result.outcome = .Failed
			result.failed_entry = close_failure.entry
			return result, false, buffer_session_failure(request.buffer_session.command, close_failure)
		}
		result.completed_kills = closed_set.closed_entries
		result.pending_kills = 0
	}
	result.outcome = .Completed
	return result, true, {}
}

/* buffer_session_save_entry saves one associated entry or first-saves an unassociated entry. */
buffer_session_save_entry :: proc(
	request: Buffer_Session_Context,
	entry: editor_session.Entry_Handle,
	first_save_path := "",
) -> (result: document.Save_Result, ok: bool, failure: Failure_Context) {
	if request.session == nil || !editor_session.session_handle_is_valid(request.handle) ||
	   !editor_session.entry_handle_is_valid(entry) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	access, access_ok, access_failure := editor_session.session_entry_access(request.session, entry)
	if !access_ok {
		return {}, false, buffer_session_failure(request.command, access_failure)
	}
	borrow, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
	if !borrowed {
		return {}, false, buffer_session_failure(request.command, borrow_failure)
	}
	if !borrow.has_document {
		if len(first_save_path) == 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		associated, saved, save_failure := buffer_session_first_save(request, entry, first_save_path)
		return associated.save, saved, save_failure
	}
	prepared: document.Prepared_Save
	prepared_ok, prepare_failure := document.save_prepare(borrow.document, borrow.buffer, &prepared)
	if !prepared_ok {
		return {}, false, native_document_failure(request.command, prepare_failure)
	}
	result, ok, prepare_failure = document.prepared_save_publish(&prepared)
	if !ok {
		failure = native_document_failure(request.command, prepare_failure)
		failure.publication = result.publication
		return result, false, failure
	}
	return result, true, {}
}

@(private)
buffer_marked_execution_request_is_valid :: proc(
	request: Buffer_Marked_Execution_Context,
	marks: []Buffer_Marked_Entry,
) -> bool {
	if request.buffer_session.session == nil ||
	   !editor_session.session_handle_is_valid(request.buffer_session.handle) ||
	   len(marks) == 0 || len(marks) > int(editor_session.MAX_INVENTORY_MARKS) {
		return false
	}
	for marked, index in marks {
		if !editor_session.entry_handle_is_valid(marked.entry) ||
		   (marked.kind != .Save && marked.kind != .Kill) {
			return false
		}
		for previous in 0 ..< index {
			if marks[previous].entry == marked.entry do return false
		}
	}
	return true
}

@(private)
marked_entry_decision_find :: proc(
	decisions: []Marked_Entry_Decision,
	entry: editor_session.Entry_Handle,
) -> (decision: Marked_Entry_Decision, found: bool) {
	for candidate in decisions {
		if candidate.entry == entry {
			if found {
				return {}, false
			}
			decision = candidate
			found = true
		}
	}
	return
}
