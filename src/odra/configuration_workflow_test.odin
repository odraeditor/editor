// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../completion"
import "../editor_session"
import "../status_bar"
import "../gutter"
import "../recovery"
import "../terminal_session"
import "core:encoding/endian"
import "core:strings"
import "core:testing"

// EMPTY_LANGUAGE_SUPPORT_CONFIGURATION is the copied empty-support fixture.
EMPTY_LANGUAGE_SUPPORT_CONFIGURATION :: `{"languages":[],"schema":1,"selections":[],"services":[]}`

/* Verifies startup configuration batches decode into compact command state. */
@(test)
startup_configuration_decode_records_state :: proc(t: ^testing.T) {
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 + TERMINAL_CONFIGURATION_HEADER_BYTES +
		len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) + INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	state, terminal_configuration, decoded := personal_configuration_startup_decode(
		batch[:],
	)
	testing.expect(t, decoded)
	testing.expect(t, state.present)
	testing.expect_value(t, state.status, Personal_Configuration_Result.Confirmed)
	testing.expect_value(t, state.observation, Personal_Configuration_Observation.Absent)
	testing.expect_value(t, state.confirmed_generation, u64(2))
	testing.expect_value(t, state.rejected_generation, u64(0))
	testing.expect_value(t, state.diagnostic_length, 0)
	testing.expect_value(t, state.status_bar_policy.position, status_bar.Position_Presentation.Line_Column_Percentage)
	testing.expect_value(t, state.status_bar_policy.compact, status_bar.Compact_Policy.Automatic)
	testing.expect_value(t, state.gutter_policy.mode, gutter.Numbering_Mode.Absolute)
	testing.expect_value(t, state.gutter_policy.side, gutter.Side.Left)
	testing.expect_value(t, state.gutter_policy.minimum_digits, u16(4))
	testing.expect_value(t, state.gutter_policy.separator.value, "│")
	testing.expect(t, state.completion_configuration.enabled)
	testing.expect_value(
		t,
		state.completion_configuration.session.minimum_identifier_graphemes,
		u16(2),
	)
	testing.expect_value(t, state.completion_configuration.limits, completion.DEFAULT_LIMITS)
	testing.expect(t, state.recovery_policy.enabled)
	testing.expect_value(t, state.recovery_policy.strategy, recovery.Strategy.Hybrid)
	testing.expect_value(t, state.recovery_policy.startup, recovery.Startup_Policy.Ask)
	testing.expect_value(t, state.recovery_policy.generation, recovery.Policy_Generation(2))
	testing.expect_value(t, terminal_configuration.global.limits, terminal_session.DEFAULT_EVENT_LIMITS)
	testing.expect_value(t, terminal_configuration.global.attention, Terminal_Attention_Channel.None)
}

/* Verifies one complete declarative support payload survives host decoding. */
@(test)
language_support_payload_decodes :: proc(t: ^testing.T) {
	support :: `{"languages":[{"display-name":"Rust","filenames":[],"id":"rust","suffixes":[".rs"]}],"schema":1,"selections":[{"language":"rust","service":"rust-analyzer"}],"services":[{"command":["rust-analyzer"],"default":true,"display-name":"Rust Analyzer","enabled":true,"environment":[],"features":["diagnostics","completion"],"id":"rust-analyzer","initialization-options":{},"languages":["rust"],"root-markers":["Cargo.toml"],"settings":{}}]}`
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 +
		TERMINAL_CONFIGURATION_HEADER_BYTES + len(support) +
		INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	startup_configuration_test_put(batch[:], 344, len(support))
	support_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 +
		TERMINAL_CONFIGURATION_HEADER_BYTES
	copy(batch[support_offset:], support)
	startup_configuration_test_factory_indentation(batch[support_offset + len(support):])
	state, _, decoded := personal_configuration_startup_decode(batch[:])
	testing.expect(t, decoded)
	if !decoded do return
	encoded, copied := personal_configuration_language_support(state, batch[:])
	testing.expect(t, copied)
	testing.expect_value(t, string(encoded), support)
}

