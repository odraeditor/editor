// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language owns bounded language-analysis identities, provider
// selection, exact-revision syntax records, resource policy, and failures.
package language

import "../document"
import "../editor"

/* KIBIBYTE is the binary byte unit used by language-analysis limits. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_LANGUAGES bounds registered semantic language identities. */
MAX_LANGUAGES :: 32
/* MAX_LANGUAGE_SELECTORS bounds exact filenames and suffixes per definition. */
MAX_LANGUAGE_SELECTORS :: 16
/* MAX_LANGUAGE_EXACT_FILENAMES bounds exact basenames per definition. */
MAX_LANGUAGE_EXACT_FILENAMES :: 8
/* MAX_LANGUAGE_SUFFIXES bounds filename suffixes per definition. */
MAX_LANGUAGE_SUFFIXES :: 8
/* MAX_LANGUAGE_ASSOCIATIONS bounds selectors in one confirmed catalog. */
MAX_LANGUAGE_ASSOCIATIONS :: MAX_LANGUAGES * MAX_LANGUAGE_SELECTORS
/* MAX_PROVIDERS bounds factory and native replacement providers. */
MAX_PROVIDERS :: 64
/* MAX_LIVE_SELECTIONS bounds buffer-owned language-analysis responsibilities. */
MAX_LIVE_SELECTIONS :: 128
/* MAX_RETAINED_TREES bounds confirmed and candidate parse ownership. */
MAX_RETAINED_TREES :: 256
/* MAX_LANGUAGE_NAME_BYTES bounds one copied semantic language name. */
MAX_LANGUAGE_NAME_BYTES :: 64
/* MAX_LANGUAGE_DISPLAY_NAME_BYTES bounds one copied display name. */
MAX_LANGUAGE_DISPLAY_NAME_BYTES :: 96
/* MAX_LANGUAGE_SCOPE_BYTES bounds one copied contribution scope. */
MAX_LANGUAGE_SCOPE_BYTES :: 256
/* MAX_PROVIDER_NAME_BYTES bounds one copied provider name. */
MAX_PROVIDER_NAME_BYTES :: 96
/* MAX_PARSER_NAME_BYTES bounds one copied parser identity. */
MAX_PARSER_NAME_BYTES :: 96
/* MAX_PROVENANCE_BYTES bounds one copied dependency provenance record. */
MAX_PROVENANCE_BYTES :: 256
/* MAX_ASSOCIATION_BYTES bounds one copied filename association. */
MAX_ASSOCIATION_BYTES :: 32
/* MAX_DIAGNOSTIC_BYTES bounds one copied contained failure diagnostic. */
MAX_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
/* MAX_QUERY_BYTES bounds retained query source per provider. */
MAX_QUERY_BYTES :: 1 * MEBIBYTE
/* MAX_CAPTURES bounds foreign captures admitted by one query pass. */
MAX_CAPTURES :: 131_072
/* MAX_SYNTAX_SPANS bounds normalized spans in one syntax snapshot. */
MAX_SYNTAX_SPANS :: 65_536
/* MAX_ANALYZED_SOURCE_BYTES bounds one retained source revision. */
MAX_ANALYZED_SOURCE_BYTES :: 64 * MEBIBYTE
/* MAX_RETAINED_ANALYSIS_BYTES bounds aggregate retained analysis storage. */
MAX_RETAINED_ANALYSIS_BYTES :: 512 * MEBIBYTE
/* MAX_TEMPORARY_BYTES bounds temporary storage for one admitted analysis job. */
MAX_TEMPORARY_BYTES :: 128 * MEBIBYTE
/* MAX_PENDING_WORK bounds admitted analysis jobs. */
MAX_PENDING_WORK :: 128
/* MAX_RETAINED_STALE_WORK bounds superseded work retained per selection. */
MAX_RETAINED_STALE_WORK :: 1
/* MAX_REFRESH_REQUESTS_PER_SELECTION bounds coalesced refresh demand. */
MAX_REFRESH_REQUESTS_PER_SELECTION :: 1
/* INITIAL_WORK_BYTES is the progress budget for initial parsing. */
INITIAL_WORK_BYTES :: 8 * MEBIBYTE
/* INCREMENTAL_WORK_BYTES is the progress budget for incremental parsing. */
INCREMENTAL_WORK_BYTES :: 2 * MEBIBYTE
/* REFRESH_WORK_BYTES is the progress budget for a complete refresh. */
REFRESH_WORK_BYTES :: MAX_ANALYZED_SOURCE_BYTES
/* MAX_VISIBLE_QUERY_SPANS bounds one visible-range query result. */
MAX_VISIBLE_QUERY_SPANS :: 16_384
/* MAINTENANCE_ITEMS_PER_STEP bounds analysis work consumed per maintenance step. */
MAINTENANCE_ITEMS_PER_STEP :: 8
/* CANCELLATION_CHECK_BYTES bounds parser input between cancellation checks. */
CANCELLATION_CHECK_BYTES :: 64 * KIBIBYTE

