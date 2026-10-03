// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../document"
import "../editor"

/* JAN_BASELINE_NAME is the accepted Stage 1 compatibility identity. */
JAN_BASELINE_NAME :: "jan-org-9.8.10-v1"
/* JAN_ORG_SYNTAX_VERSION is the accepted document-syntax reference. */
JAN_ORG_SYNTAX_VERSION :: "Org Syntax v2"
/* JAN_SPECIFICATION_COMMIT is the immutable accepted specification revision. */
JAN_SPECIFICATION_COMMIT :: "a0d1feaa414a0236f4fafc035cb890109d76c00a"

/* MAX_JAN_BASELINE_NAME_BYTES bounds one copied baseline identity. */
MAX_JAN_BASELINE_NAME_BYTES :: 64
/* MAX_JAN_SYNTAX_VERSION_BYTES bounds one copied syntax-reference identity. */
MAX_JAN_SYNTAX_VERSION_BYTES :: 64
/* MAX_JAN_COMMIT_BYTES bounds one lowercase hexadecimal specification commit. */
MAX_JAN_COMMIT_BYTES :: 40
/* MAX_JAN_NODE_KIND_BYTES bounds one copied node-kind label. */
MAX_JAN_NODE_KIND_BYTES :: 96
/* MAX_JAN_ATTRIBUTE_NAME_BYTES bounds one copied typed attribute name. */
MAX_JAN_ATTRIBUTE_NAME_BYTES :: 96
/* MAX_JAN_ATTRIBUTE_VALUE_BYTES bounds one copied attribute value. */
MAX_JAN_ATTRIBUTE_VALUE_BYTES :: 4 * KIBIBYTE
/* MAX_JAN_CAPABILITY_NAME_BYTES bounds one copied capability identity. */
MAX_JAN_CAPABILITY_NAME_BYTES :: 128
/* MAX_JAN_AVAILABILITY_DETAIL_BYTES bounds copied unavailable-stage detail. */
MAX_JAN_AVAILABILITY_DETAIL_BYTES :: 256
/* MAX_JAN_NODES bounds typed nodes in one confirmed analysis. */
MAX_JAN_NODES :: u32(1_048_576)
/* MAX_JAN_STRUCTURAL_DEPTH bounds recursive structural containment. */
MAX_JAN_STRUCTURAL_DEPTH :: u16(1_024)
/* MAX_JAN_INLINE_DEPTH bounds recursive inline-object containment. */
MAX_JAN_INLINE_DEPTH :: u16(256)
/* MAX_JAN_ATTRIBUTES_PER_NODE bounds typed attributes on one node. */
MAX_JAN_ATTRIBUTES_PER_NODE :: u16(128)
/* MAX_JAN_INDEX_FACTS bounds source facts in one confirmed analysis. */
MAX_JAN_INDEX_FACTS :: u32(1_048_576)
/* MAX_JAN_DIAGNOSTICS bounds diagnostics in one confirmed analysis. */
MAX_JAN_DIAGNOSTICS :: u32(4_096)
/* MAX_JAN_INCREMENTAL_EDITS bounds normalized edits admitted by one update. */
MAX_JAN_INCREMENTAL_EDITS :: u32(16_384)
/* MAX_JAN_REWRITE_SPLICES bounds minimal splices in one rewrite plan. */
MAX_JAN_REWRITE_SPLICES :: u32(16_384)
/* MAX_JAN_REWRITE_BYTES bounds replacement text and metadata in one rewrite. */
MAX_JAN_REWRITE_BYTES :: 16 * MEBIBYTE
/* MAX_JAN_INSPECTION_BYTES bounds one copied inspection result. */
MAX_JAN_INSPECTION_BYTES :: 1 * MEBIBYTE
/* MAX_JAN_MAINTENANCE_STEP_NS bounds one cooperative analysis step. */
MAX_JAN_MAINTENANCE_STEP_NS :: u64(50_000_000)
/* MAX_JAN_CANDIDATE_NS bounds cumulative work for one analysis candidate. */
MAX_JAN_CANDIDATE_NS :: u64(5_000_000_000)

