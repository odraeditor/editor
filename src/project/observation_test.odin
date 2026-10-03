// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:mem"
import "core:os"
import "core:testing"

/* Verifies bounded reconciliation, unavailable retention, coalescing, and cancellation. */
@(test)
observations_publish_complete_generations :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-project-observation-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil {
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}
	missing, missing_error := os.join_path({root, "missing"}, context.allocator)
	testing.expect(t, missing_error == nil)
	if missing_error != nil {
		return
	}
	defer delete(missing)
	config_dir, config_error := os.join_path({root, ".odra"}, context.allocator)
	config_path, path_error := os.join_path({root, ".odra", "config.rkt"}, context.allocator)
	testing.expect(t, config_error == nil && path_error == nil)
	if config_error != nil || path_error != nil {
		return
	}
	defer {
		delete(config_path)
		delete(config_dir)
	}
	testing.expect(t, os.make_directory(config_dir) == nil)
	testing.expect(t, os.write_entire_file(config_path, "#lang odra/config\n(project-config)\n") == nil)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	owner := Owner_Handle{id = 301, generation = 1}
	project_registry: Registry
	initialized, _ := registry_init(
		&project_registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	proposals := [?]Directory_Proposal{
		{path = root, trust = .Trusted},
		{path = missing, trust = .Untrusted},
	}
	prepared: Prepared_Snapshot
	prepared_ok, _ := registry_prepare_snapshot(
		&project_registry,
		Snapshot_Request{owner = owner, project_id = 302, name = "Observed", directories = proposals[:], temporary = true},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	project_descriptor, published, _ := prepared_snapshot_publish(&project_registry, &prepared)
	testing.expect(t, published)
	memberships, copied, _ := registry_membership_descriptors(&project_registry, project_descriptor.handle)
	testing.expect(t, copied)

	observations: Observation_Registry
	observed, observe_failure := observation_registry_init(
		&observations,
		project_descriptor.handle,
		memberships.descriptors,
		DEFAULT_POLICY,
		Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, observed, "observation init failed: %v", observe_failure.code)
	if observed {
		result, reconciled, reconcile_failure := observation_reconcile(&observations, project_descriptor.handle)
		testing.expectf(t, reconciled, "reconcile failed: %v", reconcile_failure.code)
		testing.expect(t, result.published)
		testing.expect_value(t, result.unavailable_directories, u32(1))
		batch, generation, listed, _ := observation_descriptors(&observations, project_descriptor.handle)
		testing.expect(t, listed)
		if listed {
			testing.expect_value(t, batch.descriptors[0].availability, Availability.Available)
			testing.expect(t, batch.descriptors[0].config_present)
			testing.expect_value(t, batch.descriptors[1].availability, Availability.Unavailable)
			observation_batch_close(&batch)
		}
		marked, _ := observation_mark_hint(
			&observations,
			project_descriptor.handle,
			memberships.descriptors[0].handle,
			.Overflow,
		)
		testing.expect(t, marked)
		stale_membership := memberships.descriptors[0].handle
		stale_membership.generation += 1
		_, stale_failure := observation_mark_hint(
			&observations,
			project_descriptor.handle,
			stale_membership,
			.Activity,
		)
		testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Membership)
		marked, _ = observation_mark_hint(
			&observations,
			project_descriptor.handle,
			memberships.descriptors[0].handle,
			.Activity,
		)
		testing.expect(t, marked)
		cancelled, cancelled_ok, _ := observation_reconcile(&observations, project_descriptor.handle, true)
		testing.expect(t, cancelled_ok && cancelled.cancelled)
		testing.expect_value(t, cancelled.generation, generation)
		refreshed, _ := observation_request_refresh(&observations, project_descriptor.handle)
		testing.expect(t, refreshed)
		result, reconciled, _ = observation_reconcile(&observations, project_descriptor.handle)
		testing.expect(t, reconciled && result.published && result.generation > generation)
		observation_registry_close(&observations)
	}
	descriptor_batch_close(&memberships)
	registry_close(&project_registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies dirty-marker limits reject initialization before retaining state. */
@(test)
initialization_rejects_excess_dirty_markers :: proc(t: ^testing.T) {
	policy := DEFAULT_POLICY
	policy.dirty_markers = MIN_DIRTY_MARKERS
	project := Project_Handle {
		owner = Owner_Handle{id = 401, generation = 1},
		id = 402,
		generation = 1,
	}
	descriptors: [int(MIN_DIRTY_MARKERS) + 1]Membership_Descriptor
	registry: Observation_Registry
	initialized, failure := observation_registry_init(
		&registry,
		project,
		descriptors[:],
		policy,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Failure_Code.Dirty_Marker_Limit)
	testing.expect(t, registry.state == nil)
}
