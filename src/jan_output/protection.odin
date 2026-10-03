// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

/* Protection_Action identifies explicit encryption and decryption. */
Protection_Action :: enum u8 {
	Invalid,
	Encrypt,
	Decrypt,
}

/* Protected_Subtree_State identifies source-visible and transient protection states. */
Protected_Subtree_State :: enum u8 {
	Invalid,
	Plaintext,
	Encrypted_Opaque,
	Decrypted_Transient,
}

/* Protection_Trigger identifies the consumer that requested protection work. */
Protection_Trigger :: enum u8 {
	Invalid,
	Explicit_Command,
	Search,
	Agenda,
	Export,
	Publication,
	Background_Index,
}

/* Plaintext_Save_Policy controls persistence of explicitly decrypted content. */
Plaintext_Save_Policy :: enum u8 {
	Invalid,
	Deny,
	Confirm,
	Allow,
}

/* Protected_Consumer identifies one semantic projection over protected content. */
Protected_Consumer :: enum u8 {
	Invalid,
	Interactive_View,
	Search,
	Agenda,
	Export,
	Publication,
	Background_Index,
}

/* Protection_Capability identifies one provider operation. */
Protection_Capability :: enum u8 {
	Invalid,
	Encrypt,
	Decrypt,
}

/* Protection_Capabilities is one closed provider capability set. */
Protection_Capabilities :: bit_set[Protection_Capability; u8]

/* Protection_Result_State identifies one exact provider outcome. */
Protection_Result_State :: enum u8 {
	Invalid,
	Completed,
	Cancelled,
	Failed,
}

/* Protection_Provider_Descriptor is one copied credential-free provider observation. */
Protection_Provider_Descriptor :: struct {
	identity:              string,
	generation:            Provider_Generation,
	capabilities:          Protection_Capabilities,
	state:                 Availability_State,
	admitted:              bool,
	credential_generation: u64,
}

/* Protected_Subtree_Descriptor records opaque or visible source without key material. */
Protected_Subtree_Descriptor :: struct {
	resource_id:       u64,
	resource_revision: u64,
	source_bytes:      u64,
	start:             u64,
	end:               u64,
	state:             Protected_Subtree_State,
	digest:            [32]u8,
	marker_preserved:  bool,
	archive_preserved: bool,
}

/* Protection_Request binds explicit work to an exact subtree and credential handle. */
Protection_Request :: struct {
	operation_id:             Operation_ID,
	action:                   Protection_Action,
	trigger:                  Protection_Trigger,
	provider_identity:        string,
	provider_generation:      Provider_Generation,
	configuration_generation: Configuration_Generation,
	credential_handle_id:     u64,
	credential_generation:    u64,
	subtree:                  Protected_Subtree_Descriptor,
	output_byte_limit:        u64,
	explicit:                 bool,
	cancelled:                bool,
}

/* Protection_Plan is one credential-handle-only provider handoff. */
Protection_Plan :: struct {
	operation_id:             Operation_ID,
	action:                   Protection_Action,
	provider_identity:        string,
	provider_generation:      Provider_Generation,
	configuration_generation: Configuration_Generation,
	credential_handle_id:     u64,
	credential_generation:    u64,
	resource_id:              u64,
	resource_revision:        u64,
	start:                    u64,
	end:                      u64,
	input_digest:             [32]u8,
	output_byte_limit:        u64,
	preserve_markers:         bool,
	preserve_archive:         bool,
	complete:                 bool,
}

/* Sensitive_Data_Audit proves secrets and plaintext did not escape owned boundaries. */
Sensitive_Data_Audit :: struct {
	credential_bytes_retained: u64,
	diagnostic_secret_bytes:   u64,
	undo_secret_bytes:         u64,
	log_secret_bytes:          u64,
	plaintext_persisted:       bool,
}

/* Protection_Result is one copied redacted provider result descriptor. */
Protection_Result :: struct {
	operation_id:        Operation_ID,
	provider_identity:   string,
	provider_generation: Provider_Generation,
	resource_id:         u64,
	input_revision:      u64,
	output_revision:     u64,
	state:               Protection_Result_State,
	output_state:        Protected_Subtree_State,
	output_digest:       [32]u8,
	output_bytes:        u64,
	marker_preserved:    bool,
	archive_preserved:   bool,
	plaintext_exposed:   bool,
	complete:            bool,
}