/* Jan_Baseline_Generation identifies one accepted baseline contract. */
Jan_Baseline_Generation :: distinct u64
/* Jan_Grammar_Generation identifies one exact Jan grammar artifact. */
Jan_Grammar_Generation :: distinct u64
/* Jan_Configuration_Generation identifies one confirmed configuration. */
Jan_Configuration_Generation :: distinct u64
/* Jan_Analysis_Generation identifies one atomically confirmed analysis. */
Jan_Analysis_Generation :: distinct u64
/* Jan_Node_ID identifies one node within an analysis generation. */
Jan_Node_ID :: distinct u32
/* Jan_Index_Fact_ID identifies one source fact within an analysis generation. */
Jan_Index_Fact_ID :: distinct u32
/* Jan_Rewrite_Generation identifies one exact rewrite proposal. */
Jan_Rewrite_Generation :: distinct u64

/* Jan_Baseline_Name is one bounded copied compatibility identity. */
Jan_Baseline_Name :: struct {
	bytes:  [MAX_JAN_BASELINE_NAME_BYTES]u8,
	length: u16,
}

/* Jan_Syntax_Version is one bounded copied syntax-reference identity. */
Jan_Syntax_Version :: struct {
	bytes:  [MAX_JAN_SYNTAX_VERSION_BYTES]u8,
	length: u16,
}

/* Jan_Specification_Commit is one exact copied specification revision. */
Jan_Specification_Commit :: struct {
	bytes:  [MAX_JAN_COMMIT_BYTES]u8,
	length: u8,
}

/* Jan_Node_Kind_Text is one bounded copied public node-kind label. */
Jan_Node_Kind_Text :: struct {
	bytes:  [MAX_JAN_NODE_KIND_BYTES]u8,
	length: u16,
}

/* Jan_Attribute_Name is one bounded copied typed attribute name. */
Jan_Attribute_Name :: struct {
	bytes:  [MAX_JAN_ATTRIBUTE_NAME_BYTES]u8,
	length: u16,
}

/* Jan_Attribute_Value is one bounded copied raw or normalized attribute value. */
Jan_Attribute_Value :: struct {
	bytes:  [MAX_JAN_ATTRIBUTE_VALUE_BYTES]u8,
	length: u16,
}

/* Jan_Capability_Name is one bounded copied stable semantic identity. */
Jan_Capability_Name :: struct {
	bytes:  [MAX_JAN_CAPABILITY_NAME_BYTES]u8,
	length: u16,
}

/* Jan_Availability_Detail is copied explanatory future-stage state. */
Jan_Availability_Detail :: struct {
	bytes:  [MAX_JAN_AVAILABILITY_DETAIL_BYTES]u8,
	length: u16,
}

/* Jan_Baseline_Identity fixes compatibility and specification provenance. */
Jan_Baseline_Identity :: struct {
	generation:           Jan_Baseline_Generation,
	name:                 Jan_Baseline_Name,
	syntax_version:       Jan_Syntax_Version,
	specification_commit: Jan_Specification_Commit,
}

/* Jan_Configuration_Identity identifies copied confirmed syntax configuration. */
Jan_Configuration_Identity :: struct {
	generation: Jan_Configuration_Generation,
	digest:     [32]u8,
}

/* Jan_Node_Layer distinguishes structural, inline, preserved, and recovery ownership. */
Jan_Node_Layer :: enum u8 {
	Invalid,
	Structural,
	Inline,
	Preserved,
	Recovery,
}

/* Jan_Node_Kind is the complete Stage 1 source-form vocabulary. */
Jan_Node_Kind :: enum u8 {
	Invalid,
	Document_Root,
	Zeroth_Section,
	Heading,
	Section,
	Center_Block,
	Quote_Block,
	Special_Block,
	Drawer,
	Property_Drawer,
	Dynamic_Block,
	Footnote_Definition,
	Inline_Task,
	List_Item,
	Plain_List,
	Pipe_Table,
	Table_Provider_Form,
	Source_Block,
	Example_Block,
	Export_Block,
	Comment_Block,
	Lesser_Block,
	Clock,
	Diary_Expression,
	Planning_Line,
	Line_Comment,
	Fixed_Width_Area,
	Horizontal_Rule,
	Keyword,
	Affiliated_Keyword,
	Latex_Environment,
	Node_Property,
	Paragraph,
	Table_Row,
	Table_Separator_Row,
	Entity,
	Special_Symbol,
	Latex_Fragment,
	Export_Snippet,
	Named_Footnote_Reference,
	Inline_Footnote_Reference,
	Anonymous_Footnote_Reference,
	Citation,
	Citation_Reference,
	Inline_Call,
	Inline_Source,
	Explicit_Line_Break,
	Radio_Link,
	Plain_Link,
	Angle_Link,
	Regular_Link,
	Macro,
	Target,
	Radio_Target,
	Percentage_Cookie,
	Fraction_Cookie,
	Subscript,
	Superscript,
	Table_Cell,
	Active_Timestamp,
	Inactive_Timestamp,
	Diary_Timestamp,
	Point_Timestamp,
	Timestamp_Range,
	Repeating_Timestamp,
	Delayed_Timestamp,
	Bold_Markup,
	Italic_Markup,
	Underline_Markup,
	Verbatim_Markup,
	Code_Markup,
	Strike_Through_Markup,
	Plain_Text,
	Preserved_Whitespace,
	Recovery,
}

