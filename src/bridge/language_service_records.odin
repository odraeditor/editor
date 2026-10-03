// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../language_service"

/* LANGUAGE_SERVICE_CAPABILITY_SCHEMA_VERSION identifies the first copied service ABI. */
LANGUAGE_SERVICE_CAPABILITY_SCHEMA_VERSION :: u64(2)
/* MAX_LANGUAGE_SERVICE_OPTIONS bounds copied definition option pairs. */
MAX_LANGUAGE_SERVICE_OPTIONS :: u64(64)
/* MAX_LANGUAGE_SERVICE_LANGUAGES bounds copied language identities per definition. */
MAX_LANGUAGE_SERVICE_LANGUAGES :: u64(64)
/* MAX_LANGUAGE_SERVICE_INSPECTION_FAILURES retains only the latest copied failure. */
MAX_LANGUAGE_SERVICE_INSPECTION_FAILURES :: u64(1)
/* LANGUAGE_SERVICE_DEFINITION_FIXED_TEXT_RECORDS stores name, executable, and root. */
LANGUAGE_SERVICE_DEFINITION_FIXED_TEXT_RECORDS :: u64(3)
/* MAX_LANGUAGE_SERVICE_PROPOSAL_TEXT_BYTES bounds all copied proposal text. */
MAX_LANGUAGE_SERVICE_PROPOSAL_TEXT_BYTES :: u64(
	language_service.DEFAULT_LIMITS.executable_bytes +
		language_service.DEFAULT_LIMITS.argument_bytes +
		language_service.DEFAULT_LIMITS.environment_bytes +
		language_service.DEFAULT_LIMITS.root_bytes +
		language_service.DEFAULT_LIMITS.options_bytes +
		MAX_LANGUAGE_SERVICE_LANGUAGES * language_service.MAX_NAME_BYTES,
)
/* MAX_LANGUAGE_SERVICE_PROPOSAL_BYTES bounds one complete copied proposal. */
MAX_LANGUAGE_SERVICE_PROPOSAL_BYTES :: MAX_LANGUAGE_SERVICE_PROPOSAL_TEXT_BYTES + 64 * 1_024

/* LANGUAGE_SERVICE_SCOPE_RECORD_BYTES is one exact registry and Project scope. */
LANGUAGE_SERVICE_SCOPE_RECORD_BYTES :: u64(136)
/* LANGUAGE_SERVICE_LIMITS_RECORD_BYTES is the complete copied native policy. */
LANGUAGE_SERVICE_LIMITS_RECORD_BYTES :: u64(280)
/* LANGUAGE_SERVICE_POLICY_RECORD_BYTES is the complete deadline and restart policy. */
LANGUAGE_SERVICE_POLICY_RECORD_BYTES :: u64(80)
/* LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES precedes one copied definition proposal. */
LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES :: u64(624)
/* LANGUAGE_SERVICE_SELECTION_RECORD_BYTES is one optimistic selection request. */
LANGUAGE_SERVICE_SELECTION_RECORD_BYTES :: u64(208)
/* LANGUAGE_SERVICE_LIFECYCLE_RECORD_BYTES is one checked session lifecycle request. */
LANGUAGE_SERVICE_LIFECYCLE_RECORD_BYTES :: u64(216)
/* LANGUAGE_SERVICE_TRUST_ROOT_RECORD_BYTES is one exact Project membership root. */
LANGUAGE_SERVICE_TRUST_ROOT_RECORD_BYTES :: u64(64)
/* LANGUAGE_SERVICE_TEXT_RECORD_BYTES is one offset and byte-count pair. */
LANGUAGE_SERVICE_TEXT_RECORD_BYTES :: u64(16)
/* LANGUAGE_SERVICE_OPTION_RECORD_BYTES is one copied key and value pair. */
LANGUAGE_SERVICE_OPTION_RECORD_BYTES :: u64(32)
/* LANGUAGE_SERVICE_PROVIDER_RECORD_BYTES is one copied provider descriptor. */
LANGUAGE_SERVICE_PROVIDER_RECORD_BYTES :: u64(64)
/* LANGUAGE_SERVICE_DEFINITION_RECORD_BYTES is one copied definition descriptor. */
LANGUAGE_SERVICE_DEFINITION_RECORD_BYTES :: u64(128)
/* LANGUAGE_SERVICE_SESSION_RECORD_BYTES is one copied process-session descriptor. */
LANGUAGE_SERVICE_SESSION_RECORD_BYTES :: u64(128)
/* LANGUAGE_SERVICE_USAGE_RECORD_BYTES is one complete copied accounting record. */
LANGUAGE_SERVICE_USAGE_RECORD_BYTES :: u64(128)
/* LANGUAGE_SERVICE_FAILURE_RECORD_BYTES is one copied contained failure. */
LANGUAGE_SERVICE_FAILURE_RECORD_BYTES :: u64(120)
/* LANGUAGE_SERVICE_OUTCOME_RECORD_BYTES is one copied lifecycle result. */
LANGUAGE_SERVICE_OUTCOME_RECORD_BYTES :: u64(256)
/* LANGUAGE_SERVICE_INSPECTION_HEADER_BYTES precedes one complete copied inspection. */
LANGUAGE_SERVICE_INSPECTION_HEADER_BYTES :: u64(696)
/* LANGUAGE_SERVICE_DIAGNOSTIC_COMMAND_RECORD_BYTES is one exact scoped command request. */
LANGUAGE_SERVICE_DIAGNOSTIC_COMMAND_RECORD_BYTES :: u64(160)
/* LANGUAGE_SERVICE_DIAGNOSTIC_OUTCOME_RECORD_BYTES confirms one copied admitted request. */
LANGUAGE_SERVICE_DIAGNOSTIC_OUTCOME_RECORD_BYTES :: u64(176)

