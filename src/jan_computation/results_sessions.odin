// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:unicode/utf8"

/* MAX_RESULT_POST_PROCESS_STEPS bounds one admitted result dependency graph. */
MAX_RESULT_POST_PROCESS_STEPS :: u16(1_024)
/* MAX_RESULT_STEP_DEPENDENCIES bounds direct inputs to one result processor. */
MAX_RESULT_STEP_DEPENDENCIES :: 16
/* MAX_CACHE_ENTRIES bounds inspectable execution-cache metadata. */
MAX_CACHE_ENTRIES :: u16(4_096)

/* Result_Row identifies one copied row inside a decoded result payload. */
Result_Row :: struct {
	start: u64,
	end:   u64,
}

/* Result_Candidate is borrowed adapter output before decoding and publication. */
Result_Candidate :: struct {
	descriptor: Typed_Result_Descriptor,
	scope:      Scope,
	owner:      Semantic_Target,
	payload:    string,
}

/* Decoded_Result describes copied, bounded adapter output. */
Decoded_Result :: struct {
	descriptor:   Typed_Result_Descriptor,
	scope:        Scope,
	owner:        Semantic_Target,
	content_hash: u64,
	row_count:    u32,
	byte_count:   u64,
	complete:     bool,
}

/* Post_Process_Step is one copied-identity result transformation node. */
Post_Process_Step :: struct {
	identity:         u16,
	dependencies:     [MAX_RESULT_STEP_DEPENDENCIES]u16,
	dependency_count: u8,
}

/* Result_Owner identifies the only source region an execution may replace. */
Result_Owner :: struct {
	target:          Semantic_Target,
	result_start:    u64,
	result_end:      u64,
	has_result:      bool,
	prior_result:    string,
}

/* Result_Publication is one complete exact-revision rewrite candidate. */
Result_Publication :: struct {
	operation_id:      Operation_ID,
	scope:             Scope,
	owner_node_id:     u64,
	replace_start:     u64,
	replace_end:       u64,
	replacement_bytes: u64,
	handling:          Result_Handling,
	mutates_source:    bool,
	complete:          bool,
}

/* Session_Scope_Kind identifies explicit adapter-session ownership. */
Session_Scope_Kind :: enum u8 {
	Invalid,
	Document,
	Project,
	Workspace,
}

/* Execution_Session is copied operational state and never canonical source. */
Execution_Session :: struct {
	record:              Session_Record,
	language:            Argument_Key,
	adapter_identity:    Argument_Key,
	scope_kind:          Session_Scope_Kind,
	scope_identity:      u64,
	limits:              Limits,
	reconnect_required:  bool,
	cleanup_confirmed:   bool,
}

/* Session_Event identifies explicit lifecycle and owner observations. */
Session_Event :: enum u8 {
	Invalid,
	Start,
	Activity,
	Close,
	Closed,
	Fail,
	Quarantine,
	Provider_Invalidated,
	Restart,
	Reconnect,
	Cleanup_Confirmed,
}

/* Cache_Inspection_Reason explains one exact cache outcome. */
Cache_Inspection_Reason :: enum u8 {
	Invalid,
	Exact_Hit,
	No_Entry,
	Key_Mismatch,
	Stale_Generation,
	Incomplete_Result,
	Resource_Limit,
	Explicit_Eviction,
}

/* Cache_Inspection is one source-independent cache decision. */
Cache_Inspection :: struct {
	record: Cache_Record,
	reason: Cache_Inspection_Reason,
}

/* Execution_Cache_Entry owns metadata for bytes held by Cache_Store.storage. */
Execution_Cache_Entry :: struct {
	record:       Cache_Record,
	descriptor:   Typed_Result_Descriptor,
	offset:       u64,
	created_ns:   i64,
	last_used_ns: i64,
	occupied:     bool,
}

/* Cache_Store is caller-owned bounded operational storage. */
Cache_Store :: struct {
	entries:     []Execution_Cache_Entry,
	storage:     []u8,
	entry_count: u16,
	used_bytes:  u64,
	limit_bytes: u64,
	next_id:     Cache_Entry_ID,
}

