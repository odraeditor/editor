// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

/* EXTERNAL_PROTOCOL_SCHEMA_VERSION is the only admitted external request schema. */
EXTERNAL_PROTOCOL_SCHEMA_VERSION :: 1
/* MAX_PROTOCOL_WINDOW_SECONDS bounds request validity independently from transport. */
MAX_PROTOCOL_WINDOW_SECONDS :: 15 * 60
/* MAX_PROTOCOL_VALUES bounds decoded capture and link values. */
MAX_PROTOCOL_VALUES :: 256
/* MAX_PROTOCOL_PROVENANCE_BYTES bounds copied caller and location identities. */
MAX_PROTOCOL_PROVENANCE_BYTES :: 4 * 1_024

/* Protocol_Provider_Capability identifies one effect family a provider can plan. */
Protocol_Provider_Capability :: enum u8 {
	Invalid,
	Follow_Link,
	Store_Link,
	Search_Links,
	Preview_Link,
	Intake_Media,
	Start_Capture,
	Open_Source,
}

/* Protocol_Provider_Capabilities is one closed provider capability set. */
Protocol_Provider_Capabilities :: bit_set[Protocol_Provider_Capability; u16]

/* Link_Provider_Action identifies one Jan link or media operation. */
Link_Provider_Action :: enum u8 {
	Invalid,
	Follow,
	Store,
	Search,
	Preview,
	Media_Intake,
}

/* Protocol_Dispatch_Action identifies one admitted external entrypoint. */
Protocol_Dispatch_Action :: enum u8 {
	Invalid,
	Store_Link,
	Start_Capture,
	Open_Source,
}

/* Protocol_Location_Kind identifies one checked source-location hint. */
Protocol_Location_Kind :: enum u8 {
	Invalid,
	Source_Block,
	Structural_Node,
}

/* Protocol_Value_Kind is the closed non-executable initial-value vocabulary. */
Protocol_Value_Kind :: enum u8 {
	Invalid,
	Url,
	Title,
	Body,
	Selection,
	Annotation,
}

/* Protocol_Value_Kinds tracks unique decoded request value kinds. */
Protocol_Value_Kinds :: bit_set[Protocol_Value_Kind; u16]

/* Protocol_Replay_State identifies a retained request nonce boundary. */
Protocol_Replay_State :: enum u8 {
	Invalid,
	Reserved,
	Consumed,
}

/* Protocol_Result_State identifies one provider or command outcome. */
Protocol_Result_State :: enum u8 {
	Invalid,
	Completed,
	Cancelled,
	Failed,
}

/* Protocol_Provider_Descriptor is one copied admitted provider observation. */
Protocol_Provider_Descriptor :: struct {
	identity:                string,
	generation:              Provider_Generation,
	capabilities:            Protocol_Provider_Capabilities,
	state:                   Availability_State,
	admitted:                bool,
	authentication_required: bool,
	authentication_generation: u64,
}

/* Link_Provider_Request binds a Jan link or media action to exact resources. */
Link_Provider_Request :: struct {
	operation_id:          Operation_ID,
	action:                Link_Provider_Action,
	provider_identity:     string,
	provider_generation:   Provider_Generation,
	source_resource_id:    u64,
	source_revision:       u64,
	destination_resource_id: u64,
	expected_destination_revision: u64,
	locator:               string,
	query:                 string,
	expected_bytes:        u64,
	result_limit:          u32,
	authenticated:         bool,
	authentication_generation: u64,
	explicit:              bool,
	cancelled:             bool,
}

/* Link_Effect_Plan exposes required owners without executing their effects. */
Link_Effect_Plan :: struct {
	operation_id:        Operation_ID,
	action:              Link_Provider_Action,
	provider_identity:   string,
	provider_generation: Provider_Generation,
	source_resource_id:  u64,
	source_revision:     u64,
	destination_resource_id: u64,
	expected_destination_revision: u64,
	locator:             string,
	query:               string,
	byte_limit:          u64,
	result_limit:        u32,
	resource_read:       bool,
	resource_write:      bool,
	navigation:          bool,
	preview:             bool,
	complete:            bool,
}