/* Plaintext_Save_Request binds persistence to an exact transient subtree and policy. */
Plaintext_Save_Request :: struct {
	operation_id:     Operation_ID,
	subtree:          Protected_Subtree_Descriptor,
	policy:           Plaintext_Save_Policy,
	policy_generation: Configuration_Generation,
	confirmed:        bool,
	explicit:         bool,
}

/* Protected_Consumer_View reports visibility without returning protected bytes. */
Protected_Consumer_View :: struct {
	consumer:         Protected_Consumer,
	semantic_visible: bool,
	opaque_preserved: bool,
	source_bytes:     u64,
}

/* prepare_protection_plan validates explicit exact-generation encryption or decryption. */
prepare_protection_plan :: proc(
	request: Protection_Request,
	providers: []Protection_Provider_Descriptor,
	limits := DEFAULT_LIMITS,
) -> (Protection_Plan, bool, Failure) {
	if !limits_are_valid(limits) || request.operation_id == Operation_ID(0) || request.action == .Invalid ||
	   request.trigger != .Explicit_Command || !request.explicit ||
	   !output_text_is_valid(request.provider_identity, MAX_IDENTITY_BYTES) ||
	   request.provider_generation == Provider_Generation(0) ||
	   request.configuration_generation == Configuration_Generation(0) || request.credential_handle_id == 0 ||
	   request.credential_generation == 0 || !protected_subtree_descriptor_is_valid(request.subtree) {
		return {}, false, protection_failure(request.operation_id, .Invalid_Request, .Protection)
	}
	if request.cancelled do return {}, false, protection_failure(request.operation_id, .Cancelled, .Protection)
	if request.output_byte_limit == 0 || request.output_byte_limit > limits.output_bytes {
		return {}, false, protection_failure(request.operation_id, .Limited, .Limit)
	}
	if (request.action == .Encrypt && request.subtree.state != .Plaintext) ||
	   (request.action == .Decrypt && request.subtree.state != .Encrypted_Opaque) {
		return {}, false, protection_failure(request.operation_id, .Conflict, .Resource)
	}
	provider, found, failure := select_protection_provider(request, providers)
	if failure.code != .None do return {}, false, failure
	if !found do return {}, false, protection_failure(request.operation_id, .Missing, .Protection)
	return {operation_id = request.operation_id, action = request.action,
		provider_identity = provider.identity, provider_generation = provider.generation,
		configuration_generation = request.configuration_generation,
		credential_handle_id = request.credential_handle_id,
		credential_generation = request.credential_generation,
		resource_id = request.subtree.resource_id, resource_revision = request.subtree.resource_revision,
		start = request.subtree.start, end = request.subtree.end,
		input_digest = request.subtree.digest, output_byte_limit = request.output_byte_limit,
		preserve_markers = true, preserve_archive = true, complete = true}, true, {}
}

/* protection_result_is_valid enforces marker preservation and secret isolation. */
protection_result_is_valid :: proc(
	plan: Protection_Plan,
	result: Protection_Result,
	audit: Sensitive_Data_Audit,
) -> bool {
	if !plan.complete || result.operation_id != plan.operation_id ||
	   result.provider_identity != plan.provider_identity || result.provider_generation != plan.provider_generation ||
	   result.resource_id != plan.resource_id || result.input_revision != plan.resource_revision ||
	   result.state == .Invalid || !sensitive_data_audit_is_clean(audit) { return false }
	if result.state == .Cancelled || result.state == .Failed {
		return !result.complete && result.output_state == .Invalid && result.output_bytes == 0 &&
		       result.output_revision == 0 && !protection_digest_present(result.output_digest) && !result.plaintext_exposed
	}
	if !result.complete || !result.marker_preserved || !result.archive_preserved ||
	   result.output_bytes == 0 || result.output_bytes > plan.output_byte_limit ||
	   !protection_digest_present(result.output_digest) || result.output_revision <= result.input_revision { return false }
	if plan.action == .Encrypt {
		return result.output_state == .Encrypted_Opaque && !result.plaintext_exposed
	}
	return plan.action == .Decrypt && result.output_state == .Decrypted_Transient && result.plaintext_exposed
}

