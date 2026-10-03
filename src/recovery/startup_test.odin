// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:os"
import "core:slice"
import "core:testing"

@(private)
startup_test_record :: proc(
	record_id, buffer_id: u64,
	source: string,
	source_bytes, payload: []u8,
) -> Record {
	return Record {
		record_id = Record_ID(record_id),
		buffer_id = Buffer_ID(buffer_id),
		source_present = len(source) > 0,
		source_identity = source,
		source_fingerprint = checkpoint_payload_digest(source_bytes) if len(source) > 0 else {},
		saved_revision = 1,
		recovered_revision = 2,
		encoding = .UTF_8,
		line_ending = .LF,
		payload_digest = checkpoint_payload_digest(payload),
		payload_bytes = u64(len(payload)),
		created_at_seconds = record_id,
		policy_generation = DEFAULT_POLICY.generation,
		format_version = RECOVERY_FORMAT_VERSION,
	}
}

/* Verifies startup independently classifies matching, changed, missing, and pathless sources. */
@(test)
startup_discovery_classifies_each_current_checkpoint :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	matching_path, _ := os.join_path({directory, "matching.txt"}, context.allocator)
	changed_path, _ := os.join_path({directory, "changed.txt"}, context.allocator)
	missing_path, _ := os.join_path({directory, "missing.txt"}, context.allocator)
	defer delete(matching_path)
	defer delete(changed_path)
	defer delete(missing_path)
	matching_source_text := "saved\n"
	changed_source_text := "before\n"
	matching_payload_text := "saved\ndraft\n"
	changed_payload_text := "before\ndraft\n"
	pathless_payload_text := "scratch\n"
	matching_source := transmute([]u8)matching_source_text
	changed_source := transmute([]u8)changed_source_text
	matching_payload := transmute([]u8)matching_payload_text
	changed_payload := transmute([]u8)changed_payload_text
	pathless_payload := transmute([]u8)pathless_payload_text
	testing.expect(t, os.write_entire_file(matching_path, matching_source) == nil)
	testing.expect(t, os.write_entire_file(changed_path, changed_source) == nil)
	matching := startup_test_record(1, 11, matching_path, matching_source, matching_payload)
	changed := startup_test_record(2, 12, changed_path, changed_source, changed_payload)
	missing := startup_test_record(3, 13, missing_path, matching_source, matching_payload)
	pathless := startup_test_record(4, 14, "", nil, pathless_payload)
	published, failure := store_publish(&store, matching, matching_payload)
	testing.expectf(t, published, "matching publish failed with %v", failure.code)
	published, failure = store_publish(&store, changed, changed_payload)
	testing.expectf(t, published, "changed publish failed with %v", failure.code)
	published, failure = store_publish(&store, missing, matching_payload)
	testing.expectf(t, published, "missing publish failed with %v", failure.code)
	published, failure = store_publish(&store, pathless, pathless_payload)
	testing.expectf(t, published, "pathless publish failed with %v", failure.code)
	after_text := "after\n"
	testing.expect(t, os.write_entire_file(changed_path, after_text) == nil)
	discovery, discovered, scan_failure := store_discover_startup_candidates(&store, context.allocator)
	testing.expectf(t, discovered, "discovery failed with %v", scan_failure.code)
	defer startup_discovery_close(&discovery)
	testing.expect_value(t, len(discovery.candidates), 4)
	testing.expect_value(t, discovery.candidates[0].candidate.state, Candidate_State.Restorable)
	testing.expect_value(t, discovery.candidates[1].candidate.state, Candidate_State.Conflict)
	testing.expect_value(t, discovery.candidates[2].candidate.state, Candidate_State.Missing_Source)
	testing.expect_value(t, discovery.candidates[3].candidate.state, Candidate_State.Pathless)
	testing.expect_value(t, discovery.candidates[1].candidate.conflict, Conflict_Reason.Source_Changed)
	contents, read_error := os.read_entire_file(changed_path, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(contents)
	testing.expect(t, slice.equal(contents, transmute([]u8)after_text))
}

