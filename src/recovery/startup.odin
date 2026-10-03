// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "base:runtime"
import "core:encoding/endian"
import "core:fmt"
import "core:os"
import "core:strings"

/* Candidate_Observation owns the bounded metadata exposed during startup. */
Candidate_Observation :: struct {
	candidate:        Candidate,
	source_identity:  string,
	created_at_seconds: u64,
	saved_revision:    u64,
	payload_bytes:    u64,
	encoding:         Encoding,
	line_ending:      Line_Ending,
}

/* Candidate_Action_Request binds one user action to an exact discovered candidate. */
Candidate_Action_Request :: struct {
	record_id:          Record_ID,
	buffer_id:          Buffer_ID,
	recovered_revision: u64,
	action:             Candidate_Action,
}

/* Candidate_Action_Result owns any recovered and current-source content returned by an action. */
Candidate_Action_Result :: struct {
	action:         Candidate_Action,
	candidate:      Candidate,
	checkpoint:     Loaded_Checkpoint,
	current_source: []u8,
	allocator:      runtime.Allocator,
}

/* Startup_Discovery owns one complete scan of admitted current references. */
Startup_Discovery :: struct {
	candidates:          []Candidate_Observation,
	candidate_storage:   []Candidate_Observation,
	quarantined_records: u64,
	allocator:           runtime.Allocator,
}

/* startup_discovery_close releases copied candidate metadata. */
startup_discovery_close :: proc(discovery: ^Startup_Discovery) {
	if discovery == nil do return
	for &observation in discovery.candidates {
		if len(observation.source_identity) > 0 {
			delete(observation.source_identity, discovery.allocator)
		}
	}
	if discovery.candidate_storage != nil {
		delete(discovery.candidate_storage, discovery.allocator)
	}
	discovery^ = {}
}

/* candidate_action_result_close releases copied content returned by a checked candidate action. */
candidate_action_result_close :: proc(result: ^Candidate_Action_Result) {
	if result == nil do return
	loaded_checkpoint_close(&result.checkpoint)
	if result.current_source != nil do delete(result.current_source, result.allocator)
	result^ = {}
}

/* store_discover_startup_candidates scans current references without exposing payloads. */
store_discover_startup_candidates :: proc(
	store: ^Store,
	allocator: runtime.Allocator,
) -> (Startup_Discovery, bool, Persistence_Failure) {
	if !store_is_live(store) || allocator.procedure == nil {
		return {}, false, Persistence_Failure{code = .Invalid_State}
	}
	directory := store_directory_path(store, "current", context.temp_allocator)
	if len(directory) == 0 do return {}, false, Persistence_Failure{code = .Allocation}
	defer delete(directory, context.temp_allocator)
	files, read_error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if read_error != nil do return {}, false, Persistence_Failure{code = .Read}
	defer os.file_info_slice_delete(files, context.temp_allocator)

	candidates, allocation_error := make([]Candidate_Observation, len(files), allocator)
	if allocation_error != nil do return {}, false, Persistence_Failure{code = .Allocation}
	discovery := Startup_Discovery {
		candidates = candidates,
		candidate_storage = candidates,
		allocator = allocator,
	}
	candidate_count := 0
	for file in files {
		current_bytes, read_code := store_read_private_file(store, file.fullpath, context.temp_allocator)
		if read_code != .None {
			if startup_quarantine_current(store, file.fullpath, file.name) {
				discovery.quarantined_records += 1
			}
			continue
		}
		record_id, buffer_id, _, decoded := startup_decode_current(current_bytes)
		delete(current_bytes, context.temp_allocator)
		if !decoded {
			if startup_quarantine_current(store, file.fullpath, file.name) {
				discovery.quarantined_records += 1
			}
			continue
		}
		checkpoint, loaded, load_failure := store_load_current(store, buffer_id, context.temp_allocator)
		if !loaded || checkpoint.record.record_id != record_id {
			if loaded do loaded_checkpoint_close(&checkpoint)
			_ = load_failure
			if startup_quarantine_current(store, file.fullpath, file.name) {
				discovery.quarantined_records += 1
			}
			continue
		}
		candidate := startup_candidate_for_checkpoint(store, &checkpoint)
		if valid, _ := candidate_validate(candidate); !valid {
			loaded_checkpoint_close(&checkpoint)
			if startup_quarantine_current(store, file.fullpath, file.name) {
				discovery.quarantined_records += 1
			}
			continue
		}
		source, clone_error := strings.clone(checkpoint.record.source_identity, allocator)
		if clone_error != nil {
			loaded_checkpoint_close(&checkpoint)
			startup_discovery_close(&discovery)
			return {}, false, Persistence_Failure{code = .Allocation}
		}
		discovery.candidates[candidate_count] = Candidate_Observation {
				candidate = candidate,
				source_identity = source,
				created_at_seconds = checkpoint.record.created_at_seconds,
				saved_revision = checkpoint.record.saved_revision,
				payload_bytes = checkpoint.record.payload_bytes,
				encoding = checkpoint.record.encoding,
				line_ending = checkpoint.record.line_ending,
			}
		candidate_count += 1
		loaded_checkpoint_close(&checkpoint)
	}
	discovery.candidates = discovery.candidates[:candidate_count]
	startup_sort_candidates(discovery.candidates)
	return discovery, true, {}
}