/* plaintext_save_is_allowed enforces explicit deny, confirm, or allow policy. */
plaintext_save_is_allowed :: proc(request: Plaintext_Save_Request) -> bool {
	if request.operation_id == Operation_ID(0) || !request.explicit || request.policy == .Invalid ||
	   request.policy_generation == Configuration_Generation(0) ||
	   !protected_subtree_descriptor_is_valid(request.subtree) ||
	   request.subtree.state != .Decrypted_Transient { return false }
	switch request.policy {
	case .Deny: return false
	case .Confirm: return request.confirmed
	case .Allow: return true
	case .Invalid:
	}
	return false
}

/* protected_consumer_view keeps opaque and transient content hidden from background consumers. */
protected_consumer_view :: proc(subtree: Protected_Subtree_Descriptor, consumer: Protected_Consumer) -> (Protected_Consumer_View, bool) {
	if !protected_subtree_descriptor_is_valid(subtree) || consumer == .Invalid do return {}, false
	view := Protected_Consumer_View {consumer = consumer, source_bytes = subtree.end - subtree.start}
	if subtree.state == .Plaintext {
		view.semantic_visible = true
		return view, true
	}
	view.opaque_preserved = subtree.state == .Encrypted_Opaque
	view.semantic_visible = subtree.state == .Decrypted_Transient && consumer == .Interactive_View
	return view, true
}

/* protected_subtree_descriptor_is_valid checks exact source range and preservation metadata. */
protected_subtree_descriptor_is_valid :: proc(subtree: Protected_Subtree_Descriptor) -> bool {
	return subtree.resource_id != 0 && subtree.resource_revision != 0 && subtree.source_bytes > 0 &&
	       subtree.start < subtree.end && subtree.end <= subtree.source_bytes && subtree.state != .Invalid &&
	       protection_digest_present(subtree.digest) && subtree.marker_preserved && subtree.archive_preserved
}

/* sensitive_data_audit_is_clean checks that keys and accidental plaintext were not retained. */
sensitive_data_audit_is_clean :: proc(audit: Sensitive_Data_Audit) -> bool {
	return audit.credential_bytes_retained == 0 && audit.diagnostic_secret_bytes == 0 &&
	       audit.undo_secret_bytes == 0 && audit.log_secret_bytes == 0 && !audit.plaintext_persisted
}

@(private)
select_protection_provider :: proc(
	request: Protection_Request,
	providers: []Protection_Provider_Descriptor,
) -> (Protection_Provider_Descriptor, bool, Failure) {
	matching_identity := false
	found := false
	selected: Protection_Provider_Descriptor
	for provider, index in providers {
		if !protection_provider_is_valid(provider) do return {}, false, protection_failure(request.operation_id, .Malformed, .Protection)
		for prior in providers[:index] do if prior.identity == provider.identity && prior.generation == provider.generation {
			return {}, false, protection_failure(request.operation_id, .Conflict, .Protection)
		}
		if provider.identity != request.provider_identity do continue
		matching_identity = true
		if provider.generation != request.provider_generation do continue
		selected = provider
		found = true
	}
	if !found && matching_identity do return {}, false, protection_failure(request.operation_id, .Stale, .Generation)
	if !found do return {}, false, {}
	if selected.state != .Available do return {}, false, protection_failure(request.operation_id, .Unavailable, .Protection)
	if !selected.admitted || selected.credential_generation != request.credential_generation {
		return {}, false, protection_failure(request.operation_id, .Unauthorized, .Generation)
	}
	required := Protection_Capability.Encrypt
	if request.action == .Decrypt do required = .Decrypt
	if required not_in selected.capabilities do return {}, false, protection_failure(request.operation_id, .Unsupported, .Protection)
	return selected, true, {}
}

@(private)
protection_provider_is_valid :: proc(provider: Protection_Provider_Descriptor) -> bool {
	return output_text_is_valid(provider.identity, MAX_IDENTITY_BYTES) &&
	       provider.generation != Provider_Generation(0) && provider.capabilities != {} &&
	       provider.state != .Invalid && provider.credential_generation != 0
}

@(private)
protection_digest_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
protection_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Protect, code = code, field = field}
}
