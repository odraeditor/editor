// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../language_service"
import "../language_support"

@(private)
Language_Support_Workflow_Candidate :: language_support.Runtime_Catalog_Candidate

// Language_Support_Workflow_Prepare validates one atomic language-support generation.
Language_Support_Workflow_Prepare :: proc(
	syntax: ^Syntax_Workflow_State,
	workflow: ^Language_Service_Workflow_State,
	input: []u8,
	source_generation: u64,
	allocator := context.allocator,
) -> (Language_Support_Workflow_Candidate, bool) {
	if !syntax_workflow_is_live(syntax) || !Language_Service_Workflow_Is_Live(workflow) {
		return {}, false
	}
	return language_support.runtime_catalog_prepare(
		&syntax.language_catalog,
		&workflow.registry,
		&workflow.catalog,
		workflow.factory,
		input,
		source_generation,
		allocator,
	)
}

// Language_Support_Workflow_Publish confirms one prepared language-support generation.
Language_Support_Workflow_Publish :: proc(
	candidate: ^Language_Support_Workflow_Candidate,
	syntax: ^Syntax_Workflow_State,
	workflow: ^Language_Service_Workflow_State,
) -> bool {
	if candidate == nil || !syntax_workflow_is_live(syntax) ||
	   !Language_Service_Workflow_Is_Live(workflow) {
		return false
	}
	retired := language_support.runtime_catalog_candidate_retired_definitions(candidate)
	if int(workflow.retired_definition_count) + len(retired) >
	   language_service.MAX_SERVICE_CATALOG_DEFINITIONS {
		return false
	}
	if !language_support.runtime_catalog_publish(
		candidate,
		&syntax.language_catalog,
		&workflow.catalog,
	) {
		return false
	}
	for handle in retired {
		workflow.retired_definitions[workflow.retired_definition_count] = handle
		workflow.retired_definition_count += 1
	}
	return true
}

// Language_Support_Workflow_Candidate_Close releases unpublished or superseded candidate state.
Language_Support_Workflow_Candidate_Close :: proc(
	candidate: ^Language_Support_Workflow_Candidate,
	workflow: ^Language_Service_Workflow_State,
) -> bool {
	if workflow == nil do return false
	return language_support.runtime_catalog_candidate_close(candidate, &workflow.registry)
}
