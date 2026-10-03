// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package transaction

import "../editor"
import "../history"
import "core:slice"

/* proposal_prepare checks and privately prepares one complete optimistic proposal for atomic commit. */
proposal_prepare :: proc(
	transaction: ^Multibuffer_Transaction,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	proposal: Edit_Proposal,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
	histories: []^history.Store = nil,
) -> (ok: bool, failure: Failure_Context) {
	return proposal_admit(transaction, transaction_id, undo_unit_id, proposal, allocators, limits, histories)
}

@(private)
Proposal_Admission_Entry :: struct {
	buffer:        ^editor.Buffer,
	buffer_id:     editor.Buffer_ID,
	base_revision: editor.Revision,
	batch:         []Base_Splice,
	matched:       bool,
}

/*
proposal_admit checks one complete optimistic proposal and prepares it for commit.
Stale or incomplete input fails without retry, coordinate transformation, or publication.
*/
proposal_admit :: proc(
	transaction: ^Multibuffer_Transaction,
	transaction_id: Transaction_ID,
	undo_unit_id: Undo_Unit_ID,
	proposal: Edit_Proposal,
	allocators: Allocator_Set,
	limits := DEFAULT_LIMITS,
	histories: []^history.Store = nil,
) -> (ok: bool, failure: Failure_Context) {
	assert(transaction != nil)
	assert(transaction.state == nil, "proposal target is already initialized")
	if len(proposal.snapshots) == 0 || len(proposal.snapshots) != len(proposal.edits) {
		return false, Failure_Context {
			code = .Incomplete_Participant_Set,
			transaction_id = transaction_id,
			limit = u64(len(proposal.snapshots)),
			actual = u64(len(proposal.edits)),
		}
	}
	if u64(len(proposal.snapshots)) > limits.buffer_participants {
		return false, Failure_Context {
			code = .Participant_Limit,
			transaction_id = transaction_id,
			limit = limits.buffer_participants,
			actual = u64(len(proposal.snapshots)),
		}
	}
	entries, allocation_error := make(
		[]Proposal_Admission_Entry,
		len(proposal.snapshots),
		allocators.temporary,
	)
	if allocation_error != nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	}
	defer delete(entries, allocators.temporary)
	for snapshot, index in proposal.snapshots {
		stats, stats_ok, editor_failure := editor.buffer_stats(snapshot.buffer)
		if !stats_ok {
			return false, transaction_editor_failure(transaction_id, 0, editor_failure)
		}
		if stats.buffer_id != snapshot.buffer_id {
			return false, Failure_Context {
				code = .Wrong_Buffer,
				transaction_id = transaction_id,
				buffer_id = snapshot.buffer_id,
				base_revision = snapshot.base_revision,
			}
		}
		if stats.revision != snapshot.base_revision {
			return false, Failure_Context {
				code = .Stale_Revision,
				transaction_id = transaction_id,
				buffer_id = snapshot.buffer_id,
				base_revision = snapshot.base_revision,
				actual = u64(stats.revision),
			}
		}
		entries[index] = Proposal_Admission_Entry {
			buffer = snapshot.buffer,
			buffer_id = snapshot.buffer_id,
			base_revision = snapshot.base_revision,
		}
	}
	slice.sort_by(entries, proposal_admission_entry_less)
	for index in 1 ..< len(entries) {
		if entries[index - 1].buffer_id == entries[index].buffer_id {
			return false, Failure_Context {
				code = .Incomplete_Participant_Set,
				transaction_id = transaction_id,
				buffer_id = entries[index].buffer_id,
			}
		}
	}

	for edit in proposal.edits {
		entry := proposal_admission_find(entries, edit.buffer_id)
		if entry == nil || entry.matched {
			return false, Failure_Context {
				code = .Incomplete_Participant_Set,
				transaction_id = transaction_id,
				buffer_id = edit.buffer_id,
			}
		}
		if edit.base_revision != entry.base_revision {
			return false, Failure_Context {
				code = .Stale_Revision,
				transaction_id = transaction_id,
				buffer_id = edit.buffer_id,
				base_revision = edit.base_revision,
				actual = u64(entry.base_revision),
			}
		}
		entry.batch = edit.batch
		entry.matched = true
	}
	for entry in entries {
		if !entry.matched {
			return false, Failure_Context {
				code = .Incomplete_Participant_Set,
				transaction_id = transaction_id,
				buffer_id = entry.buffer_id,
			}
		}
	}

	buffers, buffer_error := make([]^editor.Buffer, len(entries), allocators.temporary)
	if buffer_error != nil {
		return false, Failure_Context{code = .Temporary_Memory_Limit, transaction_id = transaction_id}
	}
	defer delete(buffers, allocators.temporary)
	for entry, index in entries {
		buffers[index] = entry.buffer
	}
	started, begin_failure := multibuffer_begin(
		transaction,
		transaction_id,
		undo_unit_id,
		buffers,
		proposal.origin,
		proposal.command,
		allocators,
		limits,
	)
	if !started {
		return false, begin_failure
	}
	if len(histories) > 0 {
		tracked, track_failure := multibuffer_track_history(transaction, histories)
		if !tracked do return false, track_failure
	}
	for entry in entries {
		applied, apply_failure := multibuffer_apply_batch(
			transaction,
			entry.buffer_id,
			entry.batch,
		)
		if !applied {
			return false, apply_failure
		}
	}
	return multibuffer_validate(transaction)
}

@(private)
proposal_admission_entry_less :: proc(left, right: Proposal_Admission_Entry) -> bool {
	return u64(left.buffer_id) < u64(right.buffer_id)
}

@(private)
proposal_admission_find :: proc(
	entries: []Proposal_Admission_Entry,
	buffer_id: editor.Buffer_ID,
) -> ^Proposal_Admission_Entry {
	low := 0
	high := len(entries)
	for low < high {
		middle := low + (high - low) / 2
		entry := &entries[middle]
		if entry.buffer_id == buffer_id {
			return entry
		}
		if u64(entry.buffer_id) < u64(buffer_id) {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return nil
}
