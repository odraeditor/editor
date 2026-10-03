// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "base:runtime"
import "../transaction"

/* Scheduler_Failure_Code classifies bounded checkpoint scheduling failures. */
Scheduler_Failure_Code :: enum u8 {
	None,
	Invalid_State,
	Invalid_Commit,
	Capacity_Exceeded,
	Stale_Claim,
}

/* Scheduler_Failure reports scheduling rejection without buffer contents. */
Scheduler_Failure :: struct {
	code:      Scheduler_Failure_Code,
	buffer_id: Buffer_ID,
	revision:  u64,
	limit:     u64,
}

/* Checkpoint_Claim binds one due checkpoint to its exact buffer revision. */
Checkpoint_Claim :: struct {
	buffer_id:         Buffer_ID,
	revision:          u64,
	policy_generation: Policy_Generation,
}

@(private)
Scheduler_Entry :: struct {
	live:                     bool,
	buffer_id:                Buffer_ID,
	saved_revision:           u64,
	checkpoint_revision:      u64,
	pending_revision:         u64,
	pending_first_milliseconds: u64,
	pending_last_milliseconds:  u64,
	claimed_revision:         u64,
	claimed_first_milliseconds: u64,
	claimed_last_milliseconds:  u64,
}

/* Scheduler coalesces admitted transaction commits into bounded checkpoint claims. */
Scheduler :: struct {
	policy:    Policy,
	entries:   []Scheduler_Entry,
	allocator: runtime.Allocator,
	live:      bool,
}

/* scheduler_init allocates one bounded scheduler from a confirmed policy. */
scheduler_init :: proc(
	state: ^Scheduler,
	policy: Policy,
	allocator: runtime.Allocator,
) -> (bool, Scheduler_Failure) {
	if state == nil || state.live || allocator.procedure == nil {
		return false, Scheduler_Failure{code = .Invalid_State}
	}
	if valid, _ := policy_validate(policy); !valid || !policy.enabled {
		return false, Scheduler_Failure{code = .Invalid_State}
	}
	entries, allocation_error := make(
		[]Scheduler_Entry,
		int(policy.retention.total_records),
		allocator,
	)
	if allocation_error != nil {
		return false, Scheduler_Failure{
			code = .Capacity_Exceeded,
			limit = policy.retention.total_records,
		}
	}
	state^ = Scheduler {
		policy = policy,
		entries = entries,
		allocator = allocator,
		live = true,
	}
	return true, {}
}

/* scheduler_close releases one initialized scheduler. */
scheduler_close :: proc(state: ^Scheduler) {
	if state == nil || !state.live do return
	delete(state.entries, state.allocator)
	state^ = {}
}

/* scheduler_mark_commit records the newest admitted revision for one buffer. */
scheduler_mark_commit :: proc(
	state: ^Scheduler,
	buffer_id: Buffer_ID,
	revision, monotonic_milliseconds: u64,
) -> (bool, Scheduler_Failure) {
	if !scheduler_is_live(state) || buffer_id == Buffer_ID(0) || revision == 0 {
		return false, Scheduler_Failure{
			code = .Invalid_Commit,
			buffer_id = buffer_id,
			revision = revision,
		}
	}
	entry, found := scheduler_find_entry(state, buffer_id)
	if !found {
		entry = scheduler_free_entry(state)
		if entry == nil {
			return false, Scheduler_Failure{
				code = .Capacity_Exceeded,
				buffer_id = buffer_id,
				revision = revision,
				limit = u64(len(state.entries)),
			}
		}
		entry.live = true
		entry.buffer_id = buffer_id
	}
	latest := max(entry.saved_revision, max(entry.checkpoint_revision, entry.claimed_revision))
	latest = max(latest, entry.pending_revision)
	if revision <= latest {
		return false, Scheduler_Failure{
			code = .Invalid_Commit,
			buffer_id = buffer_id,
			revision = revision,
		}
	}
	if entry.pending_revision == 0 {
		entry.pending_first_milliseconds = monotonic_milliseconds
	}
	entry.pending_revision = revision
	entry.pending_last_milliseconds = monotonic_milliseconds
	return true, {}
}

/* scheduler_claim_due claims the earliest due buffer deterministically. */
scheduler_claim_due :: proc(
	state: ^Scheduler,
	monotonic_milliseconds: u64,
) -> (Checkpoint_Claim, bool, Scheduler_Failure) {
	if !scheduler_is_live(state) {
		return {}, false, Scheduler_Failure{code = .Invalid_State}
	}
	selected: ^Scheduler_Entry
	selected_due := u64(0)
	for &entry in state.entries {
		if !entry.live || entry.pending_revision == 0 do continue
		due := scheduler_entry_due_milliseconds(entry, state.policy)
		if monotonic_milliseconds < due do continue
		if selected == nil || due < selected_due ||
		   (due == selected_due && u64(entry.buffer_id) < u64(selected.buffer_id)) {
			selected = &entry
			selected_due = due
		}
	}
	if selected == nil do return {}, false, {}
	selected.claimed_revision = selected.pending_revision
	selected.claimed_first_milliseconds = selected.pending_first_milliseconds
	selected.claimed_last_milliseconds = selected.pending_last_milliseconds
	selected.pending_revision = 0
	selected.pending_first_milliseconds = 0
	selected.pending_last_milliseconds = 0
	return Checkpoint_Claim {
		buffer_id = selected.buffer_id,
		revision = selected.claimed_revision,
		policy_generation = state.policy.generation,
	}, true, {}
}

