// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../theme"

/* THEME_CAPABILITY_SCHEMA_VERSION identifies the first copied theme ABI. */
THEME_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* MAX_THEME_INSPECTION_DIAGNOSTICS retains only the latest copied rejection. */
MAX_THEME_INSPECTION_DIAGNOSTICS :: u64(1)
/* MAX_THEME_PROPOSAL_TEXT_BYTES bounds all copied proposal text together. */
MAX_THEME_PROPOSAL_TEXT_BYTES :: u64(
	theme.MAX_THEME_IDENTITY_BYTES + theme.MAX_DISPLAY_NAME_BYTES +
		theme.MAX_PROVIDER_NAME_BYTES + theme.MAX_PROVENANCE_BYTES,
)

/* THEME_SCOPE_RECORD_BYTES is one exact registry, selection, and capability scope. */
THEME_SCOPE_RECORD_BYTES :: u64(144)
/* THEME_USAGE_RECORD_BYTES is one copied registry and hosted-turn accounting record. */
THEME_USAGE_RECORD_BYTES :: u64(56)
/* THEME_LIMITS_RECORD_BYTES is the complete copied native resource policy. */
THEME_LIMITS_RECORD_BYTES :: u64(112)
/* THEME_SNAPSHOT_HEADER_BYTES precedes copied provider, definition, and style records. */
THEME_SNAPSHOT_HEADER_BYTES :: u64(360)
/* THEME_PROVIDER_RECORD_BYTES is one pointer-free provider descriptor. */
THEME_PROVIDER_RECORD_BYTES :: u64(64)
/* THEME_DEFINITION_RECORD_BYTES is one pointer-free immutable definition descriptor. */
THEME_DEFINITION_RECORD_BYTES :: u64(112)
/* THEME_STYLE_RECORD_BYTES is one explicit semantic role and frontend-independent style. */
THEME_STYLE_RECORD_BYTES :: u64(80)
/* THEME_PROPOSAL_HEADER_BYTES precedes one complete copied definition proposal. */
THEME_PROPOSAL_HEADER_BYTES :: u64(264)
/* THEME_OUTCOME_RECORD_BYTES is one complete copied lifecycle result. */
THEME_OUTCOME_RECORD_BYTES :: u64(264)
/* THEME_DIAGNOSTIC_RECORD_BYTES is one copied contained rejection. */
THEME_DIAGNOSTIC_RECORD_BYTES :: u64(96)

/* Theme_Capability_Operation identifies one admitted synchronous theme request. */
Theme_Capability_Operation :: enum i32 {
	Scope = 1,
	Inspect = 2,
	Inspect_Definition = 3,
	Propose = 4,
	Confirm = 5,
	Select = 6,
	Replace = 7,
	Restore = 8,
	Select_Baseline = 9,
	Teardown = 10,
}

/* Theme_Capability_Access names checked authority without exposing native ownership. */
Theme_Capability_Access :: enum u64 {
	Inspect = 1,
	Propose = 2,
	Confirm = 3,
	Select = 4,
	Replace = 5,
	Restore = 6,
	Select_Baseline = 7,
	Teardown = 8,
}

/* Theme_Scope_Record binds one capability to exact registry and selection generations. */
Theme_Scope_Record :: struct {
	schema_version:                u64,
	access:                        u64,
	registry_id:                   u64,
	registry_generation:           u64,
	selection_generation:          u64,
	active_provider_id:            u64,
	active_provider_generation:    u64,
	active_definition_id:          u64,
	active_definition_generation:  u64,
	fallback_provider_id:          u64,
	fallback_provider_generation:  u64,
	fallback_definition_id:        u64,
	fallback_definition_generation: u64,
	baseline_provider_id:          u64,
	baseline_provider_generation:  u64,
	baseline_definition_id:        u64,
	baseline_definition_generation: u64,
	capability_generation:         u64,
}

/* Theme_Usage_Record publishes exact native and copied-capability accounting. */
Theme_Usage_Record :: struct {
	providers:                 u64,
	definitions:               u64,
	retained_definition_bytes: u64,
	inspection_bytes:          u64,
	preparation_peak_bytes:    u64,
	operations_in_turn:        u64,
	hosted_turns:              u64,
}

/* Theme_Limits_Record publishes the complete selected theme resource policy. */
Theme_Limits_Record :: struct {
	providers:                 u64,
	definitions:               u64,
	theme_identity_bytes:      u64,
	display_name_bytes:        u64,
	provider_name_bytes:       u64,
	provenance_bytes:          u64,
	styles:                    u64,
	retained_definition_bytes: u64,
	proposal_bytes:            u64,
	operations_per_turn:       u64,
	inspection_bytes:          u64,
	preparation_bytes:         u64,
	diagnostic_bytes:          u64,
	concurrent_hosted_turns:   u64,
}

/* Theme_Snapshot_Header_Record describes one complete copied registry inspection. */
Theme_Snapshot_Header_Record :: struct {
	scope:            Theme_Scope_Record,
	usage:            Theme_Usage_Record,
	limits:           Theme_Limits_Record,
	provider_count:   u64,
	definition_count: u64,
	style_count:      u64,
	diagnostic_count: u64,
	text_bytes:       u64,
	diagnostic_bytes: u64,
}

/* Theme_Provider_Record copies one provider without native pointers. */
Theme_Provider_Record :: struct {
	provider_id:         u64,
	provider_generation: u64,
	kind:                u64,
	state:               u64,
	name_offset:         u64,
	name_bytes:          u64,
	first_definition:    u64,
	definition_count:    u64,
}

