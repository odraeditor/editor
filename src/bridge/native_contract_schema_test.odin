// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import endian "core:encoding/endian"
import "core:testing"

@(test)
/* Verifies the encoded header and size. */
native_contract_schema_is_complete_and_versioned :: proc(t: ^testing.T) {
	bytes := make([]u8, int(native_contract_schema_bytes()), context.temp_allocator)
	defer delete(bytes, context.temp_allocator)
	testing.expect(t, native_contract_schema_encode(bytes))

	magic, magic_ok := endian.get_u64(bytes, .Little)
	version, version_ok := endian.get_u64(bytes[8:], .Little)
	header_bytes, header_ok := endian.get_u64(bytes[16:], .Little)
	entry_count, count_ok := endian.get_u64(bytes[24:], .Little)
	testing.expect(t, magic_ok && version_ok && header_ok && count_ok)
	testing.expect_value(t, magic, NATIVE_CONTRACT_SCHEMA_MAGIC)
	testing.expect_value(t, version, NATIVE_CONTRACT_SCHEMA_VERSION)
	testing.expect_value(t, header_bytes, NATIVE_CONTRACT_SCHEMA_HEADER_BYTES)
	testing.expect_value(t, entry_count, u64(len(NATIVE_CONTRACT_SCHEMA_ENTRIES)))
	testing.expect_value(
		t,
		u64(len(bytes)),
		NATIVE_CONTRACT_SCHEMA_HEADER_BYTES +
			entry_count * NATIVE_CONTRACT_SCHEMA_ENTRY_BYTES,
	)
}

@(test)
/* Verifies exact destination admission. */
native_contract_schema_rejects_truncated_storage :: proc(t: ^testing.T) {
	bytes := make([]u8, int(native_contract_schema_bytes() - 1), context.temp_allocator)
	defer delete(bytes, context.temp_allocator)
	testing.expect(t, !native_contract_schema_encode(bytes))
}

/* Verifies the language-service schema publishes every fixed record family. */
@(test)
schema_includes_language_service :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Language_Service do continue
		found += 1
	}
	testing.expect_value(t, found, 54)
}

/* Verifies the result-provider schema publishes every copied contract value. */
@(test)
native_contract_schema_includes_result_records :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Result do continue
		found += 1
	}
	testing.expect_value(t, found, 21)
}

/* Verifies the programmable Status Bar schema publishes every copied contract value. */
@(test)
schema_includes_status_bar :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Status_Bar do continue
		found += 1
	}
	testing.expect_value(t, found, 69)
}

/* Verifies the programmable terminal schema publishes every copied contract value. */
@(test)
schema_includes_terminal :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Terminal do continue
		found += 1
	}
	testing.expect_value(t, found, 31)
}

/* Verifies the Jan language schema publishes every copied contract value. */
@(test)
schema_includes_jan_language :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Jan_Language do continue
		found += 1
	}
	testing.expect_value(t, found, 19)
}

/* Verifies the Jan Planning schema publishes every copied contract value. */
@(test)
schema_includes_jan_planning :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Jan_Planning do continue
		found += 1
	}
	testing.expect_value(t, found, 18)
}

/* Verifies the Jan Computation schema publishes every copied contract value. */
@(test)
schema_includes_jan_computation :: proc(t: ^testing.T) {
	found := 0
	for entry in NATIVE_CONTRACT_SCHEMA_ENTRIES {
		if entry.concern != .Jan_Computation do continue
		found += 1
	}
	testing.expect_value(t, found, 16)
}