/* Link_Provider_Result is one copied exact-request provider outcome. */
Link_Provider_Result :: struct {
	operation_id:        Operation_ID,
	provider_identity:   string,
	provider_generation: Provider_Generation,
	state:               Protocol_Result_State,
	resource_id:         u64,
	resource_revision:   u64,
	result_count:        u32,
	byte_count:          u64,
	complete:            bool,
}

/* Protocol_Initial_Value is one bounded decoded non-executable request value. */
Protocol_Initial_Value :: struct {
	kind:      Protocol_Value_Kind,
	value:     string,
	sensitive: bool,
}

/* External_Protocol_Request is one authenticated versioned request envelope. */
External_Protocol_Request :: struct {
	envelope:                Protocol_Request,
	schema_version:          u16,
	action:                  Protocol_Dispatch_Action,
	provider_identity:       string,
	caller_identity:         string,
	caller_instance:         string,
	caller_generation:       u64,
	issued_at:               u64,
	expires_at:              u64,
	observed_at:             u64,
	nonce_digest:            [32]u8,
	payload_digest:          [32]u8,
	authentication_generation: u64,
	authenticated:           bool,
	target_resource_id:      u64,
	target_revision:         u64,
	locator:                 string,
	template_identity:       string,
	template_generation:     Configuration_Generation,
	location_kind:           Protocol_Location_Kind,
	location_identity:       string,
	values:                  []Protocol_Initial_Value,
	cancelled:               bool,
}

/* Protocol_Replay_Record reserves or consumes one exact caller nonce. */
Protocol_Replay_Record :: struct {
	caller_identity:   string,
	caller_generation: u64,
	operation_id:      Operation_ID,
	nonce_digest:      [32]u8,
	expires_at:        u64,
	state:             Protocol_Replay_State,
}

/* Protocol_Dispatch_Plan is a copied command/resource handoff without payload text. */
Protocol_Dispatch_Plan :: struct {
	operation_id:        Operation_ID,
	action:              Protocol_Dispatch_Action,
	provider_identity:   string,
	provider_generation: Provider_Generation,
	schema_version:      u16,
	caller_identity:     string,
	caller_instance:     string,
	caller_generation:   u64,
	authentication_generation: u64,
	nonce_digest:        [32]u8,
	payload_digest:      [32]u8,
	target_resource_id:  u64,
	target_revision:     u64,
	value_count:         u16,
	sensitive_value_count: u16,
	link_state_change:   bool,
	document_change:     bool,
	navigation:          bool,
	complete:            bool,
}

/* Protocol_Dispatch_Result records one exact command result without request contents. */
Protocol_Dispatch_Result :: struct {
	operation_id:      Operation_ID,
	provider_identity: string,
	provider_generation: Provider_Generation,
	state:             Protocol_Result_State,
	link_state_changed: bool,
	document_changed:   bool,
	navigation_changed: bool,
	complete:           bool,
}

