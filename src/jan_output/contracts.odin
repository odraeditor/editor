// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package jan_output owns copied export, publication, protocol, synchronization, and extension contracts.
package jan_output

import "../language"
import "core:unicode/utf8"

/* OUTPUT_SCHEMA_VERSION identifies the Jan output contract family. */
OUTPUT_SCHEMA_VERSION :: u16(1)
/* MAX_INCLUDED_RESOURCES bounds one export include graph. */
MAX_INCLUDED_RESOURCES :: u32(1_024)
/* MAX_INCLUDE_DEPTH bounds recursive include traversal. */
MAX_INCLUDE_DEPTH :: u16(128)
/* MAX_MACRO_EXPANSIONS bounds one export expansion pass. */
MAX_MACRO_EXPANSIONS :: u32(4_096)
/* MAX_NORMALIZED_NODES bounds one copied output tree. */
MAX_NORMALIZED_NODES :: u32(1_048_576)
/* MAX_OUTPUT_BYTES bounds one generated output. */
MAX_OUTPUT_BYTES :: u64(256 * 1_024 * 1_024)
/* MAX_DIAGNOSTICS bounds one output result. */
MAX_DIAGNOSTICS :: u32(65_536)
/* MAX_MANIFEST_ENTRIES bounds one publication or synchronization manifest. */
MAX_MANIFEST_ENTRIES :: u32(65_536)
/* MAX_LINKS bounds resolved links in one operation. */
MAX_LINKS :: u32(16_384)
/* MAX_PUBLICATION_TARGETS bounds checked destinations in one operation. */
MAX_PUBLICATION_TARGETS :: u32(4_096)
/* MAX_PROVIDER_OPERATIONS bounds active output providers. */
MAX_PROVIDER_OPERATIONS :: u16(128)
/* MAX_CACHE_BYTES bounds aggregate retained export cache. */
MAX_CACHE_BYTES :: u64(512 * 1_024 * 1_024)
/* MAX_PROTOCOL_PAYLOAD_BYTES bounds encoded input before protocol decoding. */
MAX_PROTOCOL_PAYLOAD_BYTES :: u64(1 * 1_024 * 1_024)
/* CANCELLATION_CHECK_ENTRIES bounds in-process work between cancellation checks. */
CANCELLATION_CHECK_ENTRIES :: u32(4_096)
/* MAX_SETTINGS bounds resolved general and backend-specific settings. */
MAX_SETTINGS :: u16(4_096)
/* MAX_FILTERS bounds one ordered export filter chain. */
MAX_FILTERS :: u16(256)
/* MAX_IDENTITY_BYTES bounds one copied output identity. */
MAX_IDENTITY_BYTES :: 96
/* MAX_SETTING_VALUE_BYTES bounds one copied setting value. */
MAX_SETTING_VALUE_BYTES :: 16 * 1_024

/* Operation_ID identifies one output operation lifetime. */
Operation_ID :: distinct u64
/* Configuration_Generation identifies one confirmed output configuration. */
Configuration_Generation :: distinct u64
/* Backend_Generation identifies one confirmed backend catalog. */
Backend_Generation :: distinct u64
/* Filter_Generation identifies one confirmed filter catalog. */
Filter_Generation :: distinct u64
/* Provider_Generation identifies one confirmed external provider catalog. */
Provider_Generation :: distinct u64
/* Manifest_ID identifies one publication or synchronization manifest. */
Manifest_ID :: distinct u64

/* Limits is the complete stable output resource policy. */
Limits :: struct {
	included_resources: u32,
	include_depth:      u16,
	macro_expansions:   u32,
	normalized_nodes:   u32,
	output_bytes:       u64,
	diagnostics:        u32,
	manifest_entries:   u32,
	links:              u32,
	publication_targets: u32,
	provider_operations: u16,
	cache_bytes:        u64,
	protocol_payload_bytes: u64,
	settings:           u16,
	filters:            u16,
	elapsed_milliseconds: u64,
	rss_bytes:          u64,
}

/* DEFAULT_LIMITS is the accepted Jan output resource ceiling. */
DEFAULT_LIMITS := Limits {
	included_resources = MAX_INCLUDED_RESOURCES,
	include_depth = MAX_INCLUDE_DEPTH,
	macro_expansions = MAX_MACRO_EXPANSIONS,
	normalized_nodes = MAX_NORMALIZED_NODES,
	output_bytes = MAX_OUTPUT_BYTES,
	diagnostics = MAX_DIAGNOSTICS,
	manifest_entries = MAX_MANIFEST_ENTRIES,
	links = MAX_LINKS,
	publication_targets = MAX_PUBLICATION_TARGETS,
	provider_operations = MAX_PROVIDER_OPERATIONS,
	cache_bytes = MAX_CACHE_BYTES,
	protocol_payload_bytes = MAX_PROTOCOL_PAYLOAD_BYTES,
	settings = MAX_SETTINGS,
	filters = MAX_FILTERS,
	elapsed_milliseconds = 300_000,
	rss_bytes = 1 * 1_024 * 1_024 * 1_024,
}