/* Theme_Definition_Record copies one immutable definition generation. */
Theme_Definition_Record :: struct {
	provider_id:          u64,
	provider_generation:  u64,
	definition_id:        u64,
	definition_generation: u64,
	state:                u64,
	identity_offset:      u64,
	identity_bytes:       u64,
	display_name_offset:  u64,
	display_name_bytes:   u64,
	provenance_offset:    u64,
	provenance_bytes:     u64,
	first_style:          u64,
	style_count:          u64,
	retained_bytes:       u64,
}

/* Theme_Style_Record copies one explicit optional-color semantic style. */
Theme_Style_Record :: struct {
	role:               u64,
	foreground_present: u64,
	foreground_red:     u64,
	foreground_green:   u64,
	foreground_blue:    u64,
	background_present: u64,
	background_red:     u64,
	background_green:   u64,
	background_blue:    u64,
	attributes:         u64,
}

/* Theme_Proposal_Header_Record carries exact optimistic-concurrency expectations. */
Theme_Proposal_Header_Record :: struct {
	expected_scope:                 Theme_Scope_Record,
	operation:                      u64,
	expected_provider_id:           u64,
	expected_provider_generation:   u64,
	expected_definition_id:         u64,
	expected_definition_generation: u64,
	identity_offset:                u64,
	identity_bytes:                 u64,
	display_name_offset:            u64,
	display_name_bytes:             u64,
	provider_name_offset:           u64,
	provider_name_bytes:            u64,
	provenance_offset:              u64,
	provenance_bytes:               u64,
	style_count:                    u64,
	text_bytes:                     u64,
}

/* Theme_Outcome_Record contains no retained Racket or native ownership. */
Theme_Outcome_Record :: struct {
	scope:                          Theme_Scope_Record,
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
	fallback_selected:              u64,
	baseline_selected:              u64,
	retained_bytes:                 u64,
	operation_count:                u64,
}

/* Theme_Diagnostic_Record copies one stable failure and optional bounded message. */
Theme_Diagnostic_Record :: struct {
	operation:             u64,
	failure_code:          u64,
	provider_id:           u64,
	provider_generation:   u64,
	definition_id:         u64,
	definition_generation: u64,
	expected_generation:   u64,
	actual_generation:     u64,
	limit:                 u64,
	actual:                u64,
	message_offset:        u64,
	message_bytes:         u64,
}

/* theme_snapshot_record_bytes validates quotas and exact copied inspection width. */
theme_snapshot_record_bytes :: proc(
	providers, definitions, styles, diagnostics, text_bytes, diagnostic_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if providers > u64(theme.MAX_PROVIDERS) ||
	   definitions > u64(theme.MAX_DEFINITIONS) ||
	   styles > definitions * u64(theme.MAX_STYLES) ||
	   diagnostics > MAX_THEME_INSPECTION_DIAGNOSTICS ||
	   text_bytes > theme.MAX_INSPECTION_BYTES ||
	   diagnostic_bytes > theme.MAX_DIAGNOSTIC_BYTES {
		return 0, false
	}
	bytes = THEME_SNAPSHOT_HEADER_BYTES + providers * THEME_PROVIDER_RECORD_BYTES +
	        definitions * THEME_DEFINITION_RECORD_BYTES +
	        styles * THEME_STYLE_RECORD_BYTES +
	        diagnostics * THEME_DIAGNOSTIC_RECORD_BYTES + text_bytes + diagnostic_bytes
	return bytes, bytes <= theme.MAX_INSPECTION_BYTES
}

/* theme_proposal_record_bytes validates one complete copied proposal width. */
theme_proposal_record_bytes :: proc(styles, text_bytes: u64) -> (bytes: u64, ok: bool) {
	if styles > u64(theme.MAX_STYLES) || text_bytes > MAX_THEME_PROPOSAL_TEXT_BYTES {
		return 0, false
	}
	bytes = THEME_PROPOSAL_HEADER_BYTES + styles * THEME_STYLE_RECORD_BYTES + text_bytes
	return bytes, bytes <= theme.MAX_PROPOSAL_BYTES
}

/* theme_record_layout_is_valid verifies every C and Racket ABI width. */
theme_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Theme_Scope_Record)) == THEME_SCOPE_RECORD_BYTES &&
	       u64(size_of(Theme_Usage_Record)) == THEME_USAGE_RECORD_BYTES &&
	       u64(size_of(Theme_Limits_Record)) == THEME_LIMITS_RECORD_BYTES &&
	       u64(size_of(Theme_Snapshot_Header_Record)) == THEME_SNAPSHOT_HEADER_BYTES &&
	       u64(size_of(Theme_Provider_Record)) == THEME_PROVIDER_RECORD_BYTES &&
	       u64(size_of(Theme_Definition_Record)) == THEME_DEFINITION_RECORD_BYTES &&
	       u64(size_of(Theme_Style_Record)) == THEME_STYLE_RECORD_BYTES &&
	       u64(size_of(Theme_Proposal_Header_Record)) == THEME_PROPOSAL_HEADER_BYTES &&
	       u64(size_of(Theme_Outcome_Record)) == THEME_OUTCOME_RECORD_BYTES &&
	       u64(size_of(Theme_Diagnostic_Record)) == THEME_DIAGNOSTIC_RECORD_BYTES
}