/* prepare_link_effect validates provider authority and returns a non-effectful plan. */
prepare_link_effect :: proc(
	request: Link_Provider_Request,
	providers: []Protocol_Provider_Descriptor,
	limits := DEFAULT_LIMITS,
) -> (Link_Effect_Plan, bool, Failure) {
	if !limits_are_valid(limits) || request.operation_id == Operation_ID(0) || request.action == .Invalid ||
	   !output_text_is_valid(request.provider_identity, MAX_IDENTITY_BYTES) ||
	   request.provider_generation == Provider_Generation(0) || !request.explicit {
		return {}, false, external_protocol_failure(request.operation_id, .Invalid_Request, .Protocol)
	}
	if request.cancelled do return {}, false, external_protocol_failure(request.operation_id, .Cancelled, .Protocol)
	if request.result_limit > limits.links || request.expected_bytes > limits.output_bytes {
		return {}, false, external_protocol_failure(request.operation_id, .Limited, .Limit)
	}
	if !link_request_shape_is_valid(request, limits) {
		return {}, false, external_protocol_failure(request.operation_id, .Malformed, .Protocol)
	}
	provider, found, failure := select_protocol_provider(request.operation_id, request.provider_identity,
		request.provider_generation, link_action_capability(request.action), providers)
	if failure.code != .None do return {}, false, failure
	if !found do return {}, false, external_protocol_failure(request.operation_id, .Missing, .Protocol)
	if provider.authentication_required && !request.authenticated {
		return {}, false, external_protocol_failure(request.operation_id, .Unauthorized, .Protocol)
	}
	if provider.authentication_required && request.authentication_generation != provider.authentication_generation {
		return {}, false, external_protocol_failure(request.operation_id, .Unauthorized, .Generation)
	}
	plan := Link_Effect_Plan {operation_id = request.operation_id, action = request.action,
		provider_identity = provider.identity, provider_generation = provider.generation,
		source_resource_id = request.source_resource_id, source_revision = request.source_revision,
		destination_resource_id = request.destination_resource_id,
		expected_destination_revision = request.expected_destination_revision,
		locator = request.locator, query = request.query,
		byte_limit = request.expected_bytes, result_limit = request.result_limit, complete = true}
	switch request.action {
	case .Follow:
		plan.resource_read = true
		plan.navigation = true
	case .Store:
		plan.resource_read = true
	case .Search:
		plan.resource_read = true
	case .Preview:
		plan.resource_read = true
		plan.preview = true
	case .Media_Intake:
		plan.resource_read = true
		plan.resource_write = true
	case .Invalid:
	}
	return plan, true, {}
}

/* link_provider_result_is_valid checks exact provider outcomes and no-effect failures. */
link_provider_result_is_valid :: proc(plan: Link_Effect_Plan, result: Link_Provider_Result) -> bool {
	if !plan.complete || result.operation_id != plan.operation_id || result.provider_identity != plan.provider_identity ||
	   result.provider_generation != plan.provider_generation || result.state == .Invalid { return false }
	if result.state == .Cancelled || result.state == .Failed {
		return !result.complete && result.resource_id == 0 && result.resource_revision == 0 &&
		       result.result_count == 0 && result.byte_count == 0
	}
	if !result.complete || result.result_count > plan.result_limit || result.byte_count > plan.byte_limit do return false
	switch plan.action {
	case .Follow:
		return result.resource_id != 0 && result.resource_revision != 0
	case .Store:
		return result.byte_count > 0
	case .Search:
		return result.result_count > 0
	case .Preview:
		return result.byte_count > 0
	case .Media_Intake:
		return result.resource_id == plan.destination_resource_id && result.resource_revision != 0 && result.byte_count > 0
	case .Invalid:
	}
	return false
}

