// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../gutter"
import endian "core:encoding/endian"
import "core:unicode/utf8"

/* GUTTER_PROVIDER_SCHEMA_VERSION identifies the copied programmable Gutter ABI. */
GUTTER_PROVIDER_SCHEMA_VERSION :: u64(1)

/* MAX_GUTTER_PROGRAMMABLE_PROVIDERS admits one personal provider generation. */
MAX_GUTTER_PROGRAMMABLE_PROVIDERS :: u64(gutter.MAX_PROGRAMMABLE_PROVIDERS)
/* MAX_GUTTER_PROGRAMMABLE_LANES bounds one personal provider definition. */
MAX_GUTTER_PROGRAMMABLE_LANES :: u64(gutter.MAX_PROGRAMMABLE_LANES_PER_PROVIDER)
/* MAX_GUTTER_PROGRAMMABLE_MARKERS bounds one copied personal publication. */
MAX_GUTTER_PROGRAMMABLE_MARKERS :: u64(gutter.MAX_PROGRAMMABLE_MARKERS_PER_PROVIDER)
/* MAX_GUTTER_PROGRAMMABLE_IDENTITY_BYTES bounds stable machine identities. */
MAX_GUTTER_PROGRAMMABLE_IDENTITY_BYTES :: u64(gutter.MAX_PROGRAMMABLE_IDENTITY_BYTES)
/* MAX_GUTTER_PROGRAMMABLE_PROVIDER_NAME_BYTES bounds one display name. */
MAX_GUTTER_PROGRAMMABLE_PROVIDER_NAME_BYTES :: u64(gutter.MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES)
/* MAX_GUTTER_PROGRAMMABLE_PACKAGE_NAME_BYTES bounds one package identity. */
MAX_GUTTER_PROGRAMMABLE_PACKAGE_NAME_BYTES :: u64(gutter.MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES)
/* MAX_GUTTER_PROGRAMMABLE_COMMAND_NAME_BYTES bounds one admitted action name. */
MAX_GUTTER_PROGRAMMABLE_COMMAND_NAME_BYTES :: u64(gutter.MAX_PROGRAMMABLE_COMMAND_NAME_BYTES)
/* MAX_GUTTER_PROGRAMMABLE_DETAIL_BYTES bounds one inspectable marker detail. */
MAX_GUTTER_PROGRAMMABLE_DETAIL_BYTES :: u64(gutter.MAX_PROGRAMMABLE_DETAIL_BYTES)
/* MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES bounds all trailing copied UTF-8. */
MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES :: u64(gutter.MAX_PROGRAMMABLE_TEXT_BYTES)

/* GUTTER_PROVIDER_HEADER_BYTES precedes lane, marker, and trailing text records. */
GUTTER_PROVIDER_HEADER_BYTES :: u64(96)
/* GUTTER_LANE_RECORD_BYTES is one pointer-free programmable lane declaration. */
GUTTER_LANE_RECORD_BYTES :: u64(152)
/* GUTTER_MARKER_RECORD_BYTES is one pointer-free logical marker declaration. */
GUTTER_MARKER_RECORD_BYTES :: u64(224)
/* MAX_GUTTER_PROVIDER_PROPOSAL_BYTES bounds one complete copied proposal. */
MAX_GUTTER_PROVIDER_PROPOSAL_BYTES :: GUTTER_PROVIDER_HEADER_BYTES +
	MAX_GUTTER_PROGRAMMABLE_LANES * GUTTER_LANE_RECORD_BYTES +
	MAX_GUTTER_PROGRAMMABLE_MARKERS * GUTTER_MARKER_RECORD_BYTES +
	MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES

/* Gutter_Provider_Record describes one complete copied personal provider. */
Gutter_Provider_Record :: struct {
	schema_version:        u64,
	definition_generation: u64,
	marker_generation:     u64,
	lane_count:            u64,
	marker_count:          u64,
	complete:              u64,
	name_offset:           u64,
	name_bytes:            u64,
	package_offset:        u64,
	package_bytes:         u64,
	text_bytes:            u64,
	proposal_bytes:        u64,
}

/* Gutter_Lane_Record copies one lane without native pointers or callbacks. */
Gutter_Lane_Record :: struct {
	definition_generation: u64,
	lane_index:             u64,
	side:                   u64,
	order:                  u64,
	attachments:            u64,
	width_policy:           u64,
	minimum_cells:          u64,
	maximum_cells:          u64,
	alignment:              u64,
	visibility:             u64,
	collision:              u64,
	priority:               u64,
	style_role:             u64,
	identity_offset:        u64,
	identity_bytes:         u64,
	separator_offset:       u64,
	separator_bytes:        u64,
	fallback_offset:        u64,
	fallback_bytes:         u64,
}

/* Gutter_Marker_Record copies one logical marker and up to four named actions. */
Gutter_Marker_Record :: struct {
	definition_generation: u64,
	marker_generation:     u64,
	marker_index:          u64,
	lane_index:            u64,
	logical_line:          u64,
	style_role:            u64,
	priority:              u64,
	representation_kind:   u64,
	stale:                 u64,
	identity_offset:       u64,
	identity_bytes:        u64,
	value_offset:          u64,
	value_bytes:           u64,
	fallback_offset:       u64,
	fallback_bytes:        u64,
	aggregation_offset:    u64,
	aggregation_bytes:     u64,
	detail_offset:         u64,
	detail_bytes:          u64,
	action_count:          u64,
	action_offsets:        [gutter.MAX_ACTIONS_PER_MARKER]u64,
	action_bytes:          [gutter.MAX_ACTIONS_PER_MARKER]u64,
}