/* Jan_Attribute_Kind identifies the copied interpretation of one lexical field. */
Jan_Attribute_Kind :: enum u8 {
	Invalid,
	Raw,
	Text,
	Boolean,
	Integer,
	Range,
	Timestamp_Part,
	Regular_Expression,
	Availability,
}

/* Jan_Recovery_Code identifies deterministic malformed-source ownership. */
Jan_Recovery_Code :: enum u8 {
	Invalid,
	Malformed,
	Unterminated,
	Context_Invalid,
	Ambiguous,
	Limited,
}

/* Jan_Index_Kind identifies a revision-bound source-fact collection. */
Jan_Index_Kind :: enum u8 {
	Invalid,
	Heading,
	Task_State,
	Priority,
	Tag,
	Property,
	Identifier,
	Name,
	Target,
	Radio_Target,
	Link,
	Timestamp,
	Planning,
	Clock,
	Footnote,
	Citation,
	Bibliography,
	Table,
	Formula,
	Block,
	Call,
	Result,
	Code_Reference,
	Affiliated_Keyword,
	File_Local_Setting,
	Lint_Fact,
	Recovery_Region,
}

/* Jan_Availability_Class reports how one capability becomes operational. */
Jan_Availability_Class :: enum u8 {
	Invalid,
	Factory_Native,
	Factory_Adapter,
	Configured_Provider,
	Future_Stage,
}

/* Jan_Stage identifies the specification owner of one capability. */
Jan_Stage :: enum u8 {
	Invalid,
	Document_Language,
	Structured_Editing,
	Planning_And_Agenda,
	Computable_Documents,
	Export_Publishing_And_Integration,
}

/* Jan_Analysis_Status reports one exact candidate or confirmed generation. */
Jan_Analysis_Status :: enum u8 {
	Invalid,
	Pending,
	Current,
	Incomplete,
	Cancelled,
	Failed,
}

/* Jan_Failure_Code classifies expected Stage 1 rejection. */
Jan_Failure_Code :: enum u8 {
	None,
	Unsupported,
	Incomplete,
	Malformed,
	Limited,
	Cancelled,
	Stale,
	Provider_Failed,
	Allocation_Failed,
	Invalid_Baseline,
	Invalid_Configuration,
	Invalid_Range,
	Invalid_Node,
	Invalid_Index,
	Invalid_Rewrite,
	Timeout,
}

/* Jan_Operation identifies one Stage 1 action that can reject. */
Jan_Operation :: enum u8 {
	None,
	Analyze,
	Publish,
	Inspect,
	Lint,
	Refresh_Lint,
	Plan_Rewrite,
	Check_Availability,
}

/* Jan_Analysis_Scope binds every copied result to exact source and configuration. */
Jan_Analysis_Scope :: struct {
	buffer_id:            editor.Buffer_ID,
	document_id:          document.Document_ID,
	has_document:         bool,
	source_revision:      editor.Revision,
	language:             Language_Identity,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	parser_generation:    Parser_Generation,
	grammar_generation:   Jan_Grammar_Generation,
	configuration:        Jan_Configuration_Identity,
	baseline:             Jan_Baseline_Identity,
	analysis_generation:  Jan_Analysis_Generation,
}

/* Jan_Source_Range is one half-open canonical UTF-8 range in an exact scope. */
Jan_Source_Range :: struct {
	scope: Jan_Analysis_Scope,
	start: editor.Byte_Offset,
	end:   editor.Byte_Offset,
}