/* Verifies one malformed current reference is quarantined while valid candidates remain available. */
@(test)
startup_discovery_quarantines_malformed_state_without_blocking :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload_text := "recover me"
	payload := transmute([]u8)payload_text
	record := startup_test_record(8, 28, "", nil, payload)
	published, failure := store_publish(&store, record, payload)
	testing.expectf(t, published, "publish failed with %v", failure.code)
	current := store_directory_path(&store, "current", context.allocator)
	defer delete(current)
	malformed, _ := os.join_path({current, "malformed.ref"}, context.allocator)
	defer delete(malformed)
	testing.expect(t, os.write_entire_file(malformed, []u8{1, 2, 3}) == nil)
	testing.expect(t, os.chmod(malformed, os.perm(int(PRIVATE_FILE_MODE))) == nil)
	discovery, discovered, scan_failure := store_discover_startup_candidates(&store, context.allocator)
	testing.expectf(t, discovered, "discovery failed with %v", scan_failure.code)
	defer startup_discovery_close(&discovery)
	testing.expect_value(t, len(discovery.candidates), 1)
	testing.expect_value(t, discovery.quarantined_records, u64(1))
	_, malformed_error := os.lstat(malformed, context.temp_allocator)
	testing.expect_value(t, malformed_error, os.Error(.Not_Exist))
	quarantine := store_directory_path(&store, "quarantine", context.allocator)
	defer delete(quarantine)
	entries, entries_error := os.read_all_directory_by_path(quarantine, context.allocator)
	testing.expect(t, entries_error == nil)
	defer os.file_info_slice_delete(entries, context.allocator)
	testing.expect_value(t, len(entries), 1)
}

/* Verifies candidate actions return exact content and reject stale observations. */
@(test)
startup_candidate_actions_revalidate_exact_identity :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	source_path, _ := os.join_path({directory, "source.txt"}, context.allocator)
	defer delete(source_path)
	source_text := "source\n"
	recovered_text := "source\nrecovered\n"
	testing.expect(t, os.write_entire_file(source_path, source_text) == nil)
	record := startup_test_record(
		51,
		61,
		source_path,
		transmute([]u8)source_text,
		transmute([]u8)recovered_text,
	)
	published, publish_failure := store_publish(&store, record, transmute([]u8)recovered_text)
	testing.expectf(t, published, "publish failed with %v", publish_failure.code)
	request := Candidate_Action_Request {
		record_id = record.record_id,
		buffer_id = record.buffer_id,
		recovered_revision = record.recovered_revision,
		action = .Compare,
	}
	result, applied, action_failure := store_apply_candidate_action(&store, request, context.allocator)
	testing.expectf(t, applied, "compare failed with %v", action_failure.code)
	if applied {
		testing.expect(t, slice.equal(result.checkpoint.payload, transmute([]u8)recovered_text))
		testing.expect(t, slice.equal(result.current_source, transmute([]u8)source_text))
		candidate_action_result_close(&result)
	}
	newer_text := "source\nnewer\n"
	newer := startup_test_record(
		52,
		61,
		source_path,
		transmute([]u8)source_text,
		transmute([]u8)newer_text,
	)
	newer.recovered_revision = 3
	published, publish_failure = store_publish(&store, newer, transmute([]u8)newer_text)
	testing.expectf(t, published, "newer publish failed with %v", publish_failure.code)
	_, applied, action_failure = store_apply_candidate_action(&store, request, context.allocator)
	testing.expect(t, !applied)
	testing.expect_value(t, action_failure.code, Persistence_Failure_Code.Candidate_Stale)
}

/* Verifies restore preserves exact pathless CRLF bytes and discard retires only that candidate. */
@(test)
startup_candidate_restore_and_discard_are_explicit :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload_text := "first\r\nsecond\r\n"
	payload := transmute([]u8)payload_text
	record := startup_test_record(71, 81, "", nil, payload)
	record.line_ending = .CRLF
	published, publish_failure := store_publish(&store, record, payload)
	testing.expectf(t, published, "publish failed with %v", publish_failure.code)
	request := Candidate_Action_Request {
		record_id = record.record_id,
		buffer_id = record.buffer_id,
		recovered_revision = record.recovered_revision,
		action = .Restore,
	}
	result, applied, action_failure := store_apply_candidate_action(&store, request, context.allocator)
	testing.expectf(t, applied, "restore failed with %v", action_failure.code)
	if applied {
		testing.expect_value(t, result.checkpoint.record.line_ending, Line_Ending.CRLF)
		testing.expect(t, slice.equal(result.checkpoint.payload, payload))
		candidate_action_result_close(&result)
	}
	request.action = .Discard
	result, applied, action_failure = store_apply_candidate_action(&store, request, context.allocator)
	testing.expectf(t, applied, "discard failed with %v", action_failure.code)
	candidate_action_result_close(&result)
	_, found, load_failure := store_load_current(&store, record.buffer_id, context.allocator)
	testing.expect(t, !found)
	testing.expect_value(t, load_failure.code, Persistence_Failure_Code.Read)
}
