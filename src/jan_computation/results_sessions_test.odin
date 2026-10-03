// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

/* Verifies complete typed decoding, exact rows, copied payload, and stale rejection. */
@(test)
results_sessions_decode_complete_typed_results :: proc(t: ^testing.T) {
	scope := computation_test_scope()
	payload := "name\tvalue\nalpha\t3"
	descriptor := Typed_Result_Descriptor {
		operation_id = 41,
		type = .Table,
		collection = .Value,
		format = .Table,
		handling = .Replace,
		row_count = 2,
		byte_count = u64(len(payload)),
		complete = true,
	}
	output: [128]u8
	rows: [4]Result_Row
	decoded, copied, decoded_rows, ok, failure := decode_typed_result(
		{descriptor = descriptor, scope = scope, owner = computation_test_target(scope), payload = payload},
		scope,
		output[:],
		rows[:],
	)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, copied, payload)
	testing.expect_value(t, len(decoded_rows), 2)
	testing.expect_value(t, decoded.row_count, u32(2))
	testing.expect(t, decoded.content_hash != 0)

	stale := scope
	stale.analysis.source_revision += 1
	_, _, _, ok, failure = decode_typed_result(
		{descriptor = descriptor, scope = scope, owner = computation_test_target(scope), payload = payload},
		stale,
		output[:],
		rows[:],
	)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Stale)

	descriptor.complete = false
	_, _, _, ok, failure = decode_typed_result(
		{descriptor = descriptor, scope = scope, owner = computation_test_target(scope), payload = payload},
		scope,
		output[:],
		rows[:],
	)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Result_Decoding)
}

/* Verifies post-processing is stable and rejects missing or cyclic dependencies. */
@(test)
results_sessions_order_bounded_post_processing :: proc(t: ^testing.T) {
	steps := []Post_Process_Step {
		{identity = 3, dependency_count = 1},
		{identity = 1},
		{identity = 2, dependency_count = 1},
	}
	steps[0].dependencies[0] = 2
	steps[2].dependencies[0] = 1
	ordered: [3]u16
	count, ok, _ := order_result_post_processing(steps, ordered[:])
	testing.expect(t, ok)
	testing.expect_value(t, count, u16(3))
	testing.expect_value(t, ordered, [3]u16{1, 2, 3})
	steps[1].dependencies[0] = 3
	steps[1].dependency_count = 1
	_, cycle_ok, cycle_failure := order_result_post_processing(steps, ordered[:])
	testing.expect(t, !cycle_ok)
	testing.expect_value(t, cycle_failure.code, Failure_Code.Cycle)
	steps[1].dependencies[0] = 99
	_, missing_ok, missing_failure := order_result_post_processing(steps, ordered[:])
	testing.expect(t, !missing_ok)
	testing.expect_value(t, missing_failure.code, Failure_Code.Cycle)
}

