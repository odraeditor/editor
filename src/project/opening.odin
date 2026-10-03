// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project

import "../document"
import "base:runtime"

/* directory_open_prepare validates one catalog result without publishing it. */
directory_open_prepare :: proc(
	registry: ^Registry,
	request: Directory_Open_Request,
	prepared: ^Directory_Open_Preparation,
) -> (ok: bool, failure: Failure_Context) {
	assert(prepared != nil)
	prepared^ = {}
	state, resolved := resolve_registry(registry, request.owner, .Prepare_Directory_Open)
	if resolved.code != .None {
		return false, resolved
	}
	if state.project != request.expected {
		return false, project_failure(state, .Prepare_Directory_Open, .Project_Switch_Unavailable)
	}
	if request.expected_catalog_generation == 0 {
		return false, project_failure(state, .Prepare_Directory_Open, .Stale_Catalog)
	}
	if request.matching_projects > state.policy.catalog_projects {
		failure = project_failure(state, .Prepare_Directory_Open, .Descriptor_Limit)
		failure.maximum = u64(state.policy.catalog_projects)
		failure.actual = u64(request.matching_projects)
		return false, failure
	}
	if !normalized_directory_is_exact(request.normalized_path, state.allocators.temporary) {
		return false, project_failure(state, .Prepare_Directory_Open, .Invalid_Path)
	}

	if request.matching_projects > 1 {
		if request.snapshot.project_id != Project_ID(0) ||
		   request.snapshot.project_generation != Project_Generation(0) ||
		   len(request.snapshot.name) != 0 || len(request.snapshot.directories) != 0 {
			return false, project_failure(state, .Prepare_Directory_Open, .Invalid_Resolution)
		}
		prepared^ = Directory_Open_Preparation {
			owner = request.owner,
			expected = request.expected,
			expected_catalog_generation = request.expected_catalog_generation,
			matching_projects = request.matching_projects,
			resolution = .Ambiguous,
		}
		return true, {}
	}

	registered := request.matching_projects == 1
	if request.snapshot.owner != request.owner || request.snapshot.project_id == Project_ID(0) ||
	   len(request.snapshot.directories) != 1 ||
	   request.snapshot.temporary == registered ||
	   (registered && request.snapshot.project_generation == Project_Generation(0)) ||
	   (!registered && request.snapshot.project_generation != Project_Generation(0)) ||
	   (!registered && request.snapshot.directories[0].trust != .Untrusted) {
		return false, project_failure(state, .Prepare_Directory_Open, .Invalid_Resolution)
	}
	if !normalized_directory_matches(
		request.snapshot.directories[0].path,
		request.normalized_path,
		state.allocators.temporary,
	) {
		return false, project_failure(state, .Prepare_Directory_Open, .Invalid_Resolution)
	}

	snapshot: Prepared_Snapshot
	snapshot_ok: bool
	snapshot_failure: Failure_Context
	if project_handle_is_valid(request.expected) {
		snapshot_ok, snapshot_failure = registry_prepare_replacement_snapshot(
			registry,
			request.expected,
			request.snapshot,
			&snapshot,
		)
	} else {
		snapshot_ok, snapshot_failure = registry_prepare_snapshot(
			registry,
			request.snapshot,
			&snapshot,
		)
	}
	if !snapshot_ok {
		snapshot_failure.operation = .Prepare_Directory_Open
		return false, snapshot_failure
	}
	prepared^ = Directory_Open_Preparation {
		snapshot = snapshot,
		owner = request.owner,
		expected = request.expected,
		expected_catalog_generation = request.expected_catalog_generation,
		matching_projects = request.matching_projects,
		resolution = .Registered if registered else .Unregistered,
	}
	return true, {}
}

/* directory_open_publish checks catalog freshness and atomically activates a prepared Project. */
directory_open_publish :: proc(
	registry: ^Registry,
	prepared: ^Directory_Open_Preparation,
	actual_catalog_generation: u64,
) -> (descriptor: Project_Descriptor, ok: bool, failure: Failure_Context) {
	if prepared == nil || prepared.resolution == .Invalid {
		return {}, false, Failure_Context{code = .Invalid_Resolution, operation = .Publish_Directory_Open}
	}
	state, resolved := resolve_registry(registry, prepared.owner, .Publish_Directory_Open)
	if resolved.code != .None {
		return {}, false, resolved
	}
	if state.project != prepared.expected {
		return {}, false, project_failure(state, .Publish_Directory_Open, .Project_Switch_Unavailable)
	}
	if actual_catalog_generation == 0 ||
	   actual_catalog_generation != prepared.expected_catalog_generation {
		failure = project_failure(state, .Publish_Directory_Open, .Stale_Catalog)
		failure.minimum = prepared.expected_catalog_generation
		failure.actual = actual_catalog_generation
		return {}, false, failure
	}
	if prepared.resolution == .Ambiguous || prepared.snapshot.state == nil {
		return {}, false, project_failure(state, .Publish_Directory_Open, .Invalid_Resolution)
	}
	published: bool
	publish_failure: Failure_Context
	descriptor, published, publish_failure = prepared_snapshot_publish(registry, &prepared.snapshot)
	if !published {
		publish_failure.operation = .Publish_Directory_Open
		return {}, false, publish_failure
	}
	prepared^ = {}
	return descriptor, true, {}
}

/* directory_open_abort releases one unpublished activation and clears ambiguity state. */
directory_open_abort :: proc(prepared: ^Directory_Open_Preparation) {
	if prepared == nil {
		return
	}
	prepared_snapshot_abort(&prepared.snapshot)
	prepared^ = {}
}

@(private)
normalized_directory_is_exact :: proc(path: string, allocator: runtime.Allocator) -> bool {
	normalized: document.Normalized_Path
	ok, _ := document.path_normalize(path, &normalized, allocator)
	return ok && document.normalized_path_text(&normalized) == path
}

@(private)
normalized_directory_matches :: proc(
	path, expected: string,
	allocator: runtime.Allocator,
) -> bool {
	normalized: document.Normalized_Path
	ok, _ := document.path_normalize(path, &normalized, allocator)
	return ok && document.normalized_path_text(&normalized) == expected
}
