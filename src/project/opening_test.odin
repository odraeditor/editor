// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "core:mem"
import "core:testing"

/* Verifies fresh unmatched and registered results publish exact native snapshots. */
@(test)
directory_open_publishes_fresh_unregistered :: proc(t: ^testing.T) {
	registration_states := [?]bool{false, true}
	for registered in registration_states {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		registry: Registry
		owner := Owner_Handle {
			id = Owner_ID(801 if registered else 800),
			generation = Owner_Generation(1),
		}
		initialized, _ := registry_init(
			&registry,
			owner,
			DEFAULT_POLICY,
			Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		trust := Trust_State.Untrusted
		generation := Project_Generation(0)
		if registered {
			trust = .Trusted
			generation = Project_Generation(17)
		}
		directories := [?]Directory_Proposal{{path = "/work/Zażółć/odra", trust = trust}}
		prepared: Directory_Open_Preparation
		prepared_ok, prepare_failure := directory_open_prepare(
			&registry,
			Directory_Open_Request {
				owner = owner,
				expected_catalog_generation = 9,
				normalized_path = "/work/Zażółć/odra",
				matching_projects = 1 if registered else 0,
				snapshot = {
					owner = owner,
					project_id = Project_ID(901 if registered else 900),
					project_generation = generation,
					durable_id = "odra" if registered else "",
					name = "Odra",
					directories = directories[:],
					temporary = !registered,
				},
			},
			&prepared,
		)
		testing.expectf(t, prepared_ok, "prepare failed: %v", prepare_failure.code)
		usage, usage_ok := registry_usage(&registry)
		testing.expect(t, usage_ok)
		testing.expect_value(t, usage.projects, u32(0))
		descriptor, published, publish_failure := directory_open_publish(&registry, &prepared, 9)
		testing.expectf(t, published, "publish failed: %v", publish_failure.code)
		testing.expect_value(t, descriptor.temporary, !registered)
		testing.expect_value(t, descriptor.handle.generation, Project_Generation(17) if registered else Project_Generation(1))
		testing.expect_value(t, descriptor.trusted_directories, u32(1) if registered else u32(0))
		batch, copied, _ := registry_membership_descriptors(&registry, descriptor.handle)
		testing.expect(t, copied)
		if copied {
			testing.expect_value(t, len(batch.descriptors), 1)
			testing.expect_value(
				t,
				directory_path_text(&batch.descriptors[0].path),
				"/work/Zażółć/odra",
			)
			descriptor_batch_close(&batch)
		}
		registry_close(&registry)
		testing.expect_value(t, tracking.current_memory_allocated, 0)
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies ambiguity, stale catalogs, and active Projects preserve prior state. */
@(test)
directory_open_rejections_preserve_registry :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(810), generation = Owner_Generation(1)}
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
	baseline_bytes := tracking.current_memory_allocated

	ambiguous: Directory_Open_Preparation
	ambiguous_ok, _ := directory_open_prepare(
		&registry,
		Directory_Open_Request {
			owner = owner,
			expected_catalog_generation = 3,
			normalized_path = "/work/odra",
			matching_projects = 2,
		},
		&ambiguous,
	)
	testing.expect(t, ambiguous_ok)
	testing.expect_value(t, ambiguous.resolution, Directory_Open_Resolution.Ambiguous)
	_, ambiguity_published, ambiguity_failure := directory_open_publish(&registry, &ambiguous, 3)
	testing.expect(t, !ambiguity_published)
	testing.expect_value(t, ambiguity_failure.code, Failure_Code.Invalid_Resolution)
	directory_open_abort(&ambiguous)
	testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)

	directories := [?]Directory_Proposal{{path = "/work/odra", trust = .Untrusted}}
	request := Directory_Open_Request {
		owner = owner,
		expected_catalog_generation = 4,
		normalized_path = "/work/odra",
		snapshot = {
			owner = owner,
			project_id = Project_ID(811),
			name = "Odra",
			directories = directories[:],
			temporary = true,
		},
	}
	prepared: Directory_Open_Preparation
	prepared_ok, _ := directory_open_prepare(&registry, request, &prepared)
	testing.expect(t, prepared_ok)
	_, stale_published, stale_failure := directory_open_publish(&registry, &prepared, 5)
	testing.expect(t, !stale_published)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Catalog)
	usage, usage_ok := registry_usage(&registry)
	testing.expect(t, usage_ok)
	testing.expect_value(t, usage.projects, u32(0))
	directory_open_abort(&prepared)
	testing.expect_value(t, tracking.current_memory_allocated, baseline_bytes)

	prepared_ok, _ = directory_open_prepare(&registry, request, &prepared)
	testing.expect(t, prepared_ok)
	first, published, _ := directory_open_publish(&registry, &prepared, 4)
	testing.expect(t, published)
	second: Directory_Open_Preparation
	_, second_ok_failure := directory_open_prepare(&registry, request, &second)
	testing.expect_value(t, second_ok_failure.code, Failure_Code.Project_Switch_Unavailable)
	testing.expect_value(t, second.resolution, Directory_Open_Resolution.Invalid)

	replacement_directories := [?]Directory_Proposal{{path = "/work/other", trust = .Untrusted}}
	replacement: Directory_Open_Preparation
	replacement_ok, replacement_failure := directory_open_prepare(
		&registry,
		Directory_Open_Request {
			owner = owner,
			expected = first.handle,
			expected_catalog_generation = 6,
			normalized_path = "/work/other",
			snapshot = {
				owner = owner,
				project_id = Project_ID(812),
				name = "Other",
				directories = replacement_directories[:],
				temporary = true,
			},
		},
		&replacement,
	)
	testing.expectf(t, replacement_ok, "replacement prepare failed: %v", replacement_failure.code)
	replaced, replacement_published, replacement_publish_failure := directory_open_publish(
		&registry,
		&replacement,
		6,
	)
	testing.expectf(
		t,
		replacement_published,
		"replacement publish failed: %v",
		replacement_publish_failure.code,
	)
	if replacement_published {
		testing.expect(t, replaced.handle != first.handle)
		testing.expect_value(t, replaced.handle.generation, Project_Generation(1))
	}

	registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies mismatched cardinality, paths, and bounds never prepare publication. */