/* Verifies unknown public feature identities reject the complete host batch. */
@(test)
language_support_payload_rejects_unknown_feature :: proc(t: ^testing.T) {
	support :: `{"languages":[],"schema":1,"selections":[],"services":[{"command":["server"],"default":false,"display-name":"Server","enabled":true,"environment":[],"features":["unknown"],"id":"server","initialization-options":{},"languages":["rust"],"root-markers":[],"settings":{}}]}`
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 +
		TERMINAL_CONFIGURATION_HEADER_BYTES + len(support) +
		INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	startup_configuration_test_put(batch[:], 344, len(support))
	support_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 +
		TERMINAL_CONFIGURATION_HEADER_BYTES
	copy(batch[support_offset:], support)
	startup_configuration_test_factory_indentation(batch[support_offset + len(support):])
	_, _, decoded := personal_configuration_startup_decode(batch[:])
	testing.expect(t, !decoded)
}

/* Verifies configured Gutter fields decode without borrowing retained command state. */
@(test)
startup_config_applies_gutter_policy :: proc(t: ^testing.T) {
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 2 + TERMINAL_CONFIGURATION_HEADER_BYTES +
		len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) + INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	startup_configuration_test_put(batch[:], 72, 0)
	startup_configuration_test_put(batch[:], 80, 2)
	startup_configuration_test_put(batch[:], 88, 32_766)
	startup_configuration_test_put(batch[:], 96, 3)
	startup_configuration_test_put(batch[:], 112, 2)
	startup_configuration_test_put(batch[:], 120, 3)
	startup_configuration_test_put(batch[:], 128, 12)
	startup_configuration_test_put(batch[:], 136, 1)
	startup_configuration_test_put(batch[:], 144, 2)
	startup_configuration_test_put(batch[:], 152, 1)
	startup_configuration_test_put(batch[:], 160, 1)
	copy(batch[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES:], "|!")
	startup_configuration_test_factory_terminal(
		batch[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 2:],
	)
	support_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 2 +
		TERMINAL_CONFIGURATION_HEADER_BYTES
	copy(batch[support_offset:], EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)
	startup_configuration_test_factory_indentation(
		batch[support_offset + len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION):],
	)
	state, _, decoded := personal_configuration_startup_decode(batch[:])
	testing.expect(t, decoded)
	if !decoded do return
	testing.expect(t, !state.gutter_policy.visible)
	testing.expect_value(t, state.gutter_policy.side, gutter.Side.Right)
	testing.expect_value(t, state.gutter_policy.order, i16(-2))
	testing.expect_value(t, state.gutter_policy.mode, gutter.Numbering_Mode.Relative)
	testing.expect_value(t, state.gutter_policy.current_line, gutter.Current_Line_Presentation.Zero)
	testing.expect_value(t, state.gutter_policy.minimum_digits, u16(3))
	testing.expect_value(t, state.gutter_policy.maximum_digits, u16(12))
	commands: Command_Context
	command_context_apply_startup_configuration(&commands, state, batch[:])
	batch[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES] = '?'
	batch[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 1] = '?'
	testing.expect_value(t, commands.gutter_policy.separator.value, "|")
	testing.expect_value(t, commands.gutter_policy.separator.fallback, "!")
	testing.expect_value(t, commands.personal_configuration.gutter_policy.separator.value, "|")
}

/* Verifies Gutter provider bytes remain bounded before trailing terminal configuration. */
@(test)
startup_configuration_gutter_provider_precedes_terminal_configuration :: proc(t: ^testing.T) {
	provider :: "provider"
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 + len(provider) +
		TERMINAL_CONFIGURATION_HEADER_BYTES + len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) +
		INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	startup_configuration_test_put(batch[:], 168, u64(len(provider)))
	provider_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4
	copy(batch[provider_offset:], provider)
	startup_configuration_test_factory_terminal(batch[provider_offset + len(provider):])
	copy(
		batch[provider_offset + len(provider) + TERMINAL_CONFIGURATION_HEADER_BYTES:],
		EMPTY_LANGUAGE_SUPPORT_CONFIGURATION,
	)
	startup_configuration_test_factory_indentation(
		batch[provider_offset + len(provider) + TERMINAL_CONFIGURATION_HEADER_BYTES +
			len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION):],
	)
	state, _, decoded := personal_configuration_startup_decode(batch[:])
	testing.expect(t, decoded)
	if !decoded do return
	provider_bytes, copied := personal_configuration_gutter_provider_bytes(state, batch[:])
	testing.expect(t, copied)
	testing.expect_value(t, string(provider_bytes), provider)
}

