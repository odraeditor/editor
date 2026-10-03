// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../document"
import "../editor_session"
import "../hosting"
import "../project"
import "base:runtime"
import endian "core:encoding/endian"
import "core:os"
import "core:unicode/utf8"

/* PROJECT_DIRECTORY_RESOLUTION_SCHEMA identifies the copied opening batch layout. */
PROJECT_DIRECTORY_RESOLUTION_SCHEMA :: u64(1)
/* PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES is the fixed opening batch prefix. */
PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES :: u64(32)
/* PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES is one fixed exact-match record. */
PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES :: u64(88)

/* Project_Directory_Candidate is one copied registered exact-path choice. */
Project_Directory_Candidate :: struct {
	project_id:            project.Project_ID,
	project_generation:    project.Project_Generation,
	durable_id:            string,
	name:                  string,
	membership_id:         string,
	path:                  string,
	trust:                 project.Trust_State,
}

/* Project_Directory_Candidate_Batch owns copied ambiguity choices until close. */
Project_Directory_Candidate_Batch :: struct {
	state:              rawptr,
	catalog_generation: u64,
	candidates:         []Project_Directory_Candidate,
}

/* Project_Directory_Open_Completion classifies one directory-opening outcome. */
Project_Directory_Open_Completion :: enum u8 {
	Invalid,
	Already_Active,
	Dir,
	Unregistered,
	Registered,
	Ambiguous,
}

/* Project_Directory_Open_Result reports activation or retained explicit choices. */
Project_Directory_Open_Result :: struct {
	completion: Project_Directory_Open_Completion,
	activation: editor_session.Project_Directory_Open_Result,
	roots:      editor_session.Root_Replace_Result,
	candidates: Project_Directory_Candidate_Batch,
}

@(private)
Project_Directory_Candidate_Batch_State :: struct {
	storage:    []byte,
	candidates: []Project_Directory_Candidate,
	allocator:  runtime.Allocator,
}

/* project_open_directory publishes one ordinary Dir or its exact valid local Project. */
project_open_directory :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	projects_directory, path: string,
	next_project_id: project.Project_ID,
) -> (result: Project_Directory_Open_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(projects_directory) == 0 || len(path) == 0 || !os.is_directory(path) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	normalized: document.Normalized_Path
	normalized_ok, _ := document.path_normalize(path, &normalized, ctx.temporary_allocator)
	if !normalized_ok {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	normalized_path := document.normalized_path_text(&normalized)
	roots, roots_ok, roots_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !roots_ok {
		return {}, false, buffer_session_failure(ctx.command, roots_failure)
	}
	defer editor_session.root_batch_close(&roots)
	for root in roots.descriptors {
		if root.path == normalized_path {
			return Project_Directory_Open_Result {
				completion = .Already_Active,
				roots = {
					generation = roots.generation,
					root_count = u32(len(roots.descriptors)),
				},
			}, true, {}
		}
	}
	active_snapshot, inspected, inspect_failure := editor_session.session_active_project(ctx.session, ctx.handle)
	if !inspected {
		return {}, false, buffer_session_failure(ctx.command, inspect_failure)
	}
	expected: project.Project_Handle
	if active_snapshot.active {
		expected = active_snapshot.descriptor.handle
	}
	batch, resolved, resolve_failure := project_directory_candidates_resolve(
		racket_runtime,
		projects_directory,
		normalized_path,
		ctx.persistent_allocator,
	)
	if !resolved {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			resolve_failure,
		)
	}
	if len(batch.candidates) > 1 {
		project_directory_candidate_batch_close(&batch)
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	if len(batch.candidates) == 0 {
		project_directory_candidate_batch_close(&batch)
		published, published_ok, publish_failure := editor_session.session_roots_replace(
			ctx.session,
			editor_session.Root_Replace_Request {
				session = ctx.handle,
				roots = []editor_session.Root_Proposal{{kind = .Dir, path = normalized_path}},
			},
		)
		if !published_ok {
			return {}, false, buffer_session_failure(ctx.command, publish_failure)
		}
		_ = next_project_id
		return Project_Directory_Open_Result{completion = .Dir, roots = published}, true, {}
	}
	candidate := batch.candidates[0]
	actual_generation, current, refresh_failure := project_directory_resolution_generation(
		racket_runtime,
		projects_directory,
		normalized_path,
		ctx.temporary_allocator,
	)
	if !current {
		project_directory_candidate_batch_close(&batch)
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			refresh_failure,
		)
	}
	activation, activated, activation_failure := editor_session.session_open_project_directory(
		ctx.session,
		editor_session.Project_Directory_Open_Request {
			session = ctx.handle,
			expected = expected,
			expected_catalog_generation = batch.catalog_generation,
			actual_catalog_generation = actual_generation,
			normalized_path = normalized_path,
			matching_projects = u32(len(batch.candidates)),
			project_id = candidate.project_id,
			project_generation = candidate.project_generation,
			durable_id = candidate.durable_id,
			name = candidate.name,
			trust = candidate.trust,
			temporary = false,
		},
	)
	project_directory_candidate_batch_close(&batch)
	if !activated {
		return {}, false, buffer_session_failure(ctx.command, activation_failure)
	}
	published, published_ok, publish_failure := editor_session.session_roots_replace(
		ctx.session,
		editor_session.Root_Replace_Request {
			session = ctx.handle,
			roots = []editor_session.Root_Proposal {
				{kind = .Project, path = normalized_path, project = activation.active.handle},
			},
		},
	)
	if !published_ok {
		return {}, false, buffer_session_failure(ctx.command, publish_failure)
	}
	return Project_Directory_Open_Result {
		completion = .Registered,
		activation = activation,
		roots = published,
	}, true, {}
}

