// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../completion"
import "../editor_session"
import "../hosting"
import "../gutter"
import "../indentation"
import "../interaction"
import language_support "../language_support"
import "../recovery"
import "../status_bar"
import "../terminal_session"
import "core:encoding/endian"
import "core:fmt"
import "core:unicode/utf8"

/* PERSONAL_CONFIGURATION_STARTUP_SCHEMA_VERSION identifies copied startup configuration batches. */
PERSONAL_CONFIGURATION_STARTUP_SCHEMA_VERSION :: u64(10)

/* PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES bounds the fixed startup configuration header. */
PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES :: 464

/* MAX_LANGUAGE_SUPPORT_CONFIGURATION_BYTES bounds one copied personal contribution. */
MAX_LANGUAGE_SUPPORT_CONFIGURATION_BYTES :: language_support.MAX_CONFIGURATION_BYTES

/* INDENTATION_CONFIGURATION_SCHEMA_VERSION identifies copied indentation batches. */
INDENTATION_CONFIGURATION_SCHEMA_VERSION :: indentation.ENCODED_SCHEMA_VERSION
/* INDENTATION_CONFIGURATION_HEADER_BYTES bounds the fixed indentation header. */
INDENTATION_CONFIGURATION_HEADER_BYTES :: indentation.ENCODED_HEADER_BYTES
/* INDENTATION_CONFIGURATION_RULE_BYTES bounds one fixed scoped rule record. */
INDENTATION_CONFIGURATION_RULE_BYTES :: indentation.ENCODED_RULE_BYTES

/* TERMINAL_CONFIGURATION_SCHEMA_VERSION identifies copied terminal configuration records. */
TERMINAL_CONFIGURATION_SCHEMA_VERSION :: u64(1)
/* TERMINAL_CONFIGURATION_HEADER_BYTES bounds the fixed terminal configuration header. */
TERMINAL_CONFIGURATION_HEADER_BYTES :: 96
/* TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES bounds one fixed Workspace policy record. */
TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES :: 88
/* TERMINAL_AUTOMATION_RECORD_BYTES bounds one fixed named automation descriptor. */
TERMINAL_AUTOMATION_RECORD_BYTES :: 64
/* MAX_TERMINAL_CONFIGURATION_WORKSPACES bounds copied Workspace policy overrides. */
MAX_TERMINAL_CONFIGURATION_WORKSPACES :: 8
/* MAX_TERMINAL_CONFIGURATION_IDENTITY_BYTES bounds copied Workspace and automation names. */
MAX_TERMINAL_CONFIGURATION_IDENTITY_BYTES :: 96
/* MAX_TERMINAL_CONFIGURATION_SHELL_BYTES bounds one copied configured shell path. */
MAX_TERMINAL_CONFIGURATION_SHELL_BYTES :: 4 * 1_024

@(private)
Terminal_Attention_Channel :: enum u8 {
	Invalid,
	None,
	Audible,
	Visual,
	Both,
}

@(private)
Terminal_Settings_State :: struct {
	shell:        [MAX_TERMINAL_CONFIGURATION_SHELL_BYTES]u8,
	shell_length: u16,
	attention:    Terminal_Attention_Channel,
	limits:       terminal_session.Event_Limits,
}

@(private)
Terminal_Workspace_Configuration_State :: struct {
	identity:        [MAX_TERMINAL_CONFIGURATION_IDENTITY_BYTES]u8,
	identity_length: u8,
	settings:        Terminal_Settings_State,
}

@(private)
Terminal_Configuration_State :: struct {
	global:           Terminal_Settings_State,
	workspaces:       [MAX_TERMINAL_CONFIGURATION_WORKSPACES]Terminal_Workspace_Configuration_State,
	workspace_count:  u8,
	automation_count: u8,
}

@(private)
Personal_Configuration_Result :: enum u8 {
	Invalid,
	Confirmed,
	Rejected,
}

@(private)
Personal_Configuration_Observation :: enum u8 {
	Invalid,
	Absent,
	Confirmed,
	Rejected,
	Unavailable,
}

@(private)
Completion_Configuration_State :: struct {
	enabled: bool,
	session: completion.Session_Policy,
	limits:  completion.Limits,
}

@(private)
Personal_Configuration_Startup_State :: struct {
	present: bool,
	status: Personal_Configuration_Result,
	observation: Personal_Configuration_Observation,
	confirmed_generation: u64,
	rejected_generation: u64,
	diagnostic_length: int,
	status_bar_policy: status_bar.Factory_Policy,
	gutter_policy:     gutter.Factory_Policy,
	completion_configuration: Completion_Configuration_State,
	recovery_policy: recovery.Policy,
	gutter_provider_offset: int,
	gutter_provider_length: int,
	language_support_offset: int,
	language_support_length: int,
	indentation_offset: int,
	indentation_length: int,
}

@(private)
command_context_apply_startup_configuration :: proc(
	commands: ^Command_Context,
	state: Personal_Configuration_Startup_State,
	startup_result: []u8,
) {
	assert(commands != nil && state.present)
	commands.personal_configuration = state
	commands.status_bar_policy = state.status_bar_policy
	commands.completion_configuration = state.completion_configuration
	indentation_candidate: indentation.Registry
	indentation_prepared := personal_configuration_indentation_prepare(
		commands.indentation_registry,
		state,
		startup_result,
		&indentation_candidate,
	)
	if indentation_prepared do commands.indentation_registry^ = indentation_candidate
	command_context_apply_gutter_configuration(commands, &commands.personal_configuration)
	ksawery_extension, ksawery_extension_ok :=
		personal_configuration_ksawery_extension(startup_result)
	if ksawery_extension_ok {
		_ = product_module_workflow_configure(
			commands,
			state.confirmed_generation,
			ksawery_extension,
		)
	}
	command_context_report_startup_configuration(commands, startup_result)
}

@(private)
command_context_report_startup_configuration :: proc(
	commands: ^Command_Context,
	startup_result: []u8,
) {
	if commands == nil || !commands.personal_configuration.present {
		return
	}
	state := commands.personal_configuration
	if state.status == .Confirmed {
		if state.observation == .Confirmed {
			command_context_set_diagnostic(commands, "Personal configuration loaded")
		}
		return
	}
	if state.status != .Rejected {
		return
	}
	detail := personal_configuration_startup_diagnostic(startup_result, state.diagnostic_length)
	state_text := "rejected"
	if state.observation == .Unavailable {
		state_text = "unavailable"
	}
	if len(detail) == 0 {
		detail = "no diagnostic detail"
	}
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Personal configuration %s: %s; factory configuration preserved",
		state_text,
		detail,
	)
	commands.diagnostic_length = len(message)
}