/* Verifies startup configuration feedback is silent for absence and explicit for failures. */
@(test)
startup_report_handles_absent_and_rejected :: proc(t: ^testing.T) {
	absent: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 + TERMINAL_CONFIGURATION_HEADER_BYTES +
		len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) + INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(absent[:], 0)
	state, _, decoded := personal_configuration_startup_decode(absent[:])
	testing.expect(t, decoded)
	commands: Command_Context
	commands.personal_configuration = state
	command_context_report_startup_configuration(&commands, absent[:])
	testing.expect_value(t, commands.diagnostic_length, 0)

	message :: "expected an operand"
	rejected_bytes :: PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + len(message) + 4 +
		TERMINAL_CONFIGURATION_HEADER_BYTES + len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) +
		INDENTATION_CONFIGURATION_HEADER_BYTES
	rejected: [rejected_bytes]u8
	startup_configuration_test_factory_batch(rejected[:], u64(len(message)))
	startup_configuration_test_put(rejected[:], 8, 2)
	startup_configuration_test_put(rejected[:], 16, 3)
	startup_configuration_test_put(rejected[:], 24, 1)
	startup_configuration_test_put(rejected[:], 32, 1)
	startup_configuration_test_put(rejected[:], 40, u64(len(message)))
	copy(rejected[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES:], message)
	payload := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + len(message)
	copy(rejected[payload:], "│")
	copy(rejected[payload + len("│"):], "|")
	rejected_state, _, rejected_decoded := personal_configuration_startup_decode(rejected[:])
	testing.expect(t, rejected_decoded)
	commands.personal_configuration = rejected_state
	command_context_report_startup_configuration(
		&commands,
		rejected[:],
	)
	diagnostic := string(commands.diagnostic[:commands.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "Personal configuration rejected"))
	testing.expect(t, strings.contains(diagnostic, message))
	testing.expect(t, strings.contains(diagnostic, "factory configuration preserved"))
}

/* Verifies global and Workspace terminal settings decode with Workspace precedence. */
@(test)
terminal_configuration_decodes_workspace_precedence :: proc(t: ^testing.T) {
	terminal_bytes :: TERMINAL_CONFIGURATION_HEADER_BYTES +
		TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES + len("/bin/shwork/bin/bash")
	batch: [PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 + terminal_bytes +
		len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION) + INDENTATION_CONFIGURATION_HEADER_BYTES]u8
	startup_configuration_test_factory_batch(batch[:], 0)
	startup_configuration_test_put(batch[:], 328, terminal_bytes)
	terminal_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4
	terminal := batch[terminal_offset:]
	fixed_bytes :: TERMINAL_CONFIGURATION_HEADER_BYTES +
		TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES
	startup_configuration_test_put(terminal, 0, TERMINAL_CONFIGURATION_SCHEMA_VERSION)
	startup_configuration_test_settings(
		terminal, 8, 3, fixed_bytes, len("/bin/sh"), terminal_session.DEFAULT_EVENT_LIMITS,
	)
	startup_configuration_test_put(terminal, 80, 1)
	startup_configuration_test_put(terminal, 88, 0)
	workspace_record :: TERMINAL_CONFIGURATION_HEADER_BYTES
	identity_offset := fixed_bytes + len("/bin/sh")
	workspace_shell_offset := identity_offset + len("work")
	startup_configuration_test_put(terminal, workspace_record, u64(identity_offset))
	startup_configuration_test_put(terminal, workspace_record + 8, len("work"))
	startup_configuration_test_settings(
		terminal, workspace_record + 16, 2, workspace_shell_offset, len("/bin/bash"),
		terminal_session.DEFAULT_EVENT_LIMITS,
	)
	copy(terminal[fixed_bytes:], "/bin/shwork/bin/bash")
	copy(terminal[terminal_bytes:], EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)
	startup_configuration_test_factory_indentation(
		terminal[terminal_bytes + len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION):],
	)
	_, configuration, decoded := personal_configuration_startup_decode(batch[:])
	testing.expect(t, decoded)
	if !decoded do return
	testing.expect_value(t, terminal_configuration_global_shell(&configuration), "/bin/sh")
	identity: editor_session.Workspace_ID
	identity.length = u32(copy(identity.bytes[:], "work"))
	settings, configured := terminal_configuration_workspace_settings(&configuration, identity)
	testing.expect(t, configured)
	if configured {
		testing.expect_value(t, string(settings.shell[:settings.shell_length]), "/bin/bash")
		testing.expect_value(t, settings.attention, Terminal_Attention_Channel.Audible)
	}
}