/* project_open_directory_candidate publishes one explicitly selected ambiguous match. */
project_open_directory_candidate :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	projects_directory: string,
	batch: ^Project_Directory_Candidate_Batch,
	index: int,
) -> (result: editor_session.Project_Directory_Open_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(projects_directory) == 0 || batch == nil || batch.state == nil ||
	   batch.catalog_generation == 0 || index < 0 || index >= len(batch.candidates) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	candidate := batch.candidates[index]
	active_snapshot, inspected, inspect_failure := editor_session.session_active_project(ctx.session, ctx.handle)
	if !inspected {
		return {}, false, buffer_session_failure(ctx.command, inspect_failure)
	}
	expected: project.Project_Handle
	if active_snapshot.active {
		expected = active_snapshot.descriptor.handle
	}
	actual_generation, current, refresh_failure := project_directory_resolution_generation(
		racket_runtime,
		projects_directory,
		candidate.path,
		ctx.temporary_allocator,
	)
	if !current {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			refresh_failure,
		)
	}
	opened, opened_ok, session_failure := editor_session.session_open_project_directory(
		ctx.session,
		editor_session.Project_Directory_Open_Request {
			session = ctx.handle,
			expected = expected,
			expected_catalog_generation = batch.catalog_generation,
			actual_catalog_generation = actual_generation,
			normalized_path = candidate.path,
			matching_projects = 1,
			project_id = candidate.project_id,
			project_generation = candidate.project_generation,
			durable_id = candidate.durable_id,
			name = candidate.name,
			trust = candidate.trust,
			temporary = false,
		},
	)
	if !opened_ok {
		return {}, false, buffer_session_failure(ctx.command, session_failure)
	}
	return opened, true, {}
}

/* project_directory_candidate_batch_close releases copied ambiguous choices. */
project_directory_candidate_batch_close :: proc(batch: ^Project_Directory_Candidate_Batch) {
	if batch == nil || batch.state == nil {
		if batch != nil {
			batch^ = {}
		}
		return
	}
	state := cast(^Project_Directory_Candidate_Batch_State)batch.state
	allocator := state.allocator
	delete(state.candidates, allocator)
	delete(state.storage, allocator)
	free(state, allocator)
	batch^ = {}
}