@(private)
personal_configuration_startup_decode :: proc(
	input: []u8,
) -> (
	state: Personal_Configuration_Startup_State,
	terminal_configuration: Terminal_Configuration_State,
	ok: bool,
) {
	if len(input) < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES {
		return {}, {}, false
	}
	schema, schema_ok := personal_configuration_startup_word(input, 0)
	status_value, status_ok := personal_configuration_startup_word(input, 8)
	observation_value, observation_ok := personal_configuration_startup_word(input, 16)
	confirmed_generation, confirmed_generation_ok := personal_configuration_startup_word(input, 24)
	rejected_generation, rejected_generation_ok := personal_configuration_startup_word(input, 32)
	diagnostic_bytes, diagnostic_bytes_ok := personal_configuration_startup_word(input, 40)
	position_value, position_ok := personal_configuration_startup_word(input, 48)
	compact_value, compact_ok := personal_configuration_startup_word(input, 56)
	visibility_value, visibility_ok := personal_configuration_startup_word(input, 64)
	gutter_visible_value, gutter_visible_ok := personal_configuration_startup_word(input, 72)
	gutter_side_value, gutter_side_ok := personal_configuration_startup_word(input, 80)
	gutter_order_value, gutter_order_ok := personal_configuration_startup_word(input, 88)
	gutter_mode_value, gutter_mode_ok := personal_configuration_startup_word(input, 96)
	gutter_scope_value, gutter_scope_ok := personal_configuration_startup_word(input, 104)
	gutter_current_value, gutter_current_ok := personal_configuration_startup_word(input, 112)
	gutter_minimum_value, gutter_minimum_ok := personal_configuration_startup_word(input, 120)
	gutter_maximum_value, gutter_maximum_ok := personal_configuration_startup_word(input, 128)
	gutter_left_padding_value, gutter_left_padding_ok := personal_configuration_startup_word(input, 136)
	gutter_right_padding_value, gutter_right_padding_ok := personal_configuration_startup_word(input, 144)
	gutter_separator_bytes, gutter_separator_ok := personal_configuration_startup_word(input, 152)
	gutter_fallback_bytes, gutter_fallback_ok := personal_configuration_startup_word(input, 160)
	gutter_provider_bytes, gutter_provider_ok := personal_configuration_startup_word(input, 168)
	completion_enabled_value, completion_enabled_ok := personal_configuration_startup_word(input, 176)
	completion_provider_value, completion_provider_ok := personal_configuration_startup_word(input, 184)
	completion_policy_value, completion_policy_ok := personal_configuration_startup_word(input, 192)
	completion_presentation_value, completion_presentation_ok := personal_configuration_startup_word(input, 200)
	completion_explicit_value, completion_explicit_ok := personal_configuration_startup_word(input, 208)
	completion_identifier_value, completion_identifier_ok := personal_configuration_startup_word(input, 216)
	completion_trigger_value, completion_trigger_ok := personal_configuration_startup_word(input, 224)
	completion_minimum_value, completion_minimum_ok := personal_configuration_startup_word(input, 232)
	completion_case_prefix_value, completion_case_prefix_ok := personal_configuration_startup_word(input, 240)
	completion_folded_prefix_value, completion_folded_prefix_ok := personal_configuration_startup_word(input, 248)
	completion_subsequence_value, completion_subsequence_ok := personal_configuration_startup_word(input, 256)
	completion_candidate_limit, completion_candidate_limit_ok := personal_configuration_startup_word(input, 264)
	completion_edit_limit, completion_edit_limit_ok := personal_configuration_startup_word(input, 272)
	completion_text_limit, completion_text_limit_ok := personal_configuration_startup_word(input, 280)
	completion_detail_limit, completion_detail_limit_ok := personal_configuration_startup_word(input, 288)
	completion_resolve_limit, completion_resolve_limit_ok := personal_configuration_startup_word(input, 296)
	completion_implementation_limit, completion_implementation_limit_ok := personal_configuration_startup_word(input, 304)
	completion_replacement_limit, completion_replacement_limit_ok := personal_configuration_startup_word(input, 312)
	completion_request_limit, completion_request_limit_ok := personal_configuration_startup_word(input, 320)
	terminal_configuration_bytes, terminal_configuration_ok := personal_configuration_startup_word(input, 328)
	ksawery_extension_bytes, ksawery_extension_ok := personal_configuration_startup_word(input, 336)
	language_support_bytes, language_support_ok := personal_configuration_startup_word(input, 344)
	recovery_enabled_value, recovery_enabled_ok := personal_configuration_startup_word(input, 352)
	recovery_strategy_value, recovery_strategy_ok := personal_configuration_startup_word(input, 360)
	recovery_debounce_value, recovery_debounce_ok := personal_configuration_startup_word(input, 368)
	recovery_interval_value, recovery_interval_ok := personal_configuration_startup_word(input, 376)
	recovery_age_value, recovery_age_ok := personal_configuration_startup_word(input, 384)
	recovery_per_buffer_value, recovery_per_buffer_ok := personal_configuration_startup_word(input, 392)
	recovery_total_records_value, recovery_total_records_ok := personal_configuration_startup_word(input, 400)
	recovery_record_bytes_value, recovery_record_bytes_ok := personal_configuration_startup_word(input, 408)
	recovery_buffer_bytes_value, recovery_buffer_bytes_ok := personal_configuration_startup_word(input, 416)
	recovery_store_bytes_value, recovery_store_bytes_ok := personal_configuration_startup_word(input, 424)
	recovery_cleanup_value, recovery_cleanup_ok := personal_configuration_startup_word(input, 432)
	recovery_startup_value, recovery_startup_ok := personal_configuration_startup_word(input, 440)
	recovery_autosave_value, recovery_autosave_ok := personal_configuration_startup_word(input, 448)
	indentation_configuration_bytes, indentation_configuration_ok :=
		personal_configuration_startup_word(input, 456)
	if !schema_ok || !status_ok || !observation_ok || !confirmed_generation_ok ||
	   !rejected_generation_ok || !diagnostic_bytes_ok || !position_ok || !compact_ok ||
	   !visibility_ok || !gutter_visible_ok || !gutter_side_ok || !gutter_order_ok ||
	   !gutter_mode_ok || !gutter_scope_ok || !gutter_current_ok || !gutter_minimum_ok ||
	   !gutter_maximum_ok || !gutter_left_padding_ok || !gutter_right_padding_ok ||
	   !gutter_separator_ok || !gutter_fallback_ok || !gutter_provider_ok ||
	   !completion_enabled_ok || !completion_provider_ok || !completion_policy_ok ||
	   !completion_presentation_ok || !completion_explicit_ok || !completion_identifier_ok ||
	   !completion_trigger_ok || !completion_minimum_ok || !completion_case_prefix_ok ||
	   !completion_folded_prefix_ok || !completion_subsequence_ok ||
	   !completion_candidate_limit_ok || !completion_edit_limit_ok ||
	   !completion_text_limit_ok || !completion_detail_limit_ok ||
	   !completion_resolve_limit_ok || !completion_implementation_limit_ok ||
	   !completion_replacement_limit_ok || !completion_request_limit_ok ||
	   !terminal_configuration_ok || !ksawery_extension_ok || !language_support_ok ||
	   !recovery_enabled_ok || !recovery_strategy_ok || !recovery_debounce_ok ||
	   !recovery_interval_ok || !recovery_age_ok || !recovery_per_buffer_ok ||
	   !recovery_total_records_ok || !recovery_record_bytes_ok ||
	   !recovery_buffer_bytes_ok || !recovery_store_bytes_ok || !recovery_cleanup_ok ||
	   !recovery_startup_ok || !recovery_autosave_ok || !indentation_configuration_ok ||
	   schema != PERSONAL_CONFIGURATION_STARTUP_SCHEMA_VERSION {
		return {}, {}, false
	}
	payload_capacity := u64(len(input) - PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES)
	payload_bytes := diagnostic_bytes + gutter_separator_bytes + gutter_fallback_bytes +
		gutter_provider_bytes + terminal_configuration_bytes + ksawery_extension_bytes +
		language_support_bytes + indentation_configuration_bytes
	if payload_bytes < diagnostic_bytes || payload_bytes > payload_capacity {
		return {}, {}, false
	}
	status, status_decoded := personal_configuration_startup_status(status_value)
	observation, observation_decoded := personal_configuration_startup_observation(observation_value)
	if !status_decoded || !observation_decoded {
		return {}, {}, false
	}
	policy, policy_ok := personal_configuration_status_bar_policy(
		position_value,
		compact_value,
		visibility_value,
	)
	if !policy_ok do return {}, {}, false
	gutter_policy, gutter_policy_ok := personal_configuration_gutter_policy(
		input,
		diagnostic_bytes,
		gutter_separator_bytes,
		gutter_fallback_bytes,
		gutter_visible_value,
		gutter_side_value,
		gutter_order_value,
		gutter_mode_value,
		gutter_scope_value,
		gutter_current_value,
		gutter_minimum_value,
		gutter_maximum_value,
		gutter_left_padding_value,
		gutter_right_padding_value,
	)
	if !gutter_policy_ok do return {}, {}, false
	completion_configuration, completion_configuration_ok :=
		personal_configuration_completion_configuration(
			completion_enabled_value,
			completion_provider_value,
			completion_policy_value,
			completion_presentation_value,
			completion_explicit_value,
			completion_identifier_value,
			completion_trigger_value,
			completion_minimum_value,
			completion_case_prefix_value,
			completion_folded_prefix_value,
			completion_subsequence_value,
			completion_candidate_limit,
			completion_edit_limit,
			completion_text_limit,
			completion_detail_limit,
			completion_resolve_limit,
			completion_implementation_limit,
			completion_replacement_limit,
			completion_request_limit,
		)
	if !completion_configuration_ok do return {}, {}, false
	recovery_policy, recovery_policy_ok := personal_configuration_recovery_policy(
		recovery_enabled_value,
		recovery_strategy_value,
		recovery_debounce_value,
		recovery_interval_value,
		recovery_age_value,
		recovery_per_buffer_value,
		recovery_total_records_value,
		recovery_record_bytes_value,
		recovery_buffer_bytes_value,
		recovery_store_bytes_value,
		recovery_cleanup_value,
		recovery_startup_value,
		recovery_autosave_value,
		confirmed_generation,
	)
	if !recovery_policy_ok do return {}, {}, false
	terminal_configuration_start := u64(PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES) +
		diagnostic_bytes + gutter_separator_bytes + gutter_fallback_bytes + gutter_provider_bytes
	terminal_configuration_end := terminal_configuration_start + terminal_configuration_bytes
	if terminal_configuration_end < terminal_configuration_start ||
	   terminal_configuration_end > u64(len(input)) {
		return {}, {}, false
	}
	terminal_configuration_decoded: bool
	terminal_configuration, terminal_configuration_decoded =
		personal_configuration_terminal_configuration(
			input[int(terminal_configuration_start):int(terminal_configuration_end)],
		)
	if !terminal_configuration_decoded do return {}, {}, false
	ksawery_extension_start := terminal_configuration_end
	ksawery_extension_end := ksawery_extension_start + ksawery_extension_bytes
	if ksawery_extension_end < ksawery_extension_start ||
	   ksawery_extension_end > u64(len(input)) {
		return {}, {}, false
	}
	language_support_start := ksawery_extension_end
	language_support_end := language_support_start + language_support_bytes
	if language_support_end < language_support_start ||
	   language_support_bytes == 0 ||
	   language_support_bytes > MAX_LANGUAGE_SUPPORT_CONFIGURATION_BYTES {
		return {}, {}, false
	}
	indentation_start := language_support_end
	indentation_end := indentation_start + indentation_configuration_bytes
	if indentation_end < indentation_start || indentation_end != u64(len(input)) ||
	   indentation_configuration_bytes == 0 {
		return {}, {}, false
	}
	language_support_candidate, language_support_prepared :=
		language_support.personal_source_prepare(
			input[int(language_support_start):int(language_support_end)],
			confirmed_generation,
			context.temp_allocator,
		)
	if !language_support_prepared do return {}, {}, false
	defer language_support.source_candidate_close(&language_support_candidate)
	state.present = true
	state.status = status
	state.observation = observation
	state.confirmed_generation = confirmed_generation
	state.rejected_generation = rejected_generation
	state.diagnostic_length = int(diagnostic_bytes)
	state.status_bar_policy = policy
	state.gutter_policy = gutter_policy
	state.completion_configuration = completion_configuration
	state.recovery_policy = recovery_policy
	state.gutter_provider_offset = PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES +
		int(diagnostic_bytes + gutter_separator_bytes + gutter_fallback_bytes)
	state.gutter_provider_length = int(gutter_provider_bytes)
	state.language_support_offset = int(language_support_start)
	state.language_support_length = int(language_support_bytes)
	state.indentation_offset = int(indentation_start)
	state.indentation_length = int(indentation_configuration_bytes)
	validation_registry: indentation.Registry
	validation_initialized, _ := indentation.registry_init(&validation_registry)
	if !validation_initialized do return {}, {}, false
	validation_candidate: indentation.Registry
	indentation_valid := personal_configuration_indentation_prepare(
		&validation_registry,
		state,
		input,
		&validation_candidate,
	)
	if !indentation_valid do return {}, {}, false
	return state, terminal_configuration, true
}

