// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package indentation

import "core:encoding/endian"
import "core:testing"

/* Verifies encoded rules prepare one complete copied generation. */
@(test)
encoded_configuration_prepares_complete_generation :: proc(t: ^testing.T) {
	matcher :: "odin"
	payload: [ENCODED_HEADER_BYTES + ENCODED_RULE_BYTES + len(matcher)]u8
	configuration_test_put(payload[:], 0, ENCODED_SCHEMA_VERSION)
	configuration_test_put(payload[:], 8, 2)
	configuration_test_put(payload[:], 16, 2)
	configuration_test_put(payload[:], 24, 8)
	configuration_test_put(payload[:], 32, 1)
	record := ENCODED_HEADER_BYTES
	configuration_test_put(payload[:], record, 1)
	configuration_test_put(payload[:], record + 8, 5)
	configuration_test_put(payload[:], record + 16, 5)
	configuration_test_put(payload[:], record + 24, 0)
	configuration_test_put(payload[:], record + 32, 1)
	configuration_test_put(payload[:], record + 40, 4)
	configuration_test_put(payload[:], record + 48, 8)
	configuration_test_put(payload[:], record + 56, 7)
	configuration_test_put(payload[:], record + 64, len(matcher))
	copy(payload[record + ENCODED_RULE_BYTES:], matcher)

	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	candidate: Registry
	prepared, _ := registry_prepare_encoded(&registry, payload[:], 2, &candidate)
	testing.expect(t, prepared)
	if !prepared do return
	effective, resolved, _ := resolve(
		&candidate,
		{
			profile_id = 1,
			buffer_id = 9,
			language = matcher,
		},
	)
	testing.expect(t, resolved)
	testing.expect_value(t, effective.scope, Scope.Language)
	testing.expect_value(t, effective.policy.representation, Representation.Tabs)
	testing.expect_value(t, effective.policy.indent_width, u16(4))
	testing.expect_value(t, effective.policy.display_tab_width, u16(8))
}

/* Verifies malformed encoded generations preserve the confirmed registry. */
@(test)
encoded_configuration_rejection_preserves_confirmed_generation :: proc(t: ^testing.T) {
	payload: [ENCODED_HEADER_BYTES]u8
	configuration_test_put(payload[:], 0, ENCODED_SCHEMA_VERSION)
	configuration_test_put(payload[:], 8, 2)
	configuration_test_put(payload[:], 16, 4)
	configuration_test_put(payload[:], 24, 4)
	configuration_test_put(payload[:], 32, 1)
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	before := registry
	candidate: Registry
	prepared, failure := registry_prepare_encoded(&registry, payload[:], 2, &candidate)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Encoding)
	testing.expect_value(t, registry, before)
}

@(private)
configuration_test_put :: proc(bytes: []u8, offset: int, value: u64) {
	written := endian.put_u64(bytes[offset:], .Little, value)
	assert(written)
}