/* Language_Service_Capability_Operation identifies one admitted synchronous request. */
Language_Service_Capability_Operation :: enum i32 {
	Scope = 1,
	Inspect = 2,
	Propose = 3,
	Confirm = 4,
	Select = 5,
	Disable = 6,
	Replace = 7,
	Restore = 8,
	Start = 9,
	Stop = 10,
	Restart = 11,
	Invoke_Diagnostic_Command = 12,
}

/* Language_Service_Capability_Access names checked authority without native ownership. */
Language_Service_Capability_Access :: enum u64 {
	Inspect = 1,
	Propose = 2,
	Confirm = 3,
	Select = 4,
	Disable = 5,
	Replace = 6,
	Restore = 7,
	Lifecycle = 8,
	Diagnostic_Commands = 9,
}

/* Language_Service_Diagnostic_Command is the closed programmable command vocabulary. */
Language_Service_Diagnostic_Command :: enum u64 {
	Invalid,
	List,
	Next,
	Previous,
}

/* Language_Service_Root_Policy selects one admitted Project-derived root. */
Language_Service_Root_Policy :: enum u64 {
	Project_Membership = 1,
	Workspace_Folder = 2,
}

/* Language_Service_Lifecycle_Action identifies one checked session transition. */
Language_Service_Lifecycle_Action :: enum u64 {
	Start = 1,
	Stop = 2,
	Restart = 3,
}

/* Language_Service_Scope_Record binds capability use to exact native generations. */
Language_Service_Scope_Record :: struct {
	schema_version:               u64,
	access:                       u64,
	registry_id:                  u64,
	registry_generation:          u64,
	selection_generation:         u64,
	active_provider_id:           u64,
	active_provider_generation:   u64,
	active_definition_id:         u64,
	active_definition_generation: u64,
	active_session_id:            u64,
	active_session_generation:    u64,
	project_id:                   u64,
	project_generation:           u64,
	membership_id:                u64,
	membership_generation:        u64,
	trust_generation:             u64,
	capability_generation:        u64,
}