@(private)
project_directory_candidates_resolve :: proc(
	racket_runtime: ^hosting.Runtime,
	projects_directory, normalized_path: string,
	allocator: runtime.Allocator,
) -> (batch: Project_Directory_Candidate_Batch, ok: bool, failure: hosting.Failure_Context) {
	return project_candidates_resolve(
		racket_runtime,
		projects_directory,
		normalized_path,
		false,
		allocator,
	)
}

/* project_catalog_candidates_resolve returns valid globally discoverable Projects. */
project_catalog_candidates_resolve :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
	allocator: runtime.Allocator,
) -> (batch: Project_Directory_Candidate_Batch, ok: bool, failure: hosting.Failure_Context) {
	return project_candidates_resolve(
		racket_runtime,
		configuration_root,
		"",
		true,
		allocator,
	)
}

@(private)
project_candidates_resolve :: proc(
	racket_runtime: ^hosting.Runtime,
	owner_root, normalized_path: string,
	catalog: bool,
	allocator: runtime.Allocator,
) -> (batch: Project_Directory_Candidate_Batch, ok: bool, failure: hosting.Failure_Context) {
	if allocator.procedure == nil {
		return {}, false, hosting.Failure_Context{code = .Runtime_Unavailable}
	}
	state, state_error := new(Project_Directory_Candidate_Batch_State, allocator)
	if state_error != nil {
		return {}, false, hosting.Failure_Context{code = .Runtime_Unavailable}
	}
	state.allocator = allocator
	state.storage, state_error = make(
		[]byte,
		hosting.MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES,
		allocator,
	)
	if state_error != nil {
		free(state, allocator)
		return {}, false, hosting.Failure_Context{code = .Runtime_Unavailable}
	}
	output_length: u64
	transferred: bool
	transfer_failure: hosting.Failure_Context
	if catalog {
		output_length, transferred, transfer_failure = hosting.runtime_project_catalog_resolution(
			racket_runtime,
			owner_root,
			state.storage,
		)
	} else {
		output_length, transferred, transfer_failure = hosting.runtime_project_directory_resolution(
			racket_runtime,
			owner_root,
			normalized_path,
			state.storage,
		)
	}
	if !transferred {
		delete(state.storage, allocator)
		free(state, allocator)
		return {}, false, transfer_failure
	}
	state.storage = state.storage[:int(output_length)]
	generation, count, parsed := project_directory_resolution_header(state.storage)
	if !parsed || count > u64(project.DEFAULT_CATALOG_PROJECTS) {
		delete(state.storage, allocator)
		free(state, allocator)
		return {}, false, hosting.Failure_Context{code = .Wrong_Result}
	}
	state.candidates, state_error = make([]Project_Directory_Candidate, int(count), allocator)
	if state_error != nil {
		delete(state.storage, allocator)
		free(state, allocator)
		return {}, false, hosting.Failure_Context{code = .Runtime_Unavailable}
	}
	text_start := PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES + count *
	              PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES
	text := state.storage[int(text_start):]
	for index := 0; index < int(count); index += 1 {
		base := int(PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES) +
		        index * int(PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES)
		record := state.storage[base:base + int(PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES)]
		project_id, id_ok := project_directory_resolution_word(record, 0)
		project_generation, generation_ok := project_directory_resolution_word(record, 8)
		trust_value, trust_ok := project_directory_resolution_word(record, 16)
		durable_id, durable_ok := project_directory_resolution_text(record, 24, text)
		name, name_ok := project_directory_resolution_text(record, 40, text)
		membership_id, membership_ok := project_directory_resolution_text(record, 56, text)
		path, path_ok := project_directory_resolution_text(record, 72, text)
		if !id_ok || !generation_ok || !trust_ok || !durable_ok || !name_ok ||
		   !membership_ok || !path_ok || project_id == 0 || project_generation == 0 ||
		   len(durable_id) == 0 || len(name) == 0 || len(membership_id) == 0 ||
		   (!catalog && path != normalized_path) || (trust_value != 1 && trust_value != 2) {
			project_directory_candidate_batch_state_destroy(state)
			return {}, false, hosting.Failure_Context{code = .Wrong_Result}
		}
		if catalog {
			canonical: document.Normalized_Path
			canonical_ok, _ := document.path_normalize(path, &canonical, allocator)
			if !canonical_ok || document.normalized_path_text(&canonical) != path {
				project_directory_candidate_batch_state_destroy(state)
				return {}, false, hosting.Failure_Context{code = .Wrong_Result}
			}
		}
		state.candidates[index] = Project_Directory_Candidate {
			project_id = project.Project_ID(project_id),
			project_generation = project.Project_Generation(project_generation),
			durable_id = durable_id,
			name = name,
			membership_id = membership_id,
			path = path,
			trust = .Trusted if trust_value == 2 else .Untrusted,
		}
	}
	return Project_Directory_Candidate_Batch {
		state = state,
		catalog_generation = generation,
		candidates = state.candidates,
	}, true, {}
}