/* Verifies publication rewrites only the exact owned result in one candidate. */
@(test)
results_sessions_publish_exact_owner_atomically :: proc(t: ^testing.T) {
	source_bytes: [128]u8
	for &value in source_bytes do value = '.'
	copy(source_bytes[30:34], "old\n")
	source := string(source_bytes[:])
	scope := computation_test_scope()
	scope.source_bytes = u64(len(source))
	target := computation_test_target(scope)
	payload := "new\n"
	decoded := Decoded_Result {
		descriptor = {operation_id = 43, type = .Text, collection = .Output, format = .Verbatim,
		              handling = .Append, byte_count = u64(len(payload)), complete = true},
		scope = scope,
		owner = target,
		byte_count = u64(len(payload)),
		complete = true,
	}
	replacement: [32]u8
	publication, replacement_text, ok, _ := prepare_result_publication(
		decoded,
		scope,
		{target = target, result_start = 30, result_end = 34, has_result = true, prior_result = source[30:34]},
		payload,
		replacement[:],
	)
	testing.expect(t, ok)
	testing.expect_value(t, replacement_text, "old\nnew\n")
	output: [256]u8
	updated, applied, _ := apply_result_publication(source, scope, publication, replacement_text, output[:])
	testing.expect(t, applied)
	testing.expect_value(t, updated[30:38], "old\nnew\n")
	testing.expect_value(t, updated[:30], source[:30])
	testing.expect_value(t, updated[38:], source[34:])

	stale := scope
	stale.analysis.source_revision += 1
	_, _, stale_ok, stale_failure := prepare_result_publication(decoded, stale,
		{target = target, result_start = 30, result_end = 34, has_result = true, prior_result = source[30:34]},
		payload, replacement[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
}

/* Verifies session reuse is explicit and restart never restores a process implicitly. */
@(test)
results_sessions_require_explicit_session_recovery :: proc(t: ^testing.T) {
	record := Session_Record {
		schema_version = COMPUTATION_SCHEMA_VERSION,
		session_id = 17,
		adapter_generation = 29,
		policy_generation = 31,
		source_revision = 7,
		state = .Prepared,
		last_activity_ns = 1,
	}
	session, created, _ := create_execution_session(record, "racket", "racket-langserver", .Document, 3)
	testing.expect(t, created)
	sessions := []Execution_Session{session}
	_, unnamed_ok, unnamed_failure := select_execution_session(sessions, 0, "racket", "racket-langserver", 29, .Document, 3, 7)
	testing.expect(t, !unnamed_ok)
	testing.expect_value(t, unnamed_failure.code, Failure_Code.Invalid_Request)

	started, _ := transition_execution_session(&sessions[0], .Start, 2, 9001)
	testing.expect(t, started)
	selected, selected_ok, _ := select_execution_session(sessions, 17, "racket", "racket-langserver", 29, .Document, 3, 7)
	testing.expect(t, selected_ok)
	testing.expect(t, selected == &sessions[0])
	restarted, _ := transition_execution_session(&sessions[0], .Restart, 3)
	testing.expect(t, restarted)
	testing.expect_value(t, sessions[0].record.state, Session_State.Recovery_Required)
	testing.expect_value(t, sessions[0].record.process_identity, u64(0))
	_, recovery_ok, recovery_failure := select_execution_session(sessions, 17, "racket", "racket-langserver", 29, .Document, 3, 7)
	testing.expect(t, !recovery_ok)
	testing.expect_value(t, recovery_failure.code, Failure_Code.Stale)
	reconnected, _ := transition_execution_session(&sessions[0], .Reconnect, 4, 9002)
	testing.expect(t, reconnected)
	invalidated, _ := transition_execution_session(&sessions[0], .Provider_Invalidated, 5)
	testing.expect(t, invalidated)
	cleaned, _ := transition_execution_session(&sessions[0], .Cleanup_Confirmed, 6)
	testing.expect(t, cleaned)
	testing.expect_value(t, sessions[0].record.state, Session_State.Closed)
}

/* Verifies complete cache keys, bounded eviction, inspection, and independent deletion. */
@(test)
results_sessions_bound_and_inspect_cache :: proc(t: ^testing.T) {
	entries: [2]Execution_Cache_Entry
	storage: [16]u8
	store, initialized := initialize_cache_store(entries[:], storage[:], 8)
	testing.expect(t, initialized)
	key := result_test_cache_key(7)
	first := "first"
	descriptor := Typed_Result_Descriptor {operation_id = 47, type = .Text, collection = .Output,
	                                      format = .Raw, handling = .Replace,
	                                      byte_count = u64(len(first)), complete = true}
	first_record, first_stored, _ := store_cache_result(&store, key, descriptor, first, 10)
	testing.expect(t, first_stored)
	inspection, payload, hit := inspect_cache(&store, key, 11)
	testing.expect(t, hit)
	testing.expect_value(t, inspection.reason, Cache_Inspection_Reason.Exact_Hit)
	testing.expect_value(t, payload, first)

	changed := key
	changed.cache_policy_digest[0] = 99
	inspection, _, hit = inspect_cache(&store, changed, 12)
	testing.expect(t, !hit)
	testing.expect_value(t, inspection.reason, Cache_Inspection_Reason.Key_Mismatch)

	second_key := result_test_cache_key(8)
	second := "other"
	descriptor.operation_id = 48
	descriptor.byte_count = u64(len(second))
	second_record, second_stored, _ := store_cache_result(&store, second_key, descriptor, second, 13)
	testing.expect(t, second_stored)
	_, _, hit = inspect_cache(&store, key, 14)
	testing.expect(t, !hit)
	testing.expect(t, first_record.entry_id != second_record.entry_id)
	eviction, evicted := evict_cache_entry(&store, second_record.entry_id)
	testing.expect(t, evicted)
	testing.expect_value(t, eviction.reason, Cache_Inspection_Reason.Explicit_Eviction)
	testing.expect_value(t, store.entry_count, u16(0))
}

@(private)
result_test_cache_key :: proc(seed: u8) -> Cache_Key {
	key := Cache_Key {adapter_generation = 29, policy_generation = 31}
	key.source_digest[0] = seed
	key.argument_digest[0] = 2
	key.input_digest[0] = 3
	key.reference_digest[0] = 4
	key.environment_digest[0] = 5
	key.adapter_identity_digest[0] = 6
	key.adapter_version_digest[0] = 7
	key.cache_policy_digest[0] = 8
	return key
}
