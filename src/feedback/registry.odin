// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback

import "base:runtime"

@(private)
Registry_State :: struct {
	id:              Registry_ID,
	generation:      Registry_Generation,
	sequence:        u64,
	policy:          Policy,
	active:          []Record,
	active_count:    int,
	history:         []Record,
	history_count:   int,
	usage:           Resource_Usage,
	last_rejection:  Failure,
	persistent:      runtime.Allocator,
	temporary:       runtime.Allocator,
}

/* registry_init creates one empty bounded registry with caller-owned allocators. */
registry_init :: proc(
	registry: ^Registry,
	id: Registry_ID,
	allocators: Allocator_Set,
	policy := DEFAULT_POLICY,
) -> (bool, Failure) {
	if registry == nil || registry.state != nil || registry.closed {
		return false, Failure{operation = .Initialize, code = .Invalid_Registry}
	}
	if id == Registry_ID(0) {
		return false, Failure{operation = .Initialize, code = .Invalid_Identity}
	}
	if ok, failure := policy_validate(policy); !ok do return false, failure
	if allocators.persistent.procedure == nil || allocators.temporary.procedure == nil {
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	state, state_error := new(Registry_State, allocators.persistent)
	if state_error != nil {
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	active, active_error := make([]Record, int(policy.active_records), allocators.persistent)
	if active_error != nil {
		free(state, allocators.persistent)
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	history, history_error := make([]Record, int(policy.history_records), allocators.persistent)
	if history_error != nil {
		delete(active, allocators.persistent)
		free(state, allocators.persistent)
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	state^ = {
		id = id,
		generation = 1,
		policy = policy,
		active = active,
		history = history,
		persistent = allocators.persistent,
		temporary = allocators.temporary,
	}
	registry.state = state
	return true, {}
}

/* registry_publish validates and atomically admits one complete generation. */
registry_publish :: proc(
	registry: ^Registry,
	proposal: Proposal,
) -> (published: Record, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Publish, code = .Invalid_Registry}
	operation := Operation.Publish
	active_index := registry_find_active(state, proposal.id)
	coalesced_index := -1
	if active_index < 0 && proposal.kind == .Notification && len(proposal.coalescing_key) > 0 {
		coalesced_index = registry_find_coalescing(state, proposal)
	}
	if active_index >= 0 || coalesced_index >= 0 do operation = .Replace
	if coalesced_index >= 0 do operation = .Coalesce
	if valid, validation_failure := proposal_validate(state, proposal, active_index, coalesced_index); !valid {
		return {}, false, registry_reject(state, validation_failure)
	}
	candidate, copied, copy_failure := record_copy_from_proposal(
		proposal, state.sequence + 1, state.persistent,
	)
	if !copied do return {}, false, registry_reject(state, copy_failure)
	replace_index := active_index
	if coalesced_index >= 0 {
		replace_index = coalesced_index
		prior := &state.active[replace_index]
		candidate.id = prior.id
		candidate.created_sequence = prior.created_sequence
		candidate.repetition_count = min(prior.repetition_count + 1, MAX_REPETITIONS)
		candidate.severity = max(prior.severity, candidate.severity)
	}
	retain := record_should_retain(candidate)
	history_candidate: Record
	if retain {
		history_candidate, copied, copy_failure = record_clone(candidate, state.persistent, true)
		if !copied {
			record_release(&candidate, state.persistent)
			return {}, false, registry_reject(state, copy_failure)
		}
	}
	remains_active := record_remains_active(candidate)
	if replace_index < 0 && remains_active && state.active_count >= len(state.active) {
		record_release(&candidate, state.persistent)
		if retain do record_release(&history_candidate, state.persistent)
		return {}, false, registry_reject(state, Failure {
			operation = operation,
			code = .Active_Limit,
			record_id = proposal.id,
			limit = state.policy.active_records,
			actual = u64(state.active_count) + 1,
		})
	}
	if retain {
		registry_prepare_history_space(state, record_owned_bytes(history_candidate), candidate.attention)
		if state.history_count >= len(state.history) ||
		   state.usage.history_bytes + record_owned_bytes(history_candidate) > state.policy.history_bytes {
			state.usage.dropped_history += 1
			record_release(&history_candidate, state.persistent)
			retain = false
		}
	}
	state.sequence += 1
	state.generation += 1
	state.usage.accepted_updates += 1
	if replace_index >= 0 {
		if remains_active {
			prior := &state.active[replace_index]
			state.usage.active_bytes -= record_owned_bytes(prior^)
			record_release(prior, state.persistent)
			state.active[replace_index] = candidate
			state.usage.active_bytes += record_owned_bytes(candidate)
		} else {
			registry_remove_active_at(state, replace_index)
			record_release(&candidate, state.persistent)
		}
	} else if remains_active {
		state.active[state.active_count] = candidate
		state.active_count += 1
		state.usage.active_records = u64(state.active_count)
		state.usage.active_bytes += record_owned_bytes(candidate)
	} else {
		record_release(&candidate, state.persistent)
	}
	if retain {
		state.history[state.history_count] = history_candidate
		state.history_count += 1
		state.usage.history_records = u64(state.history_count)
		state.usage.history_bytes += record_owned_bytes(history_candidate)
	}
	state.last_rejection = {}
	if remains_active do return state.active[registry_find_active(state, candidate.id)], true, {}
	if retain do return state.history[state.history_count - 1], true, {}
	return candidate, true, {}
}

/* registry_dismiss removes one exact active generation without clearing history. */
registry_dismiss :: proc(
	registry: ^Registry,
	id: Record_ID,
	generation: Record_Generation,
) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil do return false, Failure{operation = .Dismiss, code = .Invalid_Registry}
	index := registry_find_active(state, id)
	if index < 0 {
		return false, registry_reject(state, Failure{operation = .Dismiss, code = .Record_Not_Found, record_id = id})
	}
	if state.active[index].generation != generation {
		return false, registry_reject(state, Failure{operation = .Dismiss, code = .Stale_Generation, record_id = id, generation = generation})
	}
	registry_remove_active_at(state, index)
	state.generation += 1
	state.sequence += 1
	return true, {}
}

/* registry_expire retires transient records through one logical sequence. */
registry_expire :: proc(registry: ^Registry, through_sequence: u64) -> (expired: u64, failure: Failure) {
	state := registry_state(registry)
	if state == nil do return 0, Failure{operation = .Expire, code = .Invalid_Registry}
	index := 0
	for index < state.active_count {
		record := &state.active[index]
		if record.lifecycle == .Transient && record.updated_sequence <= through_sequence {
			registry_remove_active_at(state, index)
			expired += 1
			continue
		}
		index += 1
	}
	if expired > 0 {
		state.generation += 1
		state.sequence += 1
	}
	return expired, {}
}

/* registry_retire_source removes source-bound records for one exact owner. */
registry_retire_source :: proc(
	registry: ^Registry,
	source: Source_Reference,
) -> (retired: u64, failure: Failure) {
	state := registry_state(registry)
	if state == nil do return 0, Failure{operation = .Retire_Source, code = .Invalid_Registry}
	index := 0
	for index < state.active_count {
		record := &state.active[index]
		if record.lifecycle == .Source_Bound && record.source == source {
			registry_remove_active_at(state, index)
			retired += 1
			continue
		}
		index += 1
	}
	if retired > 0 {
		state.generation += 1
		state.sequence += 1
	}
	return retired, {}
}

/* registry_request_cancellation copies current source-owned cancel authority. */
registry_request_cancellation :: proc(
	registry: ^Registry,
	request: Cancellation_Request,
	allocator: runtime.Allocator,
) -> (Cancellation, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Cancel, code = .Invalid_Registry}
	index := registry_find_active(state, request.record_id)
	if index < 0 {
		return {}, false, registry_reject(state, Failure{operation = .Cancel, code = .Record_Not_Found, record_id = request.record_id})
	}
	record := &state.active[index]
	if record.generation != request.record_generation {
		return {}, false, registry_reject(state, Failure{operation = .Cancel, code = .Stale_Generation, record_id = request.record_id, generation = request.record_generation})
	}
	if record.source != request.source {
		return {}, false, registry_reject(state, Failure{operation = .Cancel, code = .Source_Mismatch, record_id = request.record_id, source = request.source})
	}
	for action in record.actions {
		if !action.cancel do continue
		copied, copy_failure := action_clone(action, allocator, true)
		if copy_failure.code != .None do return {}, false, registry_reject(state, copy_failure)
		return Cancellation {
			record_id = record.id,
			record_generation = record.generation,
			source = record.source,
			action = copied,
		}, true, {}
	}
	return {}, false, registry_reject(state, Failure{operation = .Cancel, code = .Cancellation_Unavailable, record_id = request.record_id})
}

/* cancellation_release frees one copied cancellation result. */
cancellation_release :: proc(cancellation: ^Cancellation, allocator: runtime.Allocator) {
	if cancellation == nil do return
	action_release(&cancellation.action, allocator)
	cancellation^ = {}
}

/* registry_resolve_action copies one action after exact record and source revalidation. */
registry_resolve_action :: proc(
	registry: ^Registry,
	request: Action_Request,
	allocator: runtime.Allocator,
) -> (Action_Authority, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Resolve_Action, code = .Invalid_Registry}
	if request.record_id == Record_ID(0) || request.record_generation == Record_Generation(0) ||
	   request.source.id == Source_ID(0) || request.source.generation == Source_Generation(0) ||
	   request.action_id == Action_ID(0) {
		return {}, false, registry_reject(state, Failure{
			operation = .Resolve_Action,
			code = .Invalid_Identity,
			record_id = request.record_id,
			generation = request.record_generation,
			source = request.source,
		})
	}
	record := registry_find_action_record(state, request)
	if record == nil {
		return {}, false, registry_reject(state, Failure{
			operation = .Resolve_Action,
			code = .Record_Not_Found,
			record_id = request.record_id,
			generation = request.record_generation,
			source = request.source,
		})
	}
	for action in record.actions {
		if action.id != request.action_id do continue
		copied, copy_failure := action_clone(action, allocator, true)
		if copy_failure.code != .None do return {}, false, registry_reject(state, copy_failure)
		return Action_Authority {
			record_id = record.id,
			record_generation = record.generation,
			source = record.source,
			action = copied,
		}, true, {}
	}
	return {}, false, registry_reject(state, Failure{
		operation = .Resolve_Action,
		code = .Action_Not_Found,
		record_id = request.record_id,
		generation = request.record_generation,
		source = request.source,
	})
}

