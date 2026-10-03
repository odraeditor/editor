// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"

/* EXTENSION_API_VERSION identifies the admitted Jan extension contract. */
EXTENSION_API_VERSION :: u16(1)
/* MAX_EXTENSION_DEFINITIONS bounds one complete extension generation. */
MAX_EXTENSION_DEFINITIONS :: u16(128)
/* MAX_EXTENSION_INPUTS bounds copied inputs for one provider turn. */
MAX_EXTENSION_INPUTS :: u32(4_096)
/* MAX_EXTENSION_INPUT_BYTES bounds copied input values for one provider turn. */
MAX_EXTENSION_INPUT_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_EXTENSION_RESULT_BYTES bounds one extension result value. */
MAX_EXTENSION_RESULT_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_EXTENSION_TEMPORARY_RESOURCES bounds cleanup obligations for one turn. */
MAX_EXTENSION_TEMPORARY_RESOURCES :: u16(256)

/* Extension_Family identifies every admitted Jan contribution family. */
Extension_Family :: enum u8 {
	Invalid,
	Hook,
	Package,
	Property_Reader,
	Property_Writer,
	Tree_Mapper,
	Agenda_Source,
	Agenda_View,
	Capture_Template,
	Capture_Value,
	Custom_Link,
	Export_Backend,
	Derived_Backend,
	Export_Filter,
	Citation_Processor,
	Table_Translator,
	Dynamic_Block,
	Execution_Adapter,
	Publishing_Provider,
	Synchronization_Provider,
}

/* Extension_Operation identifies one closed provider entrypoint. */
Extension_Operation :: enum u8 {
	Invalid,
	Run_Hook,
	Compose_Package,
	Read_Property,
	Write_Property,
	Map_Tree,
	Supply_Agenda,
	Search_Agenda,
	Render_Agenda,
	Enrich_Agenda,
	Supply_Capture_Template,
	Supply_Capture_Value,
	Parse_Link,
	Complete_Link,
	Follow_Link,
	Store_Link,
	Export_Link,
	Preview_Link,
	Render_Backend,
	Filter_Output,
	Resolve_Citation,
	Translate_Table,
	Write_Dynamic_Block,
	Execute_Source,
	Publish,
	Synchronize,
}

/* Extension_Operations is one provider's exact supported operation set. */
Extension_Operations :: bit_set[Extension_Operation; u32]

/* Extension_Authority identifies requested capability without granting direct mutation. */
Extension_Authority :: enum u8 {
	Invalid,
	Inspect,
	Document_Read,
	Resource_Read,
	Propose_Document_Edit,
	Propose_Resource,
	Process,
	Network,
	Credential,
}

/* Extension_Authorities is one independently checked authority set. */
Extension_Authorities :: bit_set[Extension_Authority; u16]

/* Extension_Source identifies deterministic contribution provenance. */
Extension_Source :: enum u8 {
	Invalid,
	Factory,
	Package,
	User,
	Workspace,
	Project,
}

/* Extension_Result_Boundary constrains a provider to values or checked candidates. */
Extension_Result_Boundary :: enum u8 {
	Invalid,
	Read_Only,
	Result_Value,
	Document_Candidate,
	Resource_Candidate,
}

/* Extension_Failure_Policy defines contained provider-failure progression. */
Extension_Failure_Policy :: enum u8 {
	Invalid,
	Continue,
	Abort_Operation,
	Disable_Provider,
}

/* Extension_Result_State classifies one contained provider turn. */
Extension_Result_State :: enum u8 {
	Invalid,
	Completed,
	Failed,
	Cancelled,
	Unavailable,
}

/* Extension_Candidate_Kind identifies a checked proposal without applying it. */
Extension_Candidate_Kind :: enum u8 {
	None,
	Document,
	Resource,
}

/* Extension_Lifecycle_Event identifies a confirmed hook boundary. */
Extension_Lifecycle_Event :: enum u8 {
	Invalid,
	Document_Opened,
	Analysis_Confirmed,
	Before_Save,
	After_Save,
	Before_Export,
	After_Export,
	Before_Publish,
	After_Publish,
	Synchronization_Confirmed,
}

