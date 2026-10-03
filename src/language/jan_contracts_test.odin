// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:testing"

/* Verifies factory baseline provenance is exact and rejects altered identities. */
@(test)
jan_factory_baseline_is_exact :: proc(t: ^testing.T) {
	baseline := jan_factory_baseline()
	testing.expect(t, jan_baseline_identity_is_valid(baseline))
	testing.expect_value(t, string(baseline.name.bytes[:baseline.name.length]), JAN_BASELINE_NAME)
	testing.expect_value(
		t,
		string(baseline.specification_commit.bytes[:baseline.specification_commit.length]),
		JAN_SPECIFICATION_COMMIT,
	)

	invalid := baseline
	invalid.generation = 0
	testing.expect(t, !jan_baseline_identity_is_valid(invalid))
	invalid = baseline
	invalid.name.bytes[0] = 'x'
	testing.expect(t, !jan_baseline_identity_is_valid(invalid))
}

/* Verifies every declared source-form node kind belongs to one closed vocabulary. */
@(test)
jan_node_kind_vocabulary_is_closed :: proc(t: ^testing.T) {
	for value in int(Jan_Node_Kind.Document_Root) ..= int(Jan_Node_Kind.Recovery) {
		testing.expect(t, jan_node_kind_is_valid(Jan_Node_Kind(value)))
	}
	testing.expect(t, !jan_node_kind_is_valid(.Invalid))
	testing.expect(t, !jan_node_kind_is_valid(Jan_Node_Kind(255)))
}

/* Verifies analysis scopes require exact document, language, provider, and generation state. */
@(test)
jan_analysis_scope_is_exact :: proc(t: ^testing.T) {
	scope := jan_test_scope()
	testing.expect(t, jan_analysis_scope_is_valid(scope))

	invalid := scope
	invalid.document_id = 0
	testing.expect(t, !jan_analysis_scope_is_valid(invalid))
	invalid = scope
	invalid.provider.language_id += 1
	testing.expect(t, !jan_analysis_scope_is_valid(invalid))
	invalid = scope
	invalid.configuration.digest = {}
	testing.expect(t, !jan_analysis_scope_is_valid(invalid))
	invalid = scope
	invalid.analysis_generation = 0
	testing.expect(t, !jan_analysis_scope_is_valid(invalid))
}

/* Verifies source ranges and nodes enforce ordering, ownership, and selected depths. */
@(test)
jan_nodes_are_revision_bound_and_bounded :: proc(t: ^testing.T) {
	node := jan_test_node()
	testing.expect(t, jan_source_range_is_valid(node.range, 128))
	testing.expect(t, jan_node_record_is_valid(node, 128))

	invalid := node
	invalid.range.end = 129
	testing.expect(t, !jan_node_record_is_valid(invalid, 128))
	invalid = node
	invalid.parent_id = invalid.id
	testing.expect(t, !jan_node_record_is_valid(invalid, 128))
	invalid = node
	invalid.structural_depth = MAX_JAN_STRUCTURAL_DEPTH + 1
	testing.expect(t, !jan_node_record_is_valid(invalid, 128))
	invalid = node
	invalid.kind = .Recovery
	testing.expect(t, !jan_node_record_is_valid(invalid, 128))
}

/* Verifies attributes, recovery records, and facts retain one exact source scope. */
@(test)
jan_derived_records_share_analysis_scope :: proc(t: ^testing.T) {
	node := jan_test_node()
	name: Jan_Attribute_Name
	name.length = u16(copy(name.bytes[:], "title"))
	value: Jan_Attribute_Value
	value.length = u16(copy(value.bytes[:], "Forecast"))
	attribute := Jan_Attribute_Record {
		node_id = node.id,
		kind = .Text,
		name = name,
		range = node.range,
		value = value,
	}
	recovery := Jan_Recovery_Record {node_id = node.id, code = .Malformed, range = node.range}
	fact := Jan_Index_Fact {id = 1, kind = .Heading, node_id = node.id, range = node.range}
	testing.expect(t, jan_attribute_record_is_valid(attribute, 128))
	testing.expect(t, jan_recovery_record_is_valid(recovery, 128))
	testing.expect(t, jan_index_fact_is_valid(fact, 128))

	attribute.name.length = 0
	recovery.code = .Invalid
	fact.kind = .Invalid
	testing.expect(t, !jan_attribute_record_is_valid(attribute, 128))
	testing.expect(t, !jan_recovery_record_is_valid(recovery, 128))
	testing.expect(t, !jan_index_fact_is_valid(fact, 128))
}