/* action_authority_release frees one copied checked action. */
action_authority_release :: proc(authority: ^Action_Authority, allocator: runtime.Allocator) {
	if authority == nil do return
	action_release(&authority.action, allocator)
	authority^ = {}
}

/* registry_inspect copies bounded newest-first state with requested redaction. */
registry_inspect :: proc(
	registry: ^Registry,
	request: Inspection_Request,
	allocator: runtime.Allocator,
) -> (Inspection, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Inspect, code = .Invalid_Registry}
	if request.expected_generation != state.generation {
		return {}, false, registry_reject(state, Failure{operation = .Inspect, code = .Stale_Generation, limit = u64(state.generation), actual = u64(request.expected_generation)})
	}
	if request.active_limit > state.policy.inspection_records || request.history_limit > state.policy.inspection_records {
		return {}, false, registry_reject(state, Failure{operation = .Inspect, code = .Inspection_Limit, limit = state.policy.inspection_records, actual = max(request.active_limit, request.history_limit)})
	}
	active_count := min(int(request.active_limit), state.active_count)
	history_count := min(int(request.history_limit), state.history_count)
	active, active_error := make([]Record, active_count, allocator)
	if active_error != nil do return {}, false, registry_reject(state, Failure{operation = .Inspect, code = .Allocation})
	history, history_error := make([]Record, history_count, allocator)
	if history_error != nil {
		delete(active, allocator)
		return {}, false, registry_reject(state, Failure{operation = .Inspect, code = .Allocation})
	}
	for destination_index in 0 ..< active_count {
		source_index := state.active_count - 1 - destination_index
		copied, copied_ok, copy_failure := record_clone(state.active[source_index], allocator, request.include_sensitive)
		if !copied_ok {
			record_slice_release(active[:destination_index], allocator)
			delete(active, allocator)
			delete(history, allocator)
			return {}, false, registry_reject(state, copy_failure)
		}
		active[destination_index] = copied
	}
	for destination_index in 0 ..< history_count {
		source_index := state.history_count - 1 - destination_index
		copied, copied_ok, copy_failure := record_clone(state.history[source_index], allocator, request.include_sensitive)
		if !copied_ok {
			record_slice_release(active, allocator)
			record_slice_release(history[:destination_index], allocator)
			delete(active, allocator)
			delete(history, allocator)
			return {}, false, registry_reject(state, copy_failure)
		}
		history[destination_index] = copied
	}
	return Inspection {
		stats = registry_stats_from_state(state),
		active = active,
		history = history,
		last_rejection = state.last_rejection,
	}, true, {}
}