/* Extension_Property_Access identifies one confirmed property interpretation. */
Extension_Property_Access :: enum u8 {
	Invalid,
	Local,
	Inherited,
	Additive,
	Derived,
	Write,
}

/* Extension_Map_Scope identifies an explicit admitted traversal boundary. */
Extension_Map_Scope :: enum u8 {
	Invalid,
	Document,
	Subtree,
	Selection,
	Agenda,
}

/* Extension_Definition is one copied inert provider declaration. */
Extension_Definition :: struct {
	identity:              string,
	generation:            Provider_Generation,
	family:                Extension_Family,
	source:                Extension_Source,
	order:                 i32,
	api_version:           u16,
	operations:            Extension_Operations,
	authorities:           Extension_Authorities,
	boundary:              Extension_Result_Boundary,
	failure_policy:        Extension_Failure_Policy,
	parent_identity:       string,
	parent_generation:     Provider_Generation,
	input_limit:           u32,
	input_byte_limit:      u64,
	result_limit:          u32,
	output_byte_limit:     u64,
	temporary_limit:       u16,
	state:                 Availability_State,
	admitted:              bool,
	complete:              bool,
}

/* Extension_Catalog_Request replaces one complete exact catalog generation. */
Extension_Catalog_Request :: struct {
	configuration_generation: Configuration_Generation,
	catalog_generation:       Provider_Generation,
	replaces_generation:      Provider_Generation,
	definition_limit:         u16,
	catalog_digest:           [32]u8,
	explicit:                 bool,
	cancelled:                bool,
}

/* Extension_Catalog_Record is one immutable admitted provider generation. */
Extension_Catalog_Record :: struct {
	configuration_generation: Configuration_Generation,
	catalog_generation:       Provider_Generation,
	definition_count:         u16,
	available_count:          u16,
	catalog_digest:           [32]u8,
	complete:                 bool,
}

/* Extension_Invocation_Request binds one provider turn to exact current state. */
Extension_Invocation_Request :: struct {
	operation_id:             Operation_ID,
	configuration_generation: Configuration_Generation,
	catalog_generation:       Provider_Generation,
	provider_identity:        string,
	provider_generation:      Provider_Generation,
	family:                   Extension_Family,
	operation:                Extension_Operation,
	resource_id:              u64,
	resource_revision:        u64,
	granted_authorities:      Extension_Authorities,
	input_count:              u32,
	input_bytes:              u64,
	result_count_limit:       u32,
	output_byte_limit:        u64,
	temporary_resource_limit: u16,
	explicit:                 bool,
	cancelled:                bool,
}

/* Extension_Invocation_Plan is one copied bounded non-reentrant provider handoff. */
Extension_Invocation_Plan :: struct {
	operation_id:             Operation_ID,
	configuration_generation: Configuration_Generation,
	catalog_generation:       Provider_Generation,
	provider_identity:        string,
	provider_generation:      Provider_Generation,
	family:                   Extension_Family,
	operation:                Extension_Operation,
	resource_id:              u64,
	resource_revision:        u64,
	authorities:              Extension_Authorities,
	boundary:                 Extension_Result_Boundary,
	failure_policy:           Extension_Failure_Policy,
	input_count:              u32,
	input_bytes:              u64,
	result_count_limit:       u32,
	output_byte_limit:        u64,
	temporary_resource_limit: u16,
	complete:                 bool,
}

/* Extension_Result records one bounded value or unapplied checked candidate. */
Extension_Result :: struct {
	operation_id:               Operation_ID,
	provider_identity:          string,
	provider_generation:        Provider_Generation,
	state:                      Extension_Result_State,
	result_count:               u32,
	result_bytes:               u64,
	candidate_kind:             Extension_Candidate_Kind,
	candidate_id:               u64,
	expected_resource_revision: u64,
	result_digest:              [32]u8,
	temporary_created:          u16,
	temporary_cleaned:          u16,
	retained_native_bytes:      u64,
	mutated_directly:           bool,
	complete:                   bool,
}

