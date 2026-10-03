// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "base:runtime"
import "core:crypto/sha2"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

RECOVERY_RECORD_HEADER_BYTES :: 168
RECOVERY_CURRENT_BYTES :: 56
RECOVERY_RECORD_MAGIC :: "ODRAREC1"
RECOVERY_CURRENT_MAGIC :: "ODRACUR1"
MAX_SOURCE_IDENTITY_BYTES :: 64 * KIBIBYTE

/* Persistence_Stage identifies an observable checkpoint publication boundary. */
Persistence_Stage :: enum u8 {
	None,
	Before_Payload_Open,
	After_Payload_Write,
	After_Payload_Sync,
	After_Payload_Rename,
	After_Payload_Directory_Sync,
	After_Record_Write,
	After_Record_Sync,
	After_Record_Rename,
	After_Record_Directory_Sync,
	After_Current_Write,
	After_Current_Sync,
	After_Current_Rename,
	After_Current_Directory_Sync,
}

/* Persistence_Failure_Code classifies durable-store failure without private content. */
Persistence_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Invalid_Record,
	Allocation,
	Directory,
	Permission,
	Open,
	Write,
	Sync,
	Rename,
	Read,
	Malformed,
	Truncated,
	Digest_Mismatch,
	Resource_Exhausted,
	Revision_Mismatch,
	Candidate_Stale,
	Action_Unavailable,
	Injected,
}

/* Persistence_Failure identifies the failed stage and public recovery identities. */
Persistence_Failure :: struct {
	code:      Persistence_Failure_Code,
	stage:     Persistence_Stage,
	record_id: Record_ID,
	buffer_id: Buffer_ID,
	limit:     u64,
	actual:    u64,
}

/* Publication_Options supports deterministic failure injection in focused tests. */
Publication_Options :: struct {
	fail_at: Persistence_Stage,
}

/* Store owns one private native recovery namespace. */
Store :: struct {
	root:      string,
	policy:    Policy,
	platform:  Platform,
	allocator: runtime.Allocator,
	live:      bool,
}

/* Loaded_Checkpoint owns copied metadata and payload from one verified current record. */
Loaded_Checkpoint :: struct {
	record:         Record,
	source_storage: string,
	payload:        []u8,
	allocator:      runtime.Allocator,
}

/* Retention_Record is the bounded metadata used for deterministic cleanup planning. */
Retention_Record :: struct {
	record_id:          Record_ID,
	buffer_id:          Buffer_ID,
	created_at_seconds: u64,
	payload_bytes:      u64,
	metadata_bytes:     u64,
	current:            bool,
}

/* Cleanup_Result reports bounded physical retirement and remaining logical usage. */
Cleanup_Result :: struct {
	removed_records: u64,
	usage:           Resource_Usage,
}

@(private)
Stored_Record_Inventory :: struct {
	retention: Retention_Record,
	digest:    Digest,
}

/* checkpoint_payload_digest returns the SHA-256 identity of one immutable payload. */
checkpoint_payload_digest :: proc(payload: []u8) -> (digest: Digest) {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, payload)
	sha2.final(&ctx, digest[:])
	return
}

/* store_init prepares a private recovery namespace without inspecting source files. */
store_init :: proc(
	store: ^Store,
	root: Root,
	policy: Policy,
	allocator: runtime.Allocator,
) -> (bool, Persistence_Failure) {
	if store == nil || store.live || allocator.procedure == nil {
		return false, Persistence_Failure{code = .Invalid_State}
	}
	if root_ok, _ := root_validate(root); !root_ok {
		return false, Persistence_Failure{code = .Invalid_State}
	}
	if policy_ok, _ := policy_validate(policy); !policy_ok || !policy.enabled {
		return false, Persistence_Failure{code = .Invalid_State}
	}
	owned_root, allocation_error := strings.clone(root.recovery_root, allocator)
	if allocation_error != nil {
		return false, Persistence_Failure{code = .Allocation}
	}
	if !store_prepare_directories(owned_root, root.platform) {
		delete(owned_root, allocator)
		return false, Persistence_Failure{code = .Directory}
	}
	store^ = Store {
		root = owned_root,
		policy = policy,
		platform = root.platform,
		allocator = allocator,
		live = true,
	}
	return true, {}
}

/* store_close releases one initialized store handle without deleting recovery data. */
store_close :: proc(store: ^Store) {
	if store == nil || !store.live do return
	delete(store.root, store.allocator)
	store^ = {}
}

