// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package jan_planning owns copied planning, time, agenda, and recovery contracts.
package jan_planning

import "../language"
import "core:unicode/utf8"

/* PLANNING_SCHEMA_VERSION identifies the durable Planning and Agenda record family. */
PLANNING_SCHEMA_VERSION :: u16(1)
/* MAX_SEMANTIC_TARGETS bounds one planning operation. */
MAX_SEMANTIC_TARGETS :: u32(4_096)
/* MAX_SOURCE_DOCUMENTS bounds one confirmed agenda source generation. */
MAX_SOURCE_DOCUMENTS :: u32(1_024)
/* MAX_AGENDA_ENTRIES bounds one agenda result. */
MAX_AGENDA_ENTRIES :: u32(65_536)
/* MAX_CAPTURE_CANDIDATES bounds one capture selection. */
MAX_CAPTURE_CANDIDATES :: u32(16_384)
/* MAX_REFILE_CANDIDATES bounds one refile destination selection. */
MAX_REFILE_CANDIDATES :: u32(16_384)
/* MAX_ATTACHMENT_OUTCOMES bounds one attachment operation. */
MAX_ATTACHMENT_OUTCOMES :: u32(4_096)
/* MAX_FEED_SOURCES bounds one feed refresh. */
MAX_FEED_SOURCES :: u16(256)
/* MAX_FEED_ENTRIES bounds one feed result. */
MAX_FEED_ENTRIES :: u32(16_384)
/* MAX_COPIED_TEXT_BYTES bounds copied agenda or capture text. */
MAX_COPIED_TEXT_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_DERIVED_STATE_BYTES bounds process-wide agenda and feed state. */
MAX_DERIVED_STATE_BYTES :: u64(64 * 1_024 * 1_024)
/* CANCELLATION_CHECK_ENTRIES bounds work between cancellation checks. */
CANCELLATION_CHECK_ENTRIES :: u32(4_096)

/* MAX_WORKFLOWS bounds one confirmed configuration. */
MAX_WORKFLOWS :: u16(64)
/* MAX_WORKFLOW_STATES bounds all workflow states in one configuration. */
MAX_WORKFLOW_STATES :: u16(256)
/* MAX_SOURCE_SETS bounds configured agenda source sets. */
MAX_SOURCE_SETS :: u16(64)
/* MAX_CAPTURE_DEFINITIONS bounds configured capture definitions. */
MAX_CAPTURE_DEFINITIONS :: u16(256)
/* MAX_AGENDA_DEFINITIONS bounds configured agenda definitions. */
MAX_AGENDA_DEFINITIONS :: u16(256)
/* MAX_CONFIGURATION_BYTES bounds copied planning configuration text. */
MAX_CONFIGURATION_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_IDENTITY_BYTES bounds one stable configured identity. */
MAX_IDENTITY_BYTES :: 96
/* MAX_LABEL_BYTES bounds one configured display label. */
MAX_LABEL_BYTES :: 128
/* MAX_RESOURCE_BYTES bounds one copied resource locator. */
MAX_RESOURCE_BYTES :: 4 * 1_024
/* MAX_TEMPLATE_BYTES bounds one copied capture template. */
MAX_TEMPLATE_BYTES :: 64 * 1_024
/* MAX_QUERY_BYTES bounds one copied agenda query. */
MAX_QUERY_BYTES :: 4 * 1_024

/* Operation_ID identifies one Planning and Agenda request lifetime. */
Operation_ID :: distinct u64
/* Configuration_Generation identifies one confirmed planning configuration. */
Configuration_Generation :: distinct u64
/* Provider_Generation identifies one confirmed configured-provider set. */
Provider_Generation :: distinct u64
/* Source_Set_ID identifies one confirmed ordered agenda source set. */
Source_Set_ID :: distinct u64
/* Clock_Domain_ID identifies one domain with at most one active clock. */
Clock_Domain_ID :: distinct u64

/* Limits is the complete fixed planning resource policy. */
Limits :: struct {
	semantic_targets:    u32,
	source_documents:    u32,
	agenda_entries:      u32,
	capture_candidates:  u32,
	refile_candidates:   u32,
	attachment_outcomes: u32,
	feed_sources:        u16,
	feed_entries:        u32,
	copied_text_bytes:   u64,
	derived_state_bytes: u64,
}

/* DEFAULT_LIMITS is the accepted Planning and Agenda resource ceiling. */
DEFAULT_LIMITS := Limits {
	semantic_targets = MAX_SEMANTIC_TARGETS,
	source_documents = MAX_SOURCE_DOCUMENTS,
	agenda_entries = MAX_AGENDA_ENTRIES,
	capture_candidates = MAX_CAPTURE_CANDIDATES,
	refile_candidates = MAX_REFILE_CANDIDATES,
	attachment_outcomes = MAX_ATTACHMENT_OUTCOMES,
	feed_sources = MAX_FEED_SOURCES,
	feed_entries = MAX_FEED_ENTRIES,
	copied_text_bytes = MAX_COPIED_TEXT_BYTES,
	derived_state_bytes = MAX_DERIVED_STATE_BYTES,
}