/* Operation_Kind identifies one Jan output semantic family. */
Operation_Kind :: enum u8 {
	Invalid,
	Configure,
	Export,
	Preview,
	Publish,
	Protocol,
	Protect,
	Synchronize,
	Extend,
	Inspect,
}

/* Lifecycle_State identifies one output operation boundary. */
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

/* Failure_Code classifies output rejection without implicit effects. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Malformed,
	Stale,
	Unavailable,
	Limited,
	Unauthorized,
	Cancelled,
	Allocation_Failed,
	Conflict,
	Cycle,
	Missing,
	Unsupported,
	Provider,
	Validation,
	Publication,
	Reconciliation_Required,
}

/* Failure_Field identifies the rejected output contract field. */
Failure_Field :: enum u8 {
	None,
	Scope,
	Selection,
	Generation,
	Backend,
	Setting,
	Include,
	Macro,
	Filter,
	Node,
	Diagnostic,
	Destination,
	Manifest,
	Protocol,
	Protection,
	Synchronization,
	Extension,
	Citation,
	Bibliography,
	Resource,
	Limit,
}

/* Capability identifies the closed Jan output and integration inventory. */
Capability :: enum u8 {
	Invalid,
	Export_Pipeline,
	Plain_Text,
	Html,
	Markdown,
	Normalized_Jan,
	Beamer,
	Latex_Pdf,
	Odt,
	Texinfo_Info,
	Calendar,
	Man_Page,
	Citations,
	Publishing,
	Protocols,
	Encryption,
	Synchronization,
	Extensions,
}

/* Availability_Class identifies native, adapter, and configured ownership. */
Availability_Class :: enum u8 {
	Invalid,
	Factory_Native,
	Factory_Adapter,
	Configured_Provider,
}

/* Availability_State separates declaration from operational availability. */
Availability_State :: enum u8 {
	Invalid,
	Declared,
	Available,
	Unavailable,
}

/* Availability_Record reports one output capability without granting authority. */
Availability_Record :: struct {
	capability:          Capability,
	class:               Availability_Class,
	state:               Availability_State,
	provider_generation: Provider_Generation,
}

/* Export_Scope_Kind identifies the selected source projection. */
Export_Scope_Kind :: enum u8 {
	Invalid,
	Document,
	Subtree,
	Region,
	Visible,
	Agenda,
}

/* Destination_Kind identifies a checked output handoff. */
Destination_Kind :: enum u8 {
	Invalid,
	Preview,
	Buffer,
	Clipboard,
	Resource,
}

/* Setting_Source identifies explicit output precedence from low to high. */
Setting_Source :: enum u8 {
	Invalid,
	Factory,
	User,
	Workspace,
	Project,
	Document,
	Ancestor_Subtree,
	Selected_Subtree,
	Invocation,
}

/* Backend_Class identifies native, adapter, and configured implementations. */
Backend_Class :: enum u8 {
	Invalid,
	Factory_Native,
	Factory_Adapter,
	Configured_Provider,
}

/* Diagnostic_Severity identifies bounded export feedback. */
Diagnostic_Severity :: enum u8 {
	Invalid,
	Information,
	Warning,
	Error,
}

/* Manifest_State identifies recoverable publication lifecycle. */
Manifest_State :: enum u8 {
	Invalid,
	Candidate,
	Local_Complete,
	Remote_Partial,
	Published,
	Reconciliation_Required,
	Failed,
}

/* Synchronization_State identifies recoverable synchronization lifecycle. */
Synchronization_State :: enum u8 {
	Invalid,
	Prepared,
	Pushed,
	Received,
	Conflicted,
	Applied,
	Reconciliation_Required,
	Expired,
}

/* Scope binds output to exact source and provider generations. */
Scope :: struct {
	analysis:                 language.Jan_Analysis_Scope,
	source_bytes:             u64,
	configuration_generation: Configuration_Generation,
	backend_generation:       Backend_Generation,
	filter_generation:        Filter_Generation,
	provider_generation:      Provider_Generation,
}

