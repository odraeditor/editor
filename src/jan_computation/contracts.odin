// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package jan_computation owns copied computation, execution, result, and extraction contracts.
package jan_computation

import "../language"
import "core:unicode/utf8"

/* COMPUTATION_SCHEMA_VERSION identifies the durable Computable Documents record family. */
COMPUTATION_SCHEMA_VERSION :: u16(1)
/* MAX_TABLE_CELLS bounds cells considered by one computation. */
MAX_TABLE_CELLS :: u32(65_536)
/* MAX_FORMULA_DEPENDENCIES bounds one formula dependency graph. */
MAX_FORMULA_DEPENDENCIES :: u32(16_384)
/* MAX_GRAPH_DEPTH bounds formula, result, and noweb graph traversal. */
MAX_GRAPH_DEPTH :: u16(1_024)
/* MAX_EXECUTABLE_TARGETS bounds one explicit execution operation. */
MAX_EXECUTABLE_TARGETS :: u32(4_096)
/* MAX_ACTIVE_SESSIONS bounds process-wide live execution sessions. */
MAX_ACTIVE_SESSIONS :: u16(64)
/* MAX_CHILD_PROCESSES bounds children admitted by one operation. */
MAX_CHILD_PROCESSES :: u16(32)
/* MAX_OUTPUT_BYTES bounds captured output for one target. */
MAX_OUTPUT_BYTES :: u64(64 * 1_024 * 1_024)
/* MAX_RETAINED_OUTPUT_BYTES bounds aggregate retained execution output. */
MAX_RETAINED_OUTPUT_BYTES :: u64(256 * 1_024 * 1_024)
/* MAX_GENERATED_FILES bounds resources produced by one extraction. */
MAX_GENERATED_FILES :: u32(4_096)
/* MAX_RESULT_ROWS bounds one decoded tabular result. */
MAX_RESULT_ROWS :: u32(16_384)
/* MAX_CACHE_BYTES bounds aggregate retained execution cache. */
MAX_CACHE_BYTES :: u64(256 * 1_024 * 1_024)
/* CANCELLATION_CHECK_ENTRIES bounds in-process work between cancellation checks. */
CANCELLATION_CHECK_ENTRIES :: u32(4_096)
/* MAX_ADAPTERS bounds one confirmed adapter generation. */
MAX_ADAPTERS :: u16(256)
/* MAX_POLICIES bounds one confirmed execution-policy generation. */
MAX_POLICIES :: u16(1_024)
/* MAX_CONFIGURATION_BYTES bounds copied computation configuration text. */
MAX_CONFIGURATION_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_IDENTITY_BYTES bounds one copied identity. */
MAX_IDENTITY_BYTES :: 96
/* MAX_VERSION_BYTES bounds one copied adapter version. */
MAX_VERSION_BYTES :: 128

/* Operation_ID identifies one computation request lifetime. */
Operation_ID :: distinct u64
/* Configuration_Generation identifies one confirmed computation configuration. */
Configuration_Generation :: distinct u64
/* Adapter_Generation identifies one confirmed adapter set. */
Adapter_Generation :: distinct u64
/* Policy_Generation identifies one confirmed execution-policy set. */
Policy_Generation :: distinct u64
/* Session_ID identifies one adapter-owned execution context. */
Session_ID :: distinct u64
/* Cache_Entry_ID identifies one bounded cached result. */
Cache_Entry_ID :: distinct u64
/* Batch_ID identifies one deterministic multi-target execution. */
Batch_ID :: distinct u64

/* Limits is the complete fixed computation resource policy. */
Limits :: struct {
	table_cells:          u32,
	formula_dependencies: u32,
	graph_depth:          u16,
	executable_targets:   u32,
	active_sessions:      u16,
	child_processes:      u16,
	output_bytes:         u64,
	retained_output_bytes: u64,
	generated_files:      u32,
	result_rows:          u32,
	cache_bytes:          u64,
	elapsed_milliseconds: u64,
	cpu_milliseconds:     u64,
	rss_bytes:            u64,
	environment_entries:  u16,
}