@(private)
registry_find_action_record :: proc(state: ^Registry_State, request: Action_Request) -> ^Record {
	for index in 0 ..< state.active_count {
		record := &state.active[index]
		if record.id == request.record_id && record.generation == request.record_generation &&
		   record.source == request.source {
			return record
		}
	}
	for reverse_index in 0 ..< state.history_count {
		index := state.history_count - 1 - reverse_index
		record := &state.history[index]
		if record.id == request.record_id && record.generation == request.record_generation &&
		   record.source == request.source {
			return record
		}
	}
	return nil
}

/* inspection_release frees one complete copied inspection. */
inspection_release :: proc(inspection: ^Inspection, allocator: runtime.Allocator) {
	if inspection == nil do return
	record_slice_release(inspection.active, allocator)
	record_slice_release(inspection.history, allocator)
	delete(inspection.active, allocator)
	delete(inspection.history, allocator)
	inspection^ = {}
}

/* registry_clear_history releases retained snapshots without changing active state. */
registry_clear_history :: proc(registry: ^Registry) -> (cleared: u64, failure: Failure) {
	state := registry_state(registry)
	if state == nil do return 0, Failure{operation = .Clear_History, code = .Invalid_Registry}
	cleared = u64(state.history_count)
	for index in 0 ..< state.history_count do record_release(&state.history[index], state.persistent)
	state.history_count = 0
	state.usage.history_records = 0
	state.usage.history_bytes = 0
	if cleared > 0 {
		state.generation += 1
		state.sequence += 1
	}
	return cleared, {}
}