/* Selection identifies one exact export source range or aggregate scope. */
Selection :: struct {
	kind:  Export_Scope_Kind,
	range: language.Jan_Source_Range,
}

/* Setting_Candidate is one borrowed general or backend-specific value. */
Setting_Candidate :: struct {
	key:              string,
	value:            string,
	backend:          string,
	source:           Setting_Source,
	additive:         bool,
	source_order:     u32,
}

/* Setting_Resolution identifies the winning scalar or additive contribution set. */
Setting_Resolution :: struct {
	winner_index:      u16,
	contribution_count: u16,
	shadowed_count:    u16,
	additive:          bool,
}

/* Projection_Policy controls comments, selection, contents, and semantic inclusion. */
Projection_Policy :: struct {
	include_comments:           bool,
	include_commented_headings: bool,
	include_archived:           bool,
	include_drawers:            bool,
	include_properties:         bool,
	include_tasks:              bool,
	include_code:               bool,
	include_results:            bool,
	contents:                   bool,
	contents_depth:             u16,
	number_headings:            bool,
	excluded_tag_count:         u16,
}

/* Include_Record identifies one admitted exact-version resource. */
Include_Record :: struct {
	resource_id:       u64,
	resource_revision: u64,
	parent_resource_id: u64,
	depth:             u16,
	start_line:        u32,
	end_line:          u32,
	minimum_heading_level: u16,
	recursive:         bool,
}

/* Macro_Record identifies one bounded expansion result. */
Macro_Record :: struct {
	identity:       string,
	argument_count: u16,
	depth:          u16,
	expansion_bytes: u64,
	defined:        bool,
	recursive:      bool,
}

/* Filter_Record identifies one exact ordered filter. */
Filter_Record :: struct {
	identity:   string,
	generation: Filter_Generation,
	order:      u16,
	available:  bool,
}

/* Normalized_Tree describes one immutable copied output tree. */
Normalized_Tree :: struct {
	scope:      Scope,
	node_count: u32,
	link_count: u32,
	byte_count: u64,
	digest:     [32]u8,
	complete:   bool,
}

/* Diagnostic_Record identifies one bounded attributable output diagnostic. */
Diagnostic_Record :: struct {
	severity:   Diagnostic_Severity,
	field:      Failure_Field,
	source_start: u64,
	source_end: u64,
	message_bytes: u32,
}

/* Destination is one non-authorizing checked output target. */
Destination :: struct {
	kind:              Destination_Kind,
	resource_id:       u64,
	expected_revision: u64,
	overwrite:         bool,
}

/* Export_Request identifies one bounded explicit pipeline request. */
Export_Request :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	selection:    Selection,
	backend:      string,
	projection:   Projection_Policy,
	settings:     []Setting_Candidate,
	includes:     []Include_Record,
	macros:       []Macro_Record,
	filters:      []Filter_Record,
	destination:  Destination,
	limits:       Limits,
	explicit:     bool,
}

/* Output_Plan describes a complete non-effectful pipeline plan. */
Output_Plan :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	selection:    Selection,
	setting_count: u16,
	include_count: u32,
	macro_count:  u32,
	filter_count: u16,
	destination:  Destination,
	complete:     bool,
}

/* Output_Descriptor reports one validated generated candidate. */
Output_Descriptor :: struct {
	operation_id: Operation_ID,
	backend_generation: Backend_Generation,
	filter_generation:  Filter_Generation,
	output_bytes:        u64,
	diagnostic_count:    u32,
	resource_count:      u32,
	complete:            bool,
}

/* Publication_Manifest_Record identifies one recoverable publication result. */
Publication_Manifest_Record :: struct {
	schema_version: u16,
	manifest_id:    Manifest_ID,
	operation_id:   Operation_ID,
	configuration_generation: Configuration_Generation,
	backend_generation: Backend_Generation,
	filter_generation:  Filter_Generation,
	entry_count:    u32,
	target_count:   u32,
	state:          Manifest_State,
}

/* Protocol_Request describes bounded encoded input without transport authority. */
Protocol_Request :: struct {
	operation_id: Operation_ID,
	provider_generation: Provider_Generation,
	payload_bytes: u64,
	explicit:      bool,
}

/* Synchronization_Manifest_Record identifies one recoverable synchronization state. */
Synchronization_Manifest_Record :: struct {
	schema_version: u16,
	manifest_id:    Manifest_ID,
	provider_generation: Provider_Generation,
	entry_count:    u32,
	conflict_count: u32,
	state:          Synchronization_State,
}