/* decode_typed_result copies and validates one complete successful adapter result. */
decode_typed_result :: proc(
	candidate: Result_Candidate,
	confirmed_scope: Scope,
	output: []u8,
	rows: []Result_Row,
	limits := DEFAULT_LIMITS,
) -> (Decoded_Result, string, []Result_Row, bool, Failure) {
	descriptor := candidate.descriptor
	if !typed_result_descriptor_is_valid(descriptor, limits) || !scope_is_valid(candidate.scope) ||
	   candidate.scope != confirmed_scope || !semantic_target_is_valid(candidate.owner, candidate.scope) {
		return {}, "", nil, false, result_failure(descriptor.operation_id, .Stale, .Scope)
	}
	if !descriptor.complete || descriptor.exit_status != 0 {
		return {}, "", nil, false, result_failure(descriptor.operation_id, .Result_Decoding, .Result)
	}
	if descriptor.byte_count != u64(len(candidate.payload)) || len(output) < len(candidate.payload) {
		return {}, "", nil, false, result_failure(descriptor.operation_id, .Limited, .Limit)
	}
	if result_type_requires_utf8(descriptor.type) && !utf8.valid_string(candidate.payload) {
		return {}, "", nil, false, result_failure(descriptor.operation_id, .Malformed, .Result)
	}
	row_count := result_payload_row_count(candidate.payload, descriptor)
	if row_count != descriptor.row_count || row_count > limits.result_rows || len(rows) < int(row_count) {
		return {}, "", nil, false, result_failure(descriptor.operation_id, .Result_Decoding, .Result)
	}
	copy(output, candidate.payload)
	result_rows := rows[:row_count]
	result_rows_assign(result_rows, candidate.payload)
	decoded := Decoded_Result {
		descriptor = descriptor,
		scope = candidate.scope,
		owner = candidate.owner,
		content_hash = result_content_hash(candidate.payload),
		row_count = row_count,
		byte_count = descriptor.byte_count,
		complete = true,
	}
	return decoded, string(output[:len(candidate.payload)]), result_rows, true, {}
}

/* order_result_post_processing returns a complete stable topological order. */
order_result_post_processing :: proc(
	steps: []Post_Process_Step,
	ordered: []u16,
	limits := DEFAULT_LIMITS,
) -> (u16, bool, Failure) {
	if len(steps) == 0 || len(steps) > int(MAX_RESULT_POST_PROCESS_STEPS) ||
	   len(steps) > int(limits.graph_depth) || len(ordered) < len(steps) {
		return 0, false, result_failure(0, .Limited, .Limit)
	}
	for step, index in steps {
		if step.identity == 0 || int(step.dependency_count) > len(step.dependencies) {
			return 0, false, result_failure(0, .Malformed, .Result)
		}
		for prior in steps[:index] do if prior.identity == step.identity {
			return 0, false, result_failure(0, .Conflict, .Result)
		}
	}
	written := 0
	for written < len(steps) {
		progress := false
		for step in steps {
			if result_order_contains(ordered[:written], step.identity) do continue
			ready := true
			dependencies := step.dependencies
			for dependency in dependencies[:int(step.dependency_count)] {
				if !result_step_exists(steps, dependency) || !result_order_contains(ordered[:written], dependency) {
					ready = false
					break
				}
			}
			if ready {
				ordered[written] = step.identity
				written += 1
				progress = true
			}
		}
		if !progress do return 0, false, result_failure(0, .Cycle, .Dependency)
	}
	return u16(written), true, {}
}

/* prepare_result_publication builds one exact-owner replacement without mutating source. */
prepare_result_publication :: proc(
	decoded: Decoded_Result,
	confirmed_scope: Scope,
	owner: Result_Owner,
	processed_payload: string,
	replacement: []u8,
) -> (Result_Publication, string, bool, Failure) {
	operation_id := decoded.descriptor.operation_id
	if !decoded.complete || decoded.scope != confirmed_scope || owner.target != decoded.owner ||
	   !semantic_target_is_valid(owner.target, confirmed_scope) {
		return {}, "", false, result_failure(operation_id, .Stale, .Target)
	}
	if u64(len(processed_payload)) > decoded.descriptor.byte_count &&
	   decoded.descriptor.handling != .Append && decoded.descriptor.handling != .Prepend {
		return {}, "", false, result_failure(operation_id, .Limited, .Result)
	}
	publication := Result_Publication {
		operation_id = operation_id,
		scope = confirmed_scope,
		owner_node_id = u64(owner.target.node_id),
		handling = decoded.descriptor.handling,
		complete = true,
	}
	if publication.handling == .Silent || publication.handling == .Discard {
		return publication, "", true, {}
	}
	if owner.has_result {
		if owner.result_start >= owner.result_end || owner.result_end > confirmed_scope.source_bytes ||
		   u64(len(owner.prior_result)) != owner.result_end - owner.result_start {
			return {}, "", false, result_failure(operation_id, .Conflict, .Result)
		}
		publication.replace_start = owner.result_start
		publication.replace_end = owner.result_end
	} else {
		publication.replace_start = u64(owner.target.range.end)
		publication.replace_end = u64(owner.target.range.end)
	}
	required := len(processed_payload)
	if publication.handling == .Append || publication.handling == .Prepend do required += len(owner.prior_result)
	if required > len(replacement) do return {}, "", false, result_failure(operation_id, .Limited, .Limit)
	cursor := 0
	switch publication.handling {
	case .Replace:
		cursor += copy(replacement[cursor:], processed_payload)
	case .Append:
		cursor += copy(replacement[cursor:], owner.prior_result)
		cursor += copy(replacement[cursor:], processed_payload)
	case .Prepend:
		cursor += copy(replacement[cursor:], processed_payload)
		cursor += copy(replacement[cursor:], owner.prior_result)
	case .Invalid, .Silent, .Discard:
		return {}, "", false, result_failure(operation_id, .Invalid_Request, .Result)
	}
	publication.replacement_bytes = u64(cursor)
	publication.mutates_source = true
	return publication, string(replacement[:cursor]), true, {}
}

