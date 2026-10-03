// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies complete generations replace atomically and sort independent of declaration order. */
@(test)
extension_catalog_replaces_and_orders_complete_provider_sets :: proc(t: ^testing.T) {
	definitions := [4]Extension_Definition {
		extension_test_definition("html-notes", 23, .Derived_Backend, {.Render_Backend}, .Result_Value),
		extension_test_definition("property-write", 19, .Property_Writer, {.Write_Property}, .Document_Candidate),
		extension_test_definition("lifecycle", 17, .Hook, {.Run_Hook}, .Read_Only),
		extension_test_definition("html", 13, .Export_Backend, {.Render_Backend}, .Result_Value),
	}
	definitions[0].parent_identity = "html"
	definitions[0].parent_generation = 13
	definitions[1].authorities += {.Propose_Document_Edit}
	output: [4]Extension_Definition
	request := extension_test_catalog_request()
	catalog, ok, failure := prepare_extension_catalog(request, 40, definitions[:], output[:])
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, catalog.catalog_generation, Provider_Generation(41))
	testing.expect_value(t, output[0].identity, "lifecycle")
	testing.expect_value(t, output[1].identity, "property-write")
	testing.expect_value(t, output[2].identity, "html")
	testing.expect_value(t, output[3].identity, "html-notes")

	request.catalog_generation = 40
	_, stale_ok, stale_failure := prepare_extension_catalog(request, 40, definitions[:], output[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Request)
	definitions[0].parent_identity = "missing"
	request.catalog_generation = 41
	_, derived_ok, derived_failure := prepare_extension_catalog(request, 40, definitions[:], output[:])
	testing.expect(t, !derived_ok)
	testing.expect_value(t, derived_failure.code, Failure_Code.Cycle)
}