@(private)
personal_configuration_ksawery_extension :: proc(input: []u8) -> ([]u8, bool) {
	if len(input) < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES do return nil, false
	diagnostic_bytes, diagnostic_ok := personal_configuration_startup_word(input, 40)
	separator_bytes, separator_ok := personal_configuration_startup_word(input, 152)
	fallback_bytes, fallback_ok := personal_configuration_startup_word(input, 160)
	gutter_provider_bytes, gutter_ok := personal_configuration_startup_word(input, 168)
	terminal_bytes, terminal_ok := personal_configuration_startup_word(input, 328)
	extension_bytes, extension_ok := personal_configuration_startup_word(input, 336)
	language_support_bytes, language_support_ok := personal_configuration_startup_word(input, 344)
	indentation_bytes, indentation_ok := personal_configuration_startup_word(input, 456)
	if !diagnostic_ok || !separator_ok || !fallback_ok || !gutter_ok || !terminal_ok ||
	   !extension_ok || !language_support_ok || !indentation_ok {
		return nil, false
	}
	start := u64(PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES) + diagnostic_bytes +
		separator_bytes + fallback_bytes + gutter_provider_bytes + terminal_bytes
	end := start + extension_bytes
	if end < start || end > u64(len(input)) ||
	   language_support_bytes + indentation_bytes != u64(len(input)) - end {
		return nil, false
	}
	return input[int(start):int(end)], true
}