/* Language_ID identifies one semantic document language; zero is invalid. */
Language_ID :: distinct u32
/* Language_Generation identifies one exact registered language identity. */
Language_Generation :: distinct u64
/* Registry_ID identifies one live native provider registry. */
Registry_ID :: distinct u32
/* Registry_Generation identifies one exact provider-selection state. */
Registry_Generation :: distinct u64
/* Provider_ID identifies one provider for a registry lifetime. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider lifecycle state. */
Provider_Generation :: distinct u64
/* Selection_Generation identifies one exact buffer language responsibility. */
Selection_Generation :: distinct u64
/* Parser_Generation identifies one exact parser owner. */
Parser_Generation :: distinct u64
/* Tree_Generation identifies one exact retained parse tree. */
Tree_Generation :: distinct u64
/* Query_Generation identifies one exact compiled syntax query. */
Query_Generation :: distinct u64
/* Syntax_Snapshot_Generation identifies one exact normalized span snapshot. */
Syntax_Snapshot_Generation :: distinct u64

/* Language_Name is one bounded copied semantic language name. */
Language_Name :: struct {
	bytes:  [MAX_LANGUAGE_NAME_BYTES]u8,
	length: u16,
}

/* Provider_Name is one bounded copied provider or parser name. */
Provider_Name :: struct {
	bytes:  [MAX_PROVIDER_NAME_BYTES]u8,
	length: u16,
}

/* Parser_Name is one bounded copied parser identity. */
Parser_Name :: struct {
	bytes:  [MAX_PARSER_NAME_BYTES]u8,
	length: u16,
}

/* Provenance_Text is one bounded copied upstream provenance record. */
Provenance_Text :: struct {
	bytes:  [MAX_PROVENANCE_BYTES]u8,
	length: u16,
}

/* Association_Text is one bounded copied filename association. */
Association_Text :: struct {
	bytes:  [MAX_ASSOCIATION_BYTES]u8,
	length: u16,
}

/* Diagnostic_Text is one bounded copied failure explanation. */
Diagnostic_Text :: struct {
	bytes:  [MAX_DIAGNOSTIC_BYTES]u8,
	length: u16,
}

/* Language_Identity is one stable semantic language name and identity. */
Language_Identity :: struct {
	id:         Language_ID,
	generation: Language_Generation,
	name:       Language_Name,
}

/* Association_Source explains why one buffer received a language identity. */
Association_Source :: enum u8 {
	None,
	Factory_Filename_Suffix,
	Native_Request,
}

/* Language_Association copies one language-selection provenance record. */
Language_Association :: struct {
	language: Language_Identity,
	source:   Association_Source,
	value:    Association_Text,
}

/* Provider_Kind distinguishes the maintained factory from native replacements. */
Provider_Kind :: enum u8 {
	Invalid,
	Factory,
	Native,
}

/* Provider_State reports one provider lifecycle state. */
Provider_State :: enum u8 {
	Invalid,
	Registered,
	Confirmed,
	Failed,
	Closed,
}

/* Provider_Capability names semantic analysis behavior without frontend authority. */
Provider_Capability :: enum u8 {
	Initial_Parse,
	Incremental_Parse,
	Visible_Query,
	Syntax_Roles,
	Structural_Syntax,
	Symbols,
}

/* Provider_Capabilities is the bounded set admitted for one provider. */
Provider_Capabilities :: bit_set[Provider_Capability; u8]