/* Jan_Node_Record is one copied pointer-free syntax node. */
Jan_Node_Record :: struct {
	id:              Jan_Node_ID,
	parent_id:       Jan_Node_ID,
	layer:           Jan_Node_Layer,
	kind:            Jan_Node_Kind,
	kind_text:       Jan_Node_Kind_Text,
	structural_depth: u16,
	inline_depth:    u16,
	range:           Jan_Source_Range,
	attribute_count: u16,
}

/* Jan_Attribute_Record is one copied typed lexical field. */
Jan_Attribute_Record :: struct {
	node_id: Jan_Node_ID,
	kind:    Jan_Attribute_Kind,
	name:    Jan_Attribute_Name,
	range:   Jan_Source_Range,
	value:   Jan_Attribute_Value,
}

/* Jan_Recovery_Record identifies bounded malformed-source ownership. */
Jan_Recovery_Record :: struct {
	node_id: Jan_Node_ID,
	code:    Jan_Recovery_Code,
	range:   Jan_Source_Range,
}

/* Jan_Index_Fact is one copied source fact derived from the same analysis. */
Jan_Index_Fact :: struct {
	id:      Jan_Index_Fact_ID,
	kind:    Jan_Index_Kind,
	node_id: Jan_Node_ID,
	range:   Jan_Source_Range,
}

/* Jan_Rewrite_Edit addresses replacement bytes in one separately owned arena. */
Jan_Rewrite_Edit :: struct {
	range:              Jan_Source_Range,
	replacement_offset: u64,
	replacement_bytes:  u64,
}

/* Jan_Rewrite_Plan_Descriptor identifies one checked minimal splice proposal. */
Jan_Rewrite_Plan_Descriptor :: struct {
	generation:        Jan_Rewrite_Generation,
	scope:             Jan_Analysis_Scope,
	splice_count:      u32,
	replacement_bytes: u64,
	metadata_bytes:    u64,
}

/* Jan_Resource_Usage reports exact logical and retained analysis work. */
Jan_Resource_Usage :: struct {
	source_bytes:       u64,
	retained_bytes:     u64,
	temporary_bytes:    u64,
	nodes:              u32,
	structural_depth:   u16,
	inline_depth:       u16,
	attributes:         u64,
	maximum_attributes: u16,
	index_facts:        u32,
	diagnostics:        u32,
	incremental_edits:  u32,
	work_bytes:         u64,
	elapsed_nanoseconds: u64,
}

/* Jan_Resource_Limits is the complete selected Stage 1 policy. */
Jan_Resource_Limits :: struct {
	source_bytes:                 u64,
	retained_bytes:               u64,
	temporary_bytes:              u64,
	nodes:                        u32,
	structural_depth:             u16,
	inline_depth:                 u16,
	attributes_per_node:          u16,
	index_facts:                  u32,
	diagnostics:                  u32,
	diagnostic_text_bytes:        u64,
	incremental_edits:            u32,
	inspection_bytes:             u64,
	rewrite_splices:              u32,
	rewrite_bytes:                u64,
	cancellation_check_bytes:     u64,
	initial_step_bytes:           u64,
	incremental_step_bytes:       u64,
	maintenance_step_nanoseconds: u64,
	candidate_nanoseconds:        u64,
}

/* DEFAULT_JAN_RESOURCE_LIMITS is the accepted Stage 1 resource policy. */
DEFAULT_JAN_RESOURCE_LIMITS :: Jan_Resource_Limits {
	source_bytes = MAX_ANALYZED_SOURCE_BYTES,
	retained_bytes = MAX_RETAINED_ANALYSIS_BYTES,
	temporary_bytes = MAX_TEMPORARY_BYTES,
	nodes = MAX_JAN_NODES,
	structural_depth = MAX_JAN_STRUCTURAL_DEPTH,
	inline_depth = MAX_JAN_INLINE_DEPTH,
	attributes_per_node = MAX_JAN_ATTRIBUTES_PER_NODE,
	index_facts = MAX_JAN_INDEX_FACTS,
	diagnostics = MAX_JAN_DIAGNOSTICS,
	diagnostic_text_bytes = MAX_DIAGNOSTIC_BYTES,
	incremental_edits = MAX_JAN_INCREMENTAL_EDITS,
	inspection_bytes = MAX_JAN_INSPECTION_BYTES,
	rewrite_splices = MAX_JAN_REWRITE_SPLICES,
	rewrite_bytes = MAX_JAN_REWRITE_BYTES,
	cancellation_check_bytes = CANCELLATION_CHECK_BYTES,
	initial_step_bytes = INITIAL_WORK_BYTES,
	incremental_step_bytes = INCREMENTAL_WORK_BYTES,
	maintenance_step_nanoseconds = MAX_JAN_MAINTENANCE_STEP_NS,
	candidate_nanoseconds = MAX_JAN_CANDIDATE_NS,
}