/* startup_configuration_test_factory_batch writes one complete factory configuration fixture. */
startup_configuration_test_factory_batch :: proc(bytes: []u8, diagnostic_bytes: u64) {
	startup_configuration_test_put(bytes, 0, PERSONAL_CONFIGURATION_STARTUP_SCHEMA_VERSION)
	startup_configuration_test_put(bytes, 8, 1)
	startup_configuration_test_put(bytes, 16, 1)
	startup_configuration_test_put(bytes, 24, 2)
	startup_configuration_test_put(bytes, 32, 0)
	startup_configuration_test_put(bytes, 40, diagnostic_bytes)
	startup_configuration_test_put(bytes, 48, 1)
	startup_configuration_test_put(bytes, 56, 1)
	startup_configuration_test_put(bytes, 64, 0x1f)
	startup_configuration_test_put(bytes, 72, 1)
	startup_configuration_test_put(bytes, 80, 1)
	startup_configuration_test_put(bytes, 88, 32_868)
	startup_configuration_test_put(bytes, 96, 2)
	startup_configuration_test_put(bytes, 104, 1)
	startup_configuration_test_put(bytes, 112, 1)
	startup_configuration_test_put(bytes, 120, 4)
	startup_configuration_test_put(bytes, 128, 20)
	startup_configuration_test_put(bytes, 136, 0)
	startup_configuration_test_put(bytes, 144, 1)
	startup_configuration_test_put(bytes, 152, u64(len("│")))
	startup_configuration_test_put(bytes, 160, u64(len("|")))
	startup_configuration_test_put(bytes, 168, 0)
	startup_configuration_test_put(bytes, 176, 1)
	startup_configuration_test_put(bytes, 184, 1)
	startup_configuration_test_put(bytes, 192, 1)
	startup_configuration_test_put(bytes, 200, 1)
	startup_configuration_test_put(bytes, 208, 1)
	startup_configuration_test_put(bytes, 216, 1)
	startup_configuration_test_put(bytes, 224, 1)
	startup_configuration_test_put(bytes, 232, 2)
	startup_configuration_test_put(bytes, 240, 1)
	startup_configuration_test_put(bytes, 248, 1)
	startup_configuration_test_put(bytes, 256, 1)
	startup_configuration_test_put(bytes, 264, completion.MAX_COMPLETION_CANDIDATES)
	startup_configuration_test_put(bytes, 272, completion.MAX_COMPLETION_ADDITIONAL_EDITS)
	startup_configuration_test_put(bytes, 280, completion.MAX_COMPLETION_TEXT_BYTES)
	startup_configuration_test_put(bytes, 288, completion.MAX_COMPLETION_DETAIL_BYTES)
	startup_configuration_test_put(bytes, 296, completion.MAX_COMPLETION_RESOLVE_BYTES)
	startup_configuration_test_put(bytes, 304, completion.MAX_COMPLETION_IMPLEMENTATIONS)
	startup_configuration_test_put(bytes, 312, completion.MAX_COMPLETION_REPLACEMENTS)
	startup_configuration_test_put(bytes, 320, completion.MAX_COMPLETION_REQUEST_REPLACEMENTS)
	startup_configuration_test_put(bytes, 328, TERMINAL_CONFIGURATION_HEADER_BYTES)
	startup_configuration_test_put(bytes, 344, len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION))
	startup_configuration_test_put(bytes, 352, 1)
	startup_configuration_test_put(bytes, 360, 3)
	startup_configuration_test_put(bytes, 368, recovery.DEFAULT_DEBOUNCE_MILLISECONDS)
	startup_configuration_test_put(bytes, 376, recovery.DEFAULT_MAXIMUM_INTERVAL_MILLISECONDS)
	startup_configuration_test_put(bytes, 384, recovery.DEFAULT_RETENTION_SECONDS)
	startup_configuration_test_put(bytes, 392, recovery.DEFAULT_RECORDS_PER_BUFFER)
	startup_configuration_test_put(bytes, 400, recovery.DEFAULT_TOTAL_RECORDS)
	startup_configuration_test_put(bytes, 408, recovery.DEFAULT_RECORD_PAYLOAD_BYTES)
	startup_configuration_test_put(bytes, 416, recovery.DEFAULT_BUFFER_STORAGE_BYTES)
	startup_configuration_test_put(bytes, 424, recovery.DEFAULT_STORE_STORAGE_BYTES)
	startup_configuration_test_put(bytes, 432, recovery.DEFAULT_CLEANUP_RECORDS)
	startup_configuration_test_put(bytes, 440, 1)
	startup_configuration_test_put(bytes, 448, 1)
	startup_configuration_test_put(bytes, 456, INDENTATION_CONFIGURATION_HEADER_BYTES)
	if diagnostic_bytes == 0 && len(bytes) >= PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + 4 {
		copy(bytes[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES:], "│")
		copy(bytes[PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + len("│"):], "|")
	}
	terminal_offset := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + int(diagnostic_bytes) + 4
	if len(bytes) >= terminal_offset + TERMINAL_CONFIGURATION_HEADER_BYTES {
		startup_configuration_test_factory_terminal(bytes[terminal_offset:])
		support_offset := terminal_offset + TERMINAL_CONFIGURATION_HEADER_BYTES
		copy(bytes[support_offset:], EMPTY_LANGUAGE_SUPPORT_CONFIGURATION)
		startup_configuration_test_factory_indentation(
			bytes[support_offset + len(EMPTY_LANGUAGE_SUPPORT_CONFIGURATION):],
		)
	}
}