/* gutter_provider_record_decode validates one exact provider header. */
gutter_provider_record_decode :: proc(
	input: []u8,
) -> (record: Gutter_Provider_Record, ok: bool) {
	if len(input) < int(GUTTER_PROVIDER_HEADER_BYTES) do return {}, false
	values: [12]u64
	for &value, index in values {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	record = {
		schema_version = values[0],
		definition_generation = values[1],
		marker_generation = values[2],
		lane_count = values[3],
		marker_count = values[4],
		complete = values[5],
		name_offset = values[6],
		name_bytes = values[7],
		package_offset = values[8],
		package_bytes = values[9],
		text_bytes = values[10],
		proposal_bytes = values[11],
	}
	required, width_ok := gutter_provider_record_bytes(
		record.lane_count,
		record.marker_count,
		record.text_bytes,
	)
	return record,
		width_ok && record.schema_version == GUTTER_PROVIDER_SCHEMA_VERSION &&
		record.definition_generation > 0 && record.marker_generation > 0 &&
		record.complete <= 1 && record.proposal_bytes == required &&
		record.name_bytes > 0 && record.name_bytes <= MAX_GUTTER_PROGRAMMABLE_PROVIDER_NAME_BYTES &&
		record.package_bytes > 0 && record.package_bytes <= MAX_GUTTER_PROGRAMMABLE_PACKAGE_NAME_BYTES
}

/* gutter_lane_record_decode decodes one exact pointer-free lane record. */
gutter_lane_record_decode :: proc(input: []u8) -> (record: Gutter_Lane_Record, ok: bool) {
	if len(input) < int(GUTTER_LANE_RECORD_BYTES) do return {}, false
	values: [19]u64
	for &value, index in values {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	record = transmute(Gutter_Lane_Record)values
	return record, true
}

/* gutter_marker_record_decode decodes one exact pointer-free marker record. */
gutter_marker_record_decode :: proc(input: []u8) -> (record: Gutter_Marker_Record, ok: bool) {
	if len(input) < int(GUTTER_MARKER_RECORD_BYTES) do return {}, false
	values: [28]u64
	for &value, index in values {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	record.definition_generation = values[0]
	record.marker_generation = values[1]
	record.marker_index = values[2]
	record.lane_index = values[3]
	record.logical_line = values[4]
	record.style_role = values[5]
	record.priority = values[6]
	record.representation_kind = values[7]
	record.stale = values[8]
	record.identity_offset = values[9]
	record.identity_bytes = values[10]
	record.value_offset = values[11]
	record.value_bytes = values[12]
	record.fallback_offset = values[13]
	record.fallback_bytes = values[14]
	record.aggregation_offset = values[15]
	record.aggregation_bytes = values[16]
	record.detail_offset = values[17]
	record.detail_bytes = values[18]
	record.action_count = values[19]
	for index in 0 ..< gutter.MAX_ACTIONS_PER_MARKER {
		record.action_offsets[index] = values[20 + index * 2]
		record.action_bytes[index] = values[21 + index * 2]
	}
	return record, true
}

/* gutter_provider_record_bytes computes one exact bounded proposal width. */
gutter_provider_record_bytes :: proc(
	lane_count, marker_count, text_bytes: u64,
) -> (total: u64, ok: bool) {
	if lane_count == 0 || lane_count > MAX_GUTTER_PROGRAMMABLE_LANES ||
	   marker_count > MAX_GUTTER_PROGRAMMABLE_MARKERS ||
	   text_bytes > MAX_GUTTER_PROGRAMMABLE_TEXT_BYTES {
		return 0, false
	}
	lane_bytes := lane_count * GUTTER_LANE_RECORD_BYTES
	marker_bytes := marker_count * GUTTER_MARKER_RECORD_BYTES
	total = GUTTER_PROVIDER_HEADER_BYTES + lane_bytes + marker_bytes + text_bytes
	return total, total <= MAX_GUTTER_PROVIDER_PROPOSAL_BYTES
}

/* gutter_record_text validates one exact sequential UTF-8 range. */
gutter_record_text :: proc(
	input: []u8,
	offset, count, expected_offset, maximum: u64,
	empty_allowed := false,
) -> (string, bool) {
	if offset != expected_offset || count > maximum || (!empty_allowed && count == 0) ||
	   offset > u64(len(input)) || count > u64(len(input)) - offset {
		return "", false
	}
	value := string(input[int(offset):int(offset + count)])
	return value, utf8.valid_string(value) && !gutter_record_text_has_control(value)
}

@(private = "file")
gutter_record_text_has_control :: proc(value: string) -> bool {
	for rune in value {
		if rune < 32 || (rune >= 127 && rune <= 159) do return true
	}
	return false
}

/* gutter_record_layout_is_valid checks public constants against native layouts. */
gutter_record_layout_is_valid :: proc() -> bool {
	return size_of(Gutter_Provider_Record) == GUTTER_PROVIDER_HEADER_BYTES &&
		size_of(Gutter_Lane_Record) == GUTTER_LANE_RECORD_BYTES &&
		size_of(Gutter_Marker_Record) == GUTTER_MARKER_RECORD_BYTES
}