/* prepare_external_protocol_dispatch admits authenticated fresh requests before command dispatch. */
prepare_external_protocol_dispatch :: proc(
	request: External_Protocol_Request,
	providers: []Protocol_Provider_Descriptor,
	replay_records: []Protocol_Replay_Record,
	limits := DEFAULT_LIMITS,
) -> (Protocol_Dispatch_Plan, Protocol_Replay_Record, bool, Failure) {
	operation_id := request.envelope.operation_id
	if !protocol_request_is_valid(request.envelope, limits) {
		code := Failure_Code.Invalid_Request
		field := Failure_Field.Protocol
		if request.envelope.payload_bytes > limits.protocol_payload_bytes {
			code = .Limited
			field = .Limit
		}
		return {}, {}, false, external_protocol_failure(operation_id, code, field)
	}
	if request.schema_version != EXTERNAL_PROTOCOL_SCHEMA_VERSION || request.action == .Invalid ||
	   !output_text_is_valid(request.provider_identity, MAX_IDENTITY_BYTES) ||
	   !output_text_is_valid(request.caller_identity, MAX_PROTOCOL_PROVENANCE_BYTES) ||
	   !output_text_is_valid(request.caller_instance, MAX_PROTOCOL_PROVENANCE_BYTES) ||
	   request.caller_generation == 0 || request.issued_at == 0 || request.expires_at < request.issued_at ||
	   request.expires_at - request.issued_at > MAX_PROTOCOL_WINDOW_SECONDS ||
	   !external_protocol_digest_present(request.nonce_digest) ||
	   !external_protocol_digest_present(request.payload_digest) {
		return {}, {}, false, external_protocol_failure(operation_id, .Malformed, .Protocol)
	}
	if request.authentication_generation == 0 || !request.authenticated {
		return {}, {}, false, external_protocol_failure(operation_id, .Unauthorized, .Protocol)
	}
	if request.observed_at < request.issued_at || request.observed_at > request.expires_at {
		return {}, {}, false, external_protocol_failure(operation_id, .Stale, .Protocol)
	}
	if request.cancelled do return {}, {}, false, external_protocol_failure(operation_id, .Cancelled, .Protocol)
	if !external_request_shape_is_valid(request, limits) {
		return {}, {}, false, external_protocol_failure(operation_id, .Malformed, .Protocol)
	}
	for record in replay_records {
		if !protocol_replay_record_is_valid(record) {
			return {}, {}, false, external_protocol_failure(operation_id, .Malformed, .Protocol)
		}
		if record.caller_identity == request.caller_identity && record.caller_generation == request.caller_generation &&
		   (record.operation_id == operation_id || record.nonce_digest == request.nonce_digest) {
			return {}, {}, false, external_protocol_failure(operation_id, .Conflict, .Protocol)
		}
	}
	provider, found, failure := select_protocol_provider(operation_id, request.provider_identity,
		request.envelope.provider_generation, dispatch_action_capability(request.action), providers)
	if failure.code != .None do return {}, {}, false, failure
	if !found do return {}, {}, false, external_protocol_failure(operation_id, .Missing, .Protocol)
	if provider.authentication_generation == 0 ||
	   request.authentication_generation != provider.authentication_generation {
		return {}, {}, false, external_protocol_failure(operation_id, .Unauthorized, .Generation)
	}
	plan := Protocol_Dispatch_Plan {operation_id = operation_id, action = request.action,
		provider_identity = provider.identity, provider_generation = provider.generation,
		schema_version = request.schema_version, caller_identity = request.caller_identity,
		caller_instance = request.caller_instance, caller_generation = request.caller_generation,
		authentication_generation = request.authentication_generation,
		nonce_digest = request.nonce_digest, payload_digest = request.payload_digest,
		target_resource_id = request.target_resource_id, target_revision = request.target_revision,
		value_count = u16(len(request.values)), complete = true}
	for value in request.values do if value.sensitive do plan.sensitive_value_count += 1
	switch request.action {
	case .Store_Link:
		plan.link_state_change = true
	case .Start_Capture:
		plan.document_change = true
	case .Open_Source:
		plan.navigation = true
	case .Invalid:
	}
	replay := Protocol_Replay_Record {caller_identity = request.caller_identity,
		caller_generation = request.caller_generation, operation_id = operation_id,
		nonce_digest = request.nonce_digest, expires_at = request.expires_at, state = .Reserved}
	return plan, replay, true, {}
}

/* protocol_replay_complete consumes one reserved nonce for every terminal outcome. */
protocol_replay_complete :: proc(record: Protocol_Replay_Record, result: Protocol_Result_State) -> (Protocol_Replay_Record, bool) {
	if !protocol_replay_record_is_valid(record) || record.state != .Reserved || result == .Invalid do return record, false
	next := record
	next.state = .Consumed
	return next, true
}

