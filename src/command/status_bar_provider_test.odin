// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../interaction"
import endian "core:encoding/endian"
import "core:testing"

@(test)
/* Verifies copied package segments resolve only current registered command identities. */
status_bar_admits_registered_commands :: proc(t: ^testing.T) {
	commands: interaction.Command_Registry
	ready, ready_failure := built_in_command_registry_init(
		&commands,
		interaction.Registry_Generation(41),
		context.allocator,
	)
	testing.expectf(t, ready, "command registry failed: %v", ready_failure.code)
	if !ready do return
	defer interaction.command_registry_close(&commands)
	request_bytes := status_bar_provider_test_request("undo")
	request, decoded, failure := status_bar_provider_request_decode(
		request_bytes,
		.Register,
		&commands,
	)
	testing.expect(t, decoded)
	testing.expect_value(t, failure, bridge.Status_Bar_Bridge_Failure_Code.None)
	if !decoded do return
	proposal := status_bar_provider_request_proposal(&request)
	testing.expect_value(t, proposal.provider_name, "Tasks")
	testing.expect_value(t, proposal.package_name, "tasks-package")
	testing.expect_value(t, len(proposal.segments), 1)
	testing.expect_value(t, proposal.segments[0].identity, "task-count")
	testing.expect_value(
		t,
		proposal.segments[0].primary_command.registry_generation,
		u64(41),
	)
}

@(test)
/* Verifies unknown actions are rejected before a package proposal reaches Status Bar storage. */
status_bar_rejects_unknown_commands :: proc(t: ^testing.T) {
	commands: interaction.Command_Registry
	ready, _ := built_in_command_registry_init(
		&commands,
		interaction.Registry_Generation(42),
		context.allocator,
	)
	if !testing.expect(t, ready) do return
	defer interaction.command_registry_close(&commands)
	request_bytes := status_bar_provider_test_request("missing-command", 42)
	_, decoded, failure := status_bar_provider_request_decode(
		request_bytes,
		.Register,
		&commands,
	)
	testing.expect(t, !decoded)
	testing.expect_value(
		t,
		failure,
		bridge.Status_Bar_Bridge_Failure_Code.Command_Not_Admitted,
	)
}

@(private = "file")
status_bar_provider_test_request :: proc(
	command_name: string,
	command_generation: u64 = 41,
) -> []u8 {
	parts := [?]string {
		"Tasks", "tasks-package", "task-count", "3 tasks", "3",
		"Three active tasks", command_name, "",
	}
	text_bytes: u64
	for part in parts do text_bytes += u64(len(part))
	total, valid := bridge.status_bar_proposal_record_bytes(1, text_bytes)
	assert(valid)
	output := make([]u8, int(total), context.temp_allocator)
	scope_values := [?]u64 {
		bridge.STATUS_BAR_CAPABILITY_SCHEMA_VERSION,
		u64(bridge.Status_Bar_Capability_Access.Register),
		11, 13, 17, 19, 23, 0, 0, command_generation, 31, 37,
	}
	for value, index in scope_values do status_bar_provider_test_put(output, index * 8, value)
	text_start := bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES + bridge.STATUS_BAR_SEGMENT_RECORD_BYTES
	cursor := text_start
	ranges: [len(parts)][2]u64
	for part, index in parts {
		ranges[index] = {cursor, u64(len(part))}
		cursor += u64(len(part))
	}
	header_values := [?]u64 {
		u64(bridge.Status_Bar_Capability_Operation.Register),
		0, 0, 23, 0, 0,
		u64(bridge.Status_Bar_Provider_Kind.Package),
		1,
		ranges[0][0], ranges[0][1], ranges[1][0], ranges[1][1],
		text_bytes, 1,
	}
	for value, index in header_values {
		status_bar_provider_test_put(output, 96 + index * 8, value)
	}
	segment_values := [?]u64 {
		0, 0, 0, 0,
		u64(bridge.Status_Bar_Provider_State.Registered),
		14, 2, 20, 30, 1, 0, 6,
		ranges[2][0], ranges[2][1], ranges[3][0], ranges[3][1],
		ranges[4][0], ranges[4][1], ranges[5][0], ranges[5][1],
		ranges[6][0], ranges[6][1], ranges[7][0], ranges[7][1],
	}
	for value, index in segment_values {
		status_bar_provider_test_put(
			output,
			int(bridge.STATUS_BAR_PROPOSAL_HEADER_BYTES) + index * 8,
			value,
		)
	}
	cursor = text_start
	for part in parts {
		copy(output[int(cursor):], transmute([]u8)part)
		cursor += u64(len(part))
	}
	return output
}

@(private = "file")
status_bar_provider_test_put :: proc(destination: []u8, offset: int, value: u64) {
	written := endian.put_u64(destination[offset:], .Little, value)
	assert(written)
}
