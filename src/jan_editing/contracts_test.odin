// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "core:testing"

/* Verifies the accepted resource policy and each one-unit subordinate overflow. */
@(test)
structured_editing_contracts_fix_resource_limits :: proc(t: ^testing.T) {
	testing.expect(t, limits_are_valid(DEFAULT_LIMITS))
	invalid := DEFAULT_LIMITS
	invalid.hidden_ranges = MAX_HIDDEN_RANGES + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.table_cells = MAX_TABLE_CELLS + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.completion_candidates = MAX_COMPLETION_CANDIDATES + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.preview_cache_bytes = MAX_PREVIEW_CACHE_BYTES + 1
	testing.expect(t, !limits_are_valid(invalid))
	invalid = DEFAULT_LIMITS
	invalid.preview_cache_bytes = invalid.preview_result_bytes - 1
	testing.expect(t, !limits_are_valid(invalid))
}

/* Verifies the complete Stage 2 family inventory is factory-native and available. */
@(test)
structured_editing_contracts_publish_stage_availability :: proc(t: ^testing.T) {
	records := structured_editing_availability()
	seen: bit_set[Capability]
	for record in records {
		testing.expect(t, record.capability > .Invalid)
		testing.expect(t, record.capability <= .Contextual_Editing)
		testing.expect_value(t, record.class, language.Jan_Availability_Class.Factory_Native)
		testing.expect(t, record.available)
		testing.expect(t, record.capability not_in seen)
		seen += {record.capability}
	}
	testing.expect(t, .Visibility in seen)
	testing.expect(t, .Structural_Editing in seen)
	testing.expect(t, .List_Editing in seen)
	testing.expect(t, .Table_Editing in seen)
	testing.expect(t, .Contextual_Editing in seen)
}

/* Verifies exact scope and target checks reject stale or ownerless values. */
@(test)
structured_editing_contracts_require_exact_targets :: proc(t: ^testing.T) {
	scope := editing_test_scope(7, 11)
	testing.expect(t, scope_is_valid(scope))
	target := Target {
		kind = .Heading,
		node_id = 3,
		range = {scope = scope.analysis, start = 0, end = 8},
	}
	testing.expect(t, target_is_valid(target, scope, 12))
	target.node_id = 0
	testing.expect(t, !target_is_valid(target, scope, 12))
	target.node_id = 3
	target.range.scope.source_revision += 1
	testing.expect(t, !target_is_valid(target, scope, 12))
}

@(private)
editing_test_scope :: proc(buffer_id: editor.Buffer_ID, revision: editor.Revision) -> Scope {
	language_name: language.Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := language.Jan_Configuration_Identity{generation = 1}
	configuration.digest[0] = 1
	return {
		analysis = {
			buffer_id = buffer_id,
			source_revision = revision,
			language = {id = 2, generation = 1, name = language_name},
			provider = {
				registry_id = 2,
				language_id = 2,
				provider_id = 1,
				provider_generation = 1,
			},
			selection_generation = 1,
			parser_generation = 1,
			grammar_generation = 1,
			configuration = configuration,
			baseline = language.jan_factory_baseline(),
			analysis_generation = 1,
		},
		view_handle = {registry_id = 1, view_id = 1, generation = 1},
		view_state_generation = 1,
		configuration_generation = 1,
		provider_generation = 1,
	}
}