/* Extension_Record identifies one copied provider contribution. */
Extension_Record :: struct {
	identity:            string,
	class:               Availability_Class,
	provider_generation: Provider_Generation,
	resource_count:      u32,
	available:           bool,
}

/* Failure reports one bounded attributable output failure. */
Failure :: struct {
	operation_id: Operation_ID,
	kind:         Operation_Kind,
	code:         Failure_Code,
	field:        Failure_Field,
	limit:        u64,
	actual:       u64,
}

/* limits_are_valid checks all stable ceilings and mandatory operation bounds. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.included_resources > 0 && limits.included_resources <= MAX_INCLUDED_RESOURCES &&
	       limits.include_depth > 0 && limits.include_depth <= MAX_INCLUDE_DEPTH &&
	       limits.macro_expansions > 0 && limits.macro_expansions <= MAX_MACRO_EXPANSIONS &&
	       limits.normalized_nodes > 0 && limits.normalized_nodes <= MAX_NORMALIZED_NODES &&
	       limits.output_bytes > 0 && limits.output_bytes <= MAX_OUTPUT_BYTES &&
	       limits.diagnostics > 0 && limits.diagnostics <= MAX_DIAGNOSTICS &&
	       limits.manifest_entries > 0 && limits.manifest_entries <= MAX_MANIFEST_ENTRIES &&
	       limits.links > 0 && limits.links <= MAX_LINKS &&
	       limits.publication_targets > 0 && limits.publication_targets <= MAX_PUBLICATION_TARGETS &&
	       limits.provider_operations > 0 && limits.provider_operations <= MAX_PROVIDER_OPERATIONS &&
	       limits.cache_bytes > 0 && limits.cache_bytes <= MAX_CACHE_BYTES &&
	       limits.protocol_payload_bytes > 0 && limits.protocol_payload_bytes <= MAX_PROTOCOL_PAYLOAD_BYTES &&
	       limits.settings > 0 && limits.settings <= MAX_SETTINGS &&
	       limits.filters > 0 && limits.filters <= MAX_FILTERS &&
	       limits.elapsed_milliseconds > 0 && limits.rss_bytes > 0
}

/* scope_is_valid checks exact source and output generations. */
scope_is_valid :: proc(scope: Scope) -> bool {
	return language.jan_analysis_scope_is_valid(scope.analysis) && scope.source_bytes > 0 &&
	       scope.configuration_generation != Configuration_Generation(0) &&
	       scope.backend_generation != Backend_Generation(0) &&
	       scope.filter_generation != Filter_Generation(0) &&
	       scope.provider_generation != Provider_Generation(0)
}

/* selection_is_valid checks one exact range or aggregate source selection. */
selection_is_valid :: proc(selection: Selection, scope: Scope) -> bool {
	if selection.kind == .Invalid do return false
	if selection.kind == .Document || selection.kind == .Agenda {
		return selection.range.scope == scope.analysis && selection.range.start == 0 &&
		       u64(selection.range.end) == scope.source_bytes
	}
	return selection.range.scope == scope.analysis &&
	       language.jan_source_range_is_valid(selection.range, scope.source_bytes) &&
	       selection.range.start < selection.range.end
}

/* destination_is_valid checks a destination without granting its effect. */
destination_is_valid :: proc(destination: Destination) -> bool {
	if destination.kind == .Invalid do return false
	if destination.kind == .Resource {
		return destination.resource_id != 0 && destination.expected_revision != 0
	}
	return destination.resource_id == 0 && destination.expected_revision == 0 && !destination.overwrite
}

/* normalized_tree_is_valid checks one immutable copied tree descriptor. */
normalized_tree_is_valid :: proc(tree: Normalized_Tree, limits := DEFAULT_LIMITS) -> bool {
	return scope_is_valid(tree.scope) && tree.complete && tree.node_count > 0 &&
	       tree.node_count <= limits.normalized_nodes && tree.link_count <= limits.links &&
	       tree.byte_count <= tree.scope.source_bytes && digest_is_present(tree.digest)
}

/* projection_policy_is_valid checks bounded contents and exclusion selection. */
projection_policy_is_valid :: proc(policy: Projection_Policy, limits := DEFAULT_LIMITS) -> bool {
	return (!policy.contents || policy.contents_depth > 0) &&
	       policy.contents_depth <= limits.include_depth &&
	       policy.excluded_tag_count <= limits.settings
}

/* diagnostic_record_is_valid checks source attribution and message bounds. */
diagnostic_record_is_valid :: proc(record: Diagnostic_Record, scope: Scope) -> bool {
	return record.severity != .Invalid && record.field != .None &&
	       record.source_start <= record.source_end && record.source_end <= scope.source_bytes &&
	       record.message_bytes > 0 && record.message_bytes <= MAX_SETTING_VALUE_BYTES
}

