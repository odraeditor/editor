// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../editor_session"
import "../hosting"
import "../project"
import endian "core:encoding/endian"

/* PROJECT_PROMOTION_SCHEMA identifies one copied durable promotion result. */
PROJECT_PROMOTION_SCHEMA :: u64(1)
/* PROJECT_PROMOTION_HEADER_BYTES is the fixed promotion result prefix. */
PROJECT_PROMOTION_HEADER_BYTES :: u64(32)
/* PROMOTION_SUPPRESSION_HEADER_BYTES is one fixed suppression result prefix. */
PROMOTION_SUPPRESSION_HEADER_BYTES :: u64(40)

/* Promotion_Suppression_Action selects one global preference operation. */
Promotion_Suppression_Action :: enum u8 {
	Invalid,
	Inspect,
	Add,
	Remove,
}

/* Promotion_Suppression_Result reports one exact global preference observation. */
Promotion_Suppression_Result :: struct {
	generation: u64,
	suppressed: bool,
}

/* Project_Promotion_Result reports durable and exact session publication. */
Project_Promotion_Result :: struct {
	activation: editor_session.Project_Directory_Open_Result,
	roots:      editor_session.Root_Replace_Result,
	reconciled: bool,
}

/* Project_Unregister_Result reports one exact global Project registry removal. */
Project_Unregister_Result :: struct {
	reconciled: bool,
}

/* Project_Rename_Result reports one exact durable Project name replacement. */
Project_Rename_Result :: struct {
	reconciled: bool,
}

/* project_promote publishes one exact ordinary Dir as an untrusted Project. */
project_promote :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, path, name: string,
) -> (result: Project_Promotion_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(configuration_root) == 0 || len(path) == 0 || len(name) == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	roots, roots_ok, roots_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !roots_ok {
		return {}, false, buffer_session_failure(ctx.command, roots_failure)
	}
	defer editor_session.root_batch_close(&roots)
	target_index, exact := project_promotion_root_index(roots.descriptors, path)
	if !exact {
		return {}, false, Failure_Context{code = .Project_Scope_Required, command = ctx.command}
	}

	storage: [hosting.MAX_PROJECT_PROMOTION_BYTES]byte
	output_length, promoted, promotion_failure := hosting.runtime_project_promotion(
		racket_runtime,
		configuration_root,
		path,
		name,
		storage[:],
	)
	if !promoted {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			promotion_failure,
		)
	}
	outcome, state, publication, decoded := project_promotion_result_decode(
		storage[:int(output_length)],
	)
	if !decoded {
		return {}, false, Failure_Context{code = .Wrong_Result, command = ctx.command}
	}
	if outcome != 1 {
		code := Failure_Code.Project_Promotion_Rejected
		if publication == 4 {
			code = .Project_Promotion_Unresolved
		}
		return {}, false, Failure_Context{code = code, command = ctx.command}
	}

	candidates, resolved, resolve_failure := project_directory_candidates_resolve(
		racket_runtime,
		configuration_root,
		path,
		ctx.persistent_allocator,
	)
	if !resolved {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			resolve_failure,
		)
	}
	defer project_directory_candidate_batch_close(&candidates)
	if len(candidates.candidates) != 1 {
		return {}, false, Failure_Context{code = .Project_Promotion_Unresolved, command = ctx.command}
	}
	candidate := candidates.candidates[0]
	if candidate.path != path || candidate.name != name || candidate.trust != .Untrusted ||
	   candidate.project_generation != project.Project_Generation(1) {
		return {}, false, Failure_Context{code = .Wrong_Result, command = ctx.command}
	}

	current, current_ok, current_failure := editor_session.session_roots(ctx.session, ctx.handle)
	if !current_ok {
		return {}, false, buffer_session_failure(ctx.command, current_failure)
	}
	defer editor_session.root_batch_close(&current)
	current_index, current_exact := project_promotion_root_index(current.descriptors, path)
	if !current_exact || current.generation != roots.generation || current_index != target_index {
		return {}, false, Failure_Context{code = .Project_Promotion_Unresolved, command = ctx.command}
	}

	activation, activated, activation_failure := editor_session.session_open_project_directory(
		ctx.session,
		editor_session.Project_Directory_Open_Request {
			session = ctx.handle,
			expected_catalog_generation = candidates.catalog_generation,
			actual_catalog_generation = candidates.catalog_generation,
			normalized_path = path,
			matching_projects = 1,
			project_id = candidate.project_id,
			project_generation = candidate.project_generation,
			durable_id = candidate.durable_id,
			name = candidate.name,
			trust = candidate.trust,
			temporary = false,
		},
	)
	if !activated {
		return {}, false, buffer_session_failure(ctx.command, activation_failure)
	}
	proposals: [int(editor_session.MAX_SESSION_ROOTS)]editor_session.Root_Proposal
	for descriptor, index in current.descriptors {
		if index == current_index {
			proposals[index] = {
				kind = .Project,
				path = descriptor.path,
				project = activation.active.handle,
			}
		} else {
			proposals[index] = {kind = descriptor.kind, path = descriptor.path, project = descriptor.project}
		}
	}
	published_roots, published, publish_failure := editor_session.session_roots_replace(
		ctx.session,
		editor_session.Root_Replace_Request {
			session = ctx.handle,
			roots = proposals[:len(current.descriptors)],
		},
	)
	if !published {
		return {}, false, buffer_session_failure(ctx.command, publish_failure)
	}
	return Project_Promotion_Result {
		activation = activation,
		roots = published_roots,
		reconciled = state == 2,
	}, true, {}
}

