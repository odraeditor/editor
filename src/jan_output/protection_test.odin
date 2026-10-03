// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies encryption and decryption use exact providers and credential handles only. */
@(test)
protected_subtrees_plan_explicit_credential_isolated_work :: proc(t: ^testing.T) {
	providers := [1]Protection_Provider_Descriptor {protection_test_provider()}
	encrypt := protection_test_request(.Encrypt, .Plaintext)
	encrypt_plan, encrypt_ok, _ := prepare_protection_plan(encrypt, providers[:])
	testing.expect(t, encrypt_ok)
	testing.expect_value(t, encrypt_plan.credential_handle_id, u64(501))
	testing.expect(t, encrypt_plan.preserve_markers)
	testing.expect(t, encrypt_plan.preserve_archive)
	encrypted := Protection_Result {operation_id = encrypt.operation_id,
		provider_identity = encrypt.provider_identity, provider_generation = encrypt.provider_generation,
		resource_id = encrypt.subtree.resource_id, input_revision = encrypt.subtree.resource_revision,
		output_revision = encrypt.subtree.resource_revision + 1,
		state = .Completed, output_state = .Encrypted_Opaque, output_bytes = 2048,
		marker_preserved = true, archive_preserved = true, complete = true}
	encrypted.output_digest[0] = 7
	testing.expect(t, protection_result_is_valid(encrypt_plan, encrypted, {}))

	decrypt := protection_test_request(.Decrypt, .Encrypted_Opaque)
	decrypt_plan, decrypt_ok, _ := prepare_protection_plan(decrypt, providers[:])
	testing.expect(t, decrypt_ok)
	decrypted := Protection_Result {operation_id = decrypt.operation_id,
		provider_identity = decrypt.provider_identity, provider_generation = decrypt.provider_generation,
		resource_id = decrypt.subtree.resource_id, input_revision = decrypt.subtree.resource_revision,
		output_revision = decrypt.subtree.resource_revision + 1,
		state = .Completed, output_state = .Decrypted_Transient, output_bytes = 1024,
		marker_preserved = true, archive_preserved = true, plaintext_exposed = true, complete = true}
	decrypted.output_digest[0] = 9
	testing.expect(t, protection_result_is_valid(decrypt_plan, decrypted, {}))
}

/* Verifies opaque content remains preserved and invisible to semantic background consumers. */
@(test)
protected_subtrees_do_not_decrypt_for_semantic_consumers :: proc(t: ^testing.T) {
	opaque := protection_test_subtree(.Encrypted_Opaque)
	consumers := []Protected_Consumer {.Search, .Agenda, .Export, .Publication, .Background_Index}
	for consumer in consumers {
		view, ok := protected_consumer_view(opaque, consumer)
		testing.expect(t, ok)
		testing.expect(t, !view.semantic_visible)
		testing.expect(t, view.opaque_preserved)
		testing.expect_value(t, view.source_bytes, u64(512))
	}
	transient := protection_test_subtree(.Decrypted_Transient)
	interactive, interactive_ok := protected_consumer_view(transient, .Interactive_View)
	testing.expect(t, interactive_ok)
	testing.expect(t, interactive.semantic_visible)
	indexed, indexed_ok := protected_consumer_view(transient, .Background_Index)
	testing.expect(t, indexed_ok)
	testing.expect(t, !indexed.semantic_visible)
}

/* Verifies plaintext persistence requires explicit deny, confirmation, or allow policy. */
@(test)
protected_plaintext_save_policy_is_explicit :: proc(t: ^testing.T) {
	request := Plaintext_Save_Request {operation_id = 71,
		subtree = protection_test_subtree(.Decrypted_Transient), policy = .Deny,
		policy_generation = 13, explicit = true}
	testing.expect(t, !plaintext_save_is_allowed(request))
	request.policy = .Confirm
	testing.expect(t, !plaintext_save_is_allowed(request))
	request.confirmed = true
	testing.expect(t, plaintext_save_is_allowed(request))
	request.policy = .Allow
	request.confirmed = false
	testing.expect(t, plaintext_save_is_allowed(request))
	request.explicit = false
	testing.expect(t, !plaintext_save_is_allowed(request))
}

/* Verifies unavailable, stale, implicit, cancelled, and secret-retaining outcomes reject. */
@(test)
protected_subtree_failures_preserve_source_and_redact_secrets :: proc(t: ^testing.T) {
	providers := [1]Protection_Provider_Descriptor {protection_test_provider()}
	request := protection_test_request(.Decrypt, .Encrypted_Opaque)
	request.trigger = .Search
	_, implicit_ok, implicit_failure := prepare_protection_plan(request, providers[:])
	testing.expect(t, !implicit_ok)
	testing.expect_value(t, implicit_failure.code, Failure_Code.Invalid_Request)
	request.trigger = .Explicit_Command
	request.provider_generation += 1
	_, stale_ok, stale_failure := prepare_protection_plan(request, providers[:])
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale)
	request.provider_generation -= 1
	providers[0].state = .Unavailable
	_, unavailable_ok, unavailable_failure := prepare_protection_plan(request, providers[:])
	testing.expect(t, !unavailable_ok)
	testing.expect_value(t, unavailable_failure.code, Failure_Code.Unavailable)
	providers[0].state = .Available
	request.cancelled = true
	_, cancelled_ok, cancelled_failure := prepare_protection_plan(request, providers[:])
	testing.expect(t, !cancelled_ok)
	testing.expect_value(t, cancelled_failure.code, Failure_Code.Cancelled)
	request.cancelled = false
	plan, ok, _ := prepare_protection_plan(request, providers[:])
	testing.expect(t, ok)
	result := Protection_Result {operation_id = request.operation_id,
		provider_identity = request.provider_identity, provider_generation = request.provider_generation,
		resource_id = request.subtree.resource_id, input_revision = request.subtree.resource_revision,
		output_revision = request.subtree.resource_revision + 1,
		state = .Completed, output_state = .Decrypted_Transient, output_bytes = 1024,
		marker_preserved = true, archive_preserved = true, plaintext_exposed = true, complete = true}
	result.output_digest[0] = 1
	audit := Sensitive_Data_Audit {undo_secret_bytes = 1}
	testing.expect(t, !protection_result_is_valid(plan, result, audit))
}

@(private = "file")
protection_test_provider :: proc() -> Protection_Provider_Descriptor {
	return {identity = "age", generation = 17, capabilities = {.Encrypt, .Decrypt},
		state = .Available, admitted = true, credential_generation = 19}
}

@(private = "file")
protection_test_subtree :: proc(state: Protected_Subtree_State) -> Protected_Subtree_Descriptor {
	subtree := Protected_Subtree_Descriptor {resource_id = 101, resource_revision = 11,
		source_bytes = 4096, start = 256, end = 768, state = state,
		marker_preserved = true, archive_preserved = true}
	subtree.digest[0] = 3
	return subtree
}

@(private = "file")
protection_test_request :: proc(action: Protection_Action, state: Protected_Subtree_State) -> Protection_Request {
	return {operation_id = 61, action = action, trigger = .Explicit_Command,
		provider_identity = "age", provider_generation = 17, configuration_generation = 13,
		credential_handle_id = 501,
		credential_generation = 19, subtree = protection_test_subtree(state),
		output_byte_limit = 8192, explicit = true}
}
