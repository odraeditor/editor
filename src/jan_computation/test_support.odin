// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "../editor"
import "../language"

@(private)
computation_test_scope :: proc(revision: editor.Revision = 7) -> Scope {
	language_name: language.Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := language.Jan_Configuration_Identity{generation = 1}
	configuration.digest[0] = 1
	return {
		analysis = {
			buffer_id = 3,
			source_revision = revision,
			language = {id = 2, generation = 1, name = language_name},
			provider = {
				registry_id = 2,
				language_id = 2,
				provider_id = 1,
				provider_generation = 1,
			},
			selection_generation = 11,
			parser_generation = 13,
			grammar_generation = 17,
			configuration = configuration,
			baseline = language.jan_factory_baseline(),
			analysis_generation = 19,
		},
		source_bytes = 128,
		configuration_generation = 23,
		adapter_generation = 29,
		policy_generation = 31,
	}
}

@(private)
computation_test_target :: proc(scope: Scope) -> Semantic_Target {
	return {
		node_id = 5,
		kind = .Source_Block,
		range = {scope = scope.analysis, start = 8, end = 24},
	}
}