/* Jan_Availability_Record reports one copied capability state. */
Jan_Availability_Record :: struct {
	capability: Jan_Capability_Name,
	class:      Jan_Availability_Class,
	owner:      Jan_Stage,
	available:  bool,
	detail:     Jan_Availability_Detail,
}

/* Jan_Failure records one bounded expected rejection. */
Jan_Failure :: struct {
	operation: Jan_Operation,
	code:      Jan_Failure_Code,
	scope:     Jan_Analysis_Scope,
	limit:     u64,
	actual:    u64,
	diagnostic: Diagnostic_Text,
}

/* Jan_Inspection is copied state and never triggers parsing or linting. */
Jan_Inspection :: struct {
	scope:          Jan_Analysis_Scope,
	status:         Jan_Analysis_Status,
	node:           Jan_Node_Record,
	has_node:       bool,
	recovery:       Jan_Recovery_Record,
	has_recovery:   bool,
	usage:          Jan_Resource_Usage,
	limits:         Jan_Resource_Limits,
	latest_failure: Jan_Failure,
}

/* jan_factory_baseline returns the immutable accepted Stage 1 baseline. */
jan_factory_baseline :: proc() -> Jan_Baseline_Identity {
	name: Jan_Baseline_Name
	name.length = u16(copy(name.bytes[:], JAN_BASELINE_NAME))
	syntax_version: Jan_Syntax_Version
	syntax_version.length = u16(copy(syntax_version.bytes[:], JAN_ORG_SYNTAX_VERSION))
	commit: Jan_Specification_Commit
	commit.length = u8(copy(commit.bytes[:], JAN_SPECIFICATION_COMMIT))
	return {
		generation = 1,
		name = name,
		syntax_version = syntax_version,
		specification_commit = commit,
	}
}

/* jan_baseline_identity_is_valid checks exact accepted compatibility provenance. */
jan_baseline_identity_is_valid :: proc(baseline: Jan_Baseline_Identity) -> bool {
	return baseline.generation != Jan_Baseline_Generation(0) &&
		jan_bounded_text_matches(baseline.name.bytes, baseline.name.length, JAN_BASELINE_NAME) &&
		jan_bounded_text_matches(
			baseline.syntax_version.bytes,
			baseline.syntax_version.length,
			JAN_ORG_SYNTAX_VERSION,
		) &&
		jan_bounded_text_matches(
			baseline.specification_commit.bytes,
			baseline.specification_commit.length,
			JAN_SPECIFICATION_COMMIT,
		)
}

/* jan_analysis_scope_is_valid checks every exact source and generation identity. */
jan_analysis_scope_is_valid :: proc(scope: Jan_Analysis_Scope) -> bool {
	return scope.buffer_id != editor.Buffer_ID(0) &&
		scope.has_document == (scope.document_id != document.Document_ID(0)) &&
		language_identity_is_valid(scope.language) &&
		scope.provider.registry_id != Registry_ID(0) &&
		scope.provider.language_id == scope.language.id &&
		scope.provider.provider_id != Provider_ID(0) &&
		scope.provider.provider_generation != Provider_Generation(0) &&
		scope.selection_generation != Selection_Generation(0) &&
		scope.parser_generation != Parser_Generation(0) &&
		scope.grammar_generation != Jan_Grammar_Generation(0) &&
		scope.configuration.generation != Jan_Configuration_Generation(0) &&
		jan_digest_is_present(scope.configuration.digest) &&
		jan_baseline_identity_is_valid(scope.baseline) &&
		scope.analysis_generation != Jan_Analysis_Generation(0)
}

