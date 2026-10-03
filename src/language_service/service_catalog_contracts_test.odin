// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"
import "core:testing"

/* Verifies catalog records preserve explicit provenance, scope, and policy. */
@(test)
service_catalog_records_keep_resolution_authority_explicit :: proc(t: ^testing.T) {
	odin := language.Language_Identity {
		id = 1,
		generation = 3,
		name = {length = 4},
	}
	definition := Service_Definition_Descriptor {
		definition = {
			registry = {id = 5, generation = 7},
			id = 11,
			generation = 13,
		},
		identity = {length = 3},
		languages = {0 = {id = odin.id, generation = odin.generation}},
		language_count = 1,
		scope = {source = .Factory, kind = .Global},
		source_generation = 17,
		policy = {enabled = true, default_selection = true},
		provenance = {length = 12},
	}

	testing.expect_value(t, definition.languages[0].id, odin.id)
	testing.expect_value(t, definition.languages[0].generation, odin.generation)
	testing.expect_value(t, definition.scope.source, Service_Contribution_Source.Factory)
	testing.expect_value(t, definition.scope.kind, Service_Scope_Kind.Global)
	testing.expect(t, definition.policy.enabled)
	testing.expect(t, definition.policy.default_selection)
}

/* Verifies a resolution trace distinguishes absence from explicit invalidity. */
@(test)
service_catalog_trace_preserves_selection_outcome :: proc(t: ^testing.T) {
	absent := Service_Resolution_Trace {
		catalog_id = 19,
		catalog_generation = 23,
		kind = .None,
		state = .Absent,
	}
	invalid := absent
	invalid.state = .Invalid_Explicit_Selection
	invalid.kind = .Explicit_Project

	testing.expect_value(t, absent.state, Service_Resolution_State.Absent)
	testing.expect_value(t, invalid.state, Service_Resolution_State.Invalid_Explicit_Selection)
	testing.expect_value(t, invalid.kind, Service_Selection_Kind.Explicit_Project)
}
