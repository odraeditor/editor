// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../language"

/* JAN_LANGUAGE_SCHEMA_VERSION identifies the copied Stage 1 command ABI. */
JAN_LANGUAGE_SCHEMA_VERSION :: u64(1)
/* MAX_JAN_LANGUAGE_COPY_BYTES bounds one complete command response. */
MAX_JAN_LANGUAGE_COPY_BYTES :: u64(language.MAX_JAN_INSPECTION_BYTES)
/* MAX_JAN_LANGUAGE_NODES bounds copied syntax paths in one response. */
MAX_JAN_LANGUAGE_NODES :: u64(language.MAX_JAN_NODES)
/* MAX_JAN_LANGUAGE_ATTRIBUTES bounds copied attributes in one response. */
MAX_JAN_LANGUAGE_ATTRIBUTES :: u64(language.MAX_JAN_NODES) *
	u64(language.MAX_JAN_ATTRIBUTES_PER_NODE)
/* MAX_JAN_LANGUAGE_RECOVERIES bounds copied recovery records in one response. */
MAX_JAN_LANGUAGE_RECOVERIES :: u64(language.MAX_JAN_DIAGNOSTICS)
/* MAX_JAN_LANGUAGE_LINT_RECORDS bounds copied lint facts in one response. */
MAX_JAN_LANGUAGE_LINT_RECORDS :: u64(language.MAX_JAN_DIAGNOSTICS)
/* MAX_JAN_LANGUAGE_AVAILABILITY bounds one copied Stage 1 capability inventory. */
MAX_JAN_LANGUAGE_AVAILABILITY :: u64(128)

/* JAN_LANGUAGE_SCOPE_RECORD_BYTES is one exact document-analysis scope. */
JAN_LANGUAGE_SCOPE_RECORD_BYTES :: u64(144)
/* JAN_LANGUAGE_COMMAND_RECORD_BYTES is one scoped read-only command request. */
JAN_LANGUAGE_COMMAND_RECORD_BYTES :: u64(160)
/* JAN_LANGUAGE_INSPECTION_HEADER_BYTES precedes one copied inspection response. */
JAN_LANGUAGE_INSPECTION_HEADER_BYTES :: u64(216)
/* JAN_LANGUAGE_NODE_RECORD_BYTES is one copied syntax path element. */
JAN_LANGUAGE_NODE_RECORD_BYTES :: u64(128)
/* JAN_LANGUAGE_ATTRIBUTE_RECORD_BYTES is one copied typed attribute. */
JAN_LANGUAGE_ATTRIBUTE_RECORD_BYTES :: u64(64)
/* JAN_LANGUAGE_RECOVERY_RECORD_BYTES is one copied malformed-source range. */
JAN_LANGUAGE_RECOVERY_RECORD_BYTES :: u64(32)
/* JAN_LANGUAGE_LINT_RECORD_BYTES is one copied lint diagnostic. */
JAN_LANGUAGE_LINT_RECORD_BYTES :: u64(96)
/* JAN_LANGUAGE_LIMITS_RECORD_BYTES is the complete Stage 1 resource policy. */
JAN_LANGUAGE_LIMITS_RECORD_BYTES :: u64(152)
/* JAN_LANGUAGE_PROVIDER_RECORD_BYTES is one exact provider-generation summary. */
JAN_LANGUAGE_PROVIDER_RECORD_BYTES :: u64(72)
/* JAN_LANGUAGE_BASELINE_RECORD_BYTES is one copied compatibility identity. */
JAN_LANGUAGE_BASELINE_RECORD_BYTES :: u64(56)
/* JAN_LANGUAGE_FAILURE_RECORD_BYTES is one copied contained rejection. */
JAN_LANGUAGE_FAILURE_RECORD_BYTES :: u64(64)
/* JAN_LANGUAGE_AVAILABILITY_RECORD_BYTES is one copied capability status. */
JAN_LANGUAGE_AVAILABILITY_RECORD_BYTES :: u64(56)

/* Jan_Language_Operation identifies one read-only Stage 1 command request. */
Jan_Language_Operation :: enum u64 {
	Inspect_Syntax = 1,
	Lint = 2,
	Lint_Refresh = 3,
	Language_Status = 4,
}