/* Extension_Failure_Disposition contains one policy outcome without mutating the catalog. */
Extension_Failure_Disposition :: struct {
	catalog_generation:  Provider_Generation,
	provider_identity:   string,
	provider_generation: Provider_Generation,
	policy:              Extension_Failure_Policy,
	continue_operation:  bool,
	abort_operation:     bool,
	disable_candidate:   bool,
	complete:            bool,
}

/* Extension_Hook_Request binds a hook to one confirmed lifecycle event. */
Extension_Hook_Request :: struct {
	invocation: Extension_Invocation_Request,
	event:      Extension_Lifecycle_Event,
	mutating:   bool,
}

/* Extension_Property_Request binds property work to one copied node value. */
Extension_Property_Request :: struct {
	invocation:    Extension_Invocation_Request,
	access:        Extension_Property_Access,
	property:      string,
	node_id:       u64,
	value_bytes:   u64,
	semantic_write: bool,
}

/* Extension_Tree_Map_Request bounds traversal without exposing native nodes. */
Extension_Tree_Map_Request :: struct {
	invocation:      Extension_Invocation_Request,
	scope:           Extension_Map_Scope,
	match_identity:  string,
	prune:           bool,
	include_archived: bool,
	include_comments: bool,
	restricted:      bool,
	stable_order:    bool,
	node_limit:      u32,
	result_limit:    u32,
}

/* Extension_Inspection_Record exposes active provider truth without callbacks. */
Extension_Inspection_Record :: struct {
	catalog_generation:  Provider_Generation,
	identity:            string,
	provider_generation: Provider_Generation,
	family:              Extension_Family,
	source:              Extension_Source,
	order:               i32,
	operations:          Extension_Operations,
	authorities:         Extension_Authorities,
	boundary:            Extension_Result_Boundary,
	failure_policy:      Extension_Failure_Policy,
	state:               Availability_State,
	active:              bool,
}

/* Extension_Conformance_Record summarizes provider-contract evidence. */
Extension_Conformance_Record :: struct {
	catalog_generation:       Provider_Generation,
	family_count:             u16,
	provider_count:           u16,
	copied_values:            bool,
	deterministic_order:      bool,
	stale_rejection:          bool,
	authority_constrained:    bool,
	mutation_candidate_only:  bool,
	failure_contained:        bool,
	limits_enforced:          bool,
	cleanup_complete:         bool,
	inspection_complete:      bool,
}

/* prepare_extension_catalog validates and sorts one atomic replacement generation. */
prepare_extension_catalog :: proc(
	request: Extension_Catalog_Request,
	confirmed_generation: Provider_Generation,
	candidates: []Extension_Definition,
	output: []Extension_Definition,
) -> (Extension_Catalog_Record, bool, Failure) {
	if request.configuration_generation == Configuration_Generation(0) ||
	   request.catalog_generation == Provider_Generation(0) ||
	   request.catalog_generation <= confirmed_generation || request.replaces_generation != confirmed_generation ||
	   request.definition_limit == 0 || request.definition_limit > MAX_EXTENSION_DEFINITIONS ||
	   len(candidates) == 0 || len(candidates) > int(request.definition_limit) || len(output) < len(candidates) ||
	   !extension_digest_present(request.catalog_digest) || !request.explicit {
		return {}, false, extension_failure(0, .Invalid_Request, .Extension)
	}
	if request.cancelled do return {}, false, extension_failure(0, .Cancelled, .Extension)
	available_count: u16
	for candidate, index in candidates {
		if !extension_definition_is_valid(candidate) {
			return {}, false, extension_failure(0, .Malformed, .Extension)
		}
		for prior in candidates[:index] do if prior.identity == candidate.identity {
			return {}, false, extension_failure(0, .Conflict, .Extension)
		}
		if candidate.family == .Derived_Backend && !extension_derived_chain_is_valid(candidate, candidates) {
			return {}, false, extension_failure(0, .Cycle, .Backend)
		}
		output[index] = candidate
		if candidate.state == .Available && candidate.admitted do available_count += 1
	}
	for index in 1..<len(candidates) {
		value := output[index]
		cursor := index
		for cursor > 0 && extension_definition_less(value, output[cursor - 1]) {
			output[cursor] = output[cursor - 1]
			cursor -= 1
		}
		output[cursor] = value
	}
	return {
		configuration_generation = request.configuration_generation,
		catalog_generation = request.catalog_generation,
		definition_count = u16(len(candidates)),
		available_count = available_count,
		catalog_digest = request.catalog_digest,
		complete = true,
	}, true, {}
}

