// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:fmt"
import "core:mem"
import "core:testing"

/* Verifies generated membership replacements preserve containment and exact logical accounting. */
@(test)
membership_sequences_preserve_invariants :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(301), generation = Owner_Generation(1)}
	initialized, _ := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}

	previous := Project_Handle{}
	for generation in 0 ..< 64 {
		paths: [8]string
		proposals: [8]Directory_Proposal
		for index in 0 ..< len(proposals) {
			paths[index] = fmt.aprintf("/generated-%02d/root-%02d", generation % 4, index)
			proposals[index] = Directory_Proposal{
				path = paths[index],
				trust = .Trusted if index % 2 == 0 else .Untrusted,
			}
		}
		prepared: Prepared_Snapshot
		prepared_ok, prepare_failure := registry_prepare_snapshot(
			&registry,
			Snapshot_Request{
				owner = owner,
				project_id = Project_ID(302),
				name = "Generated",
				directories = proposals[:],
				temporary = true,
			},
			&prepared,
		)
		testing.expectf(t, prepared_ok, "generation %d failed: %v", generation, prepare_failure.code)
		descriptor, published, publish_failure := prepared_snapshot_publish(&registry, &prepared)
		testing.expectf(t, published, "generation %d publish failed: %v", generation, publish_failure.code)
		if previous.id != Project_ID(0) {
			_, stale_ok, stale_failure := registry_project_descriptor(&registry, previous)
			testing.expect(t, !stale_ok)
			testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Project)
		}
		previous = descriptor.handle
		matches: [8]Membership_Handle
		count, classified, _ := registry_classify_path(
			&registry,
			descriptor.handle,
			fmt.tprintf("/generated-%02d/root-03/file", generation % 4),
			matches[:],
		)
		testing.expect(t, classified)
		testing.expect_value(t, count, u32(1))
		usage, usage_ok := registry_usage(&registry)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.projects, u32(1))
		testing.expect_value(t, usage.directories, u32(8))
		testing.expect_value(t, usage.trusted_directories, u32(4))
		testing.expect(t, usage.retained_path_bytes > 0)
		testing.expect(t, registry_validate(&registry))
		for path in paths {
			delete(path)
		}
	}
	registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies normalized collisions, descriptor limits, and aborted preparation leave no residue. */
@(test)
membership_failures_preserve_snapshot :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.descriptor_batch = MIN_DESCRIPTOR_BATCH
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(401), generation = Owner_Generation(1)}
	initialized, _ := registry_init(
		&registry,
		owner,
		policy,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	defer registry_close(&registry)

	collision := [?]Directory_Proposal{
		{path = "/collision/../same", trust = .Untrusted},
		{path = "/same", trust = .Trusted},
	}
	prepared: Prepared_Snapshot
	collision_ok, collision_failure := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(402), name = "Collision", directories = collision[:], temporary = true},
		&prepared,
	)
	testing.expect(t, !collision_ok)
	testing.expect_value(t, collision_failure.code, Failure_Code.Duplicate_Path)

	paths: [17]string
	proposals: [17]Directory_Proposal
	for index in 0 ..< len(proposals) {
		paths[index] = fmt.aprintf("/descriptor-%02d", index)
		proposals[index] = Directory_Proposal{path = paths[index], trust = .Untrusted}
	}
	prepared_ok, _ := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(402), name = "Descriptor", directories = proposals[:], temporary = true},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	descriptor, published, _ := prepared_snapshot_publish(&registry, &prepared)
	testing.expect(t, published)
	_, batch_ok, batch_failure := registry_membership_descriptors(&registry, descriptor.handle)
	testing.expect(t, !batch_ok)
	testing.expect_value(t, batch_failure.code, Failure_Code.Descriptor_Limit)

	replacement := [?]Directory_Proposal{{path = "/aborted", trust = .Trusted}}
	abort_ok, _ := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{owner = owner, project_id = Project_ID(402), name = "Aborted", directories = replacement[:], temporary = true},
		&prepared,
	)
	testing.expect(t, abort_ok)
	prepared_snapshot_abort(&prepared)
	current, current_ok, _ := registry_project_descriptor(&registry, descriptor.handle)
	testing.expect(t, current_ok)
	testing.expect_value(t, project_name_text(&current.name), "Descriptor")
	testing.expect_value(t, current.directory_count, u32(17))
	for path in paths {
		delete(path)
	}
}

/* Verifies the selected maximum membership count remains valid and fully copied. */
@(test)
maximum_membership_snapshot_is_bounded_and_full :: proc(t: ^testing.T) {
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(501), generation = Owner_Generation(1)}
	policy := DEFAULT_POLICY
	policy.directories = MAX_DIRECTORIES
	initialized, _ := registry_init(
		&registry,
		owner,
		policy,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	defer registry_close(&registry)

	paths: [MAX_DIRECTORIES]string
	proposals: [MAX_DIRECTORIES]Directory_Proposal
	for index in 0 ..< len(proposals) {
		paths[index] = fmt.aprintf("/maximum-%03d", index)
		proposals[index] = Directory_Proposal{path = paths[index], trust = .Untrusted}
	}
	prepared: Prepared_Snapshot
	prepared_ok, prepare_failure := registry_prepare_snapshot(
		&registry,
		Snapshot_Request{
			owner = owner,
			project_id = Project_ID(502),
			name = "Maximum",
			directories = proposals[:],
			temporary = true,
		},
		&prepared,
	)
	testing.expectf(t, prepared_ok, "maximum prepare failed: %v", prepare_failure.code)
	descriptor, published, publish_failure := prepared_snapshot_publish(&registry, &prepared)
	testing.expectf(t, published, "maximum publish failed: %v", publish_failure.code)
	testing.expect_value(t, descriptor.directory_count, MAX_DIRECTORIES)
	batch, copied, batch_failure := registry_membership_descriptors(&registry, descriptor.handle)
	testing.expectf(t, copied, "maximum descriptors failed: %v", batch_failure.code)
	if copied {
		testing.expect_value(t, len(batch.descriptors), int(MAX_DIRECTORIES))
		descriptor_batch_close(&batch)
	}
	testing.expect(t, registry_validate(&registry))
	for path in paths {
		delete(path)
	}
}