/* DEFAULT_LIMITS is the accepted Computable Documents resource ceiling. */
DEFAULT_LIMITS := Limits {
	table_cells = MAX_TABLE_CELLS,
	formula_dependencies = MAX_FORMULA_DEPENDENCIES,
	graph_depth = MAX_GRAPH_DEPTH,
	executable_targets = MAX_EXECUTABLE_TARGETS,
	active_sessions = MAX_ACTIVE_SESSIONS,
	child_processes = MAX_CHILD_PROCESSES,
	output_bytes = MAX_OUTPUT_BYTES,
	retained_output_bytes = MAX_RETAINED_OUTPUT_BYTES,
	generated_files = MAX_GENERATED_FILES,
	result_rows = MAX_RESULT_ROWS,
	cache_bytes = MAX_CACHE_BYTES,
	elapsed_milliseconds = 300_000,
	cpu_milliseconds = 300_000,
	rss_bytes = 1 * 1_024 * 1_024 * 1_024,
	environment_entries = 256,
}

/* Operation_Kind identifies one Computable Documents semantic family. */
Operation_Kind :: enum u8 {
	Invalid,
	Configure,
	Formula,
	Plot,
	Execute,
	Result,
	Session,
	Cache,
	Extract,
	Source_Edit,
	Batch,
}

/* Lifecycle_State identifies one computation operation boundary. */
Lifecycle_State :: enum u8 {
	Invalid,
	Prepared,
	Confirmed,
	Active,
	Completed,
	Cancelled,
	Failed,
	Timed_Out,
	Quarantined,
	Recovery_Required,
	Closed,
}

/* Failure_Code classifies expected rejection without partial publication. */
Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Malformed,
	Stale,
	Unavailable,
	Limited,
	Unauthorized,
	Confirmation_Required,
	Cancelled,
	Timed_Out,
	Allocation_Failed,
	Conflict,
	Cycle,
	Conversion,
	Adapter,
	Process,
	Evaluation,
	Result_Decoding,
	Publication,
	Quarantined,
}

/* Failure_Field identifies the rejected computation contract field. */
Failure_Field :: enum u8 {
	None,
	Scope,
	Target,
	Generation,
	Adapter,
	Process,
	Policy,
	Authority,
	Formula,
	Dependency,
	Result,
	Session,
	Cache,
	Resource,
	Limit,
	Batch,
}