/* registry_stats copies exact registry identity and resource accounting. */
registry_stats :: proc(registry: ^Registry) -> (Registry_Stats, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Inspect, code = .Invalid_Registry}
	return registry_stats_from_state(state), true, {}
}

/* registry_close releases one registry and all owned copied content. */
registry_close :: proc(registry: ^Registry) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil do return false, Failure{operation = .Close, code = .Invalid_Registry}
	for index in 0 ..< state.active_count do record_release(&state.active[index], state.persistent)
	for index in 0 ..< state.history_count do record_release(&state.history[index], state.persistent)
	delete(state.active, state.persistent)
	delete(state.history, state.persistent)
	allocator := state.persistent
	free(state, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return (^Registry_State)(registry.state)
}

@(private)
registry_reject :: proc(state: ^Registry_State, failure: Failure) -> Failure {
	if state != nil {
		state.last_rejection = failure
		state.usage.rejected_updates += 1
	}
	return failure
}

@(private)
registry_stats_from_state :: proc(state: ^Registry_State) -> Registry_Stats {
	return {registry_id = state.id, generation = state.generation, sequence = state.sequence, policy = state.policy, usage = state.usage}
}

@(private)
registry_find_active :: proc(state: ^Registry_State, id: Record_ID) -> int {
	for index in 0 ..< state.active_count {
		if state.active[index].id == id do return index
	}
	return -1
}

@(private)
registry_find_coalescing :: proc(state: ^Registry_State, proposal: Proposal) -> int {
	for index in 0 ..< state.active_count {
		record := &state.active[index]
		if record.kind == .Notification && record.source.id == proposal.source.id &&
		   record.coalescing_key == proposal.coalescing_key {
			return index
		}
	}
	return -1
}

@(private)
registry_remove_active_at :: proc(state: ^Registry_State, index: int) {
	record := &state.active[index]
	state.usage.active_bytes -= record_owned_bytes(record^)
	record_release(record, state.persistent)
	for move_index := index; move_index + 1 < state.active_count; move_index += 1 {
		state.active[move_index] = state.active[move_index + 1]
	}
	state.active_count -= 1
	state.active[state.active_count] = {}
	state.usage.active_records = u64(state.active_count)
}