/* prepare_extension_invocation selects one exact provider and checks caller authority. */
prepare_extension_invocation :: proc(
	request: Extension_Invocation_Request,
	catalog: Extension_Catalog_Record,
	definitions: []Extension_Definition,
) -> (Extension_Invocation_Plan, bool, Failure) {
	if !extension_catalog_record_is_valid(catalog) || request.operation_id == Operation_ID(0) ||
	   request.configuration_generation != catalog.configuration_generation ||
	   request.catalog_generation != catalog.catalog_generation ||
	   !output_text_is_valid(request.provider_identity, MAX_IDENTITY_BYTES) ||
	   request.provider_generation == Provider_Generation(0) || request.family == .Invalid ||
	   request.operation == .Invalid || request.resource_id == 0 || request.resource_revision == 0 ||
	   request.input_count == 0 || request.input_count > MAX_EXTENSION_INPUTS || request.input_bytes == 0 ||
	   request.input_bytes > MAX_EXTENSION_INPUT_BYTES || request.result_count_limit == 0 ||
	   request.result_count_limit > MAX_EXTENSION_INPUTS ||
	   request.output_byte_limit == 0 || request.output_byte_limit > MAX_EXTENSION_RESULT_BYTES ||
	   request.temporary_resource_limit > MAX_EXTENSION_TEMPORARY_RESOURCES ||
	   len(definitions) != int(catalog.definition_count) || !request.explicit {
		return {}, false, extension_failure(request.operation_id, .Invalid_Request, .Extension)
	}
	if request.cancelled do return {}, false, extension_failure(request.operation_id, .Cancelled, .Extension)
	selected: Extension_Definition
	found := false
	for definition, index in definitions {
		if !extension_definition_is_valid(definition) {
			return {}, false, extension_failure(request.operation_id, .Malformed, .Extension)
		}
		for prior in definitions[:index] do if prior.identity == definition.identity {
			return {}, false, extension_failure(request.operation_id, .Conflict, .Extension)
		}
		if definition.identity != request.provider_identity do continue
		selected = definition
		found = true
	}
	if !found do return {}, false, extension_failure(request.operation_id, .Missing, .Extension)
	if selected.generation != request.provider_generation || selected.family != request.family {
		return {}, false, extension_failure(request.operation_id, .Stale, .Generation)
	}
	if selected.state != .Available do return {}, false, extension_failure(request.operation_id, .Unavailable, .Extension)
	if !selected.admitted do return {}, false, extension_failure(request.operation_id, .Unauthorized, .Extension)
	if request.operation not_in selected.operations do return {}, false, extension_failure(request.operation_id, .Unsupported, .Extension)
	if !extension_authorities_are_subset(request.granted_authorities, selected.authorities) ||
	   .Inspect not_in request.granted_authorities {
		return {}, false, extension_failure(request.operation_id, .Unauthorized, .Extension)
	}
	if request.input_count > selected.input_limit || request.input_bytes > selected.input_byte_limit ||
	   request.result_count_limit > selected.result_limit ||
	   request.output_byte_limit > selected.output_byte_limit ||
	   request.temporary_resource_limit > selected.temporary_limit {
		return {}, false, extension_failure(request.operation_id, .Limited, .Limit)
	}
	return {
		operation_id = request.operation_id,
		configuration_generation = request.configuration_generation,
		catalog_generation = request.catalog_generation,
		provider_identity = selected.identity,
		provider_generation = selected.generation,
		family = selected.family,
		operation = request.operation,
		resource_id = request.resource_id,
		resource_revision = request.resource_revision,
		authorities = request.granted_authorities,
		boundary = selected.boundary,
		failure_policy = selected.failure_policy,
		input_count = request.input_count,
		input_bytes = request.input_bytes,
		result_count_limit = request.result_count_limit,
		output_byte_limit = request.output_byte_limit,
		temporary_resource_limit = request.temporary_resource_limit,
		complete = true,
	}, true, {}
}