@(private)
personal_configuration_language_support :: proc(
	state: Personal_Configuration_Startup_State,
	input: []u8,
) -> ([]u8, bool) {
	if !state.present || state.language_support_length <= 0 ||
	   state.language_support_offset < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES ||
	   state.language_support_offset > len(input) - state.language_support_length {
		return nil, false
	}
	result := input[
		state.language_support_offset:
		state.language_support_offset + state.language_support_length
	]
	return result, language_support.configuration_valid(result)
}

@(private)
personal_configuration_indentation_prepare :: proc(
	registry: ^indentation.Registry,
	state: Personal_Configuration_Startup_State,
	input: []u8,
	candidate: ^indentation.Registry,
) -> bool {
	if registry == nil || candidate == nil || !state.present ||
	   state.indentation_length < INDENTATION_CONFIGURATION_HEADER_BYTES ||
	   state.indentation_offset < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES ||
	   state.indentation_offset > len(input) - state.indentation_length {
		return false
	}
	payload := input[
		state.indentation_offset:
		state.indentation_offset + state.indentation_length
	]
	prepared, _ := indentation.registry_prepare_encoded(
		registry,
		payload,
		state.confirmed_generation,
		candidate,
	)
	return prepared
}

@(private)
personal_configuration_terminal_configuration :: proc(
	input: []u8,
) -> (configuration: Terminal_Configuration_State, ok: bool) {
	if len(input) < TERMINAL_CONFIGURATION_HEADER_BYTES do return {}, false
	schema, schema_ok := personal_configuration_startup_word(input, 0)
	workspace_count, workspace_count_ok := personal_configuration_startup_word(input, 80)
	automation_count, automation_count_ok := personal_configuration_startup_word(input, 88)
	if !schema_ok || !workspace_count_ok || !automation_count_ok ||
	   schema != TERMINAL_CONFIGURATION_SCHEMA_VERSION ||
	   workspace_count > MAX_TERMINAL_CONFIGURATION_WORKSPACES ||
	   automation_count > 16 {
		return {}, false
	}
	fixed_bytes := u64(TERMINAL_CONFIGURATION_HEADER_BYTES) +
		workspace_count * TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES +
		automation_count * TERMINAL_AUTOMATION_RECORD_BYTES
	if fixed_bytes > u64(len(input)) do return {}, false
	global, global_ok := terminal_configuration_settings(input, 8, fixed_bytes)
	if !global_ok do return {}, false
	configuration.global = global
	configuration.workspace_count = u8(workspace_count)
	configuration.automation_count = u8(automation_count)
	for index in 0 ..< int(workspace_count) {
		offset := TERMINAL_CONFIGURATION_HEADER_BYTES +
			index * TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES
		identity_offset, identity_offset_ok := personal_configuration_startup_word(input, offset)
		identity_length, identity_length_ok := personal_configuration_startup_word(input, offset + 8)
		if !identity_offset_ok || !identity_length_ok || identity_length == 0 ||
		   identity_length > MAX_TERMINAL_CONFIGURATION_IDENTITY_BYTES ||
		   !terminal_configuration_segment_valid(input, identity_offset, identity_length, fixed_bytes) {
			return {}, false
		}
		identity := input[int(identity_offset):int(identity_offset + identity_length)]
		if !terminal_configuration_utf8_valid(identity) do return {}, false
		for previous in configuration.workspaces[:index] {
			previous_copy := previous
			if string(previous_copy.identity[:previous_copy.identity_length]) == string(identity) do return {}, false
		}
		workspace := &configuration.workspaces[index]
		workspace.identity_length = u8(copy(workspace.identity[:], identity))
		settings, settings_ok := terminal_configuration_settings(input, offset + 16, fixed_bytes)
		if !settings_ok do return {}, false
		workspace.settings = settings
	}
	automation_base := TERMINAL_CONFIGURATION_HEADER_BYTES +
		int(workspace_count) * TERMINAL_WORKSPACE_CONFIGURATION_RECORD_BYTES
	admitted_event_mask := (u64(1) << 12) - 2
	for index in 0 ..< int(automation_count) {
		offset := automation_base + index * TERMINAL_AUTOMATION_RECORD_BYTES
		name_offset, name_offset_ok := personal_configuration_startup_word(input, offset)
		name_length, name_length_ok := personal_configuration_startup_word(input, offset + 8)
		event_mask, event_mask_ok := personal_configuration_startup_word(input, offset + 16)
		raw_output, raw_output_ok := personal_configuration_startup_word(input, offset + 24)
		batch_events, batch_events_ok := personal_configuration_startup_word(input, offset + 32)
		batch_bytes, batch_bytes_ok := personal_configuration_startup_word(input, offset + 40)
		turn_milliseconds, turn_ok := personal_configuration_startup_word(input, offset + 48)
		temporary_bytes, temporary_ok := personal_configuration_startup_word(input, offset + 56)
		if !name_offset_ok || !name_length_ok || !event_mask_ok || !raw_output_ok ||
		   !batch_events_ok || !batch_bytes_ok || !turn_ok || !temporary_ok ||
		   name_length == 0 || name_length > MAX_TERMINAL_CONFIGURATION_IDENTITY_BYTES ||
		   !terminal_configuration_segment_valid(input, name_offset, name_length, fixed_bytes) ||
		   event_mask == 0 || event_mask & ~admitted_event_mask != 0 || raw_output > 1 ||
		   (raw_output == 1) != (event_mask & (u64(1) << 10) != 0) ||
		   batch_events == 0 || batch_events > terminal_session.MAX_EVENT_BATCH_ENTRIES ||
		   batch_bytes == 0 || batch_bytes > terminal_session.MAX_EVENT_BATCH_BYTES ||
		   turn_milliseconds == 0 || turn_milliseconds > terminal_session.MAX_SUBSCRIBER_TURN_MILLISECONDS ||
		   temporary_bytes == 0 || temporary_bytes > terminal_session.MAX_SUBSCRIBER_TEMPORARY_BYTES {
			return {}, false
		}
		name := input[int(name_offset):int(name_offset + name_length)]
		if !terminal_configuration_utf8_valid(name) do return {}, false
	}
	return configuration, true
}