/* jan_source_range_is_valid checks one ordered range within an exact source. */
jan_source_range_is_valid :: proc(source_range: Jan_Source_Range, source_bytes: u64) -> bool {
	return jan_analysis_scope_is_valid(source_range.scope) &&
		source_range.start <= source_range.end && u64(source_range.end) <= source_bytes
}

/* jan_node_kind_is_valid checks the closed Stage 1 syntax vocabulary. */
jan_node_kind_is_valid :: proc(kind: Jan_Node_Kind) -> bool {
	return kind >= .Document_Root && kind <= .Recovery
}

/* jan_node_record_is_valid checks identity, ownership, depth, attributes, and range. */
jan_node_record_is_valid :: proc(
	node: Jan_Node_Record,
	source_bytes: u64,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
) -> bool {
	if !jan_resource_limits_are_valid(limits) || node.id == Jan_Node_ID(0) ||
	   node.parent_id == node.id || node.layer <= .Invalid || node.layer > .Recovery ||
	   !jan_node_kind_is_valid(node.kind) || node.kind_text.length == 0 ||
	   node.kind_text.length > MAX_JAN_NODE_KIND_BYTES ||
	   node.structural_depth > limits.structural_depth ||
	   node.inline_depth > limits.inline_depth ||
	   node.attribute_count > limits.attributes_per_node ||
	   !jan_source_range_is_valid(node.range, source_bytes) {
		return false
	}
	if node.kind == .Recovery do return node.layer == .Recovery
	if node.kind == .Preserved_Whitespace do return node.layer == .Preserved
	return true
}

/* jan_attribute_record_is_valid checks one typed copied lexical field. */
jan_attribute_record_is_valid :: proc(
	attribute: Jan_Attribute_Record,
	source_bytes: u64,
) -> bool {
	return attribute.node_id != Jan_Node_ID(0) &&
		attribute.kind >= .Raw && attribute.kind <= .Availability &&
		attribute.name.length > 0 && attribute.name.length <= MAX_JAN_ATTRIBUTE_NAME_BYTES &&
		u64(attribute.value.length) <= MAX_JAN_ATTRIBUTE_VALUE_BYTES &&
		jan_source_range_is_valid(attribute.range, source_bytes)
}

/* jan_recovery_record_is_valid checks bounded malformed-source ownership. */
jan_recovery_record_is_valid :: proc(recovery: Jan_Recovery_Record, source_bytes: u64) -> bool {
	return recovery.node_id != Jan_Node_ID(0) &&
		recovery.code >= .Malformed && recovery.code <= .Limited &&
		jan_source_range_is_valid(recovery.range, source_bytes)
}

/* jan_index_fact_is_valid checks one revision-bound source fact. */
jan_index_fact_is_valid :: proc(fact: Jan_Index_Fact, source_bytes: u64) -> bool {
	return fact.id != Jan_Index_Fact_ID(0) && fact.node_id != Jan_Node_ID(0) &&
		fact.kind >= .Heading && fact.kind <= .Recovery_Region &&
		jan_source_range_is_valid(fact.range, source_bytes)
}

/* jan_rewrite_plan_descriptor_is_valid checks exact generation and hard bounds. */
jan_rewrite_plan_descriptor_is_valid :: proc(
	plan: Jan_Rewrite_Plan_Descriptor,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
) -> bool {
	return jan_resource_limits_are_valid(limits) &&
		plan.generation != Jan_Rewrite_Generation(0) &&
		jan_analysis_scope_is_valid(plan.scope) &&
		plan.splice_count > 0 && plan.splice_count <= limits.rewrite_splices &&
		plan.replacement_bytes <= limits.rewrite_bytes &&
		plan.metadata_bytes <= limits.rewrite_bytes &&
		plan.replacement_bytes <= limits.rewrite_bytes - plan.metadata_bytes
}

