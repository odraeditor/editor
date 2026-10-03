// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_formatter

import "../editor"
import "../transaction"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"
import "core:time"

@(private)
formatter_test_buffer :: proc(t: ^testing.T, allocator: runtime.Allocator, id: editor.Buffer_ID, text: string) -> editor.Buffer {
	buffer: editor.Buffer
	opened, failure := editor.buffer_init(
		&buffer,
		id,
		text,
		{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, opened, "buffer initialization failed: %v", failure.code)
	return buffer
}

@(private)
formatter_test_source :: proc(buffer: ^editor.Buffer, id: editor.Buffer_ID, text: string) -> Formatting_Source {
	return {
		formatter = {catalog_id = 1, catalog_generation = 1, id = 1, generation = 1},
		buffer = buffer,
		buffer_id = id,
		base_revision = 0,
		text = text,
		position_encoding = .UTF_16,
		scope = .Document,
		start_byte = 0,
		end_byte = u64(len(text)),
		limits = DEFAULT_LIMITS,
	}
}

@(private)
formatter_test_text :: proc(buffer: ^editor.Buffer, allocator := context.temp_allocator) -> (string, bool) {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return "", false
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok do return "", false
	bytes, allocation_error := make([]u8, int(stats.text_bytes), allocator)
	if allocation_error != nil do return "", false
	read, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, bytes)
	return string(bytes[:int(read)]), read_ok && read == stats.text_bytes
}

/* Verifies LSP formatting is ordered, exact-revision, committed once, and undo-identified. */
@(test)
formatting_lsp_result_commits_one_revisioned_transaction :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	buffer := formatter_test_buffer(t, allocator, 1_101, "a = 1\nb = 2\n")
	source := formatter_test_source(&buffer, 1_101, "a = 1\nb = 2\n")
	response := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":5}},"newText":"b=2"},{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},"newText":"a=1"}]}`))
	proposal, normalized, failure := formatting_proposal_from_lsp(source, response, allocator)
	testing.expectf(t, normalized, "formatting normalization failed: %v", failure.code)
	if normalized {
		root: transaction.Multibuffer_Transaction
		prepared, prepare_failure := transaction.proposal_prepare(
			&root,
			1_101,
			1_101,
			proposal.edit,
			{persistent = allocator, temporary = context.temp_allocator},
		)
		testing.expectf(t, prepared, "formatting preparation failed: %v", prepare_failure.code)
		if prepared {
			result, committed, commit_failure := transaction.multibuffer_commit(&root)
			testing.expectf(t, committed, "formatting commit failed: %v", commit_failure.code)
			testing.expect_value(t, result.undo_unit_id, transaction.Undo_Unit_ID(1_101))
			text, copied := formatter_test_text(&buffer)
			testing.expect(t, copied)
			testing.expect_value(t, text, "a=1\nb=2\n")
			transaction.multibuffer_close(&root)
		}
		formatting_proposal_close(&proposal)
	}
	editor.buffer_close(&buffer)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies malformed, overlapping, and stale formatter results publish nothing. */
@(test)
formatting_rejects_malformed_overlapping_and_stale_results :: proc(t: ^testing.T) {
	buffer := formatter_test_buffer(t, context.allocator, 1_103, "abcd")
	defer editor.buffer_close(&buffer)
	source := formatter_test_source(&buffer, 1_103, "abcd")
	malformed := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":[{"range":{},"newText":"x"}]}`))
	_, accepted, failure := formatting_proposal_from_lsp(source, malformed)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Malformed_Output)
	overlap := transmute([]u8)(string(`{"jsonrpc":"2.0","id":1,"result":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"x"},{"range":{"start":{"line":0,"character":2},"end":{"line":0,"character":4}},"newText":"y"}]}`))
	_, accepted, failure = formatting_proposal_from_lsp(source, overlap)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Overlapping_Edit)

	source.base_revision = 1
	_, accepted, failure = formatting_proposal_from_output(source, transmute([]u8)(string("ABCD")))
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Input)
}

/* Verifies formatter proposal allocation failure retains no partial owner. */
@(test)
formatting_allocation_failure_and_cleanup_are_exact :: proc(t: ^testing.T) {
	buffer := formatter_test_buffer(t, context.allocator, 1_107, "abc")
	defer editor.buffer_close(&buffer)
	failing := Formatter_Test_Failing_Allocator{backing = context.allocator, fail_after = 1}
	proposal, accepted, failure := formatting_proposal_from_output(
		formatter_test_source(&buffer, 1_107, "abc"),
		transmute([]u8)(string("ABC")),
		formatter_test_failing_allocator(&failing),
	)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
	testing.expect(t, proposal.state == nil)
}