/* startup_configuration_test_factory_indentation writes one factory policy batch. */
startup_configuration_test_factory_indentation :: proc(bytes: []u8) {
	if len(bytes) < INDENTATION_CONFIGURATION_HEADER_BYTES do return
	startup_configuration_test_put(bytes, 0, INDENTATION_CONFIGURATION_SCHEMA_VERSION)
	startup_configuration_test_put(bytes, 8, 2)
	startup_configuration_test_put(bytes, 16, 4)
	startup_configuration_test_put(bytes, 24, 4)
	startup_configuration_test_put(bytes, 32, 0)
}

/* startup_configuration_test_factory_terminal writes the factory terminal policy. */
startup_configuration_test_factory_terminal :: proc(bytes: []u8) {
	startup_configuration_test_put(bytes, 0, TERMINAL_CONFIGURATION_SCHEMA_VERSION)
	startup_configuration_test_settings(
		bytes, 8, 1, TERMINAL_CONFIGURATION_HEADER_BYTES, 0,
		terminal_session.DEFAULT_EVENT_LIMITS,
	)
	startup_configuration_test_put(bytes, 80, 0)
	startup_configuration_test_put(bytes, 88, 0)
}

/* startup_configuration_test_settings writes one encoded terminal settings record. */
startup_configuration_test_settings :: proc(
	bytes: []u8,
	offset: int,
	attention: u64,
	shell_offset: int,
	shell_length: int,
	limits: terminal_session.Event_Limits,
) {
	startup_configuration_test_put(bytes, offset, attention)
	startup_configuration_test_put(bytes, offset + 8, u64(limits.event_entries))
	startup_configuration_test_put(bytes, offset + 16, limits.event_bytes)
	startup_configuration_test_put(bytes, offset + 24, limits.aggregate_event_entries)
	startup_configuration_test_put(bytes, offset + 32, limits.aggregate_event_bytes)
	startup_configuration_test_put(bytes, offset + 40, u64(limits.subscribers_per_session))
	startup_configuration_test_put(bytes, offset + 48, u64(limits.subscribers))
	startup_configuration_test_put(bytes, offset + 56, u64(shell_offset))
	startup_configuration_test_put(bytes, offset + 64, u64(shell_length))
}

/* startup_configuration_test_put writes one little-endian fixture word. */
startup_configuration_test_put :: proc(bytes: []u8, offset: int, value: u64) {
	written := endian.put_u64(bytes[offset:], .Little, value)
	assert(written)
}