/* Operation_Kind identifies one Planning and Agenda semantic family. */
Operation_Kind :: enum u8 {
	Invalid,
	Configure,
	Task,
	Metadata,
	Time,
	Refile_Archive,
	Capture,
	Attachment,
	Feed,
	Agenda,
	Recover,
}

/* Lifecycle_State identifies one operation result boundary. */
Lifecycle_State :: enum u8 {
	Invalid,
	Prepared,
	Confirmed,
	Active,
	Completed,
	Cancelled,
	Failed,
	Recovery_Required,
	Closed,
}

/* Failure_Code classifies expected planning rejection without partial publication. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Invalid_Target,
	Stale,
	Unavailable,
	Limited,
	Cancelled,
	Allocation_Failed,
	Malformed,
	Conflict,
	Confirmation_Required,
	Partial,
	Recovery_Required,
}

/* Failure_Field identifies the rejected contract field. */
Failure_Field :: enum u8 {
	None,
	Scope,
	Target,
	Generation,
	Workflow,
	Source_Set,
	Capture,
	Agenda,
	Clock,
	Limit,
	Task,
	Tag,
	Property,
	Column,
	Time,
	Effort,
	Timer,
	Refile,
	Archive,
	Resource,
	Attachment,
	Feed,
}

/* Capability is the closed Planning and Agenda feature inventory. */
Capability :: enum u8 {
	Invalid,
	Tasks,
	Metadata,
	Time,
	Refile_Archive,
	Capture,
	Attachments,
	Feeds,
	Agenda,
}

/* Availability_Class identifies factory and configured implementation ownership. */
Availability_Class :: enum u8 {
	Invalid,
	Factory_Native,
	Factory_Adapter,
	Configured_Provider,
}

/* Availability_State separates declared contracts from operational capabilities. */
Availability_State :: enum u8 {
	Invalid,
	Declared,
	Available,
	Unavailable,
}

/* Availability_Record reports one capability without granting effect authority. */
Availability_Record :: struct {
	capability:          Capability,
	class:               Availability_Class,
	state:               Availability_State,
	provider_generation: Provider_Generation,
}

/* Resource_Key is a bounded copied provider-owned resource key. */
Resource_Key :: struct {
	bytes:  [MAX_RESOURCE_BYTES]u8,
	length: u16,
}

/* Resource_Identity identifies a provider-owned document independently from a path. */
Resource_Identity :: struct {
	provider: u64,
	key:      Resource_Key,
}

/* Scope binds one request to exact analysis, planning, provider, and source-set generations. */
Scope :: struct {
	analysis:                 language.Jan_Analysis_Scope,
	source_bytes:             u64,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	source_set:               Source_Set_ID,
}

/* Semantic_Target is a copied exact-revision Jan target. */
Semantic_Target :: struct {
	node_id: language.Jan_Node_ID,
	kind:    language.Jan_Node_Kind,
	range:   language.Jan_Source_Range,
}

/* Request identifies one bounded operation over copied targets. */
Request :: struct {
	operation_id: Operation_ID,
	kind:         Operation_Kind,
	scope:        Scope,
	targets:      []Semantic_Target,
	limits:       Limits,
}

/* Result reports one attributable operation outcome. */
Result :: struct {
	operation_id:            Operation_ID,
	kind:                    Operation_Kind,
	lifecycle:               Lifecycle_State,
	configuration_generation: Configuration_Generation,
	provider_generation:     Provider_Generation,
	source_count:            u32,
	target_count:            u32,
	result_count:            u32,
	copied_text_bytes:       u64,
	truncated:               bool,
}

/* Failure reports one bounded rejection or partial-effect boundary. */
Failure :: struct {
	operation_id: Operation_ID,
	kind:         Operation_Kind,
	code:         Failure_Code,
	field:        Failure_Field,
	limit:        u64,
	actual:       u64,
	committed:    u32,
	unattempted:  u32,
}

/* Presentation_Role identifies one workflow state's semantic display role. */
Presentation_Role :: enum u8 {
	Invalid,
	Todo,
	Active,
	Waiting,
	Done,
	Cancelled,
}

/* Log_Instruction selects deterministic per-transition logging. */
Log_Instruction :: enum u8 {
	Invalid,
	None,
	State,
	Note,
	Time,
}

