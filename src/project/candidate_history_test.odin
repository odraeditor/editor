// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:mem"
import "core:testing"

/* Verifies complete load replacement, indexed lookup, recording, and copied canonical order. */
@(test)
loads_records_and_snapshots_exact_usage :: proc(t: ^testing.T) {
	history: Candidate_History
	initialized, init_failure := candidate_history_init(&history, "odra-development")
	testing.expectf(t, initialized, "history init failed with %v", init_failure.code)
	defer candidate_history_close(&history)
	definitions := []Candidate_History_Entry_Definition {
		{category = .Document, key = "/tmp/alpha.odin", sequence = 2},
		{category = .Command, key = "execute-extended-command", sequence = 4},
	}
	replaced, replace_failure := candidate_history_replace(
		&history,
		"odra-development",
		7,
		5,
		definitions,
	)
	testing.expectf(t, replaced, "history replace failed with %v", replace_failure.code)
	command_sequence, command_found := candidate_history_lookup(
		&history,
		.Command,
		"execute-extended-command",
	)
	testing.expect(t, command_found)
	testing.expect_value(t, command_sequence, u64(4))
	recorded_sequence, recorded, record_failure := candidate_history_record_success(
		&history,
		.Project_File,
		"/tmp/beta.odin",
	)
	testing.expectf(t, recorded, "history record failed with %v", record_failure.code)
	testing.expect_value(t, recorded_sequence, u64(5))
	project_sequence, project_recorded, project_failure := candidate_history_record_success(
		&history,
		.Project,
		"odra",
	)
	testing.expectf(t, project_recorded, "Project history record failed with %v", project_failure.code)
	testing.expect_value(t, project_sequence, u64(6))
	workspace_sequence, workspace_recorded, workspace_failure := candidate_history_record_success(
		&history,
		.Workspace,
		"daily-work",
	)
	testing.expectf(t, workspace_recorded, "Workspace history record failed with %v", workspace_failure.code)
	testing.expect_value(t, workspace_sequence, u64(7))
	batch, copied, copy_failure := candidate_history_snapshot(&history)
	testing.expectf(t, copied, "history snapshot failed with %v", copy_failure.code)
	defer candidate_history_batch_close(&batch)
	testing.expect_value(t, batch.project_id, "odra-development")
	testing.expect_value(t, batch.generation, u64(7))
	testing.expect_value(t, batch.next_sequence, u64(8))
	testing.expect_value(t, len(batch.entries), 5)
	if len(batch.entries) == 5 {
		testing.expect_value(t, batch.entries[0].category, Candidate_History_Category.Workspace)
		testing.expect_value(t, batch.entries[1].category, Candidate_History_Category.Project)
		testing.expect_value(t, batch.entries[2].category, Candidate_History_Category.Project_File)
		testing.expect_value(t, batch.entries[3].category, Candidate_History_Category.Command)
		testing.expect_value(t, batch.entries[4].category, Candidate_History_Category.Document)
	}
}

/* Verifies action flush thresholds, exact publication acknowledgement, and retry exhaustion. */
@(test)
bounds_dirty_generation_and_flush_retry :: proc(t: ^testing.T) {
	history: Candidate_History
	initialized, _ := candidate_history_init(&history, "flush-project")
	testing.expect(t, initialized)
	defer candidate_history_close(&history)
	for index in 0 ..< int(CANDIDATE_HISTORY_FLUSH_EVENTS) {
		candidate_history_record_success(&history, .Command, "execute-extended-command")
		if index + 1 < int(CANDIDATE_HISTORY_FLUSH_EVENTS) {
			testing.expect(t, !candidate_history_flush_due(&history))
		}
	}
	testing.expect(t, candidate_history_flush_due(&history))
	batch, copied, _ := candidate_history_snapshot(&history)
	testing.expect(t, copied)
	defer candidate_history_batch_close(&batch)
	stale, stale_failure := candidate_history_mark_published(
		&history,
		batch.dirty_generation - 1,
		1,
	)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Candidate_History_Failure_Code.Stale_Generation)
	retry, _ := candidate_history_note_flush_failure(&history)
	second_retry, retry_failure := candidate_history_note_flush_failure(&history)
	testing.expect(t, retry && !second_retry)
	testing.expect_value(t, retry_failure.code, Candidate_History_Failure_Code.Retry_Exhausted)
	published, publish_failure := candidate_history_mark_published(
		&history,
		batch.dirty_generation,
		1,
	)
	testing.expectf(t, published, "history publish failed with %v", publish_failure.code)
	testing.expect(t, !candidate_history_flush_due(&history))
}

/* Verifies rejected replacement and allocation faults preserve exact cleanup. */
@(test)
rejects_duplicate_load_without_leaking :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	history: Candidate_History
	initialized, _ := candidate_history_init(&history, "tracked-project", allocator)
	testing.expect(t, initialized)
	definitions := []Candidate_History_Entry_Definition {
		{category = .Command, key = "project-find-file", sequence = 1},
		{category = .Command, key = "project-find-file", sequence = 2},
	}
	replaced, _ := candidate_history_replace(&history, "tracked-project", 1, 3, definitions)
	testing.expect(t, !replaced)
	usage, usage_ok := candidate_history_usage(&history)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.entries, u32(0))
	candidate_history_close(&history)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