/* extension_result_is_valid contains failures and forbids direct provider mutation. */
extension_result_is_valid :: proc(plan: Extension_Invocation_Plan, result: Extension_Result) -> bool {
	if !plan.complete || result.operation_id != plan.operation_id ||
	   result.provider_identity != plan.provider_identity || result.provider_generation != plan.provider_generation ||
	   result.state == .Invalid || result.mutated_directly ||
	   result.temporary_created > plan.temporary_resource_limit ||
	   result.temporary_cleaned != result.temporary_created ||
	   result.retained_native_bytes != 0 { return false }
	if result.state != .Completed {
		return !result.complete && result.result_count == 0 && result.result_bytes == 0 &&
		       result.candidate_kind == .None && result.candidate_id == 0 &&
		       result.expected_resource_revision == 0 && !extension_digest_present(result.result_digest)
	}
	if !result.complete || result.result_count == 0 || result.result_count > plan.result_count_limit ||
	   result.result_bytes > plan.output_byte_limit || !extension_digest_present(result.result_digest) { return false }
	switch plan.boundary {
	case .Read_Only, .Result_Value:
		return result.candidate_kind == .None && result.candidate_id == 0 && result.expected_resource_revision == 0
	case .Document_Candidate:
		return result.candidate_kind == .Document && result.candidate_id != 0 &&
		       result.expected_resource_revision == plan.resource_revision
	case .Resource_Candidate:
		return result.candidate_kind == .Resource && result.candidate_id != 0 &&
		       result.expected_resource_revision == plan.resource_revision
	case .Invalid:
	}
	return false
}

/* extension_failure_disposition applies declared policy without replacing active state. */
extension_failure_disposition :: proc(
	plan: Extension_Invocation_Plan,
	result: Extension_Result,
) -> (Extension_Failure_Disposition, bool) {
	if !extension_result_is_valid(plan, result) || result.state == .Completed do return {}, false
	disposition := Extension_Failure_Disposition {
		catalog_generation = plan.catalog_generation,
		provider_identity = plan.provider_identity,
		provider_generation = plan.provider_generation,
		policy = plan.failure_policy,
		complete = true,
	}
	switch plan.failure_policy {
	case .Continue: disposition.continue_operation = true
	case .Abort_Operation: disposition.abort_operation = true
	case .Disable_Provider: disposition.disable_candidate = true
	case .Invalid: return {}, false
	}
	return disposition, true
}

/* extension_hook_request_is_valid enforces confirmed events and candidate-only mutation. */
extension_hook_request_is_valid :: proc(request: Extension_Hook_Request) -> bool {
	if request.event == .Invalid || request.invocation.family != .Hook ||
	   request.invocation.operation != .Run_Hook { return false }
	if request.mutating {
		return .Propose_Document_Edit in request.invocation.granted_authorities
	}
	return .Propose_Document_Edit not_in request.invocation.granted_authorities
}

/* extension_property_request_is_valid separates copied reads from semantic writes. */
extension_property_request_is_valid :: proc(request: Extension_Property_Request) -> bool {
	if request.access == .Invalid || !output_text_is_valid(request.property, MAX_IDENTITY_BYTES) ||
	   request.node_id == 0 || request.value_bytes > MAX_SETTING_VALUE_BYTES { return false }
	if request.access == .Write {
		return request.semantic_write && request.invocation.family == .Property_Writer &&
		       request.invocation.operation == .Write_Property &&
		       .Propose_Document_Edit in request.invocation.granted_authorities
	}
	return !request.semantic_write && request.invocation.family == .Property_Reader &&
	       request.invocation.operation == .Read_Property && request.value_bytes == 0
}