/* protocol_dispatch_result_is_valid checks completed effects and failure isolation. */
protocol_dispatch_result_is_valid :: proc(plan: Protocol_Dispatch_Plan, result: Protocol_Dispatch_Result) -> bool {
	if !plan.complete || result.operation_id != plan.operation_id || result.provider_identity != plan.provider_identity ||
	   result.provider_generation != plan.provider_generation || result.state == .Invalid { return false }
	if result.state == .Cancelled || result.state == .Failed {
		return !result.complete && !result.link_state_changed && !result.document_changed && !result.navigation_changed
	}
	return result.complete && result.link_state_changed == plan.link_state_change &&
	       result.document_changed == plan.document_change && result.navigation_changed == plan.navigation
}

@(private)
link_request_shape_is_valid :: proc(request: Link_Provider_Request, limits: Limits) -> bool {
	if request.result_limit == 0 || request.result_limit > limits.links || request.expected_bytes > limits.output_bytes do return false
	switch request.action {
	case .Follow:
		return output_text_is_valid(request.locator, MAX_PROTOCOL_PROVENANCE_BYTES) && len(request.query) == 0 &&
		       request.source_resource_id == 0 && request.source_revision == 0 && request.destination_resource_id == 0 &&
		       request.expected_destination_revision == 0 && request.expected_bytes > 0
	case .Store:
		return request.source_resource_id != 0 && request.source_revision != 0 && len(request.locator) == 0 &&
		       len(request.query) == 0 && request.destination_resource_id == 0 &&
		       request.expected_destination_revision == 0 && request.expected_bytes > 0
	case .Search:
		return output_text_is_valid(request.query, MAX_PROTOCOL_PROVENANCE_BYTES) && len(request.locator) == 0 &&
		       request.source_resource_id == 0 && request.source_revision == 0 && request.destination_resource_id == 0 &&
		       request.expected_destination_revision == 0 && request.expected_bytes > 0
	case .Preview:
		return output_text_is_valid(request.locator, MAX_PROTOCOL_PROVENANCE_BYTES) && len(request.query) == 0 &&
		       request.source_resource_id == 0 && request.source_revision == 0 && request.destination_resource_id == 0 &&
		       request.expected_destination_revision == 0 && request.expected_bytes > 0
	case .Media_Intake:
		return output_text_is_valid(request.locator, MAX_PROTOCOL_PROVENANCE_BYTES) && len(request.query) == 0 &&
		       request.source_resource_id == 0 && request.source_revision == 0 && request.destination_resource_id != 0 &&
		       request.expected_destination_revision != 0 && request.expected_bytes > 0
	case .Invalid:
	}
	return false
}

@(private)
external_request_shape_is_valid :: proc(request: External_Protocol_Request, limits: Limits) -> bool {
	if len(request.values) > MAX_PROTOCOL_VALUES do return false
	value_bytes: u64
	seen: Protocol_Value_Kinds
	for value in request.values {
		if value.kind == .Invalid || !output_text_is_valid(value.value, MAX_SETTING_VALUE_BYTES) ||
		   value.kind in seen { return false }
		seen += {value.kind}
		value_bytes += u64(len(value.value))
	}
	if value_bytes > request.envelope.payload_bytes || value_bytes > limits.protocol_payload_bytes do return false
	switch request.action {
	case .Store_Link:
		return output_text_is_valid(request.locator, MAX_PROTOCOL_PROVENANCE_BYTES) &&
		       protocol_values_are_allowed(request.values, {.Title, .Annotation}) &&
		       request.target_resource_id == 0 && request.target_revision == 0 &&
		       len(request.template_identity) == 0 && request.template_generation == Configuration_Generation(0) &&
		       request.location_kind == .Invalid && len(request.location_identity) == 0
	case .Start_Capture:
		return output_text_is_valid(request.template_identity, MAX_IDENTITY_BYTES) &&
		       request.template_generation != Configuration_Generation(0) && len(request.locator) == 0 &&
		       ((request.target_resource_id == 0 && request.target_revision == 0) ||
		        (request.target_resource_id != 0 && request.target_revision != 0)) &&
		       request.location_kind == .Invalid && len(request.location_identity) == 0
	case .Open_Source:
		return request.target_resource_id != 0 && request.target_revision != 0 && len(request.locator) == 0 &&
		       len(request.template_identity) == 0 && request.template_generation == Configuration_Generation(0) &&
		       request.location_kind != .Invalid &&
		       output_text_is_valid(request.location_identity, MAX_PROTOCOL_PROVENANCE_BYTES) && len(request.values) == 0
	case .Invalid:
	}
	return false
}

