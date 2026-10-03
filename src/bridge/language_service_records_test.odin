// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../language_service"
import "core:testing"

/* Verifies language-service ABI records remain fixed, pointer-free, and bounded. */
@(test)
language_service_layout_is_bounded :: proc(t: ^testing.T) {
	testing.expect(t, language_service_record_layout_is_valid())

	proposal_bytes, proposal_ok := language_service_definition_record_bytes(
		4,
		2,
		3,
		2,
		4 * 1_024,
		8 * 1_024,
	)
	testing.expect(t, proposal_ok)
	testing.expect_value(
		t,
		proposal_bytes,
		LANGUAGE_SERVICE_DEFINITION_HEADER_BYTES +
			11 * LANGUAGE_SERVICE_TEXT_RECORD_BYTES +
			3 * LANGUAGE_SERVICE_OPTION_RECORD_BYTES +
			12 * 1_024,
	)

	_, proposal_ok = language_service_definition_record_bytes(
		u64(language_service.DEFAULT_LIMITS.arguments) + 1, 0, 0, 0, 0, 0,
	)
	testing.expect(t, !proposal_ok)
	_, proposal_ok = language_service_definition_record_bytes(
		0, 0, MAX_LANGUAGE_SERVICE_OPTIONS + 1, 0, 0, 0,
	)
	testing.expect(t, !proposal_ok)

	inspection_bytes, inspection_ok := language_service_inspection_record_bytes(
		2,
		3,
		1,
		1,
		6,
		4,
		1,
		2 * 1_024,
	)
	testing.expect(t, inspection_ok)
	testing.expect_value(
		t,
		inspection_bytes,
		LANGUAGE_SERVICE_INSPECTION_HEADER_BYTES +
			2 * LANGUAGE_SERVICE_PROVIDER_RECORD_BYTES +
			3 * LANGUAGE_SERVICE_DEFINITION_RECORD_BYTES +
			LANGUAGE_SERVICE_SESSION_RECORD_BYTES +
			LANGUAGE_SERVICE_TRUST_ROOT_RECORD_BYTES +
			6 * LANGUAGE_SERVICE_TEXT_RECORD_BYTES +
			4 * LANGUAGE_SERVICE_OPTION_RECORD_BYTES +
			LANGUAGE_SERVICE_FAILURE_RECORD_BYTES + 2 * 1_024,
	)

	_, inspection_ok = language_service_inspection_record_bytes(
		u64(language_service.DEFAULT_LIMITS.providers) + 1, 0, 0, 0, 0, 0, 0, 0,
	)
	testing.expect(t, !inspection_ok)
	_, inspection_ok = language_service_inspection_record_bytes(
		0, 0, 0, 0, 0, 0, MAX_LANGUAGE_SERVICE_INSPECTION_FAILURES + 1, 0,
	)
	testing.expect(t, !inspection_ok)
}
