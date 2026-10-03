// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

/* Verifies child effects remain typed, bounded, denied, and policy-controlled. */
@(test)
effects_are_governed_without_granting_child_authority :: proc(t: ^testing.T) {
	registry: Registry
	initialized, initialize_failure := registry_init(&registry)
	testing.expectf(t, initialized, "registry initialization failed: %v", initialize_failure.code)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}

	record, opened, open_failure := registry_open(
		&registry,
		test_open_request("governed effects", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expectf(t, opened, "terminal open failed: %v", open_failure.code)
	if !opened do return
	policy := Effect_Policy{attention = .Both, bell_interval_nanoseconds = 100}
	_, configured, configure_failure := registry_effect_configure(&registry, record.ref, policy)
	testing.expectf(t, configured, "effect policy failed: %v", configure_failure.code)
	if !configured do return

	bytes := transmute([]u8)(string(
		"\x1b]2;build terminal\x1b\\" +
		"\x1b]7;file:///tmp/work\x1b\\" +
		"\x07" +
		"\x1b]52;c;aGk=\x1b\\" +
		"\x1b]52;c;?\x1b\\" +
		"\x1b]9;notice\x1b\\" +
		"\x1b]9;4;1;42\x1b\\" +
		"\x1b_unknown-effect\x1b\\",
	))
	write_result := terminal_emulator.write(record.emulator, bytes)
	testing.expect_value(t, write_result, terminal_emulator.Result.OK)
	if write_result != .OK do return

	state := registry_state(&registry)
	session, resolved := registry_resolve(state, record.ref)
	testing.expect(t, resolved)
	if !resolved do return
	observation: Output_Observation
	effect_failure := output_observe_effects(state, session, &observation, 1_000)
	testing.expect_value(t, effect_failure.code, Failure_Code.None)
	testing.expect_value(t, observation.effects.bell_requests, u64(1))
	testing.expect(t, observation.effects.bell_admitted)
	testing.expect(t, observation.effects.audible_attention)
	testing.expect(t, observation.effects.visual_attention)
	testing.expect(t, observation.effects.title_changed)
	testing.expect(t, observation.effects.working_context_changed)
	testing.expect(t, observation.effects.denied_effects >= 3)
	testing.expect(t, observation.effects.progress_changed)
	testing.expect(t, observation.effects.diagnostics >= observation.effects.denied_effects)

	title: [64]u8
	title_copy, title_ok, title_failure := registry_metadata_copy(
		&registry, record.ref, .Title, title[:],
	)
	testing.expectf(t, title_ok, "title copy failed: %v", title_failure.code)
	if title_ok {
		testing.expect_value(t, string(title[:title_copy.copied_bytes]), "build terminal")
		testing.expect(t, !title_copy.truncated)
	}
	working_context: [64]u8
	context_copy, context_ok, context_failure := registry_metadata_copy(
		&registry, record.ref, .Working_Context, working_context[:],
	)
	testing.expectf(t, context_ok, "working-context copy failed: %v", context_failure.code)
	if context_ok {
		testing.expect_value(
			t, string(working_context[:context_copy.copied_bytes]), "file:///tmp/work",
		)
	}
	effect_record, effects_ok, effects_failure := registry_effect_record(&registry, record.ref)
	testing.expectf(t, effects_ok, "effect record failed: %v", effects_failure.code)
	if effects_ok {
		testing.expect_value(t, effect_record.policy, policy)
		testing.expect_value(t, effect_record.progress_state, Progress_State.Set)
		testing.expect_value(t, effect_record.progress_percent, i16(42))
		testing.expect(t, effect_record.clipboard_read_denials >= 1)
		testing.expect(t, effect_record.clipboard_write_denials >= 1)
		testing.expect(t, effect_record.notification_denials >= 1)
		testing.expect(t, effect_record.unknown_sequences >= 1)
	}

	write_result = terminal_emulator.write(record.emulator, []u8{'\x07'})
	testing.expect_value(t, write_result, terminal_emulator.Result.OK)
	observation = {}
	effect_failure = output_observe_effects(state, session, &observation, 1_050)
	testing.expect_value(t, effect_failure.code, Failure_Code.None)
	testing.expect(t, !observation.effects.bell_admitted)
	testing.expect(t, !observation.effects.audible_attention)
	testing.expect(t, !observation.effects.visual_attention)

	write_result = terminal_emulator.write(record.emulator, []u8{'\x07'})
	testing.expect_value(t, write_result, terminal_emulator.Result.OK)
	observation = {}
	effect_failure = output_observe_effects(state, session, &observation, 1_100)
	testing.expect_value(t, effect_failure.code, Failure_Code.None)
	testing.expect(t, observation.effects.bell_admitted)
	effect_record, effects_ok, _ = registry_effect_record(&registry, record.ref)
	if effects_ok {
		testing.expect_value(t, effect_record.bell_requests, u64(3))
		testing.expect_value(t, effect_record.bell_admitted, u64(2))
		testing.expect_value(t, effect_record.bell_suppressed, u64(1))
	}
}

/* Verifies hostile metadata stays inert while unknown diagnostics remain bounded. */
@(test)
effects_retain_last_valid_metadata_after_hostile_input :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	record, opened, _ := registry_open(
		&registry,
		test_open_request("hostile metadata", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return
	state := registry_state(&registry)
	session, resolved := registry_resolve(state, record.ref)
	testing.expect(t, resolved)
	if !resolved do return

	valid := transmute([]u8)(string("\x1b]2;retained\x1b\\"))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, valid), terminal_emulator.Result.OK,
	)
	observation: Output_Observation
	testing.expect_value(
		t, output_observe_effects(state, session, &observation, 1).code, Failure_Code.None,
	)

	oversized: [MAX_METADATA_BYTES + 7]u8
	oversized[0] = '\x1b'
	oversized[1] = ']'
	oversized[2] = '2'
	oversized[3] = ';'
	for index in 4 ..< len(oversized) - 2 do oversized[index] = 'x'
	oversized[len(oversized) - 2] = '\x1b'
	oversized[len(oversized) - 1] = '\\'
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, oversized[:]),
		terminal_emulator.Result.OK,
	)
	observation = {}
	testing.expect_value(
		t, output_observe_effects(state, session, &observation, 2).code, Failure_Code.None,
	)
	testing.expect(t, !observation.effects.title_changed)

	unknown: [terminal_emulator.UNKNOWN_CAPTURE_BYTES + 5]u8
	unknown[0] = '\x1b'
	unknown[1] = '_'
	for index in 2 ..< len(unknown) - 2 do unknown[index] = 'u'
	unknown[len(unknown) - 2] = '\x1b'
	unknown[len(unknown) - 1] = '\\'
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, unknown[:]), terminal_emulator.Result.OK,
	)
	observation = {}
	testing.expect_value(
		t, output_observe_effects(state, session, &observation, 3).code, Failure_Code.None,
	)
	testing.expect(t, observation.effects.diagnostics > 0)

	title: [32]u8
	metadata, copied, copy_failure := registry_metadata_copy(&registry, record.ref, .Title, title[:])
	testing.expectf(t, copied, "metadata copy failed: %v", copy_failure.code)
	if copied do testing.expect_value(t, string(title[:metadata.copied_bytes]), "retained")
	effects, found, effect_failure := registry_effect_record(&registry, record.ref)
	testing.expectf(t, found, "effect record failed: %v", effect_failure.code)
	if found {
		testing.expect_value(t, effects.metadata_revision, u64(1))
		testing.expect(t, effects.unknown_sequences >= 1)
		testing.expect(t, effects.unknown_sequence_bytes <= terminal_emulator.UNKNOWN_CAPTURE_BYTES)
	}

	short: [5]u8
	short_copy, short_ok, _ := registry_metadata_copy(&registry, record.ref, .Title, short[:])
	testing.expect(t, short_ok)
	if short_ok {
		testing.expect(t, short_copy.truncated)
		testing.expect_value(t, string(short[:short_copy.copied_bytes]), "retai")
	}
	_, invalid_ok, invalid_failure := registry_metadata_copy(
		&registry, record.ref, .Invalid, short[:],
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Argument)
}
