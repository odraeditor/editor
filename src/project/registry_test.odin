// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:mem"
import "core:testing"

/* Verifies complete membership publication, overlap classification, and copied descriptors. */
@(test)
publishes_overlapping_membership_snapshot :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(11), generation = Owner_Generation(13)}
	initialized, failure := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, initialized, "init failed: %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	proposals := [?]Directory_Proposal{
		{path = "/work", trust = .Untrusted},
		{path = "/work/odra", trust = .Trusted},
	}
	prepared: Prepared_Snapshot
	prepared_ok, prepare_failure := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{
			owner = owner,
			project_id = Project_ID(17),
			name = "Odra",
			directories = proposals[:],
			temporary = true,
		},
		&prepared,
	)
	testing.expectf(t, prepared_ok, "prepare failed: %v", prepare_failure.code)
	descriptor, published, publish_failure := prepared_snapshot_publish(&registry, &prepared)
	testing.expectf(t, published, "publish failed: %v", publish_failure.code)
	testing.expect_value(t, project_name_text(&descriptor.name), "Odra")
	testing.expect_value(t, descriptor.directory_count, u32(2))
	testing.expect_value(t, descriptor.trusted_directories, u32(1))

	matches: [2]Membership_Handle
	count, classified, classify_failure := registry_classify_path(
		&registry,
		descriptor.handle,
		"/work/odra/src/main.odin",
		matches[:],
	)
	testing.expectf(t, classified, "classify failed: %v", classify_failure.code)
	testing.expect_value(t, count, u32(2))

	batch, copied, batch_failure := registry_membership_descriptors(&registry, descriptor.handle)
	testing.expectf(t, copied, "descriptor copy failed: %v", batch_failure.code)
	if copied {
		testing.expect_value(t, len(batch.descriptors), 2)
		testing.expect_value(t, directory_path_text(&batch.descriptors[1].path), "/work/odra")
		descriptor_batch_close(&batch)
	}
	testing.expect(t, registry_validate(&registry))
	registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies failed preparation and stale handles preserve the published Project. */
@(test)
rejects_invalid_project_updates_atomically :: proc(t: ^testing.T) {
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(21), generation = Owner_Generation(22)}
	initialized, _ := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	defer registry_close(&registry)

	initial := [?]Directory_Proposal{{path = "/one", trust = .Untrusted}}
	prepared: Prepared_Snapshot
	prepared_ok, _ := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(23), name = "One", directories = initial[:], temporary = true},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	first, published, _ := prepared_snapshot_publish(&registry, &prepared)
	testing.expect(t, published)

	duplicate := [?]Directory_Proposal{
		{path = "/one", trust = .Untrusted},
		{path = "/one", trust = .Trusted},
	}
	duplicate_ok, duplicate_failure := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(23), name = "One", directories = duplicate[:], temporary = true},
		&prepared,
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Path)

	replacement := [?]Directory_Proposal{{path = "/two", trust = .Trusted}}
	replacement_ok, _ := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(23), name = "One", directories = replacement[:], temporary = true},
		&prepared,
	)
	testing.expect(t, replacement_ok)
	second, replaced, _ := prepared_snapshot_publish(&registry, &prepared)
	testing.expect(t, replaced)
	testing.expect(t, second.handle.generation > first.handle.generation)

	_, stale_ok, stale_failure := registry_project_descriptor(&registry, first.handle)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Project)
	current, current_ok, _ := registry_project_descriptor(&registry, second.handle)
	testing.expect(t, current_ok)
	testing.expect_value(t, current.directory_count, u32(1))
}
