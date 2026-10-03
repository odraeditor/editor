// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:os"
import "core:slice"
import "core:testing"

@(private)
test_store_open :: proc(t: ^testing.T) -> (Store, string) {
	directory, directory_error := os.make_directory_temp("", "odra-recovery-*", context.allocator)
	testing.expectf(t, directory_error == nil, "temporary directory failed with %v", directory_error)
	root_path, path_error := os.join_path({directory, "recovery", "v1"}, context.allocator)
	testing.expectf(t, path_error == nil, "recovery path failed with %v", path_error)
	store: Store
	initialized, failure := store_init(
		&store,
		Root {
			platform = .Linux,
			state_root = directory,
			recovery_root = root_path,
			private_directory_mode = PRIVATE_DIRECTORY_MODE,
			private_file_mode = PRIVATE_FILE_MODE,
		},
		DEFAULT_POLICY,
		context.allocator,
	)
	delete(root_path)
	testing.expectf(t, initialized, "store init failed with %v", failure.code)
	return store, directory
}

@(private)
test_record_for_payload :: proc(record_id, buffer_id, saved, recovered: u64, payload: []u8) -> Record {
	return Record {
		record_id = Record_ID(record_id),
		buffer_id = Buffer_ID(buffer_id),
		source_present = true,
		source_identity = "/project/note.txt",
		source_fingerprint = test_digest(3),
		saved_revision = saved,
		recovered_revision = recovered,
		encoding = .UTF_8,
		line_ending = .LF,
		payload_digest = checkpoint_payload_digest(payload),
		payload_bytes = u64(len(payload)),
		created_at_seconds = recovered,
		policy_generation = DEFAULT_POLICY.generation,
		format_version = RECOVERY_FORMAT_VERSION,
	}
}

/* Verifies an empty modified buffer remains a valid recoverable checkpoint. */
@(test)
empty_payload_round_trips_through_current_checkpoint :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload := []u8{}
	record := test_record_for_payload(90, 91, 1, 2, payload)
	published, failure := store_publish(&store, record, payload)
	testing.expectf(t, published, "empty publish failed with %v", failure.code)
	loaded, found, load_failure := store_load_current(&store, record.buffer_id, context.allocator)
	testing.expectf(t, found, "empty checkpoint load failed with %v", load_failure.code)
	if found {
		defer loaded_checkpoint_close(&loaded)
		testing.expect_value(t, loaded.record.payload_bytes, u64(0))
		testing.expect_value(t, len(loaded.payload), 0)
	}
}

/* Verifies publication survives store reopening with exact metadata and payload. */
@(test)
checkpoint_publication_round_trips_exact_revision :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	payload_text := "draft text"
	payload := transmute([]u8)payload_text
	record := test_record_for_payload(1, 4, 2, 3, payload)
	published, failure := store_publish(&store, record, payload)
	testing.expectf(t, published, "publish failed at %v with %v", failure.stage, failure.code)
	store_close(&store)

	root_path, path_error := os.join_path({directory, "recovery", "v1"}, context.allocator)
	testing.expect(t, path_error == nil)
	reopened, reopen_failure := store_init(
		&store,
		Root {
			platform = .Linux,
			state_root = directory,
			recovery_root = root_path,
			private_directory_mode = PRIVATE_DIRECTORY_MODE,
			private_file_mode = PRIVATE_FILE_MODE,
		},
		DEFAULT_POLICY,
		context.allocator,
	)
	delete(root_path)
	testing.expectf(t, reopened, "reopen failed with %v", reopen_failure.code)
	defer store_close(&store)
	loaded, found, load_failure := store_load_current(&store, Buffer_ID(4), context.allocator)
	testing.expectf(t, found, "load failed with %v", load_failure.code)
	defer loaded_checkpoint_close(&loaded)
	testing.expect_value(t, loaded.record.record_id, Record_ID(1))
	testing.expect_value(t, loaded.record.recovered_revision, u64(3))
	testing.expect_value(t, loaded.record.source_identity, "/project/note.txt")
	testing.expect(t, slice.equal(loaded.payload, payload))
}