@(private)
terminal_configuration_settings :: proc(
	input: []u8,
	offset: int,
	fixed_bytes: u64,
) -> (settings: Terminal_Settings_State, ok: bool) {
	values: [9]u64
	for &value, index in values {
		decoded: bool
		value, decoded = personal_configuration_startup_word(input, offset + index * 8)
		if !decoded do return {}, false
	}
	attention, attention_ok := terminal_configuration_attention(values[0])
	if !attention_ok || values[1] > u64(max(u16)) || values[5] > u64(max(u16)) ||
	   values[6] > u64(max(u16)) || values[8] > MAX_TERMINAL_CONFIGURATION_SHELL_BYTES ||
	   !terminal_configuration_segment_valid(input, values[7], values[8], fixed_bytes) {
		return {}, false
	}
	limits := terminal_session.Event_Limits {
		event_entries = u16(values[1]),
		event_bytes = values[2],
		aggregate_event_entries = values[3],
		aggregate_event_bytes = values[4],
		subscribers_per_session = u16(values[5]),
		subscribers = u16(values[6]),
	}
	if !terminal_configuration_limits_valid(limits) do return {}, false
	shell := input[int(values[7]):int(values[7] + values[8])]
	if len(shell) > 0 && !terminal_configuration_utf8_valid(shell) do return {}, false
	settings.attention = attention
	settings.limits = limits
	settings.shell_length = u16(copy(settings.shell[:], shell))
	return settings, true
}

@(private)
terminal_configuration_segment_valid :: proc(
	input: []u8,
	offset, length, fixed_bytes: u64,
) -> bool {
	return offset >= fixed_bytes && offset <= u64(len(input)) &&
		length <= u64(len(input)) - offset
}

@(private)
terminal_configuration_utf8_valid :: proc(value: []u8) -> bool {
	if !utf8.valid_string(string(value)) do return false
	for byte in value do if byte == 0 do return false
	return true
}

@(private)
terminal_configuration_attention :: proc(value: u64) -> (Terminal_Attention_Channel, bool) {
	switch value {
	case 1: return .None, true
	case 2: return .Audible, true
	case 3: return .Visual, true
	case 4: return .Both, true
	}
	return .Invalid, false
}

@(private)
terminal_configuration_limits_valid :: proc(limits: terminal_session.Event_Limits) -> bool {
	return limits.event_entries >= 64 && limits.event_entries <= terminal_session.MAX_EVENT_ENTRIES &&
		limits.event_bytes >= 64 * 1_024 && limits.event_bytes <= terminal_session.MAX_EVENT_BYTES &&
		limits.aggregate_event_entries >= u64(limits.event_entries) &&
		limits.aggregate_event_entries <= terminal_session.MAX_AGGREGATE_EVENT_ENTRIES &&
		limits.aggregate_event_bytes >= limits.event_bytes &&
		limits.aggregate_event_bytes <= terminal_session.MAX_AGGREGATE_EVENT_BYTES &&
		limits.subscribers_per_session > 0 &&
		limits.subscribers_per_session <= terminal_session.MAX_SUBSCRIBERS_PER_SESSION &&
		limits.subscribers >= limits.subscribers_per_session &&
		limits.subscribers <= terminal_session.MAX_SUBSCRIBERS
}

@(private)
terminal_configuration_global_shell :: proc(configuration: ^Terminal_Configuration_State) -> string {
	if configuration == nil do return ""
	return string(configuration.global.shell[:configuration.global.shell_length])
}

@(private)
terminal_configuration_workspace_settings :: proc(
	configuration: ^Terminal_Configuration_State,
	identity: editor_session.Workspace_ID,
) -> (Terminal_Settings_State, bool) {
	if configuration == nil || identity.length == 0 do return {}, false
	identity_copy := identity
	value := string(identity_copy.bytes[:identity_copy.length])
	for workspace in configuration.workspaces[:configuration.workspace_count] {
		workspace_copy := workspace
		if string(workspace_copy.identity[:workspace_copy.identity_length]) == value {
			return workspace_copy.settings, true
		}
	}
	return {}, false
}

@(private)
terminal_configuration_effective_settings :: proc(
	commands: ^Command_Context,
	configuration: ^Terminal_Configuration_State,
) -> Terminal_Settings_State {
	if configuration == nil do return {}
	if commands != nil && commands.session_owner != nil {
		workspace, workspace_ok, _ := editor_session.session_active_workspace(
			commands.session_owner, commands.session_handle,
		)
		if workspace_ok && workspace.active {
			settings, found := terminal_configuration_workspace_settings(
				configuration, workspace.descriptor.id,
			)
			if found do return settings
		}
	}
	return configuration.global
}