/* Jan_Language_Scope_Record binds copied output to exact document analysis state. */
Jan_Language_Scope_Record :: struct {
	schema_version:          u64,
	buffer_id:               u64,
	document_id:             u64,
	has_document:            u64,
	source_revision:         u64,
	language_id:             u64,
	language_generation:     u64,
	provider_registry_id:    u64,
	provider_language_id:    u64,
	provider_id:             u64,
	provider_generation:     u64,
	selection_generation:    u64,
	parser_generation:       u64,
	grammar_generation:      u64,
	configuration_generation: u64,
	baseline_generation:     u64,
	analysis_generation:     u64,
	reserved:                u64,
}

/* Jan_Language_Command_Record carries one exact point or refresh request. */
Jan_Language_Command_Record :: struct {
	expected_scope: Jan_Language_Scope_Record,
	operation:      u64,
	point:          u64,
}

/* Jan_Language_Inspection_Header precedes copied syntax and lint arrays. */
Jan_Language_Inspection_Header :: struct {
	scope:              Jan_Language_Scope_Record,
	status:             u64,
	point:              u64,
	node_count:         u64,
	attribute_count:    u64,
	recovery_count:     u64,
	lint_generation:    u64,
	lint_count:         u64,
	availability_count: u64,
	text_bytes:         u64,
}

/* Jan_Language_Node_Record copies one syntax path element and its text offsets. */
Jan_Language_Node_Record :: struct {
	node_id:          u64,
	parent_id:        u64,
	layer:            u64,
	kind:             u64,
	structural_depth: u64,
	inline_depth:     u64,
	start:            u64,
	end:              u64,
	attribute_offset: u64,
	attribute_count:  u64,
	path_offset:      u64,
	path_bytes:       u64,
	kind_offset:      u64,
	kind_bytes:       u64,
	recovery_code:    u64,
	has_recovery:     u64,
}

/* Jan_Language_Attribute_Record copies one typed attribute and text offsets. */
Jan_Language_Attribute_Record :: struct {
	node_id:      u64,
	kind:         u64,
	start:        u64,
	end:          u64,
	name_offset:  u64,
	name_bytes:   u64,
	value_offset: u64,
	value_bytes:  u64,
}

/* Jan_Language_Recovery_Record copies one bounded malformed-source range. */
Jan_Language_Recovery_Record :: struct {
	node_id: u64,
	code:    u64,
	start:   u64,
	end:     u64,
}

/* Jan_Language_Lint_Record copies one severity, confidence, and explanation. */
Jan_Language_Lint_Record :: struct {
	id:                 u64,
	generation:         u64,
	has_range:          u64,
	start:              u64,
	end:                u64,
	code:               u64,
	severity:           u64,
	confidence:         u64,
	checker_offset:     u64,
	checker_bytes:      u64,
	explanation_offset: u64,
	explanation_bytes:  u64,
}

/* Jan_Language_Limits_Record publishes the complete selected Stage 1 policy. */
Jan_Language_Limits_Record :: struct {
	source_bytes:                 u64,
	retained_bytes:               u64,
	temporary_bytes:              u64,
	nodes:                        u64,
	structural_depth:             u64,
	inline_depth:                 u64,
	attributes_per_node:          u64,
	index_facts:                  u64,
	diagnostics:                  u64,
	diagnostic_text_bytes:        u64,
	incremental_edits:            u64,
	inspection_bytes:             u64,
	rewrite_splices:              u64,
	rewrite_bytes:                u64,
	cancellation_check_bytes:     u64,
	initial_step_bytes:           u64,
	incremental_step_bytes:       u64,
	maintenance_step_nanoseconds: u64,
	candidate_nanoseconds:        u64,
}

/* Jan_Language_Provider_Record publishes exact provider and parser generations. */
Jan_Language_Provider_Record :: struct {
	registry_id:              u64,
	language_id:              u64,
	provider_id:              u64,
	provider_generation:      u64,
	selection_generation:     u64,
	parser_generation:        u64,
	grammar_generation:       u64,
	configuration_generation: u64,
	baseline_generation:      u64,
}

