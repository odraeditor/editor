// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../document"
import "../interaction"
import "../kill_ring"
import terminal "../terminal"
import "base:runtime"
import "core:fmt"

@(private)
Clipboard_Workflow_State :: struct {
	kill_sequence_id:     u64,
	last_command_was_kill: bool,
	yank_context:         command.Yank_Context,
	adapter:              ^terminal.Clipboard_Adapter,
	transfer:             command.Clipboard_Transfer_State,
}

@(private)
Clipboard_Workflow_Output :: struct {
	ready:             bool,
	changed:           bool,
	diagnostic:        [document.MAX_DIAGNOSTIC_BYTES]byte,
	diagnostic_length: int,
}

@(private)
clipboard_workflow_reset :: proc(state: ^Clipboard_Workflow_State) {
	if state == nil {
		return
	}
	state.kill_sequence_id = 0
	state.last_command_was_kill = false
	state.yank_context = {}
	state.adapter = nil
	state.transfer = {}
}

@(private)
clipboard_workflow_cancel_yank :: proc(state: ^Clipboard_Workflow_State) {
	if state == nil {
		return
	}
	state.last_command_was_kill = false
	state.yank_context = {}
}

@(private)
clipboard_workflow_break_kill_sequence :: proc(state: ^Clipboard_Workflow_State) {
	if state == nil {
		return
	}
	state.last_command_was_kill = false
}

@(private)
clipboard_workflow_kill_sequence :: proc(
	state: ^Clipboard_Workflow_State,
	kill_command: bool,
) -> u64 {
	if state == nil {
		return 0
	}
	if !kill_command || !state.last_command_was_kill {
		if state.kill_sequence_id == max(u64) {
			state.kill_sequence_id = 0
		} else {
			state.kill_sequence_id += 1
		}
	}
	return state.kill_sequence_id
}

@(private)
clipboard_workflow_finish_command :: proc(
	state: ^Clipboard_Workflow_State,
	executed: bool,
	kill_command: bool,
) {
	if state == nil {
		return
	}
	state.last_command_was_kill = executed && kill_command
}

@(private)
clipboard_workflow_import :: proc(
	state: ^Clipboard_Workflow_State,
	ring: ^kill_ring.Ring,
	command_handle: interaction.Command_Handle,
	temporary_allocator: runtime.Allocator,
) -> (output: Clipboard_Workflow_Output) {
	output.ready = true
	if state == nil || ring == nil || !kill_ring.ring_is_valid(ring) {
		return
	}
	if state.adapter != nil {
		capabilities, capabilities_ok, capabilities_failure := terminal.clipboard_capabilities(
			state.adapter,
		)
		if !capabilities_ok {
			clipboard_workflow_terminal_diagnostic(&output, "Clipboard import", capabilities_failure)
		} else if capabilities.read {
			read, read_ok, read_failure := terminal.clipboard_read(
				state.adapter,
				terminal.Clipboard_Read_Request{result_allocator = temporary_allocator},
			)
			if !read_ok {
				clipboard_workflow_terminal_diagnostic(&output, "Clipboard import", read_failure)
			} else {
				_, admitted, admission_failure := command.clipboard_external_admit(
					ring,
					&state.transfer,
					command_handle,
					read.text,
					command.Clipboard_Token(u64(read.token)),
					temporary_allocator,
				)
				terminal.clipboard_read_result_close(&read)
				if !admitted {
					clipboard_workflow_command_diagnostic(
						&output,
						"Clipboard import",
						admission_failure,
					)
				}
			}
		}
	}
	stats, stats_ok, _ := kill_ring.ring_stats(ring)
	if stats_ok && stats.newest != kill_ring.Entry_ID(0) {
		return
	}
	output.ready = false
	if !output.changed {
		clipboard_workflow_set_diagnostic(&output, "Nothing to yank")
	}
	return
}

@(private)
clipboard_workflow_export :: proc(
	state: ^Clipboard_Workflow_State,
	ring: ^kill_ring.Ring,
	command_handle: interaction.Command_Handle,
	transfer: kill_ring.Reservation_Result,
	temporary_allocator: runtime.Allocator,
) -> (output: Clipboard_Workflow_Output) {
	if state == nil || state.adapter == nil || ring == nil ||
	   transfer.entry.id == kill_ring.Entry_ID(0) {
		return
	}
	capabilities, capabilities_ok, capabilities_failure := terminal.clipboard_capabilities(
		state.adapter,
	)
	if !capabilities_ok {
		clipboard_workflow_terminal_diagnostic(&output, "Clipboard export", capabilities_failure)
		return
	}
	if !capabilities.write {
		return
	}
	export, copied, copy_failure := command.clipboard_export_copy(
		ring,
		command_handle,
		transfer,
		terminal.MAX_CLIPBOARD_TEXT_BYTES,
		temporary_allocator,
	)
	if !copied {
		clipboard_workflow_command_diagnostic(&output, "Clipboard export", copy_failure)
		return
	}
	defer command.clipboard_export_close(&export)
	write_result, written, write_failure := terminal.clipboard_write(
		state.adapter,
		terminal.Clipboard_Write_Request{text = export.text},
	)
	if !written {
		clipboard_workflow_terminal_diagnostic(&output, "Clipboard export", write_failure)
		return
	}
	recorded := command.clipboard_transfer_record_export(
		&state.transfer,
		command.Clipboard_Token(u64(write_result.token)),
	)
	assert(recorded)
	return
}

@(private)
clipboard_workflow_set_diagnostic :: proc(output: ^Clipboard_Workflow_Output, message: string) {
	count := min(len(message), len(output.diagnostic))
	copy(output.diagnostic[:], transmute([]u8)message[:count])
	output.diagnostic_length = count
	output.changed = true
}

@(private)
clipboard_workflow_terminal_diagnostic :: proc(
	output: ^Clipboard_Workflow_Output,
	label: string,
	failure: terminal.Clipboard_Failure_Context,
) {
	message := fmt.bprintf(
		output.diagnostic[:],
		"%s: %v (limit: %d, actual: %d)",
		label,
		failure.code,
		failure.limit,
		failure.actual,
	)
	output.diagnostic_length = len(message)
	output.changed = true
}

@(private)
clipboard_workflow_command_diagnostic :: proc(
	output: ^Clipboard_Workflow_Output,
	label: string,
	failure: command.Failure_Context,
) {
	message := fmt.bprintf(
		output.diagnostic[:],
		"%s: %v (ring: %v)",
		label,
		failure.code,
		failure.kill_ring_code,
	)
	output.diagnostic_length = len(message)
	output.changed = true
}