/* store_apply_candidate_action revalidates an exact candidate before acting. */
store_apply_candidate_action :: proc(
	store: ^Store,
	request: Candidate_Action_Request,
	allocator: runtime.Allocator,
) -> (Candidate_Action_Result, bool, Persistence_Failure) {
	failure := Persistence_Failure{record_id = request.record_id, buffer_id = request.buffer_id}
	if !store_is_live(store) || allocator.procedure == nil || request.record_id == Record_ID(0) ||
	   request.buffer_id == Buffer_ID(0) || request.recovered_revision == 0 ||
	   request.action == .Invalid {
		failure.code = .Invalid_State
		return {}, false, failure
	}
	checkpoint, loaded, load_failure := store_load_current(store, request.buffer_id, allocator)
	if !loaded do return {}, false, load_failure
	if checkpoint.record.record_id != request.record_id ||
	   checkpoint.record.recovered_revision != request.recovered_revision {
		loaded_checkpoint_close(&checkpoint)
		failure.code = .Candidate_Stale
		return {}, false, failure
	}
	candidate := startup_candidate_for_checkpoint(store, &checkpoint)
	available := false
	for index in 0 ..< int(candidate.action_count) {
		if candidate.actions[index] == request.action {
			available = true
			break
		}
	}
	if !available {
		loaded_checkpoint_close(&checkpoint)
		failure.code = .Action_Unavailable
		return {}, false, failure
	}
	if request.action == .Discard {
		loaded_checkpoint_close(&checkpoint)
		discarded, discard_failure := store_retire_current(
			store,
			request.buffer_id,
			request.recovered_revision,
		)
		if !discarded do return {}, false, discard_failure
		return Candidate_Action_Result{action = request.action, candidate = candidate}, true, {}
	}
	result := Candidate_Action_Result {
		action = request.action,
		candidate = candidate,
		checkpoint = checkpoint,
		allocator = allocator,
	}
	if request.action == .Compare {
		current, read_error := os.read_entire_file(checkpoint.record.source_identity, allocator)
		if read_error != nil {
			candidate_action_result_close(&result)
			failure.code = .Read
			return {}, false, failure
		}
		if u64(len(current)) > store.policy.storage.store_storage_bytes {
			actual := u64(len(current))
			delete(current, allocator)
			candidate_action_result_close(&result)
			failure.code = .Resource_Exhausted
			failure.limit = store.policy.storage.store_storage_bytes
			failure.actual = actual
			return {}, false, failure
		}
		result.current_source = current
	}
	return result, true, {}
}