@(private)
registry_prepare_history_space :: proc(state: ^Registry_State, required_bytes: u64, attention: Attention) {
	for state.history_count >= len(state.history) ||
	    state.usage.history_bytes + required_bytes > state.policy.history_bytes {
		index := registry_history_eviction_index(state, attention)
		if index < 0 do return
		state.usage.history_bytes -= record_owned_bytes(state.history[index])
		record_release(&state.history[index], state.persistent)
		for move_index := index; move_index + 1 < state.history_count; move_index += 1 {
			state.history[move_index] = state.history[move_index + 1]
		}
		state.history_count -= 1
		state.history[state.history_count] = {}
		state.usage.history_records = u64(state.history_count)
		state.usage.evicted_history += 1
	}
}

@(private)
registry_history_eviction_index :: proc(state: ^Registry_State, incoming: Attention) -> int {
	for index in 0 ..< state.history_count {
		record := state.history[index]
		if record.attention == .Ordinary && record_is_terminal(record) do return index
	}
	for index in 0 ..< state.history_count {
		record := state.history[index]
		if record.attention == .Ordinary && record.kind == .Notification do return index
	}
	if incoming == .Required && state.history_count > 0 do return 0
	return -1
}

@(private)
proposal_validate :: proc(state: ^Registry_State, proposal: Proposal, active_index, coalesced_index: int) -> (bool, Failure) {
	operation := Operation.Publish
	if active_index >= 0 || coalesced_index >= 0 do operation = .Replace
	failure := Failure{operation = operation, record_id = proposal.id, generation = proposal.generation, source = proposal.source}
	if proposal.id == Record_ID(0) || proposal.source.id == Source_ID(0) {
		failure.code = .Invalid_Identity
		return false, failure
	}
	if proposal.generation == Record_Generation(0) || proposal.source.generation == Source_Generation(0) {
		failure.code = .Invalid_Generation
		return false, failure
	}
	if proposal.kind == .Invalid {
		failure.code = .Invalid_Kind
		return false, failure
	}
	if proposal.class == .Invalid {
		failure.code = .Invalid_Class
		return false, failure
	}
	if proposal.severity == .Invalid {
		failure.code = .Invalid_Severity
		return false, failure
	}
	if proposal.lifecycle == .Invalid || proposal.visibility == .Invalid {
		failure.code = .Invalid_Lifecycle
		return false, failure
	}
	if len(proposal.title) == 0 || len(proposal.title) > MAX_TITLE_BYTES {
		failure.code = .Title_Limit
		failure.limit = MAX_TITLE_BYTES
		failure.actual = u64(len(proposal.title))
		return false, failure
	}
	if len(proposal.message) > MAX_MESSAGE_BYTES {
		failure.code = .Message_Limit
		failure.limit = MAX_MESSAGE_BYTES
		failure.actual = u64(len(proposal.message))
		return false, failure
	}
	if !content_is_safe(proposal.title, MAX_TITLE_BYTES) || !content_is_safe(proposal.message, MAX_MESSAGE_BYTES) ||
	   !content_is_safe(proposal.coalescing_key, MAX_COALESCING_KEY_BYTES) {
		failure.code = .Unsafe_Content
		return false, failure
	}
	if len(proposal.metadata) > MAX_METADATA_ENTRIES {
		failure.code = .Metadata_Limit
		failure.limit = MAX_METADATA_ENTRIES
		failure.actual = u64(len(proposal.metadata))
		return false, failure
	}
	if len(proposal.actions) > MAX_ACTIONS {
		failure.code = .Action_Limit
		failure.limit = MAX_ACTIONS
		failure.actual = u64(len(proposal.actions))
		return false, failure
	}
	for item in proposal.metadata {
		if len(item.key) == 0 || !content_is_safe(item.key, MAX_METADATA_KEY_BYTES) ||
		   !content_is_safe(item.value, MAX_METADATA_VALUE_BYTES) {
			failure.code = .Metadata_Limit
			return false, failure
		}
	}
	for action in proposal.actions {
		if action.id == Action_ID(0) || len(action.command) == 0 ||
		   !content_is_safe(action.command, MAX_ACTION_NAME_BYTES) ||
		   !content_is_safe(action.argument, MAX_ACTION_ARGUMENT_BYTES) {
			failure.code = .Action_Limit
			return false, failure
		}
	}
	if proposal.kind == .Notification {
		if proposal.progress.state != .Invalid || proposal.progress.measurement != .Invalid ||
		   proposal.progress.current != 0 || proposal.progress.total != 0 ||
		   len(proposal.progress.phase) != 0 || proposal.class == .Progress {
			failure.code = .Invalid_Progress
			return false, failure
		}
	} else {
		if proposal.class != .Progress && proposal.class != .Completion {
			failure.code = .Invalid_Class
			return false, failure
		}
		if !progress_is_valid(proposal.progress) {
			failure.code = .Invalid_Progress
			return false, failure
		}
	}
	if active_index >= 0 {
		prior := state.active[active_index]
		if proposal.replacement != prior.id || proposal.source.id != prior.source.id {
			failure.code = .Source_Mismatch
			return false, failure
		}
		if proposal.generation <= prior.generation || proposal.source.generation < prior.source.generation {
			failure.code = .Stale_Generation
			return false, failure
		}
		if u64(proposal.generation) - u64(prior.generation) > state.policy.updates_per_record {
			failure.code = .Update_Limit
			failure.limit = state.policy.updates_per_record
			failure.actual = u64(proposal.generation) - u64(prior.generation)
			return false, failure
		}
		if prior.kind != proposal.kind ||
		   (proposal.kind == .Progress && !progress_transition_is_valid(prior.progress.state, proposal.progress.state)) {
			failure.code = .Invalid_Transition
			return false, failure
		}
	} else if coalesced_index >= 0 {
		prior := state.active[coalesced_index]
		if proposal.source.generation <= prior.source.generation {
			failure.code = .Stale_Generation
			return false, failure
		}
	} else if proposal.replacement != Record_ID(0) {
		failure.code = .Record_Not_Found
		return false, failure
	}
	return true, {}
}