/* loaded_checkpoint_close releases one verified loaded checkpoint. */
loaded_checkpoint_close :: proc(checkpoint: ^Loaded_Checkpoint) {
	if checkpoint == nil do return
	if checkpoint.payload != nil do delete(checkpoint.payload, checkpoint.allocator)
	if len(checkpoint.source_storage) > 0 do delete(checkpoint.source_storage, checkpoint.allocator)
	checkpoint^ = {}
}

/* store_publish atomically publishes payload, record, then current reference. */
store_publish :: proc(
	store: ^Store,
	record: Record,
	payload: []u8,
	options: Publication_Options = {},
) -> (bool, Persistence_Failure) {
	failure := Persistence_Failure{record_id = record.record_id, buffer_id = record.buffer_id}
	if !store_is_live(store) {
		failure.code = .Invalid_State
		return false, failure
	}
	if u64(len(payload)) != record.payload_bytes ||
	   checkpoint_payload_digest(payload) != record.payload_digest ||
	   len(record.source_identity) > int(MAX_SOURCE_IDENTITY_BYTES) {
		failure.code = .Invalid_Record
		return false, failure
	}
	if u64(len(payload)) > store.policy.storage.record_payload_bytes {
		failure.code = .Resource_Exhausted
		failure.limit = store.policy.storage.record_payload_bytes
		failure.actual = u64(len(payload))
		return false, failure
	}
	if valid, _ := record_validate(record, store.policy); !valid {
		failure.code = .Invalid_Record
		return false, failure
	}

	payload_path, payload_temp, path_ok := store_payload_paths(store, record, context.temp_allocator)
	if !path_ok {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(payload_path, context.temp_allocator)
	defer delete(payload_temp, context.temp_allocator)
	if store_fault(options, .Before_Payload_Open, &failure) do return false, failure
	if !store_regular_file_exists(payload_path) {
		published, publish_failure := store_atomic_file(
			payload_temp,
			payload_path,
			payload,
			store_directory_path(store, "payloads", context.temp_allocator),
			options,
			.After_Payload_Write,
			.After_Payload_Sync,
			.After_Payload_Rename,
			.After_Payload_Directory_Sync,
			failure,
		)
		if !published do return false, publish_failure
	}

	record_bytes, encoded := store_encode_record(record, context.temp_allocator)
	if !encoded {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(record_bytes, context.temp_allocator)
	record_digest := checkpoint_payload_digest(record_bytes)
	record_path, record_temp, record_path_ok := store_record_paths(store, record, context.temp_allocator)
	if !record_path_ok {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(record_path, context.temp_allocator)
	defer delete(record_temp, context.temp_allocator)
	if store_regular_file_exists(record_path) {
		existing, read_error := os.read_entire_file(record_path, context.temp_allocator)
		if read_error != nil || !slice.equal(existing, record_bytes) {
			if read_error == nil do delete(existing, context.temp_allocator)
			failure.code = .Invalid_Record
			return false, failure
		}
		delete(existing, context.temp_allocator)
	} else {
		published, publish_failure := store_atomic_file(
			record_temp,
			record_path,
			record_bytes,
			store_directory_path(store, "records", context.temp_allocator),
			options,
			.After_Record_Write,
			.After_Record_Sync,
			.After_Record_Rename,
			.After_Record_Directory_Sync,
			failure,
		)
		if !published do return false, publish_failure
	}

	current_bytes := store_encode_current(record, record_digest)
	current_path, current_temp, current_path_ok := store_current_paths(store, record, context.temp_allocator)
	if !current_path_ok {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(current_path, context.temp_allocator)
	defer delete(current_temp, context.temp_allocator)
	published, publish_failure := store_atomic_file(
		current_temp,
		current_path,
		current_bytes[:],
		store_directory_path(store, "current", context.temp_allocator),
		options,
		.After_Current_Write,
		.After_Current_Sync,
		.After_Current_Rename,
		.After_Current_Directory_Sync,
		failure,
	)
	if !published do return false, publish_failure
	if _, cleaned, cleanup_failure := store_cleanup(store, record.created_at_seconds); !cleaned {
		return false, cleanup_failure
	}
	return true, {}
}

/* store_load_current reads one current reference only after all digests validate. */
store_load_current :: proc(
	store: ^Store,
	buffer_id: Buffer_ID,
	allocator: runtime.Allocator,
) -> (Loaded_Checkpoint, bool, Persistence_Failure) {
	failure := Persistence_Failure{buffer_id = buffer_id}
	if !store_is_live(store) || buffer_id == Buffer_ID(0) || allocator.procedure == nil {
		failure.code = .Invalid_State
		return {}, false, failure
	}
	current_path, path_ok := store_current_path(store, buffer_id, context.temp_allocator)
	if !path_ok {
		failure.code = .Allocation
		return {}, false, failure
	}
	defer delete(current_path, context.temp_allocator)
	current_bytes, read_code := store_read_private_file(store, current_path, context.temp_allocator)
	if read_code != .None {
		failure.code = read_code
		return {}, false, failure
	}
	defer delete(current_bytes, context.temp_allocator)
	current_record, record_digest, decoded := store_decode_current(current_bytes, buffer_id)
	if !decoded {
		failure.code = .Malformed if len(current_bytes) >= RECOVERY_CURRENT_BYTES else .Truncated
		return {}, false, failure
	}
	failure.record_id = current_record
	record_path, record_path_ok := store_record_path(store, current_record, context.temp_allocator)
	if !record_path_ok {
		failure.code = .Allocation
		return {}, false, failure
	}
	defer delete(record_path, context.temp_allocator)
	record_bytes, record_read_code := store_read_private_file(store, record_path, context.temp_allocator)
	if record_read_code != .None {
		failure.code = record_read_code
		return {}, false, failure
	}
	defer delete(record_bytes, context.temp_allocator)
	if checkpoint_payload_digest(record_bytes) != record_digest {
		failure.code = .Digest_Mismatch
		return {}, false, failure
	}
	record, source, record_decoded := store_decode_record(record_bytes, allocator)
	if !record_decoded {
		failure.code = .Malformed if len(record_bytes) >= RECOVERY_RECORD_HEADER_BYTES else .Truncated
		return {}, false, failure
	}
	if record.record_id != current_record || record.buffer_id != buffer_id {
		delete(source, allocator)
		failure.code = .Malformed
		return {}, false, failure
	}
	if valid, _ := record_validate(record, store.policy); !valid {
		delete(source, allocator)
		failure.code = .Malformed
		return {}, false, failure
	}
	payload_path, payload_path_ok := store_payload_path(store, record.payload_digest, context.temp_allocator)
	if !payload_path_ok {
		delete(source, allocator)
		failure.code = .Allocation
		return {}, false, failure
	}
	defer delete(payload_path, context.temp_allocator)
	payload, payload_read_code := store_read_private_file(store, payload_path, allocator)
	if payload_read_code != .None {
		delete(source, allocator)
		failure.code = payload_read_code
		return {}, false, failure
	}
	if u64(len(payload)) != record.payload_bytes || checkpoint_payload_digest(payload) != record.payload_digest {
		delete(payload, allocator)
		delete(source, allocator)
		failure.code = .Digest_Mismatch
		return {}, false, failure
	}
	return Loaded_Checkpoint {
		record = record,
		source_storage = source,
		payload = payload,
		allocator = allocator,
	}, true, {}
}

/* store_retire_current removes only an exact confirmed saved or clean-shutdown revision. */
store_retire_current :: proc(
	store: ^Store,
	buffer_id: Buffer_ID,
	recovered_revision: u64,
) -> (bool, Persistence_Failure) {
	failure := Persistence_Failure{buffer_id = buffer_id}
	checkpoint, loaded, load_failure := store_load_current(store, buffer_id, context.temp_allocator)
	if !loaded do return false, load_failure
	defer loaded_checkpoint_close(&checkpoint)
	failure.record_id = checkpoint.record.record_id
	if checkpoint.record.recovered_revision != recovered_revision {
		failure.code = .Revision_Mismatch
		failure.limit = checkpoint.record.recovered_revision
		failure.actual = recovered_revision
		return false, failure
	}
	path, path_ok := store_current_path(store, buffer_id, context.temp_allocator)
	if !path_ok {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(path, context.temp_allocator)
	if os.remove(path) != nil {
		failure.code = .Write
		return false, failure
	}
	directory := store_directory_path(store, "current", context.temp_allocator)
	if len(directory) == 0 {
		failure.code = .Allocation
		return false, failure
	}
	defer delete(directory, context.temp_allocator)
	if !store_sync_directory(directory) {
		failure.code = .Sync
		return false, failure
	}
	return true, {}
}

/* retention_plan chooses oldest non-current records under age, count, and storage bounds. */
retention_plan :: proc(
	records: []Retention_Record,
	policy: Policy,
	now_seconds: u64,
	removed: []Record_ID,
) -> int {
	if len(records) == 0 || len(removed) == 0 do return 0
	removed_count := 0
	selected, allocation_error := make([]bool, len(records), context.temp_allocator)
	if allocation_error != nil do return 0
	defer delete(selected, context.temp_allocator)

	for record, index in records {
		if record.current do continue
		if now_seconds > record.created_at_seconds &&
		   now_seconds - record.created_at_seconds > policy.retention.maximum_age_seconds {
			_ = retention_select_record(index, records, selected, removed, &removed_count)
		}
	}
	for record, index in records {
		if selected[index] || record.current do continue
		newer := u64(0)
		for other, other_index in records {
			if selected[other_index] || other.buffer_id != record.buffer_id do continue
			if other.created_at_seconds > record.created_at_seconds ||
			   (other.created_at_seconds == record.created_at_seconds && u64(other.record_id) > u64(record.record_id)) {
				newer += 1
			}
		}
		if newer >= policy.retention.records_per_buffer {
			_ = retention_select_record(index, records, selected, removed, &removed_count)
		}
	}
	for record, index in records {
		if selected[index] || record.current do continue
		newer_bytes := u64(0)
		for other, other_index in records {
			if selected[other_index] || other.buffer_id != record.buffer_id do continue
			if other.created_at_seconds > record.created_at_seconds ||
			   (other.created_at_seconds == record.created_at_seconds && u64(other.record_id) >= u64(record.record_id)) {
				newer_bytes += other.payload_bytes + other.metadata_bytes
			}
		}
		if newer_bytes > policy.storage.buffer_storage_bytes {
			_ = retention_select_record(index, records, selected, removed, &removed_count)
		}
	}

	for {
		total_records, total_bytes := retention_totals(records, selected)
		if total_records <= policy.retention.total_records &&
		   total_bytes <= policy.storage.store_storage_bytes {
			break
		}
		oldest := -1
		for record, index in records {
			if selected[index] || record.current do continue
			if oldest < 0 || retention_record_less(record, records[oldest]) do oldest = index
		}
		if oldest < 0 || !retention_select_record(oldest, records, selected, removed, &removed_count) do break
	}
	return removed_count
}

/* store_cleanup performs at most the configured cleanup work and reports remaining usage. */
store_cleanup :: proc(
	store: ^Store,
	now_seconds: u64,
) -> (Cleanup_Result, bool, Persistence_Failure) {
	if !store_is_live(store) {
		return {}, false, Persistence_Failure{code = .Invalid_State}
	}
	inventory, inventoried, failure := store_inventory(store, context.temp_allocator)
	if !inventoried do return {}, false, failure
	defer delete(inventory, context.temp_allocator)
	removed, allocation_error := make(
		[]Record_ID,
		min(len(inventory), int(store.policy.storage.cleanup_records)),
		context.temp_allocator,
	)
	if allocation_error != nil do return {}, false, Persistence_Failure{code = .Allocation}
	defer delete(removed, context.temp_allocator)
	retention_records, records_allocation_error := make([]Retention_Record, len(inventory), context.temp_allocator)
	if records_allocation_error != nil do return {}, false, Persistence_Failure{code = .Allocation}
	defer delete(retention_records, context.temp_allocator)
	for entry, index in inventory do retention_records[index] = entry.retention
	removed_count := retention_plan(retention_records, store.policy, now_seconds, removed)
	for remove_index in 0 ..< removed_count {
		record_index := store_inventory_find(inventory, removed[remove_index])
		if record_index < 0 do continue
		record_path, path_ok := store_record_path(store, removed[remove_index], context.temp_allocator)
		if !path_ok do return {}, false, Persistence_Failure{code = .Allocation}
		removed_file := os.remove(record_path) == nil
		delete(record_path, context.temp_allocator)
		if !removed_file {
			return {}, false, Persistence_Failure{
				code = .Write,
				record_id = removed[remove_index],
				buffer_id = inventory[record_index].retention.buffer_id,
			}
		}
		if !store_digest_retained(inventory, removed[:removed_count], inventory[record_index].digest) {
			payload_path, payload_ok := store_payload_path(store, inventory[record_index].digest, context.temp_allocator)
			if payload_ok {
				_ = os.remove(payload_path)
				delete(payload_path, context.temp_allocator)
			}
		}
	}
	cleanup_directories := [?]string{"records", "payloads"}
	for name in cleanup_directories {
		directory := store_directory_path(store, name, context.temp_allocator)
		if len(directory) == 0 || !store_sync_directory(directory) {
			if len(directory) > 0 do delete(directory, context.temp_allocator)
			return {}, false, Persistence_Failure{code = .Sync}
		}
		delete(directory, context.temp_allocator)
	}
	usage := retention_usage_after(retention_records, removed[:removed_count])
	return Cleanup_Result{removed_records = u64(removed_count), usage = usage}, true, {}
}

@(private)
retention_totals :: proc(records: []Retention_Record, selected: []bool) -> (u64, u64) {
	record_count, storage_bytes := u64(0), u64(0)
	for record, index in records {
		if selected[index] do continue
		record_count += 1
		storage_bytes += record.payload_bytes + record.metadata_bytes
	}
	return record_count, storage_bytes
}

@(private)
retention_select_record :: proc(
	index: int,
	records: []Retention_Record,
	selected: []bool,
	removed: []Record_ID,
	removed_count: ^int,
) -> bool {
	if selected[index] || records[index].current || removed_count^ >= len(removed) do return false
	selected[index] = true
	removed[removed_count^] = records[index].record_id
	removed_count^ += 1
	return true
}

@(private)
retention_record_less :: proc(left, right: Retention_Record) -> bool {
	if left.created_at_seconds != right.created_at_seconds do return left.created_at_seconds < right.created_at_seconds
	return u64(left.record_id) < u64(right.record_id)
}

@(private)
store_inventory :: proc(
	store: ^Store,
	allocator: runtime.Allocator,
) -> ([]Stored_Record_Inventory, bool, Persistence_Failure) {
	directory := store_directory_path(store, "records", context.temp_allocator)
	if len(directory) == 0 do return nil, false, Persistence_Failure{code = .Allocation}
	defer delete(directory, context.temp_allocator)
	files, read_error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if read_error != nil do return nil, false, Persistence_Failure{code = .Read}
	defer os.file_info_slice_delete(files, context.temp_allocator)
	inventory, allocation_error := make([]Stored_Record_Inventory, len(files), allocator)
	if allocation_error != nil do return nil, false, Persistence_Failure{code = .Allocation}
	count := 0
	for file in files {
		if file.type != .Regular do continue
		bytes, read_code := store_read_private_file(store, file.fullpath, context.temp_allocator)
		if read_code != .None do continue
		record, source, decoded := store_decode_record(bytes, context.temp_allocator)
		delete(bytes, context.temp_allocator)
		if !decoded do continue
		delete(source, context.temp_allocator)
		current := store_current_matches(store, record.buffer_id, record.record_id)
		inventory[count] = Stored_Record_Inventory {
			retention = {
				record_id = record.record_id,
				buffer_id = record.buffer_id,
				created_at_seconds = record.created_at_seconds,
				payload_bytes = record.payload_bytes,
				metadata_bytes = u64(RECOVERY_RECORD_HEADER_BYTES + len(record.source_identity)),
				current = current,
			},
			digest = record.payload_digest,
		}
		count += 1
	}
	return inventory[:count], true, {}
}

@(private)
store_current_matches :: proc(store: ^Store, buffer_id: Buffer_ID, record_id: Record_ID) -> bool {
	path, path_ok := store_current_path(store, buffer_id, context.temp_allocator)
	if !path_ok do return false
	defer delete(path, context.temp_allocator)
	bytes, read_code := store_read_private_file(store, path, context.temp_allocator)
	if read_code != .None do return false
	defer delete(bytes, context.temp_allocator)
	current, _, decoded := store_decode_current(bytes, buffer_id)
	return decoded && current == record_id
}

@(private)
store_inventory_find :: proc(inventory: []Stored_Record_Inventory, record_id: Record_ID) -> int {
	for entry, index in inventory {
		if entry.retention.record_id == record_id do return index
	}
	return -1
}

@(private)
store_digest_retained :: proc(
	inventory: []Stored_Record_Inventory,
	removed: []Record_ID,
	digest: Digest,
) -> bool {
	for entry in inventory {
		if entry.digest != digest do continue
		was_removed := false
		for record_id in removed {
			if entry.retention.record_id == record_id {was_removed = true; break}
		}
		if !was_removed do return true
	}
	return false
}

@(private)
retention_usage_after :: proc(records: []Retention_Record, removed: []Record_ID) -> Resource_Usage {
	usage: Resource_Usage
	for record in records {
		is_removed := false
		for record_id in removed {
			if record.record_id == record_id {is_removed = true; break}
		}
		if is_removed do continue
		usage.records += 1
		usage.payload_bytes += record.payload_bytes
		usage.metadata_bytes += record.metadata_bytes
		seen_buffer := false
		for prior in records {
			if prior.record_id == record.record_id do break
			prior_removed := false
			for record_id in removed {
				if prior.record_id == record_id {prior_removed = true; break}
			}
			if !prior_removed && prior.buffer_id == record.buffer_id {seen_buffer = true; break}
		}
		if !seen_buffer do usage.buffers += 1
	}
	return usage
}

@(private)
store_is_live :: proc(store: ^Store) -> bool {
	return store != nil && store.live && len(store.root) > 0
}

@(private)
store_prepare_directories :: proc(root: string, platform: Platform) -> bool {
	mode := os.Permissions_Default_Directory
	if platform != .Windows do mode = os.perm(int(PRIVATE_DIRECTORY_MODE))
	root_error := os.make_directory_all(root, mode)
	if root_error != nil && root_error != .Exist do return false
	if !os.is_directory(root) do return false
	if platform != .Windows && os.chmod(root, mode) != nil do return false
	directory_names := [?]string{"payloads", "records", "current", "quarantine"}
	for name in directory_names {
		path, path_error := os.join_path({root, name}, context.temp_allocator)
		if path_error != nil do return false
		directory_error := os.make_directory_all(path, mode)
		created := (directory_error == nil || directory_error == .Exist) && os.is_directory(path)
		if created && platform != .Windows do created = os.chmod(path, mode) == nil
		delete(path, context.temp_allocator)
		if !created do return false
	}
	return true
}

@(private)
store_atomic_file :: proc(
	temporary_path, final_path: string,
	content: []u8,
	directory_path: string,
	options: Publication_Options,
	after_write, after_sync, after_rename, after_directory_sync: Persistence_Stage,
	failure: Persistence_Failure,
) -> (bool, Persistence_Failure) {
	result_failure := failure
	if len(directory_path) == 0 {
		result_failure.code = .Allocation
		return false, result_failure
	}
	defer delete(directory_path, context.temp_allocator)
	_ = os.remove(temporary_path)
	file, open_error := os.open(
		temporary_path,
		{.Write, .Create, .Excl},
		os.perm(int(PRIVATE_FILE_MODE)),
	)
	if open_error != nil {
		result_failure.code = .Open
		return false, result_failure
	}
	temporary_live := true
	defer if temporary_live do _ = os.remove(temporary_path)
	written := 0
	for written < len(content) {
		count, write_error := os.write(file, content[written:])
		if write_error != nil || count <= 0 {
			_ = os.close(file)
			result_failure.code = .Write
			return false, result_failure
		}
		written += count
	}
	if store_fault(options, after_write, &result_failure) {
		_ = os.close(file)
		return false, result_failure
	}
	if os.sync(file) != nil {
		_ = os.close(file)
		result_failure.code = .Sync
		return false, result_failure
	}
	if store_fault(options, after_sync, &result_failure) {
		_ = os.close(file)
		return false, result_failure
	}
	if os.close(file) != nil {
		result_failure.code = .Sync
		return false, result_failure
	}
	if os.rename(temporary_path, final_path) != nil {
		result_failure.code = .Rename
		return false, result_failure
	}
	temporary_live = false
	if store_fault(options, after_rename, &result_failure) do return false, result_failure
	if !store_sync_directory(directory_path) {
		result_failure.code = .Sync
		return false, result_failure
	}
	if store_fault(options, after_directory_sync, &result_failure) do return false, result_failure
	return true, {}
}

@(private)
store_sync_directory :: proc(path: string) -> bool {
	file, open_error := os.open(path, {.Read})
	if open_error != nil do return false
	defer os.close(file)
	return os.sync(file) == nil
}

@(private)
store_fault :: proc(
	options: Publication_Options,
	stage: Persistence_Stage,
	failure: ^Persistence_Failure,
) -> bool {
	if options.fail_at != stage do return false
	failure.code = .Injected
	failure.stage = stage
	return true
}

@(private)
store_regular_file_exists :: proc(path: string) -> bool {
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error != nil do return false
	defer os.file_info_delete(info, context.temp_allocator)
	return info.type == .Regular
}

@(private)
store_read_private_file :: proc(
	store: ^Store,
	path: string,
	allocator: runtime.Allocator,
) -> ([]u8, Persistence_Failure_Code) {
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error != nil do return nil, .Read
	defer os.file_info_delete(info, context.temp_allocator)
	if info.type != .Regular do return nil, .Malformed
	if store.platform != .Windows && info.mode != os.perm(int(PRIVATE_FILE_MODE)) {
		return nil, .Permission
	}
	content, read_error := os.read_entire_file(path, allocator)
	if read_error != nil do return nil, .Read
	return content, .None
}

@(private)
store_encode_record :: proc(record: Record, allocator: runtime.Allocator) -> ([]u8, bool) {
	bytes, allocation_error := make(
		[]u8,
		RECOVERY_RECORD_HEADER_BYTES + len(record.source_identity),
		allocator,
	)
	if allocation_error != nil do return nil, false
	copy(bytes[:8], RECOVERY_RECORD_MAGIC)
	fields := [?]u64 {
		u64(record.format_version),
		u64(record.record_id),
		u64(record.buffer_id),
		record.saved_revision,
		record.recovered_revision,
		record.created_at_seconds,
		u64(record.policy_generation),
		record.payload_bytes,
		u64(record.encoding),
		u64(record.line_ending),
		1 if record.source_present else 0,
		u64(len(record.source_identity)),
	}
	for value, index in fields {
		if !endian.put_u64(bytes[8 + index * 8:], .Little, value) {
			delete(bytes, allocator)
			return nil, false
		}
	}
	source_fingerprint := record.source_fingerprint
	payload_digest := record.payload_digest
	copy(bytes[104:136], source_fingerprint[:])
	copy(bytes[136:168], payload_digest[:])
	copy(bytes[RECOVERY_RECORD_HEADER_BYTES:], transmute([]u8)record.source_identity)
	return bytes, true
}

@(private)
store_decode_record :: proc(bytes: []u8, allocator: runtime.Allocator) -> (Record, string, bool) {
	if len(bytes) < RECOVERY_RECORD_HEADER_BYTES || string(bytes[:8]) != RECOVERY_RECORD_MAGIC do return {}, "", false
	fields: [12]u64
	for &value, index in fields {
		decoded: bool
		value, decoded = endian.get_u64(bytes[8 + index * 8:], .Little)
		if !decoded do return {}, "", false
	}
	source_length := fields[11]
	if source_length > MAX_SOURCE_IDENTITY_BYTES || source_length > u64(len(bytes) - RECOVERY_RECORD_HEADER_BYTES) ||
	   int(source_length) != len(bytes) - RECOVERY_RECORD_HEADER_BYTES {
		return {}, "", false
	}
	source, allocation_error := strings.clone(
		string(bytes[RECOVERY_RECORD_HEADER_BYTES:]),
		allocator,
	)
	if allocation_error != nil do return {}, "", false
	record := Record {
		format_version = u32(fields[0]),
		record_id = Record_ID(fields[1]),
		buffer_id = Buffer_ID(fields[2]),
		saved_revision = fields[3],
		recovered_revision = fields[4],
		created_at_seconds = fields[5],
		policy_generation = Policy_Generation(fields[6]),
		payload_bytes = fields[7],
		encoding = Encoding(fields[8]),
		line_ending = Line_Ending(fields[9]),
		source_present = fields[10] == 1,
		source_identity = source,
	}
	copy(record.source_fingerprint[:], bytes[104:136])
	copy(record.payload_digest[:], bytes[136:168])
	return record, source, true
}

@(private)
store_encode_current :: proc(record: Record, record_digest: Digest) -> (bytes: [RECOVERY_CURRENT_BYTES]u8) {
	copy(bytes[:8], RECOVERY_CURRENT_MAGIC)
	assert(endian.put_u64(bytes[8:], .Little, u64(record.record_id)))
	assert(endian.put_u64(bytes[16:], .Little, u64(record.buffer_id)))
	digest := record_digest
	copy(bytes[24:], digest[:])
	return
}

@(private)
store_decode_current :: proc(bytes: []u8, buffer_id: Buffer_ID) -> (Record_ID, Digest, bool) {
	if len(bytes) != RECOVERY_CURRENT_BYTES || string(bytes[:8]) != RECOVERY_CURRENT_MAGIC do return {}, {}, false
	record_id, record_ok := endian.get_u64(bytes[8:], .Little)
	stored_buffer, buffer_ok := endian.get_u64(bytes[16:], .Little)
	if !record_ok || !buffer_ok || record_id == 0 || stored_buffer != u64(buffer_id) do return {}, {}, false
	digest: Digest
	copy(digest[:], bytes[24:])
	if !digest_present(digest) do return {}, {}, false
	return Record_ID(record_id), digest, true
}

@(private)
store_directory_path :: proc(store: ^Store, name: string, allocator: runtime.Allocator) -> string {
	path, path_error := os.join_path({store.root, name}, allocator)
	if path_error != nil do return ""
	return path
}

@(private)
store_payload_path :: proc(store: ^Store, digest: Digest, allocator: runtime.Allocator) -> (string, bool) {
	digest_copy := digest
	hex_digest, allocation_error := hex.encode(digest_copy[:], allocator)
	if allocation_error != nil do return "", false
	defer delete(hex_digest, allocator)
	name := fmt.aprintf("%s.bin", string(hex_digest), allocator = allocator)
	if len(name) == 0 do return "", false
	defer delete(name, allocator)
	directory := store_directory_path(store, "payloads", allocator)
	if len(directory) == 0 do return "", false
	defer delete(directory, allocator)
	path, path_error := os.join_path({directory, name}, allocator)
	return path, path_error == nil
}

@(private)
store_payload_paths :: proc(store: ^Store, record: Record, allocator: runtime.Allocator) -> (string, string, bool) {
	final, final_ok := store_payload_path(store, record.payload_digest, allocator)
	if !final_ok do return "", "", false
	directory := store_directory_path(store, "payloads", allocator)
	if len(directory) == 0 {
		delete(final, allocator)
		return "", "", false
	}
	defer delete(directory, allocator)
	name := fmt.aprintf(".tmp-%d-%d", u64(record.buffer_id), u64(record.record_id), allocator = allocator)
	defer delete(name, allocator)
	temporary, path_error := os.join_path({directory, name}, allocator)
	if path_error != nil {
		delete(final, allocator)
		return "", "", false
	}
	return final, temporary, true
}

@(private)
store_record_path :: proc(store: ^Store, record_id: Record_ID, allocator: runtime.Allocator) -> (string, bool) {
	directory := store_directory_path(store, "records", allocator)
	if len(directory) == 0 do return "", false
	defer delete(directory, allocator)
	name := fmt.aprintf("%d.rec", u64(record_id), allocator = allocator)
	defer delete(name, allocator)
	path, path_error := os.join_path({directory, name}, allocator)
	return path, path_error == nil
}

@(private)
store_record_paths :: proc(store: ^Store, record: Record, allocator: runtime.Allocator) -> (string, string, bool) {
	final, final_ok := store_record_path(store, record.record_id, allocator)
	if !final_ok do return "", "", false
	directory := store_directory_path(store, "records", allocator)
	if len(directory) == 0 {
		delete(final, allocator)
		return "", "", false
	}
	defer delete(directory, allocator)
	name := fmt.aprintf(".tmp-%d", u64(record.record_id), allocator = allocator)
	defer delete(name, allocator)
	temporary, path_error := os.join_path({directory, name}, allocator)
	if path_error != nil {
		delete(final, allocator)
		return "", "", false
	}
	return final, temporary, true
}

@(private)
store_current_path :: proc(store: ^Store, buffer_id: Buffer_ID, allocator: runtime.Allocator) -> (string, bool) {
	directory := store_directory_path(store, "current", allocator)
	if len(directory) == 0 do return "", false
	defer delete(directory, allocator)
	name := fmt.aprintf("%d.ref", u64(buffer_id), allocator = allocator)
	defer delete(name, allocator)
	path, path_error := os.join_path({directory, name}, allocator)
	return path, path_error == nil
}

@(private)
store_current_paths :: proc(store: ^Store, record: Record, allocator: runtime.Allocator) -> (string, string, bool) {
	final, final_ok := store_current_path(store, record.buffer_id, allocator)
	if !final_ok do return "", "", false
	directory := store_directory_path(store, "current", allocator)
	if len(directory) == 0 {
		delete(final, allocator)
		return "", "", false
	}
	defer delete(directory, allocator)
	name := fmt.aprintf(".tmp-%d", u64(record.buffer_id), allocator = allocator)
	defer delete(name, allocator)
	temporary, path_error := os.join_path({directory, name}, allocator)
	if path_error != nil {
		delete(final, allocator)
		return "", "", false
	}
	return final, temporary, true
}