@(test)
dir_open_rejects_incoherent_catalog_results :: proc(t: ^testing.T) {
	registry: Registry
	owner := Owner_Handle{id = Owner_ID(820), generation = Owner_Generation(1)}
	initialized, _ := registry_init(
		&registry,
		owner,
		DEFAULT_POLICY,
		Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	defer registry_close(&registry)

	multi := [?]Directory_Proposal {
		{path = "/work/odra", trust = .Untrusted},
		{path = "/work/shared", trust = .Untrusted},
	}
	request := Directory_Open_Request {
		owner = owner,
		expected_catalog_generation = 2,
		normalized_path = "/work/odra",
		matching_projects = 1,
		snapshot = {
			owner = owner,
			project_id = Project_ID(821),
			project_generation = Project_Generation(2),
			name = "Multi",
			directories = multi[:],
		},
	}
	prepared: Directory_Open_Preparation
	_, multi_failure := directory_open_prepare(&registry, request, &prepared)
	testing.expect_value(t, multi_failure.code, Failure_Code.Invalid_Resolution)

	request.snapshot.directories = multi[:1]
	request.snapshot.directories[0].path = "/work/other"
	_, path_failure := directory_open_prepare(&registry, request, &prepared)
	testing.expect_value(t, path_failure.code, Failure_Code.Invalid_Resolution)

	request.normalized_path = "/work/other/../odra"
	_, normalization_failure := directory_open_prepare(&registry, request, &prepared)
	testing.expect_value(t, normalization_failure.code, Failure_Code.Invalid_Path)

	request.normalized_path = "/work/odra"
	request.matching_projects = DEFAULT_POLICY.catalog_projects + 1
	request.snapshot = {}
	_, limit_failure := directory_open_prepare(&registry, request, &prepared)
	testing.expect_value(t, limit_failure.code, Failure_Code.Descriptor_Limit)
}
