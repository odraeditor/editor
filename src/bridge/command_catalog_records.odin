// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../interaction"
import "core:unicode/utf8"

/* COMMAND_CATALOG_SCHEMA_VERSION identifies the copied command-catalog schema. */
COMMAND_CATALOG_SCHEMA_VERSION :: u64(2)
/* MAX_COMMAND_CATALOG_COMMANDS bounds one programmable command contribution. */
MAX_COMMAND_CATALOG_COMMANDS :: u64(interaction.MAX_COMMANDS)
/* MAX_COMMAND_CATALOG_TEXT_BYTES bounds copied command metadata text. */
MAX_COMMAND_CATALOG_TEXT_BYTES :: u64(4 * 1024 * 1024)
/* MAX_COMMAND_CATALOG_COPY_BYTES bounds one complete command catalog candidate. */
MAX_COMMAND_CATALOG_COPY_BYTES :: u64(8 * 1024 * 1024)

/* RACKET_INSPECTION_COMMAND_PROVIDER_ID owns programmable inspection orchestration. */
RACKET_INSPECTION_COMMAND_PROVIDER_ID :: interaction.Command_Provider_ID(3)
/* RACKET_TRANSACTION_COMMAND_PROVIDER_ID owns generic transaction-backed commands. */
RACKET_TRANSACTION_COMMAND_PROVIDER_ID :: interaction.Command_Provider_ID(4)
/* RACKET_PERSONAL_COMMAND_PROVIDER_ID owns generation-bound personal commands. */
RACKET_PERSONAL_COMMAND_PROVIDER_ID :: interaction.Command_Provider_ID(5)
/* RACKET_KSAWERY_COMMAND_PROVIDER_ID owns generation-bound Ksawery extension commands. */
RACKET_KSAWERY_COMMAND_PROVIDER_ID :: interaction.Command_Provider_ID(6)

/* COMMAND_CATALOG_HEADER_BYTES is the stable command catalog envelope width. */
COMMAND_CATALOG_HEADER_BYTES :: u64(64)
/* COMMAND_CATALOG_RECORD_BYTES is one stable programmable command width. */
COMMAND_CATALOG_RECORD_BYTES :: u64(128)

/* Command_Dispatch_Class selects one admitted programmable execution shape. */
Command_Dispatch_Class :: enum u64 {
	Invalid,
	Keymap_Inspection,
	Transaction,
	Personal,
	Ksawery_Extension,
}

/* Command_Catalog_Header_Record describes one complete copied command batch. */
Command_Catalog_Header_Record :: struct {
	schema_version:      u64,
	record_bytes:        u64,
	registry_generation: u64,
	catalog_generation:  u64,
	command_count:       u64,
	text_bytes:          u64,
	reserved_0:          u64,
	reserved_1:          u64,
}

/* Command_Catalog_Record describes one Racket-authored command declaration. */
Command_Catalog_Record :: struct {
	dispatch_class:     u64,
	invocation:         u64,
	text_requirement:   u64,
	effects:            u64,
	interactive:        u64,
	requirements:       u64,
	name_offset:        u64,
	name_bytes:         u64,
	description_offset: u64,
	description_bytes:  u64,
	provider_offset:    u64,
	provider_bytes:     u64,
	source_offset:      u64,
	source_bytes:       u64,
	location_offset:    u64,
	location_bytes:     u64,
}

/* Command_Catalog_Record_Failure_Code classifies copied catalog rejection. */
Command_Catalog_Record_Failure_Code :: enum u16 {
	None,
	Unsupported_Schema,
	Invalid_Header,
	Stale_Generation,
	Command_Limit,
	Text_Limit,
	Copy_Limit,
	Size_Mismatch,
	Count_Mismatch,
	Invalid_Command,
	Duplicate_Command,
	Unknown_Effect,
	Invalid_Text,
}

/* Command_Catalog_Record_Failure identifies one rejected copied record. */
Command_Catalog_Record_Failure :: struct {
	code:   Command_Catalog_Record_Failure_Code,
	index:  u64,
	limit:  u64,
	actual: u64,
}

/* command_catalog_record_bytes validates quotas and returns the exact copied width. */
command_catalog_record_bytes :: proc(
	command_count, text_bytes: u64,
) -> (bytes: u64, failure: Command_Catalog_Record_Failure) {
	if command_count == 0 || command_count > MAX_COMMAND_CATALOG_COMMANDS {
		return 0, {
			code = .Command_Limit,
			limit = MAX_COMMAND_CATALOG_COMMANDS,
			actual = command_count,
		}
	}
	if text_bytes > MAX_COMMAND_CATALOG_TEXT_BYTES {
		return 0, {
			code = .Text_Limit,
			limit = MAX_COMMAND_CATALOG_TEXT_BYTES,
			actual = text_bytes,
		}
	}
	bytes = COMMAND_CATALOG_HEADER_BYTES +
	        command_count * COMMAND_CATALOG_RECORD_BYTES + text_bytes
	if bytes > MAX_COMMAND_CATALOG_COPY_BYTES {
		return 0, {
			code = .Copy_Limit,
			limit = MAX_COMMAND_CATALOG_COPY_BYTES,
			actual = bytes,
		}
	}
	return bytes, {}
}

