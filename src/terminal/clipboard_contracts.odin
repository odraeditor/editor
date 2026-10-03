// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "base:runtime"

/* MAX_CLIPBOARD_TEXT_BYTES is the exact decoded-text ceiling admitted by Herdr OSC 52. */
MAX_CLIPBOARD_TEXT_BYTES :: u64(196_602)
/* DEFAULT_CLIPBOARD_TIMEOUT_MILLISECONDS bounds one synchronous clipboard request. */
DEFAULT_CLIPBOARD_TIMEOUT_MILLISECONDS :: u32(1_000)
/* MIN_CLIPBOARD_TIMEOUT_MILLISECONDS is the smallest admitted request timeout. */
MIN_CLIPBOARD_TIMEOUT_MILLISECONDS :: u32(10)
/* MAX_CLIPBOARD_TIMEOUT_MILLISECONDS is the largest admitted request timeout. */
MAX_CLIPBOARD_TIMEOUT_MILLISECONDS :: u32(5_000)
/* DEFAULT_CLIPBOARD_CANCELLATION_BYTES bounds work between cancellation checks. */
DEFAULT_CLIPBOARD_CANCELLATION_BYTES :: u64(64 * 1024)
/* MAX_CLIPBOARD_CANCELLATION_BYTES is the largest admitted work interval. */
MAX_CLIPBOARD_CANCELLATION_BYTES :: u64(4 * 1024 * 1024)
/* DEFAULT_CLIPBOARD_TEMPORARY_BYTES admits one text copy and its complete OSC 52 frame. */
DEFAULT_CLIPBOARD_TEMPORARY_BYTES :: u64(512 * 1024)

/* Clipboard_Change_Token identifies one frontend-observed clipboard value; zero is invalid. */
Clipboard_Change_Token :: distinct u64

/* Clipboard_Presentation identifies where physical clipboard effects occur. */
Clipboard_Presentation :: enum u8 {
	Unavailable,
	Outer_Terminal_Client,
}

/* Clipboard_Capabilities reports independent physical read and write availability. */
Clipboard_Capabilities :: struct {
	read:         bool,
	write:        bool,
	presentation: Clipboard_Presentation,
}

/* Clipboard_Environment is a copied presentation-path observation used for negotiation. */
Clipboard_Environment :: struct {
	remote:            bool,
	herdr:             bool,
	nested_tmux:       bool,
	nested_zellij:     bool,
	graphical_session: bool,
}

/* Clipboard_Cancel_Proc reports whether one synchronous request should stop. */
Clipboard_Cancel_Proc :: proc "odin" (user_data: rawptr) -> bool

/* Clipboard_Cancellation supplies a checked cancellation callback without global state. */
Clipboard_Cancellation :: struct {
	user_data: rawptr,
	check:   Clipboard_Cancel_Proc,
}

/* Clipboard_Config fixes request, time, work, allocation, and temporary-memory limits. */
Clipboard_Config :: struct {
	max_text_bytes:      u64,
	timeout_milliseconds: u32,
	cancellation_bytes:  u64,
	max_temporary_bytes: u64,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
}

/* clipboard_default_config returns the measured initial terminal clipboard policy. */
clipboard_default_config :: proc(
	persistent_allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> Clipboard_Config {
	return Clipboard_Config {
		max_text_bytes = MAX_CLIPBOARD_TEXT_BYTES,
		timeout_milliseconds = DEFAULT_CLIPBOARD_TIMEOUT_MILLISECONDS,
		cancellation_bytes = DEFAULT_CLIPBOARD_CANCELLATION_BYTES,
		max_temporary_bytes = DEFAULT_CLIPBOARD_TEMPORARY_BYTES,
		persistent_allocator = persistent_allocator,
		temporary_allocator = temporary_allocator,
	}
}

/* Clipboard_Write_Request lends one UTF-8 value for a bounded copied export. */
Clipboard_Write_Request :: struct {
	text:         string,
	cancellation: Clipboard_Cancellation,
}

/* Clipboard_Read_Request asks for one bounded copied external value on demand. */
Clipboard_Read_Request :: struct {
	result_allocator: runtime.Allocator,
	cancellation:     Clipboard_Cancellation,
}

/* Clipboard_Write_Result identifies one complete frontend export. */
Clipboard_Write_Result :: struct {
	token: Clipboard_Change_Token,
	bytes: u64,
}

/* Clipboard_Read_Result owns one copied UTF-8 value until clipboard_read_result_close. */
Clipboard_Read_Result :: struct {
	text:      string,
	token:     Clipboard_Change_Token,
	allocator: runtime.Allocator,
}

/* Clipboard_Transport_Read lends one complete physical response during a transport call. */
Clipboard_Transport_Read :: struct {
	text:           []u8,
	token:          Clipboard_Change_Token,
	reported_bytes: u64,
	complete:       bool,
}

/* Clipboard_Transport_Write_Proc writes one complete framed request within supplied bounds. */
Clipboard_Transport_Write_Proc :: proc "odin" (
	user_data: rawptr,
	frame: []u8,
	timeout_milliseconds: u32,
	cancellation_bytes: u64,
	cancellation: Clipboard_Cancellation,
) -> (bytes_done: u64, ok: bool, failure: Clipboard_Failure_Context)

/* Clipboard_Transport_Read_Proc lends one physical clipboard response within supplied bounds. */
Clipboard_Transport_Read_Proc :: proc "odin" (
	user_data: rawptr,
	timeout_milliseconds: u32,
	cancellation: Clipboard_Cancellation,
) -> (response: Clipboard_Transport_Read, ok: bool, failure: Clipboard_Failure_Context)

/* Clipboard_Transport_Close_Proc releases transport-owned physical resources. */
Clipboard_Transport_Close_Proc :: proc "odin" (user_data: rawptr) -> (
	ok: bool,
	failure: Clipboard_Failure_Context,
)

/* Clipboard_Transport binds one capability set to bounded synchronous physical operations. */
Clipboard_Transport :: struct {
	user_data:    rawptr,
	capabilities: Clipboard_Capabilities,
	write:        Clipboard_Transport_Write_Proc,
	read:         Clipboard_Transport_Read_Proc,
	close:        Clipboard_Transport_Close_Proc,
}

/* Clipboard_Stats reports adapter identity, capabilities, work, and exact owned storage. */
Clipboard_Stats :: struct {
	capabilities:         Clipboard_Capabilities,
	next_token:           Clipboard_Change_Token,
	completed_reads:      u64,
	completed_writes:     u64,
	retained_bytes:       u64,
	temporary_bytes:      u64,
	peak_temporary_bytes: u64,
}

/* Clipboard_Failure_Code classifies expected adapter rejection without editor-state effects. */
Clipboard_Failure_Code :: enum u16 {
	None,
	Invalid_Adapter,
	Invalid_Config,
	Persistent_Memory_Limit,
	Read_Unavailable,
	Write_Unavailable,
	Empty_Text,
	Invalid_UTF8,
	Text_Limit,
	Temporary_Memory_Limit,
	Cancelled,
	Timed_Out,
	Token_Exhausted,
	Partial_Response,
	Read_Failed,
	Write_Failed,
	Transport_Restore_Failed,
}

/* Clipboard_Failure_Context reports operation bounds and physical progress without payload data. */
Clipboard_Failure_Context :: struct {
	code:       Clipboard_Failure_Code,
	limit:      u64,
	actual:     u64,
	bytes_done: u64,
	os_errno:   i32,
}

/* Clipboard_Adapter is a non-copyable owner consumed by clipboard_adapter_close. */
Clipboard_Adapter :: struct {
	state:  rawptr,
	closed: bool,
}