/* Verifies every injected boundary leaves either the prior or complete next checkpoint current. */
@(test)
checkpoint_failure_boundaries_never_publish_partial_state :: proc(t: ^testing.T) {
	stages := [?]Persistence_Stage {
		.Before_Payload_Open,
		.After_Payload_Write,
		.After_Payload_Sync,
		.After_Payload_Rename,
		.After_Payload_Directory_Sync,
		.After_Record_Write,
		.After_Record_Sync,
		.After_Record_Rename,
		.After_Record_Directory_Sync,
		.After_Current_Write,
		.After_Current_Sync,
		.After_Current_Rename,
		.After_Current_Directory_Sync,
	}
	for stage in stages {
		store, directory := test_store_open(t)
		first_payload_text := "first"
		first_payload := transmute([]u8)first_payload_text
		first := test_record_for_payload(1, 8, 1, 2, first_payload)
		published, _ := store_publish(&store, first, first_payload)
		testing.expect(t, published)
		second_payload_text := "second"
		second_payload := transmute([]u8)second_payload_text
		second := test_record_for_payload(2, 8, 1, 3, second_payload)
		failure: Persistence_Failure
		published, failure = store_publish(&store, second, second_payload, {fail_at = stage})
		testing.expect(t, !published)
		testing.expect_value(t, failure.code, Persistence_Failure_Code.Injected)
		testing.expect_value(t, failure.stage, stage)
		loaded, found, load_failure := store_load_current(&store, Buffer_ID(8), context.allocator)
		testing.expectf(t, found, "stage %v made current unreadable: %v", stage, load_failure.code)
		if found {
			expected := Record_ID(1)
			if stage == .After_Current_Rename || stage == .After_Current_Directory_Sync {
				expected = Record_ID(2)
			}
			testing.expect_value(t, loaded.record.record_id, expected)
			loaded_checkpoint_close(&loaded)
		}
		store_close(&store)
		_ = os.remove_all(directory)
		delete(directory)
	}
}

/* Verifies retirement rejects stale confirmation and removes only the exact current revision. */
@(test)
checkpoint_retirement_requires_exact_revision :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload_text := "retire me"
	payload := transmute([]u8)payload_text
	record := test_record_for_payload(4, 14, 2, 3, payload)
	published, _ := store_publish(&store, record, payload)
	testing.expect(t, published)
	retired, failure := store_retire_current(&store, Buffer_ID(14), 2)
	testing.expect(t, !retired)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Revision_Mismatch)
	loaded, found, _ := store_load_current(&store, Buffer_ID(14), context.allocator)
	testing.expect(t, found)
	if found do loaded_checkpoint_close(&loaded)
	retired, failure = store_retire_current(&store, Buffer_ID(14), 3)
	testing.expectf(t, retired, "exact retirement failed with %v", failure.code)
	_, found, failure = store_load_current(&store, Buffer_ID(14), context.allocator)
	testing.expect(t, !found)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Read)
}

/* Verifies cleanup retains current state while enforcing age, count, and storage bounds. */
@(test)
retention_plan_is_bounded_and_deterministic :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.retention.records_per_buffer = 2
	policy.retention.total_records = 16
	policy.retention.maximum_age_seconds = MIN_RETENTION_SECONDS
	policy.storage.buffer_storage_bytes = MIN_BUFFER_STORAGE_BYTES
	policy.storage.store_storage_bytes = MIN_STORE_STORAGE_BYTES
	records: [18]Retention_Record
	for &record, index in records {
		record = Retention_Record {
			record_id = Record_ID(index + 1),
			buffer_id = Buffer_ID(index / 3 + 1),
			created_at_seconds = u64(index + 1),
			payload_bytes = 4 * MEBIBYTE,
			metadata_bytes = 200,
		}
	}
	records[17].current = true
	removed: [18]Record_ID
	count := retention_plan(records[:], policy, MIN_RETENTION_SECONDS + 20, removed[:])
	testing.expect(t, count > 0)
	for index in 0 ..< count do testing.expect(t, removed[index] != records[17].record_id)
	usage := retention_usage_after(records[:], removed[:count])
	testing.expect(t, usage.records <= policy.retention.total_records)
	testing.expect(t, usage.payload_bytes + usage.metadata_bytes <= policy.storage.store_storage_bytes)
}

