// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery

/* repository_process_start_conflict_assistance_tool admits one provider tool into Process. */
repository_process_start_conflict_assistance_tool :: proc(
	request: Conflict_Assistance_Request,
	provider: Conflict_Assistance_Provider,
	selection: Conflict_Assistance_Selection,
	tool: Conflict_Assistance_Tool_Plan,
	provider_declaration: Contribution_Declaration,
	operation_declaration: Contribution_Declaration,
	index_before: Conflict_Assistance_Index_Fingerprint,
	current_contributor: Contributor_Handle,
	current_repository: Repository_Context,
	current_repository_generation: Repository_Generation,
	now_ns: i64,
	allocator := context.allocator,
) -> (
	process: Repository_Process,
	admission: Conflict_Assistance_Tool_Admission,
	started: bool,
	failure: Conflict_Assistance_Failure,
) {
	admission = {
		request = request,
		operation = {
			request = Extension_Operation_Request_ID(u64(request.request)),
			contributor = provider.contributor,
			contribution = tool.operation.contribution,
			repository = request.target.repository,
			repository_generation = request.target.repository_generation,
		},
		access = tool.access,
		index_before = index_before,
	}
	failure = conflict_assistance_tool_admission_validate(
		admission,
		tool,
		provider,
		selection,
		provider_declaration,
		operation_declaration,
		current_contributor,
		current_repository,
		current_repository_generation,
	)
	if failure.code != .None do return
	operation_process, operation_started, operation_failure :=
		repository_process_start_extension_operation(
			admission.operation,
			tool.operation,
			operation_declaration,
			current_contributor,
			current_repository,
			current_repository_generation,
			now_ns,
			allocator,
		)
	if !operation_started {
		failure.code = conflict_assistance_operation_failure_code(operation_failure.code)
		return
	}
	return operation_process, admission, true, {}
}

/* repository_process_conflict_assistance_tool_snapshot checks exact owned Process evidence. */
repository_process_conflict_assistance_tool_snapshot :: proc(
	process: ^Repository_Process,
	admission: Conflict_Assistance_Tool_Admission,
	tool: Conflict_Assistance_Tool_Plan,
) -> (Repository_Process_Lifecycle_View, []u8, []u8, bool) {
	submission, plan, view, output, diagnostic, available :=
		repository_process_extension_operation_snapshot(process)
	if !available || submission != admission.operation ||
	   plan.contributor != tool.operation.contributor ||
	   plan.contribution != tool.operation.contribution ||
	   plan.plan != tool.operation.plan || plan.generation != tool.operation.generation ||
	   plan.effect != tool.operation.effect || plan.refresh != CONFLICT_ASSISTANCE_TOOL_REFRESH {
		return {}, nil, nil, false
	}
	return view, output, diagnostic, true
}
