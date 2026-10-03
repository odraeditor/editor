// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../interaction"
import "core:testing"

/* Verifies fixed command catalog layouts and bounded candidate rejection. */
@(test)
catalog_records_are_bounded_and_valid :: proc(t: ^testing.T) {
	testing.expect(t, command_catalog_record_layout_is_valid())
	text_value := "onedescprovidersource"
	text := transmute([]byte)text_value
	record := Command_Catalog_Record {
		dispatch_class = u64(Command_Dispatch_Class.Keymap_Inspection),
		invocation = u64(interaction.Invocation_Class.Ordinary),
		text_requirement = u64(interaction.Text_Requirement.Prohibited),
		effects = 0x02,
		interactive = 1,
		name_offset = 0,
		name_bytes = 3,
		description_offset = 3,
		description_bytes = 4,
		provider_offset = 7,
		provider_bytes = 8,
		source_offset = 15,
		source_bytes = 6,
		location_offset = 21,
	}
	records := [?]Command_Catalog_Record{record}
	header := Command_Catalog_Header_Record {
		schema_version = COMMAND_CATALOG_SCHEMA_VERSION,
		registry_generation = 17,
		catalog_generation = 1,
		command_count = 1,
		text_bytes = u64(len(text)),
	}
	header.record_bytes, _ = command_catalog_record_bytes(header.command_count, header.text_bytes)
	failure := command_catalog_records_validate(header, records[:], text, 17)
	testing.expect_value(t, failure.code, Command_Catalog_Record_Failure_Code.None)

	ksawery_extension := records
	ksawery_extension[0].dispatch_class = u64(Command_Dispatch_Class.Ksawery_Extension)
	failure = command_catalog_records_validate(header, ksawery_extension[:], text, 17)
	testing.expect_value(t, failure.code, Command_Catalog_Record_Failure_Code.None)

	unknown_effect := records
	unknown_effect[0].effects = 0x10
	failure = command_catalog_records_validate(header, unknown_effect[:], text, 17)
	testing.expect_value(t, failure.code, Command_Catalog_Record_Failure_Code.Unknown_Effect)

	stale := header
	stale.registry_generation = 18
	failure = command_catalog_records_validate(stale, records[:], text, 17)
	testing.expect_value(t, failure.code, Command_Catalog_Record_Failure_Code.Stale_Generation)

	duplicates := [?]Command_Catalog_Record{record, record}
	duplicate_header := header
	duplicate_header.command_count = 2
	duplicate_header.record_bytes, _ = command_catalog_record_bytes(
		duplicate_header.command_count,
		duplicate_header.text_bytes,
	)
	failure = command_catalog_records_validate(duplicate_header, duplicates[:], text, 17)
	testing.expect_value(t, failure.code, Command_Catalog_Record_Failure_Code.Duplicate_Command)

	_, oversized := command_catalog_record_bytes(MAX_COMMAND_CATALOG_COMMANDS + 1, 0)
	testing.expect_value(t, oversized.code, Command_Catalog_Record_Failure_Code.Command_Limit)
}