@(private)
progress_is_valid :: proc(progress: Progress) -> bool {
	if progress.state == .Invalid || progress.measurement == .Invalid ||
	   !content_is_safe(progress.phase, MAX_PHASE_BYTES) {
		return false
	}
	if progress.measurement == .Indeterminate {
		return progress.current == 0 && progress.total == 0
	}
	return progress.total > 0 && progress.current <= progress.total
}

@(private)
record_should_retain :: proc(record: Record) -> bool {
	if record.retention != .History do return false
	return record.kind == .Notification || record_is_terminal(record)
}

@(private)
record_remains_active :: proc(record: Record) -> bool {
	if record.kind == .Notification do return true
	if !record_is_terminal(record) do return true
	return record.attention == .Required || record.progress.state == .Failed
}

@(private)
record_copy_from_proposal :: proc(proposal: Proposal, sequence: u64, allocator: runtime.Allocator) -> (Record, bool, Failure) {
	record := Record {
		id = proposal.id,
		generation = proposal.generation,
		source = proposal.source,
		kind = proposal.kind,
		class = proposal.class,
		severity = proposal.severity,
		attention = proposal.attention,
		lifecycle = proposal.lifecycle,
		retention = proposal.retention,
		visibility = proposal.visibility,
		sensitivity = proposal.sensitivity,
		created_sequence = sequence,
		updated_sequence = sequence,
		repetition_count = 1,
	}
	error: runtime.Allocator_Error
	record.title, error = clone_string(proposal.title, allocator)
	if error != nil do return {}, false, Failure{operation = .Publish, code = .Allocation}
	record.message, error = clone_string(proposal.message, allocator)
	if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	record.coalescing_key, error = clone_string(proposal.coalescing_key, allocator)
	if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	record.progress = proposal.progress
	record.progress.phase, error = clone_string(proposal.progress.phase, allocator)
	if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	record.metadata, error = make([]Metadata, len(proposal.metadata), allocator)
	if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	for item, index in proposal.metadata {
		record.metadata[index].sensitive = item.sensitive
		record.metadata[index].key, error = clone_string(item.key, allocator)
		if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
		record.metadata[index].value, error = clone_string(item.value, allocator)
		if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	}
	record.actions, error = make([]Action, len(proposal.actions), allocator)
	if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	for action, index in proposal.actions {
		record.actions[index] = {id = action.id, cancel = action.cancel, sensitive = action.sensitive}
		record.actions[index].command, error = clone_string(action.command, allocator)
		if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
		record.actions[index].argument, error = clone_string(action.argument, allocator)
		if error != nil { record_release(&record, allocator); return {}, false, Failure{operation = .Publish, code = .Allocation} }
	}
	return record, true, {}
}