@(private)
startup_candidate_for_checkpoint :: proc(store: ^Store, checkpoint: ^Loaded_Checkpoint) -> Candidate {
	record := checkpoint.record
	candidate := Candidate {
		record_id = record.record_id,
		buffer_id = record.buffer_id,
		recovered_revision = record.recovered_revision,
	}
	if !record.source_present {
		candidate.state = .Pathless
		candidate.actions = {.Restore, .Inspect, .Discard, .Invalid}
		candidate.action_count = 3
		return candidate
	}
	info, stat_error := os.stat(record.source_identity, context.temp_allocator)
	if stat_error != nil {
		candidate.state = .Missing_Source if stat_error == os.Error(.Not_Exist) else .Inaccessible
		candidate.actions = {.Restore, .Inspect, .Discard, .Invalid}
		candidate.action_count = 3
		return candidate
	}
	defer os.file_info_delete(info, context.temp_allocator)
	if info.type != .Regular || info.size < 0 ||
	   u64(info.size) > store.policy.storage.store_storage_bytes {
		candidate.state = .Inaccessible
		candidate.actions = {.Restore, .Inspect, .Discard, .Invalid}
		candidate.action_count = 3
		return candidate
	}
	contents, read_error := os.read_entire_file(record.source_identity, context.temp_allocator)
	if read_error != nil {
		candidate.state = .Inaccessible
		candidate.actions = {.Restore, .Inspect, .Discard, .Invalid}
		candidate.action_count = 3
		return candidate
	}
	defer delete(contents, context.temp_allocator)
	if checkpoint_payload_digest(contents) != record.source_fingerprint {
		candidate.state = .Conflict
		candidate.conflict = .Source_Changed
		candidate.actions = {.Restore, .Inspect, .Compare, .Discard}
		candidate.action_count = 4
		return candidate
	}
	candidate.state = .Restorable
	candidate.actions = {.Restore, .Inspect, .Compare, .Discard}
	candidate.action_count = 4
	return candidate
}

@(private)
startup_decode_current :: proc(bytes: []u8) -> (Record_ID, Buffer_ID, Digest, bool) {
	if len(bytes) != RECOVERY_CURRENT_BYTES || string(bytes[:8]) != RECOVERY_CURRENT_MAGIC {
		return {}, {}, {}, false
	}
	record_id, record_ok := endian.get_u64(bytes[8:], .Little)
	buffer_id, buffer_ok := endian.get_u64(bytes[16:], .Little)
	if !record_ok || !buffer_ok || record_id == 0 || buffer_id == 0 do return {}, {}, {}, false
	digest: Digest
	copy(digest[:], bytes[24:])
	if !digest_present(digest) do return {}, {}, {}, false
	return Record_ID(record_id), Buffer_ID(buffer_id), digest, true
}

@(private)
startup_quarantine_current :: proc(store: ^Store, source, source_name: string) -> bool {
	quarantine := store_directory_path(store, "quarantine", context.temp_allocator)
	if len(quarantine) == 0 do return false
	defer delete(quarantine, context.temp_allocator)
	current := store_directory_path(store, "current", context.temp_allocator)
	if len(current) == 0 do return false
	defer delete(current, context.temp_allocator)
	for attempt in 0 ..< 1_024 {
		name := fmt.aprintf("current-%s-%d.bad", source_name, attempt, allocator = context.temp_allocator)
		if len(name) == 0 do return false
		destination, path_error := os.join_path({quarantine, name}, context.temp_allocator)
		delete(name, context.temp_allocator)
		if path_error != nil do return false
		info, stat_error := os.lstat(destination, context.temp_allocator)
		if stat_error == nil {
			os.file_info_delete(info, context.temp_allocator)
			delete(destination, context.temp_allocator)
			continue
		}
		if stat_error != os.Error(.Not_Exist) {
			delete(destination, context.temp_allocator)
			return false
		}
		renamed := os.rename(source, destination) == nil
		delete(destination, context.temp_allocator)
		if !renamed do return false
		_ = store_sync_directory(current)
		_ = store_sync_directory(quarantine)
		return true
	}
	return false
}

@(private)
startup_sort_candidates :: proc(candidates: []Candidate_Observation) {
	for index in 1 ..< len(candidates) {
		value := candidates[index]
		cursor := index
		for cursor > 0 && u64(candidates[cursor - 1].candidate.buffer_id) > u64(value.candidate.buffer_id) {
			candidates[cursor] = candidates[cursor - 1]
			cursor -= 1
		}
		candidates[cursor] = value
	}
}