@(private)
personal_configuration_completion_configuration :: proc(
	enabled, provider, policy, presentation, explicit, identifier, trigger, minimum: u64,
	case_prefix, folded_prefix, subsequence, candidates, edits, text_bytes, detail_bytes: u64,
	resolve_bytes, implementations, replacements, request_replacements: u64,
) -> (Completion_Configuration_State, bool) {
	if enabled > 1 || provider != 1 || policy != 1 || presentation != 1 ||
	   explicit > 1 || identifier > 1 || trigger > 1 || case_prefix > 1 ||
	   folded_prefix > 1 || subsequence > 1 || minimum > u64(max(u16)) ||
	   candidates > u64(max(u16)) || edits > u64(max(u8)) ||
	   text_bytes > u64(max(u16)) || detail_bytes > u64(max(u16)) ||
	   resolve_bytes > u64(max(u16)) || implementations > u64(max(u16)) ||
	   replacements > u64(max(u16)) || request_replacements > u64(max(u16)) {
		return {}, false
	}
	configuration := Completion_Configuration_State{enabled = enabled == 1}
	configuration.session = {
		explicit_enabled = explicit == 1,
		identifier_enabled = identifier == 1,
		trigger_character_enabled = trigger == 1,
		minimum_identifier_graphemes = u16(minimum),
		filter = {
			case_sensitive_prefix = case_prefix == 1,
			case_insensitive_prefix = folded_prefix == 1,
			subsequence = subsequence == 1,
		},
	}
	configuration.limits = {
		candidates = u16(candidates),
		additional_edits = u8(edits),
		text_bytes = u16(text_bytes),
		detail_bytes = u16(detail_bytes),
		resolve_bytes = u16(resolve_bytes),
		implementations = u16(implementations),
		replacements = u16(replacements),
		request_replacements = u16(request_replacements),
	}
	factory := completion.factory_configuration()
	factory.enabled = configuration.enabled
	factory.session = configuration.session
	factory.limits = configuration.limits
	return configuration, completion.factory_configuration_is_valid(factory)
}

@(private)
personal_configuration_recovery_policy :: proc(
	enabled, strategy_value, debounce, interval, maximum_age, records_per_buffer: u64,
	total_records, record_bytes, buffer_bytes, store_bytes, cleanup_records: u64,
	startup_value, autosave_value, generation: u64,
) -> (recovery.Policy, bool) {
	if enabled > 1 || generation == 0 do return {}, false
	strategy := recovery.Strategy.Invalid
	switch strategy_value {
	case 1: strategy = .Transaction_Debounced
	case 2: strategy = .Interval
	case 3: strategy = .Hybrid
	case: return {}, false
	}
	startup := recovery.Startup_Policy.Invalid
	switch startup_value {
	case 1: startup = .Ask
	case 2: startup = .Inspect
	case 3: startup = .Restore_Matching
	case: return {}, false
	}
	autosave := recovery.Source_Autosave_Policy.Invalid
	switch autosave_value {
	case 1: autosave = .Disabled
	case 2: autosave = .After_Checkpoint
	case: return {}, false
	}
	policy := recovery.Policy {
		enabled = enabled == 1,
		strategy = strategy,
		debounce_milliseconds = debounce,
		maximum_interval_milliseconds = interval,
		retention = {
			maximum_age_seconds = maximum_age,
			records_per_buffer = records_per_buffer,
			total_records = total_records,
		},
		storage = {
			record_payload_bytes = record_bytes,
			buffer_storage_bytes = buffer_bytes,
			store_storage_bytes = store_bytes,
			cleanup_records = cleanup_records,
		},
		startup = startup,
		source_autosave = autosave,
		generation = recovery.Policy_Generation(generation),
	}
	valid, _ := recovery.policy_validate(policy)
	return policy, valid
}

@(private)
personal_configuration_gutter_policy :: proc(
	input: []u8,
	diagnostic_bytes, separator_bytes, fallback_bytes: u64,
	visible_value, side_value, order_value, mode_value, scope_value, current_value: u64,
	minimum_value, maximum_value, left_padding_value, right_padding_value: u64,
) -> (policy: gutter.Factory_Policy, ok: bool) {
	if visible_value > 1 || order_value > 65_535 || minimum_value > u64(max(u16)) ||
	   maximum_value > u64(max(u16)) || left_padding_value > u64(max(u8)) ||
	   right_padding_value > u64(max(u8)) || separator_bytes == 0 || fallback_bytes == 0 ||
	   separator_bytes > gutter.MAX_REPRESENTATION_BYTES ||
	   fallback_bytes > gutter.MAX_REPRESENTATION_BYTES {
		return {}, false
	}
	side := gutter.Side.Invalid
	switch side_value {
	case 1: side = .Left
	case 2: side = .Right
	case: return {}, false
	}
	mode := gutter.Numbering_Mode.Invalid
	switch mode_value {
	case 1: mode = .None
	case 2: mode = .Absolute
	case 3: mode = .Relative
	case 4: mode = .Hybrid
	case: return {}, false
	}
	scope := gutter.Numbering_Scope.Invalid
	switch scope_value {
	case 1: scope = .Logical
	case 2: return {}, false
	case: return {}, false
	}
	current := gutter.Current_Line_Presentation.Invalid
	switch current_value {
	case 1: current = .Absolute
	case 2: current = .Zero
	case 3: current = .Hidden
	case: return {}, false
	}
	separator_start := u64(PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES) + diagnostic_bytes
	fallback_start := separator_start + separator_bytes
	separator_end := separator_start + separator_bytes
	fallback_end := fallback_start + fallback_bytes
	if separator_end < separator_start || fallback_end < fallback_start ||
	   fallback_end > u64(len(input)) {
		return {}, false
	}
	policy = {
		visible = visible_value == 1,
		side = side,
		order = i16(i64(order_value) - 32_768),
		mode = mode,
		scope = scope,
		current_line = current,
		minimum_digits = u16(minimum_value),
		maximum_digits = u16(maximum_value),
		left_padding = u8(left_padding_value),
		right_padding = u8(right_padding_value),
		separator = {
			kind = .Glyph,
			value = string(input[int(separator_start):int(separator_end)]),
			fallback = string(input[int(fallback_start):int(fallback_end)]),
		},
	}
	return policy, gutter.factory_policy_is_valid(policy)
}

@(private)
command_context_apply_gutter_configuration :: proc(
	commands: ^Command_Context,
	state: ^Personal_Configuration_Startup_State,
) {
	assert(commands != nil && state != nil)
	policy := state.gutter_policy
	separator := policy.separator.value
	fallback := policy.separator.fallback
	assert(len(separator) <= len(commands.gutter_separator))
	assert(len(fallback) <= len(commands.gutter_separator_fallback))
	for &value in commands.gutter_separator do value = 0
	for &value in commands.gutter_separator_fallback do value = 0
	copy(commands.gutter_separator[:], transmute([]u8)(separator))
	copy(commands.gutter_separator_fallback[:], transmute([]u8)(fallback))
	policy.separator.value = string(commands.gutter_separator[:len(separator)])
	policy.separator.fallback = string(commands.gutter_separator_fallback[:len(fallback)])
	commands.gutter_policy = policy
	state.gutter_policy = policy
}