/* apply_result_publication materializes one atomic whole-source candidate. */
apply_result_publication :: proc(
	source: string,
	confirmed_scope: Scope,
	publication: Result_Publication,
	replacement: string,
	output: []u8,
) -> (string, bool, Failure) {
	if !publication.complete || !publication.mutates_source || publication.scope != confirmed_scope ||
	   confirmed_scope.source_bytes != u64(len(source)) || publication.replace_start > publication.replace_end ||
	   publication.replace_end > u64(len(source)) || publication.replacement_bytes != u64(len(replacement)) {
		return "", false, result_failure(publication.operation_id, .Stale, .Result)
	}
	required := len(source) - int(publication.replace_end - publication.replace_start) + len(replacement)
	if required > len(output) do return "", false, result_failure(publication.operation_id, .Allocation_Failed, .Limit)
	cursor := copy(output, source[:publication.replace_start])
	cursor += copy(output[cursor:], replacement)
	cursor += copy(output[cursor:], source[publication.replace_end:])
	return string(output[:cursor]), true, {}
}

/* create_execution_session copies one explicitly named adapter context. */
create_execution_session :: proc(
	record: Session_Record,
	language_name, adapter_identity: string,
	scope_kind: Session_Scope_Kind,
	scope_identity: u64,
	limits := DEFAULT_LIMITS,
) -> (Execution_Session, bool, Failure) {
	language_key, language_ok := argument_key_copy(language_name)
	adapter_key, adapter_ok := argument_key_copy(adapter_identity)
	if !session_record_is_valid(record) || !language_ok || !adapter_ok || scope_kind == .Invalid ||
	   scope_identity == 0 || !limits_are_valid(limits) {
		return {}, false, result_failure(0, .Invalid_Request, .Session)
	}
	return {record = record, language = language_key, adapter_identity = adapter_key,
	        scope_kind = scope_kind, scope_identity = scope_identity, limits = limits}, true, {}
}

/* select_execution_session requires an explicit exact session identity. */
select_execution_session :: proc(
	sessions: []Execution_Session,
	requested: Session_ID,
	language_name, adapter_identity: string,
	adapter_generation: Adapter_Generation,
	scope_kind: Session_Scope_Kind,
	scope_identity: u64,
	source_revision: u64,
) -> (^Execution_Session, bool, Failure) {
	if requested == Session_ID(0) do return nil, false, result_failure(0, .Invalid_Request, .Session)
	for &session in sessions {
		if session.record.session_id != requested do continue
		if session.record.state != .Active || session.reconnect_required ||
		   argument_key_text(&session.language) != language_name ||
		   argument_key_text(&session.adapter_identity) != adapter_identity ||
		   session.record.adapter_generation != adapter_generation || session.scope_kind != scope_kind ||
		   session.scope_identity != scope_identity || session.record.source_revision != source_revision {
			return nil, false, result_failure(0, .Stale, .Session)
		}
		return &session, true, {}
	}
	return nil, false, result_failure(0, .Unavailable, .Session)
}