@(private)
project_directory_resolution_generation :: proc(
	racket_runtime: ^hosting.Runtime,
	projects_directory, normalized_path: string,
	allocator: runtime.Allocator,
) -> (generation: u64, ok: bool, failure: hosting.Failure_Context) {
	storage, storage_error := make(
		[]byte,
		hosting.MAX_PROJECT_DIRECTORY_RESOLUTION_BYTES,
		allocator,
	)
	if storage_error != nil {
		return 0, false, hosting.Failure_Context{code = .Runtime_Unavailable}
	}
	defer delete(storage, allocator)
	output_length, transferred, transfer_failure := hosting.runtime_project_directory_resolution(
		racket_runtime,
		projects_directory,
		normalized_path,
		storage,
	)
	if !transferred {
		return 0, false, transfer_failure
	}
	resolved_generation, _, parsed := project_directory_resolution_header(storage[:int(output_length)])
	if !parsed {
		return 0, false, hosting.Failure_Context{code = .Wrong_Result}
	}
	return resolved_generation, true, {}
}

@(private)
project_directory_resolution_header :: proc(bytes: []byte) -> (generation, count: u64, ok: bool) {
	if len(bytes) < int(PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES) {
		return 0, 0, false
	}
	schema, schema_ok := project_directory_resolution_word(bytes, 0)
	generation_value, generation_ok := project_directory_resolution_word(bytes, 8)
	count_value, count_ok := project_directory_resolution_word(bytes, 16)
	text_bytes, text_ok := project_directory_resolution_word(bytes, 24)
	required := PROJECT_DIRECTORY_RESOLUTION_HEADER_BYTES +
	            count_value * PROJECT_DIRECTORY_RESOLUTION_RECORD_BYTES + text_bytes
	return generation_value, count_value,
	       schema_ok && generation_ok && count_ok && text_ok &&
	       schema == PROJECT_DIRECTORY_RESOLUTION_SCHEMA && generation_value != 0 &&
	       required == u64(len(bytes))
}

@(private)
project_directory_resolution_text :: proc(
	record: []byte,
	offset: int,
	text: []byte,
) -> (value: string, ok: bool) {
	start, start_ok := project_directory_resolution_word(record, offset)
	length, length_ok := project_directory_resolution_word(record, offset + 8)
	if !start_ok || !length_ok || length == 0 || start > u64(len(text)) ||
	   length > u64(len(text)) - start {
		return "", false
	}
	value = string(text[int(start):int(start + length)])
	return value, utf8.valid_string(value)
}

@(private)
project_directory_resolution_word :: proc(bytes: []byte, offset: int) -> (u64, bool) {
	if offset < 0 || offset + 8 > len(bytes) {
		return 0, false
	}
	return endian.get_u64(bytes[offset:], .Little)
}

@(private)
project_directory_candidate_batch_state_destroy :: proc(state: ^Project_Directory_Candidate_Batch_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.candidates != nil {
		delete(state.candidates, allocator)
	}
	if state.storage != nil {
		delete(state.storage, allocator)
	}
	free(state, allocator)
}