@(private)
protocol_values_are_allowed :: proc(values: []Protocol_Initial_Value, allowed: Protocol_Value_Kinds) -> bool {
	for value in values do if value.kind not_in allowed do return false
	return true
}

@(private)
protocol_replay_record_is_valid :: proc(record: Protocol_Replay_Record) -> bool {
	return output_text_is_valid(record.caller_identity, MAX_PROTOCOL_PROVENANCE_BYTES) &&
	       record.caller_generation != 0 && record.operation_id != Operation_ID(0) &&
	       external_protocol_digest_present(record.nonce_digest) && record.expires_at != 0 && record.state != .Invalid
}

@(private)
select_protocol_provider :: proc(
	operation_id: Operation_ID,
	identity: string,
	generation: Provider_Generation,
	capability: Protocol_Provider_Capability,
	providers: []Protocol_Provider_Descriptor,
) -> (Protocol_Provider_Descriptor, bool, Failure) {
	matching_identity := false
	selected: Protocol_Provider_Descriptor
	found := false
	for provider, index in providers {
		if !protocol_provider_is_valid(provider) do return {}, false, external_protocol_failure(operation_id, .Malformed, .Protocol)
		for prior in providers[:index] do if prior.identity == provider.identity && prior.generation == provider.generation {
			return {}, false, external_protocol_failure(operation_id, .Conflict, .Protocol)
		}
		if provider.identity != identity do continue
		matching_identity = true
		if provider.generation != generation do continue
		selected = provider
		found = true
	}
	if !found && matching_identity do return {}, false, external_protocol_failure(operation_id, .Stale, .Generation)
	if !found do return {}, false, {}
	if selected.state != .Available do return {}, false, external_protocol_failure(operation_id, .Unavailable, .Protocol)
	if !selected.admitted do return {}, false, external_protocol_failure(operation_id, .Unauthorized, .Protocol)
	if capability == .Invalid || capability not_in selected.capabilities {
		return {}, false, external_protocol_failure(operation_id, .Unsupported, .Protocol)
	}
	return selected, true, {}
}

@(private)
protocol_provider_is_valid :: proc(provider: Protocol_Provider_Descriptor) -> bool {
	return output_text_is_valid(provider.identity, MAX_IDENTITY_BYTES) &&
	       provider.generation != Provider_Generation(0) && provider.state != .Invalid && provider.capabilities != {} &&
	       (!provider.authentication_required || provider.authentication_generation != 0)
}

@(private)
link_action_capability :: proc(action: Link_Provider_Action) -> Protocol_Provider_Capability {
	switch action {
	case .Follow: return .Follow_Link
	case .Store: return .Store_Link
	case .Search: return .Search_Links
	case .Preview: return .Preview_Link
	case .Media_Intake: return .Intake_Media
	case .Invalid:
	}
	return .Invalid
}

@(private)
dispatch_action_capability :: proc(action: Protocol_Dispatch_Action) -> Protocol_Provider_Capability {
	switch action {
	case .Store_Link: return .Store_Link
	case .Start_Capture: return .Start_Capture
	case .Open_Source: return .Open_Source
	case .Invalid:
	}
	return .Invalid
}

@(private)
external_protocol_digest_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
external_protocol_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Protocol, code = code, field = field}
}
