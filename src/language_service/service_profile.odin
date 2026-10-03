// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:fmt"

/* IMPLEMENTED_SERVICE_FEATURES records complete generic Odra adapters. */
IMPLEMENTED_SERVICE_FEATURES :: Service_Features {
	.Diagnostics,
	.Completion,
	.Navigation,
	.Hover,
	.References,
	.Symbols,
	.Signature_Help,
	.Semantic_Tokens,
}

/* Effective_Service_Profile borrows immutable definition data and copies negotiation state. */
Effective_Service_Profile :: struct {
	client_capabilities:     Capabilities,
	initialization_options: string,
	client_settings:        string,
	feature_policy:         Service_Features,
	environment:            []string,
	limits:                 Service_Limits,
	deadlines:              Deadline_Policy,
	restart:                Restart_Policy,
	server_capabilities:    Capabilities,
	active_capabilities:    Capabilities,
	active_features:        Service_Features,
	position_encoding:      Position_Encoding,
	synchronization_mode:   Synchronization_Mode,
	completion:             Completion_Capability_Values,
	semantic_tokens:       Semantic_Token_Capability_Values,
}

/* service_feature_policy_valid rejects feature policy disconnected from client support. */
service_feature_policy_valid :: proc(
	features: Service_Features,
	client: Capabilities,
) -> bool {
	if .Initialize not_in client || .Shutdown not_in client do return false
	if .Diagnostics in features && .Push_Diagnostics not_in client do return false
	if .Completion in features && .Completion not_in client do return false
	if .Navigation in features && .Definition not_in client do return false
	if .Hover in features && .Hover not_in client do return false
	if .References in features && .References not_in client do return false
	if .Symbols in features &&
	   (.Document_Symbols not_in client || .Workspace_Symbols not_in client) {
		return false
	}
	if .Signature_Help in features && .Signature_Help not_in client do return false
	if .Semantic_Tokens in features && .Semantic_Tokens not_in client do return false
	return true
}

/* effective_service_profile applies client, definition, native, and server policy once. */
effective_service_profile :: proc(
	definition: Definition_View,
	negotiated: Capability_Values,
) -> (Effective_Service_Profile, bool) {
	client := definition.definition.requested_capabilities
	if !service_feature_policy_valid(definition.feature_policy, client) do return {}, false
	if negotiated.position_encoding != .UTF_8 && negotiated.position_encoding != .UTF_16 {
		return {}, false
	}
	active_capabilities := client & negotiated.capabilities
	active_features: Service_Features
	if .Diagnostics in definition.feature_policy &&
	   .Diagnostics in IMPLEMENTED_SERVICE_FEATURES &&
	   .Push_Diagnostics in active_capabilities {
		active_features += {.Diagnostics}
	}
	completion := negotiated.completion
	if .Completion in definition.feature_policy &&
	   .Completion in IMPLEMENTED_SERVICE_FEATURES &&
	   .Completion in active_capabilities {
		active_features += {.Completion}
	} else {
		completion = {}
		active_capabilities -= {.Completion}
	}
	if .Diagnostics not_in active_features do active_capabilities -= {.Push_Diagnostics}
	activate_service_feature(&active_features, definition.feature_policy, active_capabilities, .Navigation, .Definition)
	activate_service_feature(&active_features, definition.feature_policy, active_capabilities, .Hover, .Hover)
	activate_service_feature(&active_features, definition.feature_policy, active_capabilities, .References, .References)
	if .Symbols in definition.feature_policy && .Symbols in IMPLEMENTED_SERVICE_FEATURES &&
	   (.Document_Symbols in active_capabilities || .Workspace_Symbols in active_capabilities) {
		active_features += {.Symbols}
	}
	activate_service_feature(&active_features, definition.feature_policy, active_capabilities, .Signature_Help, .Signature_Help)
	activate_service_feature(&active_features, definition.feature_policy, active_capabilities, .Semantic_Tokens, .Semantic_Tokens)
	synchronization_mode := Synchronization_Mode.None
	#partial switch negotiated.synchronization_mode {
	case .Full:
		if .Full_Synchronization in active_capabilities do synchronization_mode = .Full
	case .Incremental:
		if .Incremental_Synchronization in active_capabilities do synchronization_mode = .Incremental
	case:
	}
	return Effective_Service_Profile{
		client_capabilities = client,
		initialization_options = definition.initialization_options,
		client_settings = definition.client_settings,
		feature_policy = definition.feature_policy,
		environment = definition.environment,
		limits = definition.definition.limits,
		deadlines = definition.definition.deadlines,
		restart = definition.definition.restart,
		server_capabilities = negotiated.capabilities,
		active_capabilities = active_capabilities,
		active_features = active_features,
		position_encoding = negotiated.position_encoding,
		synchronization_mode = synchronization_mode,
		completion = completion,
		semantic_tokens = negotiated.semantic_tokens,
	}, true
}

@(private = "file")
activate_service_feature :: proc(
	active: ^Service_Features,
	policy: Service_Features,
	capabilities: Capabilities,
	feature: Service_Feature,
	capability: Capability,
) {
	if feature in policy && feature in IMPLEMENTED_SERVICE_FEATURES && capability in capabilities {
		active^ += {feature}
	}
}

/* service_configuration_notification builds the admitted post-initialization settings message. */
service_configuration_notification :: proc(
	settings: string,
	allocator := context.allocator,
) -> (string, bool) {
	effective_settings := settings
	if effective_settings == "" do effective_settings = `{}`
	body := fmt.aprintf(
		`{{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration","params":{{"settings":%s}}}}`,
		effective_settings,
		allocator = allocator,
	)
	return body, body != ""
}