/* Workflow_State_Candidate is one borrowed Racket-originated state definition. */
Workflow_State_Candidate :: struct {
	name:         string,
	finished:     bool,
	fast_key:     rune,
	presentation: Presentation_Role,
	log:          Log_Instruction,
}

/* Workflow_Candidate is one borrowed ordered task sequence. */
Workflow_Candidate :: struct {
	identity: string,
	states:   []Workflow_State_Candidate,
}

/* Source_Kind identifies one configured agenda source boundary. */
Source_Kind :: enum u8 {
	Invalid,
	File,
	Directory,
	Project,
	Workspace,
	Provider,
}

/* Source_Candidate is one borrowed bounded source definition. */
Source_Candidate :: struct {
	identity:       string,
	kind:           Source_Kind,
	resource:       string,
	discovery_depth: u16,
	document_limit: u32,
}

/* Source_Set_Candidate is one borrowed ordered source collection. */
Source_Set_Candidate :: struct {
	identity: string,
	sources:  []Source_Candidate,
}

/* Capture_Entry_Kind identifies one configured source template shape. */
Capture_Entry_Kind :: enum u8 {
	Invalid,
	Heading,
	Task,
	Item,
	Plain,
}

/* Capture_Candidate is one borrowed capture definition. */
Capture_Candidate :: struct {
	key:              rune,
	label:            string,
	entry_kind:       Capture_Entry_Kind,
	target:           string,
	template:         string,
	immediate_finish: bool,
}

/* Agenda_Span identifies one configured date span. */
Agenda_Span :: enum u8 {
	Invalid,
	Day,
	Week,
	All,
}

/* Agenda_Candidate is one borrowed named agenda definition. */
Agenda_Candidate :: struct {
	key:          rune,
	label:        string,
	query:        string,
	span:         Agenda_Span,
	result_limit: u32,
}

/* Configuration_Candidate is validated wholly before publication. */
Configuration_Candidate :: struct {
	generation:          Configuration_Generation,
	provider_generation: Provider_Generation,
	workflows:           []Workflow_Candidate,
	source_sets:         []Source_Set_Candidate,
	captures:            []Capture_Candidate,
	agendas:             []Agenda_Candidate,
}

/* Configuration_Descriptor exposes one immutable confirmed generation. */
Configuration_Descriptor :: struct {
	generation:          Configuration_Generation,
	provider_generation: Provider_Generation,
	workflow_count:      u16,
	workflow_states:     u16,
	source_set_count:    u16,
	source_count:        u16,
	capture_count:       u16,
	agenda_count:        u16,
	retained_bytes:      u64,
	factory_fallback:    bool,
}

/* Record_Range identifies one contiguous child range in confirmed configuration. */
Record_Range :: struct {
	start: u16,
	count: u16,
}

/* Workflow_Record borrows one confirmed workflow until replacement. */
Workflow_Record :: struct {
	identity: string,
	states:   Record_Range,
}

/* Workflow_State_Record borrows one confirmed workflow state until replacement. */
Workflow_State_Record :: struct {
	name:         string,
	finished:     bool,
	fast_key:     rune,
	presentation: Presentation_Role,
	log:          Log_Instruction,
}

/* Source_Set_Record borrows one confirmed ordered source set until replacement. */
Source_Set_Record :: struct {
	identity: string,
	sources:  Record_Range,
}

/* Source_Record borrows one confirmed source until replacement. */
Source_Record :: struct {
	identity:        string,
	kind:            Source_Kind,
	resource:        string,
	discovery_depth: u16,
	document_limit:  u32,
}

/* Capture_Record borrows one confirmed capture definition until replacement. */
Capture_Record :: struct {
	key:              rune,
	label:            string,
	entry_kind:       Capture_Entry_Kind,
	target:           string,
	template:         string,
	immediate_finish: bool,
}

/* Agenda_Record borrows one confirmed agenda definition until replacement. */
Agenda_Record :: struct {
	key:          rune,
	label:        string,
	query:        string,
	span:         Agenda_Span,
	result_limit: u32,
}

/* Configuration owns one copied generation until replacement or close. */
Configuration :: struct {
	state: rawptr,
}