/* command_catalog_records_validate rejects malformed candidates before adaptation. */
command_catalog_records_validate :: proc(
	header: Command_Catalog_Header_Record,
	records: []Command_Catalog_Record,
	text: []byte,
	expected_generation: interaction.Registry_Generation,
) -> Command_Catalog_Record_Failure {
	if header.schema_version != COMMAND_CATALOG_SCHEMA_VERSION {
		return {code = .Unsupported_Schema, actual = header.schema_version}
	}
	if header.reserved_0 != 0 || header.reserved_1 != 0 ||
	   header.registry_generation == 0 || header.catalog_generation == 0 {
		return {code = .Invalid_Header}
	}
	if header.registry_generation != u64(expected_generation) {
		return {
			code = .Stale_Generation,
			limit = u64(expected_generation),
			actual = header.registry_generation,
		}
	}
	expected_bytes, size_failure := command_catalog_record_bytes(
		header.command_count,
		header.text_bytes,
	)
	if size_failure.code != .None {
		return size_failure
	}
	if header.record_bytes != expected_bytes {
		return {code = .Size_Mismatch, limit = expected_bytes, actual = header.record_bytes}
	}
	if header.command_count != u64(len(records)) || header.text_bytes != u64(len(text)) {
		return {code = .Count_Mismatch}
	}

	for record, index in records {
		if record.dispatch_class == 0 ||
		   record.dispatch_class > u64(Command_Dispatch_Class.Ksawery_Extension) ||
		   record.invocation == 0 ||
		   record.invocation > u64(interaction.Invocation_Class.Cancellation) ||
		   record.text_requirement == 0 ||
		   record.text_requirement > u64(interaction.Text_Requirement.Required) ||
		   record.effects == 0 || record.interactive > 1 ||
		   record.requirements & ~u64(0x07) != 0 {
			return {code = .Invalid_Command, index = u64(index)}
		}
		if record.effects & ~u64(0x0f) != 0 {
			return {
				code = .Unknown_Effect,
				index = u64(index),
				limit = 0x0f,
				actual = record.effects,
			}
		}
		if (record.invocation == u64(interaction.Invocation_Class.Text_Input) &&
		    record.text_requirement != u64(interaction.Text_Requirement.Required)) ||
		   (record.invocation == u64(interaction.Invocation_Class.Cancellation) &&
		    record.text_requirement != u64(interaction.Text_Requirement.Prohibited)) {
			return {code = .Invalid_Command, index = u64(index)}
		}
		if !command_catalog_text_is_valid(
				text, record.name_offset, record.name_bytes,
				u64(interaction.MAX_COMMAND_NAME_BYTES), false,
			) ||
		   !command_catalog_text_is_valid(
				text, record.description_offset, record.description_bytes,
				u64(interaction.MAX_COMMAND_DESCRIPTION_BYTES), true,
			) ||
		   !command_catalog_text_is_valid(
				text, record.provider_offset, record.provider_bytes,
				u64(interaction.MAX_SOURCE_BYTES), false,
			) ||
		   !command_catalog_text_is_valid(
				text, record.source_offset, record.source_bytes,
				u64(interaction.MAX_SOURCE_BYTES), false,
			) ||
		   !command_catalog_text_is_valid(
				text, record.location_offset, record.location_bytes,
				u64(interaction.MAX_LOCATION_BYTES), true,
			) {
			return {code = .Invalid_Text, index = u64(index)}
		}
		name := command_catalog_text(text, record.name_offset, record.name_bytes)
		for prior_index in 0 ..< index {
			prior := records[prior_index]
			if command_catalog_text(text, prior.name_offset, prior.name_bytes) == name {
				return {code = .Duplicate_Command, index = u64(index)}
			}
		}
	}
	return {}
}

/* command_catalog_record_layout_is_valid verifies copied ABI widths. */
command_catalog_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Command_Catalog_Header_Record)) == COMMAND_CATALOG_HEADER_BYTES &&
	       u64(size_of(Command_Catalog_Record)) == COMMAND_CATALOG_RECORD_BYTES
}

/* command_catalog_text borrows one already validated UTF-8 field. */
command_catalog_text :: proc(text: []byte, offset, count: u64) -> string {
	return string(text[int(offset):int(offset + count)])
}

@(private)
command_catalog_text_is_valid :: proc(
	text: []byte,
	offset, count, limit: u64,
	empty_allowed: bool,
) -> bool {
	if (!empty_allowed && count == 0) || count > limit ||
	   offset > u64(len(text)) || count > u64(len(text)) - offset {
		return false
	}
	return utf8.valid_string(string(text[int(offset):int(offset + count)]))
}
