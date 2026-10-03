// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../gutter"
import "../interaction"
import "core:fmt"

@(private)
command_context_apply_startup_gutter_provider :: proc(
	commands: ^Command_Context,
	state: Personal_Configuration_Startup_State,
	startup_result: []u8,
) {
	if commands == nil || state.gutter_provider_length == 0 do return
	provider_bytes, bytes_ok := personal_configuration_gutter_provider_bytes(state, startup_result)
	if !bytes_ok {
		command_context_report_gutter_provider_rejection(
			commands,
			gutter.Failure_Context{operation = .Copy, code = .Invalid_Request},
		)
		return
	}
	request, decoded, decode_failure := command.racket_gutter_provider_request_decode(
		provider_bytes,
		commands.registry,
	)
	if !decoded {
		gutter.programmable_registry_fail(&commands.gutter_registry, decode_failure)
		command_context_report_gutter_provider_rejection(commands, decode_failure)
		return
	}
	proposal := command.racket_gutter_provider_request_proposal(&request)
	_, registry_generation, _, _, inspected := gutter.programmable_registry_inspect(
		&commands.gutter_registry,
	)
	if !inspected {
		command_context_report_gutter_provider_rejection(
			commands,
			gutter.Failure_Context{operation = .Prepare, code = .Invalid_Request},
		)
		return
	}
	candidate, prepared, prepare_failure := gutter.programmable_registry_prepare(
		&commands.gutter_registry,
		registry_generation,
		proposal,
	)
	if !prepared {
		command_context_report_gutter_provider_rejection(commands, prepare_failure)
		return
	}
	defer if candidate.data != nil do gutter.programmable_provider_candidate_close(&candidate)
	confirmed, confirm_failure := gutter.programmable_provider_candidate_confirm(&candidate)
	if !confirmed {
		command_context_report_gutter_provider_rejection(commands, confirm_failure)
		return
	}
	activated, activate_failure := gutter.programmable_registry_activate(
		&commands.gutter_registry,
		&candidate,
	)
	if !activated do command_context_report_gutter_provider_rejection(commands, activate_failure)
}

@(private)
personal_configuration_gutter_provider_bytes :: proc(
	state: Personal_Configuration_Startup_State,
	input: []u8,
) -> ([]u8, bool) {
	if state.gutter_provider_offset < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES ||
	   state.gutter_provider_length < 0 || state.gutter_provider_offset > len(input) ||
	   state.gutter_provider_length > len(input) - state.gutter_provider_offset {
		return nil, false
	}
	end := state.gutter_provider_offset + state.gutter_provider_length
	return input[state.gutter_provider_offset:end], true
}

@(private)
command_context_prepare_gutter_provider_reload :: proc(
	commands: ^Command_Context,
	state: Personal_Configuration_Startup_State,
	reload_result: []u8,
	registry: ^interaction.Command_Registry,
) -> (candidate: gutter.Programmable_Provider_Candidate, remove: bool,
	expected_generation: u64, ok: bool, failure: gutter.Failure_Context) {
	if commands == nil || registry == nil {
		return {}, false, 0, false,
			gutter.Failure_Context{operation = .Prepare, code = .Invalid_Request}
	}
	descriptor, generation, _, _, inspected := gutter.programmable_registry_inspect(
		&commands.gutter_registry,
	)
	if !inspected {
		return {}, false, 0, false,
			gutter.Failure_Context{operation = .Prepare, code = .Invalid_Request}
	}
	if state.gutter_provider_length == 0 {
		return {}, descriptor.provider != 0, generation, true, {}
	}
	provider_bytes, bytes_ok := personal_configuration_gutter_provider_bytes(state, reload_result)
	if !bytes_ok {
		return {}, false, generation, false,
			gutter.Failure_Context{operation = .Copy, code = .Invalid_Request}
	}
	request, decoded, decode_failure := command.racket_gutter_provider_request_decode(
		provider_bytes,
		registry,
	)
	if !decoded do return {}, false, generation, false, decode_failure
	proposal := command.racket_gutter_provider_request_proposal(&request)
	candidate, ok, failure = gutter.programmable_registry_prepare(
		&commands.gutter_registry,
		generation,
		proposal,
	)
	if !ok do return {}, false, generation, false, failure
	confirmed, confirm_failure := gutter.programmable_provider_candidate_confirm(&candidate)
	if !confirmed {
		gutter.programmable_provider_candidate_close(&candidate)
		return {}, false, generation, false, confirm_failure
	}
	return candidate, false, generation, true, {}
}

@(private)
command_context_publish_gutter_provider_reload :: proc(
	commands: ^Command_Context,
	candidate: ^gutter.Programmable_Provider_Candidate,
	remove: bool,
	expected_generation: u64,
) -> (bool, gutter.Failure_Context) {
	if candidate != nil && candidate.data != nil {
		return gutter.programmable_registry_activate(&commands.gutter_registry, candidate)
	}
	if remove {
		return gutter.programmable_registry_remove(&commands.gutter_registry, expected_generation)
	}
	return true, {}
}

@(private)
command_context_report_gutter_provider_rejection :: proc(
	commands: ^Command_Context,
	failure: gutter.Failure_Context,
) {
	if commands == nil do return
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Programmable Gutter provider rejected: %v during %v; active generation preserved",
		failure.code,
		failure.operation,
	)
	commands.diagnostic_length = len(message)
}

@(private)
gutter_programmable_intersects_display :: proc(
	provider: gutter.Programmable_Provider_View,
	view: display.Snapshot_View,
) -> bool {
	for marker in provider.publication.markers {
		for row in view.rows {
			if marker.attachment.logical_line == u64(row.logical_line) do return true
		}
	}
	return false
}

@(private)
gutter_programmable_reserved_cells :: proc(
	provider: gutter.Programmable_Provider_View,
	view: display.Snapshot_View,
) -> u32 {
	if !gutter_programmable_intersects_display(provider, view) do return 0
	reserved: u32
	for lane in provider.lanes {
		content_present := false
		for marker in provider.publication.markers {
			if marker.lane != lane.id do continue
			for row in view.rows {
				if marker.attachment.logical_line != u64(row.logical_line) do continue
				content_present = true
			}
		}
		if content_present do reserved += u32(lane.maximum_cells)
	}
	return reserved
}
