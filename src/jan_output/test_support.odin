// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "../language"

@(private = "package")
output_test_scope :: proc() -> Scope {
	language_name: language.Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := language.Jan_Configuration_Identity {generation = 1}
	configuration.digest[0] = 1
	analysis := language.Jan_Analysis_Scope {
		buffer_id = 3,
		document_id = 5,
		has_document = true,
		source_revision = 7,
		language = {id = 2, generation = 1, name = language_name},
		provider = {registry_id = 2, language_id = 2, provider_id = 1, provider_generation = 1},
		selection_generation = 11,
		parser_generation = 13,
		grammar_generation = 17,
		configuration = configuration,
		baseline = language.jan_factory_baseline(),
		analysis_generation = 19,
	}
	return {
		analysis = analysis,
		source_bytes = 128,
		configuration_generation = 23,
		backend_generation = 29,
		filter_generation = 31,
		provider_generation = 37,
	}
}

@(private = "package")
output_test_selection :: proc(scope: Scope, kind := Export_Scope_Kind.Document) -> Selection {
	return {kind = kind, range = {scope = scope.analysis, start = 0, end = 128}}
}