/* Jan_Language_Baseline_Record copies compatibility provenance text offsets. */
Jan_Language_Baseline_Record :: struct {
	generation:                 u64,
	name_offset:                u64,
	name_bytes:                 u64,
	syntax_version_offset:      u64,
	syntax_version_bytes:       u64,
	specification_commit_offset: u64,
	specification_commit_bytes: u64,
}

/* Jan_Language_Failure_Record copies the latest contained rejection. */
Jan_Language_Failure_Record :: struct {
	operation:         u64,
	code:              u64,
	source_revision:   u64,
	analysis_generation: u64,
	limit:             u64,
	actual:            u64,
	diagnostic_offset: u64,
	diagnostic_bytes:  u64,
}

/* Jan_Language_Availability_Record copies one recognized capability state. */
Jan_Language_Availability_Record :: struct {
	class:             u64,
	owner:             u64,
	available:         u64,
	capability_offset: u64,
	capability_bytes:  u64,
	detail_offset:     u64,
	detail_bytes:      u64,
}

/* jan_language_inspection_bytes validates one complete copied response. */
jan_language_inspection_bytes :: proc(
	node_count, attribute_count, recovery_count, lint_count, availability_count, text_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if node_count > MAX_JAN_LANGUAGE_NODES ||
	   attribute_count > MAX_JAN_LANGUAGE_ATTRIBUTES ||
	   recovery_count > MAX_JAN_LANGUAGE_RECOVERIES ||
	   lint_count > MAX_JAN_LANGUAGE_LINT_RECORDS ||
	   availability_count > MAX_JAN_LANGUAGE_AVAILABILITY ||
	   text_bytes > MAX_JAN_LANGUAGE_COPY_BYTES {
		return 0, false
	}
	bytes = JAN_LANGUAGE_INSPECTION_HEADER_BYTES + JAN_LANGUAGE_LIMITS_RECORD_BYTES +
		JAN_LANGUAGE_PROVIDER_RECORD_BYTES + JAN_LANGUAGE_BASELINE_RECORD_BYTES +
		JAN_LANGUAGE_FAILURE_RECORD_BYTES +
		node_count * JAN_LANGUAGE_NODE_RECORD_BYTES +
		attribute_count * JAN_LANGUAGE_ATTRIBUTE_RECORD_BYTES +
		recovery_count * JAN_LANGUAGE_RECOVERY_RECORD_BYTES +
		lint_count * JAN_LANGUAGE_LINT_RECORD_BYTES +
		availability_count * JAN_LANGUAGE_AVAILABILITY_RECORD_BYTES + text_bytes
	return bytes, bytes <= MAX_JAN_LANGUAGE_COPY_BYTES
}

/* jan_language_record_layout_is_valid verifies fixed pointer-free ABI widths. */
jan_language_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Jan_Language_Scope_Record)) == JAN_LANGUAGE_SCOPE_RECORD_BYTES &&
		u64(size_of(Jan_Language_Command_Record)) == JAN_LANGUAGE_COMMAND_RECORD_BYTES &&
		u64(size_of(Jan_Language_Inspection_Header)) == JAN_LANGUAGE_INSPECTION_HEADER_BYTES &&
		u64(size_of(Jan_Language_Node_Record)) == JAN_LANGUAGE_NODE_RECORD_BYTES &&
		u64(size_of(Jan_Language_Attribute_Record)) == JAN_LANGUAGE_ATTRIBUTE_RECORD_BYTES &&
		u64(size_of(Jan_Language_Recovery_Record)) == JAN_LANGUAGE_RECOVERY_RECORD_BYTES &&
		u64(size_of(Jan_Language_Lint_Record)) == JAN_LANGUAGE_LINT_RECORD_BYTES &&
		u64(size_of(Jan_Language_Limits_Record)) == JAN_LANGUAGE_LIMITS_RECORD_BYTES &&
		u64(size_of(Jan_Language_Provider_Record)) == JAN_LANGUAGE_PROVIDER_RECORD_BYTES &&
		u64(size_of(Jan_Language_Baseline_Record)) == JAN_LANGUAGE_BASELINE_RECORD_BYTES &&
		u64(size_of(Jan_Language_Failure_Record)) == JAN_LANGUAGE_FAILURE_RECORD_BYTES &&
		u64(size_of(Jan_Language_Availability_Record)) == JAN_LANGUAGE_AVAILABILITY_RECORD_BYTES
}