/* scheduler_resolve_claim accepts publication or restores failed work to the queue. */
scheduler_resolve_claim :: proc(
	state: ^Scheduler,
	claim: Checkpoint_Claim,
	published: bool,
) -> (bool, Scheduler_Failure) {
	if !scheduler_is_live(state) || claim.policy_generation != state.policy.generation {
		return false, Scheduler_Failure{code = .Stale_Claim}
	}
	entry, found := scheduler_find_entry(state, claim.buffer_id)
	if !found || entry.claimed_revision != claim.revision || claim.revision == 0 {
		return false, Scheduler_Failure{
			code = .Stale_Claim,
			buffer_id = claim.buffer_id,
			revision = claim.revision,
		}
	}
	if published {
		entry.checkpoint_revision = claim.revision
	} else {
		if entry.pending_revision == 0 {
			entry.pending_revision = entry.claimed_revision
			entry.pending_first_milliseconds = entry.claimed_first_milliseconds
			entry.pending_last_milliseconds = entry.claimed_last_milliseconds
		} else {
			entry.pending_first_milliseconds = min(
				entry.pending_first_milliseconds,
				entry.claimed_first_milliseconds,
			)
		}
	}
	entry.claimed_revision = 0
	entry.claimed_first_milliseconds = 0
	entry.claimed_last_milliseconds = 0
	return true, {}
}

/* scheduler_confirm_saved retires only work no newer than an exact saved revision. */
scheduler_confirm_saved :: proc(
	state: ^Scheduler,
	buffer_id: Buffer_ID,
	revision: u64,
) -> (retired_checkpoint_revision: u64, ok: bool, failure: Scheduler_Failure) {
	if !scheduler_is_live(state) || buffer_id == Buffer_ID(0) || revision == 0 {
		return 0, false, Scheduler_Failure{code = .Invalid_State}
	}
	entry, found := scheduler_find_entry(state, buffer_id)
	if !found do return 0, true, {}
	if revision < entry.saved_revision {
		return 0, false, Scheduler_Failure{
			code = .Invalid_Commit,
			buffer_id = buffer_id,
			revision = revision,
		}
	}
	entry.saved_revision = revision
	if entry.checkpoint_revision > 0 && entry.checkpoint_revision <= revision {
		retired_checkpoint_revision = entry.checkpoint_revision
		entry.checkpoint_revision = 0
	}
	if entry.pending_revision > 0 && entry.pending_revision <= revision {
		entry.pending_revision = 0
		entry.pending_first_milliseconds = 0
		entry.pending_last_milliseconds = 0
	}
	return retired_checkpoint_revision, true, {}
}

/* scheduler_forget_buffer removes all process-local scheduling state after explicit closure. */
scheduler_forget_buffer :: proc(
	state: ^Scheduler,
	buffer_id: Buffer_ID,
) -> (bool, Scheduler_Failure) {
	if !scheduler_is_live(state) || buffer_id == Buffer_ID(0) {
		return false, Scheduler_Failure{code = .Invalid_State, buffer_id = buffer_id}
	}
	entry, found := scheduler_find_entry(state, buffer_id)
	if !found do return true, {}
	entry^ = {}
	return true, {}
}

/* scheduler_transaction_observer marks one successful transaction result. */
scheduler_transaction_observer :: proc(user_data: rawptr, event: transaction.Commit_Event) -> bool {
	if user_data == nil do return false
	state := cast(^Scheduler)user_data
	marked, _ := scheduler_mark_commit(
		state,
		Buffer_ID(u64(event.buffer_id)),
		u64(event.result_revision),
		u64(event.transaction_id),
	)
	return marked
}

/* scheduler_commit_observer returns a transaction observer for one live scheduler. */
scheduler_commit_observer :: proc(state: ^Scheduler) -> transaction.Commit_Observer {
	if !scheduler_is_live(state) do return {}
	return transaction.Commit_Observer {
		procedure = scheduler_transaction_observer,
		user_data = state,
	}
}

@(private)
scheduler_is_live :: proc(state: ^Scheduler) -> bool {
	return state != nil && state.live && state.entries != nil
}

@(private)
scheduler_find_entry :: proc(state: ^Scheduler, buffer_id: Buffer_ID) -> (^Scheduler_Entry, bool) {
	for &entry in state.entries {
		if entry.live && entry.buffer_id == buffer_id do return &entry, true
	}
	return nil, false
}

@(private)
scheduler_free_entry :: proc(state: ^Scheduler) -> ^Scheduler_Entry {
	for &entry in state.entries {
		if !entry.live do return &entry
	}
	return nil
}

@(private)
scheduler_entry_due_milliseconds :: proc(entry: Scheduler_Entry, policy: Policy) -> u64 {
	quiet_due := entry.pending_last_milliseconds + policy.debounce_milliseconds
	interval_due := entry.pending_first_milliseconds + policy.maximum_interval_milliseconds
	switch policy.strategy {
	case .Transaction_Debounced:
		return quiet_due
	case .Interval:
		return interval_due
	case .Hybrid:
		return min(quiet_due, interval_due)
	case .Invalid:
		return 0
	}
	return 0
}