/* extension_tree_map_request_is_valid bounds traversal over copied nodes. */
extension_tree_map_request_is_valid :: proc(request: Extension_Tree_Map_Request) -> bool {
	return request.invocation.family == .Tree_Mapper && request.invocation.operation == .Map_Tree &&
	       request.scope != .Invalid && request.stable_order && request.node_limit > 0 &&
	       request.node_limit <= MAX_NORMALIZED_NODES && request.result_limit > 0 &&
	       request.result_limit <= request.node_limit &&
	       (len(request.match_identity) == 0 || output_text_is_valid(request.match_identity, MAX_IDENTITY_BYTES))
}

/* inspect_extension_provider returns exact active declaration metadata only. */
inspect_extension_provider :: proc(
	catalog: Extension_Catalog_Record,
	definitions: []Extension_Definition,
	identity: string,
) -> (Extension_Inspection_Record, bool) {
	if !extension_catalog_record_is_valid(catalog) || !output_text_is_valid(identity, MAX_IDENTITY_BYTES) ||
	   len(definitions) != int(catalog.definition_count) { return {}, false }
	found := false
	selected: Extension_Definition
	for definition, index in definitions {
		if !extension_definition_is_valid(definition) do return {}, false
		for prior in definitions[:index] do if prior.identity == definition.identity do return {}, false
		if definition.identity == identity {
			selected = definition
			found = true
		}
	}
	if !found do return {}, false
	return {
		catalog_generation = catalog.catalog_generation,
		identity = selected.identity,
		provider_generation = selected.generation,
		family = selected.family,
		source = selected.source,
		order = selected.order,
		operations = selected.operations,
		authorities = selected.authorities,
		boundary = selected.boundary,
		failure_policy = selected.failure_policy,
		state = selected.state,
		active = selected.admitted && selected.state == .Available,
	}, true
}

/* extension_conformance_is_complete checks the full family and safety ledger. */
extension_conformance_is_complete :: proc(record: Extension_Conformance_Record) -> bool {
	return record.catalog_generation != Provider_Generation(0) &&
	       record.family_count == u16(Extension_Family.Synchronization_Provider) &&
	       record.provider_count >= record.family_count && record.copied_values &&
	       record.deterministic_order && record.stale_rejection && record.authority_constrained &&
	       record.mutation_candidate_only && record.failure_contained && record.limits_enforced &&
	       record.cleanup_complete && record.inspection_complete
}

@(private)
extension_catalog_record_is_valid :: proc(record: Extension_Catalog_Record) -> bool {
	return record.configuration_generation != Configuration_Generation(0) &&
	       record.catalog_generation != Provider_Generation(0) && record.definition_count > 0 &&
	       record.definition_count <= MAX_EXTENSION_DEFINITIONS &&
	       record.available_count <= record.definition_count && extension_digest_present(record.catalog_digest) &&
	       record.complete
}

@(private)
extension_definition_is_valid :: proc(definition: Extension_Definition) -> bool {
	if !output_text_is_valid(definition.identity, MAX_IDENTITY_BYTES) ||
	   definition.generation == Provider_Generation(0) || definition.family == .Invalid ||
	   definition.source == .Invalid || definition.api_version != EXTENSION_API_VERSION ||
	   card(definition.operations) == 0 || .Inspect not_in definition.authorities ||
	   definition.boundary == .Invalid || definition.failure_policy == .Invalid ||
	   definition.input_limit == 0 || definition.input_limit > MAX_EXTENSION_INPUTS ||
	   definition.input_byte_limit == 0 || definition.input_byte_limit > MAX_EXTENSION_INPUT_BYTES ||
	   definition.result_limit == 0 || definition.result_limit > MAX_EXTENSION_INPUTS ||
	   definition.output_byte_limit == 0 ||
	   definition.output_byte_limit > MAX_EXTENSION_RESULT_BYTES ||
	   definition.temporary_limit > MAX_EXTENSION_TEMPORARY_RESOURCES ||
	   definition.state == .Invalid || !definition.complete { return false }
	for operation in definition.operations do if !extension_operation_allowed(definition.family, operation) do return false
	if !extension_boundary_allowed(definition.family, definition.boundary) do return false
	if (definition.boundary == .Document_Candidate) != (.Propose_Document_Edit in definition.authorities) ||
	   (definition.boundary == .Resource_Candidate) != (.Propose_Resource in definition.authorities) {
		return false
	}
	if definition.family == .Derived_Backend {
		return output_text_is_valid(definition.parent_identity, MAX_IDENTITY_BYTES) &&
		       definition.parent_identity != definition.identity &&
		       definition.parent_generation != Provider_Generation(0)
	}
	return len(definition.parent_identity) == 0 && definition.parent_generation == Provider_Generation(0)
}