@(private)
personal_configuration_status_bar_policy :: proc(
	position_value, compact_value, visibility_value: u64,
) -> (policy: status_bar.Factory_Policy, ok: bool) {
	position := status_bar.Position_Presentation.Invalid
	switch position_value {
	case 1: position = .Line_Column_Percentage
	case 2: position = .Line_Column
	case 3: position = .Byte_Offset
	case: return {}, false
	}
	compact := status_bar.Compact_Policy.Invalid
	switch compact_value {
	case 1: compact = .Automatic
	case 2: compact = .Prefer_Compact
	case 3: compact = .Essential_Only
	case: return {}, false
	}
	if visibility_value & ~u64(0x1f) != 0 do return {}, false
	visible: status_bar.Optional_Segments
	if visibility_value & 0x01 != 0 do visible += {.Encoding}
	if visibility_value & 0x02 != 0 do visible += {.Pane_State}
	if visibility_value & 0x04 != 0 do visible += {.Workspace}
	if visibility_value & 0x08 != 0 do visible += {.Project}
	if visibility_value & 0x10 != 0 do visible += {.Editing_Context}
	policy = {
		configured = true,
		position = position,
		visible = visible,
		compact = compact,
	}
	return policy, status_bar.factory_policy_is_valid(policy)
}

@(private)
personal_configuration_startup_word :: proc(input: []u8, offset: int) -> (u64, bool) {
	if offset < 0 || len(input) < offset + 8 {
		return 0, false
	}
	return endian.get_u64(input[offset:], .Little)
}

@(private)
personal_configuration_startup_diagnostic :: proc(input: []u8, length: int) -> string {
	if length <= 0 || len(input) < PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES + length {
		return ""
	}
	start := PERSONAL_CONFIGURATION_STARTUP_HEADER_BYTES
	end := start + length
	return string(input[start:end])
}

@(private)
personal_configuration_startup_status :: proc(
	value: u64,
) -> (Personal_Configuration_Result, bool) {
	switch value {
	case 1:
		return .Confirmed, true
	case 2:
		return .Rejected, true
	}
	return .Invalid, false
}

@(private)
personal_configuration_startup_observation :: proc(
	value: u64,
) -> (Personal_Configuration_Observation, bool) {
	switch value {
	case 1:
		return .Absent, true
	case 2:
		return .Confirmed, true
	case 3:
		return .Rejected, true
	case 4:
		return .Unavailable, true
	}
	return .Invalid, false
}

