// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "../language"

/* ACTIVE_CLOCK_SCHEMA_VERSION identifies the durable active-clock record schema. */
ACTIVE_CLOCK_SCHEMA_VERSION :: u16(1)

/* Clock_Transition identifies the last attributable active-clock change. */
Clock_Transition :: enum u8 {
	Invalid,
	Start,
	Resume,
	Switch,
	Recovery,
	Idle_Resolution,
	Stop,
	Cancel,
}

/* Clock_Recovery_State prevents silent restart or discard after interruption. */
Clock_Recovery_State :: enum u8 {
	Invalid,
	Active,
	Recovery_Required,
	Resolved,
}

/* Absolute_Instant is one UTC instant independent from presentation locale. */
Absolute_Instant :: struct {
	seconds:     i64,
	nanoseconds: u32,
}

/* Time_Zone_Text is one bounded copied interpretation-zone identity. */
Time_Zone_Text :: struct {
	bytes:  [MAX_IDENTITY_BYTES]u8,
	length: u16,
}

/* Active_Clock_Record is the versioned durable schema for one clock domain. */
Active_Clock_Record :: struct {
	schema_version:  u16,
	domain:          Clock_Domain_ID,
	resource:        Resource_Identity,
	target:          Semantic_Target,
	started_at:      Absolute_Instant,
	time_zone:       Time_Zone_Text,
	source_revision: u64,
	source_bytes:    u64,
	last_transition: Clock_Transition,
	recovery_state:  Clock_Recovery_State,
}

/* active_clock_record_is_valid checks one bounded durable record. */
active_clock_record_is_valid :: proc(record: Active_Clock_Record) -> bool {
	return record.schema_version == ACTIVE_CLOCK_SCHEMA_VERSION &&
	       record.domain != Clock_Domain_ID(0) && resource_identity_is_valid(record.resource) &&
	       record.target.node_id != language.Jan_Node_ID(0) && record.target.kind != .Invalid &&
	       record.source_revision == u64(record.target.range.scope.source_revision) &&
	       record.target.range.start < record.target.range.end &&
	       language.jan_source_range_is_valid(record.target.range, record.source_bytes) &&
	       record.started_at.nanoseconds < 1_000_000_000 &&
	       active_clock_time_zone_is_valid(record.time_zone) &&
	       record.last_transition != .Invalid && record.recovery_state != .Invalid
}

/* active_clock_time_zone_copy creates one pointer-free bounded zone identity. */
active_clock_time_zone_copy :: proc(value: string) -> (Time_Zone_Text, bool) {
	if !configuration_text_is_valid(value, MAX_IDENTITY_BYTES) do return {}, false
	result: Time_Zone_Text
	result.length = u16(copy(result.bytes[:], value))
	return result, true
}

/* active_clock_time_zone_is_valid checks one copied zone identity. */
active_clock_time_zone_is_valid :: proc(value: Time_Zone_Text) -> bool {
	copy := value
	return copy.length > 0 && int(copy.length) <= MAX_IDENTITY_BYTES &&
	       configuration_text_is_valid(string(copy.bytes[:copy.length]), MAX_IDENTITY_BYTES)
}

/* active_clock_startup_state preserves unresolved state on revision mismatch. */
active_clock_startup_state :: proc(
	record: Active_Clock_Record,
	current_scope: language.Jan_Analysis_Scope,
) -> Clock_Recovery_State {
	if !active_clock_record_is_valid(record) do return .Invalid
	if record.recovery_state == .Resolved do return .Resolved
	if record.recovery_state == .Recovery_Required do return .Recovery_Required
	if record.target.range.scope != current_scope do return .Recovery_Required
	return .Active
}
