// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

/* TERMINAL_CAPABILITY_SCHEMA_VERSION identifies the copied terminal facade records. */
TERMINAL_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* TERMINAL_SESSIONS_HEADER_BYTES identifies the copied session count. */
TERMINAL_SESSIONS_HEADER_BYTES :: u64(8)
/* TERMINAL_SESSION_RECORD_BYTES is one fixed copied session-summary record. */
TERMINAL_SESSION_RECORD_BYTES :: u64(160)
/* TERMINAL_SNAPSHOT_RECORD_BYTES is one copied text-snapshot header. */
TERMINAL_SNAPSHOT_RECORD_BYTES :: u64(72)
/* TERMINAL_KEY_RECORD_BYTES is one copied normalized-key request header. */
TERMINAL_KEY_RECORD_BYTES :: u64(48)
/* TERMINAL_SUBSCRIPTION_HEADER_BYTES is one copied subscription proposal header. */
TERMINAL_SUBSCRIPTION_HEADER_BYTES :: u64(80)
/* TERMINAL_SUBSCRIPTION_RECORD_BYTES is one copied active subscriber descriptor. */
TERMINAL_SUBSCRIPTION_RECORD_BYTES :: u64(72)
/* TERMINAL_EVENT_BATCH_HEADER_BYTES is one copied delivery batch header. */
TERMINAL_EVENT_BATCH_HEADER_BYTES :: u64(40)
/* TERMINAL_EVENT_RECORD_BYTES is one copied typed event descriptor. */
TERMINAL_EVENT_RECORD_BYTES :: u64(112)
/* TERMINAL_EVENT_WATERMARK_RECORD_BYTES is one copied session acknowledgment cursor. */
TERMINAL_EVENT_WATERMARK_RECORD_BYTES :: u64(24)
/* MAX_TERMINAL_INSPECTION_BYTES bounds one copied session or text response. */
MAX_TERMINAL_INSPECTION_BYTES :: u64(5 * 1_024 * 1_024)
/* MAX_TERMINAL_PROPOSAL_BYTES bounds one copied input or subscription request. */
MAX_TERMINAL_PROPOSAL_BYTES :: u64(1 * 1_024 * 1_024)

/* Terminal_Capability_Operation identifies one admitted terminal facade request. */
Terminal_Capability_Operation :: enum i32 {
	Sessions = 1,
	Session_State,
	Visible_Text,
	Scrollback,
	Send_Text,
	Send_Key,
	Terminate,
	Subscribe,
	Unsubscribe,
	Delivery_Next,
	Delivery_Snapshot,
	Delivery_Complete,
	Delivery_Reject,
}

/* Terminal_Capability_Failure_Code is the bridge-level public failure vocabulary. */
Terminal_Capability_Failure_Code :: enum u32 {
	None = 0,
	Invalid,
	Stale,
	Unavailable,
	Denied,
	Resource_Limited,
	Cancelled,
}

/* Terminal_Capability_Access defines independently grantable terminal authority. */
Terminal_Capability_Access :: enum u8 {
	Inspect,
	Input,
	Terminate,
	Subscribe,
}

/* Terminal_Capability_Access_Set combines the authority granted for one turn. */
Terminal_Capability_Access_Set :: bit_set[Terminal_Capability_Access; u8]

/* Terminal_Capability_Scope is the public session visibility boundary. */
Terminal_Capability_Scope :: enum u8 {
	Invalid = 0,
	Instance,
	Workspace,
}