/* Verifies invocation requires exact generations, declared authority, and provider limits. */
@(test)
extension_invocation_is_exact_authorized_and_bounded :: proc(t: ^testing.T) {
	definition := extension_test_definition(
		"dynamic-summary", 17, .Dynamic_Block, {.Write_Dynamic_Block}, .Document_Candidate)
	definition.authorities += {.Propose_Document_Edit}
	definitions := [1]Extension_Definition {definition}
	catalog := extension_test_catalog_record()
	request := extension_test_invocation("dynamic-summary", 17, .Dynamic_Block, .Write_Dynamic_Block)
	request.granted_authorities += {.Propose_Document_Edit}
	plan, ok, _ := prepare_extension_invocation(request, catalog, definitions[:])
	testing.expect(t, ok)
	testing.expect_value(t, plan.boundary, Extension_Result_Boundary.Document_Candidate)

	request.granted_authorities += {.Network}
	_, authority_ok, authority_failure := prepare_extension_invocation(request, catalog, definitions[:])
	testing.expect(t, !authority_ok)
	testing.expect_value(t, authority_failure.code, Failure_Code.Unauthorized)
	request.granted_authorities -= {.Network}
	request.provider_generation += 1
	_, stale_ok, stale_failure := prepare_extension_invocation(request, catalog, definitions[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
	request.provider_generation -= 1
	request.input_count = definition.input_limit + 1
	_, limited_ok, limited_failure := prepare_extension_invocation(request, catalog, definitions[:])
	testing.expect(t, !limited_ok)
	testing.expect_value(t, limited_failure.code, Failure_Code.Limited)
}

/* Verifies provider turns return unapplied candidates and contain failure cleanup. */
@(test)
extension_results_never_apply_mutations_directly :: proc(t: ^testing.T) {
	definition := extension_test_definition(
		"property-write", 17, .Property_Writer, {.Write_Property}, .Document_Candidate)
	definition.authorities += {.Propose_Document_Edit}
	definitions := [1]Extension_Definition {definition}
	request := extension_test_invocation("property-write", 17, .Property_Writer, .Write_Property)
	request.granted_authorities += {.Propose_Document_Edit}
	plan, ok, _ := prepare_extension_invocation(request, extension_test_catalog_record(), definitions[:])
	testing.expect(t, ok)
	completed := Extension_Result {
		operation_id = plan.operation_id,
		provider_identity = plan.provider_identity,
		provider_generation = plan.provider_generation,
		state = .Completed,
		result_count = 1,
		result_bytes = 64,
		candidate_kind = .Document,
		candidate_id = 501,
		expected_resource_revision = plan.resource_revision,
		temporary_created = 1,
		temporary_cleaned = 1,
		complete = true,
	}
	completed.result_digest[0] = 7
	testing.expect(t, extension_result_is_valid(plan, completed))
	completed.mutated_directly = true
	testing.expect(t, !extension_result_is_valid(plan, completed))
	completed.mutated_directly = false
	completed.expected_resource_revision += 1
	testing.expect(t, !extension_result_is_valid(plan, completed))

	failed := Extension_Result {operation_id = plan.operation_id,
		provider_identity = plan.provider_identity, provider_generation = plan.provider_generation,
		state = .Failed, temporary_created = 2, temporary_cleaned = 2}
	testing.expect(t, extension_result_is_valid(plan, failed))
	plan.failure_policy = .Disable_Provider
	disposition, disposition_ok := extension_failure_disposition(plan, failed)
	testing.expect(t, disposition_ok)
	testing.expect(t, disposition.disable_candidate)
	testing.expect(t, !disposition.abort_operation)
	failed.temporary_cleaned = 1
	testing.expect(t, !extension_result_is_valid(plan, failed))
}

/* Verifies hook, property, and mapping APIs preserve semantic owner boundaries. */
@(test)
extension_domain_requests_are_copied_and_candidate_only :: proc(t: ^testing.T) {
	hook := Extension_Hook_Request {
		invocation = extension_test_invocation("lifecycle", 17, .Hook, .Run_Hook),
		event = .After_Export,
	}
	testing.expect(t, extension_hook_request_is_valid(hook))
	hook.mutating = true
	testing.expect(t, !extension_hook_request_is_valid(hook))
	hook.invocation.granted_authorities += {.Propose_Document_Edit}
	testing.expect(t, extension_hook_request_is_valid(hook))

	property := Extension_Property_Request {
		invocation = extension_test_invocation("properties", 17, .Property_Reader, .Read_Property),
		access = .Inherited,
		property = "owner",
		node_id = 301,
	}
	testing.expect(t, extension_property_request_is_valid(property))
	property.access = .Write
	testing.expect(t, !extension_property_request_is_valid(property))

	mapping := Extension_Tree_Map_Request {
		invocation = extension_test_invocation("tree-map", 17, .Tree_Mapper, .Map_Tree),
		scope = .Subtree,
		match_identity = "heading",
		prune = true,
		restricted = true,
		stable_order = true,
		node_limit = 1024,
		result_limit = 64,
	}
	testing.expect(t, extension_tree_map_request_is_valid(mapping))
	mapping.stable_order = false
	testing.expect(t, !extension_tree_map_request_is_valid(mapping))
}

/* Verifies inspection and the full-family conformance ledger are explicit. */
@(test)
extension_inspection_and_conformance_are_complete :: proc(t: ^testing.T) {
	definitions := [1]Extension_Definition {
		extension_test_definition("agenda-source", 17, .Agenda_Source, {.Supply_Agenda}, .Result_Value),
	}
	record, found := inspect_extension_provider(extension_test_catalog_record(), definitions[:], "agenda-source")
	testing.expect(t, found)
	testing.expect(t, record.active)
	testing.expect_value(t, record.family, Extension_Family.Agenda_Source)
	testing.expect(t, .Supply_Agenda in record.operations)

	conformance := Extension_Conformance_Record {
		catalog_generation = 41,
		family_count = u16(Extension_Family.Synchronization_Provider),
		provider_count = u16(Extension_Family.Synchronization_Provider),
		copied_values = true,
		deterministic_order = true,
		stale_rejection = true,
		authority_constrained = true,
		mutation_candidate_only = true,
		failure_contained = true,
		limits_enforced = true,
		cleanup_complete = true,
		inspection_complete = true,
	}
	testing.expect(t, extension_conformance_is_complete(conformance))
	conformance.cleanup_complete = false
	testing.expect(t, !extension_conformance_is_complete(conformance))
}

@(private = "file")
extension_test_definition :: proc(
	identity: string,
	generation: Provider_Generation,
	family: Extension_Family,
	operations: Extension_Operations,
	boundary: Extension_Result_Boundary,
) -> Extension_Definition {
	return {
		identity = identity,
		generation = generation,
		family = family,
		source = .Package,
		api_version = EXTENSION_API_VERSION,
		operations = operations,
		authorities = {.Inspect, .Document_Read},
		boundary = boundary,
		failure_policy = .Continue,
		input_limit = 64,
		input_byte_limit = 1_048_576,
		result_limit = 64,
		output_byte_limit = 1_048_576,
		temporary_limit = 8,
		state = .Available,
		admitted = true,
		complete = true,
	}
}

@(private = "file")
extension_test_catalog_request :: proc() -> Extension_Catalog_Request {
	request := Extension_Catalog_Request {
		configuration_generation = 43,
		catalog_generation = 41,
		replaces_generation = 40,
		definition_limit = 16,
		explicit = true,
	}
	request.catalog_digest[0] = 3
	return request
}

@(private = "file")
extension_test_catalog_record :: proc() -> Extension_Catalog_Record {
	record := Extension_Catalog_Record {
		configuration_generation = 43,
		catalog_generation = 41,
		definition_count = 1,
		available_count = 1,
		complete = true,
	}
	record.catalog_digest[0] = 3
	return record
}

@(private = "file")
extension_test_invocation :: proc(
	identity: string,
	generation: Provider_Generation,
	family: Extension_Family,
	operation: Extension_Operation,
) -> Extension_Invocation_Request {
	return {
		operation_id = 61,
		configuration_generation = 43,
		catalog_generation = 41,
		provider_identity = identity,
		provider_generation = generation,
		family = family,
		operation = operation,
		resource_id = 101,
		resource_revision = 11,
		granted_authorities = {.Inspect, .Document_Read},
		input_count = 4,
		input_bytes = 512,
		result_count_limit = 4,
		output_byte_limit = 4096,
		temporary_resource_limit = 2,
		explicit = true,
	}
}