/* Provider_Handle is one checked pointer-free provider identity. */
Provider_Handle :: struct {
	registry_id:         Registry_ID,
	language_id:         Language_ID,
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
}

/* Provider_Descriptor is a copied bounded provider inspection record. */
Provider_Descriptor :: struct {
	handle:             Provider_Handle,
	kind:               Provider_Kind,
	state:              Provider_State,
	name:               Provider_Name,
	parser_name:        Parser_Name,
	grammar_abi:        u32,
	capabilities:       Provider_Capabilities,
	query_generation:   Query_Generation,
	provenance:         Provenance_Text,
}

/* Selection_State reports the active provider-selection disposition. */
Selection_State :: enum u8 {
	Invalid,
	Factory,
	Replacement,
	Disabled,
	Restored,
}

/* Provider_Selection copies one exact single-active-provider state. */
Provider_Selection :: struct {
	registry_id:         Registry_ID,
	registry_generation: Registry_Generation,
	language:            Language_Identity,
	state:               Selection_State,
	active:              Provider_Handle,
	factory:             Provider_Handle,
}

/* Parser_Lifecycle reports the owned parser state for one selected buffer. */
Parser_Lifecycle :: enum u8 {
	Uninitialized,
	Ready,
	Parsing,
	Failed,
	Closed,
}

/* Analysis_Status reports whether syntax is usable for the current revision. */
Analysis_Status :: enum u8 {
	Plain_Text,
	Pending,
	Current,
	Cancelled,
	Failed,
}

/* Syntax_Role is the stable frontend-independent semantic role vocabulary. */
Syntax_Role :: enum u8 {
	Invalid,
	Attribute,
	Boolean,
	Comment,
	Constant,
	Constructor,
	Function,
	Function_Builtin,
	Keyword,
	Label,
	Number,
	Operator,
	Punctuation,
	String,
	Type,
	Variable,
	Variable_Parameter,
}

/* Resource_Usage reports exact retained, temporary, and logical analysis work. */
Resource_Usage :: struct {
	retained_source_bytes: u64,
	retained_tree_bytes:   u64,
	retained_query_bytes:  u64,
	retained_span_bytes:   u64,
	temporary_bytes:       u64,
	captures:              u32,
	spans:                 u32,
	work_bytes:            u64,
}

/* Work_Kind identifies one bounded pending analysis operation. */
Work_Kind :: enum u8 {
	Invalid,
	Initial,
	Incremental,
	Refresh,
	Visible_Query,
}

/* Pending_Work copies current scheduled analysis demand. */
Pending_Work :: struct {
	kind:                 Work_Kind,
	selection_generation: Selection_Generation,
	source_revision:      editor.Revision,
	work_bytes:           u64,
	cancellation_checks:  u32,
	refresh_requested:    bool,
}

/* Parse_Snapshot identifies one exact revision-owned parser result. */
Parse_Snapshot :: struct {
	buffer_id:            editor.Buffer_ID,
	source_revision:      editor.Revision,
	language:             Language_Identity,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	parser_generation:    Parser_Generation,
	tree_generation:      Tree_Generation,
	query_generation:     Query_Generation,
	status:               Analysis_Status,
	usage:                Resource_Usage,
}

/* Syntax_Span is one normalized exact-revision semantic range. */
Syntax_Span :: struct {
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	role:            Syntax_Role,
	precedence:      u16,
	provider:        Provider_Handle,
	source_revision: editor.Revision,
}

/* Syntax_Snapshot identifies one complete normalized span publication. */
Syntax_Snapshot :: struct {
	generation:           Syntax_Snapshot_Generation,
	buffer_id:            editor.Buffer_ID,
	source_revision:      editor.Revision,
	language:             Language_Identity,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	parser_generation:    Parser_Generation,
	query_generation:     Query_Generation,
	span_count:           u32,
	structural_count:     u32,
	usage:                Resource_Usage,
}

/* Operation identifies one language-analysis action that can fail. */
Operation :: enum u8 {
	None,
	Initialize,
	Register,
	Confirm,
	Select,
	Replace,
	Disable,
	Restore,
	Fail,
	Inspect,
	Publish_Parse,
	Publish_Syntax,
	Query_Structure,
	Plan_Indentation,
	Inspect_Symbols,
	Query_Symbols,
	Publish_Symbols,
	Schedule,
	Cancel,
	Prepare_Provider,
	Load_Grammar,
	Compile_Queries,
	Close,
}

