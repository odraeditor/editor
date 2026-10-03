// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "../filesystem"
import "core:mem"
import "core:os"
import "core:testing"
import "core:time"

/* Verifies filesystem adaptation preserves entry identity and filtering semantics. */
@(test)
filesystem_candidates_preserve_entry_actions :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-candidates-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	directory, directory_error := os.join_path({root, "Projects"}, context.allocator)
	file, file_error := os.join_path({root, "profile.odin"}, context.allocator)
	testing.expect(t, directory_error == nil && file_error == nil)
	if directory_error != nil || file_error != nil do return
	defer {
		delete(file)
		delete(directory)
	}
	testing.expect(t, os.make_directory(directory) == nil)
	testing.expect(t, os.write_entire_file(file, "package profile") == nil)
	batch, observed, observe_failure := filesystem.directory_observe(
		root,
		9,
		filesystem.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, observed, "observation failed: %v", observe_failure.code)
	if !observed do return
	defer filesystem.directory_batch_close(&batch)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	baseline := tracking.current_memory_allocated
	source, adapted, adapt_failure := filesystem_candidate_source_build(&batch, allocator)
	testing.expectf(t, adapted, "adaptation failed: %v", adapt_failure.code)
	if !adapted do return
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Filesystem_Entries)
	testing.expect_value(t, len(source.definition.descriptors), 2)
	session: Candidate_Session
	_, initialized, initialize_failure := candidate_session_init(
		&session,
		Candidate_Config {
			session_id = 91,
			limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = context.temp_allocator,
		},
		source.definition,
		"pro",
	)
	testing.expectf(t, initialized, "session failed: %v", initialize_failure.code)
	if initialized {
		view, viewed, _ := candidate_session_view(&session)
		testing.expect(t, viewed)
		if viewed {
			testing.expect_value(t, len(view.rows), 2)
			for row in view.rows {
				descriptor, found := filesystem_candidate_action_entry(row.action, &batch)
				testing.expect(t, found)
				if found do testing.expect_value(t, row.label, descriptor.label)
			}
		}
		_, _, _ = candidate_session_close(&session)
	}
	filesystem_candidate_source_close(&source)
	testing.expect_value(t, tracking.current_memory_allocated, baseline)
}

/* Verifies filesystem metadata formatting is bounded and deterministic. */
@(test)
candidate_metadata_formats_file_details :: proc(t: ^testing.T) {
	permissions: [FILESYSTEM_PERMISSION_TEXT_BYTES]u8
	size: [FILESYSTEM_SIZE_TEXT_BYTES]u8
	recent_storage: [FILESYSTEM_MODIFIED_TEXT_BYTES]u8
	older_storage: [FILESYSTEM_MODIFIED_TEXT_BYTES]u8
	reference, reference_ok := time.components_to_time(2026, 8, 21, 12, 0, 0)
	recent, recent_ok := time.components_to_time(2026, 8, 20, 17, 0, 0)
	older, older_ok := time.components_to_time(2025, 11, 26, 9, 30, 0)
	testing.expect(t, reference_ok && recent_ok && older_ok)
	if !reference_ok || !recent_ok || !older_ok do return
	permission_text := filesystem_candidate_permission_text(
		.Directory,
		0o754,
		permissions[:],
	)
	size_text := filesystem_candidate_size_text(2_048, size[:])
	recent_text := filesystem_candidate_modified_text(
		time.to_unix_seconds(recent),
		time.to_unix_seconds(reference),
		recent_storage[:],
	)
	older_text := filesystem_candidate_modified_text(
		time.to_unix_seconds(older),
		time.to_unix_seconds(reference),
		older_storage[:],
	)
	testing.expect_value(t, permission_text, "drwxr-xr--")
	testing.expect_value(t, size_text, "2 KiB")
	testing.expect_value(t, recent_text, "19 hours ago")
	testing.expect_value(t, older_text, "2025 Nov 26")
}