/* Language_Service_Limits_Record publishes the complete selected native policy. */
Language_Service_Limits_Record :: struct {
	service_definitions:      u64,
	providers:                u64,
	sessions:                 u64,
	documents_per_session:    u64,
	documents_total:          u64,
	executable_bytes:         u64,
	arguments:                u64,
	argument_bytes:           u64,
	environment_entries:      u64,
	environment_bytes:        u64,
	root_bytes:               u64,
	uri_bytes:                u64,
	options_bytes:            u64,
	frame_header_bytes:       u64,
	json_depth:               u64,
	message_bytes:            u64,
	buffered_stream_bytes:    u64,
	outstanding_requests:     u64,
	notifications:            u64,
	queue_depth:              u64,
	queue_bytes:              u64,
	synchronization_changes:  u64,
	synchronization_bytes:    u64,
	diagnostics_per_document: u64,
	diagnostics_per_project:  u64,
	diagnostic_fields:        u64,
	diagnostic_message_bytes: u64,
	related_locations:        u64,
	diagnostic_bytes:         u64,
	candidates:               u64,
	candidate_text_bytes:     u64,
	standard_error_bytes:     u64,
	work_bytes_per_turn:      u64,
	retained_bytes:           u64,
	temporary_bytes:          u64,
}

/* Language_Service_Policy_Record publishes deadlines and automatic restart policy. */
Language_Service_Policy_Record :: struct {
	discovery_ns:          u64,
	initialization_ns:     u64,
	request_ns:            u64,
	cancellation_ns:       u64,
	idle_step_ns:          u64,
	restart_stability_ns:  u64,
	shutdown_ns:           u64,
	forced_termination_ns: u64,
	automatic_restarts:    u64,
	stability_ns:          u64,
}

/* Language_Service_Definition_Header_Record carries one complete copied proposal. */
Language_Service_Definition_Header_Record :: struct {
	expected_scope:                 Language_Service_Scope_Record,
	operation:                      u64,
	expected_provider_id:           u64,
	expected_provider_generation:   u64,
	expected_definition_id:         u64,
	expected_definition_generation: u64,
	provider_kind:                  u64,
	root_policy:                    u64,
	preferred_encoding:             u64,
	preferred_synchronization:      u64,
	capabilities:                   u64,
	argument_count:                 u64,
	environment_count:              u64,
	option_count:                   u64,
	language_count:                 u64,
	text_bytes:                     u64,
	option_bytes:                   u64,
	limits:                         Language_Service_Limits_Record,
	policy:                         Language_Service_Policy_Record,
}

/* Language_Service_Selection_Record carries one generation-checked selection request. */
Language_Service_Selection_Record :: struct {
	expected_scope:                 Language_Service_Scope_Record,
	operation:                      u64,
	expected_provider_id:           u64,
	expected_provider_generation:   u64,
	expected_definition_id:         u64,
	expected_definition_generation: u64,
	provider_id:                    u64,
	provider_generation:            u64,
	definition_id:                  u64,
	definition_generation:          u64,
}

/* Language_Service_Lifecycle_Record carries one checked Project session action. */
Language_Service_Lifecycle_Record :: struct {
	expected_scope:       Language_Service_Scope_Record,
	action:               u64,
	session_id:           u64,
	session_generation:   u64,
	project_id:           u64,
	project_generation:   u64,
	membership_id:        u64,
	membership_generation: u64,
	definition_id:        u64,
	definition_generation: u64,
	deadline_ns:          u64,
}

/* Language_Service_Trust_Root_Record copies one exact trusted membership root. */
Language_Service_Trust_Root_Record :: struct {
	project_id:            u64,
	project_generation:    u64,
	membership_id:         u64,
	membership_generation: u64,
	trust_generation:      u64,
	trusted:               u64,
	root_offset:           u64,
	root_bytes:            u64,
}

/* Language_Service_Text_Record identifies one copied text field. */
Language_Service_Text_Record :: struct {
	offset: u64,
	bytes:  u64,
}

/* Language_Service_Option_Record identifies one copied option key and JSON value. */
Language_Service_Option_Record :: struct {
	key_offset:   u64,
	key_bytes:    u64,
	value_offset: u64,
	value_bytes:  u64,
}

/* Language_Service_Provider_Record copies one provider without native ownership. */
Language_Service_Provider_Record :: struct {
	provider_id:         u64,
	provider_generation: u64,
	kind:                u64,
	state:               u64,
	name_offset:         u64,
	name_bytes:          u64,
	first_definition:    u64,
	definition_count:    u64,
}