@(private)
extension_operation_allowed :: proc(family: Extension_Family, operation: Extension_Operation) -> bool {
	switch family {
	case .Hook: return operation == .Run_Hook
	case .Package: return operation == .Compose_Package
	case .Property_Reader: return operation == .Read_Property
	case .Property_Writer: return operation == .Write_Property
	case .Tree_Mapper: return operation == .Map_Tree
	case .Agenda_Source: return operation == .Supply_Agenda || operation == .Search_Agenda
	case .Agenda_View: return operation == .Render_Agenda || operation == .Enrich_Agenda
	case .Capture_Template: return operation == .Supply_Capture_Template
	case .Capture_Value: return operation == .Supply_Capture_Value
	case .Custom_Link:
		return operation >= .Parse_Link && operation <= .Preview_Link
	case .Export_Backend, .Derived_Backend: return operation == .Render_Backend
	case .Export_Filter: return operation == .Filter_Output
	case .Citation_Processor: return operation == .Resolve_Citation
	case .Table_Translator: return operation == .Translate_Table
	case .Dynamic_Block: return operation == .Write_Dynamic_Block
	case .Execution_Adapter: return operation == .Execute_Source
	case .Publishing_Provider: return operation == .Publish
	case .Synchronization_Provider: return operation == .Synchronize
	case .Invalid:
	}
	return false
}

@(private)
extension_boundary_allowed :: proc(family: Extension_Family, boundary: Extension_Result_Boundary) -> bool {
	switch family {
	case .Hook: return boundary == .Read_Only || boundary == .Document_Candidate
	case .Package, .Property_Reader, .Tree_Mapper, .Agenda_Source, .Agenda_View, .Capture_Template, .Capture_Value:
		return boundary == .Read_Only || boundary == .Result_Value
	case .Property_Writer, .Dynamic_Block: return boundary == .Document_Candidate
	case .Custom_Link:
		return boundary == .Result_Value || boundary == .Document_Candidate || boundary == .Resource_Candidate
	case .Export_Backend, .Derived_Backend, .Export_Filter, .Citation_Processor, .Table_Translator:
		return boundary == .Result_Value || boundary == .Resource_Candidate
	case .Execution_Adapter, .Publishing_Provider, .Synchronization_Provider:
		return boundary == .Result_Value || boundary == .Document_Candidate || boundary == .Resource_Candidate
	case .Invalid:
	}
	return false
}

@(private)
extension_derived_chain_is_valid :: proc(definition: Extension_Definition, definitions: []Extension_Definition) -> bool {
	current := definition
	for _ in 0..<len(definitions) {
		if current.family != .Derived_Backend do return current.family == .Export_Backend
		found := false
		parent: Extension_Definition
		for candidate in definitions do if candidate.identity == current.parent_identity &&
		   candidate.generation == current.parent_generation {
			if found do return false
			parent = candidate
			found = true
		}
		if !found || parent.identity == definition.identity do return false
		current = parent
	}
	return false
}

@(private)
extension_definition_less :: proc(left, right: Extension_Definition) -> bool {
	if left.family != right.family do return left.family < right.family
	if left.order != right.order do return left.order < right.order
	if left.source != right.source do return left.source < right.source
	return strings.compare(left.identity, right.identity) < 0
}

@(private)
extension_authorities_are_subset :: proc(requested, declared: Extension_Authorities) -> bool {
	for authority in requested do if authority not_in declared do return false
	return true
}

@(private)
extension_digest_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
extension_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Extend, code = code, field = field}
}