/* Verifies direct argv execution, output limits, deadlines, temp-file output, and cleanup. */
@(test)
external_formatter_execution_is_bounded_and_cleans_up :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	definition := formatter_test_external_record("/usr/bin/tr", []string{"a-z", "A-Z"}, .Standard_Input, .Standard_Output)
	run, started, failure := external_run_start({
		definition = &definition,
		input = transmute([]u8)(string("alpha")),
		admitted_root = "/tmp",
		working_directory = "/tmp",
		project_trusted = true,
		now_ns = 1,
	}, allocator)
	testing.expectf(t, started, "external formatter start failed: %v", failure.code)
	if started {
		external_test_poll_until_done(&run, 1)
		output, completed, output_failure := external_run_output(&run)
		testing.expectf(t, completed, "external formatter failed: %v", output_failure.code)
		testing.expect_value(t, string(output), "ALPHA")
		external_run_close(&run)
	}

	limited := formatter_test_external_record("/usr/bin/yes", nil, .Standard_Input, .Standard_Output)
	limited.limits.output_bytes = 128
	run, started, _ = external_run_start({definition = &limited, admitted_root = "/tmp", working_directory = "/tmp", project_trusted = true, now_ns = 1}, allocator)
	if started {
		poll := external_test_poll_until_done(&run, 1)
		testing.expect_value(t, poll.failure.code, Failure_Code.Output_Limit)
		external_run_close(&run)
	}

	temporary := formatter_test_external_record("/usr/bin/sed", []string{"-i", "s/a/A/g", TEMPORARY_FILE_ARGUMENT}, .Temporary_File, .Temporary_File)
	run, started, _ = external_run_start({definition = &temporary, input = transmute([]u8)(string("aba")), admitted_root = "/tmp", working_directory = "/tmp", project_trusted = true, now_ns = 1}, allocator)
	if started {
		state := external_state(&run)
		path_storage: [MAX_PATH_BYTES]u8
		path_length := copy(path_storage[:], state.temporary_path)
		external_test_poll_until_done(&run, 1)
		output, completed, _ := external_run_output(&run)
		testing.expect(t, completed)
		testing.expect_value(t, string(output), "AbA")
		external_run_close(&run)
		_, stat_error := os.stat(string(path_storage[:path_length]), context.temp_allocator)
		testing.expect(t, stat_error != nil)
	}

	timed := formatter_test_external_record("/usr/bin/sleep", []string{"5"}, .Standard_Input, .Standard_Output)
	timed.limits.timeout_ns = 1
	run, started, _ = external_run_start({definition = &timed, admitted_root = "/tmp", working_directory = "/tmp", project_trusted = true, now_ns = 1}, allocator)
	if started {
		poll, _ := external_run_poll(&run, 3)
		testing.expect_value(t, poll.status, External_Run_Status.Timed_Out)
		external_run_close(&run)
	}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
formatter_test_external_record :: proc(executable: string, arguments: []string, input: Input_Mode, output: Output_Mode) -> Formatter_Record {
	record := Formatter_Record {
		kind = .External,
		input_mode = input,
		output_mode = output,
		limits = DEFAULT_LIMITS,
		profile = {availability = .Available},
	}
	copy_text(executable, &record.profile.resolved)
	for argument, index in arguments do copy_text(argument, &record.arguments[index])
	record.argument_count = u8(len(arguments))
	return record
}

@(private)
external_test_poll_until_done :: proc(run: ^External_Run, now: i64) -> External_Run_Poll {
	result: External_Run_Poll
	for index in 0..<2_000 {
		result, _ = external_run_poll(run, now + i64(index) * i64(time.Millisecond))
		if result.status != .Running do return result
		time.sleep(time.Millisecond)
	}
	return result
}

@(private = "file")
Formatter_Test_Failing_Allocator :: struct {
	backing: runtime.Allocator,
	fail_after: u64,
	successful: u64,
}

@(private = "file")
formatter_test_failing_allocator :: proc(data: ^Formatter_Test_Failing_Allocator) -> runtime.Allocator {
	return {procedure = formatter_test_failing_allocator_proc, data = data}
}

@(private = "file")
formatter_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Formatter_Test_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful += 1
	}
	return allocator.backing.procedure(allocator.backing.data, mode, size, alignment, old_memory, old_size, location)
}