/* Language_Service_Definition_Record copies one immutable definition generation. */
Language_Service_Definition_Record :: struct {
	provider_id:           u64,
	provider_generation:   u64,
	definition_id:         u64,
	definition_generation: u64,
	state:                 u64,
	root_policy:           u64,
	preferred_encoding:    u64,
	preferred_sync:        u64,
	capabilities:          u64,
	name_offset:           u64,
	name_bytes:            u64,
	executable_offset:     u64,
	executable_bytes:      u64,
	first_argument:        u64,
	argument_count:        u64,
	retained_bytes:        u64,
}

/* Language_Service_Session_Record copies one Project-scoped process session. */
Language_Service_Session_Record :: struct {
	session_id:             u64,
	session_generation:     u64,
	provider_id:            u64,
	provider_generation:    u64,
	definition_id:          u64,
	definition_generation:  u64,
	project_id:             u64,
	project_generation:     u64,
	membership_id:          u64,
	membership_generation:  u64,
	health:                 u64,
	capabilities:           u64,
	position_encoding:      u64,
	synchronization_mode:   u64,
	automatic_restarts:     u64,
	bound_documents:        u64,
}

/* Language_Service_Usage_Record publishes exact native and hosted accounting. */
Language_Service_Usage_Record :: struct {
	providers:            u64,
	definitions:          u64,
	sessions:             u64,
	documents:            u64,
	outstanding_requests: u64,
	notifications:        u64,
	queue_depth:          u64,
	queue_bytes:          u64,
	standard_error_bytes: u64,
	retained_bytes:       u64,
	temporary_bytes:      u64,
	work_bytes:           u64,
	inspection_bytes:     u64,
	operations_in_turn:   u64,
	hosted_turns:         u64,
	failures:             u64,
}

/* Language_Service_Failure_Record copies one stable contained failure. */
Language_Service_Failure_Record :: struct {
	operation:             u64,
	failure_code:          u64,
	provider_id:           u64,
	provider_generation:   u64,
	definition_id:         u64,
	definition_generation: u64,
	session_id:            u64,
	session_generation:    u64,
	resource:              u64,
	expected_generation:   u64,
	actual_generation:     u64,
	limit:                 u64,
	actual:                u64,
	message_offset:        u64,
	message_bytes:         u64,
}

/* Language_Service_Outcome_Record contains no retained Racket or native ownership. */
Language_Service_Outcome_Record :: struct {
	scope:                          Language_Service_Scope_Record,
	operation:                      u64,
	completion:                     u64,
	changed:                        u64,
	previous_provider_id:           u64,
	previous_provider_generation:   u64,
	previous_definition_id:         u64,
	previous_definition_generation: u64,
	provider_id:                    u64,
	provider_generation:            u64,
	definition_id:                  u64,
	definition_generation:          u64,
	session_id:                     u64,
	session_generation:             u64,
	health:                         u64,
	retained_bytes:                 u64,
}

/* Language_Service_Inspection_Header_Record describes one copied owner snapshot. */
Language_Service_Inspection_Header_Record :: struct {
	scope:            Language_Service_Scope_Record,
	usage:            Language_Service_Usage_Record,
	limits:           Language_Service_Limits_Record,
	policy:           Language_Service_Policy_Record,
	provider_count:   u64,
	definition_count: u64,
	session_count:    u64,
	trust_root_count: u64,
	argument_count:   u64,
	option_count:     u64,
	failure_count:    u64,
	text_bytes:       u64,
	total_bytes:      u64,
}

/* language_service_definition_record_bytes validates one complete copied proposal. */
language_service_definition_record_bytes :: proc(
	arguments, environment, options, languages, text_bytes, option_bytes: u64,
) -> (bytes: u64, ok: bool) {
	limits := language_service.DEFAULT_LIMITS
	if arguments > u64(limits.arguments) || environment > u64(limits.environment_entries) ||
	   options > MAX_LANGUAGE_SERVICE_OPTIONS || languages > MAX_LANGUAGE_SERVICE_LANGUAGES ||
	   text_bytes > MAX_LANGUAGE_SERVICE_PROPOSAL_TEXT_BYTES || option_bytes > limits.options_bytes {
		return 0, false
	}
	records := LANGUAGE_SERVICE_DEFINITION_FIXED_TEXT_RECORDS + arguments + environment + languages
	bytes = LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES +
	        records * LANGUAGE_SERVICE_TEXT_RECORD_BYTES +
	        options * LANGUAGE_SERVICE_OPTION_RECORD_BYTES + text_bytes + option_bytes
	return bytes, bytes <= MAX_LANGUAGE_SERVICE_PROPOSAL_BYTES
}