@(private)
record_clone :: proc(source: Record, allocator: runtime.Allocator, include_sensitive: bool) -> (Record, bool, Failure) {
	proposal := Proposal {
		id = source.id,
		generation = source.generation,
		source = source.source,
		kind = source.kind,
		class = source.class,
		severity = source.severity,
		attention = source.attention,
		lifecycle = source.lifecycle,
		retention = source.retention,
		visibility = source.visibility,
		sensitivity = source.sensitivity,
		title = source.title,
		message = source.message,
		coalescing_key = source.coalescing_key,
		progress = source.progress,
	}
	if source.sensitivity == .Sensitive && !include_sensitive {
		proposal.title = "<redacted>"
		proposal.message = "<redacted>"
		proposal.coalescing_key = ""
	}
	metadata := make([]Metadata_Proposal, len(source.metadata), context.temp_allocator)
	defer delete(metadata, context.temp_allocator)
	for item, index in source.metadata {
		metadata[index] = {key = item.key, value = item.value, sensitive = item.sensitive}
		if item.sensitive && !include_sensitive do metadata[index].value = "<redacted>"
	}
	actions := make([]Action_Proposal, len(source.actions), context.temp_allocator)
	defer delete(actions, context.temp_allocator)
	for action, index in source.actions {
		actions[index] = {id = action.id, command = action.command, argument = action.argument, cancel = action.cancel, sensitive = action.sensitive}
		if action.sensitive && !include_sensitive do actions[index].argument = "<redacted>"
	}
	proposal.metadata = metadata
	proposal.actions = actions
	copied, ok, failure := record_copy_from_proposal(proposal, source.updated_sequence, allocator)
	if ok {
		copied.created_sequence = source.created_sequence
		copied.updated_sequence = source.updated_sequence
		copied.repetition_count = source.repetition_count
	}
	return copied, ok, failure
}

@(private)
record_release :: proc(record: ^Record, allocator: runtime.Allocator) {
	if record == nil do return
	delete_string(record.title, allocator)
	delete_string(record.message, allocator)
	delete_string(record.coalescing_key, allocator)
	delete_string(record.progress.phase, allocator)
	for &item in record.metadata {
		delete_string(item.key, allocator)
		delete_string(item.value, allocator)
	}
	for &action in record.actions do action_release(&action, allocator)
	delete(record.metadata, allocator)
	delete(record.actions, allocator)
	record^ = {}
}

@(private)
record_slice_release :: proc(records: []Record, allocator: runtime.Allocator) {
	for &record in records do record_release(&record, allocator)
}

@(private)
action_clone :: proc(source: Action, allocator: runtime.Allocator, include_sensitive: bool) -> (Action, Failure) {
	action := Action{id = source.id, cancel = source.cancel, sensitive = source.sensitive}
	error: runtime.Allocator_Error
	action.command, error = clone_string(source.command, allocator)
	if error != nil do return {}, Failure{operation = .Cancel, code = .Allocation}
	argument := source.argument
	if source.sensitive && !include_sensitive do argument = "<redacted>"
	action.argument, error = clone_string(argument, allocator)
	if error != nil {
		delete_string(action.command, allocator)
		return {}, Failure{operation = .Cancel, code = .Allocation}
	}
	return action, {}
}

@(private)
action_release :: proc(action: ^Action, allocator: runtime.Allocator) {
	delete_string(action.command, allocator)
	delete_string(action.argument, allocator)
	action^ = {}
}

@(private)
record_owned_bytes :: proc(record: Record) -> u64 {
	bytes := u64(size_of(Record) + len(record.title) + len(record.message) + len(record.coalescing_key) + len(record.progress.phase))
	bytes += u64(len(record.metadata)) * u64(size_of(Metadata))
	for item in record.metadata do bytes += u64(len(item.key) + len(item.value))
	bytes += u64(len(record.actions)) * u64(size_of(Action))
	for action in record.actions do bytes += u64(len(action.command) + len(action.argument))
	return bytes
}

@(private)
clone_string :: proc(contents: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	if len(contents) == 0 do return "", nil
	bytes, allocation_error := make([]byte, len(contents), allocator)
	if allocation_error != nil do return "", allocation_error
	copy(bytes, contents)
	return string(bytes), nil
}

@(private)
delete_string :: proc(contents: string, allocator: runtime.Allocator) {
	if len(contents) > 0 do delete(contents, allocator)
}