/* project_unregister removes one exact globally discoverable Project reference. */
project_unregister :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, id, root: string,
	generation: project.Project_Generation,
) -> (result: Project_Unregister_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(configuration_root) == 0 || len(id) == 0 || len(root) == 0 || generation == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	storage: [hosting.MAX_PROJECT_PROMOTION_BYTES]byte
	output_length, removed, remove_failure := hosting.runtime_project_unregister(
		racket_runtime,
		configuration_root,
		id,
		root,
		u64(generation),
		storage[:],
	)
	if !removed {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command},
			remove_failure,
		)
	}
	outcome, state, publication, decoded := project_promotion_result_decode(
		storage[:int(output_length)],
	)
	if !decoded {
		return {}, false, Failure_Context{code = .Wrong_Result, command = ctx.command}
	}
	if outcome != 1 {
		code := Failure_Code.Project_Durability_Failure
		if publication == 4 {
			code = .Project_Promotion_Unresolved
		}
		return {}, false, Failure_Context{code = code, command = ctx.command}
	}
	return Project_Unregister_Result{reconciled = state == 2}, true, {}
}

/* project_rename publishes one checked Project display-name generation. */
project_rename :: proc(
	ctx: Project_Command_Context,
	racket_runtime: ^hosting.Runtime,
	configuration_root, root, name: string,
	generation: project.Project_Generation,
) -> (result: Project_Rename_Result, ok: bool, failure: Failure_Context) {
	if !project_command_context_is_valid(ctx) || racket_runtime == nil ||
	   len(configuration_root) == 0 || len(root) == 0 || len(name) == 0 || generation == 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = ctx.command}
	}
	storage: [hosting.MAX_PROJECT_PROMOTION_BYTES]byte
	output_length, renamed, rename_failure := hosting.runtime_project_rename(
		racket_runtime, configuration_root, root, name, u64(generation), storage[:],
	)
	if !renamed {
		return {}, false, hosting_failure_context(
			Failure_Context{command = ctx.command}, rename_failure,
		)
	}
	outcome, state, publication, decoded := project_promotion_result_decode(
		storage[:int(output_length)],
	)
	if !decoded do return {}, false, Failure_Context{code = .Wrong_Result, command = ctx.command}
	if outcome != 1 {
		code := Failure_Code.Project_Durability_Failure
		if publication == 4 do code = .Project_Promotion_Unresolved
		return {}, false, Failure_Context{code = code, command = ctx.command}
	}
	return Project_Rename_Result{reconciled = state == 2}, true, {}
}