/* Verifies physical cleanup removes superseded records while preserving the current checkpoint. */
@(test)
store_cleanup_preserves_current_checkpoint :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	store.policy.retention.records_per_buffer = 1
	for revision in 2 ..= 4 {
		payload_text := "checkpoint"
		payload := transmute([]u8)payload_text
		record := test_record_for_payload(u64(revision), 21, 1, u64(revision), payload)
		published, failure := store_publish(&store, record, payload)
		testing.expectf(t, published, "publish %d failed with %v", revision, failure.code)
	}
	result, cleaned, failure := store_cleanup(&store, 4)
	testing.expectf(t, cleaned, "cleanup failed with %v", failure.code)
	testing.expect_value(t, result.usage.records, u64(1))
	loaded, found, load_failure := store_load_current(&store, Buffer_ID(21), context.allocator)
	testing.expectf(t, found, "current checkpoint lost with %v", load_failure.code)
	if found {
		testing.expect_value(t, loaded.record.recovered_revision, u64(4))
		loaded_checkpoint_close(&loaded)
	}
}

/* Verifies truncated and corrupted publication metadata never becomes restorable. */
@(test)
checkpoint_loading_rejects_truncation_and_corruption :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload_text := "integrity"
	payload := transmute([]u8)payload_text
	record := test_record_for_payload(31, 31, 1, 2, payload)
	published, _ := store_publish(&store, record, payload)
	testing.expect(t, published)
	record_path, path_ok := store_record_path(&store, record.record_id, context.temp_allocator)
	testing.expect(t, path_ok)
	record_bytes, read_error := os.read_entire_file(record_path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	record_bytes[len(record_bytes) - 1] = record_bytes[len(record_bytes) - 1] ~ 0xff
	testing.expect(t, os.write_entire_file(record_path, record_bytes) == nil)
	delete(record_bytes, context.temp_allocator)
	delete(record_path, context.temp_allocator)
	_, found, failure := store_load_current(&store, record.buffer_id, context.allocator)
	testing.expect(t, !found)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Digest_Mismatch)

	second := test_record_for_payload(32, 32, 1, 2, payload)
	published, _ = store_publish(&store, second, payload)
	testing.expect(t, published)
	current_path, current_ok := store_current_path(&store, second.buffer_id, context.temp_allocator)
	testing.expect(t, current_ok)
	testing.expect(t, os.write_entire_file(current_path, []u8{1, 2, 3, 4}) == nil)
	delete(current_path, context.temp_allocator)
	_, found, failure = store_load_current(&store, second.buffer_id, context.allocator)
	testing.expect(t, !found)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Truncated)
}

/* Verifies permission denial and record-size exhaustion fail without exposing payloads. */
@(test)
checkpoint_failures_are_bounded_before_restore :: proc(t: ^testing.T) {
	store, directory := test_store_open(t)
	defer os.remove_all(directory)
	defer delete(directory)
	defer store_close(&store)
	payload_text := "private"
	payload := transmute([]u8)payload_text
	record := test_record_for_payload(41, 41, 1, 2, payload)
	published, _ := store_publish(&store, record, payload)
	testing.expect(t, published)
	current_path, path_ok := store_current_path(&store, record.buffer_id, context.temp_allocator)
	testing.expect(t, path_ok)
	testing.expect(t, os.chmod(current_path, {}) == nil)
	_, found, failure := store_load_current(&store, record.buffer_id, context.allocator)
	testing.expect(t, !found)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Permission)
	testing.expect(t, os.chmod(current_path, os.perm(int(PRIVATE_FILE_MODE))) == nil)
	delete(current_path, context.temp_allocator)

	limited := store.policy
	limited.storage.record_payload_bytes = MIN_RECORD_PAYLOAD_BYTES
	store.policy = limited
	large_payload := make([]u8, int(MIN_RECORD_PAYLOAD_BYTES + 1), context.temp_allocator)
	defer delete(large_payload, context.temp_allocator)
	large_payload[0] = 1
	large := test_record_for_payload(42, 42, 1, 2, large_payload)
	published, failure = store_publish(&store, large, large_payload)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Persistence_Failure_Code.Resource_Exhausted)
}
