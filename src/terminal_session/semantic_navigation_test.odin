// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "core:time"
import "../terminal_emulator"

@(test)
/* Verifies only complete OSC 133 boundaries create prompt and result records. */
semantic_requires_confirmed_boundaries :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	record, opened, open_failure := registry_open(
		&registry,
		test_open_request("semantic-confirmed", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expectf(t, opened, "terminal open failed with %v", open_failure.code)
	if !opened do return
	session := semantic_test_session(&registry, record.ref)
	testing.expect(t, session != nil)
	if session == nil do return

	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("$ prompt-looking text\r\n"))), terminal_emulator.Result.OK)
	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("\x1b]133;"))), terminal_emulator.Result.OK)
	stats, inspected, inspect_failure := registry_semantic_stats(&registry, record.ref)
	testing.expectf(t, inspected, "semantic stats failed with %v", inspect_failure.code)
	testing.expect_value(t, stats.prompt_records, u16(0))

	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("A\x07λ> "))), terminal_emulator.Result.OK)
	oversized: [MAX_OSC_133_BYTES + 16]u8
	for &byte in oversized do byte = 'x'
	copy(oversized[:], transmute([]u8)(string("\x1b]133;A;")))
	oversized[len(oversized) - 1] = 0x07
	testing.expect_value(t, semantic_write_session(session, oversized[:]), terminal_emulator.Result.OK)
	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("\x1b]133;B\x07echo one\x1b]133;C\x07one\r\n"))), terminal_emulator.Result.OK)
	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("\x1b]133;D;7\x07"))), terminal_emulator.Result.OK)
	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(string("\x1b]133;B\x07echo two\x1b]133;C\x07two\r\n\x1b]133;D\x07"))), terminal_emulator.Result.OK)
	stats, inspected, inspect_failure = registry_semantic_stats(&registry, record.ref)
	testing.expectf(t, inspected, "semantic stats failed with %v", inspect_failure.code)
	testing.expect_value(t, stats.prompt_records, u16(1))
	testing.expect_value(t, stats.result_records, u16(2))
	results: [2]Command_Result_Record
	copied, required, copied_ok, copy_failure := registry_copy_command_results(
		&registry, record.ref, results[:],
	)
	testing.expectf(t, copied_ok, "result copy failed with %v", copy_failure.code)
	testing.expect_value(t, copied, 2)
	testing.expect_value(t, required, 2)
	testing.expect(t, results[0].exit_status_present)
	testing.expect_value(t, results[0].exit_status, i32(7))
	testing.expect(t, results[0].output_start_bytes < results[0].output_end_bytes)
	testing.expect(t, results[1].sequence > results[0].sequence)
	testing.expect(t, !results[1].exit_status_present)
}

@(test)
/* Verifies the bounded PTY output path preserves split OSC 133 parser state. */
semantic_observes_split_pty_output :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request(
			"semantic-pty",
			arguments = []string {
				"-c",
				"printf '\\033]133;'; sleep 0.02; " +
					"printf 'A\\a> \\033]133;B\\aecho ok\\033]133;C\\aok\\r\\n\\033]133;D;0\\a'",
			},
		),
	)
	testing.expect(t, opened)
	if !opened do return
	for turn in 0 ..< 1_000 {
		observation, stepped := registry_step_output(&registry, record.ref, i64(turn + 1))
		testing.expectf(t, stepped, "semantic PTY output failed with %v", observation.failure.code)
		if !stepped do return
		stats, stats_ok, _ := registry_semantic_stats(&registry, record.ref)
		if stats_ok && stats.prompt_records == 1 && stats.result_records == 1 do return
		if !observation.progress do time.sleep(time.Millisecond)
	}
	testing.expectf(t, false, "semantic PTY records were not observed")
}