/* limits_are_valid checks every fixed resource ceiling independently. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.semantic_targets > 0 && limits.semantic_targets <= MAX_SEMANTIC_TARGETS &&
	       limits.source_documents > 0 && limits.source_documents <= MAX_SOURCE_DOCUMENTS &&
	       limits.agenda_entries > 0 && limits.agenda_entries <= MAX_AGENDA_ENTRIES &&
	       limits.capture_candidates > 0 && limits.capture_candidates <= MAX_CAPTURE_CANDIDATES &&
	       limits.refile_candidates > 0 && limits.refile_candidates <= MAX_REFILE_CANDIDATES &&
	       limits.attachment_outcomes > 0 && limits.attachment_outcomes <= MAX_ATTACHMENT_OUTCOMES &&
	       limits.feed_sources > 0 && limits.feed_sources <= MAX_FEED_SOURCES &&
	       limits.feed_entries > 0 && limits.feed_entries <= MAX_FEED_ENTRIES &&
	       limits.copied_text_bytes > 0 && limits.copied_text_bytes <= MAX_COPIED_TEXT_BYTES &&
	       limits.derived_state_bytes > 0 && limits.derived_state_bytes <= MAX_DERIVED_STATE_BYTES
}

/* scope_is_valid checks all exact source and configuration generations. */
scope_is_valid :: proc(scope: Scope) -> bool {
	return language.jan_analysis_scope_is_valid(scope.analysis) &&
	       scope.configuration_generation != Configuration_Generation(0) &&
	       scope.provider_generation != Provider_Generation(0) &&
	       scope.source_set != Source_Set_ID(0)
}

/* semantic_target_is_valid checks one copied target against its exact scope. */
semantic_target_is_valid :: proc(target: Semantic_Target, scope: Scope) -> bool {
	return scope_is_valid(scope) && target.node_id != language.Jan_Node_ID(0) &&
	       target.kind != .Invalid && target.range.scope == scope.analysis &&
	       target.range.start < target.range.end &&
	       language.jan_source_range_is_valid(target.range, scope.source_bytes)
}

/* request_is_valid checks one complete bounded request without retaining input. */
request_is_valid :: proc(request: Request) -> bool {
	if request.operation_id == Operation_ID(0) || request.kind == .Invalid ||
	   !scope_is_valid(request.scope) || !limits_are_valid(request.limits) ||
	   len(request.targets) > int(request.limits.semantic_targets) {
		return false
	}
	for target in request.targets do if !semantic_target_is_valid(target, request.scope) do return false
	return true
}

/* planning_capability_declarations returns the complete non-operational family inventory. */
planning_capability_declarations :: proc() -> [8]Availability_Record {
	return {
		{capability = .Tasks, class = .Factory_Native, state = .Declared},
		{capability = .Metadata, class = .Factory_Native, state = .Declared},
		{capability = .Time, class = .Factory_Native, state = .Declared},
		{capability = .Refile_Archive, class = .Factory_Native, state = .Declared},
		{capability = .Capture, class = .Factory_Native, state = .Declared},
		{capability = .Attachments, class = .Factory_Adapter, state = .Declared},
		{capability = .Feeds, class = .Configured_Provider, state = .Declared},
		{capability = .Agenda, class = .Factory_Native, state = .Declared},
	}
}

/* planning_capability_availability publishes final domain state without granting authority. */
planning_capability_availability :: proc(
	provider_generation: Provider_Generation,
	attachments_available, feeds_available: bool,
) -> [8]Availability_Record {
	return {
		{capability = .Tasks, class = .Factory_Native, state = .Available},
		{capability = .Metadata, class = .Factory_Native, state = .Available},
		{capability = .Time, class = .Factory_Native, state = .Available},
		{capability = .Refile_Archive, class = .Factory_Native, state = .Available},
		{capability = .Capture, class = .Factory_Native, state = .Available},
		{capability = .Attachments, class = .Factory_Adapter,
			state = .Available if attachments_available else .Unavailable,
			provider_generation = provider_generation},
		{capability = .Feeds, class = .Configured_Provider,
			state = .Available if feeds_available else .Unavailable,
			provider_generation = provider_generation},
		{capability = .Agenda, class = .Factory_Native, state = .Available},
	}
}

/* resource_identity_copy creates one pointer-free bounded resource identity. */
resource_identity_copy :: proc(provider: u64, key: string) -> (Resource_Identity, bool) {
	if provider == 0 || !configuration_text_is_valid(key, MAX_RESOURCE_BYTES) do return {}, false
	identity: Resource_Identity
	identity.provider = provider
	identity.key.length = u16(copy(identity.key.bytes[:], key))
	return identity, true
}

/* resource_identity_is_valid checks one copied provider-owned resource identity. */
resource_identity_is_valid :: proc(identity: Resource_Identity) -> bool {
	key := identity.key
	return identity.provider != 0 && key.length > 0 &&
	       int(key.length) <= MAX_RESOURCE_BYTES &&
	       utf8.valid_string(string(key.bytes[:key.length]))
}

/* resource_identity_text borrows the copied key from one resource identity. */
resource_identity_text :: proc(identity: ^Resource_Identity) -> string {
	if identity == nil || !resource_identity_is_valid(identity^) do return ""
	return string(identity.key.bytes[:identity.key.length])
}

@(private)
configuration_text_is_valid :: proc(text: string, maximum: int) -> bool {
	return len(text) > 0 && len(text) <= maximum && utf8.valid_string(text)
}