/* Failure_Code classifies expected language-analysis rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Language,
	Invalid_Association,
	Invalid_Provider,
	Stale_Provider,
	Duplicate_Provider,
	Provider_Limit,
	Provider_Name_Limit,
	Parser_Name_Limit,
	Provenance_Limit,
	Provider_Not_Confirmed,
	Provider_Not_Active,
	Factory_Provider_Required,
	Stale_Selection,
	Selection_Disabled,
	Invalid_Grammar_Artifact,
	Invalid_Query_Artifact,
	Invalid_Resource_Profile,
	Duplicate_Query_Kind,
	Duplicate_Capture_Mapping,
	Native_Grammar_Unauthorized,
	Artifact_Missing,
	Artifact_Size_Mismatch,
	Artifact_Digest_Mismatch,
	Unsupported_Platform,
	Grammar_Symbol_Missing,
	Grammar_Language_Version_Incompatible,
	Library_Load_Failed,
	Library_Unload_Failed,
	Grammar_ABI_Incompatible,
	Invalid_Query,
	Unknown_Capture,
	Invalid_Capture_Mapping,
	Parser_Initialization,
	Cancelled,
	Timeout,
	Depth_Limit,
	Invalid_Transaction,
	Unavailable_Base_Snapshot,
	Invalid_UTF8_Boundary,
	Structural_Capability_Unavailable,
	No_Structural_Target,
	Symbol_Capability_Unavailable,
	Invalid_Symbol_Query,
	No_Symbol,
	Ambiguous_Symbol,
	Stale_Symbol,
	Symbol_Limit,
	Symbol_Name_Limit,
	Symbol_Container_Limit,
	Symbol_Annotation_Limit,
	Symbol_Hierarchy_Limit,
	Symbol_Memory_Limit,
	Node_Kind_Limit,
	Node_Limit,
	Line_Limit,
	Prepared_Text_Limit,
	Syntax_Error_Region,
	Source_Limit,
	Query_Limit,
	Capture_Limit,
	Span_Limit,
	Snapshot_Limit,
	Pending_Work_Limit,
	Retained_Memory_Limit,
	Temporary_Memory_Limit,
	Work_Limit,
	Generation_Limit,
	Allocation,
}

/* Failure records one bounded expected rejection without borrowed storage. */
Failure :: struct {
	operation:            Operation,
	code:                 Failure_Code,
	language_id:          Language_ID,
	provider:             Provider_Handle,
	selection_generation: Selection_Generation,
	source_revision:      editor.Revision,
	limit:                u64,
	actual:               u64,
	diagnostic:           Diagnostic_Text,
}

/* Policy is the selected bounded factory language-analysis policy. */
Policy :: struct {
	languages:                     u16,
	providers:                     u16,
	live_selections:               u16,
	retained_trees:                u16,
	query_bytes:                   u64,
	captures:                      u32,
	spans:                         u32,
	analyzed_source_bytes:         u64,
	retained_analysis_bytes:       u64,
	temporary_bytes:               u64,
	pending_work:                  u16,
	retained_stale_work:           u8,
	refresh_requests_per_selection: u8,
	initial_work_bytes:            u64,
	incremental_work_bytes:        u64,
	refresh_work_bytes:            u64,
	visible_query_spans:           u32,
	maintenance_items_per_step:    u16,
	cancellation_check_bytes:      u64,
}