/* transition_execution_session applies explicit lifecycle and restart recovery. */
transition_execution_session :: proc(
	session: ^Execution_Session,
	event: Session_Event,
	now_ns: i64,
	process_identity: u64 = 0,
) -> (bool, Failure) {
	if session == nil || event == .Invalid || now_ns < session.record.last_activity_ns {
		return false, result_failure(0, .Invalid_Request, .Session)
	}
	switch event {
	case .Invalid:
		return false, result_failure(0, .Invalid_Request, .Session)
	case .Start:
		if session.record.state != .Prepared || process_identity == 0 do return false, result_failure(0, .Conflict, .Session)
		session.record.state = .Active
		session.record.process_identity = process_identity
	case .Activity:
		if session.record.state != .Active do return false, result_failure(0, .Conflict, .Session)
	case .Close:
		if session.record.state != .Prepared && session.record.state != .Active && session.record.state != .Failed &&
		   session.record.state != .Quarantined && session.record.state != .Recovery_Required {
			return false, result_failure(0, .Conflict, .Session)
		}
		session.record.state = .Closing
	case .Closed, .Cleanup_Confirmed:
		if session.record.state != .Prepared && session.record.state != .Closing && session.record.state != .Failed &&
		   session.record.state != .Quarantined && session.record.state != .Recovery_Required {
			return false, result_failure(0, .Conflict, .Session)
		}
		session.record.state = .Closed
		session.record.process_identity = 0
		session.cleanup_confirmed = true
		session.reconnect_required = false
	case .Fail:
		if session.record.state != .Active && session.record.state != .Closing do return false, result_failure(0, .Conflict, .Session)
		session.record.state = .Failed
	case .Quarantine:
		if session.record.state != .Active && session.record.state != .Closing && session.record.state != .Failed do return false, result_failure(0, .Conflict, .Session)
		session.record.state = .Quarantined
	case .Provider_Invalidated:
		if session.record.state == .Closed || session.record.state == .Invalid do return false, result_failure(0, .Conflict, .Session)
		session.record.state = .Recovery_Required
		session.reconnect_required = true
	case .Restart:
		if session.record.state == .Closed do return false, result_failure(0, .Conflict, .Session)
		session.record.state = .Recovery_Required
		session.record.process_identity = 0
		session.reconnect_required = true
	case .Reconnect:
		if session.record.state != .Recovery_Required || process_identity == 0 do return false, result_failure(0, .Unauthorized, .Session)
		session.record.state = .Active
		session.record.process_identity = process_identity
		session.reconnect_required = false
	}
	session.record.last_activity_ns = now_ns
	return true, {}
}

/* initialize_cache_store binds caller-owned entries and bytes to a fixed ceiling. */
initialize_cache_store :: proc(entries: []Execution_Cache_Entry, storage: []u8, limit_bytes: u64) -> (Cache_Store, bool) {
	if len(entries) == 0 || len(entries) > int(MAX_CACHE_ENTRIES) || len(storage) == 0 ||
	   limit_bytes == 0 || limit_bytes > MAX_CACHE_BYTES || limit_bytes > u64(len(storage)) {
		return {}, false
	}
	return {entries = entries, storage = storage, limit_bytes = limit_bytes, next_id = 1}, true
}

/* inspect_cache reports exact hits and attributable non-hit outcomes. */
inspect_cache :: proc(store: ^Cache_Store, key: Cache_Key, now_ns: i64) -> (Cache_Inspection, string, bool) {
	if store == nil || !cache_key_is_valid(key) do return {{state = .Rejected}, .Resource_Limit}, "", false
	for &entry in store.entries {
		if !entry.occupied do continue
		if cache_key_equal(entry.record.key, key) {
			if !entry.descriptor.complete {
				return {record = entry.record, reason = .Incomplete_Result}, "", false
			}
			entry.last_used_ns = now_ns
			record := entry.record
			record.state = .Hit
			return {record = record, reason = .Exact_Hit}, string(store.storage[entry.offset:entry.offset + entry.record.byte_count]), true
		}
		if entry.record.key.source_digest == key.source_digest {
			record := entry.record
			record.state = .Invalidated
			reason := Cache_Inspection_Reason.Key_Mismatch
			if entry.record.key.adapter_generation != key.adapter_generation ||
			   entry.record.key.policy_generation != key.policy_generation {
				reason = .Stale_Generation
			}
			return {record = record, reason = reason}, "", false
		}
	}
	return {{key = key, state = .Miss}, .No_Entry}, "", false
}

