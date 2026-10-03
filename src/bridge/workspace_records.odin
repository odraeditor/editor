// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor_session"

/* WORKSPACE_COMMAND_SCHEMA_VERSION identifies copied Workspace requests and results. */
WORKSPACE_COMMAND_SCHEMA_VERSION :: u64(1)
/* MAX_WORKSPACE_COMMAND_BYTES bounds one complete copied Workspace exchange. */
MAX_WORKSPACE_COMMAND_BYTES :: u64(4 * 1024 * 1024)
/* MAX_WORKSPACE_RESULT_RECORDS bounds copied Workspace catalog entries. */
MAX_WORKSPACE_RESULT_RECORDS :: u64(256)
/* MAX_WORKSPACE_MEMBER_RECORDS bounds copied member resolutions. */
MAX_WORKSPACE_MEMBER_RECORDS :: u64(editor_session.MAX_SESSION_ROOTS)
/* WORKSPACE_REQUEST_HEADER_BYTES precedes copied identity, name, and root data. */
WORKSPACE_REQUEST_HEADER_BYTES :: u64(48)
/* WORKSPACE_RESULT_HEADER_BYTES precedes all copied result records and text. */
WORKSPACE_RESULT_HEADER_BYTES :: u64(88)
/* WORKSPACE_DESCRIPTOR_RECORD_BYTES is one pointer-free Workspace summary. */
WORKSPACE_DESCRIPTOR_RECORD_BYTES :: u64(56)
/* WORKSPACE_MEMBER_RECORD_BYTES is one pointer-free resolved Project member. */
WORKSPACE_MEMBER_RECORD_BYTES :: u64(104)

/* Workspace_Command_Action identifies one programmable lifecycle operation. */
Workspace_Command_Action :: enum u64 {
	Invalid,
	Create,
	Open,
	Update,
	List,
	Inspect,
	Add_Project,
	Remove_Project,
	Unregister,
	Move_Project_Up,
	Move_Project_Down,
}

/* Workspace_Request_Header_Record describes one copied optimistic request. */
Workspace_Request_Header_Record :: struct {
	schema_version:      u64,
	action:              u64,
	expected_generation: u64,
	id_bytes:            u64,
	name_bytes:          u64,
	root_count:          u64,
}

/* Workspace_Result_Header_Record describes one copied operation result. */
Workspace_Result_Header_Record :: struct {
	schema_version:     u64,
	action:             u64,
	success:            u64,
	workspace_count:    u64,
	member_count:       u64,
	publication:        u64,
	text_bytes:         u64,
	diagnostic_count:   u64,
	diagnostic_offset:  u64,
	diagnostic_bytes:   u64,
	reserved:           u64,
}

/* Workspace_Descriptor_Record is one pointer-free durable composition summary. */
Workspace_Descriptor_Record :: struct {
	id_offset:     u64,
	id_bytes:      u64,
	generation:    u64,
	name_offset:   u64,
	name_bytes:    u64,
	member_offset: u64,
	member_count:  u64,
}

/* Workspace_Member_Record is one pointer-free Project resolution and diagnostic. */
Workspace_Member_Record :: struct {
	workspace_index:   u64,
	state:             u64,
	project_id:        u64,
	project_generation: u64,
	durable_id_offset: u64,
	durable_id_bytes:  u64,
	name_offset:       u64,
	name_bytes:        u64,
	root_offset:       u64,
	root_bytes:        u64,
	trust:             u64,
	diagnostic_offset: u64,
	diagnostic_bytes:  u64,
}

/* workspace_result_bytes validates record quotas and the exact copied width. */
workspace_result_bytes :: proc(
	workspaces, members, text_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if workspaces > MAX_WORKSPACE_RESULT_RECORDS || members > MAX_WORKSPACE_MEMBER_RECORDS ||
	   text_bytes > MAX_WORKSPACE_COMMAND_BYTES {
		return 0, false
	}
	bytes = WORKSPACE_RESULT_HEADER_BYTES +
	        workspaces * WORKSPACE_DESCRIPTOR_RECORD_BYTES +
	        members * WORKSPACE_MEMBER_RECORD_BYTES + text_bytes
	return bytes, bytes <= MAX_WORKSPACE_COMMAND_BYTES
}