/* Capability is the closed Computable Documents feature inventory. */
Capability :: enum u8 {
	Invalid,
	Formulas,
	Text_Plots,
	Graphical_Plots,
	Execution,
	Results,
	Sessions,
	Cache,
	Source_Editing,
	Noweb,
	Tangling,
	Batch,
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

/* Availability_Record reports one capability without granting execution authority. */
Availability_Record :: struct {
	capability:         Capability,
	class:              Availability_Class,
	state:              Availability_State,
	adapter_generation: Adapter_Generation,
}

/* Authority_Decision is one deny-first execution policy outcome. */
Authority_Decision :: enum u8 {
	Invalid,
	Deny,
	Confirm,
	Allow,
}

/* Source_Origin classifies the admitted origin of executable source. */
Source_Origin :: enum u8 {
	Invalid,
	Factory,
	User,
	Workspace,
	Project,
	Document,
	External,
}

/* Invocation_Context distinguishes interactive, batch, and export execution. */
Invocation_Context :: enum u8 {
	Invalid,
	Interactive,
	Batch,
	Export,
}

/* Effect identifies one authority-relevant execution effect. */
Effect :: enum u8 {
	Read_Resource,
	Write_Resource,
	Network,
	Child_Process,
	Environment,
	Credential,
}

/* Effects is a fixed set of requested execution effects. */
Effects :: bit_set[Effect; u8]

/* Result_Collection identifies value or output collection semantics. */
Result_Collection :: enum u8 {
	Invalid,
	Value,
	Output,
}

/* Result_Type identifies one decoded computation value family. */
Result_Type :: enum u8 {
	Invalid,
	Absence,
	Scalar,
	List,
	Table,
	Resource,
	Text,
	Document_Fragment,
	Graphics,
}

/* Result_Format identifies one admitted source representation. */
Result_Format :: enum u8 {
	Invalid,
	Raw,
	Verbatim,
	Code,
	Table,
	List,
	File,
	Link,
	Structured,
}

/* Result_Handling identifies one requested publication behavior. */
Result_Handling :: enum u8 {
	Invalid,
	Replace,
	Append,
	Prepend,
	Silent,
	Discard,
}

/* Session_State identifies one adapter-owned session lifecycle. */
Session_State :: enum u8 {
	Invalid,
	Prepared,
	Active,
	Closing,
	Recovery_Required,
	Closed,
	Failed,
	Quarantined,
}

/* Cache_State identifies one cache inspection outcome. */
Cache_State :: enum u8 {
	Invalid,
	Hit,
	Miss,
	Invalidated,
	Rejected,
	Evicted,
}

/* Batch_Mode identifies deterministic multi-target publication policy. */
Batch_Mode :: enum u8 {
	Invalid,
	Atomic,
	Best_Effort,
}

/* Scope binds work to exact analysis, configuration, adapter, and policy generations. */
Scope :: struct {
	analysis:                 language.Jan_Analysis_Scope,
	source_bytes:             u64,
	configuration_generation: Configuration_Generation,
	adapter_generation:       Adapter_Generation,
	policy_generation:        Policy_Generation,
}

/* Semantic_Target is one copied exact-revision executable or formula target. */
Semantic_Target :: struct {
	node_id: language.Jan_Node_ID,
	kind:    language.Jan_Node_Kind,
	range:   language.Jan_Source_Range,
}

/* Request identifies one bounded explicit computation operation. */
Request :: struct {
	operation_id: Operation_ID,
	kind:         Operation_Kind,
	scope:        Scope,
	targets:      []Semantic_Target,
	limits:       Limits,
	invocation:   Invocation_Context,
	effects:      Effects,
}

/* Typed_Result_Descriptor reports one decoded candidate result without owning payload bytes. */
Typed_Result_Descriptor :: struct {
	operation_id: Operation_ID,
	type:         Result_Type,
	collection:   Result_Collection,
	format:       Result_Format,
	handling:     Result_Handling,
	row_count:    u32,
	byte_count:   u64,
	exit_status:  i32,
	complete:     bool,
}

/* Session_Record identifies one adapter-owned session without making it document state. */
Session_Record :: struct {
	schema_version:     u16,
	session_id:         Session_ID,
	adapter_generation: Adapter_Generation,
	policy_generation:  Policy_Generation,
	source_revision:    u64,
	process_identity:   u64,
	state:              Session_State,
	last_activity_ns:   i64,
}

/* Cache_Key binds reuse to complete semantic and environment digests. */
Cache_Key :: struct {
	source_digest:      [32]u8,
	argument_digest:    [32]u8,
	input_digest:       [32]u8,
	reference_digest:   [32]u8,
	environment_digest: [32]u8,
	adapter_identity_digest: [32]u8,
	adapter_version_digest:  [32]u8,
	cache_policy_digest:     [32]u8,
	adapter_generation: Adapter_Generation,
	policy_generation:  Policy_Generation,
}

/* Cache_Record reports one bounded cache entry and its inspection state. */
Cache_Record :: struct {
	entry_id:   Cache_Entry_ID,
	key:        Cache_Key,
	state:      Cache_State,
	byte_count: u64,
	row_count:  u32,
}

/* Extraction_Descriptor reports one complete checked extraction plan. */
Extraction_Descriptor :: struct {
	operation_id:   Operation_ID,
	scope:          Scope,
	target_count:   u32,
	resource_count: u32,
	byte_count:     u64,
	complete:       bool,
}

/* Batch_Descriptor reports deterministic batch ordering and outcomes. */
Batch_Descriptor :: struct {
	batch_id:    Batch_ID,
	mode:        Batch_Mode,
	target_count: u32,
	completed:   u32,
	rejected:    u32,
	unattempted: u32,
	cancelled:   bool,
}

/* Failure reports one bounded attributable computation failure. */
Failure :: struct {
	operation_id: Operation_ID,
	kind:         Operation_Kind,
	code:         Failure_Code,
	field:        Failure_Field,
	limit:        u64,
	actual:       u64,
}

/* Adapter_Candidate is one borrowed Racket-originated adapter definition. */
Adapter_Candidate :: struct {
	identity:         string,
	language:         string,
	version:          string,
	class:            Availability_Class,
	in_process:       bool,
	runtime_required: bool,
	limits:           Limits,
}

/* Policy_Candidate is one borrowed deny-first execution rule. */
Policy_Candidate :: struct {
	identity:    string,
	adapter:     string,
	language:    string,
	origin:      Source_Origin,
	interactive: Authority_Decision,
	batch:       Authority_Decision,
	effects:     Effects,
}

/* Configuration_Candidate is validated wholly before publication. */
Configuration_Candidate :: struct {
	generation:         Configuration_Generation,
	adapter_generation: Adapter_Generation,
	policy_generation:  Policy_Generation,
	adapters:           []Adapter_Candidate,
	policies:           []Policy_Candidate,
}

/* Configuration_Descriptor exposes one immutable confirmed generation. */
Configuration_Descriptor :: struct {
	generation:         Configuration_Generation,
	adapter_generation: Adapter_Generation,
	policy_generation:  Policy_Generation,
	adapter_count:      u16,
	policy_count:       u16,
	retained_bytes:     u64,
	factory_fallback:   bool,
}

/* Adapter_Record borrows one confirmed copied adapter until replacement. */
Adapter_Record :: struct {
	identity:         string,
	language:         string,
	version:          string,
	class:            Availability_Class,
	in_process:       bool,
	runtime_required: bool,
	limits:           Limits,
}

/* Policy_Record borrows one confirmed copied policy until replacement. */
Policy_Record :: struct {
	identity:    string,
	adapter:     string,
	language:    string,
	origin:      Source_Origin,
	interactive: Authority_Decision,
	batch:       Authority_Decision,
	effects:     Effects,
}

/* Configuration owns one copied adapter and policy generation. */
Configuration :: struct {
	state: rawptr,
}

/* limits_are_valid checks all stable ceilings and mandatory execution limits. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.table_cells > 0 && limits.table_cells <= MAX_TABLE_CELLS &&
	       limits.formula_dependencies > 0 && limits.formula_dependencies <= MAX_FORMULA_DEPENDENCIES &&
	       limits.graph_depth > 0 && limits.graph_depth <= MAX_GRAPH_DEPTH &&
	       limits.executable_targets > 0 && limits.executable_targets <= MAX_EXECUTABLE_TARGETS &&
	       limits.active_sessions > 0 && limits.active_sessions <= MAX_ACTIVE_SESSIONS &&
	       limits.child_processes > 0 && limits.child_processes <= MAX_CHILD_PROCESSES &&
	       limits.output_bytes > 0 && limits.output_bytes <= MAX_OUTPUT_BYTES &&
	       limits.retained_output_bytes > 0 && limits.retained_output_bytes <= MAX_RETAINED_OUTPUT_BYTES &&
	       limits.generated_files > 0 && limits.generated_files <= MAX_GENERATED_FILES &&
	       limits.result_rows > 0 && limits.result_rows <= MAX_RESULT_ROWS &&
	       limits.cache_bytes > 0 && limits.cache_bytes <= MAX_CACHE_BYTES &&
	       limits.elapsed_milliseconds > 0 && limits.cpu_milliseconds > 0 &&
	       limits.rss_bytes > 0 && limits.environment_entries > 0
}

/* scope_is_valid checks exact source and computation generations. */
scope_is_valid :: proc(scope: Scope) -> bool {
	return language.jan_analysis_scope_is_valid(scope.analysis) &&
	       scope.configuration_generation != Configuration_Generation(0) &&
	       scope.adapter_generation != Adapter_Generation(0) &&
	       scope.policy_generation != Policy_Generation(0)
}

/* semantic_target_is_valid checks one target against its exact source scope. */
semantic_target_is_valid :: proc(target: Semantic_Target, scope: Scope) -> bool {
	return scope_is_valid(scope) && target.node_id != language.Jan_Node_ID(0) &&
	       target.kind != .Invalid && target.range.scope == scope.analysis &&
	       target.range.start < target.range.end &&
	       language.jan_source_range_is_valid(target.range, scope.source_bytes)
}

/* request_is_valid checks one complete explicit request without retaining input. */
request_is_valid :: proc(request: Request) -> bool {
	if request.operation_id == Operation_ID(0) || request.kind == .Invalid ||
	   request.invocation == .Invalid || !scope_is_valid(request.scope) ||
	   !limits_are_valid(request.limits) ||
	   len(request.targets) == 0 || len(request.targets) > int(request.limits.executable_targets) {
		return false
	}
	for target in request.targets do if !semantic_target_is_valid(target, request.scope) do return false
	return true
}

/* typed_result_descriptor_is_valid checks decoded result shape and bounds. */
typed_result_descriptor_is_valid :: proc(result: Typed_Result_Descriptor, limits := DEFAULT_LIMITS) -> bool {
	return result.operation_id != Operation_ID(0) && result.type != .Invalid &&
	       result.collection != .Invalid && result.format != .Invalid && result.handling != .Invalid &&
	       result.row_count <= limits.result_rows && result.byte_count <= limits.output_bytes
}

/* session_record_is_valid checks durable session identity and exact generations. */
session_record_is_valid :: proc(record: Session_Record) -> bool {
	return record.schema_version == COMPUTATION_SCHEMA_VERSION &&
	       record.session_id != Session_ID(0) && record.adapter_generation != Adapter_Generation(0) &&
	       record.policy_generation != Policy_Generation(0) && record.source_revision != 0 &&
	       record.state != .Invalid
}

/* cache_key_is_valid checks all digests and generations required for reuse. */
cache_key_is_valid :: proc(key: Cache_Key) -> bool {
	return digest_is_present(key.source_digest) && digest_is_present(key.argument_digest) &&
	       digest_is_present(key.input_digest) && digest_is_present(key.reference_digest) &&
	       digest_is_present(key.environment_digest) &&
	       digest_is_present(key.adapter_identity_digest) &&
	       digest_is_present(key.adapter_version_digest) &&
	       digest_is_present(key.cache_policy_digest) &&
	       key.adapter_generation != Adapter_Generation(0) && key.policy_generation != Policy_Generation(0)
}

/* extraction_descriptor_is_valid checks one complete bounded extraction plan. */
extraction_descriptor_is_valid :: proc(descriptor: Extraction_Descriptor, limits := DEFAULT_LIMITS) -> bool {
	return descriptor.operation_id != Operation_ID(0) && scope_is_valid(descriptor.scope) &&
	       descriptor.complete && descriptor.target_count > 0 &&
	       descriptor.target_count <= limits.executable_targets &&
	       descriptor.resource_count > 0 && descriptor.resource_count <= limits.generated_files
}

/* batch_descriptor_is_valid checks deterministic outcome accounting. */
batch_descriptor_is_valid :: proc(descriptor: Batch_Descriptor, limits := DEFAULT_LIMITS) -> bool {
	return descriptor.batch_id != Batch_ID(0) && descriptor.mode != .Invalid &&
	       descriptor.target_count > 0 && descriptor.target_count <= limits.executable_targets &&
	       descriptor.completed + descriptor.rejected + descriptor.unattempted == descriptor.target_count
}

/* computation_capability_declarations returns the complete non-operational family inventory. */
computation_capability_declarations :: proc() -> [11]Availability_Record {
	return {
		{capability = .Formulas, class = .Factory_Native, state = .Declared},
		{capability = .Text_Plots, class = .Factory_Native, state = .Declared},
		{capability = .Graphical_Plots, class = .Factory_Adapter, state = .Declared},
		{capability = .Execution, class = .Factory_Adapter, state = .Declared},
		{capability = .Results, class = .Factory_Native, state = .Declared},
		{capability = .Sessions, class = .Factory_Native, state = .Declared},
		{capability = .Cache, class = .Factory_Native, state = .Declared},
		{capability = .Source_Editing, class = .Factory_Native, state = .Declared},
		{capability = .Noweb, class = .Factory_Native, state = .Declared},
		{capability = .Tangling, class = .Factory_Native, state = .Declared},
		{capability = .Batch, class = .Factory_Native, state = .Declared},
	}
}

@(private)
digest_is_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
configuration_text_is_valid :: proc(value: string, maximum: int) -> bool {
	return len(value) > 0 && len(value) <= maximum && utf8.valid_string(value)
}