/* store_cache_result copies one complete result and evicts oldest entries as needed. */
store_cache_result :: proc(
	store: ^Cache_Store,
	key: Cache_Key,
	descriptor: Typed_Result_Descriptor,
	payload: string,
	now_ns: i64,
) -> (Cache_Record, bool, Failure) {
	if store == nil || !cache_key_is_valid(key) || !typed_result_descriptor_is_valid(descriptor) ||
	   !descriptor.complete || descriptor.byte_count != u64(len(payload)) {
		return {}, false, result_failure(descriptor.operation_id, .Invalid_Request, .Cache)
	}
	if descriptor.byte_count > store.limit_bytes do return {}, false, result_failure(descriptor.operation_id, .Limited, .Cache)
	for store.entry_count >= u16(len(store.entries)) || store.used_bytes + descriptor.byte_count > store.limit_bytes {
		if !evict_oldest_cache_entry(store) do return {}, false, result_failure(descriptor.operation_id, .Limited, .Cache)
	}
	cache_compact(store)
	slot := cache_free_slot(store)
	if slot == nil || store.used_bytes + descriptor.byte_count > u64(len(store.storage)) {
		return {}, false, result_failure(descriptor.operation_id, .Allocation_Failed, .Cache)
	}
	offset := store.used_bytes
	copy(store.storage[offset:], payload)
	record := Cache_Record {entry_id = store.next_id, key = key, state = .Miss,
	                        byte_count = descriptor.byte_count, row_count = descriptor.row_count}
	slot^ = {record = record, descriptor = descriptor, offset = offset,
	         created_ns = now_ns, last_used_ns = now_ns, occupied = true}
	store.next_id += 1
	store.entry_count += 1
	store.used_bytes += descriptor.byte_count
	return record, true, {}
}

/* evict_cache_entry deletes cache-owned bytes without accepting document state. */
evict_cache_entry :: proc(store: ^Cache_Store, entry_id: Cache_Entry_ID) -> (Cache_Inspection, bool) {
	if store == nil || entry_id == Cache_Entry_ID(0) do return {}, false
	for &entry in store.entries {
		if !entry.occupied || entry.record.entry_id != entry_id do continue
		record := entry.record
		record.state = .Evicted
		entry.occupied = false
		store.entry_count -= 1
		cache_compact(store)
		return {record = record, reason = .Explicit_Eviction}, true
	}
	return {}, false
}

@(private)
result_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Result, code = code, field = field}
}

@(private)
result_type_requires_utf8 :: proc(kind: Result_Type) -> bool {
	return kind != .Resource && kind != .Graphics
}

@(private)
result_payload_row_count :: proc(payload: string, descriptor: Typed_Result_Descriptor) -> u32 {
	if descriptor.type != .List && descriptor.type != .Table do return 0
	if len(payload) == 0 do return 0
	count := u32(1)
	for value in transmute([]u8)payload do if value == '\n' do count += 1
	if payload[len(payload) - 1] == '\n' do count -= 1
	return count
}

@(private)
result_rows_assign :: proc(rows: []Result_Row, payload: string) {
	if len(rows) == 0 do return
	start, row := 0, 0
	for value, index in transmute([]u8)payload {
		if value == '\n' {
			if row < len(rows) do rows[row] = {start = u64(start), end = u64(index)}
			row += 1
			start = index + 1
		}
	}
	if row < len(rows) do rows[row] = {start = u64(start), end = u64(len(payload))}
}

@(private)
result_content_hash :: proc(payload: string) -> u64 {
	hash := u64(14_695_981_039_346_656_037)
	for value in transmute([]u8)payload {
		hash = hash ~ u64(value)
		hash *= 1_099_511_628_211
	}
	return hash
}

@(private)
result_order_contains :: proc(order: []u16, identity: u16) -> bool {
	for candidate in order do if candidate == identity do return true
	return false
}

@(private)
result_step_exists :: proc(steps: []Post_Process_Step, identity: u16) -> bool {
	for step in steps do if step.identity == identity do return true
	return false
}

@(private)
cache_key_equal :: proc(left, right: Cache_Key) -> bool {
	return left == right
}

@(private)
cache_free_slot :: proc(store: ^Cache_Store) -> ^Execution_Cache_Entry {
	for &entry in store.entries do if !entry.occupied do return &entry
	return nil
}

@(private)
evict_oldest_cache_entry :: proc(store: ^Cache_Store) -> bool {
	oldest: ^Execution_Cache_Entry
	for &entry in store.entries {
		if !entry.occupied do continue
		if oldest == nil || entry.last_used_ns < oldest.last_used_ns ||
		   (entry.last_used_ns == oldest.last_used_ns && entry.record.entry_id < oldest.record.entry_id) {
			oldest = &entry
		}
	}
	if oldest == nil do return false
	oldest.occupied = false
	store.entry_count -= 1
	cache_compact(store)
	return true
}

@(private)
cache_compact :: proc(store: ^Cache_Store) {
	if store == nil do return
	cursor := u64(0)
	for &entry in store.entries {
		if !entry.occupied do continue
		if entry.offset != cursor {
			copy(store.storage[cursor:], store.storage[entry.offset:entry.offset + entry.record.byte_count])
			entry.offset = cursor
		}
		cursor += entry.record.byte_count
	}
	store.used_bytes = cursor
}