/* language_service_inspection_record_bytes validates one complete copied inspection. */
language_service_inspection_record_bytes :: proc(
	providers, definitions, sessions, trust_roots, arguments, options, failures, text_bytes: u64,
) -> (bytes: u64, ok: bool) {
	limits := language_service.DEFAULT_LIMITS
	if providers > u64(limits.providers) || definitions > u64(limits.service_definitions) ||
	   sessions > u64(limits.sessions) || trust_roots > u64(limits.sessions) ||
	   arguments > definitions * u64(limits.arguments) ||
	   options > definitions * MAX_LANGUAGE_SERVICE_OPTIONS ||
	   failures > MAX_LANGUAGE_SERVICE_INSPECTION_FAILURES || text_bytes > limits.retained_bytes {
		return 0, false
	}
	bytes = LANGUAGE_SERVICE_INSPECTION_HEADER_BYTES +
	        providers * LANGUAGE_SERVICE_PROVIDER_RECORD_BYTES +
	        definitions * LANGUAGE_SERVICE_DEFINITION_RECORD_BYTES +
	        sessions * LANGUAGE_SERVICE_SESSION_RECORD_BYTES +
	        trust_roots * LANGUAGE_SERVICE_TRUST_ROOT_RECORD_BYTES +
	        arguments * LANGUAGE_SERVICE_TEXT_RECORD_BYTES +
	        options * LANGUAGE_SERVICE_OPTION_RECORD_BYTES +
	        failures * LANGUAGE_SERVICE_FAILURE_RECORD_BYTES + text_bytes
	return bytes, bytes <= limits.retained_bytes
}

/* language_service_record_layout_is_valid verifies every C and Racket ABI width. */
language_service_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Language_Service_Scope_Record)) == LANGUAGE_SERVICE_SCOPE_RECORD_BYTES &&
	       u64(size_of(Language_Service_Limits_Record)) == LANGUAGE_SERVICE_LIMITS_RECORD_BYTES &&
	       u64(size_of(Language_Service_Policy_Record)) == LANGUAGE_SERVICE_POLICY_RECORD_BYTES &&
	       u64(size_of(Language_Service_Definition_Header_Record)) == LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES &&
	       u64(size_of(Language_Service_Selection_Record)) == LANGUAGE_SERVICE_SELECTION_RECORD_BYTES &&
	       u64(size_of(Language_Service_Lifecycle_Record)) == LANGUAGE_SERVICE_LIFECYCLE_RECORD_BYTES &&
	       u64(size_of(Language_Service_Trust_Root_Record)) == LANGUAGE_SERVICE_TRUST_ROOT_RECORD_BYTES &&
	       u64(size_of(Language_Service_Text_Record)) == LANGUAGE_SERVICE_TEXT_RECORD_BYTES &&
	       u64(size_of(Language_Service_Option_Record)) == LANGUAGE_SERVICE_OPTION_RECORD_BYTES &&
	       u64(size_of(Language_Service_Provider_Record)) == LANGUAGE_SERVICE_PROVIDER_RECORD_BYTES &&
	       u64(size_of(Language_Service_Definition_Record)) == LANGUAGE_SERVICE_DEFINITION_RECORD_BYTES &&
	       u64(size_of(Language_Service_Session_Record)) == LANGUAGE_SERVICE_SESSION_RECORD_BYTES &&
	       u64(size_of(Language_Service_Usage_Record)) == LANGUAGE_SERVICE_USAGE_RECORD_BYTES &&
	       u64(size_of(Language_Service_Failure_Record)) == LANGUAGE_SERVICE_FAILURE_RECORD_BYTES &&
	       u64(size_of(Language_Service_Outcome_Record)) == LANGUAGE_SERVICE_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Language_Service_Inspection_Header_Record)) == LANGUAGE_SERVICE_INSPECTION_HEADER_BYTES
}
