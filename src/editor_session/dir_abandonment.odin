// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

/* session_prepare_dir_abandonment snapshots one exact ordinary Dir after dirty protection. */
session_prepare_dir_abandonment :: proc(
	session: ^Session,
	handle: Session_Handle,
	root: Root_Handle,
	action: Dir_Abandonment_Action,
	suppressed: bool,
	prepared: ^Dir_Abandonment_Preparation,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	prepared^ = {}
	data, resolved_failure := resolve_session(session, handle, .Prepare_Dir_Abandonment)
	if resolved_failure.code != .None {
		return false, resolved_failure
	}
	if action == .Invalid {
		return false, session_failure(data, .Prepare_Dir_Abandonment, .Invalid_Root)
	}
	index := session_root_index(data, root)
	if index < 0 || data.roots[index].kind != .Dir {
		failure = session_failure(data, .Prepare_Dir_Abandonment, .Invalid_Root)
		failure.root = root
		return false, failure
	}
	owner := &data.roots[index]
	if len(owner.path) == 0 || len(owner.path) > len(prepared.path) {
		failure = session_failure(data, .Prepare_Dir_Abandonment, .Invalid_Path)
		failure.root = root
		return false, failure
	}
	copy(prepared.path[:], transmute([]u8)owner.path)
	prepared.session = data.handle
	prepared.root = owner.handle
	prepared.root_set = data.root_generation
	prepared.action = action
	prepared.outcome = .Ready if suppressed else .Decision_Required
	prepared.path_length = u32(len(owner.path))
	return true, {}
}

/* session_admit_dir_abandonment revalidates the decision before its pending action continues. */
session_admit_dir_abandonment :: proc(
	session: ^Session,
	prepared: ^Dir_Abandonment_Preparation,
	decision: Dir_Abandonment_Decision,
) -> (admission: Dir_Abandonment_Admission, ok: bool, failure: Failure_Context) {
	if prepared == nil || prepared.outcome == .Invalid || prepared.action == .Invalid {
		return .Invalid, false, Failure_Context {
			code = .Invalid_Session,
			operation = .Admit_Dir_Abandonment,
		}
	}
	data, resolved_failure := resolve_session(
		session,
		prepared.session,
		.Admit_Dir_Abandonment,
	)
	if resolved_failure.code != .None {
		return .Invalid, false, resolved_failure
	}
	if prepared.outcome == .Decision_Required && decision == .Cancel {
		prepared^ = {}
		return .Cancelled, true, {}
	}
	path := dir_abandonment_path_text(prepared)
	admitted := false
	switch prepared.outcome {
	case .Ready:
		admitted = decision == .Continue && data.root_generation == prepared.root_set &&
		           session_root_is_exact_dir(data, prepared.root, path)
	case .Decision_Required:
		switch decision {
		case .Decline, .Disable_Prompt:
			admitted = data.root_generation == prepared.root_set &&
			           session_root_is_exact_dir(data, prepared.root, path)
		case .Convert:
			admitted = session_root_is_exact_project_path(data, path)
		case .Invalid, .Continue, .Cancel:
		}
	case .Invalid:
	}
	if !admitted {
		failure = session_failure(data, .Admit_Dir_Abandonment, .Busy)
		failure.root = prepared.root
		return .Invalid, false, failure
	}
	prepared^ = {}
	return .Continue, true, {}
}

/* session_abort_dir_abandonment invalidates one unconsumed decision. */
session_abort_dir_abandonment :: proc(prepared: ^Dir_Abandonment_Preparation) {
	if prepared != nil {
		prepared^ = {}
	}
}

@(private)
session_root_index :: proc(data: ^Session_Data, root: Root_Handle) -> int {
	if data == nil || !root_handle_is_valid(root) || root.session != data.handle {
		return -1
	}
	for owner, index in data.roots {
		if owner.handle == root {
			return index
		}
	}
	return -1
}

@(private)
session_root_is_exact_dir :: proc(data: ^Session_Data, root: Root_Handle, path: string) -> bool {
	index := session_root_index(data, root)
	return index >= 0 && data.roots[index].kind == .Dir && data.roots[index].path == path
}

@(private)
session_root_is_exact_project_path :: proc(data: ^Session_Data, path: string) -> bool {
	if data == nil || len(path) == 0 {
		return false
	}
	for owner in data.roots {
		if owner.kind == .Project && owner.path == path &&
		   session_project_root_is_valid(data, owner.project, owner.path) {
			return true
		}
	}
	return false
}