@(private)
command_context_reload_personal_commands :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.racket_runtime == nil ||
	   commands.interaction_generation == nil || commands.registry_generation == 0 {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	reload_batch: [hosting.MAX_PERSONAL_CONFIGURATION_STARTUP_BYTES]u8
	reload_length, reloaded, reload_failure := hosting.runtime_personal_configuration_reload(
		commands.racket_runtime,
		commands.lifecycle_configuration_root,
		u64(commands.registry_generation),
		reload_batch[:],
	)
	if !reloaded {
		return {}, App_Failure{stage = .Configuration_Load, hosting = reload_failure}
	}
	reload_result := reload_batch[:int(reload_length)]
	state, terminal_configuration, decoded := personal_configuration_startup_decode(reload_result)
	if !decoded {
		generation, generation_ok := personal_configuration_startup_word(reload_result, 24)
		if generation_ok && generation > 0 {
			_, _ = hosting.runtime_personal_generation_transition(
				commands.racket_runtime,
				2,
				generation,
			)
		}
		return {}, App_Failure{stage = .Configuration_Load, hosting = {code = .Wrong_Result}}
	}
	if state.status == .Rejected {
		state.status_bar_policy = commands.status_bar_policy
		state.gutter_policy = commands.gutter_policy
		state.completion_configuration = commands.completion_configuration
		state.recovery_policy = commands.personal_configuration.recovery_policy
		_, _ = hosting.runtime_personal_generation_transition(
			commands.racket_runtime,
			2,
			state.confirmed_generation,
		)
		commands.personal_configuration = state
		if state.rejected_generation > 0 {
			_ = product_module_workflow_configure(
				commands,
				state.rejected_generation,
				nil,
				.Rejected,
			)
		}
		command_context_report_personal_command_reload(commands, reload_result)
		return Interaction_Result{changed = true}, {}
	}
	generation := interaction.Registry_Generation(state.confirmed_generation)
	if generation == 0 || generation <= commands.registry_generation {
		_, _ = hosting.runtime_personal_generation_transition(
			commands.racket_runtime,
			2,
			state.confirmed_generation,
		)
		return {}, App_Failure{stage = .Configuration_Load, hosting = {code = .Wrong_Result}}
	}

	candidate: interaction.Generation_Activation
	racket_candidate_pending := true
	defer {
		if candidate.registry.state != nil || candidate.ready {
			_, _ = interaction.generation_activation_close(&candidate)
		}
		if racket_candidate_pending {
			_, _ = hosting.runtime_personal_generation_transition(
				commands.racket_runtime,
				2,
				state.confirmed_generation,
			)
		}
	}

	command_catalog, catalog_loaded, catalog_failure := hosting.runtime_load_command_catalog(
		commands.racket_runtime,
		generation,
		commands.persistent_allocator,
	)
	if !catalog_loaded {
		return {}, App_Failure{stage = .Command_Registry_Init, hosting = catalog_failure}
	}
	definitions, definitions_ok := hosting.command_catalog_candidate_definitions(&command_catalog)
	if !definitions_ok {
		hosting.command_catalog_candidate_close(&command_catalog)
		return {}, App_Failure{stage = .Command_Registry_Init}
	}
	registry_ok, registry_failure := command.built_in_command_registry_init(
		&candidate.registry,
		generation,
		commands.persistent_allocator,
		definitions,
	)
	hosting.command_catalog_candidate_close(&command_catalog)
	if !registry_ok {
		return {}, App_Failure{stage = .Command_Registry_Init, interaction = registry_failure}
	}

	profile_candidate, profile_loaded, profile_failure := hosting.runtime_load_keymap_profile(
		commands.racket_runtime,
		u64(generation),
		commands.persistent_allocator,
	)
	if !profile_loaded {
		return {}, App_Failure{stage = .Keymap_Activation, hosting = profile_failure}
	}
	profile_definition, profile_adapted :=
		hosting.keymap_profile_candidate_catalog_definition(&profile_candidate)
	if !profile_adapted {
		hosting.keymap_profile_candidate_close(&profile_candidate)
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	pair_ok, pair_failure := interaction.generation_activation_complete(
		&candidate,
		generation,
		profile_definition,
		commands.active_interaction_context,
		interaction.Context_ID(state.confirmed_generation),
		commands.persistent_allocator,
	)
	hosting.keymap_profile_candidate_close(&profile_candidate)
	if !pair_ok {
		return {}, App_Failure{stage = .Keymap_Activation, interaction = pair_failure}
	}
	gutter_candidate, gutter_remove, gutter_expected_generation,
		gutter_prepared, gutter_prepare_failure := command_context_prepare_gutter_provider_reload(
		commands,
		state,
		reload_result,
		&candidate.registry,
	)
	defer if gutter_candidate.data != nil {
		gutter.programmable_provider_candidate_close(&gutter_candidate)
	}
	if !gutter_prepared {
		gutter.programmable_registry_fail(&commands.gutter_registry, gutter_prepare_failure)
		command_context_report_gutter_provider_rejection(commands, gutter_prepare_failure)
		return Interaction_Result{changed = true}, {}
	}
	completion_candidate: Completion_Workflow_State
	completion_prepared := false
	defer if completion_prepared do completion_workflow_close(&completion_candidate)
	if completion_workflow_is_live(commands.completion_workflow) {
		completion_candidate, completion_prepared = completion_workflow_prepare_reconfiguration(
			commands.completion_workflow,
			state.completion_configuration,
		)
		if !completion_prepared {
			return {}, App_Failure{stage = .Completion}
		}
	}
	terminal_settings := terminal_configuration_effective_settings(commands, &terminal_configuration)
	terminal_configuration_valid, terminal_configuration_failure :=
		terminal_session.registry_event_can_configure(
			&commands.terminal_workflow.registry,
			terminal_settings.limits,
		)
	if !terminal_configuration_valid {
		return {}, App_Failure {
			stage = .Terminal_Workflow,
			terminal_workflow_stage = .Refresh,
			terminal_session_failure = terminal_configuration_failure,
		}
	}
	ksawery_extension_bytes, ksawery_extension_decoded :=
		personal_configuration_ksawery_extension(reload_result)
	if !ksawery_extension_decoded {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	language_support_bytes, language_support_decoded := personal_configuration_language_support(
		state,
		reload_result,
	)
	if !language_support_decoded {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	language_support_candidate, language_support_prepared := language_support_workflow_prepare(
		commands.syntax_workflow,
		commands.language_service_workflow,
		language_support_bytes,
		state.confirmed_generation,
		commands.persistent_allocator,
	)
	if !language_support_prepared {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	defer language_support_workflow_candidate_close(
		&language_support_candidate,
		commands.language_service_workflow,
	)
	indentation_candidate: indentation.Registry
	indentation_prepared := personal_configuration_indentation_prepare(
		commands.indentation_registry,
		state,
		reload_result,
		&indentation_candidate,
	)
	if !indentation_prepared {
		return {}, App_Failure{stage = .Configuration_Load}
	}

	racket_activated, racket_failure := hosting.runtime_personal_generation_transition(
		commands.racket_runtime,
		1,
		state.confirmed_generation,
	)
	if !racket_activated {
		return {}, App_Failure{stage = .Keymap_Activation, hosting = racket_failure}
	}
	racket_candidate_pending = false
	published, publish_failure := interaction.generation_activation_publish(
		commands.interaction_generation,
		&candidate,
		&commands.pending,
		&commands.context_pending,
	)
	assert(published, "prepared personal command generation failed to publish")
	if !published {
		return {}, App_Failure{stage = .Keymap_Activation, interaction = publish_failure}
	}
	keymap, keymap_ok := interaction.profile_activation_snapshot(
		&commands.interaction_generation.profile,
	)
	assert(keymap_ok, "published personal command generation has no profile snapshot")
	if !keymap_ok {
		return {}, App_Failure{stage = .Keymap_Activation}
	}
	gutter_published, gutter_publish_failure := command_context_publish_gutter_provider_reload(
		commands,
		&gutter_candidate,
		gutter_remove,
		gutter_expected_generation,
	)
	assert(gutter_published, "prepared programmable Gutter generation failed to publish")
	if !gutter_published {
		return {}, App_Failure{stage = .Gutter, gutter = gutter_publish_failure}
	}
	if completion_prepared {
		published_completion := completion_workflow_publish_reconfiguration(
			commands.completion_workflow,
			&completion_candidate,
		)
		assert(published_completion, "prepared completion generation failed to publish")
		if !published_completion do return {}, App_Failure{stage = .Completion}
		completion_prepared = false
	}
	if !product_module_workflow_configure(
		commands,
		state.confirmed_generation,
		ksawery_extension_bytes,
	) {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	commands.registry = &commands.interaction_generation.registry
	commands.registry_generation = generation
	commands.profile_activation = &commands.interaction_generation.profile
	commands.context_maps = &commands.interaction_generation.context_maps
	commands.keymap = keymap
	commands.personal_configuration = state
	commands.status_bar_policy = state.status_bar_policy
	commands.completion_configuration = state.completion_configuration
	commands.terminal_configuration^ = terminal_configuration
	terminal_configuration_applied, terminal_apply_failure :=
		terminal_session.registry_event_configure(
			&commands.terminal_workflow.registry,
			terminal_settings.limits,
		)
	assert(terminal_configuration_applied, "prepared terminal configuration failed to publish")
	if !terminal_configuration_applied {
		return {}, App_Failure {
			stage = .Terminal_Workflow,
			terminal_workflow_stage = .Refresh,
			terminal_session_failure = terminal_apply_failure,
		}
	}
	attention_applied, attention_failure := terminal_workflow_configure_attention(
		commands.terminal_workflow,
		terminal_settings.attention,
	)
	assert(attention_applied, "prepared terminal attention failed to publish")
	if !attention_applied {
		return {}, App_Failure {
			stage = .Terminal_Workflow,
			terminal_workflow_stage = .Refresh,
			terminal_session_failure = attention_failure,
		}
	}
	language_support_published := language_support_workflow_publish(
		&language_support_candidate,
		commands.syntax_workflow,
		commands.language_service_workflow,
	)
	assert(language_support_published, "prepared language support generation failed to publish")
	if !language_support_published {
		return {}, App_Failure{stage = .Configuration_Load}
	}
	commands.indentation_registry^ = indentation_candidate
	_ = language_service_workflow_reconcile(
		commands.language_service_workflow,
		commands.syntax_workflow,
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	command_context_apply_gutter_configuration(commands, &commands.personal_configuration)
	command_context_report_personal_command_reload(commands, reload_result)
	return Interaction_Result{changed = true}, {}
}

@(private)
command_context_report_personal_command_reload :: proc(
	commands: ^Command_Context,
	reload_result: []u8,
) {
	if commands.personal_configuration.status == .Confirmed {
		command_context_set_diagnostic(commands, "Personal commands reloaded")
		return
	}
	detail := personal_configuration_startup_diagnostic(
		reload_result,
		commands.personal_configuration.diagnostic_length,
	)
	if len(detail) == 0 do detail = "no diagnostic detail"
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Personal command reload rejected: %s; active generation preserved",
		detail,
	)
	commands.diagnostic_length = len(message)
}