/* jan_resource_limits_are_valid checks selected limits against inherited ceilings. */
jan_resource_limits_are_valid :: proc(limits: Jan_Resource_Limits) -> bool {
	return limits.source_bytes > 0 && limits.source_bytes <= MAX_ANALYZED_SOURCE_BYTES &&
		limits.retained_bytes >= limits.source_bytes &&
		limits.retained_bytes <= MAX_RETAINED_ANALYSIS_BYTES &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		limits.nodes > 0 && limits.nodes <= MAX_JAN_NODES &&
		limits.structural_depth > 0 && limits.structural_depth <= MAX_JAN_STRUCTURAL_DEPTH &&
		limits.inline_depth > 0 && limits.inline_depth <= MAX_JAN_INLINE_DEPTH &&
		limits.attributes_per_node > 0 &&
		limits.attributes_per_node <= MAX_JAN_ATTRIBUTES_PER_NODE &&
		limits.index_facts > 0 && limits.index_facts <= MAX_JAN_INDEX_FACTS &&
		limits.diagnostics > 0 && limits.diagnostics <= MAX_JAN_DIAGNOSTICS &&
		limits.diagnostic_text_bytes > 0 && limits.diagnostic_text_bytes <= MAX_DIAGNOSTIC_BYTES &&
		limits.incremental_edits > 0 && limits.incremental_edits <= MAX_JAN_INCREMENTAL_EDITS &&
		limits.inspection_bytes > 0 && limits.inspection_bytes <= MAX_JAN_INSPECTION_BYTES &&
		limits.rewrite_splices > 0 && limits.rewrite_splices <= MAX_JAN_REWRITE_SPLICES &&
		limits.rewrite_bytes > 0 && limits.rewrite_bytes <= MAX_JAN_REWRITE_BYTES &&
		limits.cancellation_check_bytes > 0 &&
		limits.cancellation_check_bytes <= CANCELLATION_CHECK_BYTES &&
		limits.initial_step_bytes > 0 && limits.initial_step_bytes <= INITIAL_WORK_BYTES &&
		limits.incremental_step_bytes > 0 &&
		limits.incremental_step_bytes <= INCREMENTAL_WORK_BYTES &&
		limits.incremental_step_bytes <= limits.initial_step_bytes &&
		limits.maintenance_step_nanoseconds > 0 &&
		limits.maintenance_step_nanoseconds <= MAX_JAN_MAINTENANCE_STEP_NS &&
		limits.candidate_nanoseconds >= limits.maintenance_step_nanoseconds &&
		limits.candidate_nanoseconds <= MAX_JAN_CANDIDATE_NS
}

/* jan_resource_usage_is_within checks logical work against one selected policy. */
jan_resource_usage_is_within :: proc(
	usage: Jan_Resource_Usage,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
) -> bool {
	return jan_resource_limits_are_valid(limits) &&
		usage.source_bytes <= limits.source_bytes &&
		usage.retained_bytes <= limits.retained_bytes &&
		usage.temporary_bytes <= limits.temporary_bytes &&
		usage.nodes <= limits.nodes &&
		usage.structural_depth <= limits.structural_depth &&
		usage.inline_depth <= limits.inline_depth &&
		usage.maximum_attributes <= limits.attributes_per_node &&
		usage.index_facts <= limits.index_facts &&
		usage.diagnostics <= limits.diagnostics &&
		usage.incremental_edits <= limits.incremental_edits &&
		usage.elapsed_nanoseconds <= limits.candidate_nanoseconds
}

/* jan_availability_record_is_valid checks stage ownership and availability class. */
jan_availability_record_is_valid :: proc(record: Jan_Availability_Record) -> bool {
	if record.capability.length == 0 ||
	   record.capability.length > MAX_JAN_CAPABILITY_NAME_BYTES ||
	   record.class <= .Invalid || record.class > .Future_Stage ||
	   record.owner <= .Invalid || record.owner > .Export_Publishing_And_Integration ||
	   record.detail.length > MAX_JAN_AVAILABILITY_DETAIL_BYTES {
		return false
	}
	if record.class == .Future_Stage {
		return !record.available && record.owner != .Document_Language && record.detail.length > 0
	}
	if record.class == .Factory_Native do return record.available
	return record.class == .Factory_Adapter || record.class == .Configured_Provider
}

@(private)
jan_bounded_text_matches :: proc(bytes: [$N]u8, length: $T, expected: string) -> bool {
	if u64(length) != u64(len(expected)) || u64(length) > N do return false
	for value, index in expected {
		if bytes[index] != u8(value) do return false
	}
	return true
}

@(private)
jan_digest_is_present :: proc(digest: [32]u8) -> bool {
	for value in digest {
		if value != 0 do return true
	}
	return false
}