@(test)
/* Verifies prompt movement is ordered, bounded, and generation-local. */
semantic_moves_retained_prompts :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request("semantic-move", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return
	session := semantic_test_session(&registry, record.ref)
	if session == nil do return
	content := "\x1b]133;A\x07first> \x1b]133;B\x07one\x1b]133;C\x07x\r\n\x1b]133;D;0\x07\x1b]133;A\x1b\\second> "
	testing.expect_value(t, semantic_write_session(session, transmute([]u8)(content)), terminal_emulator.Result.OK)

	first, first_ok, first_failure := registry_move_prompt(&registry, record.ref, 0, .Next)
	testing.expectf(t, first_ok, "first prompt failed with %v", first_failure.code)
	second, second_ok, second_failure := registry_move_prompt(
		&registry, record.ref, first.sequence, .Next,
	)
	testing.expectf(t, second_ok, "second prompt failed with %v", second_failure.code)
	testing.expect(t, second.sequence > first.sequence)
	previous, previous_ok, previous_failure := registry_move_prompt(
		&registry, record.ref, second.sequence, .Previous,
	)
	testing.expectf(t, previous_ok, "previous prompt failed with %v", previous_failure.code)
	testing.expect_value(t, previous.sequence, first.sequence)
	_, past_end, past_end_failure := registry_move_prompt(
		&registry, record.ref, second.sequence, .Next,
	)
	testing.expect(t, !past_end)
	testing.expect_value(t, past_end_failure.code, Failure_Code.Navigation_Unavailable)

	closed, _ := registry_close_session(&registry, record.ref)
	testing.expect(t, closed)
	_, stale_ok, stale_failure := registry_move_prompt(&registry, record.ref, 0, .Next)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Reference)
}

@(test)
/* Verifies alternate-screen markers are excluded and tracked prompts invalidate on eviction. */
semantic_excludes_alt_screen_and_eviction :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer registry_close(&registry)
	request := test_open_request("semantic-eviction", arguments = []string{"-c", "sleep 30"})
	request.emulator.columns = 10
	request.emulator.rows = 3
	request.start.columns = 10
	request.start.rows = 3
	request.limits.scrollback_bytes = 1
	request.limits.scrollback_rows = 5
	record, opened, _ := registry_open(&registry, request)
	testing.expect(t, opened)
	if !opened do return
	session := semantic_test_session(&registry, record.ref)
	if session == nil do return

	_ = semantic_write_session(session, transmute([]u8)(string("\x1b[?1049h\x1b]133;A\x07alternate> \x1b[?1049l")))
	_ = semantic_write_session(session, transmute([]u8)(string("\x1b]133;A\x07primary> ")))
	stats, stats_ok, _ := registry_semantic_stats(&registry, record.ref)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.prompt_records, u16(1))
	first, first_ok, _ := registry_move_prompt(&registry, record.ref, 0, .Next)
	testing.expect(t, first_ok)

	filler := transmute([]u8)(string("012345678901234567890123456789\r\n"))
	for _ in 0 ..< 5_000 do _ = semantic_write_session(session, filler)
	_ = semantic_write_session(session, transmute([]u8)(string("\x1b]133;A\x07new> ")))
	stats, stats_ok, _ = registry_semantic_stats(&registry, record.ref)
	testing.expect(t, stats_ok)
	testing.expect_value(t, stats.prompt_records, u16(1))
	newest, newest_ok, _ := registry_move_prompt(&registry, record.ref, 0, .Previous)
	testing.expect(t, newest_ok)
	testing.expect(t, newest.sequence > first.sequence)
	_, stale_ok, stale_failure := registry_move_prompt(
		&registry, record.ref, first.sequence, .Next,
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Navigation_Unavailable)
}

@(private)
semantic_test_session :: proc(registry: ^Registry, ref: Session_Ref) -> ^Session_State {
	state := registry_state(registry)
	if state == nil do return nil
	session, resolved := registry_resolve(state, ref)
	if !resolved do return nil
	return session
}