/* output_descriptor_is_valid checks one complete bounded output candidate. */
output_descriptor_is_valid :: proc(descriptor: Output_Descriptor, limits := DEFAULT_LIMITS) -> bool {
	return descriptor.operation_id != Operation_ID(0) &&
	       descriptor.backend_generation != Backend_Generation(0) &&
	       descriptor.filter_generation != Filter_Generation(0) && descriptor.complete &&
	       descriptor.output_bytes <= limits.output_bytes &&
	       descriptor.diagnostic_count <= limits.diagnostics &&
	       descriptor.resource_count <= limits.publication_targets
}

/* publication_manifest_is_valid checks recoverable publication accounting. */
publication_manifest_is_valid :: proc(record: Publication_Manifest_Record, limits := DEFAULT_LIMITS) -> bool {
	return record.schema_version == OUTPUT_SCHEMA_VERSION && record.manifest_id != Manifest_ID(0) &&
	       record.operation_id != Operation_ID(0) &&
	       record.configuration_generation != Configuration_Generation(0) &&
	       record.backend_generation != Backend_Generation(0) &&
	       record.filter_generation != Filter_Generation(0) && record.entry_count > 0 &&
	       record.entry_count <= limits.manifest_entries && record.target_count > 0 &&
	       record.target_count <= limits.publication_targets && record.state != .Invalid
}

/* protocol_request_is_valid checks payload bounds before any decoding or transport. */
protocol_request_is_valid :: proc(request: Protocol_Request, limits := DEFAULT_LIMITS) -> bool {
	return request.operation_id != Operation_ID(0) &&
	       request.provider_generation != Provider_Generation(0) && request.explicit &&
	       request.payload_bytes > 0 && request.payload_bytes <= limits.protocol_payload_bytes
}

/* synchronization_manifest_is_valid checks recoverable conflict accounting. */
synchronization_manifest_is_valid :: proc(record: Synchronization_Manifest_Record, limits := DEFAULT_LIMITS) -> bool {
	return record.schema_version == OUTPUT_SCHEMA_VERSION && record.manifest_id != Manifest_ID(0) &&
	       record.provider_generation != Provider_Generation(0) && record.entry_count > 0 &&
	       record.entry_count <= limits.manifest_entries && record.conflict_count <= record.entry_count &&
	       record.state != .Invalid
}

/* extension_record_is_valid checks one copied bounded provider contribution. */
extension_record_is_valid :: proc(record: Extension_Record, limits := DEFAULT_LIMITS) -> bool {
	return output_text_is_valid(record.identity, MAX_IDENTITY_BYTES) && record.class != .Invalid &&
	       record.provider_generation != Provider_Generation(0) &&
	       record.resource_count <= limits.publication_targets
}

/* output_capability_declarations returns the complete non-operational inventory. */
output_capability_declarations :: proc() -> [17]Availability_Record {
	return {
		{capability = .Export_Pipeline, class = .Factory_Native, state = .Declared},
		{capability = .Plain_Text, class = .Factory_Native, state = .Declared},
		{capability = .Html, class = .Factory_Native, state = .Declared},
		{capability = .Markdown, class = .Factory_Native, state = .Declared},
		{capability = .Normalized_Jan, class = .Factory_Native, state = .Declared},
		{capability = .Beamer, class = .Factory_Adapter, state = .Declared},
		{capability = .Latex_Pdf, class = .Factory_Adapter, state = .Declared},
		{capability = .Odt, class = .Factory_Adapter, state = .Declared},
		{capability = .Texinfo_Info, class = .Factory_Adapter, state = .Declared},
		{capability = .Calendar, class = .Factory_Adapter, state = .Declared},
		{capability = .Man_Page, class = .Factory_Adapter, state = .Declared},
		{capability = .Citations, class = .Factory_Adapter, state = .Declared},
		{capability = .Publishing, class = .Configured_Provider, state = .Declared},
		{capability = .Protocols, class = .Configured_Provider, state = .Declared},
		{capability = .Encryption, class = .Configured_Provider, state = .Declared},
		{capability = .Synchronization, class = .Configured_Provider, state = .Declared},
		{capability = .Extensions, class = .Configured_Provider, state = .Declared},
	}
}

@(private)
digest_is_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
output_text_is_valid :: proc(value: string, maximum: int) -> bool {
	return len(value) > 0 && len(value) <= maximum && utf8.valid_string(value)
}