/* DEFAULT_POLICY is the measured production contract for syntax analysis. */
DEFAULT_POLICY :: Policy {
	languages = MAX_LANGUAGES,
	providers = MAX_PROVIDERS,
	live_selections = MAX_LIVE_SELECTIONS,
	retained_trees = MAX_RETAINED_TREES,
	query_bytes = MAX_QUERY_BYTES,
	captures = MAX_CAPTURES,
	spans = MAX_SYNTAX_SPANS,
	analyzed_source_bytes = MAX_ANALYZED_SOURCE_BYTES,
	retained_analysis_bytes = MAX_RETAINED_ANALYSIS_BYTES,
	temporary_bytes = MAX_TEMPORARY_BYTES,
	pending_work = MAX_PENDING_WORK,
	retained_stale_work = MAX_RETAINED_STALE_WORK,
	refresh_requests_per_selection = MAX_REFRESH_REQUESTS_PER_SELECTION,
	initial_work_bytes = INITIAL_WORK_BYTES,
	incremental_work_bytes = INCREMENTAL_WORK_BYTES,
	refresh_work_bytes = REFRESH_WORK_BYTES,
	visible_query_spans = MAX_VISIBLE_QUERY_SPANS,
	maintenance_items_per_step = MAINTENANCE_ITEMS_PER_STEP,
	cancellation_check_bytes = CANCELLATION_CHECK_BYTES,
}

/* Language_Selection_Inspection is one complete copied buffer-owned state view. */
Language_Selection_Inspection :: struct {
	buffer_id:            editor.Buffer_ID,
	document_id:          document.Document_ID,
	has_document:         bool,
	association:          Language_Association,
	selection:            Provider_Selection,
	selection_generation: Selection_Generation,
	confirmed_revision:   editor.Revision,
	parser_lifecycle:     Parser_Lifecycle,
	analysis_status:      Analysis_Status,
	parse_snapshot:       Parse_Snapshot,
	syntax_snapshot:      Syntax_Snapshot,
	usage:                Resource_Usage,
	pending:              Pending_Work,
	latest_failure:       Failure,
}

/* syntax_role_is_valid reports whether a value is in the stable role vocabulary. */
syntax_role_is_valid :: proc(role: Syntax_Role) -> bool {
	return role >= .Attribute && role <= .Variable_Parameter
}

/* syntax_span_is_valid checks one non-empty exact-revision UTF-8 byte range. */
syntax_span_is_valid :: proc(span: Syntax_Span, source_bytes: u64) -> bool {
	return syntax_role_is_valid(span.role) && span.provider.provider_id != Provider_ID(0) &&
		u64(span.start) < u64(span.end) && u64(span.end) <= source_bytes
}

/* policy_is_valid checks the selected nonzero bounds and subordinate limits. */
policy_is_valid :: proc(policy: Policy) -> bool {
	return policy.languages > 0 && policy.languages <= MAX_LANGUAGES &&
		policy.providers > 0 && policy.providers <= MAX_PROVIDERS &&
		policy.live_selections > 0 && policy.live_selections <= MAX_LIVE_SELECTIONS &&
		u32(policy.retained_trees) >= u32(policy.live_selections) * 2 &&
		policy.retained_trees <= MAX_RETAINED_TREES &&
		policy.query_bytes > 0 && policy.query_bytes <= MAX_QUERY_BYTES &&
		policy.captures > 0 && policy.captures <= MAX_CAPTURES &&
		policy.spans > 0 && policy.spans <= MAX_SYNTAX_SPANS &&
		policy.analyzed_source_bytes > 0 && policy.analyzed_source_bytes <= MAX_ANALYZED_SOURCE_BYTES &&
		policy.retained_analysis_bytes >= policy.analyzed_source_bytes &&
		policy.retained_analysis_bytes <= MAX_RETAINED_ANALYSIS_BYTES &&
		policy.temporary_bytes > 0 && policy.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		policy.pending_work > 0 && policy.pending_work <= MAX_PENDING_WORK &&
		policy.retained_stale_work <= MAX_RETAINED_STALE_WORK &&
		policy.refresh_requests_per_selection <= MAX_REFRESH_REQUESTS_PER_SELECTION &&
		policy.initial_work_bytes > 0 && policy.initial_work_bytes <= policy.analyzed_source_bytes &&
		policy.incremental_work_bytes > 0 && policy.incremental_work_bytes <= policy.initial_work_bytes &&
		policy.refresh_work_bytes == policy.analyzed_source_bytes &&
		policy.visible_query_spans > 0 && policy.visible_query_spans <= policy.spans &&
		policy.maintenance_items_per_step > 0 &&
		policy.cancellation_check_bytes > 0 &&
		policy.cancellation_check_bytes <= policy.incremental_work_bytes
}