/* project_promotion_suppression inspects or updates one bounded global Dir preference. */
project_promotion_suppression :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root, path: string,
	action: Promotion_Suppression_Action,
) -> (result: Promotion_Suppression_Result, ok: bool, failure: Failure_Context) {
	if racket_runtime == nil || len(configuration_root) == 0 || len(path) == 0 ||
	   action == .Invalid {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	storage: [hosting.MAX_PROJECT_PROMOTION_BYTES]byte
	output_length, transferred, transfer_failure := hosting.runtime_promotion_suppression(
		racket_runtime,
		configuration_root,
		path,
		u64(action),
		storage[:],
	)
	if !transferred {
		return {}, false, hosting_failure_context({}, transfer_failure)
	}
	if output_length < PROMOTION_SUPPRESSION_HEADER_BYTES {
		return {}, false, Failure_Context{code = .Wrong_Result}
	}
	bytes := storage[:int(output_length)]
	schema, schema_ok := endian.get_u64(bytes[0:], .Little)
	outcome, outcome_ok := endian.get_u64(bytes[8:], .Little)
	suppressed, suppressed_ok := endian.get_u64(bytes[16:], .Little)
	generation, generation_ok := endian.get_u64(bytes[24:], .Little)
	publication, publication_ok := endian.get_u64(bytes[32:], .Little)
	if !schema_ok || !outcome_ok || !suppressed_ok || !generation_ok || !publication_ok ||
	   schema != PROJECT_PROMOTION_SCHEMA || (outcome != 1 && outcome != 2) || suppressed > 1 ||
	   publication < 1 || publication > 3 ||
	   (outcome == 1 && publication != 2) || (outcome == 2 && generation != 0) {
		return {}, false, Failure_Context{code = .Wrong_Result}
	}
	if outcome == 2 {
		code := Failure_Code.Project_Suppression_Rejected
		if publication == 3 {
			code = .Project_Suppression_Unresolved
		}
		return {}, false, Failure_Context{code = code}
	}
	return Promotion_Suppression_Result {
		generation = generation,
		suppressed = suppressed == 1,
	}, true, {}
}

@(private)
project_promotion_root_index :: proc(
	descriptors: []editor_session.Root_Descriptor,
	path: string,
) -> (index: int, ok: bool) {
	matched := -1
	for descriptor, candidate_index in descriptors {
		if descriptor.kind == .Project {
			return 0, false
		}
		if descriptor.kind == .Dir && descriptor.path == path {
			if matched >= 0 {
				return 0, false
			}
			matched = candidate_index
		}
	}
	return matched, matched >= 0
}

@(private)
project_promotion_result_decode :: proc(bytes: []byte) -> (outcome, state, publication: u64, ok: bool) {
	if len(bytes) < int(PROJECT_PROMOTION_HEADER_BYTES) {
		return 0, 0, 0, false
	}
	schema, schema_ok := endian.get_u64(bytes[0:], .Little)
	outcome_value, outcome_ok := endian.get_u64(bytes[8:], .Little)
	state_value, state_ok := endian.get_u64(bytes[16:], .Little)
	publication_value, publication_ok := endian.get_u64(bytes[24:], .Little)
	return outcome_value, state_value, publication_value,
	       schema_ok && outcome_ok && state_ok && publication_ok &&
	       schema == PROJECT_PROMOTION_SCHEMA && (outcome_value == 1 || outcome_value == 2) &&
	       publication_value >= 1 && publication_value <= 4 &&
	       ((outcome_value == 1 && (state_value == 1 || state_value == 2) && publication_value == 3) ||
	        (outcome_value == 2 && state_value == 0))
}