/* Verifies the selected Jan policy remains inside inherited language ceilings. */
@(test)
jan_resource_policy_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, jan_resource_limits_are_valid(DEFAULT_JAN_RESOURCE_LIMITS))
	testing.expect_value(t, DEFAULT_JAN_RESOURCE_LIMITS.nodes, u32(1_048_576))
	testing.expect_value(t, DEFAULT_JAN_RESOURCE_LIMITS.structural_depth, u16(1_024))
	testing.expect_value(t, DEFAULT_JAN_RESOURCE_LIMITS.inline_depth, u16(256))
	testing.expect_value(t, DEFAULT_JAN_RESOURCE_LIMITS.candidate_nanoseconds, u64(5_000_000_000))

	invalid := DEFAULT_JAN_RESOURCE_LIMITS
	invalid.nodes = MAX_JAN_NODES + 1
	testing.expect(t, !jan_resource_limits_are_valid(invalid))
	invalid = DEFAULT_JAN_RESOURCE_LIMITS
	invalid.rewrite_bytes = MAX_JAN_REWRITE_BYTES + 1
	testing.expect(t, !jan_resource_limits_are_valid(invalid))
	invalid = DEFAULT_JAN_RESOURCE_LIMITS
	invalid.candidate_nanoseconds = invalid.maintenance_step_nanoseconds - 1
	testing.expect(t, !jan_resource_limits_are_valid(invalid))
}

/* Verifies resource usage accepts exact ceilings and rejects one-unit overflow. */
@(test)
jan_resource_usage_rejects_overflow :: proc(t: ^testing.T) {
	usage := Jan_Resource_Usage {
		source_bytes = MAX_ANALYZED_SOURCE_BYTES,
		retained_bytes = MAX_RETAINED_ANALYSIS_BYTES,
		temporary_bytes = MAX_TEMPORARY_BYTES,
		nodes = MAX_JAN_NODES,
		structural_depth = MAX_JAN_STRUCTURAL_DEPTH,
		inline_depth = MAX_JAN_INLINE_DEPTH,
		maximum_attributes = MAX_JAN_ATTRIBUTES_PER_NODE,
		index_facts = MAX_JAN_INDEX_FACTS,
		diagnostics = MAX_JAN_DIAGNOSTICS,
		incremental_edits = MAX_JAN_INCREMENTAL_EDITS,
		elapsed_nanoseconds = MAX_JAN_CANDIDATE_NS,
	}
	testing.expect(t, jan_resource_usage_is_within(usage))
	usage.index_facts += 1
	testing.expect(t, !jan_resource_usage_is_within(usage))
}

/* Verifies rewrite proposals enforce exact scope, splice count, and aggregate bytes. */
@(test)
jan_rewrite_descriptors_are_bounded :: proc(t: ^testing.T) {
	plan := Jan_Rewrite_Plan_Descriptor {
		generation = 1,
		scope = jan_test_scope(),
		splice_count = 3,
		replacement_bytes = 1 * MEBIBYTE,
		metadata_bytes = 1 * MEBIBYTE,
	}
	testing.expect(t, jan_rewrite_plan_descriptor_is_valid(plan))
	plan.splice_count = 0
	testing.expect(t, !jan_rewrite_plan_descriptor_is_valid(plan))
	plan.splice_count = 3
	plan.replacement_bytes = MAX_JAN_REWRITE_BYTES
	plan.metadata_bytes = 1
	testing.expect(t, !jan_rewrite_plan_descriptor_is_valid(plan))
}

/* Verifies future-stage capabilities are unavailable and name their owning stage. */
@(test)
jan_future_stage_availability_is_explicit :: proc(t: ^testing.T) {
	capability: Jan_Capability_Name
	capability.length = u16(copy(capability.bytes[:], "jan-promote-subtree"))
	detail: Jan_Availability_Detail
	detail.length = u16(copy(detail.bytes[:], "available after Jan Structured Editing"))
	record := Jan_Availability_Record {
		capability = capability,
		class = .Future_Stage,
		owner = .Structured_Editing,
		available = false,
		detail = detail,
	}
	testing.expect(t, jan_availability_record_is_valid(record))
	record.available = true
	testing.expect(t, !jan_availability_record_is_valid(record))
	record.available = false
	record.owner = .Document_Language
	testing.expect(t, !jan_availability_record_is_valid(record))
}

@(private = "file")
jan_test_scope :: proc() -> Jan_Analysis_Scope {
	language_name: Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := Jan_Configuration_Identity {generation = 1}
	configuration.digest[0] = 1
	return {
		buffer_id = 3,
		document_id = 5,
		has_document = true,
		source_revision = 7,
		language = {id = 2, generation = 1, name = language_name},
		provider = {registry_id = 2, language_id = 2, provider_id = 1, provider_generation = 1},
		selection_generation = 11,
		parser_generation = 13,
		grammar_generation = 17,
		configuration = configuration,
		baseline = jan_factory_baseline(),
		analysis_generation = 19,
	}
}

@(private = "file")
jan_test_node :: proc() -> Jan_Node_Record {
	kind_text: Jan_Node_Kind_Text
	kind_text.length = u16(copy(kind_text.bytes[:], "heading"))
	return {
		id = 1,
		layer = .Structural,
		kind = .Heading,
		kind_text = kind_text,
		structural_depth = 1,
		range = {scope = jan_test_scope(), start = editor.Byte_Offset(0), end = 12},
		attribute_count = 2,
	}
}
